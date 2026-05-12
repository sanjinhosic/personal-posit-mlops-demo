# 1. Setup ----
library(here)
library(pins)
library(digest)

source(here::here("R", "recovery_model.R"))

board <- board_folder(here::here("data", "pins"), versioned = TRUE)

# 2. Load model + primitives ----
model      <- pin_read(board, "recovery_model")
primitives <- pin_read(board, "recovery_primitives")

# Hash uniquely identifies a trained model; retraining changes the hash
# and triggers re-scoring of all batches under the new model.
model_pin_hash <- substr(digest(model, algo = "sha256"), 1, 12)

# 3. Anti-join against existing history ----
history <- tryCatch(pin_read(board, "predictions_history"),
                    error = function(e) NULL)

already_scored <- if (is.null(history)) {
  character(0)
} else {
  history$batch_id[history$model_pin_hash == model_pin_hash]
}

to_score <- primitives[!primitives$batch_id %in% already_scored, ]

if (nrow(to_score) == 0) {
  cat("No new batches to score under model", model_pin_hash, "\n")
  quit("no")
}

# 4. Score ----
preds <- predict_yield(model, to_score$input_cells, n_compound = 5000)

new_history <- data.frame(
  batch_id        = to_score$batch_id,
  collection_date = to_score$collection_date,
  input_cells     = to_score$input_cells,
  q05             = preds$q05,
  q25             = preds$q25,
  q50             = preds$q50,
  q75             = preds$q75,
  q95             = preds$q95,
  model_pin_hash  = model_pin_hash,
  scored_at       = Sys.time(),
  stringsAsFactors = FALSE
)

combined <- if (is.null(history)) new_history else rbind(history, new_history)

# 5. Publish ----
pin_write(
  board,
  combined,
  name        = "predictions_history",
  type        = "rds",
  title       = "Per-batch predictions appended over time",
  description = "Idempotent on (batch_id, model_pin_hash); each retrain re-scores all batches."
)

cat("Scored", nrow(to_score), "batches under model", model_pin_hash, "\n")
