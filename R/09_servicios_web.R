# Servicios compartidos por la API. No ejecuta scraping al cargar este archivo.
source('R/05_chatbot.R', local=TRUE, encoding='UTF-8')

fd_web <- new.env(parent=emptyenv())
fd_web$snapshot <- NULL
fd_web$firma <- ''
fd_web$proceso <- NULL
fd_web$error <- NULL
fd_web$automatico <- identical(Sys.getenv('FOOTDATA_AUTO_UPDATE', '1'), '1')
fd_web$ultimo_inicio <- as.POSIXct(NA)

fd_iso <- function(x) {
  x <- gsub('/', '-', as.character(x), fixed=TRUE)
  x <- sub('T', ' ', x, fixed=TRUE)
  x <- sub('Z$', '', x)
  fechas <- suppressWarnings(as.POSIXct(x, format='%Y-%m-%d %H:%M:%S', tz='UTC'))
  ifelse(is.na(fechas), NA_character_, format(fechas, '%Y-%m-%dT%H:%M:%SZ', tz='UTC'))
}

fd_leer <- function(ruta) {
  readr::read_csv(ruta, col_types=readr::cols(.default=readr::col_character()),
                  locale=readr::locale(encoding='UTF-8'), show_col_types=FALSE, progress=FALSE)
}

fd_cargar_snapshot <- function(forzar=FALSE) {
  archivo <- 'data/procesados/mineria_noticias.csv'
  archivo_tokens <- 'data/procesados/tokens_limpios.csv'
  firma <- paste(file.info(c(archivo, archivo_tokens))$mtime, collapse='|')
  ocupado <- dir.exists('reportes/fase8/actualizacion_en_curso.lock')
  fallo <- !is.null(fd_web$error)
  if (!is.null(fd_web$snapshot) && (ocupado || fallo || (!forzar && identical(firma, fd_web$firma))))
    return(fd_web$snapshot)
  if (!file.exists(archivo)) stop('Faltan datos procesados. Ejecuta Rscript R/06_actualizacion.R.')
  # Durante una actualización se conserva la última instantánea completa en memoria.
  if (ocupado) stop('Actualización en curso. Espera a que terminen las cuatro fases.')
  n <- fd_leer(archivo)
  if (!all(c('id','titulo','url','fuente','fecha_publicacion_utc') %in% names(n)))
    stop('El CSV de minería no tiene las columnas requeridas.')
  if (anyDuplicated(n$id)) stop('Hay IDs duplicados en el CSV de minería.')
  for (col in c('resumen','medio','equipos_detectados','competiciones_detectadas','tema_principal')) {
    if (!col %in% names(n)) n[[col]] <- rep('',nrow(n))
    n[[col]][is.na(n[[col]])] <- ''
  }
  columnas_tema <- setdiff(grep('^tema_', names(n), value=TRUE), 'tema_principal')
  temas <- lapply(seq_len(nrow(n)), function(i) {
    sub('^tema_', '', columnas_tema[vapply(columnas_tema, function(col)
      tolower(n[[col]][i]) %in% c('true','t','1'), logical(1))])
  })
  # Recupera también los CSV históricos afectados por la conversión de tema_principal.
  n$tema_principal <- vapply(temas, function(t) if (length(t)) t[[1]] else 'sin_clasificar', character(1))
  n$fecha_publicacion_utc <- fd_iso(n$fecha_publicacion_utc)
  tokens <- if (file.exists(archivo_tokens)) fd_leer(archivo_tokens) else data.frame(id=character(),palabra=character())
  if (any(!as.character(tokens$id) %in% n$id)) stop('Los tokens y las noticias pertenecen a ejecuciones diferentes. Completa nuevamente la actualización.')
  token_ids <- split(tokens$palabra, as.character(tokens$id))
  entidades <- function(x) {
    if (is.na(x) || !nzchar(x)) return(list())
    as.list(unique(trimws(strsplit(x, ';', fixed=TRUE)[[1]])))
  }
  articulos <- lapply(seq_len(nrow(n)), function(i) list(
    id=as.character(n$id[i]), title=n$titulo[i], summary=n$resumen[i],
    url=n$url[i], source=n$fuente[i], medium=n$medio[i],
    date=n$fecha_publicacion_utc[i], topic=n$tema_principal[i],
    topics=as.list(temas[[i]]), teams=entidades(n$equipos_detectados[i]),
    competitions=entidades(n$competiciones_detectadas[i]),
    tokens=as.list(unname(token_ids[[as.character(n$id[i])]]))
  ))
  extraidas <- if ('fecha_extraccion_utc' %in% names(n)) fd_iso(n$fecha_extraccion_utc) else NA_character_
  fd_web$snapshot <- list(noticias=n, respuesta=list(
    articles=articulos,
    meta=list(total=nrow(n), generatedAt=format(Sys.time(),'%Y-%m-%dT%H:%M:%SZ',tz='UTC'),
      extractedAt=if (all(is.na(extraidas))) NA_character_ else max(extraidas,na.rm=TRUE),
      validDates=sum(!is.na(n$fecha_publicacion_utc)),
      methodology='Titulares y resúmenes RSS de BBC Sport. Temas y entidades detectados por reglas; análisis descriptivo, sin predicciones.')
  ))
  fd_web$firma <- firma
  fd_web$snapshot
}

