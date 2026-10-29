# Prueba real en emulador Android de 16 KB

Fecha: 28-10-2026. AVD persistente: **Personas_API36_16KB** (perfil Pixel 7).

## Entorno verificado

- Imagen oficial: `system-images;android-36;google_apis_ps16k;arm64-v8a`, revisión 7.
- Archivo de Google verificado con SHA-1 publicado `dda632745023567113d9954101709c6526a3c250` antes de instalar.
- Android API **36**, arquitectura ARM64, `adb shell getconf PAGE_SIZE` devuelve **16384**.
- Aceleración Hypervisor.Framework y renderizado software; 2 GB de RAM.
- Dispositivo de ADB: `emulator-5556`. Todas las operaciones se dirigieron a este serial; el teléfono físico no se modificó.

## Resultado con build release

Se instaló el APK universal generado desde el AAB firmado ya verificado, sin cambiar su código ni recompilar un entrypoint de QA. SHA-256 del APK: `96489e930c1974cc078900cc01b086b0309da74fb4df6e228dfe2cb87f372af8`.

1. Arranque release y pantalla inicial: **aprobado**, sin caída en el buffer crash.
2. Selección de una referencia pública por Photo Picker y detección de un rostro: **aprobado**.
3. Lote de seis archivos: JPEG, HEIC, PNG sin rostro y JPEG dañado; todas las imágenes son muestras públicas de OpenCV o sintéticas, no fotos personales.
4. Análisis terminado en el paso 3: **3 coincidencias** y **1 archivo ilegible**, sin caída nativa. No es un benchmark de precisión del producto.
5. Funcionó con permiso de notificaciones **denegado** y acceso a fotos limitado al selector del sistema. No se aceptó analítica para esta prueba.

## Pruebas nativas adicionales

**6/6 aprobadas**, sin fallos, de `AnalysisCompletionTest` y `PrefetchSafetyTest` en el mismo runtime de 16384 bytes. Se usó su harness debug firmado para instrumentación, separado de la prueba del flujo release. Después se retiró la instalación debug de este emulador y se restauró la app release.

Esto cubre cancelación/publicación de final, persistencia y liberación de recursos en casos sintéticos. No equivale a una matriz completa de bibliotecas reales, fondos prolongados, todos los permisos, gamas de teléfono o todos los formatos.

## Evidencia local

En `.tooling/release-checks/emulator-16kb/` del repo móvil:

- `runtime.json`: ambiente y resultados.
- `startup.png`, `startup.xml`: inicio release.
- `release-results.png`, `release-results.xml`: resultado del lote.
- `startup-crash.log`, `workflow-crash.log`: comprobación de crashes.
- `native-tests.log`: seis pruebas instrumentadas.

Reporte consolidado: `flutter_app/build/android-release-readiness.json`. Estos archivos y las fotos de QA quedan ignorados por Git. Las fuentes de las imágenes y su alcance están en `.tooling/release-checks/emulator-qa/sources.json`.

## Abrir desde Android Studio

El AVD está registrado en el SDK local y aparece como **Personas_API36_16KB** en Device Manager. La sesión de QA se ejecuta sin ventana, con la app release instalada. Para abrir una ventana independiente, detener primero esa sesión (Stop en Device Manager o `adb -s emulator-5556 emu kill`) y arrancarlo desde Device Manager. No iniciar una segunda instancia sobre sus mismos datos.

Comando alternativo en este Mac, una vez detenido:

```sh
/Users/christianguantiva/Library/Android/sdk/emulator/emulator -avd Personas_API36_16KB -gpu software -no-snapshot
```

Repetir `getconf PAGE_SIZE` al cambiar de imagen. Un emulador Android estándar de 4 KB no sustituye este AVD.

## Espacio y alcance

Se eliminaron únicamente intermedios y cachés regenerables para instalar y arrancar la imagen. Se conservaron código, modelos, AAB/APK, reportes y firma. Gradle y las herramientas Flutter iOS pueden volver a descargar dependencias/cachés en el siguiente build. El emulador ocupa varios GB: conservar espacio libre para Android Studio.

La verificación de **ejecución 16 KB de esta build y este escenario queda aprobada**. Continúan pendientes el respaldo de la clave por el titular, su registro en Play App Signing, endpoint HTTPS definitivo y las demás pruebas de lanzamiento. No se subió nada a las tiendas ni a GitHub durante esta tarea.

## Seguimiento del 29-10-2026

El AVD fue respaldado y sus datos recreados. Se completó la [interrupción activa y recuperación](android-active-interruption-2026-10-29.md) sobre un APK release nuevo. Quedó apagado limpiamente, con 50 resultados parciales conservados.
