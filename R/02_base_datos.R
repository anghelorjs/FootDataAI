# ============================================================================
# FOOTDATA AI | FASE 3 - IMPORTACION Y CONSULTAS EN SQLITE
# Ejecutar desde la raiz del proyecto: Rscript R/02_base_datos.R
# Entrada:  data/crudos/noticias_futbol.csv (RSS BBC Sport)
# Salidas:  data/futbol.sqlite, reportes/reporte_fase3.csv,
#           reportes/noticias_recientes.csv, reportes/noticias_por_dia.csv,
#           reportes/noticias_por_fuente.csv, reportes/calidad_fechas.csv
# ============================================================================

paquetes <- c('DBI', 'RSQLite', 'readr', 'dplyr', 'tibble', 'stringr')
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltantes)) stop('Instala paquetes: ', paste(faltantes, collapse = ', '))

entrada <- file.path('data', 'crudos', 'noticias_futbol.csv')
base_sqlite <- file.path('data', 'futbol.sqlite')
dir.create('data', recursive=TRUE, showWarnings=FALSE)
dir.create('reportes', recursive=TRUE, showWarnings=FALSE)
if (!file.exists(entrada)) stop('No existe ', entrada, '. Ejecuta primero R/01_extraccion.R')

cat('\nFOOTDATA AI - FASE 3 | BASE DE DATOS SQLITE\n')
noticias <- readr::read_csv(
  entrada, show_col_types=FALSE,
  col_types=readr::cols(.default=readr::col_character()),
  locale=readr::locale(encoding='UTF-8'), progress=FALSE
)
requeridas <- c('url', 'titulo', 'fecha_publicacion_utc', 'medio',
                'idioma', 'pais_fuente', 'imagen_url', 'fecha_extraccion_utc',
                'fuente', 'resumen')
faltantes_csv <- setdiff(requeridas, names(noticias))
if (length(faltantes_csv)) stop('Faltan columnas en CSV: ', paste(faltantes_csv,collapse=', '))

# Tratar vacios como NULL y limpiar texto sin modificar el archivo crudo.
limpiar <- function(x) {
  x <- as.character(x)
  x <- stringr::str_squish(x)
  x[is.na(x) | !nzchar(x)] <- NA_character_
  x
}
for (cl in requeridas) noticias[[cl]] <- limpiar(noticias[[cl]])
# URL canonica basica: elimina fragmentos y barras finales del path.
# No quitar parametros arbitrarios: pueden identificar articulos distintos.
noticias$url <- sub('#.*$', '', noticias$url)
noticias$url <- sub('/+$', '', noticias$url)

# Fechas almacenadas en UTC como texto ISO 8601; NA permanece NA.
fecha_iso <- function(x) {
  x <- limpiar(x)
  if (!length(x)) return(x)
  x <- sub('T', ' ', x, fixed=TRUE)
  x <- sub('Z$', '', x)
  # El RSS corregido entrega YYYY-mm-dd HH:MM:SS.
  es_formato <- !is.na(x) & grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2}:[0-9]{2})?$', x)
  es_fecha <- rep(FALSE, length(x))
  if (any(es_formato)) {
    candidatos <- x[es_formato]
    candidatos[nchar(candidatos)==10L] <- paste0(candidatos[nchar(candidatos)==10L], ' 00:00:00')
    convertidas <- suppressWarnings(as.POSIXct(candidatos, format='%Y-%m-%d %H:%M:%S', tz='UTC'))
    es_fecha[which(es_formato)] <- !is.na(convertidas)
  }
  x[!es_fecha] <- NA_character_
  x
}

noticias$fecha_publicacion_utc <- fecha_iso(noticias$fecha_publicacion_utc)
noticias$fecha_extraccion_utc <- fecha_iso(noticias$fecha_extraccion_utc)

filas_csv <- nrow(noticias)
invalidas <- sum(is.na(noticias$url) | !grepl('^https?://', noticias$url) |
                   is.na(noticias$titulo))
noticias <- noticias[!is.na(noticias$url) & grepl('^https?://', noticias$url) &
                       !is.na(noticias$titulo), , drop=FALSE]
# Conservar el ultimo registro de cada URL en caso de duplicados.
noticias <- noticias[!duplicated(noticias$url, fromLast=TRUE), , drop=FALSE]

con <- DBI::dbConnect(RSQLite::SQLite(), base_sqlite)
DBI::dbExecute(con, 'PRAGMA busy_timeout = 5000')
DBI::dbExecute(con, 'PRAGMA foreign_keys = ON')

