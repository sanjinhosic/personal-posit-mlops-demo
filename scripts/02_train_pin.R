# 1. Setup ----
library(here)
library(pins)
library(digest)

source(here::here("R", "recovery_model.R"))

board <- board_folder(here::here("data", "pins"), versioned = TRUE)

# 2. Read upstream pin ----
primitives    <- pin_read(board, "recovery_primitives")
upstream_hash <- substr(digest(primitives, algo = "sha256"), 1, 12)

# 3. Train ----
model <- new_recovery_model(
  primitives,
  reference_date = max(primitives$mfg_date),
  decay_tau_days = 180,
  upstream_hash  = upstream_hash
)

# 4. Publish ----
pin_write(
  board,
  model,
  name        = "recovery_model",
  type        = "rds",
  title       = "Multi-stage bootstrap recovery model",
  description = sprintf("Trained on %d completed batches; decay tau %d days; ESS %.1f.",
                        model$n_pool, model$decay_tau_days, model$decay_ess),
  metadata    = list(
    n_pool         = model$n_pool,
    decay_tau_days = model$decay_tau_days,
    decay_ess      = round(model$decay_ess, 2),
    reference_date = format(model$reference_date),
    upstream_hash  = model$upstream_hash,
    trained_on     = format(model$trained_on)
  )
)

cat("Wrote recovery_model: ESS",
    round(model$decay_ess, 1), "of", model$n_pool,
    "(upstream", upstream_hash, ")\n")
