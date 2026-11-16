# Politica compartida por el extractor, la API y sus procesos hijos.
# El intervalo solicitado nunca acorta el TTL/cache o Retry-After de la fuente.
fd_rss_intervalo_minutos <- function(valor=Sys.getenv('FOOTDATA_RSS_INTERVAL_MINUTES','15')) {
  n <- suppressWarnings(as.numeric(valor))
  if (length(n)!=1L || is.na(n) || !is.finite(n) || n<1 || n>1440 || n!=floor(n))
    stop('El intervalo RSS debe ser un numero entero entre 1 y 1440 minutos.')
  as.integer(n)
}

fd_rss_cache <- function(ruta='reportes/cache_rss.rds') {
  x <- if (file.exists(ruta)) tryCatch(readRDS(ruta),error=function(e) NULL) else NULL
  if (!is.list(x) || !is.list(x$feeds)) return(list(feeds=list()))
  x
}

fd_rss_numero <- function(x, defecto=0) {
  if (is.null(x) || !length(x)) return(defecto)
  v <- suppressWarnings(as.numeric(x[[1]]))
  if (is.na(v) || !is.finite(v) || v<0) defecto else v
}

fd_rss_fecha_http <- function(x) {
  if (is.null(x) || length(x)!=1 || is.na(x)) return(as.POSIXct(NA))
  x <- sub('^[A-Za-z]{3}, *','',x)
  m <- regmatches(x,regexec('^([0-9]{1,2}) ([A-Za-z]{3}) ([0-9]{4}) ([0-9]{2}:[0-9]{2}:[0-9]{2}) GMT$',x))[[1]]
  if (length(m)!=5) return(as.POSIXct(NA))
  mes <- match(tolower(m[3]),tolower(month.abb))
  if (is.na(mes)) return(as.POSIXct(NA))
  suppressWarnings(as.POSIXct(sprintf('%s-%02d-%02d %s',m[4],mes,as.integer(m[2]),m[5]),format='%Y-%m-%d %H:%M:%S',tz='UTC'))
}

fd_rss_guardar_respuesta <- function(cache,nombre,codigo,headers=list(),ttl=NULL,ahora=Sys.time()) {
  names(headers) <- tolower(names(headers))
  anterior <- cache$feeds[[nombre]]
  if (is.null(anterior)) anterior <- list()
  actual <- anterior
  actual$checked_at <- as.numeric(ahora)
  actual$http <- as.integer(codigo)
  if (codigo %in% c(200L,304L)) {
    actual$failures <- 0L
    actual$retry_until <- 0
    if (codigo==200L && !is.null(ttl)) actual$ttl_seconds <- fd_rss_numero(ttl)*60
    control <- headers[['cache-control']]
    max_age <- if (!is.null(control)) regmatches(control,regexec('(?:^|[, ])max-age=([0-9]+)',control,ignore.case=TRUE))[[1]] else character()
    if (length(max_age)>1) actual$cache_seconds <- max(0,as.numeric(max_age[2])-fd_rss_numero(headers[['age']]))
    else if (codigo==200L) actual$cache_seconds <- 0
    for (campo in c('etag','last-modified')) {
      if (!is.null(headers[[campo]])) actual[[campo]] <- headers[[campo]]
      else if (codigo==200L) actual[[campo]] <- NULL
    }
  } else {
    actual$failures <- as.integer(fd_rss_numero(anterior$failures)+1)
    espera <- min(3600,60*2^min(actual$failures-1,6))
    if (codigo==403L) espera <- max(espera,3600)
    retry <- headers[['retry-after']]
    if (!is.null(retry)) {
      if (grepl('^[0-9]+$',retry)) espera <- max(espera,as.numeric(retry))
      else {
        fecha <- fd_rss_fecha_http(retry)
        if (!is.na(fecha)) espera <- max(espera,as.numeric(difftime(fecha,ahora,units='secs')))
      }
    }
    actual$retry_until <- as.numeric(ahora)+espera
  }
  cache$feeds[[nombre]] <- actual
  cache
}

fd_rss_plan <- function(ahora=Sys.time(),ultimo=NULL,cache=fd_rss_cache(),intervalo=fd_rss_intervalo_minutos()) {
  if (is.null(ultimo) && file.exists('reportes/ultima_consulta_bbc.rds'))
    ultimo <- tryCatch(readRDS('reportes/ultima_consulta_bbc.rds'),error=function(e) NULL)
  solicitado <- fd_rss_intervalo_minutos(intervalo)*60
  fuente <- max(c(0,vapply(cache$feeds,function(x) max(fd_rss_numero(x$ttl_seconds),fd_rss_numero(x$cache_seconds)),numeric(1))))
  efectivo <- max(solicitado,fuente)
  intento <- if (inherits(ultimo,'POSIXct') && !is.na(ultimo)) as.numeric(ultimo) else 0
  revisiones <- vapply(cache$feeds,function(x) fd_rss_numero(x$checked_at),numeric(1))
  ultimo_efectivo <- max(c(intento,revisiones))
  retry <- max(c(0,vapply(cache$feeds,function(x) fd_rss_numero(x$retry_until),numeric(1))))
  siguiente <- max(if (ultimo_efectivo>0) ultimo_efectivo+efectivo else 0,retry)
  espera <- max(0,ceiling(siguiente-as.numeric(ahora)))
  motivo <- if (retry>ultimo_efectivo+efectivo) 'La fuente pidio una espera adicional o hubo un error de conexion.' else
    if (fuente>solicitado) 'Se respeta el TTL/cache indicado por la fuente.' else 'Intervalo configurado entre consultas.'
  iso <- function(x) if (x>0) format(as.POSIXct(x,origin='1970-01-01',tz='UTC'),'%Y-%m-%dT%H:%M:%SZ',tz='UTC') else NA_character_
  list(intervalMinutes=as.integer(intervalo),sourceMinimumSeconds=fuente,effectiveIntervalSeconds=efectivo,
       cooldownSeconds=espera,cooldownReason=motivo,nextCheckAt=iso(siguiente),lastCheckedAt=iso(ultimo_efectivo))
}

fd_rss_mismos_datos <- function(anterior,nuevo) {
  columnas <- setdiff(names(anterior),'fecha_extraccion_utc')
  if (!all(columnas %in% names(nuevo)) || nrow(anterior)!=nrow(nuevo)) return(FALSE)
  a <- as.data.frame(anterior[order(anterior$url),columnas,drop=FALSE])
  b <- as.data.frame(nuevo[order(nuevo$url),columnas,drop=FALSE])
  isTRUE(all.equal(a,b,check.attributes=FALSE))
}
