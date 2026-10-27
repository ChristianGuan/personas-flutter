# ADR 011 — Solapar preparación e inferencia en Android con memoria acotada

El usuario observó que la primera búsqueda Android tarda mucho más que iOS. No se atribuye esta diferencia a la CPU: las referencias/fotos pueden diferir y Android se estaba ejecutando debug mientras iOS Release. El motor ya se inicializa durante la selección de referencia; precargar modelos antes del contador no resuelve el recorrido inicial del álbum.

Se midió en el Android conectado con seis entradas espaciadas del último conjunto autorizado de209 fotos, dos rondas intercaladas e idénticas referencias. Las fotos se procesaron sólo dentro del teléfono: se extrajeron contadores/tiempos, nunca fotos, embeddings, rutas ni IDs. El último snapshot y los originales no se modificaron. La caché nativa de análisis se vació antes de cada recorrido; no se vació la caché del sistema operativo/proveedor. Referencia y modelos preparados, igual que al pulsar Buscar en la app.

| Hilos / umbral de bitmap actual | Ronda1 | Ronda2 | Media |
|---|---:|---:|---:|
| 2 /16MiB (anterior) | 16004ms | 15721ms | 15863ms |
| 2 /32MiB | 11890ms | 12138ms | 12014ms |
| 4 /32MiB | 12281ms | 12455ms | 12368ms |

Los seis resultados por foto fueron iguales en las seis ejecuciones, con13 embeddings calculados, cero hits de caché y cero imágenes ilegibles. No hubo coincidencias fuertes en esta muestra; no es una evaluación de precisión ni un benchmark de las209 fotos. Resultado: **24,3% menos tiempo en la muestra emparejada**, sin promesa de igual mejora en todos los álbumes.

La preparación ocupaba9,1–9,3s y el paso de detección completo5,1–5,7s por recorrido anterior. Al serializarlos para bitmaps mayores de16MiB se impedía solapar la decodificación de fotos habituales de3200px. Permitir preparación simultánea aumentó algo los costes individuales por contención pero redujo el tiempo total. Cuatro hilos no mejoraron frente a dos; se mantienen dos. Los tiempos por etapa pueden solaparse y no deben sumarse como si fueran fases seriales.

Se mantiene el canal rendezvous y una sola inferencia nativa. Se permite preparar el siguiente bitmap si el actual ocupa como máximo min(32MiB,maxHeap/8). Dispositivos low-RAM o sistema con MemoryInfo.lowMemory al iniciar la búsqueda limitan el umbral a16MiB o menos según heap. Entradas diferidas o mayores esperan a liberar la actual. Máximo dos imágenes preparadas; el umbral es de la imagen actual, no un límite de memoria total. La siguiente imagen puede llegar al límite de3200x3200ARGB8888 y existen buffers transitorios de conversión, Mat y DNN. No se habilita largeHeap ni se mantienen bitmaps adicionales en caché.

Se conservan sRGB/ARGB8888, orientación y fallback HEIC, resolución máxima3200, ambas escalas full+960, filtros de cara, hashes/modelos, FP32, umbrales, NMS, coseno, caché de vectores en RAM y orden de resultados. No hay nuevas propiedades analíticas ni permisos. Los contadores opcionales son para perfilado local; no registran cuerpos/datos personales ni se envían a la API. La optimización se aplica al runtime Flutter Android; el prototipo anterior mantiene su umbral por defecto para comparaciones.

Validación de seguridad: presupuesto bajo distintos heaps/presión de memoria, límites de preparación y cancelación con reciclaje de todos los bitmaps, fallo de proveedor sin cambiar orden ni convertir errores en negativos. Versión Flutter0.9.1+14. Para builds locales por ABI usar --split-per-abi --target-platform android-arm64 --android-project-arg=force-version-code-ignoring-abi=true (sin limitar arquitecturas en la configuración del proyecto). El benchmark se invoca expresamente mediante APK de instrumentación y localBenchmark=true, nunca mediante un endpoint de producción.
