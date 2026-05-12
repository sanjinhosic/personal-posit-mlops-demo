library(testthat)

testthat::test_dir(
  here::here("tests", "testthat"),
  reporter = "summary"
)
