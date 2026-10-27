# Tareas

La migración R21/V17 se sigue en [002-flutter-migration/tasks.md](../002-flutter-migration/tasks.md). Los pendientes de aceptación con fotos personales, nube real e índice persistente de esta lista se conservan.

Estados: [x] implementado/documentado; [ ] pendiente. Implementación no implica aceptación manual.

- [x] T01 Inspección de carpeta, instrucciones y entorno. Sin AGENTS.md ni base previa.
- [x] T02 Especificación y decisiones trazables R01–R11.
- [x] T03 Comparar modelos y motores; licencias de pesos; descargar fuentes oficiales y verificar SHA-256 (R04,R09).
- [x] T04 Proyecto Kotlin/Compose, dependencias fijas y Wrapper.
- [x] T05 Referencia y conjunto pequeño con Photo Picker; seleccionar cara tocando (R01–R03).
- [x] T06 Pipeline YuNet/SFace real, comparación y resultados sin duplicados (R04,R05).
- [x] T07 Progreso/tiempo, errores parciales y cancelación (R06).
- [x] T08 Cuadrícula, ampliación, selección y compartir nativo (R07); aceptación V04 pendiente.
- [x] T09 Pruebas unitarias de coseno, grupo y selección compartida.
- [ ] T10 Validar en Android real: V01–V04,V07, medir inferencia y calibrar con álbum etiquetado. Instalación e inicio en CPH2637/API 36 comprobados; pendiente selección de fotos y evaluación manual.
- [x] T11 Álbumes MediaStore implementados en T21/R14; prueba de aislamiento de bucket real aprobada. Aceptación de permisos reales V06 pendiente en T24.
- [ ] T12 Índice Room transaccional, reutilización/invalidation/purga/borrado; V05 y tests. Depende T10,T11.
- [ ] T13 Medir memoria, caras pequeñas y lotes grandes; ajustar muestreo/mosaicos según resultados T10.
- [ ] T14 Aceptación integral MVP y revisar distribución comercial/avisos de todas las dependencias.

Siguiente: T10. No presentar T11/T12 como existentes: esta entrega es el incremento técnico inicial solicitado.

- [x] T15 (R03,R12) Eliminar tope de 30, añadir tandas deduplicadas y selector alternativo de Archivos; vaciar conjunto conservando referencia.
- [x] T16 (R07,R12) Reorganizar UI en pasos, tema claro/oscuro, acciones inferiores persistentes, cuadrícula única, selección accesible de rostro, deselección y miniaturas con concurrencia limitada.
- [ ] T17 (V08) Validar selección >30 con fotos reales, acumulación/cancelación, texto ampliado y búsqueda larga en Android. No se sustituyen fotos del usuario por resultados simulados.

- [x] T18 (R13) Añadir diagnóstico por foto y revisión ampliada de descartadas; proteger selección compartida contra URIs fuera de resultados. Compilación/pruebas/lint correctos.
- [ ] T19 (V09,T10) Repetir prueba reportada de 11 fotos/6 resultados y determinar etapa del fallo antes de ajustar detector o reconocimiento. Incluir negativos para calibración posterior.

- [x] T20 (R14) Tema índigo centralizado y componentes; navegación por cinco pasos con transiciones finitas.
- [x] T21 (R03,R10,R14) Álbumes MediaStore reales, permiso opcional completo/limitado/denegado/revocado y alternativa individual.
- [x] T22 (R06,R07,R13,R14) Contexto con recorte elegido; progreso real; resultados/descartadas; revisión completa y barra de compartir.
- [x] T23 (V10) Compilar, pruebas/lint y revisión en dispositivo: pantallas vacías, tamaño pequeño, texto grande, oscuro y animación desactivada; registrar límites.

- [ ] T24 (V06,V10) Aceptación manual en galería autorizada, permisos reales completo/limitado/revocado/denegado permanente, TalkBack, recepción compartida en otra app y cancelación de álbum grande. No se considera cubierta por estados de presentación de tests.

T20–T23: APK compilado, 8 pruebas JVM y 10 instrumentadas aprobadas en CPH2637/API 36; capturas revisadas, incluyendo fuente 200%/320×480 dp y oscuro. Modelos y umbrales sin cambios. Siguientes: T24 para aceptación UI/galería real y T19 para el diagnóstico de las cinco fotos ausentes.

