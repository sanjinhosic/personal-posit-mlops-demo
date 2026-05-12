source(testthat::test_path("..", "..", "R", "simulator.R"))
source(testthat::test_path("..", "..", "R", "recovery_model.R"))

train_data <- generate_recovery_batches(n_batches = 200)

test_that("model returns a recovery_model object with required slots", {
  m <- new_recovery_model(train_data, reference_date = max(train_data$mfg_date))
  expect_s3_class(m, "recovery_model")
  expect_equal(m$n_pool, 200)
  expect_true(all(c("r1", "r2", "r3", "weights", "caps",
                    "reference_date", "decay_tau_days", "decay_ess",
                    "upstream_hash", "trained_on") %in% names(m)))
})

test_that("decay shrinks effective sample size below pool size", {
  m <- new_recovery_model(train_data, reference_date = max(train_data$mfg_date),
                          decay_tau_days = 90)
  expect_lt(m$decay_ess, m$n_pool)
})

test_that("infinite tau recovers uniform weights and full ESS", {
  m <- new_recovery_model(train_data, reference_date = max(train_data$mfg_date),
                          decay_tau_days = Inf)
  expect_equal(m$decay_ess, m$n_pool)
})

test_that("training fails with too few batches", {
  expect_error(
    new_recovery_model(train_data[1:5, ]),
    "Not enough batches"
  )
})

test_that("predict_yield quantiles are monotonic per row", {
  m   <- new_recovery_model(train_data, reference_date = max(train_data$mfg_date))
  out <- predict_yield(m, c(1e9, 2e9, 3e9), n_compound = 3000)
  expect_true(all(out$q05 <= out$q25))
  expect_true(all(out$q25 <= out$q50))
  expect_true(all(out$q50 <= out$q75))
  expect_true(all(out$q75 <= out$q95))
})

test_that("predicted median yield increases with input cells (in unsaturated range)", {
  m   <- new_recovery_model(train_data, reference_date = max(train_data$mfg_date))
  out <- predict_yield(m, c(5e8, 1.5e9, 2.5e9), n_compound = 3000)
  expect_lt(out$q50[1], out$q50[2])
  expect_lt(out$q50[2], out$q50[3])
})

test_that("yield saturates near the stage caps for very large inputs", {
  m    <- new_recovery_model(train_data, reference_date = max(train_data$mfg_date))
  high <- predict_yield(m, c(5e9, 1e10), n_compound = 3000)
  expect_lt(abs(high$q95[1] - high$q95[2]) / high$q95[1], 0.1)
})

test_that("predict_termination is no longer exported", {
  expect_false(exists("predict_termination", mode = "function"))
})
