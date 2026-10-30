# ADR 013 — Optimizar lectura y conservar el motor tras medir alternativas

Estado: lector optimizado implementado; inferencia y planificación actuales conservadas. Android CPH2637, SoC MT6835, heap Java de 256 MiB. No se ha demostrado una aceleración grande del escaneo completo.

## Cambio aplicado

`ContentPhotos` abre un `AssetFileDescriptor` y usa su longitud únicamente para decidir si cabe un snapshot y reservar su buffer. Si supera 8 MiB, pasa directamente a la misma decodificación URI que ya usaba: evita leer primero 8 MiB que iba a descartar. Con longitud desconocida o incorrectamente pequeña sigue leyendo hasta EOF o hasta el límite; nunca trunca según metadatos.

El SHA-256 del snapshot se calcula durante esa lectura, con el mismo prefijo y todos los bytes, en vez de recorrer otra vez el buffer en otro dispatcher. La longitud, URI y fecha no se usan como identidad. La caché conserva las mismas claves. Cancelación, límite de 8 MiB y fallback HEIF de hasta 64 MiB se mantienen.

Píxeles sRGB/ARGB8888, orientación, lado máximo de 3200, dos escalas YuNet, dos vistas SFace, pesos FP32, umbrales, normalización, confirmaciones y cola de analítica no cambian. Ninguna alternativa de inferencia se añadió a la app.

## Mediciones y opciones descartadas

Se midieron opciones reales, no se adoptaron por promesas de una biblioteca. Modelos y referencias preparados, caché facial vacía en cada recorrido. Las imágenes personales permanecieron dentro del teléfono; sólo se extrajeron tiempos y conteos agregados.

| Experimento | Resultado y decisión |
| --- | --- |
| YuNet, uno/dos/cuatro hilos | Cuatro hilos mejoraron la microprueba de detección, pero combinar cuatro en detección y dos en reconocimiento empeoró el pipeline completo ~3,4 % en cuatro rondas. Conservar dos. Cajas/vectores de la prueba sintética fueron idénticos. |
| Un detector por escala | Mejora media del pipeline sintético ~0,8 %, menor que la variación entre rondas, con otro detector en memoria. Descartado. |
| ONNX Runtime Android 1.31.1, mismo SFace | Por 40 inferencias de una cara pública: OpenCV 1438,86 ms; ORT CPU 1623,22 ms; XNNPACK 2502,73 ms; NNAPI 60441,56 ms. Es una prueba de un recorte, no precisión de álbumes. Diferencias máximas ~3–4e-6 frente a OpenCV. Descartados; ORT sólo es dependencia opcional del banco de pruebas. |
| Dos preparaciones paralelas, tres slots | Dos rondas sobre seis fotos autorizadas: preparación serial optimizada 10813,76/10782,42 ms; paralela 10904,60/10355,97 ms. Mismas decisiones, cero ilegibles, ningún MATCH en esta muestra. Ganancia media ~1,6 %, no consistente y con mayor memoria. Descartado. Se conserva el máximo previo de dos bitmaps y la limitación para fotos grandes. |

### Lector optimizado

Prueba sintética alternada, cuatro rondas de diez preparaciones: PNG público de 92×112; versión grande del mismo PNG con relleno hasta más de 12 MiB. No representa el coste de decodificar una foto grande en píxeles ni mide inferencia.

| Archivo | Antes, media por 10 | Después, media por 10 | Reducción |
| --- | ---: | ---: | ---: |
| Pequeño | 78,12 ms | 66,88 ms | 14,4 % |
| Mayor de 12 MiB | 302,23 ms | 65,06 ms | 78,5 % |

Se comprobaron píxeles decodificados y claves de caché iguales. Estos porcentajes describen **preparación/decodificación de esos archivos**, no velocidad del escaneo completo.

Muestra real de seis entradas espaciadas de la última selección inactiva, con referencias autorizadas, dos órdenes alternados: anterior 12026,21/11932,36 ms; optimizado 11677,88/11998,83 ms. Media 11979,29→11838,35 ms (~1,2 %), con una ronda en sentido contrario. No es evidencia de una mejora grande o estadísticamente estable del recorrido completo. Cero hits de caché, cero ilegibles y mismas decisiones; no hubo MATCH en esa muestra, por lo que no evalúa precisión con positivos familiares.

La decodificación acumuló alrededor de 9,7–10,2 s y el motor 8,4–9,1 s; ya se solapan, no deben sumarse. La lectura optimizada reduce trabajo, pero no elimina esos costes dominantes. No se extrapolan seis entradas al álbum completo ni se ofrece un porcentaje universal.

## Validación

- 33 pruebas JVM aprobadas, incluidas seis del lector: no leer snapshots grandes conocidos, hash completo idéntico, longitud pequeña incorrecta, límite con tamaño desconocido, cancelación y rechazo temprano de encabezado.
- 75 pruebas Flutter aprobadas, una prueba opt-in de producción omitida; analizador sin incidencias, desde checkout aislado.
- Android: píxeles y claves iguales antes/después; cuatro contratos originales de `FilteringTest` ejecutados, sin omisiones (conteos AT&T/ORL, alias/contenido cambiado, EXIF/archivo grande, caché parcial con nueve caras).
- Conteos de evaluación conservados: una referencia 179/180 positivos y 0/3420 falsos positivos; dos 160/160 y 0/3040; cuatro 120/120 y 0/2280. Sigue siendo la regresión controlada y conocida de ADR012, no garantía para álbumes familiares.
- No se crearon eventos sintéticos ni se enviaron fotos, vectores o rutas a la API.

## Herramientas y reproducción

`tools/android_scan_benchmark/run.py` genera una app temporal independiente. Las pruebas públicas usan sólo un fixture suministrado por el desarrollador; `AlbumReadProfile` requiere una compilación de desarrollo sin R8 de `co.local.personas.pruebas`, firmada con la misma clave, una selección inactiva y la invocación explícita. El modo de álbum no es parte de la app publicada. Ver el README de la herramienta.

Fuentes primarias consultadas:

- [ONNX Runtime móvil](https://onnxruntime.ai/docs/tutorials/mobile/): recomienda medir en cada dispositivo y advierte que particionar el modelo puede degradar el rendimiento.
- [API Java SessionOptions](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OrtSession.SessionOptions.html): CPU, XNNPACK y NNAPI.
- [ML Kit Face Detection](https://developers.google.com/ml-kit/vision/face-detection): detecta caras, no identifica personas; no sustituye por sí solo SFace.
- [AssetFileDescriptor](https://developer.android.com/reference/android/content/res/AssetFileDescriptor): longitud y creación del stream del recurso.
- [InsightFace](https://github.com/deepinsight/insightface#license): el código y sus modelos publicados tienen condiciones diferentes; no se incorporaron pesos de investigación a la app comercial.

Para un salto mayor sigue pendiente evaluar decodificación y otro motor con un conjunto representativo etiquetado. Reducir resolución, quitar escalas o simplificar referencias no se considera una optimización equivalente de precisión.
