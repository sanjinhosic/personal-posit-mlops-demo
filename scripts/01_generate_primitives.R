# 1. Setup ----
library(here)
library(pins)

source(here::here("R", "simulator.R"))

board_dir <- here::here("data", "pins")
dir.create(board_dir, recursive = TRUE, showWarnings = FALSE)

# 2. Generate ----
batches <- generate_recovery_batches(n_batches = 500)

# 3. Publish ----
board <- board_folder(board_dir, versioned = TRUE)

pin_write(
  board,
  batches,
  name        = "recovery_primitives",
  type        = "rds",
  title       = "Synthetic multi-stage recovery batches",
  description = "Dated batches with three sequential recovery stages and slow stage-3 drift.",
  metadata    = list(
    n_batches      = nrow(batches),
    date_range     = format(range(batches$collection_date)),
    drift_per_year = 0.019,
    seed           = 42
  )
)

cat("Wrote", nrow(batches), "batches to recovery_primitives pin at", board_dir, "\n")
