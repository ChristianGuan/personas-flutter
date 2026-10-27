# 004 — Primera búsqueda Android

## Problema y alcance
Analítica v2 muestra Android209fotos/678.758s frente iOS203/71.533s; referencias/conjuntos pueden diferir. No afirmar causalidad por CPU ni usar la segunda búsqueda con caché como prueba de mejora fría. Android está instalado debug, iOS Release, diferencia a considerar. El motor se inicializa durante referencia, antes de búsqueda. Pipeline actual decodifica sRGB ARGB8888 máximo3200, YuNet full+960, SFaceFP32, dos hilos, inferencia serial y caché RAM. Bitmaps>16MiB bloquean preparación siguiente.

## Requisitos
Medir primero sobre el teléfono y mismas entradas/referencia. Mantener modelos/hashes, umbrales, escalas, orientación, mínimo de cara, fusión NMS y decisiones; no aceptar una mejora basada en reducir detección de caras pequeñas. No subir fotos, embeddings, URI/IDs/álbumes/EXIF ni perfiles personales. Benchmarks opcionales de instrumentación leen sólo localmente el último conjunto autorizado, no modifican originales ni selección/snapshots y sólo exportan contadores/tiempos agregados. No activar analítica, no alterar consentimiento ni API. No ejecutar si hay búsqueda activa.

## Plan de medida
Añadir contadores nativos opcionales (no logging de producción) para conversión, detección por escala y embeddings. Medir preparación/decodificación mediante PhotoSource wrapper y duración de lote. Comparar presupuestos de CPU intercalados con caché de resultados vacía; referencia/modelos precargados como en uso real. Comparar resultados por foto en memoria, exportar únicamente igualdad y contadores. Variaciones de IO/térmica/OS deben declararse. La instrumentación no incorpora fotografías al repositorio ni al APK.

## Criterios de aceptación
Optimización elegida mediante evidencia, con un recorrido frío medido antes/después y repetición intercalada cuando sea razonable; mantener las mismas decisiones en entradas emparejadas. Regresiones de cancelación/reciclaje y caché; compilar Flutter/Android y actualizar sólo cuando no haya análisis activo. Registrar límites del tamaño de muestra; no prometer un multiplicador universal. Si el cuello depende de proveedores/HEIC, mejorar esa etapa conservando píxeles y fallback; si es inferencia, probar presupuesto de CPU y paralelismo acotado antes de cambiar política.

## Decisión medida
Muestra6 de209 fotos del último conjunto autorizado, dos órdenes intercalados, caché nativa vacía cada vez: 2hilos/16MiB=16004/15721ms; 2hilos/32MiB=11890/12138ms; 4hilos/32MiB=12281/12455ms. Cero hits de caché y cero ilegibles;13embeddings y mismas decisiones por foto en las seis ejecuciones. La muestra no produjo coincidencias fuertes; no es evaluación de precisión ni benchmark de todo el álbum. Preparación9.1–9.3s en baseline explica gran parte de demora; ambos pasos de detección mantienen coste equivalente. Se elige conservar2hilos y habilitar umbral actual<=min(32MiB,maxHeap/8), limitado16MiB en dispositivos low-RAM o sistema con poca memoria.

El canal sigue rendezvous: como máximo dos imágenes preparadas, inferencia nativa serial. Si la actual excede umbral o es snapshot diferido, espera liberación. El límite no es memoria total: siguiente bitmap puede ocupar hasta3200x3200x4 más conversiones transitorias y Mat/DNN. No anunciar64MiB como límite RSS. Mantener en cuenta presión de memoria del sistema al iniciar búsqueda. La lectura de modelo y matching no cambian; no se reduce preparación moviéndola antes del contador.
