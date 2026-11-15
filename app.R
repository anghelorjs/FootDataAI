# =============================================================================
# FOOTDATA AI | FASE 8 - DASHBOARD + CHATBOT + ACTUALIZACION RSS
# Instalar: install.packages(c('shiny','bslib','readr','dplyr','tidyr',
#                            'stringr','ggplot2','plotly','DT','processx'))
# Ejecutar desde la carpeta FootDataAI: Rscript app.R
# Fuente de datos: data/procesados/mineria_noticias.csv y reportes/fase5/*.csv
# Actualización opcional: lanza las fases 2-5 desde R/06_actualizacion.R.
# =============================================================================

paquetes <- c('shiny','bslib','readr','dplyr','tidyr','stringr','ggplot2','plotly','DT')
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly=TRUE)]
if (length(faltantes)) stop('Instala paquetes faltantes: ', paste(faltantes,collapse=', '),
                            '\ninstall.packages(c(',paste(sprintf('"%s"',faltantes),collapse=', '),'))')

if (!file.exists('R/05_chatbot.R')) stop('Falta R/05_chatbot.R en el proyecto.')
if (!file.exists('R/06_actualizacion.R')) stop('Falta R/06_actualizacion.R en el proyecto.')
source('R/05_chatbot.R', local=TRUE)

archivo_noticias <- 'data/procesados/mineria_noticias.csv'
archivo_equipos <- 'reportes/fase5/09_detalle_menciones_equipos.csv'
archivo_competiciones <- 'reportes/fase5/10_detalle_menciones_competiciones.csv'
archivo_palabras <- 'reportes/fase5/01_frecuencia_palabras.csv'
archivo_bigramas <- 'reportes/fase5/02_bigramas.csv'

if (!file.exists(archivo_noticias)) stop('No existe ',archivo_noticias,
  '. Ejecuta primero Rscript R/03_preprocesamiento.R y Rscript R/04_mineria_datos.R')

leer_csv <- function(path) {
  if (!file.exists(path)) return(NULL)
  readr::read_csv(path,show_col_types=FALSE,
                  col_types=readr::cols(.default=readr::col_character()),
                  locale=readr::locale(encoding='UTF-8'),progress=FALSE)
}

cargar <- function() {
  n <- leer_csv(archivo_noticias)
  req <- c('id','titulo','url','fecha_publicacion_utc','fuente')
  ausentes <- setdiff(req,names(n))
  if (length(ausentes)) stop('Faltan columnas en mineria_noticias.csv: ',paste(ausentes,collapse=', '))
  if (anyDuplicated(n$id)) stop('IDs duplicados en mineria_noticias.csv')
  n$id <- as.character(n$id)
  n$titulo <- dplyr::coalesce(n$titulo,'')
  n$fecha_dia <- as.Date(substr(n$fecha_publicacion_utc,1,10),format='%Y-%m-%d')
  if (!'medio' %in% names(n)) n$medio <- n$fuente
  if (!'idioma' %in% names(n)) n$idioma <- NA_character_
  if (!'tema_principal' %in% names(n)) n$tema_principal <- 'sin_clasificar'
  n$tema_principal[is.na(n$tema_principal)|!nzchar(n$tema_principal)] <- 'sin_clasificar'
  if (!'equipos_detectados' %in% names(n)) n$equipos_detectados <- ''
  if (!'competiciones_detectadas' %in% names(n)) n$competiciones_detectadas <- ''
  n$equipos_detectados <- dplyr::coalesce(n$equipos_detectados,'')
  n$competiciones_detectadas <- dplyr::coalesce(n$competiciones_detectadas,'')
  list(noticias=n,
       equipos=leer_csv(archivo_equipos),
       competiciones=leer_csv(archivo_competiciones),
       palabras=leer_csv(archivo_palabras),
       bigramas=leer_csv(archivo_bigramas))
}

