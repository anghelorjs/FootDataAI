# ============================================================================
# FOOTDATA AI | FASE 2 - RSS DE BBC SPORT (ALTERNATIVA A GDELT)
# Ejecutar desde la raiz de FootDataAI: Rscript R/01_extraccion.R
# Solo metadatos del RSS: titulo, resumen, fecha, URL y fuente.
# ============================================================================

paquetes <- c('httr2', 'xml2', 'dplyr', 'readr', 'tibble', 'stringr')
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltantes)) stop('Instala los paquetes faltantes: ', paste(faltantes, collapse=', '))
source('R/12_configuracion_rss.R',local=TRUE,encoding='UTF-8')

CARPETA_CRUDOS <- file.path('data', 'crudos')
CARPETA_REPORTES <- 'reportes'
CSV_SALIDA <- file.path(CARPETA_CRUDOS, 'noticias_futbol.csv')
LOG_SALIDA <- file.path(CARPETA_REPORTES, 'log_extracciones.csv')
CONTROL <- file.path(CARPETA_REPORTES, 'ultima_consulta_bbc.rds')
INTERVALO_MINUTOS <- fd_rss_intervalo_minutos()
CACHE_RUTA <- file.path(CARPETA_REPORTES,'cache_rss.rds')
cache_http <- fd_rss_cache(CACHE_RUTA)

# Fuentes oficiales por seccion. No se consultan paginas individuales.
FEEDS <- c(
  'BBC Sport Football' = 'https://feeds.bbci.co.uk/sport/football/rss.xml',
  'BBC Sport European Football' = 'https://feeds.bbci.co.uk/sport/football/european/rss.xml'
)

dir.create(CARPETA_CRUDOS, recursive=TRUE, showWarnings=FALSE)
dir.create(CARPETA_REPORTES, recursive=TRUE, showWarnings=FALSE)

columnas <- c('url', 'titulo', 'fecha_publicacion_utc', 'medio', 'idioma',
              'pais_fuente', 'imagen_url', 'fecha_extraccion_utc', 'fuente', 'resumen')
base_vacia <- function() {
  tibble::as_tibble(as.data.frame(setNames(
    replicate(length(columnas), character(0), simplify=FALSE), columnas),
    stringsAsFactors=FALSE))
}
leer_csv <- function(path, vacio) {
  if (!file.exists(path)) return(vacio)
  x <- readr::read_csv(path, show_col_types=FALSE,
                       col_types=readr::cols(.default=readr::col_character()),
                       locale=readr::locale(encoding='UTF-8'))
  for (cl in setdiff(names(vacio), names(x))) x[[cl]] <- NA_character_
  dplyr::select(x, dplyr::all_of(names(vacio)))
}
texto_xml <- function(nodo, xpath) {
  hijo <- xml2::xml_find_first(nodo, xpath)
  if (inherits(hijo, 'xml_missing')) return(NA_character_)
  val <- xml2::xml_text(hijo, trim=TRUE)
  if (!nzchar(val)) NA_character_ else val
}
fecha_rss <- function(x) {
  # Independiente del idioma regional de Windows. BBC entrega meses ingleses.
  if (is.na(x) || !nzchar(trimws(x))) return(NA_character_)
  x <- trimws(x)
  x <- sub('^(Mon|Tue|Wed|Thu|Fri|Sat|Sun),?\\s+', '', x, ignore.case=TRUE)
  patron <- '^([0-9]{1,2})\\s+([A-Za-z]{3})\\s+([0-9]{4})\\s+([0-9]{2}:[0-9]{2})(:[0-9]{2})?\\s+(GMT|UTC|[+-][0-9]{4})$'
  m <- regmatches(x, regexec(patron, x, ignore.case=TRUE))[[1]]
  if (length(m) != 7L) return(NA_character_)
  meses <- c(Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6,
             Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12)
  mes <- unname(meses[match(tolower(m[3]), tolower(names(meses)))])
  if (is.na(mes)) return(NA_character_)
  hora <- paste0(m[5], if (nzchar(m[6])) m[6] else ':00')
  iso <- sprintf('%04d-%02d-%02d %s', as.integer(m[4]), mes,
                 as.integer(m[2]), hora)
  base <- suppressWarnings(as.POSIXct(iso, format='%Y-%m-%d %H:%M:%S', tz='UTC'))
  if (is.na(base)) return(NA_character_)
  zona <- toupper(m[7])
  desplazamiento <- 0
  if (grepl('^[+-][0-9]{4}$', zona)) {
    signo <- if (substr(zona,1,1)=='+') 1 else -1
    h <- as.integer(substr(zona,2,3))
    min <- as.integer(substr(zona,4,5))
    if (h > 23 || min > 59) return(NA_character_)
    desplazamiento <- signo * (h*3600 + min*60)
  }
  format(base-desplazamiento, '%Y-%m-%d %H:%M:%S', tz='UTC')
}

