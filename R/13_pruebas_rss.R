# Pruebas sin Internet: tiempos, cache HTTP, errores y omision del reprocesamiento.
if (.Platform$OS.type=='windows') invisible(Sys.setlocale('LC_ALL','English_United States.utf8'))
source('R/12_configuracion_rss.R',local=TRUE,encoding='UTF-8')
total <- 0L
chequear <- function(nombre,condicion) {
  stopifnot(isTRUE(condicion)); total <<- total+1L
  cat('[OK] ',nombre,'\n',sep='')
}
ahora <- as.POSIXct('2026-11-15 12:00:00',tz='UTC')
vacio <- list(feeds=list())
chequear('Intervalo predeterminado de 15 minutos',fd_rss_intervalo_minutos('15')==15L)
chequear('Permite solicitar un minuto',fd_rss_intervalo_minutos('1')==1L)
for (x in c('0','-1','1.5','abc','1441','Inf'))
  chequear(paste('Rechaza intervalo',x),inherits(tryCatch(fd_rss_intervalo_minutos(x),error=function(e)e),'error'))
plan_vacio <- fd_rss_plan(ahora,as.POSIXct(NA),vacio,15)
chequear('La primera consulta esta disponible',plan_vacio$cooldownSeconds==0)
cache <- fd_rss_guardar_respuesta(vacio,'Football',200L,
  list('Cache-Control'='public, max-age=3','ETag'='"v1"','Last-Modified'='Sun, 15 Nov 2026 11:00:00 GMT'),ttl='15',ahora=ahora)
plan <- fd_rss_plan(ahora,ahora,cache,1)
chequear('Respeta TTL de 15 aunque se solicite un minuto',plan$effectiveIntervalSeconds==900 && plan$cooldownSeconds==900)
chequear('Informa el minimo declarado por la fuente',plan$sourceMinimumSeconds==900)
chequear('No impone una hora extra',fd_rss_plan(ahora+901,ahora,cache,1)$cooldownSeconds==0)
chequear('Permite un intervalo configurado mayor',fd_rss_plan(ahora,ahora,cache,30)$cooldownSeconds==1800)
sin_cambios <- fd_rss_guardar_respuesta(cache,'Football',304L,ahora=ahora+901)
chequear('304 conserva TTL y validadores',sin_cambios$feeds$Football$ttl_seconds==900 && identical(sin_cambios$feeds$Football$etag,'"v1"'))
chequear('304 inicia la espera desde la comprobacion reciente',fd_rss_plan(ahora+901,ahora,sin_cambios,1)$cooldownSeconds==900)
http_cache <- fd_rss_guardar_respuesta(vacio,'Football',200L,list('cache-control'='public, max-age=1200','age'='200'),ttl='15',ahora=ahora)
chequear('Respeta cache HTTP restante cuando supera el TTL',fd_rss_plan(ahora,ahora,http_cache,1)$sourceMinimumSeconds==1000)
limitado <- fd_rss_guardar_respuesta(cache,'Football',429L,list('Retry-After'='1800'),ahora=ahora)
chequear('429 respeta Retry-After en segundos',fd_rss_plan(ahora,ahora,limitado,1)$cooldownSeconds==1800)
fecha_retry <- fd_rss_guardar_respuesta(cache,'Football',503L,list('Retry-After'='Sun, 15 Nov 2026 12:30:00 GMT'),ahora=ahora)
chequear('503 respeta Retry-After con fecha GMT',fd_rss_plan(ahora,ahora,fecha_retry,1)$cooldownSeconds==1800)
bloqueado <- fd_rss_guardar_respuesta(cache,'Football',403L,ahora=ahora)
chequear('403 amplia la espera',fd_rss_plan(ahora,ahora,bloqueado,1)$cooldownSeconds>=3600)
fallo <- fd_rss_guardar_respuesta(vacio,'Football',0L,ahora=ahora)
fallo <- fd_rss_guardar_respuesta(fallo,'Football',0L,ahora=ahora+61)
chequear('Fallos consecutivos aumentan la espera',fallo$feeds$Football$retry_until-as.numeric(ahora+61)==120)
a <- data.frame(url=c('https://example.org/1','https://example.org/2'),titulo=c('A','B'),resumen=c('Uno','Dos'),fecha_extraccion_utc='antes')
b <- a[2:1,]; b$fecha_extraccion_utc <- 'despues'
chequear('Una nueva fecha de consulta no simula cambios de contenido',fd_rss_mismos_datos(a,b))
b$titulo[1] <- 'Nuevo titular'
chequear('Detecta cambios reales aunque no haya nuevas URLs',!fd_rss_mismos_datos(a,b))
chequear('Detecta noticias nuevas',!fd_rss_mismos_datos(a,rbind(a,a[1,])))
dos_fuentes <- fd_rss_guardar_respuesta(cache,'European',200L,ttl='30',ahora=ahora)
chequear('Se aplica el mayor intervalo de las fuentes',fd_rss_plan(ahora,ahora,dos_fuentes,1)$effectiveIntervalSeconds==1800)

probar_pipeline_sin_cambios <- function() {
  raiz <- getwd()
  temporal <- tempfile('footdata-rss-')
  dir.create(temporal)
  setwd(temporal)
  on.exit(setwd(raiz),add=TRUE)
  dir.create('R'); dir.create('data/crudos',recursive=TRUE)
  dir.create('data/procesados'); dir.create('reportes/fase5',recursive=TRUE)
  writeLines('url,titulo\nhttps://example.org/1,A','data/crudos/noticias_futbol.csv')
  writeLines("cat('RSS sin cambios de contenido')",'R/01_extraccion.R')
  for (nombre in c('02_base_datos.R','03_preprocesamiento.R','04_mineria_datos.R'))
    writeLines("stop('No debe ejecutarse un derivado sin cambios')",file.path('R',nombre))
  derivados <- c('data/futbol.sqlite','data/procesados/noticias_preprocesadas.csv',
    'data/procesados/tokens_limpios.csv','data/procesados/mineria_noticias.csv',
    paste0('reportes/fase5/',c('01_frecuencia_palabras.csv','02_bigramas.csv',
      '09_detalle_menciones_equipos.csv','10_detalle_menciones_competiciones.csv')))
  file.create(derivados)
  source(file.path(raiz,'R/06_actualizacion.R'),local=TRUE,encoding='UTF-8')
  estado <- readLines('reportes/fase8/estado.txt',warn=FALSE)
  all(c('estado=COMPLETADO','fase=Final') %in% estado) &&
    any(grepl('Sin cambios',estado,fixed=TRUE)) &&
    !file.exists('reportes/fase8/02_02_base_datos.log') &&
    !dir.exists('reportes/fase8/actualizacion_en_curso.lock')
}
chequear('Sin cambios no repite SQLite, preprocesamiento ni mineria',probar_pipeline_sin_cambios())
cat('RSS: ',total,' pruebas superadas.\n',sep='')
