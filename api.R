# FootDataAI: API R + interfaz React compilada. Ejecutar desde la raíz.
if (.Platform$OS.type == 'windows') {
  # Windows no reconoce LC_ALL=C.UTF-8, usado por algunas terminales.
  Sys.setenv(LC_ALL='English_United States.utf8')
  invisible(Sys.setlocale('LC_ALL','English_United States.utf8'))
}
paquetes <- c('plumber','jsonlite','readr','processx','later')
faltantes <- paquetes[!vapply(paquetes,requireNamespace,logical(1),quietly=TRUE)]
if (length(faltantes)) stop('Instala primero: install.packages(c(',paste(sprintf('"%s"',faltantes),collapse=', '),'))')
if (!file.exists('R/09_servicios_web.R')) stop('Ejecuta desde la carpeta raíz de FootDataAI.')
source('R/09_servicios_web.R',local=TRUE,encoding='UTF-8')
invisible(tryCatch(fd_cargar_snapshot(),error=function(e) message(conditionMessage(e))))

api <- plumber::pr()
api <- plumber::pr_set_serializer(api,plumber::serializer_unboxed_json(na='null',null='null'))
api <- plumber::pr_set_parsers(api,list(json=list(simplifyVector=FALSE)))
api <- plumber::pr_set_error(api,function(req,res,err) {
  res$status <- 500L
  list(error=conditionMessage(err))
})
# Solo loopback. Las mutaciones aceptan JSON del mismo origen o del Vite local.
api <- plumber::pr_filter(api,'origen',function(req,res) {
  if (req$REQUEST_METHOD %in% c('POST','PUT','DELETE')) {
    origen <- req$HTTP_ORIGIN
    permitidos <- c(paste0('http://',req$HTTP_HOST),'http://127.0.0.1:5173','http://localhost:5173')
    if (!is.null(origen) && !origen %in% permitidos) {res$status <- 403L; return(list(error='Origen no permitido.'))}
    if (is.null(req$CONTENT_TYPE) || !grepl('^application/json',req$CONTENT_TYPE)) {
      res$status <- 415L; return(list(error='Se requiere application/json.'))
    }
  }
  res$setHeader('X-Content-Type-Options','nosniff')
  plumber::forward()
})
api <- plumber::pr_get(api,'/api/health',function() list(ok=TRUE,service='FootDataAI',version='1.0.0'))
api <- plumber::pr_get(api,'/api/snapshot',function(res) {
  tryCatch(fd_cargar_snapshot()$respuesta,error=function(e) {res$status <- 503L; list(error=conditionMessage(e))})
})
api <- plumber::pr_get(api,'/api/status',function() fd_estado())
api <- plumber::pr_post(api,'/api/chat',function(req,res) {
  cuerpo <- req$body
  if (!is.list(cuerpo) || !is.character(cuerpo$question) || length(cuerpo$question)!=1 ||
      is.na(cuerpo$question) || !nzchar(trimws(cuerpo$question)) || nchar(cuerpo$question)>1000) {
    res$status <- 400L; return(list(error='Escribe una pregunta de entre 1 y 1000 caracteres.'))
  }
  tryCatch({
    n <- fd_filtrar(fd_cargar_snapshot()$noticias,if (is.null(cuerpo$filters)) list() else cuerpo$filters)
    respuesta <- fd_chatbot_responder(cuerpo$question,n)
    list(text=respuesta$texto,type=respuesta$tipo,scopeCount=nrow(n),
      articles=as.list(as.character(respuesta$noticias$id)))
  },error=function(e) {res$status <- 400L; list(error=conditionMessage(e))})
})
api <- plumber::pr_post(api,'/api/update',function() fd_iniciar_actualizacion())
api <- plumber::pr_post(api,'/api/settings',function(req,res) {
  if (!is.list(req$body) || !is.logical(req$body$automatic) || length(req$body$automatic)!=1 || is.na(req$body$automatic)) {
    res$status <- 400L; return(list(error='automatic debe ser true o false.'))
  }
  fd_web$automatico <- req$body$automatic
  fd_estado()
})
api <- plumber::pr_get(api,'/api/logs',function() {
  archivos <- c('01_01_extraccion.log','02_02_base_datos.log','03_03_preprocesamiento.log','04_04_mineria_datos.log')
  lapply(archivos,function(x) {
    p <- file.path('reportes/fase8',x)
    list(name=x,lines=as.list(if (file.exists(p)) tail(readLines(p,warn=FALSE,encoding='UTF-8'),40) else 'Todavía no hay registros.'))
  })
})
if (dir.exists('frontend/dist')) {
  api <- plumber::pr_static(api,'/',direc='frontend/dist')
} else message('Interfaz sin compilar. Ejecuta: cd frontend; npm install; npm run build')

# El temporizador funciona aunque no haya navegadores abiertos, mientras la API siga activa.
programar <- function() {
  fd_tick()
  later::later(programar,60)
}
later::later(programar,60)
puerto <- as.integer(Sys.getenv('FOOTDATA_PORT','8000'))
message('FootDataAI disponible en http://127.0.0.1:',puerto)
plumber::pr_run(api,host='127.0.0.1',port=puerto,docs=FALSE)
