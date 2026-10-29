# Android release con API de producción — 29-10-2026

Aplicación compilada desde el commit `f404690` con `--dart-define=ANALYTICS_API_URL=https://halladin.cloud`. Versión `0.9.2+15`, paquete `co.local.personas`, min SDK 28 y target/compile SDK 36. Los cambios posteriores de esta validación sólo añaden prueba y documentación; no modifican el código de la app compilada.

## Artefactos locales

- AAB firmado: `flutter_app/build/app/outputs/bundle/release/app-release.aab` (142,4 MB decimales).
- APK universal derivado de ese AAB mediante bundletool: `.tooling/production-release/halladin-production.apk`.
- SHA-256 AAB: `2f8f8d1729ad992a31d6fc19e1f3783051225e892c35754d1b6122c57702e3ad`.
- SHA-256 APK: `94c679b5b4b403e5667213a0a30b21809d490a1ba1b2309c06b839e9c6817751`.

Los binarios y evidencias locales permanecen fuera de Git. Se conserva la upload key existente. La firma del AAB se verificó con jarsigner; la del APK con apksigner y comparación del certificado contra el keystore local. La URL de producción está presente en el código Dart AOT del AAB. No se incluyeron credenciales administrativas ni PostgreSQL.

## Comprobaciones

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Sin incidencias |
| Suite Flutter con URL de producción | 69 pruebas aprobadas; smoke de producción omitido por defecto |
| Smoke HTTP opt-in contra producción | Registro, ACK, reenvío deduplicado y revocación aprobados; instalación sintética eliminada |
| `bundletool validate` | Aprobado |
| BundleConfig | `PAGE_ALIGNMENT_16K` |
| ELF64 del AAB y APK | 14 bibliotecas compatibles con 16 KB |
| `zipalign -c -P 16 -v 4` | Aprobado |
| Arranque del APK release | Aprobado en emulador API 36 con `PAGE_SIZE=16384` |

## Flujo real en el APK

Se utilizó `emulator-5556`, iniciado con `-read-only -no-snapshot`, sin modificar el teléfono físico conectado ni persistir las pruebas en la imagen original del emulador. Se limpiaron los datos de Halladin sólo en esa sesión temporal antes de instalar el APK.

1. Inicio sin consentimiento: `enabled=0`, sin UUID de instalación y cola vacía.
2. Se desactivaron Wi-Fi y datos del emulador; se aceptó analítica desde su interfaz. Se creó la credencial en almacenamiento seguro y quedó un evento de sesión pendiente.
3. Tras detener y abrir la app sin red, se conservaron el UUID y la cola; quedó un segundo evento de sesión pendiente.
4. Al recuperar conectividad, la cola pasó de dos eventos a cero por ACK de la API de producción.
5. Se revocó desde el interruptor. La interfaz confirmó el borrado; SQLite quedó con `enabled=0`, `installation_id=null`, `deletion_pending=0` y cola vacía. La instalación sintética quedó eliminada.
6. Con red y analítica desactivadas se completó una búsqueda local de una foto de prueba, con una coincidencia; también se denegó el permiso de notificaciones. Al terminar seguían sin UUID y con cola vacía.

La referencia es una imagen pública de los fixtures de OpenCV, procedente de `samples/data/lena.jpg`, utilizada sólo dentro del emulador. No se enviaron fotografías ni nombres ni rutas a la API. El smoke HTTP usó únicamente un evento sintético de sesión; la prueba del APK generó sesiones del entorno de pruebas y confirmó su eliminación.

Esta evidencia cubre el escenario descrito. No sustituye pruebas en otros dispositivos, formatos y versiones, ni implica publicación o aprobación de Google Play. No se realizó carga a Play Console. Para pruebas internas se debe usar el AAB firmado, conservando y respaldando la upload key.
