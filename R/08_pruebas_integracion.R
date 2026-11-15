# =============================================================================
# FOOTDATA AI | FASE 9 - PRUEBAS E INTEGRACION (SIN INTERNET)
# Desde la raiz del proyecto: Rscript R/08_pruebas_integracion.R
# No altera datos existentes, no llama a BBC y no inicia app.R.
# =============================================================================

cat('\n====================================================\n')
cat(' FOOTDATA AI | FASE 9 - PRUEBAS E INTEGRACION\n')
cat('====================================================\n\n')

paquetes <- c('readr','DBI','RSQLite')
faltan <- paquetes[!vapply(paquetes,requireNamespace,logical(1),quietly=TRUE)]
if (length(faltan)) stop('Instala primero estos paquetes: ',paste(faltan,collapse=', '))
if (!dir.exists('R') || !dir.exists('data')) stop('Ejecuta desde la raiz de FootDataAI.')

salida <- 'reportes/fase9'
dir.create(salida,recursive=TRUE,showWarnings=FALSE)
resultados <- list()
registrar <- function(grupo,prueba,ok,detalle='') {
  resultados[[length(resultados)+1L]] <<- data.frame(
    grupo=grupo,prueba=prueba,estado=if (isTRUE(ok)) 'OK' else 'FALLO',
    detalle=as.character(detalle),stringsAsFactors=FALSE
  )
  cat(sprintf('[%-5s] %s | %s\n',if (isTRUE(ok)) 'OK' else 'FALLO',grupo,prueba))
}
chequear <- function(grupo,prueba,codigo) {
  tryCatch({
    valor <- force(codigo)
    if (is.list(valor) && !is.null(valor$ok)) registrar(grupo,prueba,valor$ok,
      if (is.null(valor$detalle)) '' else valor$detalle)
    else registrar(grupo,prueba,isTRUE(valor),if (isTRUE(valor)) '' else 'Condicion no satisfecha')
  },error=function(e) registrar(grupo,prueba,FALSE,conditionMessage(e)))
}
leer <- function(path) readr::read_csv(path,show_col_types=FALSE,
  col_types=readr::cols(.default=readr::col_character()),
  locale=readr::locale(encoding='UTF-8'),progress=FALSE)
vacio <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))

rutas <- c(
  'app.R','R/01_extraccion.R','R/02_base_datos.R',
  'R/03_preprocesamiento.R','R/04_mineria_datos.R',
  'R/05_chatbot.R','R/06_actualizacion.R',
  'data/crudos/noticias_futbol.csv','data/futbol.sqlite',
  'data/procesados/noticias_preprocesadas.csv',
  'data/procesados/tokens_limpios.csv',
  'data/procesados/mineria_noticias.csv',
  'reportes/fase5/01_frecuencia_palabras.csv',
  'reportes/fase5/02_bigramas.csv',
  'reportes/fase5/09_detalle_menciones_equipos.csv',
  'reportes/fase5/10_detalle_menciones_competiciones.csv'
)
for (ruta in rutas) chequear('Archivos',ruta,file.exists(ruta))

# Valida sintaxis de scripts sin ejecutarlos (especialmente app.R).
for (script in c('app.R',list.files('R',pattern='\\.R$',full.names=TRUE))) {
  chequear('Sintaxis',script, {
    parse(file=script,keep.source=FALSE)
    TRUE
  })
}

raw <- proc <- mineria <- tokens <- NULL
con <- NULL
if (file.exists('data/crudos/noticias_futbol.csv')) {
  raw <- tryCatch(leer('data/crudos/noticias_futbol.csv'),error=function(e) NULL)
}
if (file.exists('data/procesados/noticias_preprocesadas.csv')) {
  proc <- tryCatch(leer('data/procesados/noticias_preprocesadas.csv'),error=function(e) NULL)
}
if (file.exists('data/procesados/mineria_noticias.csv')) {
  mineria <- tryCatch(leer('data/procesados/mineria_noticias.csv'),error=function(e) NULL)
}
if (file.exists('data/procesados/tokens_limpios.csv')) {
  tokens <- tryCatch(leer('data/procesados/tokens_limpios.csv'),error=function(e) NULL)
}

