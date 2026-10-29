# Evidencia Android del 28-10-2026

- `compileSdk=36`, `targetSdk=36`, `minSdk=28`.
- AAB release generado correctamente con Flutter; validado por bundletool oficial 1.18.3.
- BundleConfig: `PAGE_ALIGNMENT_16K`.
- Firma JAR del AAB verificada y comparada con la upload key local.
- SHA-256 público del certificado de upload: `c0e32c9d006af4c933853fb9fa70185a5057d4242389f9572db744b8f0e55780`.
- AAB SHA-256: `5afec398d90878b0bbbddddb6475d967fbb77ac9b81bbadbc50185159d8b02ff`.
- APK universal generado desde ese AAB con el mismo certificado; apksigner y zipalign 16 KB aprobados.
- Las 14 librerías ELF64 del AAB y del APK cumplen la comprobación estática de segmentos y empaquetado. No se encontró una dependencia nativa de 64 bits que requiriera reemplazo por alineación.
- 55 pruebas Flutter, 6 instrumentadas Android y 3 del verificador estático aprobadas.
- Prueba negativa: release sin `key.properties` falla con el error esperado; configuración restaurada. No hay fallback a firma debug.
- Teléfono de prueba: CPH2637, Android API 36, páginas **4096 bytes**.

**Actualización:** ejecución en emulador oficial API 36 con páginas de 16384 bytes aprobada el 28-10-2026: arranque y búsqueda release, más 6 pruebas nativas con harness debug. Ver el reporte de emulador. Quedan el respaldo cifrado de la clave por el titular, su registro en Play App Signing, una URL de API definitiva y las pruebas completas de permisos/fondo de la candidata de tienda.

## Archivos locales de comprobación

- AAB: `flutter_app/build/app/outputs/bundle/release/app-release.aab`.
- Reporte completo: `flutter_app/build/android-release-readiness.json`.
- APK universal: `.tooling/release-checks/universal.apk`.
- Logs de compilación y verificación: `.tooling/` y `.tooling/release-checks/`.
- Material de firma: `.tooling/signing/personas-upload.jks` y `flutter_app/android/key.properties`, ambos con permisos 600 e ignorados por Git. Las contraseñas no se imprimieron.

El AAB sigue siendo una build técnica de preparación: no se ha subido a ninguna tienda, registrado la clave con Google ni cambiado versión/identificadores o URL hacia un dominio productivo. No instalar el APK release encima del debug sin decidir cómo preservar datos; usan certificados diferentes.

## Incidencias del entorno resueltas

La compilación inicial se quedó sin espacio. Se eliminaron solo los artefactos regenerables del `flutter_app/build` histórico, conservando fuentes y claves. Se reinició el daemon/caché local de Gradle afectado. Después se instaló el paquete oficial de command-line tools de Android (checksum verificado), porque faltaba apkanalyzer para la comprobación final de Flutter. El build final terminó con código 0.

No se actualizaron Gradle/AGP/Kotlin en esta tarea: la toolchain actual compila, aunque Flutter avisa de soporte futuro. Esas advertencias no se han ocultado ni se presentan como resueltas.

Ver [detalle y evidencia del emulador de 16 KB](android-emulator-16kb-2026-10-28.md).
