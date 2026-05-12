source(testthat::test_path("..", "..", "R", "simulator.R"))

test_that("simulator produces the documented schema", {
  df <- generate_recovery_batches(n_batches = 50)
  required <- c("batch_id", "collection_date", "input_cells",
                "stage1_output", "stage2_output", "stage3_output",
                "donor_age", "equipment_id", "process_version")
  expect_true(all(required %in% names(df)))
  expect_equal(nrow(df), 50)
  expect_false("outcome_status" %in% names(df))
})

test_that("simulator is reproducible from seed", {
  a <- generate_recovery_batches(n_batches = 20, seed = 123)
  b <- generate_recovery_batches(n_batches = 20, seed = 123)
  expect_identical(a, b)
})

test_that("stage outputs respect denominator caps", {
  df <- generate_recovery_batches(n_batches = 500)
  expect_true(all(df$stage1_output <= 3e9))
  expect_true(all(df$stage2_output <= 1e9))
})

test_that("drift_per_year shifts stage 3 mean upward", {
  df_drift <- generate_recovery_batches(n_batches = 1000, drift_per_year = 0.1)
  early <- df_drift[df_drift$collection_date < as.Date("2024-01-01"), ]
  late  <- df_drift[df_drift$collection_date >= as.Date("2024-01-01"), ]
  expect_gt(median(late$stage3_output), median(early$stage3_output))
})
