# ADR 009 — Flutter con reconocimiento nativo

Estado: implementado en el incremento R21 (0.7.0+9). La evidencia de ejecución se registra en `docs/validation.md`.

## Decisión

Compartir interfaz, navegación, selección, decisiones manuales y estado de sesión en Dart/Flutter. Integrar fotografías y reconocimiento mediante canales de plataforma. No sustituir SFace/YuNet por un plugin con otro preprocesamiento o criterio de identidad.

`flutter_app/` es la aplicación nueva; el proyecto Android raíz se conserva como referencia y fuente única de `data/`, `domain/`, modelos, recursos y avisos HEIC. La nueva actividad Android usa Flutter y no carga Compose. Mantiene `co.local.personas` para actualizar la instalación anterior; requiere la misma firma. iOS usa el mismo identificador de producto, con extensión `co.local.personas.share`.

Flutter 3.47.7/Dart 3.13.5, obtenido de la distribución estable oficial con SHA-256 fijado en `tools/setup_flutter.py`. Dependencias Dart de producción: SDK Flutter y localizaciones SDK; no nuevas dependencias visuales o de reconocimiento. El lockfile queda versionado. Herramientas y binarios regenerables viven en `.tooling/`, ignorado. Android mínimo 28, compile 36, target 35; iOS mínimo 16.

## Contrato entre plataformas

MethodChannel `co.local.personas/photos`: `initialize`, `pick`, `albums`, `requestAccess`, `albumPhotos`, `reference`, `releaseReference`, `image`, `search`, `cancel`, `clear`, `share`, `settings`, `cloudSettings`. EventChannel `co.local.personas/events`: `photo`, `done`, `incoming`.

Los handles de rostro identifican embeddings guardados únicamente en RAM nativa. Dart recibe cajas normalizadas e identificadores; no vectores. `search` confirma el inicio y emite un evento por foto, con `runId`, resultado y clave de contenido. El controlador descarta generaciones viejas, fotos ajenas al conjunto y duplicados. Sólo `done` termina una cancelación. Un fallo de lectura/inferencia produce `unreadable`; nunca se convierte en negativo de identidad.

Las decisiones manuales se limitan a la misma persona y contenido. Sólo resultados aceptados pueden seleccionarse y compartirse. Los casos dudosos requieren confirmación explícita. La similitud no se presenta como certeza. Cambiar de persona o borrar sesión elimina el feedback. La sesión continúa sin índice/historial persistente.

Android envuelve directamente `ContentPhotos`, `OpenCvFaces` y `BatchPhotoSearch`. Conserva inferencia serial, preparación anticipada acotada, validación de acceso/bytes, caché parcial y fallback HEIC de R20. No hay un nuevo motor Android paralelo.

iOS usa Swift (PhotoKit, PHPicker, documentos, ImageIO, compartir) y Objective-C++ (OpenCV 4.12). Imagen orientada, sRGB RGBA8 hasta 3200 px; conversión BGR, YuNet multiescala, mínimo 24 px/NMS 0,4, alineación de cinco puntos y SFace FP32. Referencia 0,65, análisis 0,85, coincidencia ≥0,50, revisión desde 0,363; normalización L2 y producto escalar equivalentes al contrato Android. No se afirma igualdad de precisión entre dispositivos sólo por conservar pesos y umbrales: los decodificadores y kernels son diferentes y necesitan evaluación real.

Cola de inferencia serial/dos hilos OpenCV; caché iOS RAM 1024 entradas/20 MiB, reserva por rostros y embeddings faltantes explícitos. Una coincidencia fuerte permite parar; una foto negativa compara todas las caras. Las repeticiones vuelven a leer bytes autorizados y usan SHA-256 antes de reutilizar resultados. Las miniaturas/vistas viajan como JPEG de visualización, máximo dos solicitudes simultáneas y 1600 px; no se usan para inferencia ni para compartir.

## Fotografías, nube y originales

Los álbumes requieren permiso opcional completo/limitado; los selectores individuales y Archivos siguen disponibles sin acceso global. Se revalida un álbum al volver a primer plano y se eliminan selección/resultados si pierde acceso. No existe un tope total de 30 fotos impuesto por Dart. Las referencias adicionales son transaccionales y conservan la anterior si falla el archivo o no hay rostro.

Android conserva URIs/grants y comparte originales con ClipData. Google Fotos depende del proveedor cloud del Photo Picker o de Compartir → Personas; Drive depende del proveedor de Archivos. No se enumeran bibliotecas cloud mediante una cuenta propia.

iOS usa PHPicker/iCloud Fotos; documentos con acceso de seguridad y copia temporal del original sin recomprimir. Se identifican copias idénticas por SHA-256 para evitar duplicarlas al volver a elegirlas. ImageIO admite las variantes HEIC que pueda decodificar el sistema, con límite de 64 MiB/100 Mpx declarados; no es compatibilidad universal. Al compartir se exportan bytes originales, con extensión del tipo detectado. Google Fotos puede enviar fotos a la extensión de compartir; ésta guarda originales en el App Group y pide abrir Personas para confirmar su incorporación. No se inicia una búsqueda ni se cambia la referencia automáticamente.

Para recibir desde otras apps, Runner y PersonasShare requieren el mismo App Group registrado y firma/capacidad de Apple adecuadas. El grupo por defecto `group.co.local.personas` debe personalizarse junto con los identificadores si no pertenece al equipo de firma. No se requiere cuenta propia de Personas. Credenciales y fotos no forman parte del repositorio.

## OpenCV iOS reproducible

Dispositivo: artefacto oficial 4.12.0 de GitHub, SHA-256 `86b42c9f141cd9169b91be2fc380b0e556a88a95c98ccc8e7aef8349ab74cf70`, recortado a ARM64 con `lipo`. El artefacto original mezcla arquitecturas antiguas y no contiene ARM64 de simulador; no puede usarse como si fuera esa plataforma.

Simulador ARM64: código de la etiqueta 4.12.0, commit `49486f61fb25722cbcf586b7f4320921d46fb38e`, archivo fuente SHA-256 `44c106d5bb47efec04e531fd93008b3fcd1d27138985c5baf4eafac0e1ec9e9d`. Constructor iOS oficial con CMake 3.31.10, Release, sin bitcode ni wrappers Swift/ObjC ni módulos visuales/codec innecesarios, tres procesos de compilación. `xcodebuild -create-xcframework` agrupa plataformas reales; nunca se altera la plataforma Mach-O. Licencias y manifiesto de privacidad incluidos en recursos de Runner.

## Límites

La migración no promete acelerar inferencia ni mejorar precisión. Falta medir con álbumes familiares y HEIC del usuario; se conserva esa deuda de evaluación. La descarga de proveedores depende de red/disponibilidad. No hay backend, subida de imágenes ni analítica. Instalación en un iPhone físico, distribución y App Group dependen de la firma y del dispositivo del usuario. No se publica automáticamente en tiendas.
