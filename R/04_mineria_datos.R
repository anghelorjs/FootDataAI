# ============================================================================
# FOOTDATA AI | FASE 5 - MINERIA DE TEXTO Y EXPLORACION
# Ejecutar desde la carpeta raiz: Rscript R/04_mineria_datos.R
# Entradas: data/procesados/noticias_preprocesadas.csv, tokens_limpios.csv
# Salidas: reportes/fase5/ (tablas y graficos), data/procesados/mineria_noticias.csv
# No modifica SQLite, noticias originales ni los archivos de fase 4.
# ============================================================================

paquetes <- c('readr','dplyr','tidyr','stringr','tidytext','ggplot2','tibble','scales','stopwords')
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly=TRUE)]
if (length(faltantes)) stop('Instala los paquetes faltantes: ',paste(faltantes,collapse=', '),
                            '\ninstall.packages(c(',paste(sprintf('"%s"',faltantes),collapse=', '),'))')

entrada_noticias <- 'data/procesados/noticias_preprocesadas.csv'
entrada_tokens <- 'data/procesados/tokens_limpios.csv'
salida <- 'reportes/fase5'
dir.create(salida,recursive=TRUE,showWarnings=FALSE)
dir.create('data/procesados',recursive=TRUE,showWarnings=FALSE)
if (!file.exists(entrada_noticias) || !file.exists(entrada_tokens)) {
  stop('Faltan archivos de la fase 4. Ejecuta: Rscript R/03_preprocesamiento.R')
}
leer <- function(ruta) readr::read_csv(ruta,show_col_types=FALSE,locale=readr::locale(encoding='UTF-8'),progress=FALSE)
guardar <- function(x,nombre) readr::write_excel_csv(x,file.path(salida,nombre),na='')

cat('\n====================================================\n')
cat(' FOOTDATA AI | FASE 5 - MINERIA DE DATOS\n')
cat('====================================================\n')
noticias <- leer(entrada_noticias)
tokens <- leer(entrada_tokens)
requeridas_noticias <- c('id','titulo','texto_normalizado','fecha_publicacion_utc','fuente')
requeridas_tokens <- c('id','palabra')
if (length(f <- setdiff(requeridas_noticias,names(noticias)))) stop('Faltan columnas en noticias: ',paste(f,collapse=', '))
if (length(f <- setdiff(requeridas_tokens,names(tokens)))) stop('Faltan columnas en tokens: ',paste(f,collapse=', '))
noticias <- noticias |> dplyr::mutate(id=as.character(id),
  texto_normalizado=dplyr::coalesce(as.character(texto_normalizado),''),
  fecha_publicacion_utc=as.character(fecha_publicacion_utc),
  dia=as.Date(substr(fecha_publicacion_utc,1,10),format='%Y-%m-%d'))
tokens <- tokens |> dplyr::mutate(id=as.character(id),palabra=as.character(palabra)) |>
  dplyr::filter(!is.na(palabra),nzchar(palabra))
if (anyDuplicated(noticias$id)) stop('IDs duplicados en noticias_preprocesadas.csv.')
if (!nrow(noticias) || !nrow(tokens)) stop('No hay suficientes noticias o tokens para analizar.')
if (any(!tokens$id %in% noticias$id)) stop('Hay tokens con ID inexistente en noticias.')

# 1. Frecuencia de terminos y bigramas. Los bigramas se derivan del texto
# normalizado (incluyen palabras funcionales); se filtran stopwords en extremos.
frecuencias <- tokens |> dplyr::count(palabra,name='frecuencia',sort=TRUE)
stop_en <- unique(c(stopwords::stopwords('en'),'bbc','sport','sports','says','said',
                    'could','would','also','one','two','three','new','get','gets',
                    'got','will','year','years','today','week'))
bigramas <- noticias |>
  dplyr::select(id,texto_normalizado) |>
  tidytext::unnest_tokens(bigrama,texto_normalizado,token='ngrams',n=2) |>
  tidyr::separate_wider_delim(bigrama,delim=' ',names=c('palabra1','palabra2'),too_few='align_start') |>
  dplyr::filter(!is.na(palabra1),!is.na(palabra2),
                stringr::str_detect(palabra1,'^[a-z]{3,}$'),
                stringr::str_detect(palabra2,'^[a-z]{3,}$'),
                !palabra1 %in% stop_en,!palabra2 %in% stop_en) |>
  dplyr::mutate(bigrama=paste(palabra1,palabra2)) |>
  dplyr::count(bigrama,name='frecuencia',sort=TRUE)