extraer_feed <- function(nombre, url) {
  req <- httr2::request(url) |>
    httr2::req_user_agent('FootDataAI/1.0 (proyecto academico; RSS; consultas espaciadas)') |>
    httr2::req_timeout(25) |>
    httr2::req_error(is_error=function(resp) FALSE)
  anterior <- cache_http$feeds[[nombre]]
  if (!is.null(anterior$etag)) req <- httr2::req_headers(req,`If-None-Match`=anterior$etag)
  if (!is.null(anterior[['last-modified']])) req <- httr2::req_headers(req,`If-Modified-Since`=anterior[['last-modified']])
  resp <- tryCatch(httr2::req_perform(req), error=function(e) e)
  if (inherits(resp, 'error')) {
    cache_http <<- fd_rss_guardar_respuesta(cache_http,nombre,0L)
    warning('No se pudo consultar ', nombre, ': ', conditionMessage(resp))
    return(list(estado='CONEXION', datos=base_vacia()))
  }
  codigo <- httr2::resp_status(resp)
  headers <- as.list(httr2::resp_headers(resp))
  cache_http <<- fd_rss_guardar_respuesta(cache_http,nombre,codigo,headers)
  if (codigo==304L) return(list(estado='304',datos=base_vacia()))
  if (codigo != 200L) {
    warning(nombre, ': HTTP ', codigo, '. No se reintentara.')
    return(list(estado=as.character(codigo), datos=base_vacia()))
  }
  doc <- tryCatch(xml2::read_xml(httr2::resp_body_raw(resp)), error=function(e) e)
  if (inherits(doc, 'error')) {
    warning(nombre, ': XML no valido: ', conditionMessage(doc))
    return(list(estado='XML_INVALIDO', datos=base_vacia()))
  }
  items <- xml2::xml_find_all(doc, '//channel/item')
  ttl <- texto_xml(xml2::xml_find_first(doc,'//channel'),'./ttl')
  cache_http <<- fd_rss_guardar_respuesta(cache_http,nombre,codigo,headers,ttl)
  if (!length(items)) {
    warning(nombre, ': RSS sin elementos item.')
    return(list(estado='SIN_ITEMS', datos=base_vacia()))
  }
  data <- lapply(items, function(item) {
    link <- texto_xml(item, './link')
    title <- texto_xml(item, './title')
    desc <- texto_xml(item, './description')
    pub <- fecha_rss(texto_xml(item, './pubDate'))
    tibble::tibble(
      url=link,
      titulo=title,
      fecha_publicacion_utc=pub,
      medio='BBC Sport',
      idioma='English',
      pais_fuente='United Kingdom',
      imagen_url=NA_character_,
      fecha_extraccion_utc=format(Sys.time(), '%Y-%m-%d %H:%M:%S', tz='UTC'),
      fuente=nombre,
      resumen=desc
    )
  })
  datos <- dplyr::bind_rows(data) |>
    dplyr::mutate(url=stringr::str_trim(url),
                  titulo=stringr::str_squish(titulo),
                  resumen=stringr::str_squish(resumen)) |>
    dplyr::filter(!is.na(url), nzchar(url), !is.na(titulo), nzchar(titulo)) |>
    dplyr::distinct(url, .keep_all=TRUE)
  list(estado='200', datos=datos)
}

