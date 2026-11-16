# Pruebas locales con fixtures: no consulta Internet ni modifica los CSV.
if (.Platform$OS.type=='windows') invisible(Sys.setlocale('LC_ALL','English_United States.utf8'))
source('R/05_chatbot.R',local=TRUE,encoding='UTF-8')
n <- data.frame(
  id=c('1','2','3','4'),
  titulo=c('Ronaldinho to play first game since 2015','Ronaldinho makes comeback in Ravenna win',
           'Chelsea wins a friendly','A title without a summary'),
  resumen=c('Ronaldinho is set to start for Ravenna against Forli on Sunday.',
            'Ronaldinho played the first half of the derby against Forli.',
            'Chelsea won a friendly match.',NA_character_),
  fecha_publicacion_utc=c('2026-11-14T12:00:00Z','2026-11-15T12:00:00Z','2026-11-15T10:00:00Z',NA_character_),
  fuente='BBC Sport Football',url=paste0('https://example.org/',1:4),
  equipos_detectados=c('','','Chelsea',''),competiciones_detectadas='',stringsAsFactors=FALSE)
comprobaciones <- 0L
chequear <- function(nombre,condicion) {
  stopifnot(isTRUE(condicion))
  comprobaciones <<- comprobaciones+1L
  cat('[OK] ',nombre,'\n',sep='')
}
buscar <- fd_chatbot_responder('Dime todas las noticias que implican a Ronaldinho',n)
chequear('Busca personas sin diccionario de equipos',setequal(buscar$noticias$id,c('1','2')))
chequear('Contexto con orden de los resultados',identical(buscar$contexto_ids,c('2','1')))
ambigua <- fd_chatbot_responder('Que indica la noticia?',n,contexto_ids=buscar$contexto_ids)
chequear('Pide elegir cuando la referencia singular es ambigua',ambigua$tipo=='aclaracion' && nrow(ambigua$noticias)==2L)
primera <- fd_chatbot_responder('La primera',n,contexto_ids=buscar$contexto_ids)
chequear('Resuelve ordinal y extrae el resumen exacto',primera$tipo=='lectura' && identical(primera$noticias$id,'2') && grepl(n$resumen[2],primera$texto,fixed=TRUE))
segunda <- fd_chatbot_responder('Explicame la segunda noticia',n,contexto_ids=buscar$contexto_ids)
chequear('Resuelve la segunda noticia',identical(segunda$contexto_ids,'1') && grepl(n$resumen[1],segunda$texto,fixed=TRUE))
plural <- fd_chatbot_responder('Resume estas noticias',n,contexto_ids=buscar$contexto_ids)
chequear('Lee los resúmenes del conjunto anterior',plural$tipo=='lectura' && nrow(plural$noticias)==2 && all(vapply(n$resumen[1:2],function(x) grepl(x,plural$texto,fixed=TRUE),logical(1))))
sin_contexto <- fd_chatbot_responder('Que indica la noticia?',n)
chequear('No elige noticias arbitrarias sin contexto',sin_contexto$tipo=='aclaracion' && nrow(sin_contexto$noticias)==0)
obsoleta <- fd_chatbot_responder('Que indica esta noticia?',n,contexto_ids='inexistente')
chequear('Detecta identificadores obsoletos',obsoleta$tipo=='aclaracion' && !length(obsoleta$contexto_ids))
restringida <- fd_chatbot_responder('Resume estas noticias',n[3,,drop=FALSE],contexto_ids=buscar$contexto_ids)
chequear('La memoria no salta los filtros actuales',nrow(restringida$noticias)==0)
cambio <- fd_chatbot_responder('Que indica la noticia de Chelsea?',n,contexto_ids=buscar$contexto_ids)
chequear('Una entidad explícita cambia el tema',identical(cambio$noticias$id,'3'))
ausente <- fd_chatbot_responder('Que indica la noticia de Messi?',n,contexto_ids=buscar$contexto_ids)
chequear('No atribuye noticias anteriores a otra persona',nrow(ausente$noticias)==0)
indice <- fd_chatbot_responder('Noticia 9',n,contexto_ids=buscar$contexto_ids)
chequear('Valida índices fuera de la lista',indice$tipo=='aclaracion')
sin_resumen <- fd_chatbot_responder('Que indica esta noticia?',n,contexto_ids='4')
chequear('Informa cuando no hay resumen',grepl('No hay resumen almacenado',sin_resumen$texto,fixed=TRUE))
fecha <- fd_chatbot_responder('Cuando se publico?',n,contexto_ids='2')
chequear('Distingue fecha de publicación de fecha del suceso',grepl(n$fecha_publicacion_utc[2],fecha$texto,fixed=TRUE) && grepl('no necesariamente',fecha$texto,fixed=TRUE))
causa <- fd_chatbot_responder('Por que?',n,contexto_ids='2')
chequear('No inventa una causa al leer el RSS',grepl('No puedo confirmar la causa',causa$texto,fixed=TRUE) && grepl(n$resumen[2],causa$texto,fixed=TRUE))
conteo <- fd_chatbot_responder('Cuantas noticias hay sobre Ronaldinho?',n)
chequear('Cuenta noticias de una persona',grepl('Tengo 2 noticia',conteo$texto,fixed=TRUE))
recientes <- fd_chatbot_responder('Ultimas noticias sobre Ronaldinho',n)
chequear('Últimas noticias conserva el sujeto de búsqueda',setequal(recientes$noticias$id,c('1','2')))
muchas <- n[rep(1,8),,drop=FALSE]
muchas$id <- as.character(seq_len(nrow(muchas)))
chequear('Todas las noticias no trunca a cinco',nrow(fd_chatbot_responder('Todas las noticias sobre Ronaldinho',muchas)$noticias)==8)
limitada <- fd_chatbot_responder('Noticias sobre Ronaldinho',n,max_resultados=1)
chequear('La memoria sigue las noticias efectivamente mostradas',length(limitada$contexto_ids)==1 && nrow(limitada$noticias)==1)
ultima <- fd_chatbot_responder('La ultima',n,contexto_ids=buscar$contexto_ids)
chequear('Última se refiere a la posición de la lista anterior',identical(ultima$noticias$id,'1'))
directa <- fd_chatbot_responder('Que indican las noticias sobre Ronaldinho?',n)
chequear('Puede leer un tema sin una búsqueda previa',directa$tipo=='lectura' && nrow(directa$noticias)==2)
vacia <- fd_chatbot_responder('Noticias de Messi',n,contexto_ids=buscar$contexto_ids)
chequear('Una nueva búsqueda sin resultados limpia el contexto',!length(vacia$contexto_ids))
cat('CONVERSACION: ',comprobaciones,' pruebas superadas.\n',sep='')