# 2. TF-IDF por noticia: ayuda a identificar terminos distintivos, pero
# puntuaciones de documentos cortos deben interpretarse con cautela.
tf_idf <- tokens |>
  dplyr::count(id,palabra,name='n') |>
  tidytext::bind_tf_idf(term=palabra,document=id,n=n) |>
  dplyr::arrange(dplyr::desc(tf_idf))
top_tfidf <- tf_idf |>
  dplyr::group_by(id) |>
  dplyr::slice_max(tf_idf,n=5,with_ties=FALSE) |>
  dplyr::ungroup() |>
  dplyr::left_join(noticias |> dplyr::select(id,titulo),by='id') |>
  dplyr::select(id,titulo,palabra,n,tf,idf,tf_idf)

# 3. Diccionario transparente de equipos y competiciones. Solo detecta
# menciones textuales; no supone que un medio entregue entidad oficial.
# Los patrones evitan identificadores demasiado ambiguos como "city" o "united".
equipos <- c(
  'Real Madrid'='\\b(real madrid|madrid cf)\\b',
  'FC Barcelona'='\\b(fc barcelona|barcelona|barca)\\b',
  'Manchester City'='\\b(manchester city|man city)\\b',
  'Manchester United'='\\b(manchester united|man utd)\\b',
  'Liverpool'='\\bliverpool\\b',
  'Arsenal'='\\barsenal\\b',
  'Chelsea'='\\bchelsea\\b',
  'Tottenham'='\\b(tottenham|spurs)\\b',
  'Bayern Munich'='\\b(bayern munich|bayern munchen|bayern)\\b',
  'Borussia Dortmund'='\\b(borussia dortmund|dortmund)\\b',
  'Paris Saint-Germain'='\\b(paris saint germain|paris saint-germain|psg)\\b',
  'Juventus'='\\bjuventus\\b',
  'AC Milan'='\\b(ac milan|a c milan)\\b',
  'Inter Milan'='\\b(inter milan|internazionale)\\b',
  'Napoli'='\\bnapoli\\b',
  'Atletico Madrid'='\\b(atletico madrid|atletico de madrid)\\b',
  'Newcastle United'='\\b(newcastle united|newcastle)\\b',
  'Aston Villa'='\\baston villa\\b'
)
competiciones <- c(
  'UEFA Champions League'='\\b(champions league|uefa champions|ucl)\\b',
  'Premier League'='\\b(premier league|english premier|epl)\\b',
  'LaLiga'='\\b(la liga|laliga)\\b',
  'Bundesliga'='\\bbundesliga\\b',
  'Serie A'='\\b(serie a|italian serie a)\\b',
  'Ligue 1'='\\b(ligue 1|french ligue 1)\\b',
  'Europa League'='\\b(europa league|uefa europa)\\b',
  'World Cup'='\\b(world cup|fifa world cup)\\b',
  "Women's Champions League"='\\b(women s champions league|womens champions league|uwcl)\\b',
  'Nations League'='\\bnations league\\b'
)
# En titulares/resumen hay mayusculas, signos y acentos; usar version de fase 4.
detectar <- function(dic) {
  if (!length(dic)) return(tibble::tibble(id=character(),entidad=character()))
  dplyr::bind_rows(lapply(seq_along(dic),function(i) {
    hit <- stringr::str_detect(noticias$texto_normalizado,dic[[i]])
    tibble::tibble(id=noticias$id[hit],entidad=names(dic)[i])
  }))
}
menciones_equipos <- detectar(equipos)
menciones_competiciones <- detectar(competiciones)
conteo_equipos <- menciones_equipos |> dplyr::count(entidad,name='noticias',sort=TRUE)
conteo_competiciones <- menciones_competiciones |> dplyr::count(entidad,name='noticias',sort=TRUE)

