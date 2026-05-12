library(shiny)
library(here)
library(pins)
library(ggplot2)
library(scales)

source(here::here("R", "recovery_model.R"))

board <- board_folder(here::here("data", "pins"), versioned = TRUE)
model <- pin_read(board, "recovery_model")

input_grid <- seq(5e8, 5e9, length.out = 50)

ui <- fluidPage(
  titlePanel("Recovery Predictor"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("input_cells", "Input cells (stage 0)",
                  min = 5e8, max = 5e9, value = 2e9, step = 1e8),
      hr(),
      h4("Model"),
      verbatimTextOutput("model_meta"),
      hr(),
      h4("Prediction at slider value"),
      verbatimTextOutput("current_summary"),
      width = 3
    ),
    mainPanel(
      h4("Predicted final yield with 50% and 95% intervals"),
      plotOutput("yield_plot", height = "520px"),
      width = 9
    )
  )
)

server <- function(input, output, session) {

  yield_bands <- reactive({
    predict_yield(model, input_grid, n_compound = 5000)
  })

  current_yield <- reactive({
    predict_yield(model, input$input_cells, n_compound = 5000)
  })

  output$model_meta <- renderText({
    paste(
      sprintf("Pool size : %d batches", model$n_pool),
      sprintf("Decay ESS : %.0f",       model$decay_ess),
      sprintf("Tau       : %d days",    model$decay_tau_days),
      sprintf("Trained   : %s",         format(model$trained_on, "%Y-%m-%d")),
      sprintf("Reference : %s",         format(model$reference_date)),
      sep = "\n"
    )
  })

  output$current_summary <- renderText({
    cur <- current_yield()
    paste(
      sprintf("q05  %.2fe8", cur$q05 / 1e8),
      sprintf("q25  %.2fe8", cur$q25 / 1e8),
      sprintf("q50  %.2fe8  (median)", cur$q50 / 1e8),
      sprintf("q75  %.2fe8", cur$q75 / 1e8),
      sprintf("q95  %.2fe8", cur$q95 / 1e8),
      sep = "\n"
    )
  })

  output$yield_plot <- renderPlot({
    b   <- yield_bands()
    cur <- current_yield()
    ggplot(b, aes(x = input_cells)) +
      geom_ribbon(aes(ymin = q05, ymax = q95), fill = "steelblue", alpha = 0.2) +
      geom_ribbon(aes(ymin = q25, ymax = q75), fill = "steelblue", alpha = 0.4) +
      geom_line(aes(y = q50), color = "steelblue", linewidth = 1) +
      geom_vline(xintercept = input$input_cells, color = "firebrick", linetype = "dashed") +
      geom_point(data = cur, aes(x = input_cells, y = q50),
                 color = "firebrick", size = 3) +
      scale_x_continuous(labels = label_number(scale = 1e-9, suffix = "e9")) +
      scale_y_continuous(labels = label_number(scale = 1e-8, suffix = "e8")) +
      labs(x = "Input cells (stage 0)", y = "Predicted yield (cells)") +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui, server)
