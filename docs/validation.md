# Validación — 2026-10-21

## Entorno observado

Carpeta inicialmente vacía; no AGENTS.md ni proyecto que preservar. JDK Oracle 21.0.10, Android SDK local con android-35 y android-36.1. Sin Gradle global en PATH; Wrapper oficial 8.13 descargado y ejecutado con verificación de SHA-256. ADB 37.0.0: tras permitir ejecución fuera del sandbox inició correctamente; `adb devices` no mostró dispositivos. `emulator -list-avds` devolvió lista vacía. No instalación ni ejecución Android realizadas.

## Verificaciones ejecutadas

| ID | Requisitos | Comprobación | Resultado |
|---|---|---|---|
| B01 | R01–R09 | `./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --console=plain` | BUILD SUCCESSFUL; ejecutado otra vez tras ajustes finales |
| U01 | R04 | Invariancia de coseno a escala, rechazo de vectores nulos/NaN, similitud negativa y rechazo de cara distinta | Aprobado |
| U02 | R04,R05 | Coincidencia de cualquier rostro de grupo; lista vacía no coincide | Aprobado |
| U03 | R07 | Intersección selección/resultados, exclusión de ajenos y deduplicación | Aprobado |
| M01 | R04,R09 | `python3 tools/models.py --check` | Ambos ONNX tienen tamaño y SHA-256 oficiales exactos |
| V01–V07 | Todos | Flujo/galería/inferencia/compartir/permisos en Android y evaluación real | Pendiente: no hay dispositivo ni álbum etiquetado |

JUnit: 8 pruebas, 0 fallos, 0 errores. No se han escrito tests de álbumes/índice que aún no se implementan. Se deberán añadir en T11/T12.

Lint final: 0 errores y 9 advertencias; advertencias de versiones más nuevas y target/compile 35. No se ocultaron mediante baseline. Las advertencias iniciales de backup e icono se resolvieron agregando reglas de extracción y un recurso vectorial. El APK universal incorpora las bibliotecas nativas de varias ABI y pesa aproximadamente 197 MiB; no es una entrega optimizada para tienda. No disponer de strip de símbolos no impidió compilar.

## Evaluación pendiente T10 (R11)

1. Instalar en Android físico API 28+ con `adb install -r app/build/outputs/apk/debug/app-debug.apk`. Registrar marca/modelo, API, RAM, versión app, hashes de modelos, umbral, tamaño original de imágenes y temperatura/estado de batería.
2. Preparar fuera de Git un álbum consentido real con positivos, negativos y fotos grupales. Separar fotos para calibración y un conjunto de evaluación sin ajustar el umbral sobre él. La referencia no debe ser una copia exacta del positivo del test.
3. Etiquetar manualmente presencia/ausencia por foto; incluir perfiles, cambios de edad, poca luz, oclusiones y caras pequeñas. Comenzar con un lote pequeño y después repetir con >30 fotos. El límite inicial de 30 ya fue retirado; el selector de Android puede limitar cada tanda, acumulable.
4. Elegir cara y conjunto, ejecutar en modo avión con archivos locales; registrar duración total mostrada y conteo de omitidas. Probar primero con caché de modelos fría y repetir caliente. Registrar referencia y selección correctas sin publicar las imágenes ni sus rutas.
5. Clasificar TP, FP, FN, TN contra etiquetas. Fotos ilegibles se informan aparte con cobertura, no se convierten silenciosamente en negativos correctos. Precisión = TP/(TP+FP), recuperación = TP/(TP+FN); denominador cero se registra como no definido. Registrar conteos FP y FN, tamaño del conjunto, omitidas y tiempo total.
6. Calibrar Matching.THRESHOLD sólo con conjunto de calibración, registrar cambio y repetir evaluación separada. La similitud coseno no es porcentaje de certeza.
7. Ejecutar V01–V04,V07: EXIF y rostros múltiples; conjunto aislado; sin coincidencias; cancelar y repetir; revocar/eliminar acceso; imagen corrupta; seleccionar/deseleccionar y verificar contenido recibido por otra app.

No hay métricas de precisión/recuperación del producto: no se proporcionaron fotos de evaluación ni dispositivo. Los resultados de LFW del proveedor no sustituyen esta evaluación.

## Límites concretos

- Implementada prueba técnica con inferencia real en código; aceptación end-to-end Android pendiente.
- Sin álbumes consultables por MediaStore ni índice persistente: T11/T12, después de T10.
- Sin retención de permisos ni recuperación de sesión tras muerte del proceso; volver a seleccionar.
- La cancelación espera el retorno de la operación nativa en curso; no hay interrupción JNI.
- Resize a 3200 y corte de cajas <24 px requieren evaluar recuperación y memoria; T13.
- Compartir grants del proveedor, disponibilidad remota y comportamiento de selectores/OEM requieren dispositivo.
- El borrado actual elimina referencias/embeddings de la sesión en memoria; no constituye borrado seguro de RAM ni un índice persistente. Las únicas copias de archivo creadas por la app son modelos públicos en noBackupFilesDir.

## Inferencia ejecutada en host (M02, R04)

Se ejecutó `tools/smoke_models.py` en un venv temporal con opencv-python-headless 4.12.0.88 y numpy 2.2.6. Muestra descargada a /tmp desde https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/lena.jpg; no se incorpora al proyecto.

Resultado observado: 1 rostro detectado, alignCrop 112×112×3, embedding finito de 128 dimensiones; una imagen negra no produjo caras. Tiempo medido 89.3 ms en este host macOS arm64 con dos hilos, incluida carga de modelos en el bloque medido. No es tiempo Android, benchmark de álbum, ni medida de precisión/recuperación. El script no imprime vectores, landmarks, imágenes ni rutas. No sustituye T10.

Reproducción opcional (fuera del entorno Android):

```sh
python3 -m venv /tmp/personas-model-check
/tmp/personas-model-check/bin/pip install opencv-python-headless==4.12.0.88 numpy==2.2.6
/tmp/personas-model-check/bin/python tools/smoke_models.py /ruta/a/imagen-de-prueba.jpg
```

## Validación posterior en dispositivo conectado — 2026-10-21

Dispositivo reportado por ADB: modelo CPH2637, Android API 36. No se registra el número de serie.

- `adb install -r app/build/outputs/apk/debug/app-debug.apk`: Success.
- `adb shell am start -W -n co.local.personas/.ui.MainActivity`: Status ok, arranque frío, TotalTime 1049 ms. Este tiempo es de apertura de la actividad, no de búsqueda facial.
- `adb shell pidof co.local.personas`: proceso presente después del arranque.

Instalación e inicio comprobados. La ausencia de dispositivo descrita arriba corresponde a la comprobación inicial y ya está resuelta. No se han elegido ni extraído fotos del dispositivo. T10 sigue pendiente de selección manual de referencia y conjunto por el usuario, ejecución de inferencia Android y revisión de coincidencias, cancelación y compartir. Todavía no hay métricas de precisión/recuperación.

## Incremento R12 — selección ampliada y UI

Se elimina PickMultipleVisualMedia(30) y se usa el máximo predeterminado del sistema; selección acumulativa por URI, OpenMultipleDocuments alternativo y vaciar conjunto. Interfaz con tarjetas, tema claro/oscuro, barra de acciones inferior, una cuadrícula lazy y chips para selección accesible del rostro. Miniaturas con concurrencia máxima de dos.

Comando ejecutado: `./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --console=plain`: BUILD SUCCESSFUL. Las 8 pruebas existentes de comparación/selección compartida pasan; lint 0 errores, 9 advertencias. Estos checks no prueban la selección >30 en el proveedor del dispositivo. V08, el rendimiento de álbumes grandes y la inferencia Android con fotos reales siguen pendientes.

Fuentes API: https://developer.android.com/training/data-storage/shared/photo-picker y https://developer.android.com/reference/androidx/activity/result/contract/ActivityResultContracts.OpenMultipleDocuments.

La actualización R12 se instaló en CPH2637/API 36 con `adb install -r`: Success. `am start -W` devolvió Status ok (arranque frío 1461 ms; no tiempo de búsqueda). Al revisar pantalla, el usuario estaba usando el selector de fotos; no se alteró su selección ni se confirmó en su nombre. Revisión visual de la pantalla principal actualizada pendiente; no se considera aprobada por el arranque. Captura temporal descartada, no incluida en el repositorio.

## Reporte de campo y diagnóstico R13

El usuario reporta una búsqueda de 11 fotos donde aparece la persona, con 6 resultados; algunas tienen ojos cerrados. Reporte manual, no reproducción independiente. No se conoce aún cuáles de las cinco ausentes fallaron en detección, tamaño mínimo, comparación o lectura. No se atribuye causalidad a los ojos cerrados ni se extrapola precisión general. Se necesitan también negativos para evaluar falsos positivos antes de calibrar.

Se agrega revisión de fotos procesadas por categoría: coincidencia, cero rostros utilizables, rostros sin coincidencia suficiente y error de análisis/lectura. “Sin rostros utilizables” puede incluir detecciones descartadas por tamaño mínimo; no significa que la imagen no contenga personas. “Sin coincidencia suficiente” no demuestra que se detectó específicamente el rostro buscado si hay otras personas en la foto. Las descartadas se pueden ampliar, pero no se agregan a la selección compartida. Diagnóstico sólo en memoria, sin escribir fotos, URIs, scores ni embeddings a logs/Git.

No se modificaron detector (0.85), tamaño mínimo (24 px) ni umbral de reconocimiento (0.363). Compilación, 8 pruebas unitarias existentes y lint completados: BUILD SUCCESSFUL; lint 0 errores y 9 advertencias. La UI de diagnóstico y la reproducción de 11 fotos siguen pendientes de comprobación manual.

Siguiente V09: repetir con idéntica referencia y las mismas 11 fotos; abrir “Revisar fotos descartadas” y registrar sólo conteos de categorías. Examinar localmente las ausentes; si no hay rostro utilizable, evaluar detector/escalas/tamaño; si hay rostros, comprobar que se detectó el objetivo antes de calibrar comparación. Después repetir con positivos y negativos separados de calibración. No bajar umbrales a partir de un conjunto sólo positivo.

Versión de diagnóstico instalada en CPH2637/API 36: instalación Success y apertura Status ok (1514 ms de arranque, no de inferencia). Pendiente repetición V09 por el usuario.

## R14 — Rediseño visual 0.2 y álbumes (2026-10-21)

### Implementado

