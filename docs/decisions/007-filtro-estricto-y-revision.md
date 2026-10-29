# ADR 007 — Aceptación estricta, revisión explícita y reutilización antes de decodificar

Actualización: [ADR012](012-reconocimiento-dos-vistas.md) sustituye el descriptor original por dos vistas del mismo rostro. Los umbrales de este ADR se mantienen. Para reproducir sus conteos históricos con la herramienta actual, usar `--descriptor original`.

Estado: implementado y validado en CPH2637/API 36 con suite completa de 29 pruebas, perfilado adicional y diálogos a fuente real 200%; pendiente aceptación con álbum familiar. Sustituye el umbral automático de ADR 001/004 y amplía la caché de ADR 006.

## Problema y evidencia

El usuario indica que se incluyen fotografías de otras personas. La regla anterior aceptaba cualquier cara que superara coseno 0.363 con cualquiera de las referencias. Es el punto inicial del ejemplo SFace/LFW, no una garantía para álbumes con muchas comparaciones. No se encontró un error en el orden BGR/RGB, alineación o dimensiones del contrato OpenCV.

Se prepararon 400 imágenes públicas AT&T/ORL desde el archivo oficial de Cambridge (crédito AT&T Laboratories Cambridge), exclusivamente en /tmp y caché privada de QA. SHA-256 del ZIP: `509d763bd2276aa054d260d7f1000e8be212738134f2f83d8ff13bc2adf1c8ec`. Base histórica de 40 sujetos, imágenes frontales de 92×112 en gris, variaciones limitadas de expresión/gafas/pose; no representa álbumes familiares, edades o perfiles difíciles. No se distribuyen estas fotos ni vectores.

Protocolo declarado: sujetos 1–20 calibración, 21–40 evaluación; referencias 1, 1–2 o 1–4; consultar sólo imágenes posteriores a las referencias, positivos del mismo sujeto y negativos de los otros 19 del mismo split. Elegir en calibración el menor umbral de [0.50,0.55,0.60,0.65,0.70] con cero FP en los tres protocolos. Seleccionado 0.50. La evaluación no intervino en esa elección; es una comprobación interna separada por identidades, sin auditoría externa ciega. Los protocolos comparten imágenes y sus comparaciones no son observaciones independientes.

Host OpenCV 4.12.0 / FP32: una referencia pasa de 10 FP de calibración a 0; TP 180→179 de 180. En evaluación ambos criterios tienen 0 FP de 3420 negativos, TP 180→177 de 180. Las fotos positivas restantes siguen disponibles como pendientes. Dos/cuatro referencias: ver conteos completos y validación nativa en docs/validation.md. No se afirma una precisión universal del 100% ni reducción de FP en la evaluación donde ya eran cero.

## Decisión

- Automático MATCH: coseno >=0.50. REVIEW: [0.363,0.50). NONE: inferior. No se muestra similitud como certeza.
- Los casos REVIEW aparecen separados como **Por revisar**, sin selección múltiple ni compartir. El usuario puede abrir cualquier foto analizada, confirmar **Sí, es esta persona** o excluir **No es esta persona**. Una confirmación explícita permite compartir esa foto; no incorpora un rostro al modelo ni crea otra referencia.
- Confirmaciones/exclusiones sólo en RAM, asociadas al contenido exacto y persona actual (bytes completos y pipeline cuando hay snapshot; píxeles BGR/pipeline en el fallback). Repetir conserva la decisión; otra persona o contenido distinto no la hereda. Borrar sesión limpia feedback, detecciones, alias y embeddings. No hay aprendizaje automático a partir de resultados.
- Varias referencias siguen usando máximo coseno. No hay nuevo tope de referencias; QA de 1/2/4 no garantiza ausencia de falsos positivos con más ejemplos.

## Rendimiento y exactitud del cálculo

Preparar referencias una vez por lote y conservar vectores de comparación normalizados en caché. Mantener exactamente las dos normalizaciones FP32 previas (salida SFace→L2, luego L2 para coseno) y el producto acumulado en Double→Float. Comparación preparada idéntica al cálculo anterior, salvo la nueva decisión deliberada. La caché declara una nueva versión del formato; referencias y análisis exhaustivo siguen retornando el primer L2.

Antes de decodificar, leer el archivo completo autorizado y calcular SHA-256 incluyendo contrato ImageDecoder/maxEdge. Para archivos <=8 MiB se dispone de un snapshot de bytes; primera lectura decodifica ese mismo snapshot y usa su hash más la versión de pipeline como clave de análisis. No se necesita un segundo hash de todos los píxeles BGR. Un alias acotado permite localizar esa entrada al repetir y se descartan los bytes tras el análisis. Una repetición con alias válido puede comparar embeddings sin crear Bitmap/BGR ni repetir hash de píxeles. Se vuelve a leer el contenido y comprobar acceso; no se usa URI, fecha, tamaño o encabezado como identidad.

Alias limitados a 2048, caché nativa a 1024 entradas/20 MiB reservados. Hints concurrentes sólo orientan la preparación IO; el worker valida alias/entrada real. La ruta sin snapshot conserva SHA-256 de píxeles BGR, dimensiones y pipeline. Un archivo recodificado puede ocupar otra entrada aunque sus píxeles coincidan; se prioriza invalidación segura. Una entrada evictada o parcial que no alcanza MATCH solicita decodificación del mismo snapshot y completa las caras pendientes. Una foto vacía completa sí puede devolver NONE sin decodificar. Cambio de referencia siempre vuelve a comparar los vectores, no reutiliza una decisión de identidad.

Archivos >8 MiB usan la ruta URI original sin alias codificado; necesitan decodificación para validar sus píxeles. El límite evita retener archivos enormes, pero esa primera lectura parcial añade IO. Se conserva prefetch acotado a dos bitmaps; snapshots diferidos esperan liberación para evitar decodificaciones grandes solapadas. Cancelación recicla bitmaps y no emite resultados posteriores. No se cambian pesos, FP32, tamaño máximo, EXIF, detector ni sus dos escalas. No se añade persistencia o dependencia.

## Fuentes y reproducción

- [Base oficial AT&T/ORL](https://www.cl.cam.ac.uk/research/dtg/attarchive/facedatabase.html).
- [Ejemplo oficial SFace](https://github.com/opencv/opencv_zoo/blob/main/models/face_recognition_sface/sface.py).
- `tools/prepare_filter_qa.py --output /tmp/personas-filter-qa/android` verifica el ZIP y prepara PNG/manifest.
- `tools/evaluate_filtering.py --fixtures /tmp/personas-filter-qa/android --output /tmp/personas-filter-qa/metrics.json` selecciona sólo con calibración, informa evaluación separada y prepara regresiones dirigidas. Requiere OpenCV Python 4.12.0.88 y numpy 2.2.6; no mide el APK.
- Pruebas Android opcionales `FilteringTest` y `FilteringUiTest`, con `filterFixtures=qa-filter` y los PNG/JSON preparados dentro de la caché privada. Sin fixtures se omiten; producción nunca utiliza ejemplos.

## Límites

Subir el umbral reduce aceptación automática de algunas fotos correctas; revisión explícita compensa accesibilidad, no equivale a recuperación automática. Persisten limitaciones del modelo con perfil, baja resolución, edades y parecidos familiares. Hace falta evaluar el álbum etiquetado del usuario con negativos suficientes. El beneficio de caché depende de memoria y proveedor; leer/descargar archivos sigue costando, y la primera búsqueda puede conservar casi todo el trabajo nativo.