# Cuenta las menciones basandose en el conjunto de noticias FILTRADO.
# Las entidades ya vienen detectadas por las reglas de la fase 5.
resumen_entidades <- function(datos,col) {
  if (!nrow(datos)) return(data.frame(entidad=character(),noticias=integer()))
  items <- strsplit(datos[[col]],';',fixed=TRUE)
  registros <- lapply(seq_along(items),function(i) {
    v <- trimws(items[[i]])
    v <- unique(v[nzchar(v)])
    if (!length(v)) return(NULL)
    data.frame(id=datos$id[i],entidad=v,stringsAsFactors=FALSE)
  })
  registros <- dplyr::bind_rows(registros)
  if (!nrow(registros)) return(data.frame(entidad=character(),noticias=integer()))
  registros |>
    dplyr::distinct(id,entidad) |>
    dplyr::count(entidad,name='noticias',sort=TRUE)
}

# Un enlace se construye solo cuando la URL tiene esquema http(s).
# El resto de las columnas se escapan automaticamente en la tabla.
enlace_seguro <- function(u) {
  if (is.na(u) || !grepl('^https?://',u,ignore.case=TRUE)) return('Sin enlace')
  url_escape <- htmltools::htmlEscape(u)
  paste0('<a href="',url_escape,'" target="_blank" rel="noopener noreferrer">Abrir noticia</a>')
}