chequear('RSS','CSV legible y con noticias',!is.null(raw) && nrow(raw)>0)
chequear('RSS','URLs no vacias',!is.null(raw) && 'url' %in% names(raw) && !any(vacio(raw$url)))
chequear('RSS','Titulos no vacios',!is.null(raw) && 'titulo' %in% names(raw) && !any(vacio(raw$titulo)))
chequear('RSS','URLs unicas en CSV',!is.null(raw) && 'url' %in% names(raw) && !anyDuplicated(raw$url))
chequear('RSS','Esquema HTTPS/HTTP de URLs',!is.null(raw) && 'url' %in% names(raw) &&
  all(grepl('^https?://',raw$url,ignore.case=TRUE)))

sqlite_total <- NA_integer_
if (file.exists('data/futbol.sqlite')) {
  con <- tryCatch(DBI::dbConnect(RSQLite::SQLite(),dbname='data/futbol.sqlite'),
    error=function(e) NULL)
}
chequear('SQLite','Conexion a base de datos',!is.null(con))
if (!is.null(con)) {
  tablas <- DBI::dbListTables(con)
  chequear('SQLite','Tabla noticias existe','noticias' %in% tablas)
  chequear('SQLite','Tabla historial_importaciones existe','historial_importaciones' %in% tablas)
  if ('noticias' %in% tablas) {
    chequear('SQLite','Conteo de registros',{
      sqlite_total <- as.integer(DBI::dbGetQuery(con,'SELECT COUNT(*) AS n FROM noticias')$n[1])
      list(ok=sqlite_total>0,detalle=paste('Noticias:',sqlite_total))
    })
    chequear('SQLite','Sin URLs duplicadas',{
      repetidas <- DBI::dbGetQuery(con,
        'SELECT COUNT(*) AS n FROM (SELECT url FROM noticias GROUP BY url HAVING COUNT(*) > 1)')$n[1]
      repetidas==0
    })
    chequear('SQLite','Sin titulos ni URL vacios',{
      faltantes <- DBI::dbGetQuery(con,
        "SELECT COUNT(*) AS n FROM noticias WHERE url IS NULL OR TRIM(url)='' OR titulo IS NULL OR TRIM(titulo)=''")$n[1]
      faltantes==0
    })
  }
}

chequear('Integridad','CSV preprocesado legible',!is.null(proc) && nrow(proc)>0)
chequear('Integridad','CSV mineria legible',!is.null(mineria) && nrow(mineria)>0)
chequear('Integridad','CSV tokens legible',!is.null(tokens) && nrow(tokens)>0)
chequear('Integridad','IDs unicos en preprocesamiento',!is.null(proc) && 'id' %in% names(proc) && !anyDuplicated(proc$id))
chequear('Integridad','IDs unicos en mineria',!is.null(mineria) && 'id' %in% names(mineria) && !anyDuplicated(mineria$id))
chequear('Integridad','Coinciden noticias SQLite y fase 4',!is.null(proc) && !is.na(sqlite_total) && nrow(proc)==sqlite_total)
chequear('Integridad','Coinciden noticias fase 4 y 5',!is.null(proc) && !is.null(mineria) &&
  'id' %in% names(proc) && 'id' %in% names(mineria) &&
  setequal(proc$id,mineria$id) && nrow(proc)==nrow(mineria))
chequear('Integridad','Todos los tokens tienen noticia',!is.null(tokens) && !is.null(mineria) &&
  'id' %in% names(tokens) && 'id' %in% names(mineria) && all(tokens$id %in% mineria$id))
chequear('Integridad','Columnas necesarias para el Dashboard',!is.null(mineria) &&
  all(c('id','titulo','url','fecha_publicacion_utc','fuente') %in% names(mineria)))
chequear('Integridad','Columnas de entidades del chatbot',!is.null(mineria) &&
  all(c('equipos_detectados','competiciones_detectadas') %in% names(mineria)))

if (!is.null(mineria) && 'fecha_publicacion_utc' %in% names(mineria)) {
  con_fecha <- !vacio(mineria$fecha_publicacion_utc)
  invalidas <- sum(con_fecha & is.na(as.Date(substr(mineria$fecha_publicacion_utc,1,10),format='%Y-%m-%d')))
  chequear('Calidad','Fechas presentes con formato valido',
    list(ok=invalidas==0,detalle=paste('Fechas invalidas:',invalidas,
      '| Sin fecha:',sum(!con_fecha))))
  registrar('Calidad','Porcentaje con fecha (informativo)',TRUE,
    sprintf('%.1f%%',100*mean(con_fecha)))
}

