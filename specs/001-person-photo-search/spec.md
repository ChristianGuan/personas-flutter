# 001 — Búsqueda de persona en fotos

R21 amplía la aplicación a Android/iOS mediante Flutter y conserva los requisitos anteriores: [especificación 002](../002-flutter-migration/spec.md), [plan](../002-flutter-migration/plan.md) y [tareas](../002-flutter-migration/tasks.md). La implementación Android original se mantiene como fuente del motor/modelos y referencia verificable.

## Historias y requisitos

| ID | Historia / requisito | Criterio observable |
|---|---|---|
| R01 | Como propietario elijo una referencia | Selector de imágenes; sin acceso global obligatorio |
| R02 | Elijo a una persona entre varias | Recuadros sobre la imagen corregida; tocar uno; no buscar sin elección |
| R03 | Defino el conjunto | Sólo URIs seleccionadas; luego álbum MediaStore con filtro estricto por bucket y volumen |
| R04 | Busco con IA local real | Detección + cinco landmarks + alineación + embedding normalizado + coseno; una foto por URI; basta una cara coincidente |
| R05 | Comprendo estados vacíos | Explicar referencia sin rostro y búsqueda sin coincidencias |
| R06 | Puedo esperar o cancelar | UI responde; contador real, omitidas y tiempo; cancelar entre operaciones; no corromper índice |
| R07 | Reviso y comparto | Cuadrícula, ampliación, selección individual/todas; ACTION_SEND_MULTIPLE sólo seleccionadas y permisos temporales |
| R08 | Reutilizo análisis | Índice privado; invalidar por contenido, modelo y preprocesamiento; limpiar entradas eliminadas |
| R09 | Controlo datos y permisos | Borrar derivados, excluir backup, sin logs sensibles ni red de aplicación; manejar denegación/revocación |
| R10 | Accedo a álbumes disponibles | Completo/limitado/denegado/revocado; no MANAGE_EXTERNAL_STORAGE; alternativa de selección |
| R12 | Selecciono más de 30 fotos y uso una interfaz clara | Selección por máximo nativo, añadir tandas sin duplicados, alternativa Archivos, vaciar conjunto, acciones visibles y pantalla desplazable |
| R11 | Evalúo calidad | Etiquetas reales, TP/FP/FN/TN, precisión, recuperación y duración por dispositivo; nunca porcentajes de certeza |

## Escenarios de aceptación manual

- V01 (R01,R02,R05): referencia con dos personas; tocar ambas alternativamente; foto sin caras; fotos EXIF 1–8.
- V02 (R03,R04): conjunto con fotos individuales, grupales, negativas y duplicadas; ningún resultado ajeno al conjunto.
- V03 (R06,R09): cancelar mientras procesa; archivo ilegible/eliminado; revocar permisos; la siguiente búsqueda sigue funcionando.
- V04 (R07): abrir foto, seleccionar una, todas y ninguna; receptor nativo recibe exactamente las elegidas.
- V05 (R08): repetir búsqueda sin cambios, editar una imagen, cambiar modelo/preprocesamiento, borrar imagen e índice.
- V06 (R10): acceso completo, limitado, denegado y revocado en Android 14+; álbum remoto no se presenta como carpeta local.
- V07 (R04,R11): modo avión con fotos locales y modelos incluidos; evaluación etiquetada descrita en docs/validation.md.

No hay datos de evaluación aportados. Ningún escenario manual se considera aprobado por compilar el APK.

- V08 (R03,R12): seleccionar >30 fotos; añadir otra tanda con duplicados; cancelar una tercera tanda sin perder el conjunto; vaciar conservando referencia; revisar en pantalla pequeña, tema oscuro y texto ampliado. La capacidad por tanda depende de Android/proveedor, no prometer selección ilimitada por apertura.

## R13 — Diagnóstico de coincidencias ausentes

V09: después de buscar se muestra un conteo de coincidencias, fotos sin rostros utilizables, fotos con rostros sin coincidencia suficiente y errores. Cada descartada se puede ampliar para revisión local, sin confundirse con coincidencia ni poder compartirla como tal. Cambiar referencia, rostro o conjunto reinicia el diagnóstico. Cancelar conserva únicamente las fotos ya procesadas. No persistir diagnóstico ni información sensible en logs. La categoría no establece por sí sola la causa de un fallo del rostro objetivo en una foto grupal.

## R14 — Flujo visual cálido, accesible y por pasos

Inicio con “Encuentra sus mejores momentos”, acción “Buscar a una persona” y explicación solicitada. No mostrar búsquedas recientes sin persistencia real. Referencia amplia con recuadros tocables, alternativa accesible mediante chips y recorte de la cara elegida. Álbumes MediaStore reales con portada/nombre/cantidad visible según permiso, selección mediante borde/check/texto y alternativa de fotos individuales. Análisis con persona/conjunto, progreso real, coincidencias progresivas y cancelar. Resultados revisables a imagen completa con selección múltiple y compartir fijo.

