# FootDataAI

Observatorio de noticias de fútbol con **React + TypeScript, Tailwind CSS y Apache ECharts**, conectado mediante **Plumber** al procesamiento en **R**, la base **SQLite** y el chatbot local del proyecto.

## Ejecutar el proyecto

Requisitos: **R 4.4 o superior** y **Node.js 22.19 o superior** (incluye npm). Ejecuta los comandos desde una terminal en la carpeta raíz `FootDataAI`.

### Primera instalación

```powershell
Rscript R/instalar_web.R
cd frontend
npm.cmd install
npm.cmd run build
cd ..
Rscript api.R
```

Abre **http://127.0.0.1:8000**. La API sirve también la interfaz compilada: no hace falta mantener dos servidores abiertos para usar el sistema.

El repositorio incluye noticias procesadas. Si faltan los CSV, genera los datos primero:

```powershell
Rscript R/06_actualizacion.R
```

En macOS/Linux usa `npm` en lugar de `npm.cmd`. Los scripts se ejecutan desde la raíz, incluso cuando se trabaja con RStudio. En RStudio puedes ejecutar `source('api.R', encoding='UTF-8')` con el directorio de trabajo en `FootDataAI`.

### Las siguientes veces

```powershell
Rscript api.R
```

Abre **http://127.0.0.1:8000** y deja la terminal abierta. Detén el servidor con **Ctrl + C**. Si cambias el código de la interfaz, vuelve a ejecutar `npm.cmd run build` dentro de `frontend`.

### Desarrollo con recarga automática

Terminal 1, desde la raíz:

```powershell
Rscript api.R
```

Terminal 2:

```powershell
cd frontend
npm.cmd run dev
```

Abre **http://127.0.0.1:5173**. Vite envía `/api` a Plumber en el puerto 8000. Los datos siguen viniendo de R; no se usan noticias simuladas.

## La nueva interfaz

- **Panorama general:** indicadores reales, evolución diaria con zoom, distribución temática, treemap de equipos, red de coocurrencias y últimas noticias.
- **Noticias:** búsqueda en titulares, resúmenes y entidades; filtros combinables; ordenación; paginación; tarjetas/lista; detalle; enlace a BBC y noticias guardadas en el navegador.
- **Laboratorio:** red de equipos y competiciones con umbral de noticias compartidas, mapa de calor por día/hora UTC, dispersión de términos por documentos y TF-IDF, treemap y distribución temática.
- **Asistente:** consulta el motor existente de `R/05_chatbot.R`, muestra las noticias recuperadas y permite usar toda la base o el contexto filtrado. Conserva la conversación al navegar entre secciones mientras no recargues la página.
- **Fuentes y sistema:** seguimiento de las cuatro fases, actualización automática/manual, recarga local, fuentes RSS y registros de ejecución.
- **Exportar CSV:** descarga únicamente las noticias de la selección actual, con sus URLs y metadatos.

Los filtros de fecha, canal, equipo, competición, tema y búsqueda se combinan. Seleccionar un equipo, un nodo, un tema o un término en las visualizaciones aplica su filtro. Pulsar un punto de la evolución selecciona ese día y excluye registros sin fecha. El mapa de calor permite inspeccionar el conteo de cada celda. **Limpiar filtros** restaura el conjunto completo.

## Cómo se actualizan los datos

```text
BBC Sport RSS → 01_extraccion.R → 02_base_datos.R (SQLite)
             → 03_preprocesamiento.R → 04_mineria_datos.R
             → Plumber → React / gráficos / chatbot
```

La actualización reutiliza `R/06_actualizacion.R` y sus procesos separados. Conserva el historial por URL y respeta **60 minutos entre intentos de consulta RSS**, incluidos los fallidos. La actualización manual queda deshabilitada durante ese intervalo y mientras exista otro proceso activo. La aplicación revisa el estado cada cinco segundos y recarga la instantánea al terminar.

La actualización automática está **activada por defecto**. El servidor revisa cada minuto si corresponde consultar las fuentes, aunque no haya una pestaña abierta. Es necesario que **`Rscript api.R` continúe ejecutándose y el equipo esté encendido y conectado**. Al arrancar, la primera comprobación ocurre después de un minuto. No es una tarea instalada en el sistema operativo.

El interruptor de la sección Sistema cambia la configuración de la sesión del servidor. Para arrancar siempre sin actualizaciones automáticas en esa terminal:

```powershell
$env:FOOTDATA_AUTO_UPDATE='0'
Rscript api.R
```

Para recuperar el comportamiento predeterminado, establece la variable en `'1'`. Durante la actualización, las consultas usan la última instantánea completa en memoria. Si fallan los RSS, el sistema informa el error y conserva las noticias existentes. Si falla una fase posterior, revisa su registro y completa de nuevo el flujo antes de utilizar los derivados nuevos.

**Recargar datos locales** vuelve a leer los CSV disponibles sin llamar a BBC. Una actualización externa que cambie los archivos se refleja al recargar; una actualización iniciada desde la API se refleja automáticamente al finalizar.

## Qué significan las visualizaciones