fd_filtrar <- function(n, filtros=list()) {
  if (!is.list(filtros)) stop('Los filtros deben ser un objeto JSON.')
  texto <- function(clave) {
    x <- filtros[[clave]]
    if (is.null(x)) return('')
    if (!is.character(x) || length(x)!=1 || is.na(x)) stop('Filtro inválido: ',clave)
    x
  }
  hit <- rep(TRUE,nrow(n))
  if (nzchar(x <- texto('source'))) hit <- hit & n$fuente==x
  if (nzchar(x <- texto('topic'))) {
    if (x=='sin_clasificar') hit <- hit & n$tema_principal==x
    else {
      col <- paste0('tema_',x)
      hit <- hit & if (col %in% names(n)) tolower(n[[col]]) %in% c('true','t','1') else FALSE
    }
  }
  if (nzchar(x <- texto('team'))) hit <- hit & fd_menciona_entidad(n,'equipos_detectados',x)
  if (nzchar(x <- texto('competition'))) hit <- hit & fd_menciona_entidad(n,'competiciones_detectadas',x)
  if (nzchar(x <- texto('query'))) hit <- hit & grepl(fd_normalizar(x),
    fd_normalizar(paste(n$titulo,n$resumen,n$equipos_detectados,n$competiciones_detectadas)),fixed=TRUE)
  fechas <- substr(n$fecha_publicacion_utc,1,10)
  sin_fecha <- is.na(n$fecha_publicacion_utc)
  incluir <- !identical(filtros$includeUndated,FALSE)
  for (limite in c('from','to')) {
    x <- texto(limite)
    if (nzchar(x)) {
      if (!grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}$',x) || is.na(as.Date(x))) stop('Fecha inválida: ',limite)
      compara <- if (limite=='from') fechas>=x else fechas<=x
      hit <- hit & ((sin_fecha & incluir) | (!sin_fecha & compara))
    }
  }
  if (!incluir) hit <- hit & !sin_fecha
  if (!is.null(filtros$ids)) {
    ids <- unlist(filtros$ids,use.names=FALSE)
    if (length(ids)>100000) stop('Demasiados IDs.')
    hit <- hit & n$id %in% ids
  }
  hit[is.na(hit)] <- FALSE
  n[hit,,drop=FALSE]
}

fd_control_rss <- function() {
  p <- 'reportes/ultima_consulta_bbc.rds'
  anterior <- if (file.exists(p)) tryCatch(readRDS(p),error=function(e) NULL) else NULL
  if (!inherits(anterior,'POSIXct')) return(0)
  max(0, ceiling(3600-as.numeric(difftime(Sys.time(),anterior,units='secs'))))
}

fd_estado <- function() {
  p <- fd_web$proceso
  vivo <- !is.null(p) && p$is_alive()
  if (!is.null(p) && !vivo) {
    if (!identical(p$get_exit_status(),0L)) fd_web$error <- 'La actualización terminó con errores. Revisa los registros.'
    else fd_web$error <- NULL
    fd_web$proceso <- NULL
  }
  path <- 'reportes/fase8/estado.txt'
  lineas <- if (file.exists(path)) readLines(path,warn=FALSE,encoding='UTF-8') else character()
  valor <- function(clave) {
    x <- lineas[startsWith(lineas,paste0(clave,'='))]
    if (length(x)) substring(x[[1]],nchar(clave)+2) else ''
  }
  bloqueado <- dir.exists('reportes/fase8/actualizacion_en_curso.lock')
  list(running=vivo || bloqueado, automatic=fd_web$automatico,
    cooldownSeconds=fd_control_rss(), state=if (!is.null(fd_web$error)) 'ERROR' else valor('estado'),
    phase=valor('fase'), detail=if (!is.null(fd_web$error)) fd_web$error else valor('detalle'),
    updatedAt=valor('fecha'))
}

fd_iniciar_actualizacion <- function() {
  estado <- fd_estado()
  if (estado$running) return(list(started=FALSE, message='Ya hay una actualización en curso.',status=estado))
  if (estado$cooldownSeconds>0) return(list(started=FALSE,
    message=sprintf('La próxima consulta RSS estará disponible en %d minutos.',ceiling(estado$cooldownSeconds/60)), status=estado))
  # Guarda la última instantánea antes de que el proceso escriba los derivados.
  tryCatch(fd_cargar_snapshot(),error=function(e) NULL)
  dir.create('reportes/fase8',recursive=TRUE,showWarnings=FALSE)
  fd_web$proceso <- processx::process$new(
    file.path(R.home('bin'),if (.Platform$OS.type=='windows') 'Rscript.exe' else 'Rscript'),
    c('--vanilla','R/06_actualizacion.R'), wd=getwd(),
    stdout='reportes/fase8/api_actualizacion.log', stderr='2>&1',
    cleanup=TRUE, windows_hide_window=TRUE)
  fd_web$ultimo_inicio <- Sys.time()
  fd_web$error <- NULL
  list(started=TRUE, message='Actualización iniciada. Los datos se recargarán cuando terminen las cuatro fases.',status=fd_estado())
}

fd_tick <- function() {
  estado <- fd_estado()
  espera <- if (is.na(fd_web$ultimo_inicio)) Inf else as.numeric(difftime(Sys.time(),fd_web$ultimo_inicio,units='secs'))
  if (fd_web$automatico && !estado$running && estado$cooldownSeconds==0 && espera>=3600)
    tryCatch(fd_iniciar_actualizacion(),error=function(e) {fd_web$error <- conditionMessage(e)})
}
