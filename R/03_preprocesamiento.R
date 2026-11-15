# =============================================================================
# FOOTDATA AI | FASE 4: PREPROCESAMIENTO Y CALIDAD DE NOTICIAS
# Ejecutar desde la carpeta principal: Rscript R/03_preprocesamiento.R
# Entrada: data/futbol.sqlite (tabla noticias; fase 3)
# Salidas: data/procesados/ y reportes/fase4/
# No cambia ni elimina registros de SQLite ni del CSV crudo.
# =============================================================================

paquetes <- c('DBI','RSQLite','dplyr','readr','stringr','tibble','tidyr',
              'tidytext','stopwords','ggplot2')
faltantes <- paquetes[!vapply(paquetes,requireNamespace,logical(1),quietly=TRUE)]
if (length(faltantes)) stop('Instala estos paquetes: ', paste(faltantes,collapse=', '),
                            '\nEjemplo: install.packages(c(',paste(sprintf('"%s"',faltantes),collapse=', '),'))')

ruta_db <- file.path('data','futbol.sqlite')
if (!file.exists(ruta_db)) stop('No existe ',ruta_db,'. Ejecuta la fase 3 primero.')
carpeta_procesados <- file.path('data','procesados')
carpeta_reporte <- file.path('reportes','fase4')
dir.create(carpeta_procesados, recursive=TRUE, showWarnings=FALSE)
dir.create(carpeta_reporte, recursive=TRUE, showWarnings=FALSE)
guardar <- function(datos, ruta) readr::write_excel_csv(datos,ruta,na='')

cat('\n====================================================\n')
cat(' FOOTDATA AI | FASE 4 - PREPROCESAMIENTO\n')
cat('====================================================\n')
con <- DBI::dbConnect(RSQLite::SQLite(),ruta_db)
# Conexion cerrada despues de leer: el procesamiento posterior es sobre copias locales.
if (!DBI::dbExistsTable(con,'noticias')) stop('Falta la tabla noticias en SQLite.')
noticias <- DBI::dbGetQuery(con,'SELECT id, url, titulo, resumen, medio, fuente, idioma, pais_fuente, fecha_publicacion_utc, fecha_extraccion_utc FROM noticias ORDER BY id')
DBI::dbDisconnect(con)
if (!nrow(noticias)) stop('La tabla noticias esta vacia.')
requeridas <- c('id','url','titulo','resumen','fecha_publicacion_utc','fecha_extraccion_utc')
if (length(f <- setdiff(requeridas,names(noticias)))) stop('Columnas faltantes: ',paste(f,collapse=', '))

# Limpieza y normalizacion: texto original no se altera.
limpiar_campo <- function(x) {
  x <- as.character(x)
  x <- stringr::str_replace_all(x,'<[^>]+>',' ')
  x <- stringr::str_replace_all(x,'&amp;','&')
  x <- stringr::str_replace_all(x,'&quot;','"')
  x <- stringr::str_replace_all(x,'&#39;|&apos;',"'")
  x <- stringr::str_replace_all(x,'&nbsp;',' ')
  x <- stringr::str_squish(x)
  x[is.na(x) | !nzchar(x)] <- NA_character_
  x
}
normalizar <- function(x) {
  x <- limpiar_campo(x)
  x <- stringr::str_to_lower(x,locale='en')
  x <- iconv(x,from='',to='ASCII//TRANSLIT',sub='')
  x <- stringr::str_replace_all(x,'https?://\\S+',' ')
  x <- stringr::str_replace_all(x,'[^a-z0-9 ]',' ')
  stringr::str_squish(x)
}
fecha_valida <- function(x) {
  x <- as.character(x)
  x[!grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2}:[0-9]{2})?$',x) | is.na(x)] <- NA_character_
  x
}