# 4. Cruce entre temas previos y menciones de entidades.
columnas_tema <- setdiff(grep('^tema_',names(noticias),value=TRUE), 'tema_principal')
if (!length(columnas_tema)) stop('La fase 4 no genero columnas tema_*.')
para_logico <- function(x) tolower(trimws(as.character(x))) %in% c('true','t','1','si','sí')
for (col in columnas_tema) noticias[[col]] <- para_logico(noticias[[col]])
por_tema <- noticias |>
  dplyr::select(id,dplyr::all_of(columnas_tema)) |>
  tidyr::pivot_longer(cols=dplyr::all_of(columnas_tema),names_to='tema',values_to='detectado') |>
  dplyr::filter(detectado) |>
  dplyr::mutate(tema=sub('^tema_','',tema)) |>
  dplyr::count(tema,name='noticias',sort=TRUE)
if (!nrow(por_tema)) por_tema <- tibble::tibble(tema=character(),noticias=integer())

# 5. Tendencias temporales: no se reemplazan fechas ausentes con fecha de extracción.
tendencias <- noticias |>
  dplyr::filter(!is.na(dia)) |>
  dplyr::count(dia,name='noticias',sort=FALSE)
temas_dia <- noticias |>
  dplyr::filter(!is.na(dia)) |>
  dplyr::select(id,dia,dplyr::all_of(columnas_tema)) |>
  tidyr::pivot_longer(cols=dplyr::all_of(columnas_tema),names_to='tema',values_to='detectado') |>
  dplyr::filter(detectado) |>
  dplyr::mutate(tema=sub('^tema_','',tema)) |>
  dplyr::count(dia,tema,name='noticias')

# 6. Tabla para el futuro dashboard y chatbot (menciones y palabras distintivas).
# No sobreescribe las columnas crudas ni entrena un clasificador.
resumir_entidades <- function(t) {
  t |> dplyr::group_by(id) |>
    dplyr::summarise(entidades=paste(sort(unique(entidad)),collapse='; '),.groups='drop')
}
noticias_mineria <- noticias |>
  dplyr::left_join(resumir_entidades(menciones_equipos) |>
                     dplyr::rename(equipos_detectados=entidades),by='id') |>
  dplyr::left_join(resumir_entidades(menciones_competiciones) |>
                     dplyr::rename(competiciones_detectadas=entidades),by='id') |>
  dplyr::mutate(equipos_detectados=dplyr::coalesce(equipos_detectados,''),
                competiciones_detectadas=dplyr::coalesce(competiciones_detectadas,''))
readr::write_excel_csv(noticias_mineria,'data/procesados/mineria_noticias.csv',na='')

# 7. Guardar tablas para el informe y la fase 6.
guardar(frecuencias,'01_frecuencia_palabras.csv')
guardar(bigramas,'02_bigramas.csv')
guardar(top_tfidf,'03_tfidf_por_noticia.csv')
guardar(conteo_equipos,'04_equipos_mencionados.csv')
guardar(conteo_competiciones,'05_competiciones_mencionadas.csv')
guardar(por_tema,'06_temas_detectados.csv')
guardar(tendencias,'07_noticias_por_dia.csv')
guardar(temas_dia,'08_temas_por_dia.csv')
guardar(menciones_equipos,'09_detalle_menciones_equipos.csv')
guardar(menciones_competiciones,'10_detalle_menciones_competiciones.csv')

indicadores <- tibble::tibble(
  indicador=c('noticias_procesadas','tokens_utilizados','palabras_distintas',
              'bigramas_distintos','noticias_con_tema','noticias_sin_tema',
              'noticias_con_equipo_detectado','noticias_con_competicion_detectada',
              'noticias_con_fecha','noticias_sin_fecha','dias_distintos'),
  valor=c(nrow(noticias),nrow(tokens),nrow(frecuencias),nrow(bigramas),
          sum(rowSums(as.data.frame(noticias[,columnas_tema,drop=FALSE]))>0),
          sum(rowSums(as.data.frame(noticias[,columnas_tema,drop=FALSE]))==0),
          dplyr::n_distinct(menciones_equipos$id),
          dplyr::n_distinct(menciones_competiciones$id),
          sum(!is.na(noticias$dia)),sum(is.na(noticias$dia)),
          dplyr::n_distinct(noticias$dia,na.rm=TRUE))
)
guardar(indicadores,'00_reporte_fase5.csv')

