
# ============================================================
# FOOTDATA AI
# FASE 1 - CONFIGURACION DEL ENTORNO
# Proyecto de Mineria de Datos
# ============================================================

cat("\n========================================\n")
cat("       FOOTDATA AI - FASE 1\n")
cat("========================================\n\n")

# 1. PAQUETES NECESARIOS

paquetes <- c(
  # Extraccion web
  "httr2",
  "jsonlite",
  "xml2",
  "rvest",

  # Procesamiento de datos
  "dplyr",
  "tidyr",
  "stringr",
  "lubridate",
  "readr",
  "tibble",

  # Mineria de texto
  "tidytext",
  "stopwords",

  # Base de datos
  "DBI",
  "RSQLite",

  # Dashboard y chatbot
  "shiny",
  "bslib",
  "ggplot2",
  "plotly",
  "DT",
  "scales"
)

# 2. INSTALAR PAQUETES FALTANTES

faltantes <- paquetes[
  !vapply(
    paquetes,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(faltantes) > 0) {

  cat("Instalando paquetes faltantes:\n")
  print(faltantes)

  install.packages(
    faltantes,
    repos = "https://cloud.r-project.org"
  )

} else {
  cat("Todos los paquetes ya estan instalados.\n")
}

# 3. VERIFICAR INSTALACION

estado <- data.frame(
  paquete = paquetes,
  instalado = vapply(
    paquetes,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
)

print(estado)

if (!all(estado$instalado)) {
  stop("Hay paquetes sin instalar. Revisar la consola.")
}

# 4. VERIFICAR CARPETA PRINCIPAL

carpetas_requeridas <- c(
  "R",
  "data",
  "data/crudos",
  "data/procesados",
  "www",
  "reportes"
)

# Crear carpetas faltantes
for (carpeta in carpetas_requeridas) {
  if (!dir.exists(carpeta)) {
    dir.create(
      carpeta,
      recursive = TRUE,
      showWarnings = FALSE
    )
  }
}

cat("\nCarpetas verificadas correctamente.\n")

# 5. VERIFICAR SQLITE

conexion <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = "data/futbol.sqlite"
)

DBI::dbExecute(
  conexion,
  "CREATE TABLE IF NOT EXISTS prueba_configuracion (
     id INTEGER PRIMARY KEY,
     mensaje TEXT
   )"
)

DBI::dbExecute(
  conexion,
  "INSERT INTO prueba_configuracion (mensaje)
   VALUES ('Conexion funcionando')"
)

resultado <- DBI::dbGetQuery(
  conexion,
  "SELECT * FROM prueba_configuracion
   ORDER BY id DESC LIMIT 1"
)

cat("\nPrueba de SQLite:\n")
print(resultado)

DBI::dbDisconnect(conexion)

# 6. VERIFICAR VERSION DE R

cat("\nVersion de R:\n")
print(R.version.string)

# 7. FINALIZACION

cat("\n========================================\n")
cat(" CONFIGURACION FINALIZADA CORRECTAMENTE\n")
cat(" FOOTDATA AI LISTO PARA DESARROLLAR\n")
cat("========================================\n")