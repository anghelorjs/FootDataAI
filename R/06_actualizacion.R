# =============================================================================
# FOOTDATA AI | FASE 8 - ACTUALIZACION INCREMENTAL DESDE RSS
# Ejecutar desde FootDataAI: Rscript R/06_actualizacion.R
# Usa los scripts EXISTENTES 01, 02, 03 y 04 en orden.
# El extractor comparte el intervalo configurable y respeta el TTL/cache del RSS.
# =============================================================================

ejecutar_actualizacion <- function() {
if (!dir.exists('R') || !file.exists('R/01_extraccion.R')) {
  stop('Ejecuta desde la raiz de FootDataAI (carpeta que contiene R/ y app.R).')
}

salida <- file.path('reportes', 'fase8')
dir.create(salida, recursive=TRUE, showWarnings=FALSE)
archivo_estado <- file.path(salida, 'estado.txt')
carpeta_candado <- file.path(salida, 'actualizacion_en_curso.lock')

# Un candado global impide actualizaciones simultaneas desde varias sesiones.
if (!dir.create(carpeta_candado, showWarnings=FALSE)) {
  cat('Ya hay otra actualizacion en ejecucion (o un candado pendiente).\n')
  cat('Si no existe ningun proceso activo, elimina manualmente:\n', carpeta_candado, '\n')
  stop('Candado activo: no se inicia una segunda ejecución.')
}
on.exit(unlink(carpeta_candado, recursive=TRUE, force=TRUE), add=TRUE)

ahora <- function() format(Sys.time(), '%Y-%m-%d %H:%M:%S %Z')
reportar <- function(estado, fase, detalle) {
  lineas <- c(
    paste0('estado=', estado),
    paste0('fase=', fase),
    paste0('detalle=', gsub('[\r\n=]', ' ', detalle)),
    paste0('fecha=', ahora())
  )
  temporal <- paste0(archivo_estado, '.tmp')
  writeLines(lineas, temporal, useBytes=TRUE)
  if (file.exists(archivo_estado)) unlink(archivo_estado)
  if (!file.rename(temporal, archivo_estado)) {
    file.copy(temporal, archivo_estado, overwrite=TRUE)
    unlink(temporal)
  }
  cat('[', ahora(), '] ', estado, ' | ', fase, ' | ', detalle, '\n', sep='')
}

rscript <- Sys.which('Rscript')
if (!nzchar(rscript)) {
  rscript <- file.path(R.home('bin'), if (.Platform$OS.type == 'windows') 'Rscript.exe' else 'Rscript')
}
if (!file.exists(rscript)) stop('No se encontro Rscript. Configura PATH o R_HOME.')

pasos <- c(
  '01_extraccion.R',
  '02_base_datos.R',
  '03_preprocesamiento.R',
  '04_mineria_datos.R'
)

reportar('EN_CURSO', 'Inicio', 'Actualizando noticias y resultados locales')
csv_crudo <- 'data/crudos/noticias_futbol.csv'
firma_antes <- if (file.exists(csv_crudo)) unname(tools::md5sum(csv_crudo)) else NA_character_
for (i in seq_along(pasos)) {
  script <- file.path('R', pasos[[i]])
  if (!file.exists(script)) {
    reportar('ERROR', pasos[[i]], paste('No existe', script))
    stop('La actualización se interrumpió; consulta el reporte de estado y los logs.')
  }
  reportar('EN_CURSO', pasos[[i]], sprintf('Ejecutando paso %d de %d', i, length(pasos)))
  log <- file.path(salida, sprintf('%02d_%s.log', i, sub('\\.R$', '', pasos[[i]])))
  # Cada paso se ejecuta en un proceso R distinto para aislar paquetes/variables.
  resultado <- tryCatch(
    suppressWarnings(system2(rscript, args=c('--vanilla', shQuote(script)),
                             stdout=log, stderr=log, wait=TRUE)),
    error=function(e) e
  )
  if (inherits(resultado, 'error')) {
    reportar('ERROR', pasos[[i]], conditionMessage(resultado))
    stop('La actualización se interrumpió; consulta el reporte de estado y los logs.')
  }
  codigo <- if (is.numeric(resultado)) as.integer(resultado[[1]]) else 0L
  if (!identical(codigo, 0L)) {
    reportar('ERROR', pasos[[i]], paste('Codigo de salida', codigo, '- revisa', log))
    stop('La actualización se interrumpió; consulta el reporte de estado y los logs.')
  }
  if (i==1L) {
    firma_despues <- if (file.exists(csv_crudo)) unname(tools::md5sum(csv_crudo)) else NA_character_
    derivados <- c('data/futbol.sqlite','data/procesados/noticias_preprocesadas.csv',
      'data/procesados/tokens_limpios.csv','data/procesados/mineria_noticias.csv',
      paste0('reportes/fase5/',c('01_frecuencia_palabras.csv','02_bigramas.csv',
        '09_detalle_menciones_equipos.csv','10_detalle_menciones_competiciones.csv')))
    if (!is.na(firma_antes) && identical(firma_antes,firma_despues) && all(file.exists(derivados))) {
      reportar('COMPLETADO','Final','Sin cambios en las noticias. Se conservan SQLite, los graficos y el chatbot ya procesados.')
      return(invisible(NULL))
    }
  }
}

if (!file.exists('data/procesados/mineria_noticias.csv')) {
  reportar('ERROR', 'Verificacion', 'Falta mineria_noticias.csv')
  stop('La actualización se interrumpió; consulta el reporte de estado y los logs.')
}
reportar('COMPLETADO', 'Final', 'RSS, SQLite, preprocesamiento y mineria actualizados')

}

ejecutar_actualizacion()
