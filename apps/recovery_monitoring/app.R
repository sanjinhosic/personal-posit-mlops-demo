library(shiny)
library(here)
library(pins)
library(ggplot2)
library(scales)

board <- board_folder(here::here("data", "pins"), versioned = TRUE)

ui <- fluidPage(
  titlePanel("Recovery Model Monitoring"),
  fluidRow(
    column(4, wellPanel(h4("Coverage 50%"), h2(textOutput("cov50")),
                        helpText("Target: 50%"))),
    column(4, wellPanel(h4("Coverage 95%"), h2(textOutput("cov95")),
                        helpText("Target: 95%"))),
    column(4, wellPanel(h4("MAPE"), h2(textOutput("mape")),
                        helpText("Median absolute % error")))
  ),
  fluidRow(
    column(6,
      h4("Calibration: predicted vs observed"),
      plotOutput("calibration_plot", height = "360px")
    ),
    column(6,
      h4("PIT histogram"),
      plotOutput("pit_plot", height = "360px"),
      helpText("Flat distribution implies good calibration.")
    )
  ),
  fluidRow(
    column(6,
      h4("Coverage over time"),
      plotOutput("coverage_trend_plot", height = "280px")
    ),
    column(6,
      h4("Stage 3 drift (KS D) over time"),
      plotOutput("drift_trend_plot", height = "280px")
    )
  ),
  fluidRow(
    column(12,
      h4("Drift (KS test: recent 90 days vs baseline)"),
      tableOutput("drift_table")
    )
  )
)

server <- function(input, output, session) {

  bundle <- reactive({
    invalidateLater(60 * 1000)
    list(
      metrics    = pin_read(board, "model_metrics"),
      history    = pin_read(board, "predictions_history"),
      primitives = pin_read(board, "recovery_primitives")
    )
  })

  latest <- reactive({
    m <- bundle()$metrics
    m[which.max(as.Date(m$evaluation_date)), ]
  })

  calibration <- reactive({
    b <- bundle()
    hash <- latest()$model_pin_hash
    preds <- b$history[b$history$model_pin_hash == hash, ]
    merge(
      preds,
      b$primitives[, c("batch_id", "stage3_output")],
      by = "batch_id"
    )
  })

  output$cov50 <- renderText(sprintf("%.1f%%", 100 * latest()$coverage_50))
  output$cov95 <- renderText(sprintf("%.1f%%", 100 * latest()$coverage_95))
  output$mape  <- renderText(sprintf("%.1f%%", 100 * latest()$mape))

  output$calibration_plot <- renderPlot({
    c <- calibration()
    ggplot(c, aes(x = q50, y = stage3_output)) +
      geom_linerange(aes(ymin = q25, ymax = q75), alpha = 0.25) +
      geom_point(alpha = 0.5, size = 1.5) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "firebrick") +
      scale_x_continuous(labels = label_number(scale = 1e-8, suffix = "e8")) +
      scale_y_continuous(labels = label_number(scale = 1e-8, suffix = "e8")) +
      labs(x = "Predicted q50", y = "Observed yield") +
      theme_minimal(base_size = 12)
  })

  output$pit_plot <- renderPlot({
    c <- calibration()
    bands <- c(0.05, 0.25, 0.5, 0.75, 0.95)
    pit <- mapply(function(y, q05, q25, q50, q75, q95) {
      qs <- c(q05, q25, q50, q75, q95)
      approx(c(qs[1] - (qs[2] - qs[1]), qs, qs[5] + (qs[5] - qs[4])),
             c(0, bands, 1), xout = y, rule = 2)$y
    }, c$stage3_output, c$q05, c$q25, c$q50, c$q75, c$q95)

    ggplot(data.frame(pit = pit), aes(x = pit)) +
      geom_histogram(bins = 10, fill = "steelblue", color = "white") +
      geom_hline(yintercept = length(pit) / 10,
                 linetype = "dashed", color = "firebrick") +
      scale_x_continuous(limits = c(0, 1)) +
      labs(x = "PIT u-value", y = "Count") +
      theme_minimal(base_size = 12)
  })

  output$drift_table <- renderTable({
    m <- latest()
    data.frame(
      Variable    = c("input_cells", "stage1_output", "stage2_output", "stage3_output"),
      `KS D`      = c(m$drift_input_D, m$drift_stage1_D, m$drift_stage2_D, m$drift_stage3_D),
      `p-value`   = c(m$drift_input_p, m$drift_stage1_p, m$drift_stage2_p, m$drift_stage3_p),
      Significant = ifelse(c(m$drift_input_p, m$drift_stage1_p,
                             m$drift_stage2_p, m$drift_stage3_p) < 0.05,
                           "yes", ""),
      check.names = FALSE
    )
  }, digits = 4)

  output$coverage_trend_plot <- renderPlot({
    m <- bundle()$metrics
    m$evaluation_date <- as.Date(m$evaluation_date)
    m <- m[order(m$evaluation_date), ]
    cov_long <- rbind(
      data.frame(date = m$evaluation_date, band = "50%", coverage = m$coverage_50),
      data.frame(date = m$evaluation_date, band = "95%", coverage = m$coverage_95)
    )
    refs <- data.frame(band = c("50%", "95%"), target = c(0.5, 0.95))
    ggplot(cov_long, aes(x = date, y = coverage, color = band)) +
      geom_hline(data = refs, aes(yintercept = target, color = band),
                 linetype = "dashed", alpha = 0.5, show.legend = FALSE) +
      geom_line(linewidth = 1) +
      geom_point(size = 2) +
      scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +
      scale_color_manual(values = c("50%" = "steelblue", "95%" = "firebrick")) +
      labs(x = NULL, y = "Coverage", color = "Interval") +
      theme_minimal(base_size = 12)
  })

  output$drift_trend_plot <- renderPlot({
    m <- bundle()$metrics
    m$evaluation_date <- as.Date(m$evaluation_date)
    m <- m[order(m$evaluation_date), ]
    m$sig <- m$drift_stage3_p < 0.05
    ggplot(m, aes(x = evaluation_date, y = drift_stage3_D)) +
      geom_line(linewidth = 1, color = "grey60") +
      geom_point(aes(color = sig), size = 3) +
      scale_color_manual(values = c("FALSE" = "grey40", "TRUE" = "firebrick"),
                         labels = c("FALSE" = "n.s.", "TRUE" = "p < 0.05"),
                         name = NULL) +
      labs(x = NULL, y = "KS D-statistic") +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")
  })
}

shinyApp(ui, server)