# Pruebas reales del motor sin red. Se ejecutan sobre el CSV producido en fase 5.
if (file.exists('R/05_chatbot.R') && !is.null(mineria) && nrow(mineria)>0) {
  motor <- new.env(parent=globalenv())
  cargado <- tryCatch({sys.source('R/05_chatbot.R',envir=motor); TRUE},error=function(e) FALSE)
  chequear('Chatbot','Motor cargado',cargado)
  if (cargado && exists('fd_chatbot_responder',envir=motor,inherits=FALSE)) {
    preguntas <- list(
      'Ultimas noticias'='ultimas noticias',
      'Total de noticias'='cuantas noticias hay',
      'Ranking de equipos'='que equipos aparecen mas',
      'Busqueda imposible'='noticias sobre xqzvpruebainexistente'
    )
    for (nombre in names(preguntas)) {
      pregunta <- preguntas[[nombre]]
      chequear('Chatbot',nombre,{
        r <- motor$fd_chatbot_responder(pregunta,mineria)
        list(ok=is.list(r) && is.character(r$texto) && length(r$texto)==1 &&
          nzchar(r$texto) && is.data.frame(r$noticias),detalle=substr(r$texto,1,160))
      })
    }
    chequear('Chatbot','Ultimas noticias con enlaces HTTPS/HTTP',{
      r <- motor$fd_chatbot_responder('ultimas noticias',mineria)
      nrow(r$noticias)>0 && 'url' %in% names(r$noticias) &&
        all(grepl('^https?://',r$noticias$url,ignore.case=TRUE))
    })
    chequear('Chatbot','Conteo coincide con la base cargada',{
      r <- motor$fd_chatbot_responder('cuantas noticias hay',mineria)
      grepl(as.character(nrow(mineria)),r$texto,fixed=TRUE)
    })
    chequear('Chatbot','Limite de resultados respetado',{
      r <- motor$fd_chatbot_responder('ultimas noticias',mineria,max_resultados=3)
      nrow(r$noticias)<=3
    })
  }
}

# La actualizacion ya se ejecuto en fase 8, aquí solo se audita el estado.
estado_archivo <- 'reportes/fase8/estado.txt'
chequear('Actualizacion','Archivo de estado presente',file.exists(estado_archivo))
if (file.exists(estado_archivo)) {
  estado <- readLines(estado_archivo,warn=FALSE,encoding='UTF-8')
  chequear('Actualizacion','Ultimo estado COMPLETADO',
    any(grepl('^estado=COMPLETADO$',estado)))
}
chequear('Actualizacion','Sin candado de ejecucion pendiente',
  !dir.exists('reportes/fase8/actualizacion_en_curso.lock'))
for (archivo in c('01_01_extraccion.log','02_02_base_datos.log',
                  '03_03_preprocesamiento.log','04_04_mineria_datos.log')) {
  chequear('Actualizacion',paste('Log',archivo),
    file.exists(file.path('reportes/fase8',archivo)))
}

if (!is.null(con)) DBI::dbDisconnect(con)
resultado <- do.call(rbind,resultados)
readr::write_excel_csv(resultado,file.path(salida,'reporte_pruebas.csv'),na='')
resumen <- as.data.frame(table(resultado$estado),stringsAsFactors=FALSE)
names(resumen) <- c('estado','cantidad')
readr::write_excel_csv(resumen,file.path(salida,'resumen_pruebas.csv'),na='')
cat('\n=================== RESUMEN FASE 9 ===================\n')
print(resumen,row.names=FALSE)
fallos <- resultado[resultado$estado=='FALLO',c('grupo','prueba','detalle'),drop=FALSE]
if (nrow(fallos)) {
  cat('\nATENCION: Estas comprobaciones necesitan revision:\n')
  print(fallos,row.names=FALSE)
  cat('\nRevisa reportes/fase9/reporte_pruebas.csv\n')
  quit(save='no',status=1L)
}
cat('\nFASE 9: PRUEBAS AUTOMATICAS SUPERADAS.\n')
cat('Falta completar las pruebas manuales de interfaz y actualizacion.\n')
cat('Reportes: reportes/fase9/\n')