- [x] T25 (R15,V11) Selector con miniaturas lazy sin tope de tres, selección táctil de cajas superpuestas y detección multiescala con deduplicación.
- [x] T26 (V11) Compilar y probar nueve rostros con inferencia real; seleccionar 4/9 por miniaturas y 7 sobre imagen; instalar corrección. Repetición con foto original del usuario pendiente.

- [ ] T27 (R15) Repetir con la referencia original que sólo mostraba tres recuadros; registrar cuántas caras utilizables aparecen con 0.2.1. No confundir la prueba de nueve copias públicas con una evaluación de precisión en grupos reales.

T25/T26: 10 pruebas JVM y 11 instrumentadas aprobadas, 0 errores de lint; 0.2.1 instalada. Detección de referencia ajustada a 0.65 con confirmación visual; análisis del conjunto sigue en 0.85 y reconocimiento en 0.363.

- [x] T28 (R16) Reproducir búsqueda con fotos distintas de la misma persona y negativos; verificar preprocesamiento oficial.
- [x] T29 (R16) Referencias complementarias confirmadas, preservación transaccional al fallar/cancelar y repetición sobre el mismo conjunto.
- [x] T30 (V12) Tests unitarios/instrumentados con cambios de pose/iluminación, negativos y flujo de descartada; compilar e instalar. Registrar límites de la evaluación pública y validación pendiente con álbum del usuario.

- [ ] T31 (R16,V12) Repetir con el álbum del usuario y referencias confirmadas de distintas poses; medir precisión/recuperación con negativos suficientes. La regresión pública dirigida no completa la evaluación real.

T28–T30: 12 tests JVM y 14 instrumentados aprobados en API 36; detección y coseno sin rebaja. Prueba de pose/iluminación: 5/11 positivos con una referencia y 11/11 con dos, ambos con 0/2 negativos aceptados; alcance limitado a una secuencia y dos identidades negativas, no generalizable.

- [x] T32 (R17) Acceso visible a Google Fotos, guía y ajustes del proveedor; conservar selección/alternativa Archivos.
- [x] T33 (R17) Recepción de imágenes compartidas, validación IO y confirmación sin perder referencia/conjunto ni modificar análisis activo.
- [x] T34 (V13) Compilar, lint, pruebas de importación y UI; instalar y comprobar apertura real del selector/ajustes; registrar límites cloud.
- [ ] T35 (V13) Seleccionar imágenes que sólo existan en Google Fotos con la cuenta configurada por el usuario; comprobar descarga, búsqueda y recepción compartida desde ese proveedor.

T32–T34: 0.4.0 instalada; 12 pruebas JVM y suite completa de 20 instrumentadas aprobadas (49.277 s). Comprobación adicional del diálogo con font_scale real 2.0 y límite 320×480 dp aprobada; ajuste original restaurado. Lint: 0 errores y 14 advertencias. No se habilitó/cambió la cuenta de nube ni se dio por aprobada una descarga desde Google Fotos: pendiente T35.

- [x] T36 (R18) Perfilado y búsqueda con parada tras primera coincidencia, conservando detección y evaluación completa de negativos.
- [x] T37 (R18) Caché RAM por contenido BGR y pipeline, LRU acotada, embeddings parciales explícitos y limpieza con la sesión.
- [x] T38 (R18) Decodificación anticipada acotada, una sola inferencia, cancelación/liberación y progreso por foto.
- [x] T39 (V14) Compilar/lint/tests y comparar decisiones, cold/warm, cambio de referencia/contenido, errores y cancelación; registrar equipo/alcance y disponibilidad de dispositivo.

Estado inicial R18 sin dispositivo: APK 0.5.0 y androidTest compilados, 17 tests JVM aprobados, lint 0 errores/14 advertencias, hashes de modelos correctos. Comparación host de decisiones/vectores aprobada, incluidos cambios de referencia; no mide Android. En ese momento T39 estaba pendiente de ejecución instrumentada/medición e instalación. No se heredó la aprobación de 20 tests de 0.4.0 a esta versión.

Actualización T39 al conectar el teléfono: 0.5.0 instalada en CPH2637/API 36; suite completa **OK (23 tests)**, 67.587 s. Mismos outcomes del recorrido completo en los 16 casos públicos de la comparación. Medianas de tres recorridos en Android: completo 2008 ms, primero optimizado 1506 ms, repetido 180 ms. Referencia distinta, cambio de píxeles/URI/dimensiones, error intermedio y cancelación con dos bitmaps comprobados. Medición de memoria y aceptación con álbum real siguen en T13/T10/T31; no se generalizan estos tiempos a todos los álbumes.

