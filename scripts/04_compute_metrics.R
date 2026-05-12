# 1. Setup ----
library(here)
library(pins)

board <- board_folder(here::here("data", "pins"), versioned = TRUE)

# 2. Load inputs ----
primitives <- pin_read(board, "recovery_primitives")
history    <- pin_read(board, "predictions_history")

current_model_hash <- history$model_pin_hash[which.max(history$scored_at)]
latest_preds <- history[history$model_pin_hash == current_model_hash, ]

# 3. Calibration on all batches ----
calibration <- merge(
  latest_preds,
  primitives[, c("batch_id", "stage3_output")],
  by = "batch_id"
)
calibration$in_50 <- with(calibration, stage3_output >= q25 & stage3_output <= q75)
calibration$in_95 <- with(calibration, stage3_output >= q05 & stage3_output <= q95)
calibration$ape   <- abs(calibration$stage3_output - calibration$q50) /
                     calibration$stage3_output

# 4. Drift via KS test on recent (last 90 days) vs baseline ----
cutoff   <- max(primitives$mfg_date) - 90
recent   <- primitives[primitives$mfg_date >= cutoff, ]
baseline <- primitives[primitives$mfg_date <  cutoff, ]

vars <- c("input_cells", "stage1_output", "stage2_output", "stage3_output")
drift <- do.call(rbind, lapply(vars, function(v) {
  k <- suppressWarnings(ks.test(recent[[v]], baseline[[v]]))
  data.frame(variable = v,
             D = unname(k$statistic),
             p_value = k$p.value)
}))

# 5. Assemble row ----
metrics_row <- data.frame(
  evaluation_date  = Sys.Date(),
  model_pin_hash   = current_model_hash,
  n_calibration    = nrow(calibration),
  coverage_50      = mean(calibration$in_50),
  coverage_95      = mean(calibration$in_95),
  mape             = mean(calibration$ape),
  drift_input_D    = drift$D[drift$variable == "input_cells"],
  drift_input_p    = drift$p_value[drift$variable == "input_cells"],
  drift_stage1_D   = drift$D[drift$variable == "stage1_output"],
  drift_stage1_p   = drift$p_value[drift$variable == "stage1_output"],
  drift_stage2_D   = drift$D[drift$variable == "stage2_output"],
  drift_stage2_p   = drift$p_value[drift$variable == "stage2_output"],
  drift_stage3_D   = drift$D[drift$variable == "stage3_output"],
  drift_stage3_p   = drift$p_value[drift$variable == "stage3_output"],
  stringsAsFactors = FALSE
)

# 6. Upsert on (evaluation_date, model_pin_hash) ----
existing <- tryCatch(pin_read(board, "model_metrics"), error = function(e) NULL)

combined <- if (is.null(existing)) {
  metrics_row
} else {
  key_match <- existing$evaluation_date == metrics_row$evaluation_date &
               existing$model_pin_hash  == metrics_row$model_pin_hash
  rbind(existing[!key_match, ], metrics_row)
}

pin_write(
  board,
  combined,
  name        = "model_metrics",
  type        = "rds",
  title       = "Calibration and drift metrics over time",
  description = "One row per (evaluation_date, model_pin_hash)."
)

cat("Metrics for", format(metrics_row$evaluation_date),
    "model", current_model_hash, "\n",
    "  coverage 50%:", sprintf("%.3f", metrics_row$coverage_50), "(target 0.50)\n",
    "  coverage 95%:", sprintf("%.3f", metrics_row$coverage_95), "(target 0.95)\n",
    "  MAPE        :", sprintf("%.3f", metrics_row$mape), "\n",
    "  drift stage3:", sprintf("D=%.3f p=%.4f", metrics_row$drift_stage3_D,
                                                metrics_row$drift_stage3_p), "\n")
