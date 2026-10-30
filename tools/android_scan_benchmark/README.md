# Perfilado Android aislado

Herramienta de desarrollo, fuera de los módulos publicados. Genera el proyecto y los informes en `.tooling/android-scan-benchmark`, usa OpenCV 4.12.0 y los pesos originales, y elimina sus paquetes desechables al terminar. Nunca instala ni reemplaza `co.local.personas` o `co.local.personas.pruebas`. Se requiere un dispositivo ARM64 explícito, Android SDK 36, JDK 17 o compatible y las dependencias de Gradle del repositorio.

Preparar el conjunto público con `python3 tools/prepare_filter_qa.py --output /tmp/personas-filter-qa/android`. Crédito: AT&T Laboratories Cambridge; condiciones y alcance en [la base oficial](https://www.cl.cam.ac.uk/research/dtg/attarchive/facedatabase.html). No usar imágenes personales como fixture. Los ejemplos sólo se empaquetan en el APK de pruebas, nunca en Halladin.

```sh
python3 tools/android_scan_benchmark/run.py --fixture /tmp/personas-filter-qa/android/s01-01.png
python3 tools/android_scan_benchmark/run.py --fixture /tmp/personas-filter-qa/android/s01-01.png --device SERIAL --test PhotoReadOptimizationTest
python3 tools/android_scan_benchmark/run.py --fixture /tmp/personas-filter-qa/android/s01-01.png --device SERIAL --test FilteringRegressionTest
```

Sin `--device` sólo compila. Un benchmark que falla o se omite se trata como fallo, incluso si `am instrument` devuelve código de proceso cero. Los informes contienen tiempos, conteos y comparaciones numéricas; no exportan fotos, vectores, URI o IDs.

Pruebas disponibles:

- `PhotoReadOptimizationTest`: compara el lector anterior con el actual, píxeles/claves y tiempos sobre PNG pequeño y relleno superior a 12 MiB. No estima el tiempo del álbum ni de decodificar muchos megapíxeles.
- `FilteringRegressionTest`: prepara fixtures en caché privada y ejecuta los cuatro contratos originales de `FilteringTest`, incluido el de nueve caras. Exige los 400 PNG preparados.
- `DetectorThroughputTest`: compara uno/dos/cuatro hilos y dos detectores por escala. Exige igualdad exacta de salidas en la prueba pública.
- `MixedInferenceTest`: nombre histórico del experimento de reutilización por escala; compara el motor actual y `ScaleDetectorExperiment` en composiciones sintéticas de seis imágenes. El experimento conserva una copia del motor de ADR012 con la variante, exclusivamente para pruebas; no está conectado a producción.
- `OrtSfaceProbeTest`: añade **sólo al proyecto temporal** ONNX Runtime Android 1.31.1. Compara CPU, XNNPACK y NNAPI con el mismo recorte/pesos; informa diferencias numéricas y no afirma precisión de álbumes. NNAPI puede tardar mucho. Esta dependencia no entra en los builds de Halladin.

`LegacyContentPhotos` fija el lector de `745d350` para comparar antes/después. `ParallelPrepareSearch` es un experimento de dos preparaciones y tres slots que **no se adoptó**. Su orden se conserva y libera bitmaps bajo cancelación; no sustituye la planificación de producción.

## Muestra real, sólo bajo invocación explícita

```sh
python3 tools/android_scan_benchmark/run.py --fixture /tmp/personas-filter-qa/android/s01-01.png --device SERIAL --test AlbumReadProfile --allow-album
```

Este modo especial instala una instrumentación firmada con la clave local que apunta exclusivamente a `co.local.personas.pruebas`. Requiere esa variante de desarrollo con **R8 y resource shrinking desactivados**; una app minificada puede fallar por incompatibilidad de nombres/clases. No basta con el flag Flutter `--no-shrink` en el SDK usado: configurar `isMinifyEnabled = false` e `isShrinkResources = false` en el build de desarrollo. No aplicar esos cambios a la configuración publicada.

Requiere `android/key.properties` local y que la app esté firmada con esa misma clave. Las contraseñas se pasan con archivos temporales de permisos 600. Comprueba que no haya servicio de análisis en primer plano y que el snapshot esté inactivo. No ejecutarlo mientras el usuario esté usando la app: instrumentar reinicia su proceso y vacía su caché RAM, aunque conserva archivos/datos y resultados persistidos.

Lee sólo seis entradas espaciadas de la última selección ya autorizada y su referencia. Compara lector anterior, lector actual y preparación paralela experimental en dos órdenes alternados. No cambia fotos, resultados persistidos, consentimiento ni cola de analítica. Los tiempos del proveedor/SO no parten de caché vacía; sólo la caché de rostros se limpia en cada recorrido. No implica una evaluación de precisión con positivos familiares.

Decisión y resultados del 29-10-2026: [ADR013](../../docs/decisions/013-primer-escaneo-android-medido.md).