# 8. Graficos; si la muestra no alcanza, no generamos graficos enganosos.
graficar_top <- function(df,columna,titulo,archivo,maximo=15) {
  if (!nrow(df)) return(invisible(NULL))
  df <- utils::head(df,maximo)
  names(df)[names(df)==columna] <- 'etiqueta'
  p <- ggplot2::ggplot(df,ggplot2::aes(x=stats::reorder(etiqueta,noticias),y=noticias)) +
    ggplot2::geom_col(fill='#176b89') + ggplot2::coord_flip() +
    ggplot2::labs(title=titulo,x=NULL,y='Noticias que mencionan la entidad') +
    ggplot2::theme_minimal(base_size=12)
  ggplot2::ggsave(file.path(salida,archivo),p,width=9,height=6,dpi=140)
}
if (nrow(bigramas)) {
  p <- ggplot2::ggplot(utils::head(bigramas,20),
    ggplot2::aes(x=stats::reorder(bigrama,frecuencia),y=frecuencia)) +
    ggplot2::geom_col(fill='#0f766e') + ggplot2::coord_flip() +
    ggplot2::labs(title='20 bigramas mas frecuentes',x=NULL,y='Frecuencia') +
    ggplot2::theme_minimal(base_size=12)
  ggplot2::ggsave(file.path(salida,'grafico_bigramas.png'),p,width=10,height=7,dpi=140)
}
graficar_top(conteo_equipos,'entidad','Equipos mas mencionados','grafico_equipos.png')
graficar_top(conteo_competiciones,'entidad','Competiciones mas mencionadas','grafico_competiciones.png')
if (nrow(por_tema)) {
  p <- ggplot2::ggplot(por_tema,ggplot2::aes(x=stats::reorder(tema,noticias),y=noticias)) +
    ggplot2::geom_col(fill='#2563eb') + ggplot2::coord_flip() +
    ggplot2::labs(title='Temas detectados en titulares y resumenes',
                  subtitle='Los temas se solapan; una noticia puede tener varios',x=NULL,y='Noticias') +
    ggplot2::theme_minimal(base_size=12)
  ggplot2::ggsave(file.path(salida,'grafico_temas.png'),p,width=9,height=6,dpi=140)
}
if (nrow(tendencias)>=2L) {
  p <- ggplot2::ggplot(tendencias,ggplot2::aes(x=dia,y=noticias)) +
    ggplot2::geom_line(color='#0f766e',linewidth=0.8) +
    ggplot2::geom_point(color='#0f766e') +
    ggplot2::scale_x_date(date_labels='%d %b',date_breaks='1 day') +
    ggplot2::labs(title='Noticias disponibles por fecha de publicacion',
                  subtitle='Fechas faltantes excluidas; solo publicaciones del RSS disponible',
                  x='Fecha (UTC)',y='Noticias') +
    ggplot2::theme_minimal(base_size=12) +
    ggplot2::theme(axis.text.x=ggplot2::element_text(angle=45,hjust=1))
  ggplot2::ggsave(file.path(salida,'grafico_noticias_por_dia.png'),p,width=10,height=5,dpi=140)
}

cat('\n===== REPORTE FASE 5 =====\n')
print(indicadores,n=Inf)
cat('\nTop 10 bigramas:\n'); print(utils::head(bigramas,10))
cat('\nTop 10 equipos:\n'); print(utils::head(conteo_equipos,10))
cat('\nTop 10 competiciones:\n'); print(utils::head(conteo_competiciones,10))
cat('\nAVISOS METODOLOGICOS:\n')
cat('- Las noticias sin tema detectado NO son errores: el diccionario no cubre todos los casos.\n')
cat('- Las menciones por reglas pueden tener falsos positivos/negativos; se revisaran manualmente.\n')
cat('- Los terminos TF-IDF son caracteristicos de documentos; NO equivalen a relevancia futbolistica.\n')
cat('- Con pocas noticias, las tendencias son DESCRIPTIVAS, no predicciones.\n')
if (sum(is.na(noticias$dia))>0) cat('- Hay noticias sin fecha; se excluyeron de los graficos por dia.\n')
cat('\nArchivo principal: data/procesados/mineria_noticias.csv\n')
cat('Reportes: reportes/fase5/\n')
cat('FASE 5 COMPLETADA\n')
