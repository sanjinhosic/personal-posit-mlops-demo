# Generates a historical metrics trail by re-training and re-evaluating at a
# series of past evaluation dates. Each row models the world as of that date:
# the model sees only batches collected by then, and calibration plus KS drift
# are computed within that window. Result: a populated time series that the
# monitoring dashboard can render as a trend.

# 1. Setup ----
library(here)
library(pins)
library(digest)

source(here::here("R", "recovery_model.R"))

board      <- board_folder(here::here("data", "pins"), versioned = TRUE)
primitives <- pin_read(board, "recovery_primitives")

# 2. Evaluation schedule ----
start_eval <- min(primitives$collection_date) + 240
end_eval   <- max(primitives$collection_date)
eval_dates <- seq.Date(start_eval, end_eval, by = "6 weeks")

# 3. Compute one metrics row per evaluation date ----
metrics_rows <- lapply(eval_dates, function(eval_date) {
  past <- primitives[primitives$collection_date <= eval_date, ]
  if (nrow(past) < 50) return(NULL)

  m    <- new_recovery_model(past, reference_date = eval_date)
  hash <- substr(digest(m, algo = "sha256"), 1, 12)

  preds <- predict_yield(m, past$input_cells, n_compound = 3000)
  in_50 <- past$stage3_output >= preds$q25 & past$stage3_output <= preds$q75
  in_95 <- past$stage3_output >= preds$q05 & past$stage3_output <= preds$q95
  ape   <- abs(past$stage3_output - preds$q50) / past$stage3_output

  cutoff   <- eval_date - 90
  recent   <- past[past$collection_date >= cutoff, ]
  baseline <- past[past$collection_date <  cutoff, ]
  if (nrow(recent) < 5 || nrow(baseline) < 5) return(NULL)

  vars  <- c("input_cells", "stage1_output", "stage2_output", "stage3_output")
  drift <- vapply(vars, function(v) {
    k <- suppressWarnings(ks.test(recent[[v]], baseline[[v]]))
    c(D = unname(k$statistic), p = k$p.value)
  }, numeric(2))

  data.frame(
    evaluation_date  = eval_date,
    model_pin_hash   = hash,
    n_calibration    = nrow(past),
    coverage_50      = mean(in_50),
    coverage_95      = mean(in_95),
    mape             = mean(ape),
    drift_input_D    = drift["D", "input_cells"],
    drift_input_p    = drift["p", "input_cells"],
    drift_stage1_D   = drift["D", "stage1_output"],
    drift_stage1_p   = drift["p", "stage1_output"],
    drift_stage2_D   = drift["D", "stage2_output"],
    drift_stage2_p   = drift["p", "stage2_output"],
    drift_stage3_D   = drift["D", "stage3_output"],
    drift_stage3_p   = drift["p", "stage3_output"],
    stringsAsFactors = FALSE
  )
})

metrics_rows <- do.call(rbind, metrics_rows)

# 4. Upsert into existing metrics ----
existing <- tryCatch(pin_read(board, "model_metrics"), error = function(e) NULL)

if (!is.null(existing)) {
  key_existing <- paste(existing$evaluation_date, existing$model_pin_hash)
  key_new      <- paste(metrics_rows$evaluation_date, metrics_rows$model_pin_hash)
  combined     <- rbind(existing[!key_existing %in% key_new, ], metrics_rows)
} else {
  combined <- metrics_rows
}
combined <- combined[order(as.Date(combined$evaluation_date)), ]

pin_write(
  board,
  combined,
  name        = "model_metrics",
  type        = "rds",
  title       = "Calibration and drift metrics over time",
  description = "Backfilled historical evaluations plus latest weekly metrics."
)

cat("Wrote", nrow(metrics_rows), "historical metric rows;",
    "total", nrow(combined), "rows now.\n")