noticias <- noticias |>
  dplyr::mutate(
    titulo_limpio=limpiar_campo(titulo),
    resumen_limpio=limpiar_campo(resumen),
    texto_normalizado=normalizar(paste(dplyr::coalesce(titulo,''),dplyr::coalesce(resumen,''))),
    fecha_publicacion_utc=fecha_valida(fecha_publicacion_utc),
    fecha_extraccion_utc=fecha_valida(fecha_extraccion_utc)
  )
# Categoria principal (reglas transparentes; no son resultados oficiales de BBC).
# Las expresiones se aplican al titular + resumen y las categorias no son excluyentes.
patrones <- list(
  fichajes='\\b(transfer|transfers|signing|signed|signs|deal|bid|loan|contract|free agent|release clause)\\b',
  champions='\\b(champions league|uefa champions|ucl)\\b',
  premier_league='\\b(premier league|english premier|epl)\\b',
  laliga='\\b(la liga|laliga|spanish league)\\b',
  mundial='\\b(world cup|fifa world cup|world championship)\\b',
  selecciones='\\b(international|national team|england|spain|brazil|argentina|france|germany)\\b',
  lesiones='\\b(injury|injured|fitness|sidelined|hamstring|knee injury)\\b',
  partidos='\\b(match|fixture|win|wins|lost|defeat|draw|goal|goals|final|semi final)\\b'
)
for (categoria in names(patrones)) {
  noticias[[paste0('tema_',categoria)]] <- stringr::str_detect(
    dplyr::coalesce(noticias$texto_normalizado,''),patrones[[categoria]])
}
columnas_tema <- paste0('tema_',names(patrones))
noticias$n_temas <- rowSums(as.data.frame(noticias[,columnas_tema,drop=FALSE]))
noticias$tema_principal <- vapply(seq_len(nrow(noticias)),function(i) {
  encontrados <- names(patrones)[as.logical(unlist(noticias[i,columnas_tema,drop=FALSE],use.names=FALSE))]
  if (!length(encontrados)) 'sin_clasificar' else encontrados[[1]]
},character(1))
noticias$fecha_dia <- as.Date(substr(noticias$fecha_publicacion_utc,1,10),format='%Y-%m-%d')

# Tokenizacion en ingles: se mantiene el archivo crudo y se generan derivados.
tokens <- noticias |>
  dplyr::select(id,texto_normalizado) |>
  tidytext::unnest_tokens(palabra,texto_normalizado,token='words') |>
  dplyr::filter(!is.na(palabra),stringr::str_detect(palabra,'^[a-z]{3,}$'))
stop_en <- unique(c(stopwords::stopwords('en'),
  'bbc','sport','sports','says','said','could','would','also','one','two','three','new',
  'get','gets','got','will','year','years','today','week'))
tokens <- tokens |> dplyr::filter(!palabra %in% stop_en)
frecuencia <- tokens |>
  dplyr::count(palabra,name='frecuencia',sort=TRUE)
tokens_por_noticia <- tokens |>
  dplyr::count(id,name='cantidad_tokens')
noticias <- noticias |>
  dplyr::left_join(tokens_por_noticia,by='id') |>
  dplyr::mutate(cantidad_tokens=dplyr::coalesce(cantidad_tokens,0L))

# Indicadores y reportes de calidad.
indicadores <- tibble::tibble(
  indicador=c('noticias_sqlite','urls_duplicadas','sin_titulo','sin_resumen',
              'sin_fecha_publicacion','con_fecha_publicacion',
              'sin_fecha_extraccion','sin_tema_detectado',
              'sin_tokens_validos','tokens_limpios','palabras_distintas',
              'fuentes_distintas'),
  valor=c(nrow(noticias),sum(duplicated(noticias$url)),
          sum(is.na(noticias$titulo_limpio)),sum(is.na(noticias$resumen_limpio)),
          sum(is.na(noticias$fecha_dia)),sum(!is.na(noticias$fecha_dia)),
          sum(is.na(noticias$fecha_extraccion_utc)),sum(noticias$n_temas==0L),
          sum(noticias$cantidad_tokens==0L),nrow(tokens),nrow(frecuencia),
          dplyr::n_distinct(noticias$fuente))
)
resumen_temas <- tibble::tibble(
  tema=names(patrones),
  noticias=vapply(columnas_tema,function(col) sum(noticias[[col]],na.rm=TRUE),integer(1))
) |> dplyr::arrange(dplyr::desc(noticias))
resumen_fuentes <- noticias |>
  dplyr::count(fuente,sort=TRUE,name='noticias')