DBI::dbExecute(con, "
CREATE TABLE IF NOT EXISTS noticias (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url TEXT NOT NULL UNIQUE,
  titulo TEXT NOT NULL,
  fecha_publicacion_utc TEXT,
  medio TEXT,
  idioma TEXT,
  pais_fuente TEXT,
  imagen_url TEXT,
  fecha_extraccion_utc TEXT,
  fuente TEXT,
  resumen TEXT,
  fecha_importacion_utc TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now'))
)")
DBI::dbExecute(con, 'CREATE INDEX IF NOT EXISTS idx_noticias_fecha ON noticias(fecha_publicacion_utc)')
DBI::dbExecute(con, 'CREATE INDEX IF NOT EXISTS idx_noticias_medio ON noticias(medio)')
DBI::dbExecute(con, 'CREATE INDEX IF NOT EXISTS idx_noticias_fuente ON noticias(fuente)')
DBI::dbExecute(con, "
CREATE TABLE IF NOT EXISTS historial_importaciones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha_utc TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')),
  filas_csv INTEGER NOT NULL,
  validas_unicas INTEGER NOT NULL,
  insertadas INTEGER NOT NULL,
  total_sqlite INTEGER NOT NULL,
  sin_fecha_publicacion INTEGER NOT NULL
)")

DBI::dbBegin(con)
resultado <- tryCatch({
  total_previo <- DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM noticias')$n[[1]]
  consulta <- paste0(
    'INSERT INTO noticias (', paste(requeridas,collapse=', '), ') VALUES (',
    paste(rep('?',length(requeridas)),collapse=', '), ') ',
    'ON CONFLICT(url) DO UPDATE SET ',
    'titulo=excluded.titulo, ',
    'fecha_publicacion_utc=COALESCE(excluded.fecha_publicacion_utc, noticias.fecha_publicacion_utc), ',
    'medio=COALESCE(excluded.medio, noticias.medio), ',
    'idioma=COALESCE(excluded.idioma, noticias.idioma), ',
    'pais_fuente=COALESCE(excluded.pais_fuente, noticias.pais_fuente), ',
    'imagen_url=COALESCE(excluded.imagen_url, noticias.imagen_url), ',
    'fecha_extraccion_utc=COALESCE(excluded.fecha_extraccion_utc, noticias.fecha_extraccion_utc), ',
    'fuente=COALESCE(excluded.fuente, noticias.fuente), ',
    'resumen=COALESCE(excluded.resumen, noticias.resumen)'
  )
  if (nrow(noticias)) {
    # SQLite maneja NA_character_ como NULL.
    for (i in seq_len(nrow(noticias))) {
      DBI::dbExecute(con, consulta, params=unname(as.list(noticias[i,requeridas,drop=FALSE])))
    }
  }
  total <- DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM noticias')$n[[1]]
  sin_fecha <- DBI::dbGetQuery(con,
    'SELECT COUNT(*) AS n FROM noticias WHERE fecha_publicacion_utc IS NULL')$n[[1]]
  DBI::dbExecute(con, paste0(
    'INSERT INTO historial_importaciones ',
    '(filas_csv, validas_unicas, insertadas, total_sqlite, sin_fecha_publicacion) ',
    'VALUES (?, ?, ?, ?, ?)'),
    params=list(filas_csv,nrow(noticias),total-total_previo,total,sin_fecha))
  DBI::dbCommit(con)
  list(total=total, nuevas=total-total_previo, sin_fecha=sin_fecha)
}, error=function(e) {
  DBI::dbRollback(con)
  stop('Error al importar (se revirtieron cambios): ', conditionMessage(e))
})

# Exportaciones útiles para revisión y futuras fases.
recientes <- DBI::dbGetQuery(con, "
  SELECT id, titulo, fecha_publicacion_utc, medio, fuente, url
  FROM noticias ORDER BY COALESCE(fecha_publicacion_utc, fecha_extraccion_utc) DESC LIMIT 20
")
por_dia <- DBI::dbGetQuery(con, "
  SELECT SUBSTR(fecha_publicacion_utc,1,10) AS fecha_utc, COUNT(*) AS noticias
  FROM noticias WHERE fecha_publicacion_utc IS NOT NULL
  GROUP BY SUBSTR(fecha_publicacion_utc,1,10) ORDER BY fecha_utc
")
por_fuente <- DBI::dbGetQuery(con, "
  SELECT fuente, COUNT(*) AS noticias FROM noticias
  GROUP BY fuente ORDER BY noticias DESC
")
calidad <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS total,
    SUM(CASE WHEN fecha_publicacion_utc IS NULL THEN 1 ELSE 0 END) AS sin_fecha_publicacion,
    SUM(CASE WHEN fecha_extraccion_utc IS NULL THEN 1 ELSE 0 END) AS sin_fecha_extraccion,
    COUNT(DISTINCT url) AS urls_unicas
  FROM noticias
")
reporte <- tibble::tibble(
  indicador=c('filas_csv','filas_descartadas_sin_url_o_titulo',
              'filas_validas_unicas_csv','nuevas_insertadas_en_esta_ejecucion',
              'total_noticias_sqlite','sin_fecha_publicacion_sqlite',
              'con_fecha_publicacion_sqlite'),
  valor=c(filas_csv,invalidas,nrow(noticias),resultado$nuevas,
          resultado$total,resultado$sin_fecha,resultado$total-resultado$sin_fecha)
)
readr::write_excel_csv(reporte,'reportes/reporte_fase3.csv')
readr::write_excel_csv(recientes,'reportes/noticias_recientes.csv')
readr::write_excel_csv(por_dia,'reportes/noticias_por_dia.csv')
readr::write_excel_csv(por_fuente,'reportes/noticias_por_fuente.csv')
readr::write_excel_csv(calidad,'reportes/calidad_fechas.csv')

cat('\n===== REPORTE FASE 3 =====\n')
print(reporte,n=Inf)
cat('\nNoticias por fuente:\n')
print(por_fuente)
cat('\nPrimeras noticias de la base:\n')
print(utils::head(recientes[,c('titulo','fecha_publicacion_utc')],5))
if (resultado$sin_fecha > 0L) {
  cat('\nAVISO: ',resultado$sin_fecha,' noticias carecen de fecha de publicacion.\n',sep='')
  cat('No se reemplazaron por la fecha de extraccion. Corrige el lector RSS\n')
  cat('y vuelve a extraer e importar para completar las fechas disponibles.\n')
}
cat('\nSQLite:',base_sqlite,'\n')
cat('Reportes: reportes/reporte_fase3.csv y otros 4 CSV\n')
DBI::dbDisconnect(con)
cat('FASE 3 COMPLETADA\n')
