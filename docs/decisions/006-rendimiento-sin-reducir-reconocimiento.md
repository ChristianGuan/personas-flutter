# ADR 006 — Reducir trabajo redundante manteniendo reconocimiento

El usuario pide acelerar el primer análisis y las búsquedas repetidas sin perder precisión. El recorrido anterior calcula todos los embeddings de cada foto y después pregunta si cualquiera coincide. Repite decodificación, detección y embeddings al cambiar la referencia, aunque las fotos sigan iguales.

Se conserva OpenCV 4.12.0 CPU FP32, dos hilos, YuNet/SFace y sus hashes, resize/orientación, ambas escalas, umbrales, NMS, alineación y coseno. La referencia continúa mostrando todos los candidatos. En búsqueda, después de completar las detecciones, se compara cada embedding y se termina cuando ya hay un match: la disyunción lógica no cambia al omitir las caras posteriores. Si no se encuentra coincidencia, se evalúan todas. Un fallo posterior en una cara que ya no necesita evaluarse tampoco impide aceptar una coincidencia válida anterior; no se finge haber inspeccionado las caras omitidas.

La caché RAM guarda todas las detecciones y embeddings parciales explícitos. Una referencia distinta puede necesitar caras aún no calculadas, que se alinean sobre los píxeles actuales. Clave por SHA-256 del BGR exacto usado por DNN, dimensiones/tipo/pipeline; siempre se relee/decodifica y se verifica acceso. No se confía sólo en URI/metadata ni se publica como negativa una entrada parcial. Una coincidencia anterior tampoco se trata como etiqueta para otra referencia.

Caché LRU limitada a 1024 imágenes y presupuesto de 20 MiB para detecciones/vectores (incluidos los pendientes). No guarda bitmaps, URI o nuevos datos en disco, y se limpia al borrar la sesión. No sustituye el índice persistente pendiente de R08/T12. El presupuesto de caché no es un límite del consumo total: bitmaps y OpenCV tienen su propio coste.

Se añade preparación IO mediante canal rendezvous: una inferencia nativa serial y como máximo actual+siguiente bitmap. Con imágenes actuales de más de 16 MiB se espera su liberación antes de preparar la siguiente. Cancelación libera elementos entregados/no entregados y los bitmaps cuyo resultado de decodificación se descarte. El orden del conjunto y el contador real se conservan. Reutilizar Mat de alineación/feature entre caras evita asignaciones por cara; la comprobación SHA de los modelos usa bloques de 64 KiB, evitando una asignación del tamaño completo de SFace al inicializar.

No se aplicó la propuesta de separar detectores por escala: la comparación host no mostró mejora. No se cambiaron a GPU/FP16, modelos más pequeños o umbrales menos exigentes. La ganancia inicial de parada temprana depende de grupos con una coincidencia; fotos con una sola cara o negativas siguen necesitando el trabajo nativo equivalente. Las búsquedas repetidas se benefician cuando sus entradas permanecen en la caché de la sesión. El hash y la preparación añaden un coste que debe medirse en Android.

`tools/benchmark_recognition.py` mide una reproducción host con recursos públicos, comparando decisiones y los vectores efectivamente calculados; no ejecuta el APK ni mide el teléfono. Las pruebas Android comparan el recorrido completo y el nuevo, cambios de referencia/contenido y cancelación con dos bitmaps. Resultados y disponibilidad del dispositivo se registran en docs/validation.md, sin afirmar tiempos ni equivalencia Android antes de ejecutarlas.

Fuentes primarias:

- https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.channels/-channel/
- https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.channels/-receive-channel/cancel.html
- https://github.com/opencv/opencv/blob/4.12.0/modules/java/generator/src/cpp/Mat.cpp
