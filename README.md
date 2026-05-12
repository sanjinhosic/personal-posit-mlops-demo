# personal-posit-mlops-demo

End-to-end ML deployment demo mirroring a production Posit Connect architecture, built on a fully public stack: Posit Connect Cloud for Shiny apps, GitHub Actions for scheduled training and scoring, GitHub-hosted pins for versioned model artifacts. Uses a synthetic multi-stage bioprocess recovery dataset to demonstrate idempotent batch scoring, time-decay sample weighting, drift monitoring, and calibration tracking.

## Architecture

```
synthetic recovery generator  (R/simulator.R)
              |
              v
      recovery_primitives  (pins board_folder, committed to data/pins/)
              |
     +--------+--------+
     |                 |
     v                 v
  train.qmd        score.qmd
  (weekly,         (daily,
   GH Actions)      GH Actions)
     |                 |
     v                 v
recovery_model   predictions_history
    (pin)              (pin)
     |                 |
     +------> metrics.qmd
              (weekly, GH Actions)
                     |
                     v
             model_metrics  (pin)
                     |
       +-------------+-------------+
       v                           v
recovery_predictor        recovery_monitoring
(Shiny on Posit            (Shiny on Posit
 Connect Cloud)             Connect Cloud)

   reads pins via pins::board_url() from raw.githubusercontent.com
```

## Lifecycle stages

| Stage | Artifact | Hosted at | Trigger |
|-------|----------|-----------|---------|
| Generate | `recovery_primitives` pin | `data/pins/` in this repo | GH Actions weekly or manual |
| Train | `recovery_model` pin | `data/pins/` in this repo | GH Actions weekly cron |
| Score | `predictions_history` pin | `data/pins/` in this repo | GH Actions daily cron |
| Metrics | `model_metrics` pin | `data/pins/` in this repo | GH Actions weekly cron |
| Serve | `recovery_predictor` Shiny | Posit Connect Cloud | Auto-deploy on commit |
| Monitor | `recovery_monitoring` Shiny | Posit Connect Cloud | Auto-deploy on commit |

Scheduled GH Actions runners execute the train, score, and metrics scripts, commit updated pin files back to the repo, and push. Shiny apps on Connect Cloud read those pins via `pins::board_url()` from `raw.githubusercontent.com`, so they always see the latest committed artifact.

## Generator output schema

The simulator publishes `recovery_primitives` with:

| Column | Type | Description |
|--------|------|-------------|
| batch_id | character | Unique per batch |
| mfg_date | Date | Manufacturing date; spans 2 years; uniform sampling |
| input_cells | numeric | Stage 0 input; lognormal; cap 5e9 |
| stage1_output | numeric | After step 1; cap 3e9 |
| stage2_output | numeric | After step 2; cap 1e9 |
| stage3_output | numeric | Final yield |

## Drift design

The simulator shifts the stage 3 recovery mean upward by 4 percentage points per simulated year, with stages 1 and 2 stationary. Over a 2-year span this drives median yield from 4.7e8 to 5.3e8. This non-stationarity is what time-decay weighting in training compensates for, and what KS drift tests in metrics surface to the monitoring dashboard. Reproducible via `set.seed(42)`.

## Patterns showcased

1. Pinned model artifacts with metadata (upstream hash, decay params, effective sample size)
2. Idempotent batch scoring via anti-join on `(batch_id, model_pin_hash)`
3. Time-decay sample weighting for non-stationary distributions
4. Multi-stage chain prediction with saturation caps
5. Quarto-as-pipeline (code plus audit-trail HTML in one artifact)
6. Rolling KS drift tests and PIT calibration in a live dashboard
7. Graceful degradation when optional pins are missing
8. CI-driven scheduling via GitHub Actions as a stand-in for Connect schedules

## Repository layout (target)

```
personal-posit-mlops-demo/
|-- R/
|   |-- simulator.R                # multi-stage recovery generator
|   |-- recovery_model.R           # constructor + predict functions
|-- scripts/
|   |-- 01_generate_primitives.R   # invokes simulator, writes primitives pin
|   |-- 02_train_pin.R             # local equivalent of GH Actions training job
|   |-- 03_score_batches.R         # local equivalent of GH Actions scoring job
|   |-- 04_compute_metrics.R       # local equivalent of GH Actions metrics job
|   |-- 05_backfill_metrics.R      # one-shot historical metrics backfill
|-- apps/
|   |-- recovery_predictor/        # Shiny what-if  (deployed to Connect Cloud)
|   |-- recovery_monitoring/       # Shiny monitor  (deployed to Connect Cloud)
|   |-- recovery_training/         # train.qmd      (rendered by GH Actions)
|   |-- recovery_scoring/          # score.qmd      (rendered by GH Actions)
|   |-- recovery_metrics/          # metrics.qmd    (rendered by GH Actions)
|-- .github/workflows/
|   |-- train.yml                  # weekly retrain cron
|   |-- score.yml                  # daily scoring cron
|   |-- metrics.yml                # weekly metrics cron
|   |-- test.yml                   # run testthat on every push
|-- data/pins/                     # board_folder root; committed pin artifacts
|-- tests/testthat/                # unit tests for predict functions
|-- renv.lock
|-- .gitignore
|-- README.md
|-- personal-posit-mlops-demo.Rproj
```

Currently scaffolded: everything except `renv.lock`. The full pipeline runs end-to-end locally (generate, train, score, metrics), all three Quartos render to self-contained HTML, the test suite passes (21 expectations across simulator and model), and the monitoring dashboard renders a real time-series trend after running the metrics backfill.

## Local execution (once complete)

1. `Rscript scripts/01_generate_primitives.R` writes `recovery_primitives` to `data/pins/`
2. `Rscript scripts/02_train_pin.R` trains and writes `recovery_model`
3. `Rscript scripts/03_score_batches.R` scores new batches and appends `predictions_history`
4. `Rscript scripts/04_compute_metrics.R` computes calibration plus drift and writes `model_metrics`
5. `Rscript scripts/05_backfill_metrics.R` (one-time) populates historical metrics rows so the monitoring dashboard renders a real time series
6. `Rscript tests/testthat.R` runs the unit test suite
7. `shiny::runApp("apps/recovery_predictor")` explores the what-if UI; `shiny::runApp("apps/recovery_monitoring")` for the dashboard

## Public deployment

* Shiny apps publish to Posit Connect Cloud via its GitHub integration; commit and push, Connect Cloud auto-deploys
* Scheduled jobs run as GitHub Actions cron workflows that execute the scripts above and commit updated pins back to the repo
* Quarto reports (rendered HTML from train, score, metrics) can be served from a `gh-pages` branch or published to Quarto Pub
