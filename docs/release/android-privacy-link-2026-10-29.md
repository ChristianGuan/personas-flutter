# Android 0.9.2+16: enlace de privacidad

Preparada el 29-10-2026 para pruebas internas de Google Play. Se conserva `versionName=0.9.2` y se incrementa `versionCode` de 15 a 16 para distinguir el nuevo artefacto.

El panel «Ayúdanos a mejorar» de Inicio y el diálogo «Analítica» incluyen **Política de privacidad**, antes del interruptor de consentimiento. El botón abre `https://halladin.cloud/privacidad` en el navegador del sistema mediante el puente nativo existente de Android/iOS. No requiere activar analítica, ni incorpora SDKs o WebView. Si el navegador no está disponible, se muestra la URL sin bloquear la búsqueda.

## Artefactos

Compilación desde la raíz:

```sh
./tools/flutter.sh build appbundle --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

- AAB para Play: `flutter_app/build/app/outputs/bundle/release/app-release.aab`.
- APK universal derivado del mismo AAB: `.tooling/privacy-link-release/halladin-0.9.2-16.apk`.
- SHA-256 AAB: `54aace59465003dd2054677a54dd33695c33c3cf85e8e322a25ffaaad1e06330`.
- SHA-256 APK: `59acf233bf50875bdca82b2a8e364059436bc1c0bfffdb4b632f52e5a0077ac6`.

Ambos artefactos están firmados con la upload key existente, cuyo certificado se comparó con la firma del APK. Los binarios, secretos y evidencias operativas permanecen fuera de Git.

## Validación

- Análisis estático: sin incidencias.
- Suite Flutter: 71 pruebas aprobadas; smoke de producción omitido por defecto.
- Nuevas pruebas: abrir privacidad sin consentimiento y manejar la ausencia de navegador mostrando la URL.
- Sintaxis Swift: `swiftc -frontend -parse` aprobada; no se realizó compilación ni ejecución iOS en esta entrega.
- Bundletool: validación y manifiesto aprobados; `versionCode=16`, target SDK 36 y `PAGE_ALIGNMENT_16K`.
- Firma AAB y APK verificadas; `zipalign -P 16` y comprobación de las 14 bibliotecas ELF64 aprobadas.
- APK release instalado y arrancado en emulador API 36 con páginas de 16384 bytes. Se utilizó una sesión temporal `-read-only -no-snapshot`, sin modificar el teléfono conectado ni la imagen original del emulador.
- El botón abre el navegador con la URL pública. El estado de analítica, antes y después de abrirla, permanece desactivado, sin UUID de instalación y con cola vacía. No se activó analítica ni se crearon eventos en producción durante esta prueba.

Las declaraciones de Seguridad de los datos revisadas con el titular mantienen interacciones, otras acciones, diagnósticos, rendimiento y UUID de instalación: recogida opcional para análisis. No hay cambios en los eventos ni en sus finalidades.

No se ha subido esta versión a Play Console. El AAB queda disponible para cargar en pruebas internas y comprobar la instalación distribuida por Google Play. Esta entrega no implica aprobación de la tienda ni una validación exhaustiva en todos los dispositivos.