Cinco pasos HOME/REFERENCE/ALBUMS/ANALYSIS/RESULTS, tema centralizado índigo claro/oscuro, gradiente suave sólo en el destacado del inicio, fotografías reales, recorte del rostro, chips accesibles, álbumes MediaStore opcionales, progreso real, resultados progresivos, selección y revisión completa. Se conservan la revisión de descartadas y el mecanismo nativo de compartir con ClipData/grants. No se cambian modelo, preprocesamiento ni umbrales. No hay nuevas dependencias visuales de producción. Se añaden dependencias androidTest fijadas (Compose UI tests con el mismo BOM, runner 1.6.2 y ext:junit 1.2.1).

### Verificaciones ejecutadas

- `./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug --console=plain`: BUILD SUCCESSFUL. 8 pruebas JVM, 0 fallos. Lint: 0 errores y 14 advertencias (versiones disponibles, target SDK 35 y dos sugerencias UseKtx; no ocultadas).
- CPH2637, Android API 36: pruebas instrumentadas mediante `adb shell am instrument -w -e class co.local.personas.ui.FlowUiTest -e faceFixture qa-real-face.jpg co.local.personas.test/androidx.test.runner.AndroidJUnitRunner`: **OK (10 tests)**, última ejecución 20.735 s. Este tiempo es de la suite y no un benchmark de búsqueda.
- Una primera prueba de texto grande no encontró un elemento todavía no compuesto por la cuadrícula lazy. Se corrigió la navegación del test para desplazar el contenedor antes de buscar el control. Prueba filtrada y suite final aprobadas; no se ocultó el fallo.
- Las tres escalas de animación del sistema se guardaron, desactivaron temporalmente para la suite y restauraron en finally. La navegación y los estados siguieron disponibles con animaciones desactivadas.

| Verificación | Requisito | Evidencia / alcance |
|---|---|---|
| V10a Inicio y referencia vacía | R01,R14 | Encabezado y acción principal visibles; navegar a referencia y no avanzar sin rostro |
| V10b Pantalla pequeña y fuente grande | R14 | Contenedor de prueba de 320×480 dp con fuente 200% en el teléfono real; acciones fijas visibles y selector de referencia alcanzable con scroll; no cambió el tamaño de fuente global del teléfono |
| V10c Sin rostro | R02,R05,R14 | Bitmap uniforme generado en test, decodificación e inferencia OpenCV Android reales; cero caras; mensaje útil y avance desactivado |
| V10d Sin permiso / sin álbumes / limitado | R10,R14 | Estados de presentación de prueba, acción de selección individual disponible; explicación de conteos limitados. No equivale a conceder/revocar permisos reales del sistema |
| V10e Sin coincidencias, cancelado y error parcial | R05,R06,R13,R14 | Estados de UI de prueba; siguientes acciones verificadas; no son una medición de exactitud ni una prueba de interrupción JNI |
| V10f Oscuro | R14 | Configuración nocturna local de test, navegación y estados vacíos verificados; revisión visual de capturas |
| V10g Álbum aislado + reconocimiento nativo | R03,R04,R07 | Dos filas temporales de MediaStore en carpetas diferentes con igual nombre “Same”; consulta devuelve sólo el URI del bucket elegido; reconocimiento real devuelve sólo esa foto, aunque el otro álbum tenga la misma cara |
| V10h Selección y revisión | R07,R14 | Seleccionar todas habilita compartir y selecciona únicamente el resultado; imagen completa abre sin recorte de encuadre y conserva la selección |

La prueba opcional V10g/h usa exclusivamente la muestra pública oficial ya descargada desde https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/lena.jpg en la caché privada, no incluida en APK/repo. Crea dos copias propias en MediaStore y las elimina en finally mediante sus URIs exactas. No lee, modifica ni elimina originales del usuario. La referencia y la foto candidata son copias de la misma muestra: comprueba integración, no generalización, precisión o recuperación. La selección del álbum se invoca desde el test; no comprueba el diálogo de concesión de permiso de la galería personal.

Se recuperaron y revisaron capturas de inicio, referencia, rostro/recorte real, resultados seleccionados, imagen completa, permisos/álbumes vacíos, sin coincidencias, modo oscuro y texto grande. Capturas temporales fuera de Git en /tmp/personas-ui-review, sin imágenes personales del usuario. Los estados inventados de presentación están sólo en androidTest; producción no genera coincidencias de ejemplo ni portadas ficticias.

Contraste calculado de pares principales de tokens mediante luminancia sRGB: botón blanco/índigo 7.77:1; texto secundario/fondo claro 6.94:1; texto del destacado en extremos del gradiente 11.17:1 y 11.14:1; texto principal/fondo oscuro 14.77:1; texto del botón oscuro 8.06:1. No constituye auditoría de accesibilidad completa. Selección reforzada con check/texto/semántica y controles de al menos 48 dp; TalkBack auditivo pendiente.

### Límites y próximos pasos

- Pendiente comprobar en el diálogo Android/OEM todas las combinaciones de permisos completo, limitado, denegado permanente y revocado y la recepción de fotos compartidas en otra aplicación. La suite no cambió ni amplió los permisos de la galería personal.
- La consulta real de MediaStore y su aislamiento se verificaron con filas propiedad de la app; el catálogo personal completo y la selección visual de sus álbumes requieren la autorización del usuario dentro de la app.
- Los estados de cancelación/error se revisaron visualmente; falta repetir cancelación con un álbum grande y fotos ilegibles reales. Consultas IO y generación impiden resultados obsoletos, pero no se ha hecho un benchmark de bibliotecas grandes.
- No hay historial ni índice persistente, por lo que no se muestran búsquedas recientes.
- La prueba del usuario de 11 fotos/6 resultados sigue pendiente de diagnóstico V09; este rediseño no pretende resolver ni medir ese problema.

Cierre de QA R14: se retiraron las capturas y la muestra de la caché privada del teléfono y se desinstaló únicamente co.local.personas.test. El APK principal 0.2 permanece instalado. Las copias de MediaStore generadas por la suite se eliminaron en su bloque finally. Capturas de revisión conservadas sólo en /tmp fuera del repo.

## R15 — Referencia con más de tres personas

Reporte del usuario: en una referencia con más de tres personas sólo se podían elegir tres. Inspección: no existe una constante de máximo tres en detector, ViewModel o selector. Sin la referencia original no se ha confirmado si el reporte se originaba en detección incompleta, disponibilidad visual del selector o cajas superpuestas.

Cambios: miniaturas de rostro como elementos independientes de LazyVerticalGrid, sin FlowRow concentrado en un único bloque; selección accesible por número y recorte; prioridad a menor caja contenedora en toques sobre cajas superpuestas. YuNet ahora procesa la resolución de análisis y una segunda escala de lado máximo 960 cuando corresponde; reproyecta caja/5 landmarks y fusiona duplicados (NMS IoU>0.4), generando embeddings SFace sobre la imagen de análisis. Pesos, umbral detector 0.85 y umbral de reconocimiento 0.363 se conservan. Versión de detección futura para invalidación de índice: yunet-multiscale-v2; aún no existe índice persistente.

La prueba nativa de grupos compone nueve copias de la muestra pública de OpenCV exclusivamente en el test, no en producción. La detección debe devolver nueve rostros deduplicados con embeddings reales; se eligen el cuarto y el noveno por sus miniaturas y el séptimo mediante coordenadas de la imagen. Una prueba JVM adicional comprueba mantener nueve cajas distintas y otra fusiona duplicados entre escalas sin eliminar otras caras. Esto no mide precisión con grupos familiares o rostros distintos ni reproduce la foto original del usuario.

Durante la regresión, la prueba de álbumes intentaba seleccionar desde el ViewModel inmediatamente después de navegar, antes de terminar la consulta real del catálogo. El selector rechaza correctamente interacciones mientras carga. La hipótesis inicial de una carrera ON_RESUME se descartó y el cambio experimental se retiró. El test ahora espera la carga del catálogo antes de seleccionar, siguiendo la misma condición de habilitación de la UI. La lógica de permisos/carga de álbumes de producción permanece como antes de R15.

Coste/limitación: hasta una detección adicional por foto grande y su fusión; no se ha medido todavía el impacto en un álbum extenso. La cancelación sigue esperando las operaciones JNI en curso. Falta repetir la foto original y, si aparecen sólo tres recuadros, registrar cuántos rostros utilizables encuentra la nueva versión antes de decidir otros cambios de detección.

Aclaración posterior del usuario: en su foto aparecen sólo tres recuadros. Se orienta el cambio específicamente a detección de referencia: score mínimo 0.65, con confirmación visual manual del rostro; el score durante búsqueda de fotos sigue en 0.85 y el umbral coseno en 0.363. El score nuevo no representa probabilidad de identidad ni garantiza detectar los rostros de esa foto sin repetirla. Las notas anteriores de “detector 0.85 conservado” aplican al análisis del álbum; en referencia queda sustituido por esta política v2.

Cierre R15/0.2.1: compilación de APK/app de pruebas, 10 pruebas JVM (8 comparación/selección y 2 fusión de detecciones) y lint completados: BUILD SUCCESSFUL, 0 errores de lint y 14 advertencias. Suite Android final en CPH2637/API 36 con política de referencia 0.65: OK (11 tests), 26.672 s de suite, no benchmark de búsqueda. Incluye nueve detecciones reales deduplicadas y selección de rostros 4/9 por miniaturas y 7 mediante toque. Capturas de estas dos vistas revisadas. La prueba de álbumes también pasó tras esperar la carga de su catálogo. Pesos y coseno sin cambios.

La app 0.2.1 permanece instalada y se abrió correctamente. Se retiraron de su caché la muestra y las capturas de QA y se desinstaló sólo el APK de pruebas. Las fotos temporales de MediaStore fueron eliminadas por el test. Ajustes de animación restaurados. Siguiente comprobación: repetir la referencia original del usuario; no se ha confirmado aún el nuevo número de caras de esa foto concreta.

## R16 — Comparación con distintas poses e iluminación (0.3.0)

Reporte del usuario: falsos negativos en la mayoría de pruebas; motivo predominante “Rostros detectados, sin coincidencia suficiente”. Se verificó el contrato de preprocesamiento contra el código oficial FaceRecognizerSF de OpenCV 4.12.0; no se encontró evidencia suficiente de un error de canales/normalización. En host, dos imágenes diferentes de la misma persona (david1/david2 de OpenCV) dieron coseno 0.771, mientras dos controles de otras identidades quedaron bajo el umbral. Esto valida ese par de control, no todos los casos del usuario.

La prueba más difícil usa pose lateral frente a cambios de iluminación: una referencia única pierde positivos reales de la misma secuencia. Se conserva coseno 0.363 y se añade comparación contra varias referencias que el usuario confirma. No se añaden automáticamente imágenes rechazadas como positivas. La UI permite “Usar como otra referencia”, elegir el rostro correcto y volver a buscar sobre el mismo conjunto, sin perder álbum ni URIs.

