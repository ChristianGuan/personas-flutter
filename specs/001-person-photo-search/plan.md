# Plan técnico

Incremento activo R21: interfaz y sesión migradas a Flutter en `flutter_app/`. [Plan multiplataforma](../002-flutter-migration/plan.md), [tareas](../002-flutter-migration/tasks.md) y [ADR 009](../../docs/decisions/009-migracion-flutter.md). Este documento conserva el diseño de la implementación Android nativa, reutilizada como motor y referencia de comportamiento.

Un módulo app, paquetes ui/domain/data. Compose en español, AndroidViewModel + StateFlow, coroutine de orquestación en Main y un ejecutor dedicado de concurrencia 1 para OpenCV. Decodificación en IO. PhotoSource y FaceEngine permiten sustituir acceso e inferencia sin dobles en producción.

## Prueba técnica

Photo Picker con fallback del contrato AndroidX para referencia y conjuntos. Se elimina el máximo explícito de 30 y se usa el máximo del sistema por tanda. Las selecciones se acumulan y deduplican por URI; alternativa OpenMultipleDocuments filtrada a image/*. La app no impone máximo total; el selector/proveedor puede limitar cada tanda. Vaciar conjunto conserva la referencia. Añadir fotos nuevas invalida resultados y selección compartida para no presentar una búsqueda incompleta como actual. URIs válidas durante la sesión; no se persisten ni se solicita retención de permisos innecesaria. Cancelar selector conserva selección anterior. Se advierte que proveedores remotos pueden necesitar descarga; no hay permiso INTERNET en la app.

ImageDecoder corrige orientación EXIF y usa bitmap software. Lado largo máximo 3200, proporción conservada; una foto por operación; previews a 512/1600. YuNet procesa la imagen decodificada completa, no una miniatura de 320 px; el modelo internamente reduce resolución. Cajas menores de 24 px se descartan. Este límite puede perder rostros pequeños de fotos de muy alta resolución y no garantiza detección en multitudes: V07 debe evaluar memoria/recuperación antes de decidir análisis por mosaicos con solape. No afirmar que el problema de caras pequeñas está resuelto.

YuNet produce caja y cinco landmarks en el orden de FaceRecognizerSF. RGBA → BGR; alignCrop realiza transformación de similitud a 112×112; feature aplica blob RGB, escala 1 y media 0 en OpenCV; salida de 128 floats, L2 y comparación coseno. Política actual R19 centralizada en Matching: >=0.50 automático, [0.363,0.50) revisión explícita; calibración pública con sujetos separados, pendiente álbum familiar. 0.363 fue el punto inicial del ejemplo oficial LFW. Nunca mostrarlo como confianza.

Progreso aumenta al terminar u omitir una foto; tiempo monotónico incluye decodificación e inferencia. Cancelación cooperativa: una llamada JNI no se interrumpe a mitad, se espera su retorno y luego se descarta el resultado si fue cancelada. Resultados parciales permanecen. Fallos de foto incrementan contador sin registrar URI/embedding. Inicialización fallida de motor en referencia produce error visible.

## Álbumes implementados en R14 e índice pendiente

MediaStore implementado: consultar sólo columnas de ID/bucket/nombre en cursor, agrupar por BUCKET_ID y volumen (no nombre); Android <=32 READ_EXTERNAL_STORAGE con maxSdk 32, 33+ READ_MEDIA_IMAGES y 34+ READ_MEDIA_VISUAL_USER_SELECTED. Consultas en IO y recorrido de cursor con cancelación; se cargan metadatos/URIs en memoria, no todos los bitmaps. No hay paginación de metadatos todavía; medir con bibliotecas grandes. Reconsultar al volver a foreground porque el permiso puede cambiar. El selector es alternativa independiente, no equivalente a permiso global ni a álbum remoto.

Room propuesto: PhotoIndex(uriHash, contentDigest, modelDigest, preprocessingVersion, completedAt), FaceEmbedding(photoKey, ordinal, vector). Clave versionada incluye ambos modelos y estrategia EXIF/resize/alineación. No indexar sólo por URI: metadata de proveedores puede no reflejar edición; calcular digest del contenido si no hay versión fiable. Transacción por fotografía completa, incluso cero rostros; cancelación no deja entradas parciales. No persistir fotos/recortes. Revalidar accesibilidad al abrir/compartir y purgar referencias inaccesibles. Borrado transaccional de todas las tablas. Excluir DB de backup y transferencia; usar almacenamiento privado sin rutas en logs. Ninguna tabla creada todavía.

Compartir: intersección de resultados y selección, deduplicada; content URIs, ClipData y FLAG_GRANT_READ_URI_PERMISSION; destinatario manual. V04 debe comprobar grants del proveedor en Android físico.

## Interfaz ampliada (R12)

Una sola LazyVerticalGrid aloja cabecera, tarjetas de pasos y resultados con elementos de ancho completo; no hay grillas de desplazamiento anidadas. Scaffold con acción inferior fuera del contenido desplazable, navegación segura y tema claro/oscuro verde. Referencia con recuadros y chips de rostro alternativos para accesibilidad. Selección de resultados, deseleccionar todas, ampliación y confirmación al borrar sesión. Las miniaturas visibles usan un semáforo de dos decodificaciones concurrentes para evitar una ráfaga al aparecer muchos resultados.

## Diagnóstico de recuperación (R13)

SearchState conserva PhotoReview(uri, outcome) por foto procesada durante la sesión. Cero FoundFace -> sin rostros utilizables; alguna coincidencia -> MATCH; caras sin coincidencia -> BELOW_THRESHOLD; excepción -> UNREADABLE (puede ser lectura o inferencia). Sin scores ni embeddings adicionales en el diagnóstico. La UI presenta conteos y miniaturas de descartadas expandibles, sólo para revisión. No se cambian umbrales sin evidencia de etapa y evaluación con negativos. No hay comprobación explícita de apertura de ojos en este pipeline.

## Implementación R14 — rediseño por pasos

Reemplazar la pantalla continua por HOME / REFERENCE / ALBUMS / ANALYSIS / RESULTS en StateFlow del ViewModel. Tema propio con superficies teñidas, acento índigo, escala de espaciado 4/8/12/16/24/32, formas 12/20/28 dp y tipografía Material escalable. Componentes reutilizables para foto, recorte, estado vacío, contexto de búsqueda y acción inferior. Animaciones Compose finitas de 180 ms (respetan duración del sistema), sin dependencias nuevas. Una cuadrícula lazy por pantalla, scaffold con insets y barra inferior fuera de fotos.

Álbumes reales: MediaStore por volumen y BUCKET_ID, sin usar rutas físicas; portada de última foto visible y conteo de imágenes autorizadas. Permiso de imágenes opcional por versión Android; acceso limitado etiquetado, recargar al volver a primer plano; denegación con selector individual como siguiente acción. No acceso a álbumes privados/remotos de otras apps. Cargar consultas y URIs en IO, thumbnails acotadas; conservar ejecutor de inferencia y compartir con grants temporales. Invalidar selección de álbum al refrescar permisos para no reutilizar un conjunto inaccesible. No conservar permisos URI innecesarios.

R14 sustituye el diseño continuo verde de R12: el tema y las pantallas actuales están centralizados y usan índigo. La cuadrícula adapta columnas a ancho y tamaño de fuente (celda mínima 144 dp, 240 dp con fuente grande). La barra fija está fuera del viewport de fotos y consume su propio espacio de Scaffold. El encabezado se acorta a “Paso N de 3” con texto grande.

Concurrencia: las consultas de biblioteca tienen generación; una respuesta cancelada/obsoleta no puede sobrescribir una selección nueva. Volver del selector individual cancela refrescos pendientes para no perder sus URIs si coinciden con ON_RESUME. Salir de álbumes cancela la consulta de biblioteca. El análisis sigue siendo serial en el ejecutor existente, con modelos/umbral/preprocesamiento sin cambios.

Fuentes oficiales: https://developer.android.com/about/versions/14/changes/partial-photo-video-access ; https://developer.android.com/training/data-storage/shared/media ; https://developer.android.com/develop/ui/compose/animation/quick-guide ; https://developer.android.com/develop/ui/compose/testing .

## R15 — Selección de grupos y detección multiescala

No había una constante que limitase la selección a tres. Se reemplaza el FlowRow de chips por elementos lazy independientes con recorte y estado seleccionado, para que la altura del bloque no limite la lista. El toque sobre cajas superpuestas elige la menor caja contenedora.

YuNet se ejecuta en la imagen decodificada y, si supera 960 px de lado largo, también en una copia de lado máximo 960. Cajas y cinco landmarks se reproyectan mediante factores X/Y reales; se conservan detecciones de al menos 24 px en coordenadas originales y se fusionan con NMS IoU>0.4 conservando mayor score. Orden visual estable arriba/abajo e izquierda/derecha. SFace alinea y genera embeddings desde la imagen original de análisis, no desde la copia reducida. Modelos sin cambios; detector 0.65 exclusivamente en referencia, 0.85 en las fotos de búsqueda y coseno 0.363 para reconocer. Coste adicional: hasta una inferencia de detección extra por foto; la cancelación espera el retorno de las operaciones nativas.

El futuro índice deberá incluir la nueva versión de preprocesamiento/detección `yunet-multiscale-v2`. Esta app aún no persiste embeddings, por lo que no hay índice existente que migrar. No se garantiza detectar toda cara real ni se atribuye el reporte de tres rostros a una causa confirmada sin repetir con la foto original.

Aclaración del usuario en R15: sólo se dibujaban tres recuadros, por lo que la limitación reportada es de detección y no únicamente del selector. Se añade `analyzeReference`: YuNet usa score mínimo 0.65 exclusivamente en la referencia que el usuario revisa; el análisis del conjunto continúa con 0.85 y SFace/coseno con 0.363. El score de detección se restablece explícitamente en cada llamada del detector compartido. Es un punto inicial interno para admitir más candidatos, no una calibración universal; puede mostrar candidatos espurios que el usuario debe evitar. La segunda escala complementa este cambio. Versión futura de índice: detección multiescala v2 y política de referencia v2 (los embeddings de álbum siguen su política 0.85).

## R16 — Variabilidad de la referencia

Revisado contrato SFace contra implementación oficial 4.12.0: blob RGB escala 1, media 0 y alineación 5 puntos coinciden con el código actual. No se detectó un error evidente de dimensiones/canales; se reproduce pérdida por pose/iluminación usando fotos distintas de un vídeo oficial de OpenCV. El mismo sujeto puede quedar bajo coseno 0.363 desde una referencia menos representativa; bajar ampliamente el umbral también puede aceptar controles negativos.

Conservar umbral 0.363 y añadir ejemplos de la misma persona confirmados manualmente. SearchState guarda ReferenceExample(thumbnail, embedding), únicamente para referencias anteriores, y la referencia/rostro actual. En append, capturar ejemplo anterior y detectar la foto nueva fuera de Main; commit atómico sólo si hay caras utilizables; error/cancelación conserva estado válido. Comparación: máximo coseno entre referencias y caras de cada foto, sin promediar poses distintas ni elegir ejemplos automáticamente. Preview de descartada lleva al paso de referencia con elección explícita de rostro. Acción inferior permite repetir en el mismo conjunto, sin navegar a álbumes e invalidarlo. Cambiar de persona elimina ejemplos anteriores.

No añadir persistencia ni caché de embeddings del conjunto en este cambio. Se reanaliza cada fotografía, con el progreso real existente. Las miniaturas de referencia se reducen a 256 px en Default; embeddings/fotos permanecen en dispositivo. La prueba opcional de integración usará recursos públicos en caché privada, excluyendo las fotos semilla del conjunto de comparación cuando mida recuperación de prueba.

El usuario puede quitar referencias anteriores y repetir con el mismo conjunto aunque sólo quede la referencia actual. Al elegir otra persona se limpian los ejemplos anteriores una vez preparada la nueva foto. El aviso de rostro pequeño usa menor lado de caja <80 px sólo como recomendación, no como rechazo ni garantía de calidad. Los ejemplos repetidos con coseno >0.9999 no duplican el ancla anterior; la referencia actual sigue disponible para confirmar.

QA opcional preparado con tools/prepare_recognition_qa.py: exclusivamente recursos públicos externos al APK. Las semillas se excluyen de los positivos del test, pero la elección de la segunda referencia se hizo observando la misma prueba; no es una validación ciega ni independiente. Guardar únicamente conteos y tiempos de prueba, sin exportar embeddings o fotos personales. V12 incluye también el flujo UI de usar una descartada, expresamente confirmada, y la conservación de ejemplos ante error/cancelación.

## R17 — Fuentes cloud autorizadas

Reutilizar PickVisualMedia/PickMultipleVisualMedia para contenido local y cloud; no fijar EXTRA_LOCAL_ONLY. Incorporar acceso «Google Fotos» con diálogo desplazable que permite abrir el selector o ACTION_PICK_IMAGES_SETTINGS; capturar ActivityNotFoundException y SecurityException con siguiente acción útil. No cambiar el proveedor ni la cuenta sin intervención del usuario. Los ajustes pueden faltar en Android antiguo; siguen disponibles Compartir → Personas y Archivos (Drive).

Registrar ACTION_SEND/ACTION_SEND_MULTIPLE image/* en MainActivity. Una única actividad por tarea conserva el ViewModel cuando llegan más fotografías; onNewIntent atiende la nueva selección. Validar extras/ClipData y MIME en IO, sin logs/rutas ni copias persistentes. El ViewModel conserva la propuesta de importación en memoria; un diálogo permite descartarla, usar una foto como referencia o añadirlas al conjunto, sin alterar un análisis activo. La navegación a álbumes requiere una referencia elegida; si se reciben fotos antes, ir a referencia y conservarlas para buscar después.

No integrar la Library API: actualmente administra contenido creado por la propia app, no permite enumerar toda la biblioteca preexistente. El Photo Picker evita necesitar un proyecto OAuth para este acceso. La disponibilidad de nube depende de Android, actualizaciones y configuración del proveedor. Los originales remotos son entregados por el proveedor; no se modifica el pipeline de identidad ni se promete acceso offline a archivos no descargados.

R17 cambia la invalidación incondicional de álbum al volver a foreground: mientras libraryLoading bloquea buscar, reconsultar catálogo y URIs del álbum seleccionado; conservar conjunto y resultados si siguen iguales. Si cambia el conjunto autorizado, sustituirlo e invalidar resultados; ante revocación total o error de revalidación, limpiar álbum/conjunto. Así cancelar el selector o los ajustes no vacía un álbum que sigue disponible, manteniendo la protección ante cambios de permisos.

Fuentes: https://developer.android.com/training/data-storage/shared/photo-picker ; https://developer.android.com/reference/android/provider/MediaStore#ACTION_PICK_IMAGES_SETTINGS ; https://developer.android.com/training/sharing/receive ; https://developers.google.com/photos/overview/about .

## R18 — Menos trabajo redundante, mismo reconocimiento

Perfilado previo: el pipeline genera todos los embeddings antes de aplicar any-match y reanaliza las fotos completas al cambiar/añadir referencias. Separar los dos detectores por escala se probó en host y no mejoró el tiempo, por lo que se descarta ese cambio sin evidencia Android. Conservar el detector y sus dos pasadas actuales, Core threads=2 y el reconocimiento FP32.

OpenCvFaces añade match(bitmap,references): ambas escalas y NMS se completan antes de comparar; al primer match se puede retornar exactamente la misma decisión lógica sin calcular embeddings de caras posteriores. analyze/analyzeReference siguen devolviendo todos los rostros. Reutilizar row/crop/feature Mat entre las caras de una misma llamada sin cambiar operaciones numéricas.

Caché LRU sólo RAM, máximo 1024 fotos / 20 MiB de vectores y detecciones (presupuesto calculado reservando los embeddings pendientes). La clave incluye el pipeline y un hash de los bytes BGR contiguos y dimensiones; se calcula después de decodificar/convertir, por lo que no hay una carrera entre hash de archivo y decodificación de una versión diferente. Guardar las 15 floats de TODAS las detecciones y un embedding nullable por cara. Una entrada parcial nunca se trata como análisis negativo completo; al cambiar referencia se calculan las caras pendientes si hace falta. Referencia con score 0.65 no reutiliza la caché de búsqueda 0.85. Sin URI, fotos o recortes persistidos, ni cambio a backup/permisos. Borrar sesión limpia también esta caché mediante el mismo worker serial.

BatchPhotoSearch: productor IO y canal rendezvous con limpieza onUndeliveredElement. Como máximo dos bitmaps de análisis: actual y siguiente preparado; no una cola de álbum completo ni varios motores compartiendo instancias JNI. Decodificación cancelada libera el bitmap aunque withContext descarte el resultado. Consumidor conserva orden, ejecuta inferencia+comparación en una única llamada al worker y emite un resultado/progreso por foto terminada. Liberar el bitmap actual en finally; cancelar productor/canal en toda salida. Mantener previews limitadas a dos decodificaciones pequeñas.

Si el bitmap actual supera 16 MiB, el productor espera su liberación antes de decodificar el siguiente, para evitar mantener dos fotografías grandes junto al workspace nativo. Es una política de memoria; no reduce resolución ni altera píxeles.

La verificación de modelos al inicializar conserva SHA-256 y hashes oficiales, leyendo bloques de 64 KiB en vez de cargar todos los bytes de SFace en un array de unos 38 MB. Esto reduce la asignación temporal de inicialización, no el trabajo nativo por foto.

Comparar búsqueda anterior completa y nueva en recursos públicos opcionales; comprobar igualdad de decisiones y bit patterns de embeddings reutilizados, cambio de contenido/referencia, expulsión, cancelación y errores. Medir separadamente cold/warm e inicialización; no incluir selección de referencia en búsqueda ni extrapolar resultados host al teléfono. Si no está conectado, compilar/tests JVM y registrar validación Android pendiente.

Fuentes: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.channels/-channel/ ; https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.channels/-receive-channel/cancel.html .

V14 ejecutado posteriormente en CPH2637/API 36 con el dispositivo conectado: 23 pruebas instrumentadas aprobadas, incluida comparación de recorrido completo/primero/repetido, entrada parcial con nueva referencia y limpieza por cancelación. Evidencia, tiempos y límites en docs/validation.md. El perfilado host anterior no se sustituye ni se presenta como medición Android; ahora hay una comparación adicional hecha en el teléfono.

## R19 — Política estricta con revisión y acceso codificado reutilizable

Preparar QA público AT&T/ORL (40 sujetos ×10 imágenes) desde el archivo oficial de Cambridge, fuera de APK/Git, con crédito y SHA-256. Sujetos 1–20 para calibrar, 21–40 para evaluar; seleccionar el menor umbral >=0.50 de una rejilla fija con cero falsos positivos de calibración para protocolos 1/2/4 referencias. Publicar TP/FP/FN y pendientes, fallos de detección y límites; no usar la evaluación para ajustar. El umbral no es una probabilidad ni una calibración de álbumes familiares.

Matching añade MATCH/REVIEW/NONE y PreparedReferences. Normalizar cada referencia una vez por batch y guardar en caché el vector de comparación normalizado por segunda vez, reproduciendo la normalización que antes hacía cada cosine. Producto escalar Double y redondeo Float iguales. La parada temprana sólo es válida para MATCH estricto; REVIEW requiere seguir buscando una cara fuerte. Mantener geometría completa y embeddings parciales explícitos.

ContentPhotos.prepare lee hasta 8 MiB de bytes codificados y obtiene huella con maxEdge/versión de decodificación. Un indicio concurrente acotado de OpenCvFaces permite preparar sólo los bytes si hay un análisis reutilizable. El worker valida que existe el registro por contenido/pipeline y que los embeddings conocidos bastan; si no, decodifica los mismos bytes preparados en IO. En primer análisis se decodifican en el productor como antes. Cuando hay snapshot, la clave del análisis combina hash de bytes y pipeline y evita un segundo hash redundante de todos los píxeles; el fallback conserva clave BGR. Un alias sin análisis completo reutilizable nunca puede producir un negativo; expulsión o indicio obsoleto obliga a fallback. Archivos mayores del límite o sin ruta de bytes válida se decodifican mediante la ruta original sin alias. Las fotos no quedan persistidas.

VM conserva decisión y huella por foto, más huellas confirmadas/rechazadas manualmente de esa sesión/persona. Confirmar un candidato lo incorpora como confirmado por el usuario; rechazar lo elimina de resultados/selección y repetir conserva el descarte sólo si la huella coincide. Nueva persona y cambio de rostro limpian rechazos. UI: Por revisar separado de resultados y descartadas, acciones explícitas y selección/compartir sólo sobre resultados aceptados. No hay autoaprendizaje ni autoexpansión de referencias.

## R20 — Decodificación HEIC compatible con OpenCV

Inspección: ContentPhotos sólo fija ALLOCATOR_SOFTWARE y maxEdge; no fija color ni garantiza configuración. Utils.bitmapToMat de OpenCV 4.12 admite RGBA_8888/RGB_565, no RGBA_F16/RGBA_1010102. Un HEIC/HDR puede producir bitmap incompatible aunque ImageDecoder abra el contenedor. Confirmación del usuario: los archivos aparecen, el error ocurre al abrir; conservar selección/MIME.

Fijar sRGB en ImageDecoder y normalizar su salida software a ARGB_8888 mediante Canvas sobre destino sRGB cuando haga falta. Reutilizar sin copia la salida ya compatible. Reciclar fuentes intermedias y salida abandonada por cancelación; conservar tamaño/orientación decididos por ImageDecoder. Una única función debe servir para URI y snapshots, referencias, previews y búsqueda. Actualizar contrato/hash de decodificación y pipeline. Error de decodificación explícito en referencia sin sustituir referencias válidas; errores de lote siguen siendo UNREADABLE, nunca negativos de identidad.

La prueba Android mostró rechazo nativo de HEIC de 10 bits, incluido IOException genérico en el teléfono. Capturar IOException de ImageDecoder y, sólo para contenedores HEIF, usar `io.github.awxkee:avif-coder:3.0.0:release@aar` local. Máximo 64 MiB codificados y 100 millones de píxeles declarados, un fallback simultáneo en IO; el codec puede decodificar antes de reducir, por lo que sigue pendiente medir memoria. Compile SDK 36 requerido por el AAR; min 28 y target 35 sin cambios. Licencias e inventario incluidos en assets; ver ADR 008.

El codec 3.0.0 trata RGBA como RGB al aplicar orientación HEIC. Adaptador acotado `HeifOrientation`: validar cajas ISO-BMFF y asociaciones v0 de la imagen primaria, retirar únicamente asociaciones irot/imir en copia RAM, decodificar y aplicar giros/espejos mediante Matrix. Conservar crop/color, offsets, otros ítems y original; rechazar variantes no admitidas explícitamente. Retirar el adaptador al actualizar a una versión con orientación RGBA comprobada.

Preparar fixtures HEIC reales desde muestra pública (8/10 bits, sRGB/P3 y ocho orientaciones sobre imagen no cuadrada) en /tmp; registrar hashes y herramienta. Pruebas reales ContentPhotos/OpenCvFaces/VM, comparación de píxeles y referencia/batch/preview/caché; F16 sintético sólo comprueba compatibilidad del formato. Mantener pesos, umbral estricto/revisión, permisos y compartir. Registrar ejecución concreta en dispositivo y emulador.
