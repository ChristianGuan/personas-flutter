# ADR 008 — Lectura HEIC/HEIF y formato de píxel

Estado: implementado en 0.6.1; ejecución y límites en [validación](../validation.md).

## Problema observado

Los archivos aparecen en el selector y fallan al abrirse para referencia y conjunto. ALLOCATOR_SOFTWARE no garantiza ARGB_8888: OpenCV bitmapToMat rechaza RGBA_F16. Además, pruebas con HEIC reales de 10 bits fueron rechazadas por ImageDecoder en emulador y teléfono. El teléfono puede lanzar IOException genérico desde getPixels, además de DecodeException. Convertir el bitmap después no resuelve ese rechazo.

Los archivos concretos del usuario no fueron proporcionados. La regresión pública reproduce fallos de esta ruta compartida, sin atribuir a todo HEIF una causa única. No se cambian MIME ni permisos.

## Decisión

1. ImageDecoder primero, software, sRGB y tamaño máximo existente (3200 para reconocimiento). Conservar su orientación y el contrato común para URI/snapshot.
2. `softwareSrgb8888`: reutilizar bitmap ya ARGB_8888/sRGB; convertir F16/P3 dibujando sobre destino sRGB de 8 bits y reciclar la fuente. Copiar sólo configuración puede conservar P3.
3. Ante IOException, intentar exclusivamente contenedores HEIF con `io.github.awxkee:avif-coder:3.0.0:release@aar` local. Sin red, recompresión, fotos convertidas persistidas ni modificación de originales. Referencia, miniaturas, batch y ampliación comparten ContentPhotos.
4. Entrada alternativa limitada a 64 MiB y dimensiones positivas de hasta 100 millones de píxeles; un fallback simultáneo en IO. Reciclar salidas/intermedios abandonados por error/cancelación. El codec puede decodificar antes de reducir: estos límites no garantizan un pico pequeño de memoria y no sustituyen T13.
5. Versionar caché/pipeline. Conservar modelos, FP32, escalas, umbrales, selección y compartir de originales.
6. Si fallan ambos lectores, PhotoDecodeException y mensaje de lectura específico, conservando referencias previas. En lote sigue siendo UNREADABLE, nunca un negativo de identidad.

Compile SDK 36 requerido por el AAR; min SDK 28 y target SDK 35 se conservan. La dependencia de lectura se añade ante rechazo nativo comprobado; no hay dependencias visuales nuevas. Release AAR SHA-256 `799f8b5babbcaa1b3d6d0987e9c87afaa4a331c0afaf00a91a4dbabdf371c06f`, fuente tag 3.0.0/commit `ec76e60f5b17b275402adece11bdb6a827335634`.

## Orientación del codec fijado

En 3.0.0 `avifpixart/src/orientation.rs` agrupa píxeles de tres canales aunque HEIC entrega RGBA; giros provocan una longitud de buffer incorrecta. No basta con abrir el archivo para dar por correcta su orientación.

`HeifOrientation` valida cajas ISO-BMFF y retira sólo asociaciones irot/imir de la imagen primaria en copia RAM. Índice cero significa ausencia de propiedad; tamaños, offsets, datos de imagen, crop, color y asociaciones de otros ítems permanecen. Matrix aplica las transformaciones después de decodificar, en orden, sin interpolación adicional. imir=1 refleja izquierda/derecha, imir=0 arriba/abajo. No se cambia EXIF por heurísticas ni se toca el archivo original.

Admite asociaciones v0 con IDs de 16 bits e índices de 7 bits que interpreta el codec HEVC fijado. Rechaza versiones/anchos no admitidos, índices, longitudes y bits reservados inválidos. Retirar al actualizar a un codec que supere la regresión de ocho orientaciones RGBA. Tests JVM comprueban alcance primario, bytes intactos, ausencia de copias innecesarias y rechazo de datos inválidos.

## Dependencias y avisos

El AAR incluye cuatro ABIs, pero su lector HEVC alternativo se compila para ARM/ARM64; x86 depende de Android. Avisos e inventario en `app/src/main/assets/licenses/heic/THIRD_PARTY_NOTICES.txt` y `components.json`: fuentes MIT/BSD/Apache, Cargo.lock oficial y checksums de archivos de crates, archivos BSD del decoder, libavif, dav1d y libyuv. El inventario incluye componentes de compilación/plataforma y no afirma que todos estén en cada ABI. Revisión general de distribución comercial pendiente T14.

## Reproducción y límites

`tools/prepare_heic_qa.py` usa Pillow 11.3.0, pillow-heif 1.1.1 y numpy sólo en desarrollo. Muestra pública OpenCV fijada por SHA-256, sin fotos del usuario. Genera HEIC reales sRGB/P3 de 8/10 bits, giros/espejos, ocho orientaciones de imagen no cuadrada, imagen plana y copia truncada; reabre para verificar profundidad y guarda manifest/hashes fuera de APK/Git. P3 se transforma con el perfil ColorSync de macOS, no sólo se etiqueta.

```sh
/tmp/personas-model-check/bin/python tools/prepare_heic_qa.py \
  --source /tmp/personas-smoke-lena.jpg --output /tmp/personas-heic-qa
```

`HeicPhotoTest`/`HeicUiTest` requieren `heicFixtures=qa-heic` con las muestras en caché privada. Cubren URI/snapshot, igualdad JPEG/PNG anterior, F16/P3, ocho orientaciones, inferencia real, caché repetida, preview, error parcial y preservación de referencia. Sin fixtures se omiten sólo los métodos que los necesitan; no se simula reconocimiento.

Tras compilar ambos APK, `tools/run_heic_qa.py --serial ID_ADB --fixtures /tmp/personas-heic-qa --adb /ruta/platform-tools/adb` los instala, valida hashes del QA público, carga sólo esas muestras, ejecuta siete pruebas y recupera captura/métricas a /tmp. Restaura las escalas de animación originales incluso si falla. El teléfono debe estar desbloqueado y autorizar cualquier diálogo de instalación propio del fabricante.

No se promete soporte universal para HEIF, HDR auxiliar, 12 bits, archivos truncados, imágenes enormes o proveedores que impidan leer bytes. El reconocimiento usa sRGB de 8 bits; los originales conservan formato/color para compartir. Pendiente probar los HEIC concretos descargados por el usuario.

## Fuentes primarias

- [ImageDecoder](https://developer.android.com/reference/android/graphics/ImageDecoder).
- [OpenCV 4.12 bitmapToMat](https://github.com/opencv/opencv/blob/4.12.0/modules/java/generator/src/cpp/utils.cpp).
- [Codec 3.0.0](https://github.com/awxkee/avif-coder/tree/3.0.0).
- [Orientación de la versión fijada](https://github.com/awxkee/avif-coder/blob/ec76e60f5b17b275402adece11bdb6a827335634/avifpixart/src/orientation.rs).
- [libheif: interpretación de imir](https://github.com/strukturag/libheif/blob/v1.20.2/libheif/box.cc).
- [pillow-heif: guardado de 10 bits](https://pillow-heif.readthedocs.io/en/latest/saving-images.html).