- [x] T40 (R19) Reproducir falsos positivos en QA público con separación de sujetos y elegir política estricta por calibración; registrar recuperación y pendientes.
- [x] T41 (R19) MATCH/REVIEW/NONE, normalización preparada exacta, confirmación/descarte manual y protección de compartir.
- [x] T42 (R19) Alias por bytes completos, preparación acotada y fallback exacto sin saltarse cambios de contenido/permisos.
- [x] T43 (V15) Pruebas JVM/Android, regresión de negativos reales, EXIF/contenido/caché parcial, UI revisión y medición de tiempos; instalar y documentar límites.

Cierre T40–T43: 0.6.0 instalada, 19 tests JVM, suite final de 29 tests Android aprobada (101.895 s), perfilado adicional de hilos aprobado y 2 checks de diálogos con fuente real 200% (4.298 s); lint 0 errores/14 advertencias existentes. Calibración/evaluación con 20+20 sujetos públicos, política >=0.50 automática y [0.363,0.50) revisable. Con una referencia: calibración FP 10→0, evaluación 177 TP/0 FP y 3 positivos pendientes; con 2/4 refs 160/120 TP y cero FP en evaluación. No se generaliza a familias. Dos ejecuciones de rendimiento en 16 entradas conservaron todos los outcomes; repetidas medianas 164/110 ms, primer recorrido 1576/1946 ms frente a completo 2146/1711: no hay mejora estable demostrada del primer recorrido. 2 hilos fue más rápido que 1/4 en perfilado, se mantiene. Ver validación y ADR 007. T10/T31 (álbum real), T13 (memoria/grandes conjuntos), T35 (nube real) y T12 (índice persistente) siguen pendientes.

- [x] T44 (R20) Lectura software sRGB ARGB_8888, fallback HEVC local y orientación; liberar intermediarios y versionar caché/pipeline.
- [x] T45 (R20) Error de lectura específico, preservar referencias previas y UNREADABLE en lote sin cambiar precisión/permisos.
- [x] T46 (V16) HEIC reales 8/10 bits/P3 y ocho orientaciones fuera del APK; pruebas F16, referencia/batch/preview/caché, JPEG/PNG y parser acotado.
- [x] T47 (V16) Compilar/lint/tests, ejecutar Android e instalar; documentar límites y comprobaciones pendientes.

Cierre técnico R20: 0.6.1 instalada en CPH2637/API 36; 22 tests JVM aprobados y lint 0 errores/14 advertencias. Siete tests HEIC aprobados en emulador ARM64/API 35, incluidas ocho orientaciones sobre imagen no cuadrada, error parcial, referencia, búsqueda, caché y ampliación. En teléfono pasaron los seis tests de datos/inferencia; el test de ampliación necesitó corregir su desplazamiento y pasó después en emulador. Regresión general del emulador: 35/36 iniciales y caso de álbum restante aprobado al conceder su permiso previo; ajustes cloud no existen en ATD y se excluyeron. La reinstalación para repetir la suite completa del teléfono quedó esperando desbloqueo/instalador del fabricante; no se afirma aprobación de esa suite. Ver docs/validation.md.

- [x] T48 (V16) Completar la regresión y revisión visual en teléfono desbloqueado: 36/37 casos iniciales y caso HEIC UI restante aprobado al esperar miniatura por clave estable; ver validación.
- [ ] T49 (V16) Probar los HEIC concretos descargados por el usuario. No sustituir esta aceptación por los fixtures públicos.

Actualización tras desbloqueo: 37 casos distintos comprobados en CPH2637/API 36, distribuidos en suite inicial (36 aprobados de 37; 131.227 s) y repetición del único test pendiente (OK, 7.231 s). El ajuste fue exclusivamente del test: desplazar al ítem lazy por su clave y esperar la imagen real antes de tocarla. Revisadas capturas HEIC ampliado, oscuro y texto 200%/pantalla pequeña en el teléfono. App de producción 0.6.1 sin cambios; ajustes temporales restaurados. Pendiente sólo T49 dentro de la aceptación HEIC.