V10: navegación atrás entre pasos; inicio y referencia vacía; referencia sin rostro; permiso completo/limitado/denegado/revocado; álbumes vacíos; cancelar/errores parciales/sin coincidencias; selección no comunicada sólo por color. Verificar pantalla pequeña, fuente 200%, tema oscuro y animaciones desactivadas. Las fotografías en producción siempre proceden de selección real o MediaStore autorizado. No variar reconocimiento para obtener resultados visuales.

## R15 — Referencias con más de tres rostros

V11: todos los rostros detectados tienen una miniatura seleccionable, sin un máximo de tres y con scroll lazy. Comprobar rostros 4 y 9 por miniatura y rostro 7 sobre la imagen. Si se superponen cajas, el toque prioriza la caja menor que contiene el punto. Una persona no detectada no se presenta como un rostro reconocido ficticio.

Fotos grandes: detectar a resolución de análisis y en una segunda escala de lado máximo 960; reproyectar caja y cinco landmarks, fusionar duplicados por IoU y generar embeddings sobre la imagen de análisis original. Conservar umbral de reconocimiento y detección de búsqueda (0.85); usar score 0.65 exclusivamente para los candidatos de referencia revisados por el usuario. Probar nueve caras con inferencia nativa real y confirmar que no se duplican por las dos escalas.

## R16 — Reconocimiento con referencias complementarias confirmadas

El usuario reporta mayoría de búsquedas sin coincidencias pese a presencia real; diagnóstico predominante BELOW_THRESHOLD. No atribuirlo automáticamente a detección o un error matemático. V12: probar fotos realmente distintas de una misma persona, con pose/iluminación diferentes y controles negativos; no sólo copias del mismo archivo.

Permitir añadir otra foto de referencia de la misma persona. El usuario debe confirmar el rostro correcto de cada foto; no incorporar automáticamente caras de resultados/descartadas ni usar suposiciones como etiquetas. Coincide una foto si cualquiera de sus caras supera el umbral actual con cualquiera de las referencias confirmadas. Conservar conjunto y álbum al añadir referencia para repetir sobre las mismas imágenes. Reemplazar referencia limpia las anteriores. Cancelar/fallar al añadir preserva las referencias válidas. No sumar fotos ilegibles o sin cara como ejemplo válido. Miniaturas/embeddings sólo en memoria y borrados con la sesión; sin logs sensibles.

Las descartadas pueden abrirse y proponerse como otra referencia; se debe seleccionar explícitamente el rostro antes de repetir la búsqueda. No aceptar automáticamente otra cara de un grupo ni rebajar globalmente la similitud hasta admitir negativos conocidos.

## R17 — Fotografías de Google Fotos y almacenamiento en la nube

Permitir elegir fotografías de Google Fotos mediante el Photo Picker de Android cuando exista un proveedor de nube compatible y esté habilitado por el usuario. Mostrar acceso explícito «Google Fotos» en referencia y conjunto, explicación de la configuración y enlace a los ajustes del selector. No afirmar que un proveedor está conectado sólo porque Google Fotos esté instalado. Los álbumes MediaStore siguen siendo exclusivamente locales; los álbumes remotos se exploran dentro del selector del sistema, según disponibilidad del proveedor.

Alternativa: recibir imágenes enviadas desde Google Fotos u otra galería mediante Compartir → Personas, sin enviar nada a terceros. Confirmar si una sola imagen será referencia o parte del conjunto; varias imágenes se añaden al conjunto tras confirmación. Conservar la referencia y acumular/deduplicar fotografías; advertir cuando se sustituye un álbum local. Una importación durante el análisis queda pendiente hasta que termine o se cancele, sin cambiar el conjunto en ejecución. Rechazar esquemas distintos de content:// y tipos conocidos que no sean imágenes. Cancelar no modifica la sesión.

El proveedor puede descargar los archivos y necesitar conexión. La app procesa únicamente fotos autorizadas, fuera de Main, sin OAuth propio, claves, backend, permiso INTERNET ni exploración automática de toda la biblioteca de Google. Archivos conserva acceso a imágenes de Google Drive cuando su proveedor esté disponible. Errores de disponibilidad/descarga deben ofrecer volver a elegir; no inventar progreso de descarga.

V13: apertura del selector y de sus ajustes en el dispositivo; conservar sesión al cancelar; importar una y varias imágenes con grants temporales, deduplicación y rechazo de archivos/tipos ajenos; referencia y búsqueda real con contenido autorizado; comprobación de texto grande y ajustes no disponibles. Separar comprobaciones de integración Android de una descarga cloud real con cuenta del usuario: no dar esta última por validada sin realizarla.

## R18 — Análisis más rápido conservando las decisiones de reconocimiento

El usuario reporta lentitud tanto en el primer análisis como al repetir. Mantener pesos, FP32, umbrales, resolución máxima, orientación, dos escalas YuNet, fusión de detecciones, alineación, normalización y comparación actuales. No sustituir originales por miniaturas ni omitir caras por tamaño/posición distintos de la política existente.

