# ============================================================================
# FOOTDATA AI | FASE 2 - RSS DE BBC SPORT (ALTERNATIVA A GDELT)
# Ejecutar desde la raiz de FootDataAI: Rscript R/01_extraccion.R
# Solo metadatos del RSS: titulo, resumen, fecha, URL y fuente.
# ============================================================================

paquetes <- c('httr2', 'xml2', 'dplyr', 'readr', 'tibble', 'stringr')
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltantes)) stop('Instala los paquetes faltantes: ', paste(faltantes, collapse=', '))

CARPETA_CRUDOS <- file.path('data', 'crudos')
CARPETA_REPORTES <- 'reportes'
CSV_SALIDA <- file.path(CARPETA_CRUDOS, 'noticias_futbol.csv')
LOG_SALIDA <- file.path(CARPETA_REPORTES, 'log_extracciones.csv')
CONTROL <- file.path(CARPETA_REPORTES, 'ultima_consulta_bbc.rds')
INTERVALO_MINUTOS <- 60

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
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  x <- trimws(x)
  # RSS 2.0: Sun, 15 Nov 2026 12:30:00 GMT o con offset +0000
  x <- sub(' GMT$', ' +0000', x)
  x <- sub(' UTC$', ' +0000', x)
  formats <- c('%a, %d %b %Y %H:%M:%S %z',
               '%d %b %Y %H:%M:%S %z',
               '%a, %d %b %Y %H:%M %z')
  for (fmt in formats) {
    fecha <- suppressWarnings(as.POSIXct(x, format=fmt, tz='UTC'))
    if (!is.na(fecha)) return(format(fecha, '%Y-%m-%d %H:%M:%S', tz='UTC'))
  }
  NA_character_
}

extraer_feed <- function(nombre, url) {
  req <- httr2::request(url) |>
    httr2::req_user_agent('FootDataAI/1.0 (proyecto academico; RSS; consultas espaciadas)') |>
    httr2::req_timeout(25) |>
    httr2::req_error(is_error=function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error=function(e) e)
  if (inherits(resp, 'error')) {
    warning('No se pudo consultar ', nombre, ': ', conditionMessage(resp))
    return(list(estado='CONEXION', datos=base_vacia()))
  }
  codigo <- httr2::resp_status(resp)
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
cat('Noticias guardadas previamente:', nrow(acumulado), '\n')

if (file.exists(CONTROL)) {
  anterior <- tryCatch(readRDS(CONTROL), error=function(e) NULL)
  if (inherits(anterior, 'POSIXct')) {
    min_pasados <- as.numeric(difftime(Sys.time(), anterior, units='mins'))
    if (is.finite(min_pasados) && min_pasados >= 0 && min_pasados < INTERVALO_MINUTOS) {
      cat(sprintf('Se omite consulta: faltan %.1f minutos para el proximo intento.\n',
                  INTERVALO_MINUTOS-min_pasados))
      cat('Archivo disponible:', CSV_SALIDA, '\n')
      quit(save='no',status=0)
    }
  }
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
consolidado <- dplyr::bind_rows(acumulado, nuevas) |>
  dplyr::distinct(url, .keep_all=TRUE)

# Crear CSV solo cuando haya datos (nuevos o historicos).
if (nrow(consolidado)) {
  readr::write_excel_csv(consolidado, CSV_SALIDA, na='')
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
