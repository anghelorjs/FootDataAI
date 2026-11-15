# =============================================================================
# FOOTDATA AI | FASE 7 - MOTOR CHATBOT LOCAL
# Se carga con source('R/05_chatbot.R', local=TRUE) desde app.R.
# Respuestas basadas UNICAMENTE en mineria_noticias.csv (sin IA externa).
# =============================================================================

fd_normalizar <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ''
  v <- suppressWarnings(iconv(x, from='', to='ASCII//TRANSLIT', sub=''))
  v[is.na(v)] <- x[is.na(v)]
  v <- tolower(v)
  trimws(gsub(' +', ' ', gsub('[^a-z0-9]+', ' ', v)))
}

fd_lista_entidades <- function(n, columna) {
  if (!(columna %in% names(n))) return(character())
  z <- unlist(strsplit(paste(n[[columna]], collapse=';'), ';', fixed=TRUE))
  sort(unique(trimws(z[nzchar(trimws(z))])))
}

fd_ordenar <- function(n) {
  # ISO UTC en orden descendente, faltantes al final, sin inventar fechas.
  fechas <- as.character(n$fecha_publicacion_utc)
  fechas[is.na(fechas)] <- ''
  n[order(fechas, decreasing=TRUE), , drop=FALSE]
}

fd_buscar_entidad <- function(pregunta_norm, opciones) {
  if (!length(opciones)) return(NULL)
  # Exactamente una frase reconocible del diccionario previamente detectado.
  for (e in opciones[order(nchar(opciones), decreasing=TRUE)]) {
    normal <- fd_normalizar(e)
    if (nzchar(normal) && grepl(paste0('(^| )',normal,'( |$)'),pregunta_norm)) return(e)
  }
  # Alias coloquiales, sin hacer coincidencias vagas como 'city' o 'united'.
  alias <- c('man utd'='Manchester United','man city'='Manchester City',
             'psg'='Paris Saint-Germain','barca'='FC Barcelona',
             'spurs'='Tottenham','ucl'='UEFA Champions League',
             'champions'='UEFA Champions League','epl'='Premier League',
             'liga de naciones'='Nations League',
             'liga de campeones'='UEFA Champions League',
             'mundial'='World Cup')
  for (a in names(alias)) {
    if (alias[[a]] %in% opciones && grepl(paste0('(^| )',a,'( |$)'),pregunta_norm)) return(alias[[a]])
  }
  NULL
}

fd_menciona_entidad <- function(n, columna, entidad) {
  if (is.null(entidad) || !(columna %in% names(n))) return(rep(FALSE,nrow(n)))
  vapply(strsplit(ifelse(is.na(n[[columna]]),'',as.character(n[[columna]])), ';',fixed=TRUE),
         function(v) entidad %in% trimws(v), logical(1))
}

fd_resumen_entidades <- function(n, columna, limite=5) {
  entidades <- fd_lista_entidades(n,columna)
  if (!length(entidades)) return(data.frame(entidad=character(),noticias=integer()))
  cantidad <- vapply(entidades,function(e) sum(fd_menciona_entidad(n,columna,e)),integer(1))
  out <- data.frame(entidad=entidades,noticias=as.integer(cantidad))
  utils::head(out[order(-out$noticias,out$entidad),,drop=FALSE],limite)
}

