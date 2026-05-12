# Generates synthetic multi-stage bioprocess recovery batches.
# Stages 1 and 2 are stationary; stage 3 mean drifts upward with date,
# motivating the time-decay weighting in the downstream training step.
# A per-batch latent quality term shifts all three stage recoveries
# together, introducing realistic within-batch covariance among r1, r2, r3.

generate_recovery_batches <- function(n_batches      = 500,
                                      start_date     = as.Date("2023-01-01"),
                                      end_date       = as.Date("2024-12-31"),
                                      drift_per_year = 0.06,
                                      batch_q_sd     = 0.07,
                                      seed           = 42) {

  set.seed(seed)

  dates <- sort(sample(
    seq.Date(start_date, end_date, by = "day"),
    n_batches, replace = TRUE
  ))
  years_offset <- as.numeric(dates - mean(c(start_date, end_date))) / 365.25

  cap_input  <- 5e9
  cap_stage1 <- 3e9
  cap_stage2 <- 1e9

  input_cells <- pmin(rlnorm(n_batches, log(2e9), 0.55), cap_input)

  # Per-batch latent quality: a single random offset that shifts all
  # three stage recoveries together. Good batches recover more across
  # the whole chain; bad batches lose more at every step.
  batch_q  <- rnorm(n_batches, mean = 0, sd = batch_q_sd)

  r1_raw   <- rbeta(n_batches, 10, 6)
  r2_raw   <- rbeta(n_batches, 8, 6)
  r3_mean  <- pmin(pmax(0.75 + drift_per_year * years_offset, 0.4), 0.95)
  r3_kappa <- 60
  r3_raw   <- rbeta(n_batches, r3_mean * r3_kappa, (1 - r3_mean) * r3_kappa)

  r1 <- pmin(pmax(r1_raw + batch_q, 0.05), 0.99)
  r2 <- pmin(pmax(r2_raw + batch_q, 0.05), 0.99)
  r3 <- pmin(pmax(r3_raw + batch_q, 0.05), 0.99)

  stage1_output <- pmin(input_cells   * r1, cap_stage1)
  stage2_output <- pmin(stage1_output * r2, cap_stage2)
  stage3_output <- stage2_output * r3

  tibble::tibble(
    batch_id      = vapply(seq_len(n_batches),
                           function(i) paste0(sample(c(letters, 0:9), 12, TRUE),
                                              collapse = ""),
                           character(1)),
    mfg_date      = dates,
    input_cells   = input_cells,
    stage1_output = stage1_output,
    stage2_output = stage2_output,
    stage3_output = stage3_output
  )
}
