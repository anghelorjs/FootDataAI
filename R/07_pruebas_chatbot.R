# FOOTDATA AI | FASE 7 - PRUEBAS AUTOMATICAS SIN INTERNET
# Ejecutar desde FootDataAI: Rscript R/07_pruebas_chatbot.R
source('R/05_chatbot.R', local=TRUE)
noticias_prueba <- data.frame(
  id=c('1','2','3'),
  titulo=c('Chelsea win big match', 'Arsenal secure new transfer', 'Champions League final preview'),
  resumen=c('Chelsea football team wins','Arsenal signs player','European football competition'),
  fecha_publicacion_utc=c('2026-11-15 12:00:00','2026-11-14 12:00:00',NA),
  fuente=c('BBC Sport Football','BBC Sport Football','BBC Sport European Football'),
  url=c('https://example.org/1','https://example.org/2','https://example.org/3'),
  equipos_detectados=c('Chelsea','Arsenal',''),
  competiciones_detectadas=c('','','UEFA Champions League'),
  tema_fichajes=c(FALSE,TRUE,FALSE),
  stringsAsFactors=FALSE
)
pruebas <- list(
  'consulta equipo'=fd_chatbot_responder('Noticias sobre Chelsea',noticias_prueba),
  'consulta competición'=fd_chatbot_responder('Champions League',noticias_prueba),
  'últimas noticias'=fd_chatbot_responder('Últimas noticias',noticias_prueba),
  'consulta temática'=fd_chatbot_responder('Noticias de fichajes',noticias_prueba),
  'total'=fd_chatbot_responder('¿Cuántas noticias hay?',noticias_prueba),
  'no encontrado'=fd_chatbot_responder('Noticias sobre Juventus',noticias_prueba)
)
stopifnot(
  nrow(pruebas[['consulta equipo']]$noticias)==1,
  nrow(pruebas[['consulta competición']]$noticias)==1,
  nrow(pruebas[['últimas noticias']]$noticias)==3,
  nrow(pruebas[['consulta temática']]$noticias)==1,
  grepl('3 noticia',pruebas[['total']]$texto),
  nrow(pruebas[['no encontrado']]$noticias)==0
)
cat('FASE 7: 6 PRUEBAS SUPERADAS.\n')
