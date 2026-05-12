# Non-parametric bootstrap model for multi-stage recovery prediction.
# Stage ratios are computed per batch with denominator caps applied. Per-batch
# joint sampling preserves within-batch covariance. Exponential time decay
# weights recent batches higher to handle non-stationarity in stage 3 recovery.
# Set decay_tau_days = Inf to disable decay and recover uniform weighting.

new_recovery_model <- function(primitives,
                               reference_date  = Sys.Date(),
                               decay_tau_days  = 180,
                               cap_input       = 5e9,
                               cap_stage1      = 3e9,
                               cap_stage2      = 1e9,
                               upstream_hash   = NA_character_,
                               trained_on      = Sys.time()) {

  required <- c("batch_id", "mfg_date", "input_cells",
                "stage1_output", "stage2_output", "stage3_output")
  stopifnot(is.data.frame(primitives),
            all(required %in% names(primitives)))

  pool <- primitives
  if (nrow(pool) < 10) {
    stop("Not enough batches to train (need >= 10).")
  }

  stage1_denom <- pmin(pool$input_cells,   cap_input)
  stage2_denom <- pmin(pool$stage1_output, cap_stage1)
  stage3_denom <- pmin(pool$stage2_output, cap_stage2)

  r1 <- pool$stage1_output / stage1_denom
  r2 <- pool$stage2_output / stage2_denom
  r3 <- pool$stage3_output / stage3_denom

  ages_days <- as.numeric(reference_date - pool$mfg_date)
  if (is.finite(decay_tau_days)) {
    raw_weights <- exp(-ages_days / decay_tau_days)
  } else {
    raw_weights <- rep(1, length(ages_days))
  }
  weights   <- raw_weights / sum(raw_weights)
  decay_ess <- 1 / sum(weights^2)

  structure(
    list(
      r1             = r1,
      r2             = r2,
      r3             = r3,
      weights        = weights,
      caps           = list(input = cap_input,
                            stage1 = cap_stage1,
                            stage2 = cap_stage2),
      reference_date = reference_date,
      decay_tau_days = decay_tau_days,
      decay_ess      = decay_ess,
      n_pool         = nrow(pool),
      upstream_hash  = upstream_hash,
      trained_on     = trained_on
    ),
    class = "recovery_model"
  )
}

print.recovery_model <- function(x, ...) {
  cat("<recovery_model>\n")
  cat("  pool size       :", x$n_pool, "batches\n")
  cat("  decay tau       :", x$decay_tau_days, "days\n")
  cat("  effective N     :", round(x$decay_ess, 1), "\n")
  cat("  reference date  :", format(x$reference_date), "\n")
  cat("  trained on      :", format(x$trained_on), "\n")
  invisible(x)
}

# Per-batch joint sampling: draws row indices with replacement weighted by
# recency, then takes the matched (r1, r2, r3) triple for each draw. This
# preserves within-batch covariance among the three stage ratios.
.joint_draws <- function(model, n_compound) {
  idx <- sample.int(model$n_pool, size = n_compound,
                    replace = TRUE, prob = model$weights)
  list(r1 = model$r1[idx], r2 = model$r2[idx], r3 = model$r3[idx])
}

.chain_yield <- function(input_cells, r1, r2, r3, caps) {
  s1 <- pmin(pmin(input_cells, caps$input) * r1, caps$stage1)
  s2 <- pmin(s1 * r2,                           caps$stage2)
  s2 * r3
}

predict_yield <- function(model, input_cells, n_compound = 10000,
                          probs = c(0.05, 0.25, 0.5, 0.75, 0.95)) {

  stopifnot(inherits(model, "recovery_model"))
  draws <- .joint_draws(model, n_compound)

  bands <- vapply(input_cells, function(x) {
    quantile(.chain_yield(x, draws$r1, draws$r2, draws$r3, model$caps),
             probs = probs, names = FALSE)
  }, numeric(length(probs)))

  out <- as.data.frame(t(bands))
  names(out) <- paste0("q", sprintf("%02d", round(probs * 100)))
  data.frame(input_cells = input_cells, out)
}

