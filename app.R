
library(shiny)
library(bslib)

ui <- page_fluid(
  theme = bs_theme(
    version = 5,
    bootswatch = "darkly"
  ),

  div(
    style = "text-align:center; padding:50px;",

    h1("⚽ FOOTDATA AI"),

    h3("Dashboard y ChatBot de Futbol Internacional"),

    p("Proyecto de Mineria de Datos con R"),

    actionButton(
      "probar",
      "Probar aplicacion",
      class = "btn-success"
    ),

    br(),
    br(),

    textOutput("resultado")
  )
)

server <- function(input, output, session) {

  output$resultado <- renderText({

    if (input$probar > 0) {
      "¡FootDataAI esta funcionando correctamente!"
    } else {
      "Sistema iniciado. Esperando conexion de noticias."
    }

  })

}

shinyApp(ui, server)