cat('\nFOOTDATA AI - Extraccion RSS de futbol\n')
acumulado <- leer_csv(CSV_SALIDA, base_vacia())
datos_previos <- acumulado
cat('Noticias guardadas previamente:', nrow(acumulado), '\n')

plan <- fd_rss_plan(cache=cache_http,intervalo=INTERVALO_MINUTOS)
if (plan$cooldownSeconds>0) {
  cat(sprintf('Se omite consulta: faltan %.1f minutos. %s\n',plan$cooldownSeconds/60,plan$cooldownReason))
  cat('Archivo disponible:',CSV_SALIDA,'\n')
  quit(save='no',status=0)
}
# Contabilizar intentos fallidos para no sobrecargar el servidor.
saveRDS(Sys.time(), CONTROL)

resultados <- list()
estados <- character()
for (i in seq_along(FEEDS)) {
  if (i > 1L) Sys.sleep(3)
  nombre <- names(FEEDS)[i]
  cat('Consultando:', nombre, '\n')
  r <- extraer_feed(nombre, FEEDS[[i]])
  saveRDS(cache_http,CACHE_RUTA)
  estados <- c(estados, paste0(nombre, ':', r$estado))
  resultados[[i]] <- r$datos
  if (r$estado %in% c('429','403')) {
    cat('El servidor limita el acceso. Se detienen las consultas.\n')
    break
  }
}

extraidas <- dplyr::bind_rows(resultados) |>
  dplyr::distinct(url, .keep_all=TRUE)
nuevas <- dplyr::filter(extraidas, !(url %in% acumulado$url))
# Actualizar metadatos de URLs existentes (especialmente fechas antes vacias).
# Los datos del RSS fresco prevalecen cuando son informativos.
if (nrow(extraidas)) {
  acumulado <- acumulado |>
    dplyr::filter(!(url %in% extraidas$url))
}
consolidado <- dplyr::bind_rows(acumulado, extraidas) |>
  dplyr::distinct(url, .keep_all=TRUE)

# Crear CSV solo cuando haya datos (nuevos o historicos).
if (nrow(consolidado) && !fd_rss_mismos_datos(datos_previos,consolidado)) {
  readr::write_excel_csv(consolidado, CSV_SALIDA, na='')
} else if (nrow(consolidado)) {
  cat('El contenido RSS no cambio. Se conserva el CSV sin volver a escribirlo.\n')
} else {
  cat('No llegaron noticias validas. No se creo un CSV vacio.\n')
}

registro <- tibble::tibble(
  fecha_utc=format(Sys.time(), '%Y-%m-%d %H:%M:%S', tz='UTC'),
  http=paste(estados, collapse='; '),
  recibidas=as.character(nrow(extraidas)),
  nuevas=as.character(nrow(nuevas)),
  acumuladas=as.character(nrow(consolidado))
)
log_anterior <- leer_csv(LOG_SALIDA, registro[0,])
readr::write_excel_csv(dplyr::bind_rows(log_anterior, registro), LOG_SALIDA, na='')

cat('\n===== RESUMEN DE LA EXTRACCION =====\n')
cat('Noticias recibidas:',nrow(extraidas),'\n')
cat('Noticias nuevas:',nrow(nuevas),'\n')
cat('Noticias acumuladas:',nrow(consolidado),'\n')
cat('Estado:',paste(estados,collapse='; '),'\n')
cat('CSV:',CSV_SALIDA,'\n')
cat('Log:',LOG_SALIDA,'\n')
if (nrow(nuevas)) print(utils::head(dplyr::select(nuevas, titulo, fecha_publicacion_utc), 5))
if (!any(grepl(':(200|304)$', estados))) {
  stop('Ningun canal RSS respondio correctamente. Se conservaron las noticias existentes; revisa el log de extraccion.')
}