resumen_idiomas <- noticias |>
  dplyr::count(idioma,sort=TRUE,name='noticias')
resumen_diario <- noticias |>
  dplyr::filter(!is.na(fecha_dia)) |>
  dplyr::count(fecha_dia,sort=FALSE,name='noticias')

# CSV mantenidos separados del registro crudo y de SQLite.
guardar(noticias,file.path(carpeta_procesados,'noticias_preprocesadas.csv'))
guardar(tokens,file.path(carpeta_procesados,'tokens_limpios.csv'))
guardar(indicadores,file.path(carpeta_reporte,'reporte_calidad_fase4.csv'))
guardar(frecuencia,file.path(carpeta_reporte,'palabras_frecuentes.csv'))
guardar(resumen_temas,file.path(carpeta_reporte,'resumen_temas.csv'))
guardar(resumen_fuentes,file.path(carpeta_reporte,'resumen_fuentes.csv'))
guardar(resumen_idiomas,file.path(carpeta_reporte,'resumen_idiomas.csv'))
guardar(resumen_diario,file.path(carpeta_reporte,'noticias_por_dia.csv'))

# Dos graficos no temporales: sirven aunque las 82 fechas sigan faltando.
graf_temas <- ggplot2::ggplot(resumen_temas,
    ggplot2::aes(x=stats::reorder(tema,noticias),y=noticias)) +
  ggplot2::geom_col(fill='#2563eb') +
  ggplot2::coord_flip() +
  ggplot2::labs(title='Noticias por tema detectado',
    subtitle='Una noticia puede pertenecer a varios temas',x=NULL,y='Noticias') +
  ggplot2::theme_minimal(base_size=12)
ggplot2::ggsave(file.path(carpeta_reporte,'grafico_temas.png'),graf_temas,
                width=9,height=5,dpi=140)
if (nrow(frecuencia)) {
  graf_palabras <- ggplot2::ggplot(utils::head(frecuencia,20),
      ggplot2::aes(x=stats::reorder(palabra,frecuencia),y=frecuencia)) +
    ggplot2::geom_col(fill='#0f766e') + ggplot2::coord_flip() +
    ggplot2::labs(title='20 palabras mas frecuentes',x=NULL,y='Frecuencia') +
    ggplot2::theme_minimal(base_size=12)
  ggplot2::ggsave(file.path(carpeta_reporte,'grafico_palabras.png'),graf_palabras,
                  width=9,height=6,dpi=140)
}

cat('\n===== REPORTE FASE 4 =====\n')
print(indicadores,n=Inf)
cat('\nTemas detectados:\n')
print(resumen_temas,n=Inf)
cat('\nTop 15 palabras:\n')
print(utils::head(frecuencia,15))
if (all(is.na(noticias$fecha_dia))) {
  cat('\nAVISO: todas las fechas de publicacion son NA.\n')
  cat('No se calculan tendencias por fecha. Ejecuta nuevamente el extractor\n')
  cat('corregido y luego la fase 3 cuando venza el intervalo del RSS.\n')
}
cat('\nDatos: ',file.path(carpeta_procesados,'noticias_preprocesadas.csv'),'\n',sep='')
cat('Reportes: ',carpeta_reporte,'\n',sep='')
cat('FASE 4 COMPLETADA\n')