Durante la búsqueda, dejar de generar embeddings cuando una cara ya satisface la misma condición «cualquier cara coincide con cualquier referencia». Para una foto sin coincidencias se deben evaluar todas sus caras. La referencia sigue generando todos los rostros seleccionables. Una preparación anticipada acotada permite decodificar la siguiente imagen mientras se analiza la actual, manteniendo orden, progreso real, errores parciales y cancelación.

Reutilizar detecciones y embeddings mediante caché RAM acotada de la sesión, con clave SHA-256 de los píxeles BGR exactos usados por el motor, dimensiones y versión de pipeline. Leer/decodificar otra vez para comprobar el contenido y el acceso; nunca usar sólo URI/fecha/tamaño como prueba de identidad. Conservar todas las detecciones y distinguir embeddings aún no calculados para poder cambiar de persona sin perder caras. Borrar sesión limpia la caché. No persistir fotos, recortes ni nuevos datos biométricos en disco; el índice persistente R08/T12 sigue siendo otro incremento.

V14: comparar decisiones/outcomes/orden con el recorrido completo anterior en imágenes positivas, negativas, grupos y sin caras; cambiar referencia tras una coincidencia temprana; editar una foto conservando URI; caché vacía/caliente/expulsada; cancelación con una foto preparada y errores intermedios. Medir antes/después separando primer recorrido y repetición, con tiempos reales y alcance explícito. Una medición host no se presenta como rendimiento Android.

## R19 — Menos personas equivocadas y repetición más rápida

El usuario aclara que el filtro incluye otras personas. Separar aceptación automática estricta, casos por revisar y descartadas. Elegir el umbral automático con positivos y negativos de calibración pública y reportar aparte sujetos de evaluación; mantener 0.363 sólo como límite de candidatos revisables. No llamar coincidencia automática a una similitud dudosa ni compartir candidatos mediante Seleccionar todas. Mostrar Por revisar con contador y revisión a imagen completa; Sí es esta persona confirma explícitamente, No es esta persona descarta y retira de selección. Las confirmaciones se etiquetan como del usuario, sin entrenar ni añadir referencias automáticamente.

Recordar descartes manuales sólo en la sesión y para el contenido exacto de la persona buscada. Editar el contenido o empezar otra persona no debe heredar un rechazo ajeno. Permitir restauración explícita. Mantener modelos locales, permisos y uso compartido, y no mostrar scores como porcentajes.

Para acelerar repeticiones, comprobar bytes codificados completos mediante SHA-256 y reutilizar un análisis existente antes de decodificar cuando sea suficiente. Si faltan embeddings para otra referencia o la caché expiró, decodificar esos mismos bytes y completar el análisis. No validar contenido sólo por metadatos/URI. Limitar memoria de bytes preparados; archivos grandes y proveedores incompatibles conservan la ruta de lectura/decodificación anterior sin reutilización codificada. No persistir fotos ni vectores nuevos. Preparar las normalizaciones de comparación una vez conservando el cálculo coseno previo.

V15: comprobar falsos positivos y recuperación automática/pendiente por separado, con sujetos distintos entre calibración/evaluación, y referencias 1/2/4. Comparar cacheada/completa con la misma política estricta, contenido/EXIF cambiado, registro parcial, archivo grande, error/cancelación y acceso perdido. Verificar que confirmar/descartar actualiza resultados y compartir, que descartar no reaparece al repetir y que nueva persona/contenido no hereda descartes. Medir primer/repetido en Android e instalar; no extrapolar una base histórica de rostros frontales a familias reales.

## R20 — HEIC/HEIF en referencia y conjunto

El usuario reporta que los HEIC descargados aparecen en el selector, pero fallan al abrirlos tanto para referencia como para búsqueda. Corregir la lectura compartida por referencia, miniaturas y batch; no atribuir el fallo al selector ni modificar umbrales/modelos. ImageDecoder debe conservar orientación/resize y entregar un bitmap software sRGB ARGB_8888 compatible con bitmapToMat, incluso cuando la fuente tenga color ampliado/alta profundidad. Nunca recomprimir ni modificar el archivo original.

Conservar snapshots/caché acotados con versión de decodificación nueva y el mismo contrato en ruta URI y bytes. Si el lector nativo falla, intentar decodificación HEVC local sin red, con límites de tamaño y orientación conservada. Cancelación y error deben liberar también los bitmaps intermedios de conversión. Si ambos lectores rechazan el archivo o está incompleto, mostrar un error de lectura útil, distinto de «sin rostros», conservando referencias válidas. No afirmar compatibilidad universal con variantes HEIF ni validación de dispositivo sin ejecutar las pruebas.

V16: HEIC reales 8/10 bits, color P3, extensión .HEIC, referencia y conjunto con inferencia nativa, primer/repetido y orden/error parcial. Verificar conversión F16/sRGB, orientación y que JPEG/PNG normales conservan píxeles/decisiones. Fixtures públicos sólo fuera de APK/Git; compilar/lint/pruebas y usar dispositivo/emulador disponible.