fd_chatbot_responder <- function(pregunta, noticias, max_resultados=5) {
  p <- fd_normalizar(pregunta)
  vacio <- noticias[0,,drop=FALSE]
  res <- function(texto, datos=vacio, tipo='consulta')
    list(texto=texto,noticias=datos,tipo=tipo)
  if (!nzchar(p)) return(res('Escribe una pregunta sobre fútbol, equipos, competiciones o noticias.'))
  if (!nrow(noticias)) return(res('Todavía no hay noticias procesadas. Ejecuta las fases 2 a 5 y recarga los archivos.'))
  n <- noticias
  if (grepl('^(hola|buenas|ayuda|que puedes hacer|como funciona)',p))
    return(res('Puedes preguntar: últimas noticias, noticias de Chelsea, Champions League, fichajes, ¿cuántas noticias hay?, ¿qué equipos aparecen más? También puedes buscar palabras de un titular.'))

  equipos <- fd_lista_entidades(n,'equipos_detectados')
  comps <- fd_lista_entidades(n,'competiciones_detectadas')
  ranking <- grepl('mas mencionad|mas nombrad|mas aparec|ranking|top [0-9]|mas frecuentes',p)
  tipo_equipos <- grepl('equipos|clubes',p)
  tipo_comp <- grepl('competiciones|ligas|torneos',p)
  if (ranking && (tipo_equipos || tipo_comp)) {
    col <- if (tipo_comp) 'competiciones_detectadas' else 'equipos_detectados'
    tabla <- fd_resumen_entidades(n,col,5)
    if (!nrow(tabla)) return(res('No se detectaron entidades de ese tipo en las noticias recopiladas.'))
    cuerpo <- paste(sprintf('%s: %d noticia(s)',tabla$entidad,tabla$noticias),collapse='; ')
    return(res(paste0('En las ',nrow(n),' noticias almacenadas, las ',
      if (tipo_comp) 'competiciones' else 'entidades de equipo',
      ' más mencionadas son: ',cuerpo,'. Una noticia puede mencionar varias entidades.'), tipo='estadistica'))
  }

  equipo <- fd_buscar_entidad(p,equipos)
  comp <- fd_buscar_entidad(p,comps)
  filtro <- rep(TRUE,nrow(n))
  criterio <- character()
  if (!is.null(equipo)) {
    filtro <- filtro & fd_menciona_entidad(n,'equipos_detectados',equipo)
    criterio <- c(criterio,equipo)
  }
  if (!is.null(comp)) {
    filtro <- filtro & fd_menciona_entidad(n,'competiciones_detectadas',comp)
    criterio <- c(criterio,comp)
  }
  # Mapeo de preguntas frecuentes en español a temas y términos de RSS en inglés.
  temas <- list(
    fichajes=list(patron='fichaj|transferenc|mercado de pases|traspas',campo='tema_fichajes',
                 claves=c('transfer','signing','signs','signed','deal','move')),
    lesiones=list(patron='lesion|lesionad|injur',campo='tema_lesiones',
                 claves=c('injury','injured','fitness')),
    partidos=list(patron='partid|resultados|encuentros',campo='tema_partidos',
                 claves=c('match','game','win','draw','defeat')),
    selecciones=list(patron='seleccion|internacional|nacional',campo='tema_selecciones',
                    claves=c('international','national team','england','spain'))
  )
  clave_tema <- NULL
  for (t in names(temas)) if (grepl(temas[[t]]$patron,p)) {clave_tema <- t; break}
  if (!is.null(clave_tema)) {
    info <- temas[[clave_tema]]
    texto <- paste(fd_normalizar(n$titulo),fd_normalizar(if ('resumen' %in% names(n)) n$resumen else rep('',nrow(n))))
    patrones <- paste(info$claves,collapse='|')
    hit <- grepl(patterns <- paste0('(^| )(',patrones,')( |$)'),texto)
    if (info$campo %in% names(n))
      hit <- hit | tolower(as.character(n[[info$campo]])) %in% c('true','t','1')
    filtro <- filtro & hit
    criterio <- c(criterio,clave_tema)
  }

  cuenta <- grepl('cuant[ao]s? noticias|cantidad de noticias|total de noticias',p)
  # Si no identificamos tema ni entidad, buscar términos significativos del usuario.
  if (!length(criterio) && !cuenta && !grepl('ultim|recient|novedad|actual',p)) {
    palabras <- strsplit(p,' ',fixed=TRUE)[[1]]
    stop <- c('que','cuales','cual','hay','sobre','del','las','los','una','uno','unos',
              'unas','para','por','con','sin','de','el','la','en','un','me','mostrar',
              'muestrame','dame','busca','buscar','noticias','noticia','quiero',
              'saber','tienes','tiene','informacion','acerca','favor','hoy','ayer',
              'semana','esta','este','ultimo','ultimas','recientes','mas')
    palabras <- unique(palabras[nchar(palabras)>2 & !palabras %in% stop])
    if (length(palabras)) {
      texto <- fd_normalizar(paste(n$titulo,
        if ('resumen' %in% names(n)) n$resumen else '',
        if ('equipos_detectados' %in% names(n)) n$equipos_detectados else '',
        if ('competiciones_detectadas' %in% names(n)) n$competiciones_detectadas else ''))
      filtro <- filtro & vapply(texto,function(x) any(vapply(palabras,
        function(w) grepl(paste0('(^| )',w,'( |$)'),x),logical(1))), logical(1))
      criterio <- paste(palabras,collapse=', ')
    } else if (!grepl('noticias|futbol',p)) {
      return(res('No entendí la consulta. Prueba con: noticias de Chelsea, últimas noticias, fichajes o equipos más mencionados.'))
    }
  }
  encontrados <- fd_ordenar(n[filtro,,drop=FALSE])
  contexto <- if (length(criterio)) paste(criterio,collapse=' y ') else 'fútbol internacional'
  if (cuenta) return(res(sprintf('Tengo %d noticia(s) sobre %s dentro de una base de %d registros. Es un conteo de los datos almacenados, no de todas las noticias existentes.',
                                 nrow(encontrados),contexto,nrow(n)),tipo='estadistica'))
  if (!nrow(encontrados)) return(res(paste0('No encontré noticias sobre ',contexto,
    ' en la base local. Esto no significa que no existan; puedes actualizar los RSS y reprocesar los datos.')))
  mostradas <- utils::head(encontrados, max_resultados)
  res(sprintf('Encontré %d noticia(s) sobre %s en la base local. Te muestro %d, ordenadas por fecha de publicación (sin fecha al final).',
              nrow(encontrados),contexto,nrow(mostradas)),mostradas,'noticias')
}