- **Evolución:** noticias por fecha de publicación UTC, con ceros en los días intermedios sin publicaciones. Excluye fechas ausentes.
- **Temas:** distribución excluyente por tema principal. El filtro de un tema incluye también las noticias en las que aparece como tema secundario; por eso un filtro temático puede recuperar más registros que su porción del anillo.
- **Treemap:** noticias que mencionan cada equipo. Un artículo puede contar para varios equipos.
- **Red:** dos entidades se conectan cuando aparecen en una misma noticia. El grosor representa documentos compartidos. Se muestran hasta 28 entidades con mayor presencia y se omiten nodos sin conexiones tras aplicar el umbral. No representa causalidad ni resultados de partidos.
- **Mapa de calor:** conteos por día de semana y hora UTC, acumulados sobre la selección. No reemplaza fechas faltantes por la fecha de extracción.
- **TF-IDF:** se recalcula con los tokens de R para el conjunto filtrado: `(apariciones / tokens del documento) × ln(documentos totales / documentos con el término)`. El eje vertical muestra el máximo por documento, el horizontal los documentos que contienen el término y el tamaño las apariciones. Se muestran los 35 términos más frecuentes.

Son análisis descriptivos de titulares y resúmenes RSS, sin predicciones, sentimientos inventados ni artículos completos extraídos. Los diccionarios pueden omitir entidades o producir falsos positivos. El chatbot es un motor **local por reglas y búsqueda**, sin servicios de IA externos, sin claves API y sin generación libre de respuestas. Los titulares se conservan en inglés, como en la fuente original.

## Estructura

```text
api.R                         API y servidor de la interfaz compilada
app.R                         Interfaz Shiny anterior, conservada
R/01_... a R/08_...            Fases originales
R/09_servicios_web.R           Instantánea, filtros, estado y procesos
R/10_pruebas_web.R             Pruebas de los nuevos servicios
R/instalar_web.R               Instalación de dependencias de R
frontend/src/                 React, componentes y análisis de datos
frontend/package-lock.json    Versiones reproducibles de dependencias
frontend/dist/                Compilación local (ignorada en Git)
scripts/probar_api.py          Pruebas HTTP opcionales con Python 3
data/                         SQLite, noticias y tokens
reportes/fase8/                Estado y logs de actualización
```

Se corrigió la fase de minería para que `tema_principal` conserve su categoría textual en lugar de convertirse en `FALSE`. La API puede leer también los CSV antiguos afectados y reconstruir la categoría desde sus banderas temáticas.

## Verificaciones

```powershell
cd frontend
npm.cmd test
npm.cmd run build
cd ..
Rscript R/07_pruebas_chatbot.R
Rscript R/08_pruebas_integracion.R
Rscript R/10_pruebas_web.R
```

Con la API abierta, en otra terminal (Python es opcional):

```powershell
python scripts/probar_api.py
python scripts/probar_api.py --actualizar
```

El segundo comando realiza una actualización RSS real si el intervalo lo permite; verifica que la API siga atendiendo consultas y que el chat termine usando la nueva instantánea. No fuerza el intervalo de BBC. Las pruebas existentes de integración generan sus reportes en `reportes/fase9`.

## API local

| Método | Ruta | Función |
| --- | --- | --- |
| GET | `/api/health` | Estado del servicio |
| GET | `/api/snapshot` | Noticias, tokens y metadatos |
| GET | `/api/status` | Fase actual, intervalo RSS y modo automático |
| POST | `/api/chat` | `{ "question": "Noticias de Chelsea", "filters": {} }` |
| POST | `/api/update` | Inicia el flujo si no hay ejecución ni intervalo pendiente |
| POST | `/api/settings` | `{ "automatic": true }` |
| GET | `/api/logs` | Últimas líneas de los cuatro registros |

Los filtros del chat aceptan `query`, `source`, `topic`, `team`, `competition`, `from`, `to` e `includeUndated`. Fechas en formato `YYYY-MM-DD`. Los POST requieren JSON. El servidor escucha únicamente en `127.0.0.1`; no expone tu equipo a la red.

## Problemas frecuentes

- **`Rscript` no se reconoce:** agrega el directorio `bin` de tu instalación de R al PATH o usa la ruta completa al ejecutable. Ejemplo: `& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' api.R`.
- **`npm.ps1` bloqueado en Windows:** usa `npm.cmd`, como en los comandos de esta guía; no necesitas cambiar la política de ejecución.
- **Interfaz sin compilar:** ejecuta `npm.cmd install` y `npm.cmd run build` en `frontend`, luego reinicia la API.
- **Puerto 8000 ocupado:** detén la instancia anterior con Ctrl + C. Para usar otro puerto con la interfaz compilada: `$env:FOOTDATA_PORT='8001'; Rscript api.R`, y abre `http://127.0.0.1:8001`. En desarrollo Vite utiliza el puerto 8000 definido en `frontend/vite.config.ts`.
- **Avisos `LC_*=C.UTF-8` en Windows:** la API configura una región UTF-8 compatible para sus servicios y procesos hijos. En una terminal con ese valor heredado, para ejecutar las fases antiguas utiliza `$env:LC_ALL='English_United States.utf8'` antes de `Rscript`.
- **BBC no responde:** revisa Fuentes y sistema, la conexión y `reportes/fase8`. Los datos previos siguen disponibles. El siguiente intento debe respetar el intervalo RSS.
- **Candado pendiente tras un cierre abrupto:** comprueba primero que no haya ninguna actualización activa en ninguna terminal antes de retirar manualmente `reportes/fase8/actualizacion_en_curso.lock`.

Documentación técnica de referencia: [Plumber](https://www.rplumber.io/articles/programmatic-usage.html), [Tailwind con Vite](https://tailwindcss.com/docs/installation/using-vite) y [Apache ECharts](https://echarts.apache.org/en/option.html).
