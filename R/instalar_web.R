# Ejecutar una vez desde la raíz: Rscript R/instalar_web.R
paquetes <- c('plumber','jsonlite','processx','later','httr2','xml2','dplyr',
              'readr','tibble','stringr','DBI','RSQLite','tidyr','tidytext',
              'stopwords','ggplot2','scales')
faltan <- paquetes[!vapply(paquetes,requireNamespace,logical(1),quietly=TRUE)]
if (length(faltan)) install.packages(faltan,repos='https://cloud.r-project.org')
if (!all(vapply(paquetes,requireNamespace,logical(1),quietly=TRUE))) stop('Hay paquetes pendientes de instalar.')
cat('Dependencias de R listas. Compila frontend y ejecuta Rscript api.R.\n')