### Verificación ejecutada

- `./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug --console=plain`: BUILD SUCCESSFUL; **12 tests JVM**, 0 fallos. Lint: 0 errores, 14 advertencias existentes/versiones/UseKtx.
- Suite Android completa en CPH2637, API 36: `am instrument -w -e class co.local.personas.ui.FlowUiTest -e faceFixture qa-real-face.jpg -e identityFixtures qa-identity co.local.personas.test/androidx.test.runner.AndroidJUnitRunner`: **OK (14 tests)**, 38.149 s de suite. No es tiempo de búsqueda.
- Nueva regresión nativa de reconocimiento: 11 fotogramas positivos distintos de las dos referencias y 2 imágenes de otras identidades. El conjunto se conservó al añadir referencia y ningún negativo fue aceptado en esta prueba.
- Prueba UI completa: una imagen inicialmente BELOW_THRESHOLD se revisa como descartada, se propone como ejemplo y el usuario confirma su rostro antes de repetir; se recupera sólo dentro del conjunto original. Esta comprobación incluye la propia foto confirmada como semilla y es únicamente una prueba de flujo, no de exactitud.
- Se verificó que lectura fallida, cero caras y cancelación al añadir ejemplo mantienen la referencia y los ejemplos válidos. Quitar un ejemplo y reemplazar persona funcionan. Comparación, miniaturas e inferencia fuera de Main.
- Capturas de referencias, resultados y recuperación de descartada revisadas en el teléfono; sin imágenes personales del usuario, archivos fuera de Git.

### Conteos observados del conjunto de regresión

| Configuración | TP | FP | FN | TN | Precisión del conjunto | Recuperación del conjunto |
|---|---:|---:|---:|---:|---:|---:|
| Una referencia lateral | 5 | 0 | 6 | 2 | 5/5 | 5/11 |
| Referencia lateral + frontal confirmada | 11 | 0 | 0 | 2 | 11/11 | 11/11 |

Búsqueda final: 13 fotos procesadas, 0 omitidas y 1696 ms medidos por la app. Incluye decodificación e inferencia del conjunto; no incluye elección/preparación de referencias. Duración de la primera búsqueda no registrada, por lo que no se compara rendimiento entre ambas.

**Alcance limitado:** son imágenes de UNA secuencia de seguimiento de una identidad, con sólo dos controles negativos. Las semillas no están entre los 11 positivos, pero la segunda referencia se eligió observando esta misma prueba. No es una evaluación ciega, independiente ni representativa de familias, niños, edades, cámaras o álbumes reales; los conteos no se extrapolan. Etiquetas procedentes de la secuencia de seguimiento y de los controles públicos, no de un álbum etiquetado del usuario. El umbral no se calibró con este conjunto. Precisión aquí es la métrica TP/(TP+FP), no un porcentaje de certeza de cada foto.

### Recursos y reproducción

`tools/prepare_recognition_qa.py` fue ejecutado y prepara las muestras públicas a /tmp con OpenCV Python 4.12.0.88 y numpy 2.2.6, usando curl con verificación HTTPS del sistema. El urllib del Python local falló por su almacén de certificados; no se desactivó TLS. El helper, que sólo se usa en desarrollo, se comprobó con curl y guardó fuentes/hashes. Ningún recurso de ejemplo se añade al APK ni al repo.

- Vídeo: https://raw.githubusercontent.com/opencv/opencv_extra/4.x/testdata/cv/tracking/david/data/david.webm
- SHA-256 del vídeo probado: 4bbe69b7d097379af4d7ad128f02692820dc57a6d8275ea2b9e7eef4399a3e61
- Referencias: fotogramas 473 y 354. Positivos: 59,118,177,236,295,414,532,591,650,709,769.
- Controles negativos: https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/messi5.jpg y https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/lena.jpg.
- Contrato oficial de preparación: https://raw.githubusercontent.com/opencv/opencv/4.12.0/modules/objdetect/src/face_recognize.cpp .

### Pendiente

Repetir con el álbum del usuario y distintas identidades positivas/negativas, anotando detección del rostro objetivo, referencia usada, TP/FP/FN/TN y duración. Una sola referencia conserva sus limitaciones: la mejora se activa aportando otros ejemplos correctos. No se promete que todos los falsos negativos queden resueltos, ni que un ejemplo incorrecto no mezcle personas. Índice persistente e historial continúan pendientes.

Cierre R16: recursos QA retirados de la caché privada; se desinstaló únicamente el APK de pruebas. La app 0.3.0 sigue instalada y se abrió correctamente. Las filas temporales de MediaStore fueron borradas por el test y los ajustes de animación originales quedaron restaurados. Evidencia pública temporal conservada fuera del repo en /tmp.

## R17 — Fotografías de Google Fotos / nube (0.4.0)

Acceso visible en referencia y conjunto; guía y apertura de los ajustes del proveedor cloud, protegida por API/extensión y gestión de actividad ausente/denegación. Se mantiene Photo Picker image-only sin EXTRA_LOCAL_ONLY, con selección por tandas. Archivos permite los proveedores SAF disponibles, incluido Drive. Google Fotos instalado no se presenta como cuenta conectada ni se mezclan álbumes remotos con MediaStore.