ui <- shiny::fluidPage(
  theme=bslib::bs_theme(version=5,bootswatch='darkly',primary='#10b981'),
  shiny::tags$head(shiny::tags$style(shiny::HTML('
    .container-fluid {max-width: 1600px; padding-top: 12px;}
    .kpi {background:#202c39;border:1px solid #34465a;border-radius:12px;padding:16px;margin-bottom:14px;}
    .kpi .num {font-size:30px;font-weight:750;line-height:1.25;}
    .kpi .desc {color:#c2d0dd;font-size:13px;}
    .well {background:#1d2935;border:1px solid #35465a;}
    .shiny-output-error-validation {color:#f0c36d;}
  '))),
  shiny::titlePanel('⚽ FootDataAI | Dashboard de noticias internacionales'),
  shiny::p('Análisis descriptivo de titulares y resúmenes de BBC Sport. Las menciones de entidades se detectan mediante reglas.'),
  shiny::sidebarLayout(
    shiny::sidebarPanel(width=3,
      shiny::h4('Filtros'),
      shiny::selectInput('fuente','Canal RSS',choices='Todos'),
      shiny::selectInput('tema','Tema principal',choices='Todos'),
      shiny::selectInput('equipo','Equipo mencionado',choices='Todos'),
      shiny::selectInput('competicion','Competición mencionada',choices='Todos'),
      shiny::dateRangeInput('rango','Fecha de publicación (UTC)',start=NULL,end=NULL,
                            format='yyyy-mm-dd',separator=' a '),
      shiny::checkboxInput('incluir_sin_fecha','Incluir noticias sin fecha',value=TRUE),
      shiny::textInput('busqueda','Buscar en titular',''),
      shiny::actionButton('actualizar_rss','Actualizar noticias desde BBC',class='btn-primary'),
      shiny::br(), shiny::br(),
      shiny::actionButton('recargar','Recargar archivos locales',class='btn-success'),
      shiny::hr(),
      shiny::p('Actualizar ejecuta las fases 2–5. BBC RSS solo se consulta cuando han transcurrido 60 minutos desde el intento anterior.'),
      shiny::p(shiny::strong('Estado:'), shiny::textOutput('estado_actualizacion')),
      shiny::tags$details(shiny::tags$summary('Ver detalles de actualizacion'),
                          shiny::verbatimTextOutput('detalle_actualizacion')),
      shiny::p('Recargar solo vuelve a leer los CSV existentes.'),
      shiny::p(shiny::textOutput('actualizacion'))
    ),
    shiny::mainPanel(width=9,
      shiny::fluidRow(
        shiny::column(3,shiny::uiOutput('kpi_total')),
        shiny::column(3,shiny::uiOutput('kpi_fecha')),
        shiny::column(3,shiny::uiOutput('kpi_equipos')),
        shiny::column(3,shiny::uiOutput('kpi_fuentes'))
      ),
      shiny::tabsetPanel(
        shiny::tabPanel('Panorama',
          shiny::br(),
          shiny::fluidRow(
            shiny::column(6,plotly::plotlyOutput('grafico_dias',height='340px')),
            shiny::column(6,plotly::plotlyOutput('grafico_temas',height='340px'))
          ),
          shiny::fluidRow(
            shiny::column(6,plotly::plotlyOutput('grafico_equipos',height='350px')),
            shiny::column(6,plotly::plotlyOutput('grafico_competiciones',height='350px'))
          )
        ),
        shiny::tabPanel('Minería de texto',
          shiny::br(),
          shiny::p('Frecuencias y bigramas corresponden a la última ejecución de fase 5 y no se recalculan con los filtros.'),
          shiny::fluidRow(
            shiny::column(6,plotly::plotlyOutput('grafico_palabras',height='450px')),
            shiny::column(6,plotly::plotlyOutput('grafico_bigramas',height='450px'))
          )
        ),
        shiny::tabPanel('Noticias',
          shiny::br(),
          shiny::p('El botón de búsqueda y los filtros actúan sobre las noticias disponibles en la base procesada.'),
          DT::DTOutput('tabla_noticias')
        ),
        shiny::tabPanel('ChatBot',
          shiny::br(),
          shiny::h4('🤖 Consulta las noticias de FootDataAI'),
          shiny::p('Respuestas basadas solo en los CSV de la fase 5. Sin IA externa, sin noticias inventadas.'),
          shiny::p('Ejemplos: últimas noticias · noticias de Chelsea · fichajes · cuántas noticias hay · equipos más mencionados.'),
          shiny::div(class='fd-chat-history',style='max-height:520px;overflow-y:auto;',
                     shiny::uiOutput('chat_historial')),
          shiny::fluidRow(
            shiny::column(10,shiny::textInput('chat_pregunta',NULL,
              placeholder='Ej.: ¿Qué noticias hay sobre la Champions League?',width='100%')),
            shiny::column(2,shiny::actionButton('chat_enviar','Enviar',class='btn-success',width='100%'))
          ),
          shiny::actionButton('chat_limpiar','Limpiar conversación',class='btn-outline-secondary'),
          shiny::p(shiny::tags$small('El ChatBot consulta el corpus completo cargado, independientemente de los filtros del Dashboard.'))
        ),
        shiny::tabPanel('Metodología',shiny::br(),
          shiny::h4('Alcance y limitaciones'),
          shiny::tags$ul(
            shiny::tags$li('Fuente: canales RSS de BBC Sport, no un historial completo de todos los medios.'),
            shiny::tags$li('Temas y entidades: detección por reglas; puede haber falsos positivos y negativos.'),
            shiny::tags$li('Una noticia puede mencionar más de un equipo o competición.'),
            shiny::tags$li('Las noticias sin fecha no se agregan en el gráfico temporal.'),
            shiny::tags$li('Las tendencias observadas son descriptivas, no predictivas.'),
            shiny::tags$li('El ChatBot consulta noticias locales mediante reglas y búsquedas; no es un modelo generativo.'),
            shiny::tags$li('Actualización bajo demanda con intervalos de seguridad; no se evita el límite impuesto por la fuente.')
          ),
          shiny::verbatimTextOutput('calidad')
        )
      )
    )
  )
)

server <- function(input,output,session) {
  datos <- shiny::reactiveVal(cargar())
  ultimo <- shiny::reactiveVal(Sys.time())

  # Fase 8: ejecutar procesamiento en otro proceso para no bloquear Shiny.
  proceso_actualizacion <- shiny::reactiveVal(NULL)
  estado_actualizacion <- shiny::reactiveVal('Sin actualización iniciada en esta sesión')
  detalle_actualizacion <- shiny::reactiveVal('')
  ruta_estado <- 'reportes/fase8/estado.txt'
  ruta_lock <- 'reportes/fase8/actualizacion_en_curso.lock'
  leer_estado <- function() {
    if (!file.exists(ruta_estado)) return('Sin actualizaciones registradas')
    lineas <- tryCatch(readLines(ruta_estado, warn=FALSE, encoding='UTF-8'), error=function(e) character())
    paste(lineas, collapse=' | ')
  }

  shiny::observeEvent(input$actualizar_rss, {
    actual <- proceso_actualizacion()
    if (!is.null(actual) && actual$is_alive()) {
      shiny::showNotification('Ya se esta actualizando. Revisa el estado.', type='warning')
      return(invisible(NULL))
    }
    if (dir.exists(ruta_lock)) {
      shiny::showNotification('Otra actualización está en curso o dejó un candado pendiente. Revisa reportes/fase8.', type='warning', duration=12)
      return(invisible(NULL))
    }
    dir.create('reportes/fase8', recursive=TRUE, showWarnings=FALSE)
    ejecutable <- Sys.which('Rscript')
    if (!nzchar(ejecutable)) ejecutable <- file.path(R.home('bin'), if (.Platform$OS.type=='windows') 'Rscript.exe' else 'Rscript')
    if (!file.exists(ejecutable)) {
      shiny::showNotification('No se encontró Rscript.',type='error')
      return(invisible(NULL))
    }
    intento <- tryCatch(processx::process$new(
      command=ejecutable,
      args=c('--vanilla', 'R/06_actualizacion.R'),
      wd=normalizePath(getwd()),
      stdout='reportes/fase8/consola.log',
      stderr='reportes/fase8/errores.log',
      cleanup=FALSE
    ), error=function(e) e)
    if (inherits(intento, 'error')) {
      shiny::showNotification(paste('No se pudo iniciar:', conditionMessage(intento)),type='error',duration=12)
      return(invisible(NULL))
    }
    proceso_actualizacion(intento)
    estado_actualizacion('Actualizando en segundo proceso...')
    detalle_actualizacion('El dashboard seguirá disponible mientras se ejecutan las fases.')
    shiny::showNotification('Actualización iniciada. No cierres el proceso de R.',type='message')
  })

  shiny::observe({
    shiny::invalidateLater(1500, session)
    p <- proceso_actualizacion()
    if (is.null(p)) return(invisible(NULL))
    detalle_actualizacion(leer_estado())
    if (p$is_alive()) return(invisible(NULL))
    codigo <- p$get_exit_status()
    proceso_actualizacion(NULL)
    if (!is.null(codigo) && codigo==0L) {
      tryCatch({
        datos(cargar())
        ultimo(Sys.time())
        estado_actualizacion('Completado. Dashboard y ChatBot recargados.')
        shiny::showNotification('Noticias y gráficos actualizados.',type='message')
      }, error=function(e) {
        estado_actualizacion(paste('Procesado, pero falló la recarga:',conditionMessage(e)))
        shiny::showNotification(conditionMessage(e),type='error',duration=12)
      })
    } else {
      estado_actualizacion(paste('Error durante la actualización (código',codigo,'). Revisa reportes/fase8.'))
      shiny::showNotification('Fallo la actualización. Revisa los logs por fase.',type='error',duration=12)
    }
  })
  output$estado_actualizacion <- shiny::renderText(estado_actualizacion())
  output$detalle_actualizacion <- shiny::renderText(detalle_actualizacion())

  # ChatBot: historial local a la sesión, con respuestas fundamentadas en noticias.
  historial <- shiny::reactiveVal(list())
  shiny::observeEvent(input$chat_enviar, {
    pregunta <- trimws(input$chat_pregunta)
    if (!nzchar(pregunta)) return(invisible(NULL))
    respuesta <- tryCatch(fd_chatbot_responder(pregunta,datos()$noticias),
      error=function(e) list(texto=paste('No pude procesar la pregunta:',conditionMessage(e)),
                              noticias=datos()$noticias[0,,drop=FALSE],tipo='error'))
    anterior <- historial()
    anterior[[length(anterior)+1L]] <- list(pregunta=pregunta,respuesta=respuesta)
    historial(tail(anterior,12L))
    shiny::updateTextInput(session,'chat_pregunta',value='')
  })
  shiny::observeEvent(input$chat_limpiar, historial(list()))
  output$chat_historial <- shiny::renderUI({
    mensajes <- historial()
    if (!length(mensajes)) return(shiny::div(class='alert alert-secondary',
      'Escribe una pregunta para consultar los titulares almacenados.'))
    shiny::tagList(lapply(mensajes,function(m) {
      r <- m$respuesta
      tarjetas <- if (!is.null(r$noticias) && nrow(r$noticias))
        lapply(seq_len(nrow(r$noticias)), function(i) {
          noticia <- r$noticias[i,,drop=FALSE]
          url <- noticia$url[[1]]
          titulo <- noticia$titulo[[1]]
          fecha <- noticia$fecha_publicacion_utc[[1]]
          fecha <- if (is.na(fecha) || !nzchar(fecha)) 'Fecha no disponible (UTC)' else paste0('Publicado UTC: ',fecha)
          fuente <- noticia$fuente[[1]]
          enlace <- if (!is.na(url) && grepl('^https?://',url,ignore.case=TRUE))
            shiny::tags$a(href=url,target='_blank',rel='noopener noreferrer',titulo)
            else shiny::span(titulo)
          shiny::div(style='border-left:3px solid #10b981;padding:9px 12px;margin:8px 0;background:#23333f;border-radius:5px;',
                     enlace,shiny::tags$div(style='font-size:12px;color:#b9c7d3;',
                       paste(fecha,'|',fuente)))
        }) else NULL
      shiny::div(style='margin:12px 0 18px 0;',
        shiny::div(style='text-align:right;margin-bottom:8px;',
          shiny::span(style='display:inline-block;background:#145c50;color:white;padding:9px 13px;border-radius:12px;max-width:90%;',m$pregunta)),
        shiny::div(style='background:#1f2d3b;border:1px solid #3a5265;border-radius:12px;padding:12px;',
          shiny::strong('FootDataAI: '),shiny::span(r$texto),tarjetas))
    }))
  })

  # Se inicia una sola lectura y se actualiza bajo demanda.
  shiny::observeEvent(input$recargar, {
    tryCatch({
      nuevo <- cargar()
      datos(nuevo)
      ultimo(Sys.time())
      shiny::showNotification('Archivos CSV recargados.',type='message')
    },error=function(e) shiny::showNotification(conditionMessage(e),type='error',duration=12))
  })

  shiny::observeEvent(datos(), {
    n <- datos()$noticias
    equipos <- sort(unique(unlist(strsplit(n$equipos_detectados,';',fixed=TRUE))))
    comps <- sort(unique(unlist(strsplit(n$competiciones_detectadas,';',fixed=TRUE))))
    equipos <- trimws(equipos); comps <- trimws(comps)
    equipos <- equipos[nzchar(equipos)]; comps <- comps[nzchar(comps)]
    shiny::updateSelectInput(session,'fuente',choices=c('Todos',sort(unique(n$fuente))),selected='Todos')
    shiny::updateSelectInput(session,'tema',choices=c('Todos',sort(unique(n$tema_principal))),selected='Todos')
    shiny::updateSelectInput(session,'equipo',choices=c('Todos',equipos),selected='Todos')
    shiny::updateSelectInput(session,'competicion',choices=c('Todos',comps),selected='Todos')
    fechas <- n$fecha_dia[!is.na(n$fecha_dia)]
    if (length(fechas)) shiny::updateDateRangeInput(session,'rango',
      start=min(fechas),end=max(fechas),min=min(fechas),max=max(fechas))
  },ignoreInit=FALSE)

  filtradas <- shiny::reactive({
    n <- datos()$noticias
    if (!is.null(input$fuente) && input$fuente!='Todos') n <- n[n$fuente==input$fuente,,drop=FALSE]
    if (!is.null(input$tema) && input$tema!='Todos') n <- n[n$tema_principal==input$tema,,drop=FALSE]
    if (!is.null(input$equipo) && input$equipo!='Todos') {
      n <- n[vapply(strsplit(n$equipos_detectados,';',fixed=TRUE),
        function(x) input$equipo %in% trimws(x),logical(1)),,drop=FALSE]
    }
    if (!is.null(input$competicion) && input$competicion!='Todos') {
      n <- n[vapply(strsplit(n$competiciones_detectadas,';',fixed=TRUE),
        function(x) input$competicion %in% trimws(x),logical(1)),,drop=FALSE]
    }
    if (!is.null(input$rango) && length(input$rango)==2 && all(!is.na(input$rango))) {
      dentro <- !is.na(n$fecha_dia) & n$fecha_dia>=input$rango[1] & n$fecha_dia<=input$rango[2]
      if (isTRUE(input$incluir_sin_fecha)) dentro <- dentro | is.na(n$fecha_dia)
      n <- n[dentro,,drop=FALSE]
    } else if (!isTRUE(input$incluir_sin_fecha)) n <- n[!is.na(n$fecha_dia),,drop=FALSE]
    if (!is.null(input$busqueda) && nzchar(trimws(input$busqueda))) {
      n <- n[stringr::str_detect(n$titulo,stringr::fixed(trimws(input$busqueda),ignore_case=TRUE)),,drop=FALSE]
    }
    n
  })

  kpi <- function(numero,descripcion) shiny::div(class='kpi',
    shiny::div(class='num',as.character(numero)),shiny::div(class='desc',descripcion))
  output$kpi_total <- shiny::renderUI(kpi(nrow(filtradas()),'Noticias filtradas'))
  output$kpi_fecha <- shiny::renderUI(kpi(sum(!is.na(filtradas()$fecha_dia)),'Con fecha publicada'))
  output$kpi_equipos <- shiny::renderUI(kpi(sum(nzchar(filtradas()$equipos_detectados)),'Con equipo detectado'))
  output$kpi_fuentes <- shiny::renderUI(kpi(dplyr::n_distinct(filtradas()$fuente),'Canales RSS'))
  output$actualizacion <- shiny::renderText(paste('Archivos leídos:',format(ultimo(),'%Y-%m-%d %H:%M:%S')))

  # plotly::ggplotly permite explorar barras y fechas con hover.
  barra <- function(df,etiqueta,valor,titulo,color='#10b981',limite=12) {
    shiny::validate(shiny::need(nrow(df)>0,'No hay datos para esta selección.'))
    df <- utils::head(df,limite)
    p <- ggplot2::ggplot(df,ggplot2::aes(x=stats::reorder(.data[[etiqueta]],.data[[valor]]),
                                      y=.data[[valor]])) +
      ggplot2::geom_col(fill=color) + ggplot2::coord_flip() +
      ggplot2::labs(title=titulo,x=NULL,y='Noticias / menciones') +
      ggplot2::theme_minimal(base_size=12)
    plotly::ggplotly(p)
  }

  output$grafico_dias <- plotly::renderPlotly({
    df <- filtradas() |>
      dplyr::filter(!is.na(fecha_dia)) |>
      dplyr::count(fecha_dia,name='noticias') |>
      dplyr::arrange(fecha_dia)
    shiny::validate(shiny::need(nrow(df)>0,'No hay noticias fechadas en este filtro.'))
    p <- ggplot2::ggplot(df,ggplot2::aes(x=fecha_dia,y=noticias)) +
      ggplot2::geom_line(color='#14b8a6',linewidth=0.8) +
      ggplot2::geom_point(color='#14b8a6') +
      ggplot2::labs(title='Noticias por día (UTC)',x='Fecha',y='Noticias') +
      ggplot2::theme_minimal(base_size=12)
    plotly::ggplotly(p)
  })
  output$grafico_temas <- plotly::renderPlotly({
    df <- filtradas() |> dplyr::count(tema_principal,name='noticias',sort=TRUE)
    barra(df,'tema_principal','noticias','Temas principales',color='#3b82f6')
  })
  output$grafico_equipos <- plotly::renderPlotly({
    barra(resumen_entidades(filtradas(),'equipos_detectados'),'entidad','noticias','Equipos más mencionados')
  })
  output$grafico_competiciones <- plotly::renderPlotly({
    barra(resumen_entidades(filtradas(),'competiciones_detectadas'),'entidad','noticias',
          'Competiciones más mencionadas',color='#f59e0b')
  })
  output$grafico_palabras <- plotly::renderPlotly({
    df <- datos()$palabras
    shiny::validate(shiny::need(!is.null(df) && all(c('palabra','frecuencia') %in% names(df)),
      'Falta reportes/fase5/01_frecuencia_palabras.csv'))
    df$frecuencia <- as.numeric(df$frecuencia)
    barra(df,'palabra','frecuencia','Palabras frecuentes (corpus completo)',color='#06b6d4',limite=20)
  })
  output$grafico_bigramas <- plotly::renderPlotly({
    df <- datos()$bigramas
    shiny::validate(shiny::need(!is.null(df) && all(c('bigrama','frecuencia') %in% names(df)),
      'Falta reportes/fase5/02_bigramas.csv'))
    df$frecuencia <- as.numeric(df$frecuencia)
    barra(df,'bigrama','frecuencia','Bigramas frecuentes (corpus completo)',color='#8b5cf6',limite=20)
  })
  output$tabla_noticias <- DT::renderDT({
    n <- filtradas()
    tabla <- data.frame(
      'Título'=n$titulo,
      'Publicación UTC'=ifelse(is.na(n$fecha_publicacion_utc),'Sin fecha',n$fecha_publicacion_utc),
      'Canal'=n$fuente,
      'Tema'=n$tema_principal,
      'Equipos'=n$equipos_detectados,
      'Competiciones'=n$competiciones_detectadas,
      'Enlace'=vapply(n$url,enlace_seguro,character(1)),
      check.names=FALSE,stringsAsFactors=FALSE
    )
    tabla <- tabla[order(ifelse(tabla[['Publicación UTC']]=='Sin fecha','',tabla[['Publicación UTC']]),
                         decreasing=TRUE),,drop=FALSE]
    DT::datatable(tabla,rownames=FALSE,escape=seq_len(ncol(tabla)-1),
      filter='top',options=list(pageLength=10,scrollX=TRUE,language=list(search='Buscar:')))
  })
  output$calidad <- shiny::renderPrint({
    n <- filtradas()
    cat('Noticias en el filtro:',nrow(n),'\n')
    cat('Sin fecha:',sum(is.na(n$fecha_dia)),'\n')
    cat('Sin equipo detectado:',sum(!nzchar(n$equipos_detectados)),'\n')
    cat('Sin competición detectada:',sum(!nzchar(n$competiciones_detectadas)),'\n')
    cat('Sin tema principal:',sum(n$tema_principal=='sin_clasificar'),'\n')
    cat('Nota: la fecha proviene del RSS; las noticias sin fecha no se sustituyen por fecha de extracción.\n')
  })
}

shiny::shinyApp(ui,server)
