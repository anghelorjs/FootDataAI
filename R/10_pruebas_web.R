# Pruebas sin internet y sin modificar los datos existentes.
if (.Platform$OS.type=='windows') invisible(Sys.setlocale('LC_ALL','English_United States.utf8'))
source('R/09_servicios_web.R', encoding='UTF-8')
s <- fd_cargar_snapshot()
stopifnot(length(s$respuesta$articles)==nrow(s$noticias))
stopifnot(all(s$noticias$tema_principal %in% c('fichajes','champions','premier_league','laliga','mundial','selecciones','lesiones','partidos','sin_clasificar')))
stopifnot(all(vapply(s$respuesta$articles,function(a) is.list(a$tokens) && is.list(a$teams) && is.list(a$topics),logical(1))))
stopifnot(identical(fd_iso(c('2026/11/15 19:09:06',NA_character_)),c('2026-11-15T19:09:06Z',NA_character_)))
prueba <- data.frame(id=c('1','2','3'),titulo=c('Arsenal wins','Chelsea transfer','Copa de futbol'),resumen='',
  fuente=c('BBC','European','BBC'),tema_principal=c('partidos','fichajes','sin_clasificar'),
  tema_partidos=c('TRUE','TRUE','FALSE'),equipos_detectados=c('Arsenal; Chelsea','Chelsea',''),
  competiciones_detectadas=c('Premier League','Premier League',''),
  fecha_publicacion_utc=c('2026-11-15T12:00:00Z','2026-11-13T23:30:00Z',NA_character_))
stopifnot(identical(fd_filtrar(prueba,list(team='Chelsea',topic='partidos',source='European'))$id,'2'))
stopifnot(identical(fd_filtrar(prueba,list(from='2026-11-14',to='2026-11-15'))$id,c('1','3')))
stopifnot(identical(fd_filtrar(prueba,list(from='2026-11-14',includeUndated=FALSE))$id,'1'))
stopifnot(nrow(fd_filtrar(prueba,list(team='Ars')))==0)
stopifnot(identical(fd_filtrar(prueba,list(query='FUTBOL'))$id,'3'))
stopifnot(nrow(fd_filtrar(prueba,list(ids=list())))==0)
stopifnot(inherits(tryCatch(fd_filtrar(prueba,list(from='incorrecta')),error=function(e)e),'error'))
respuesta <- fd_chatbot_responder('Noticias sobre Arsenal',s$noticias)
stopifnot(is.character(respuesta$texto),is.data.frame(respuesta$noticias))
json <- jsonlite::toJSON(s$respuesta,auto_unbox=TRUE,na='null',null='null')
roundtrip <- jsonlite::fromJSON(json,simplifyVector=FALSE)
stopifnot(is.list(roundtrip$articles),is.list(roundtrip$articles[[1]]$tokens))
for (archivo in c('api.R','R/09_servicios_web.R','R/10_pruebas_web.R')) parse(archivo)
cat('WEB: 14 comprobaciones superadas. Noticias: ',nrow(s$noticias),'\n',sep='')