Personas acepta SEND/SEND_MULTIPLE image/* como destino de compartir. La actividad y el ViewModel se reutilizan; valida extras/ClipData, deduplica URI y comprueba esquema content y MIME conocido en IO. Se pide confirmación para añadir al conjunto o usar una sola foto como referencia. Una propuesta recibida durante inferencia espera hasta terminar/cancelar. No se añadieron dependencias, permiso INTERNET, OAuth, copias persistentes, logs de URI ni cambios a modelos/umbrales.

Revalidación de álbum: el refresco al volver de un proveedor mantiene un álbum cuyo conjunto autorizado no cambió; si cambia, invalida resultados, y si desaparece el acceso o falla la revalidación limpia el conjunto local. Buscar permanece bloqueado durante la reconsulta. La prueba real del álbum de dos carpetas añade una repetición de refresh para verificar que una vuelta sin cambios conserva el bucket correcto.

Primera suite de R17: 20 pruebas ejecutadas; las comprobaciones de importación/selector pasaron, pero el cierre de sharedIntentReusesSessionAndRequiresConfirmationBeforeMerging falló al esperar DESTROYED (último evento PAUSED). ActivityScenario identifica eventos mediante el intent de lanzamiento y deja de seguirlos cuando onNewIntent sustituye ese intent por SEND_MULTIPLE. Se restauró el intent de lanzamiento únicamente en la limpieza del test; la recepción real de producción y la comprobación de reutilización permanecen. Referencia del mecanismo: https://github.com/android/android-test/blob/main/core/java/androidx/test/core/app/ActivityScenario.java (`activityMatchesIntent`). No se omitió la prueba ni se alteró la recepción para hacerla pasar.

Alcance de los tests nuevos: filas temporales propias de MediaStore con imágenes públicas o un bitmap uniforme, y un documento de texto propio para comprobar su rechazo; nunca imágenes personales en capturas/APK. Valida integración de intents y reconocimiento local, no una descarga desde una cuenta Google. Los grants de los intents se incluyen, pero los recursos de esa prueba son propiedad de la app: no sustituyen una comprobación de grants entre Google Fotos y Personas.

Pendiente V13/T35: seleccionar fotografías que sólo existan en la nube con la cuenta del usuario y comprobar descarga, búsqueda y envío desde Google Fotos. No se cambió la cuenta ni la configuración de nube automáticamente; tampoco se simularon una sesión OAuth o una descarga cloud. La compatibilidad del proveedor requiere habilitación por el usuario. Las limitaciones anteriores de reconocimiento y evaluación con álbum real siguen vigentes.

### Resultado verificado R17

- Build de aplicación y androidTest correcto; 12 pruebas JVM sin fallos. Lint: 0 errores, 14 advertencias de versiones/target/UseKtx; sin nuevas supresiones. Modelos verificados por SHA-256/tamaño, sin cambios.
- CPH2637/API 36, `am instrument -w -e class co.local.personas.ui.FlowUiTest,co.local.personas.ui.CloudImportTest -e faceFixture qa-real-face.jpg -e identityFixtures qa-identity co.local.personas.test/androidx.test.runner.AndroidJUnitRunner`: **OK (20 tests)**, 49.277 s de suite. Incluye regresiones previas de reconocimiento, álbum aislado y selección/compartir.
- Importación de una imagen como referencia con búsqueda nativa posterior; recepción real de un nuevo intent en la misma actividad; cancelar sin modificar conjunto; confirmar y deduplicar; referencia conservada. Un envío durante búsqueda nativa queda pendiente, no cambia el snapshot, y se puede aceptar tras cancelación.
- Rechazo de texto conocido, esquemas https/file, acción ajena y extra mal formado. Se usan únicamente dos imágenes y un documento propios de cada test, borrados en finally.
- Desde el acceso Google Fotos de la app se abrieron los ajustes reales del selector y el selector real de Android; se volvió con Atrás sin seleccionar imágenes ni cambiar la cuenta/proveedor. No se capturó el contenido de la biblioteca personal ni los datos de la cuenta.
- Se recuperaron 24 capturas de estados/pruebas públicas y se revisaron la guía, el conjunto y el diálogo de importación. Un diálogo nativo crea su propia densidad: el override de Compose por sí solo no demuestra texto del sistema ampliado dentro del diálogo.
- Por eso se ejecutó además la prueba `CloudImportTest#largeTextCloudHelpAndUnavailableSettingsKeepAlternativesReachable` con **font_scale real del sistema 2.0**, argumento `verifySystemLargeText=true` y superficie limitada a 320×480 dp. Se comprobó configuración y altura real del título ampliado, scroll hasta Configurar nube y acceso a Abrir selector: **OK (1 test)**, 2.923 s. Captura adicional revisada. El valor anterior de font_scale se restauró en finally, igual que las escalas de animación de la suite. Esta prueba aislada posterior no cambió código de producción.

Evidencia temporal en /tmp/personas-ui-review (25 capturas, sólo recursos públicos/estados de prueba), fuera de Git. Ninguna prueba anterior equivale a descarga cloud autenticada; T35 permanece pendiente.

Cierre R17: caché QA retirada y vacía; se desinstaló únicamente co.local.personas.test. Confirmado versionCode 5 / versionName 0.4.0, instalada y abierta en el teléfono: Status ok, arranque frío 1296 ms (no tiempo de reconocimiento). font_scale restaurado a su valor original 1.0. Las filas temporales de MediaStore se eliminaron en finally; no se modificaron fotos originales ni la configuración de la cuenta Google.

## R18 — Rendimiento conservando reconocimiento (0.5.0, 2026-10-22)

El usuario confirma lentitud en el primer análisis y al repetir. Se implementan: parada tras primera coincidencia válida, caché RAM acotada de detecciones/embeddings parciales, preparación IO acotada de la siguiente foto, una sola llamada al worker por foto y una actualización de progreso/resultado por foto terminada. La referencia sigue devolviendo todas las caras. Negativos sin coincidencia evalúan todas. Los modelos, FP32, Core threads=2, resolución/EXIF, ambas escalas, umbrales, NMS, alineación y coseno se conservan. Reutilización de Mat por cara y verificación SHA de modelos mediante bloques, sin lectura completa de SFace a un array temporal de tamaño del archivo.

### Comprobaciones ejecutadas

- `./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug --console=plain`: BUILD SUCCESSFUL. **17 tests JVM**, 0 fallos: 10 matching, 2 detecciones y 5 caché. Lint: 0 errores, 14 advertencias existentes/versiones/UseKtx; sin supresiones nuevas.
- Caché JVM: LRU por bytes/entradas, reserva de embeddings pendientes, vectores sin alteración de bits, conservación de todas las caras en registros parciales, cero caras, reemplazo, rechazo de entradas demasiado grandes y borrado completo.
- `python3 tools/models.py --check`: SHA-256 y tamaños de ambos ONNX correctos. `python3 -m py_compile tools/benchmark_recognition.py` correcto.
- Se compilaron las pruebas Android nuevas `SearchPerformanceTest`: equivalencia con recorrido completo y cambio de referencia/contenido/dimensiones, batch con error intermedio/orden, y cancelación liberando actual+siguiente. **No se ejecutaron**: ADB no muestra dispositivo conectado. Tampoco se ejecutó la regresión Android de 20 tests previa sobre 0.5.0. El APK está preparado, no instalado en este incremento.

### Perfilado host y comparación de decisiones

OpenCV Python 4.12.0.88 (`cv2.__version__=4.12.0`), numpy 2.2.6, CPU arm64 del computador, 2 hilos, sin GPU/FP16. Recursos públicos preparados en /tmp/personas-qa-repro: 11 frames distintos de David y dos negativos; el grupo es una composición sintética de nueve copias de Lena, NO nueve personas distintas. Las mismas limitaciones de R16 sobre una secuencia/no evaluación independiente siguen vigentes.

Primero se probó mantener detectores separados por escala: 4 entradas públicas de 1600×1600, tres recorridos pareados. Detector compartido: 161.99/163.22/160.94 ms; separados: 166.41/168.26/161.45 ms. Detecciones exactamente iguales, sin beneficio consistente; no se aplicó esa propuesta.

Después se ejecutó:

```sh
/tmp/personas-model-check/bin/python tools/benchmark_recognition.py --fixtures /tmp/personas-qa-repro --output /tmp/personas-speed-host.json
```

El helper reproduce el reconocimiento y la caché en Python; **no ejecuta Kotlin, ImageDecoder, JNI Android ni la preparación IO del APK**. Excluye carga de modelos y calentamiento de kernels por igual, mantiene dos pasadas cuando corresponde y compara tres recorridos. Los tiempos de las fotos incluyen lectura/decodificación OpenCV; el grupo se copia desde memoria. No son velocidades del teléfono ni del álbum del usuario.

| Prueba host | Recorrido completo, mediana | Primer recorrido optimizado, mediana | Repetición con caché, mediana | Embeddings completo → primero → repetido |
|---|---:|---:|---:|---|
| 13 fotos distintas, referencias David | 117.403 ms | 115.834 ms | 5.385 ms | 13 → 13 → 0 |
| Grupo sintético positivo, coincidencia temprana | 99.814 ms | 48.565 ms | 2.807 ms | 9 → 1 → 0 |
| Mismo grupo sin coincidencia | 92.630 ms | 92.849 ms | 2.928 ms | 9 → 9 → 0 |

En los tres casos coincidieron exactamente las decisiones respecto al recorrido completo, incluso cambiando de referencia sobre la caché parcial. Todos los vectores efectivamente calculados coincidieron exactamente entre ambos caminos host. Las repeticiones evitaron todas las pasadas del detector y todos los embeddings en estas muestras sin expulsión de caché. El grupo positivo mantuvo ambas pasadas del detector en el primer recorrido. No se alteraron umbrales para obtener esos tiempos/resultados.

Esto demuestra ahorro de trabajo y equivalencia en los controles host, no una mejora universal de precisión ni un multiplicador Android. El primer recorrido de fotos con una cara y de negativos quedó prácticamente igual: siguen necesitando el mismo trabajo nativo y el hash añade coste. La mejora de la primera búsqueda depende de coincidencias tempranas en grupos y del solapamiento IO disponible; para bitmaps >16 MiB se limita éste para controlar memoria. La descarga cloud puede seguir dominando el tiempo. La caché se pierde al borrar sesión, al expulsarse entradas o morir el proceso; no es el índice persistente T12.

### Estado previo a reconectar el dispositivo (T39/V14)

Conectar teléfono e instalar 0.5.0; ejecutar regresión UI/recognition y `SearchPerformanceTest` con las mismas muestras públicas opcionales; medir primer/repetido con ambos motores ya inicializados, igualdad de outcomes, referencia distinta tras entrada parcial, URI editado, error intermedio y cancelación con bitmap preparado. Guardar sólo conteos/tiempos, retirar fixtures y APK de tests al terminar. Medir memoria y un álbum real autorizado; no presentar ni la equivalencia host ni compilar androidTest como aprobación de ese dispositivo. En esta sesión no se copiaron recursos de prueba al teléfono ni se modificaron sus ajustes.

### Actualización V14 — Dispositivo conectado e instalación

Tras la petición de cargar la app se conectó CPH2637, Android API 36. Instalación de 0.5.0 (versionCode 6) con `adb install -r`: Success; apertura Status ok, arranque frío 1105 ms. No hubo cambios de código de producción entre el APK compilado anteriormente y esta validación.

Suite completa sobre el APK 0.5.0:

```sh
adb shell am instrument -w -e class co.local.personas.ui.FlowUiTest,co.local.personas.ui.CloudImportTest,co.local.personas.data.SearchPerformanceTest -e faceFixture qa-real-face.jpg -e identityFixtures qa-identity co.local.personas.test/androidx.test.runner.AndroidJUnitRunner
```

**OK (23 tests)**, 67.587 s de suite. Incluye los 20 tests de UI/reconocimiento/importación previos y 3 nuevos de rendimiento/caché/cancelación; las pruebas opcionales contaron con sus muestras públicas. Las escalas de animación se guardaron y restauraron en finally; no se cambió el tamaño global del texto ni la cuenta/proveedor cloud. Las copias temporales de MediaStore creadas por tests se eliminaron en sus bloques finally.

`SearchPerformanceTest` comparó tres veces el recorrido exhaustivo anterior contra el nuevo sobre el mismo conjunto de 16 URI: 13 fotos públicas distintas, un grupo sintético de nueve copias de Lena, una imagen uniforme y un archivo inexistente intercalado. Ambos motores estaban inicializados antes de empezar los tiempos. El grupo es negativo para la referencia David de esta comparación, por lo que el primer recorrido debe calcular sus nueve embeddings; no se escogió una referencia que forzara salida temprana en ese grupo.

| Recorrido Android | Ejecuciones | Mediana |
|---|---|---:|
| Completo, sin caché ni parada temprana | 2149 / 2008 / 1596 ms | 2008 ms |
| Primero optimizado, caché inicialmente vacía | 1500 / 1506 / 1876 ms | 1506 ms |
| Repetición optimizada, caché de sesión | 173 / 186 / 180 ms | 180 ms |

En este conjunto el primer recorrido consumió **25 % menos tiempo** por mediana; la repetición tardó aproximadamente **1/11.2** del recorrido completo. Hubo exactamente los mismos outcomes y orden en los 16 casos de cada recorrido, incluidas 11 coincidencias, la imagen sin caras y el error de lectura intermedio. No es una estimación de precisión universal, un benchmark ciego ni una promesa de multiplicador para bibliotecas reales; hay sólo tres repeticiones, calentamiento/variación de CPU y un grupo sintético. Los tiempos incluyen lectura/decodificación e inferencia de la búsqueda, no la selección/preparación de la referencia ni la inicialización de modelos. La comparación de 16 casos evita actividad de la UI mientras mide el motor; medir álbumes reales con miniaturas visibles sigue pendiente.

La línea base usa `OpenCvFaces.analyze` exhaustivo con caché desactivada dentro del mismo APK; compara el recorrido lógico completo frente a la búsqueda optimizada, no dos binarios 0.4.0/0.5.0. Ambos caminos comparten los pesos y las operaciones de alineación/feature.

Otras comprobaciones nativas nuevas aprobadas:

- Grupo de nueve caras: coincidencia con un embedding en lugar de nueve; repetir calcula cero. Cambiar a una referencia opuesta calcula las ocho caras pendientes y reproduce el rechazo del recorrido completo; una entrada positiva parcial no oculta otras caras.
- Cambiar un píxel invalida la reutilización; reemplazar el contenido en el mismo URI por una imagen uniforme no conserva una coincidencia anterior. Mismo total de píxeles con dimensiones distintas produce una entrada diferente.
- Borrar caché fuerza una nueva detección; cancelar con el worker bloqueado y actual+siguiente bitmap preparados libera ambos y no publica resultados cancelados.
- Regresión de reconocimiento con referencias complementarias: 5/11 positivos con referencia lateral y 11/11 con dos referencias, 0/2 negativos aceptados en ambos; conserva exactamente el alcance limitado de R16.

Evidencia temporal fuera de Git: /tmp/personas-ui-review/performance-metrics.json, identity-metrics.json y 24 capturas de estados/muestras públicas. No se exportaron embeddings, fotografías personales ni contenido de la cuenta cloud. La descarga de una foto que sólo exista en Google Fotos (T35), la memoria con fotos grandes (T13) y la evaluación con álbum del usuario (T10/T31) continúan pendientes.

Cierre V14: recursos QA retirados (caché vacía), se desinstaló únicamente co.local.personas.test y se dejó abierta 0.5.0 en el teléfono. Apertura final Status ok, arranque frío 1537 ms; no es tiempo de análisis. Las escalas de animación originales quedaron restauradas y las fotos originales se conservaron.

## R19 — Filtro estricto y repetición por contenido (0.6.0, 2026-10-22)

El fallo aclarado por el usuario es inclusión de otras personas. Se sustituye aceptación automática >=0.363 por >=0.50; [0.363,0.50) queda en **Por revisar**, sin selección/compartir. Confirmar o excluir desde la foto completa modifica sólo esa sesión/persona/contenido; no entrena ni añade referencias. Ver ADR 007 para cálculo, claves y límites de memoria.

### Calibración pública y evaluación separada

Archivo oficial AT&T/ORL verificado por SHA-256, crédito AT&T Laboratories Cambridge. 40 sujetos ×10 imágenes, 92×112 en gris; imágenes y vectores fuera de APK/Git. Sujetos 1–20 calibración y 21–40 evaluación. Una/dos/cuatro referencias usan imágenes 1 /1–2 /1–4; consultas restantes y negativos de otros 19 sujetos del mismo split. Selección previa por calibración: menor valor de [0.50,0.55,0.60,0.65,0.70] con cero FP en todos los protocolos. Elegido 0.50; evaluación no ajustó la política.

Inferencia nativa OpenCV 4.12.0 / FP32 en CPH2637/API 36: 400 consultas con rostro utilizable, 160 referencias utilizables. El helper host produce los mismos conteos. No se suman protocolos que comparten imágenes como muestras independientes.

| Split | Referencias | Positivos / negativos | TP / FP con 0.363 | TP / FP automáticos con 0.50 | FN automáticos | Positivos / negativos por revisar |
|---|---:|---:|---:|---:|---:|---:|
| Calibración | 1 | 180 / 3420 | 180 / 10 | 179 / 0 | 1 | 1 / 10 |
| Calibración | 2 | 160 / 3040 | 160 / 9 | 159 / 0 | 1 | 1 / 9 |
| Calibración | 4 | 120 / 2280 | 120 / 8 | 120 / 0 | 0 | 0 / 8 |
| Evaluación | 1 | 180 / 3420 | 180 / 0 | 177 / 0 | 3 | 3 / 0 |
| Evaluación | 2 | 160 / 3040 | 160 / 0 | 160 / 0 | 0 | 0 / 0 |
| Evaluación | 4 | 120 / 2280 | 120 / 0 | 120 / 0 | 0 | 0 / 0 |

Con una referencia, precisión automática en esta evaluación =177/(177+0)=1; recuperación automática =177/180=0.9833. Las tres restantes son pendientes; confirmar manualmente no cuenta como recuperación automática. En evaluación el criterio anterior ya tenía cero FP: no se atribuye una reducción allí. La reducción 10→0 se observó en calibración y en una regresión dirigida de esas personas. Base histórica frontal con sujetos separados, comprobación interna sin evaluación externa ciega; desconocido solapamiento con entrenamiento del proveedor. No demuestra ausencia de falsos positivos familiares ni para un número ilimitado de referencias. Pendiente T10/T31 con álbum etiquetado del usuario.

Regresión previa de pose/iluminación (vídeo público, 11 positivos y dos negativos): con umbral estricto, referencia lateral da 0 automáticos; dos referencias confirmadas dan 9 automáticos y 2 pendientes, cero negativos automáticos o pendientes. Las 11 siguen disponibles entre ambos grupos, pero ya no se afirma que las 11 se recuperen automáticamente. Este caso dirigido sigue sin ser una evaluación independiente.

### Verificación de código y flujo

- JVM: 19 pruebas aprobadas (12 comparación/política/selección, 2 fusión de detecciones, 5 caché). Límites exactos REVIEW/MATCH y mismo resultado Float de coseno/preparación con 100 pares reproducibles.
- Android: suite completa de 29 pruebas, reconocimiento real sin dobles. Incluye regresión de referencia/grupos, integración cloud, caché/performance y cuatro pruebas de filtrado/contenido; dos nuevas de UI revisión/exclusión.
- Por revisar no entra en resultados, toggle/select-all ni compartir. Confirmación explícita permite restaurar una descartada; excluir retira selección, repetir mantiene exclusión, empezar otra persona limpia feedback. Comprobado con una pareja negativa pública que la política anterior aceptaba.
- Cache-hit repetido no decodifica; cambios bajo la misma URI y archivo eliminado no se reutilizan. Una entrada parcial con nueva persona solicita completar las ocho caras pendientes, en lugar de devolver un negativo incompleto. Limpiar sesión invalida alias y detecciones.
- Comparación URI/snapshot exacta para ocho orientaciones EXIF, con resize real a 64 px; archivo >8 MiB usa ruta URI sin alias. Error intermedio mantiene orden y estado, cancelación recicla los dos bitmaps y no emite resultados posteriores.
- Primera medición detectó coste redundante al calcular SHA de bytes y de BGR: se eliminó el segundo cuando el snapshot verificado ya proporciona la clave junto con el pipeline; se conservó BGR en fallback. Se evita Formatter por cada byte y consulta de caché adicional si ya se preparó bitmap.
- Una prueba cloud asumía que URI distinta implicaba trabajo nativo nuevo: la caché correcta por contenido la hacía terminar antes de la aserción. Se reemplazó su carga por variantes reales de píxeles, con limpieza en finally. Otra prueba tocaba una foto parcialmente fuera del viewport; se posicionó el ítem antes del toque. El error de mutabilidad de los fixtures se corrigió copiando a bitmap mutable sólo en test. No se ralentizó producción para sostener tests.

### Rendimiento Android

Misma política estricta para recorrido exhaustivo, primero optimizado y repetido. 16 entradas: 13 fotos públicas distintas, grupo sintético de nueve copias de un rostro, imagen vacía y archivo ausente intermedio. Tres recorridos; no incluye descarga cloud ni álbum familiar. Los 16 outcomes/orden coinciden exactamente: 9 MATCH, 2 REVIEW, las otras categorías conservadas.

Dos suites completas aprobadas del mismo pipeline estricto (antes/después de finalizar el fallback de proveedores; las entradas válidas usan la misma ruta). Tiempos de tres recorridos por ejecución:

| Ejecución | Completo (ms) | Primero optimizado (ms) | Repetido (ms) | Medianas completo / primero / repetido |
|---|---|---|---|---|
| 1 | 2132, 2348, 2146 | 1554, 1620, 1576 | 166, 164, 150 | 2146 / 1576 / 164 |
| Final | 1732, 1711, 1602 | 1946, 2009, 1843 | 148, 107, 110 | 1711 / 1946 / 110 |

La repetición mejora claramente frente al recorrido completo dentro de cada ejecución. **No hay mejora estable demostrada en el primer recorrido**: en la última ejecución fue más lento. No ocultar esta limitación ni extrapolar el resultado favorable de la primera. Las fotos negativas siguen requiriendo todas las caras; validar contenido añade trabajo. No comparar cifras de 0.5/0.6 como benchmark entre binarios: la política de aceptación cambió y el equipo presenta variación.

Perfilado adicional nativo con tres órdenes intercalados, caché vacía, 14 entradas públicas (incluido grupo sintético): 1 hilo =2266/2375/2395 ms; 2 =1516/1587/1489; 4 =1923/2129/2088. Decisiones iguales en todos los recorridos. Se conservan los dos hilos actuales, porque cambiar a uno o cuatro empeora este dispositivo. No se introduce una supuesta aceleración sin evidencia.

Datos agregados nativos en [007-public-filter-counts.json](evaluation/007-public-filter-counts.json). No contiene imágenes, embeddings, URI ni datos del usuario.

### Cierre y revisión visual

APK 0.6.0 (versionCode 7) instalado. Suite completa final **OK (29 tests)** en 101.895 s; perfilado adicional **OK (1 test)** en 18.966 s. No hubo cambios de producción posteriores a esa suite. Las dos comprobaciones específicas con `font_scale=2.0` real aprobaron **OK (2 tests)** en 4.298 s; la configuración de fuente y las tres escalas de animación se restauraron en finally.

La primera aserción de texto grande esperaba una altura lineal excesiva y falló. Se corrigió la comprobación para verificar la densidad real del texto (`fontScale=2`) y su crecimiento sobre la altura sin escalar, después de desplazar el título al viewport; Android 14+ usa [escalado no lineal](https://developer.android.com/about/versions/14/features#non-linear-font-scaling), por lo que 200% no duplica todas las alturas. Medición del título: 102 px con density=3 (34 dp, frente a lineHeight sin escalar de 24 sp). No se redujo el tamaño de texto de producción para pasar la prueba.

Revisión visual de capturas públicas: sección Por revisar separada y sin checkbox; exclusión etiquetada con restauración explícita; confirmación/exclusión legibles y alcanzables con scroll en superficie de 320×480 dp y fuente real 200%. Capturas, fixtures y métricas temporales fuera de Git; los datos agregados no identificables se conservan en el JSON enlazado. 19 pruebas JVM, lint 0 errores/14 advertencias preexistentes, hashes de ambos modelos verificados y scripts Python compilables. Al terminar se eliminaron exclusivamente los recursos privados de QA y el APK de tests; 0.6.0 quedó abierta (arranque Status ok). Las fotos originales y los modelos se conservaron.

### Límites conservados

No es un reconocedor infalible. Subir umbral reduce recuperación automática de algunas fotos correctas y exige revisar las dudosas; más referencias correctas ayudan en estos datos sin garantizar otros álbumes. Primer análisis sigue realizando las dos escalas y todo el trabajo nativo necesario de fotos negativas; caché/repeticiones ofrecen la mayor mejora. Archivos >8 MiB conservan decodificación y tienen una lectura adicional parcial; proveedores remotos pueden volver a descargar o fallar. Medición de memoria/álbumes grandes T13, evaluación familiar T10/T31, nube real T35 e índice persistente T12 siguen pendientes.


## R20 — HEIC en referencia y búsqueda (0.6.1, 2026-10-23)

### Cambio y fallos reproducidos

Los archivos se podían elegir, pero fallaban al abrir. Se centralizó salida software sRGB ARGB_8888 y se comprobó que algunos HEIC de 10 bits ni siquiera se decodificaban en Android. En CPH2637/API 36 se observó IOException genérico desde getPixels; capturar sólo DecodeException no activaba la alternativa. Ahora el fallback HEVC es local, acotado y sólo se intenta tras fallo nativo. El decoder alternativo 3.0.0 además necesitó un adaptador de orientación RGBA (ADR 008). Modelos, resolución de reconocimiento, umbrales, permisos y compartir de originales conservados.

Compile SDK 36, min 28/target 35. Nuevo AAR release fijado por versión/checksum; avisos incluidos en APK. El debug universal pesa 262515280 bytes, SHA-256 `e69ddc75cbca901aeb05477194d99cb9f2c99c980c9e6c7d5bdc128910972129`. Sin fixtures HEIC en APK. Hashes de ambos modelos correctos.

### Evidencia ejecutada

- Compilación debug y androidTest aprobada; **22 pruebas JVM** (0 fallos/omisiones), **lint 0 errores/14 advertencias**.
- QA generado con muestra pública OpenCV fijada por SHA y Pillow 11.3.0/pillow-heif 1.1.1, sin fotos personales. Quince HEIC reales más copia truncada: seis variantes del rostro (8/10 bits, sRGB/P3, giro y espejo), ocho orientaciones de una imagen no cuadrada y fondo plano. Manifest/hashes fuera del APK/Git.
- Emulador temporal AOSP ATD API 35/ARM64: **OK (7 tests)**, ejecución final 2.775 s. Lectura URI y snapshot con mismos píxeles, maxEdge, archivos originales intactos, ARGB_8888/sRGB; JPEG/PNG idénticos al decoder previo; conversión/release F16/P3; ocho orientaciones con geometría correcta y diferencia media por canal <6 frente a HEIC base (compresiones distintas). Inferencia real: seis variantes MATCH en primer/repetido, sin nuevos embeddings al repetir; fondo NO_FACE y truncado UNREADABLE. VM: HEIC como referencia, resultados, imagen completa, fallo de referencia extra conserva estado previo.
- En el emulador el lector Android abrió sRGB/P3 de 8 bits y rechazó los cuatro HEIC de 10 bits del conjunto principal. La alternativa local resolvió los cuatro. No se toma un F16 sintético como prueba de reconocimiento real.
- CPH2637/API 36: 0.6.1 instalada; **seis tests de datos/inferencia HEIC aprobados**, incluidas ocho orientaciones, conversión de color, búsqueda real y caché. El séptimo test llegó a seis coincidencias pero falló al buscar la miniatura mediante índice de scroll; se corrigió para desplazarse por descripción accesible y pasó en emulador. La repetición final en teléfono quedó esperando desbloqueo y pantalla de instalación del fabricante. No se declara una suite final completa aprobada en ese dispositivo.
- Regresión general del emulador: 35/36 casos aprobados en primer recorrido (32.967 s). El caso de álbum restante requería permiso previo: la consulta podía ver filas creadas por la propia app, pero el ViewModel correctamente retiraba el álbum al detectar permiso NONE. Al conceder READ_MEDIA_IMAGES en este emulador vacío, el caso aislado pasó: **OK (1 test)**, 3.240 s. No se modificó comportamiento de permisos para acomodar el test. El caso de apertura de ajustes cloud se excluyó porque ATD no incluye la aplicación Settings; no se da por validado allí.
- Revisadas capturas reales del emulador: HEIC ampliado, tema oscuro y tamaño 320×480 dp/fuente 200%. Controles accesibles y fotografía visible. Escalas de animación restauradas por los scripts.

ATD trae `debug.hwui.drawing_enabled=0`: desactiva Canvas y produce capturas/bitmaps vacíos. Se habilitó dibujo sólo en el emulador de QA antes de verificar color/interfaz; no se alteró código de producción por esa configuración. La preparación del emulador queda fuera del proyecto. No había AVD previo; la imagen temporal se obtuvo del repositorio oficial Android. El SDK de compilación queda disponible para el proyecto.

### Reproducción y pendientes

Ver ADR 008 y `tools/prepare_heic_qa.py`. Con los dos APK compilados y dispositivo desbloqueado:

```sh
python3 tools/run_heic_qa.py --serial ID_ADB --fixtures /tmp/personas-heic-qa --adb /ruta/platform-tools/adb
```

Este script valida hashes, instala, carga sólo QA público y ejecuta los siete tests HEIC. La suite general necesita también los fixtures públicos descritos en R16/R19. No hay garantía de soporte universal de HEIF: fallback ARM/ARM64, asociaciones v0, límites 64 MiB/100 millones de píxeles; memoria con imágenes grandes pendiente T13. No se evaluaron HDR auxiliar, 12 bits o los HEIC descargados concretos del usuario. UI final de teléfono desbloqueado y aceptación con esos archivos quedan en T48. T10/T31/T35/T12 mantienen su alcance pendiente.

Cierre: SHA-256 del APK instalado en el teléfono coincide exactamente con la compilación final indicada arriba. Se canceló únicamente la reinstalación redundante que estaba esperando desbloqueo; se retiraron los fixtures HEIC de caché y el APK de instrumentación, conservando la app 0.6.1 e iniciando MainActivity. El emulador propio se cerró y sus archivos grandes temporales se eliminaron. Muestras públicas/manifiestos y evidencia permanecen en /tmp para reproducir; ninguna foto privada se copió al proyecto.

### Actualización tras desbloquear el teléfono — 2026-10-23

Comprobado desbloqueo y completada la validación en CPH2637/API 36 usando el mismo APK de producción, sin reinstalarlo innecesariamente. Se instaló sólo androidTest y se cargaron las muestras públicas de R16/R19/R20.

La suite de 37 casos terminó en 131.227 s con 36 aprobados y un fallo de sincronización en HeicUiTest. Las seis pruebas HEIC de datos/inferencia, filtros, álbumes, importación, cancelación y otros casos UI pasaron. El test restante buscaba una descripción que sólo existe cuando termina de decodificarse la miniatura; al recorrer la cuadrícula podía saltarse las fotos aún cargando. Se corrigió exclusivamente el test para desplazar por la clave estable del resultado y esperar la imagen real. Repetición aislada: **OK (1 test)**, 7.231 s, incluyendo ampliación y preservación de referencia ante archivo roto. Son 37 casos distintos aprobados a través de ambas ejecuciones, no una única suite completa verde. Compilación androidTest/lint posteriores aprobados (0 errores/14 advertencias existentes).

Revisadas capturas reales del teléfono de HEIC ampliado, tema oscuro y referencia vacía en pantalla pequeña con texto 200%; imagen, controles y acciones visibles. Evidencia pública recuperada en `/tmp/personas-heic-phone-final`, salida de suite en `/tmp/personas-heic-full-suite.txt` y repetición en `/tmp/personas-heic-phone-ui-final.txt`, fuera de Git. Animaciones y configuración de mantener pantalla encendida por USB restauradas en finally. No se cambiaron permisos del teléfono ni el APK de producción. Se retiran otra vez fixtures HEIC y paquete de pruebas y se inicia la app para uso normal.

T48 queda completada para UI/regresión en teléfono. La aceptación con los HEIC descargados concretos, que no se proporcionaron, queda separada en T49. T10/T31/T35/T12/T13 conservan sus pendientes anteriores.


## R21 / V17 — Migración Flutter 0.7.0+9 (2026-10-23)

Interfaz/sesión compartidas en `flutter_app/`, adaptador Android sobre el código data/domain existente y adaptador iOS Swift/Objective-C++ con OpenCV real. Modelos YuNet/SFace verificados por SHA-256; no cambio de pesos ni umbrales. SDD en `specs/002-flutter-migration/` y arquitectura/comandos en ADR 009 y `flutter_app/README.md`.

Entorno verificado: Flutter 3.47.7 / Dart 3.13.5 estable, macOS ARM64; Android SDK 36, Gradle 8.14.3, AGP 8.13.2, Kotlin 2.2.20, NDK 28.2.13676358/CMake 3.22.1; Xcode 27.1 / runtime iOS 27.1. Android mínimo 28 e iOS mínimo 16. Flutter advierte de futuras versiones mínimas de Gradle/AGP/Kotlin: la compilación actual pasa sin omitir la validación de dependencias. No se cambió el SDK global seleccionado con xcode-select.

Resultados:

- `tools/flutter.sh analyze`: sin incidencias.
- `tools/flutter.sh test`: **18 pruebas aprobadas** (13 controlador, 5 widgets). Cubren más de 30 fotos, nueve opciones de rostro, referencias adicionales fallidas/sin cara, feedback por persona/contenido, exclusión de dudosas y archivos ilegibles al compartir, generaciones/progreso obsoletos, cancelación con resultados parciales, permisos revocados, recepción durante inicialización, selección cloud pendiente y transiciones al vaciar una cuadrícula desplazada. Vista de 320×480 dp con texto 200 %, alternativas sin permiso y resultados vacíos.
- Android: APK debug ARM64 compilado, instalado en CPH2637/API 36, mismo `co.local.personas`, versión 0.7.0/code 9. Escenario nativo Flutter de integración aprobado; salida `All tests passed` (14 s en la ejecución final de ese escenario).
- iOS: compilación debug para dispositivo aprobada **sin firma**; incluye ONNX y PersonasShare.appex. Compilación ARM64 de simulador aprobada y app ejecutada en el simulador iPhone Duo/iOS 27.1. El mismo escenario real de integración aprobado (50 s, incluidos tiempo de espera para copiar QA y capturas; no es tiempo de inferencia).

El escenario usa exclusivamente QA pública fuera del APK/repositorio: referencia HEIC de Lena de 10 bits; seis variantes HEIC (8/10 bits, sRGB/P3, giro/espejo), 40 alias idénticos para probar selección/caché, dos personas distintas (Messi y David), una imagen sin cara y un archivo incompleto. **50 procesadas, 46 coincidencias esperadas, dos negativos excluidos, un noFace y un unreadable**, repetido con el mismo resultado. Selección de las 46, apertura de HEIC completo, cambio a referencia sin cara, borrado de sesión, texto grande y oscuro. No equivale a 46 positivos independientes ni a una evaluación familiar de precisión.

Registro de dos recorridos con referencia/modelos ya preparados: Android 3093/1149 ms; simulador iOS 266/275 ms. Incluyen orquestación de la prueba y lectura, con muchos bytes repetidos; son una regresión funcional, no un benchmark comparable entre plataformas ni una promesa de aceleración en álbumes reales. La migración conserva el criterio, pero sólo estas entradas demuestran las mismas decisiones en ambos adaptadores.

Se corrigieron durante la integración el arranque diferido del puente FlutterFragmentActivity, la recepción inicial de imágenes, la revalidación de un álbum al volver a resultados y las referencias mutables de cuadrículas lazy durante la animación de salida. La cuadrícula usa snapshots de cada construcción y deja de aceptar interacción/semántica del paso saliente. La selección pendiente del proveedor bloquea cambios de conjunto y búsqueda hasta terminar, con progreso indeterminado; cancelar el selector conserva lo anterior.

Revisión visual: capturas de resultados con selección y vista HEIC completa en Android e iOS; referencia sin rostro, inicio claro/oscuro y fuente ampliada. Se ajustaron acciones para priorizar las fotos, etiquetas cortas en celdas estrechas, título adaptado a texto grande y mensaje sin rostro antes de la imagen. Las capturas de la app normal y la prueba se guardaron en `/tmp/personas-flutter-android/` y `/tmp/personas-flutter-ios/`, fuera del repositorio. Los dobles y fixtures pertenecen sólo a tests; la app normal instalada ejecuta `lib/main.dart`.

Límites de la validación inicial: no hubo iPhone físico conectado ni equipo/certificados de firma configurados; entonces no se instaló en iPhone ni se publicó en tiendas. Falta probar permisos completo/limitado, descarga de iCloud/Google Fotos/Drive y recepción por la extensión con una cuenta/dispositivo reales. Tampoco se enviaron fotos a destinatarios. La extensión requiere App Group registrado y la misma capacidad en ambos targets. La regresión nativa Android histórica sigue documentada en R20; no se presenta como una nueva ejecución de toda su suite con Flutter.

Permanecen T49 (HEIC concretos del usuario), T10/T31 (álbum familiar/calibración), T13 (bibliotecas grandes/memoria), T35 (proveedor cloud real) y T12 (índice persistente). No se modificaron fotografías originales ni se incorporaron fotos personales/embeddings al repositorio.

Cierre de instalación: último APK normal 0.7.0/code 9 actualizado y abierto en Android tras finalizar la prueba del usuario; última app normal instalada y abierta en el simulador iOS. Confirmados en Android tamaño físico 1080×2400, fuente 1.0 y modo nocturno desactivado, iguales a los valores anteriores a la QA. La comprobación temporal de 320×480 dp/fuente del sistema 200 % mantuvo la acción inferior accesible. En iOS también se revisó el tamaño de texto de accesibilidad del sistema y se restauraron tamaño/apariencia previos. Retirada únicamente la carpeta privada `cache/qa-flutter` del Android; las capturas temporales de la sesión de uso se eliminaron y sólo se conserva QA pública fuera del repositorio. Se limpiaron intermediarios regenerables tras verificar las compilaciones; se conservan el APK final y ambos Runner.app.

### Actualización — iPhone físico (2026-10-23)

Conectado un iPhone 15 Pro Max/iOS 27.0.1, emparejado y con modo de desarrollador habilitado. El usuario inició y renovó la sesión de Apple directamente en Xcode. La consola siguió rechazándola con `missing Xcode-Username`/`No Accounts`; la compilación desde la interfaz de Xcode sí creó un certificado Apple Development válido y perfiles para `co.local.personas` y `co.local.personas.share`, ambos con `group.co.local.personas`. No se leyeron contraseñas ni claves privadas. La selección temporal del equipo en el proyecto se restauró; la compilación final recibió el equipo como parámetro.

Compilación **Release firmada aprobada**, punto de entrada `lib/main.dart`, versión 0.7.0/build 9, mínimo iOS 16, ambos ONNX y PersonasShare.appex presentes. `codesign --verify --deep --strict` aprobó. Producto en `flutter_app/build/iphone/Build/Products/Release-iphoneos/Runner.app`; log en `/tmp/personas-iphone-release.log`.

Instalación por devicectl aprobada. Xcode confirmó inicialmente `Developer App Certificate is not trusted`; el usuario autorizó el desarrollador en el teléfono. Se dejó nuevamente el producto Release y se abrió por devicectl sin depurador; lanzamiento y proceso activo comprobados. El catálogo del dispositivo confirmó versión/build y App Group. Perfiles de esta instalación válidos hasta el 30 de octubre de 2026; requieren renovación para seguir ejecutando la app después de caducar. No se publicó en TestFlight/App Store ni se modificaron fotos.

Con ayuda solicitada por el usuario para el espacio, se eliminaron únicamente cachés regenerables identificadas de npm, pip, descargas Homebrew, módulos de Xcode y versiones de caché Gradle distintas de la actual, además de logs grandes de QA y una compilación fallida de esta migración. Liberados 7.26 GiB; disponibles 9.54 GiB inmediatamente después y aproximadamente 8.5 GiB tras compilar. Se conservaron SDK, modelos, XCFramework, APK y apps finales.

F11 completada para instalación y arranque físico. No se realizó una nueva revisión visual de pantallas ni la suite de reconocimiento en este iPhone; la evidencia de interfaz/HEIC/inferencia continúa siendo la de Android físico y simulador indicada arriba. F12 mantiene permisos completo/limitado, fototeca familiar, nube y recepción/compartir originales con cuentas reales.

## R22 / V18 — UI cercana y dinámica, 0.7.1+10 (2026-10-23)

Inicio «Encuentra tus mejores momentos», instrucciones en trato de tú, indicador de tres pasos y fotografía de referencia antes de los controles para cambiarla. Tema/tipografía/botones en `flutter_app/lib/app_theme.dart`; componentes de orientación, selección, progreso y aviso en `ui_components.dart`. Selecciones de rostros/álbumes/resultados, recuadros, miniaturas cargadas, cambio de paso y barra inferior usan transiciones breves. Movimiento reducido omite la animación de tamaño y hace inmediatos los demás cambios propios. No se añadieron dependencias visuales.

El aviso aparece antes de buscar y durante el análisis: «El primer escaneo de un álbum puede tardar un poco más. Si vuelves a buscar en las mismas fotos durante esta sesión, el reconocimiento puede ser más rápido». Describe la caché existente y acotada, que puede perderse al terminar el proceso/borrar la sesión; no afirma aprendizaje, precisión creciente ni aceleración persistente. No se modificaron motores, modelos, umbrales, permisos, originales ni el flujo de compartir.

Validación final:

- `tools/flutter.sh analyze`: sin incidencias; `/tmp/personas-r22-analyze.log`.
- **19 pruebas Dart aprobadas**: 13 de sesión y 6 de widgets, incluidas regresiones previas, estados vacíos/sin permisos y todos los pasos en 320×480 dp, texto 200 %, oscuro y movimiento reducido. La selección y compartir siguen alcanzables; etiqueta accesible con cantidad seleccionada. `/tmp/personas-r22-tests.log`.
- La prueba ampliada detectó que una etiqueta larga de la barra podía ocupar todo el alto con fuente grande. Se acortó la etiqueta visible y se conservó el significado completo para lectores de pantalla. También detectó un error de layout con AnimatedSize de duración cero al cambiar la selección: con movimiento reducido se omite ese widget. El test desplaza realmente la foto alta hasta su checkbox, sin suponer que toda la celda cabe en el viewport.
- Escenario Flutter nativo real aprobado en iOS Simulator ARM64: 50 entradas públicas, 46 coincidencias esperadas, dos personas negativas fuera de resultados, un noFace y un unreadable; repetición equivalente, selección de 46 y HEIC ampliado. Incluye seis variantes HEIC y 40 alias idénticos: no es una evaluación familiar de precisión ni un benchmark. Log final `/tmp/personas-r22-final.log`; hashes de YuNet/SFace correctos.
- Revisadas capturas públicas de referencia/rostro, álbumes sin permiso, aviso, resultados seleccionados, imagen completa y referencia sin rostro en `/tmp/personas-r22-final/`. La prueba conserva las capturas previas al registrar métricas. Para comprobar apariencia/tamaño reales de iOS se usó además la app normal con `simctl ui`: oscuro y `accessibility-extra-large` en `system-dark-large.png`, claro y tamaño anterior en `system-light.png`. Acción principal visible y contenido desplazable; restaurados `light`/`large`. Estas capturas del sistema son la evidencia visual de tema/texto, separada de los overrides del binding de test.
- App normal para iOS Simulator compilada y abierta. **Release iPhone firmada, instalada y abierta sin depurador** en iPhone 15 Pro Max/iOS 27.0.1; proceso activo comprobado. `codesign --verify --deep --strict` aprobado. Runner y PersonasShare muestran 0.7.1/build 10; la extensión toma la versión de la configuración Flutter. Team/dispositivo siguen como parámetros locales. Log `/tmp/personas-r22-iphone-build.log`.
- APK Android ARM64 debug compilado: `co.local.personas`, versión 0.7.1/code 10 comprobados con aapt. La versión Android también deriva de pubspec. Tras comprobar por la interfaz accesible que no había análisis activo, actualización in situ aprobada en CPH2637 y arranque de MainActivity verificado. Gradle conserva sus advertencias previas de futuras versiones mínimas de Flutter; no se omitió su validación. `/tmp/personas-r22-android-build.log`.

Los tests usan dobles únicamente en `test/`; las fotos de integración son públicas y permanecen fuera del repositorio. No se usaron fotografías personales para estas capturas. No se volvió a ejecutar una evaluación de reconocimiento con álbumes privados ni se revisaron visualmente las nuevas pantallas en el iPhone físico; la revisión visual fue en simulador. F12/T49/T10/T31/T35/T12/T13 mantienen su alcance pendiente. La firma personal conserva la caducidad del 30 de octubre de 2026.

## R23 / V19 — Segundo plano y avisos, 0.8.0+11 (2026-10-23)

Android desacopla la búsqueda de la Activity con runtime de aplicación/servicio dataSync, progreso real y cancelación, wake lock acotado, timeout y aviso final. iOS solicita tarea continua CPU en iOS 26+ y utiliza tiempo limitado si se rechaza; atiende expiración/cancelación y publica notificación local. Permiso de avisos opcional, solicitado en contexto, con acceso a sus ajustes. Snapshot nativo y último análisis en caché privada, sin embeddings persistidos; selección, feedback y progreso se reconcilian al volver o abrir el aviso. Se conserva el recorte de referencia para mostrarlo tras un arranque nuevo, pero se exige volver a elegir la referencia para buscar si sus handles caducaron. [ADR 010](decisions/010-analisis-en-segundo-plano.md).

Verificado:

- **29 tests Dart aprobados** y análisis estático sin incidencias. Diez regresiones nuevas cubren restauración fría, eventos perdidos/duplicados, finalización durante inicialización, notificaciones denegadas sin bloquear ni repetir el diálogo, cancelación pendiente de permiso, interrupción, borrado con snapshot pendiente, selección/feedback, aviso antiguo durante una nueva búsqueda y caché purgada. El test de pantalla pequeña/200 %/oscuro/movimiento reducido incluye ahora el aviso de segundo plano. Logs `/tmp/personas-r23-tests-final.log` y `/tmp/personas-r23-analyze-final.log`.
- Compilaciones Android ARM64 debug y iOS Simulator ARM64 aprobadas. iPhone Release normal compilada con perfiles locales y firma completa verificada; Runner y PersonasShare 0.8.0/build 11. `UIBackgroundModes=processing` e identificador de tarea `co.local.personas.analysis.*` presentes en la app compilada. No se guardan Team/UDID en el proyecto. Logs `/tmp/personas-r23-final-android-build.log`, `/tmp/personas-r23-final-sim-build.log`, `/tmp/personas-r23-final-iphone-build.log`.
- **Prueba nativa real de cambio de app en iOS Simulator/iOS 27.1** con `integration_test/background_probe.dart`, sin driver de tests ni temporizador simulado. 370 fotos públicas: 50 fixtures HEIC/alias/negativas anteriores + 320 variantes JPEG con píxeles/bytes distintos de la misma muestra pública fijada. Al iniciar se abrió Ajustes; el archivo nativo registró avance 0→25→50…→370 y finalización mientras Personas seguía fuera de primer plano. Resultado: 366 match, 2 none (identidades distintas), 1 noFace, 1 unreadable. La repetición en primer plano produjo **idénticas decisiones en las 370 entradas**, sin duplicados. No es calibración de precisión familiar ni benchmark. `/tmp/personas-r23-sim-background.json`, `/tmp/personas-r23-sim-report.json`.
- El simulador **rechazó la continuación ampliada y concedió `iosLimited`**. Esa ruta completó esta prueba corta; no demuestra ejecución ilimitada ni que BGContinuedProcessingTask sea concedida en iPhone. Avisos sin autorización durante la prueba no bloquearon el análisis.
- Terminación/reapertura del proceso de prueba después de completar: restauró 370 eventos/366 coincidencias idénticas y detectó referencias caducadas; muestra una acción útil para volver a elegirlas. `/tmp/personas-r23-sim-restored.json`; captura pública revisada `/tmp/personas-r23-sim-results.png`.
- Cancelación nativa real en un segundo escenario: detuvo una búsqueda de 370 con **26 procesadas**, `active=false`, `cancelled=true`, mantuvo las 26 coincidencias parciales y no anunció éxito. `/tmp/personas-r23-sim-cancelled.json`; captura `/tmp/personas-r23-cancelled.png`.
- Android físico conectado, pero bloqueado. El intento QA anterior a la comprobación de visibilidad fue rechazado por Android (`ForegroundServiceStartNotAllowedException`), dejando estado cancelado y cero procesadas; no se publicó éxito. Se añadió mensaje concreto para volver y pulsar Buscar. La entrada QA ahora espera estado resumed. Esto **no prueba aún continuidad/aviso Android**.
- Tras las pruebas se restauró el punto de entrada normal `lib/main.dart`, se actualizó Android in situ y se abrió su Activity; sigue pendiente desbloquear para revisión visible. Se retiraron únicamente fixtures/marcadores/resultados públicos de QA de los contenedores. La aplicación normal de simulador también quedó restaurada. Verificado que los binarios normales no incluyen `background-probe.json`.
- Hash y tamaño de YuNet/SFace correctos; sin cambios en modelos, umbrales, detección, preprocesamiento o compartir originales. Sintaxis del preparador Python y configurador Ruby aprobada. No hay dependencias nuevas.

**Estado al 2026-10-23 (actualizado en el cierre físico siguiente):** iPhone físico desconectado (destino offline/túnel no disponible); su Release normal estaba preparada, pero esta actualización no pudo instalarse allí. Quedaba desbloquear Android y reconectar iPhone para comprobar continuación ampliada, entrega/tap del aviso, progreso y cancelación desde el sistema con permiso real. El cierre forzado y las decisiones del sistema pueden detener el análisis; se recupera como interrumpido con lo guardado y no se reinicia ocultamente. La caché del último análisis no es un índice de reconocimiento ni un historial. La evaluación de fototecas familiares/proveedores con cuentas reales de F12 sigue pendiente.

### Cierre físico de F21 — 2026-10-24

Ambos dispositivos volvieron a estar disponibles. Comprobaciones con 370 fotos públicas y los adaptadores/modelos reales, sin driver que mantuviera la app visible:

- **Android CPH2637/API 36:** al aparecer `running` se abrió Ajustes; checkpoints 0→25→50…→370, `cancelled=false`, 366 coincidencias/2 negativas/1 sin rostro/1 ilegible. Repetición visible con idénticas 370 decisiones; reinicio del proceso recuperó todos los resultados y detectó handles caducados. Servicio detenido y wake lock liberado al terminar; la comprobación excluye el historial de adquisiciones/liberaciones de `dumpsys power`. Evidencia `/tmp/personas-r23-android-background-device.json`, `/tmp/personas-r23-android-banner-device.json`, `/tmp/personas-r23-android-device-report.json`, `/tmp/personas-r23-android-cold-device.json`; captura pública revisada `/tmp/personas-r23-android-public-results.png`.
- El aviso Android se publicó con texto correcto y PendingIntent de resultados. Se observó que el canal inicial normal no habilitaba banner, y se añadió canal de importancia alta con preservación de elecciones del usuario. Confirmados en el registro real `IMPORTANCE_HIGH`, `mShowBanner=true` y permiso concedido. La captura accesible de ColorOS no mostró el banner; la alternativa de reconocimiento visual del host falló al iniciar Vision. **No se afirma haber verificado visualmente el banner ni un tap real Android**. Sí se comprobó la ruta de apertura por el mismo extra `openAnalysis`, publicación, configuración, recuperación y servicio.
- **iPhone 15 Pro Max/iOS 27.0.1:** sistema concedió **`iosContinued`**; al iniciar se activó Ajustes y se registró progreso hasta 370/finalización. Las decisiones en segundo plano coinciden con la referencia en primer plano del mismo dispositivo. No se cambió el procesamiento al revisar la entrega. Tras esperar el callback de registro antes de liberar la tarea, estado real: `completionDelivered=true`, `banners=true`, `notificationCenter=true`, `lastDeliveryFailed=false`. **El usuario confirmó que tocar el aviso abre los resultados.** `/tmp/personas-r23-iphone-background-device.json`, `/tmp/personas-r23-iphone-device-report.json`, `/tmp/personas-r23-iphone-delivery-device.json`.
- Una espera manual del protocolo QA para repetir en primer plano caducó mientras se revisaba el aviso; el motor ya había procesado las 370 fotos y guardado `done` sin cancelación/error. Se contrastaron sus 370 decisiones guardadas con la referencia visible anterior y resultaron idénticas. No se presenta ese handshake caducado como una nueva prueba de repetición aprobada.
- El escenario iPhone usa el alias `/var` de Foundation en lugar de `/private/var` del temporal Dart. El marcador `background-ready` se transfirió **después** de las fotos: la copia de directorios al dispositivo no garantiza el orden. Son ajustes de QA; los proveedores de producción ya devuelven URLs nativas.
- **29 tests Dart aprobados** y análisis estático sin incidencias: `/tmp/personas-r23-physical-tests.log`, `/tmp/personas-r23-physical-analyze.log`. Compilaciones normales finales Android/iPhone aprobadas, firma iPhone íntegra verificada y ambos binarios sin `background-probe.json`. Logs `/tmp/personas-r23-physical-final-android-build.log`, `/tmp/personas-r23-physical-final-iphone-build.log`. Versión 0.8.0/build 11.
- Versiones normales instaladas/abiertas en ambos teléfonos. Se retiraron únicamente las imágenes/marcadores/resultados públicos de QA. iPhone usó el método nativo `clear` mediante una entrada QA de limpieza; después se instaló `lib/main.dart` sin flags QA. Una búsqueda real iniciada por el usuario se dejó terminar antes de actualizar y se conservaron sus resultados; no se exportaron sus fotos ni se añadieron sus identificadores a la evidencia. Ajuste temporal de pantalla USB Android restaurado exactamente a su valor anterior y avisos QA retirados.

F21 cerrada con estos límites de evidencia. La cancelación nativa de 26 fotos del simulador y las regresiones del controlador siguen vigentes; la acción de cancelar desde una notificación Android no se pulsó en el dispositivo físico. La presentación de banners depende del sistema y de preferencias del usuario; no se evitan No molestar ni las restricciones de iOS. F12/F13 mantienen su alcance pendiente; esta validación no calibra precisión familiar ni promete ejecución tras cierre forzado.

## R26 / V22 — Preparación recuperable en iPhone (2026-10-24)

Versión 0.8.1/build 12. El usuario informó una barra de carga persistente en «¿A quién quieres encontrar?» con los comandos bloqueados. La preparación/selección no disponía de plazo ni cancelación desde esa pantalla. Ahora usa identidad de petición, finalización única, Cancelar carga y cancelación con Volver. La referencia y cada importación tras cerrar el selector caducan a los 90 segundos; elegir fotos no caduca. Se atiende el cierre interactivo del selector, y las consultas síncronas a Fotos para referencia/preview/importación se ejecutan fuera del hilo principal. Los resultados tardíos no sustituyen ni desbloquean otra petición; sus handles se liberan. La liberación de referencias anteriores no mantiene la interfaz ocupada. Modelos, escalas y umbrales intactos.

- **40 pruebas Flutter aprobadas**: cargas pendientes, cancelación por botón/flecha, selección tardía con éxito/error, recuperación tras error, limpieza anterior pendiente, notificación/inicialización antigua durante una nueva carga, pantalla 320×480 dp y texto 200 %. Regresiones existentes de análisis/selección/compartir conservadas. `/tmp/personas-r26-tests.log`.
- **Análisis estático sin incidencias**: `/tmp/personas-r26-analyze.log`.
- **Pruebas Swift Foundation**: `ios/Tests/PhotoPreparationTests.swift` compila con la clase de producción y comprueba cancelación inmediata, plazo, respuesta única, respuesta tardía, reintento y renovación de plazo por elemento. Ejecutable temporal `/tmp/personas-photo-preparation-tests` aprobado.
- **Integración nativa iOS Simulator ARM64**: `integration_test/reference_recovery_test.dart` aprobado con HEIC público de QA. Cancela la primera referencia, ignora una cancelación de esa petición durante la segunda, detecta rostros al reintentar y obtiene preview. Sin API de fixtures de producción ni borrado global de sesión; sólo una copia pública, retirada al terminar. `/tmp/personas-r26-ios-integration.log`.
- **Compilaciones**: APK Android y app normal de simulador aprobados; Release iPhone aprobada y firma completa verificada. `/tmp/personas-r26-android-build.log`, `/tmp/personas-r26-ios-normal-build.log`, `/tmp/personas-r26-iphone-build.log`. Simulador restaurado al punto de entrada normal.
- **iPhone físico**: Release 0.8.1+12 instalada y abierta sin depurador después de confirmar que no había análisis activo. Se conserva el resultado anterior de 203 fotos procesadas. Sólo se consultaron estado/cantidades; no se exportaron fotografías ni se guardaron sus identificadores.

Límite: no se reprodujo manualmente el bloqueo con la foto concreta del usuario ni con un proveedor cloud real; tampoco se ejercitó un gesto físico de cierre del selector en esta revisión. La cancelación del puente real se verificó en simulador y la UI en widget tests. F12 mantiene las pruebas con cuentas/fototeca reales. Esta corrección no es una nueva evaluación de precisión.
