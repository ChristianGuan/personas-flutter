# Recuperación de un análisis activo — 29-10-2026

**Resultado: aprobado en una nueva build release de QA.** Se cerró la prueba que había quedado bloqueada por corrupción del emulador. Tras detener el proceso durante un análisis real, la app volvió al paso 3 con **50 de 201 fotos procesadas y 50 coincidencias**, identificadas como resultados parciales.

Esta ejecución tiene un binario distinto del usado el 28 de octubre. Las 13 comprobaciones y las 7 pruebas de analítica del [reporte anterior](android-functional-privacy-2026-10-28.md) conservan su alcance original; no se atribuyen automáticamente a esta nueva build.

## Binario y entorno identificados

| Campo | Valor verificado |
|---|---|
| Repositorio de origen | `repos/personas-flutter` |
| Entrada Flutter | `lib/main.dart`, sin entrypoint de instrumentación |
| APK SHA-256 | `65b0bdf7e7446de4a375ab2173846b423fe9817a4cc39dd2169ac32f5e83e122` |
| Firma | Upload key de Personas; certificado SHA-256 `c0e32c9d006af4c933853fb9fa70185a5057d4242389f9572db744b8f0e55780` |
| Android target / depurable | **36 / false** |
| Comprobación estática | **12 ELF64** alineados a 16 KB y offsets ZIP aprobados |
| Runtime | Android API 36 ARM64, `PAGE_SIZE=16384` |
| AVD / ADB | `Personas_API36_16KB` / `emulator-5556` |
| Seguridad del runtime de prueba | SELinux **Enforcing** |
| Recursos configurados | 2 GB de RAM, 2 núcleos; gráficos software, Vulkan desactivado |
| Instalación | `adb install --no-incremental` |
| Analítica | Sin consentimiento y `ANALYTICS_API_URL` vacío para esta QA |

El APK queda conservado en el repo móvil en `.tooling/release-checks/active-interruption-20261029/personas-release.apk`, además de la salida de compilación. La configuración de analítica vacía significa que **este binario de QA requiere reconstrucción con el endpoint definitivo antes de distribuirlo a usuarios**. Esta tarea no generó un nuevo AAB ni publicó una versión.

## Recuperación del entorno

1. Se conservó una copia APFS del AVD dañado en `.tooling/avd-backups/Personas_API36_16KB-20261029.avd`, bajo la raíz del workspace `IA_FOTOS`.
2. Se intentó recuperar su APK mediante acceso root y SELinux permisivo, exclusivamente para diagnóstico. Los metadatos de `/data` devolvieron `Structure needs cleaning`; no se recuperó el binario anterior. Este modo de recuperación no se utilizó para validar la app.
3. Se generó una release nueva del repositorio móvil, con su configuración de firma y target 36. Un primer intento reutilizó el registro de plugins de QA debug al usar `--no-pub`; la compilación normal regeneró el registro de release y terminó correctamente. No se modificó la lógica de la app para resolverlo.
4. Después del respaldo se reinicializaron **sólo los datos de ese AVD**. El arranque limpio terminó en aproximadamente 25 segundos. Se verificaron páginas de 16 KB y SELinux Enforcing antes de instalar el APK.
5. Se eliminaron cachés/intermedios regenerables para recuperar espacio; se conservaron las claves, el APK firmado, el respaldo y los reportes. Flutter/Gradle pueden descargar herramientas y dependencias de nuevo en próximos builds.

No se modificó el teléfono físico ni se utilizó la BD para esta prueba.

## Ejecución y observaciones

Se crearon 200 variantes JPEG de una muestra pública previamente identificada de OpenCV y se añadió la referencia: **201 archivos de QA**, sin fotos personales. Se seleccionaron desde un álbum real mediante la interfaz release. Las variantes no representan una biblioteca diversa ni permiten estimar precisión o rendimiento de producción.

| Caso | Antes de detener | Tras relanzar |
|---|---|---|
| Interrupción muy temprana | Servicio foreground activo; pantalla con 2 fotos procesadas | Paso 3, **0/201** y 0 coincidencias, marcados como parciales: aún no había un checkpoint de resultados |
| Interrupción con avance guardado | Servicio foreground activo; notificación con 47 procesadas y captura posterior con 49 | Paso 3, **50/201** y **50 coincidencias**, marcados como parciales |

En ambos casos se usó `am force-stop`, se comprobó que el PID desaparecía y se relanzó la app. El servicio activo quedó registrado con `isForeground=true`. Los contadores de notificación, captura y restauración corresponden a instantes sucesivos: el análisis avanzó entre esas lecturas y la detención del proceso.

Las aserciones sobre el XML final confirmaron `Búsqueda cancelada`, `50 coincidencias` y `50 de 201 fotos procesadas. Estos resultados son parciales.` El buffer de crashes quedó vacío. Para volver a buscar se solicita una referencia nueva, porque sus representaciones en memoria desaparecen con el proceso; esa ruta también se utilizó entre los dos ensayos.

### Límite de recuperación

El motor guarda checkpoints **cada 25 fotos**, además del estado inicial y final. Un cierre abrupto puede perder el avance posterior al último guardado. El ensayo temprano —2 mostradas, 0 recuperadas— demuestra este límite; no se promete recuperar cada resultado visible inmediatamente antes del cierre. No se cambió esa política durante esta tarea.

La prueba verifica un cierre forzado controlado y recuperación desde disco. Siguen pendientes reinicio completo del dispositivo, cierres automáticos por memoria/batería, otras marcas y la candidata descargada desde Play. La matriz iOS se realiza por separado.

## Evidencia local

Rutas relativas al repositorio móvil:

- `.tooling/release-checks/active-interruption-20261029/process-interruption.json`: resultado y configuración de la prueba.
- `initial-checkpoint-case.json`, `initial-before-interruption.png`: ensayo temprano, en la misma carpeta.
- `active-service.txt`, `progress-before-kill.txt`, `before-interruption.png`: servicio y avance observados.
- `restored.xml`, `restored.png`: resultados recuperados.
- `crash.log`, `package-flags.txt`, `static-pages.json`, `build.log`: comprobaciones técnicas.
- `personas-release.apk`: binario firmado probado.
- `flutter_app/build/android-release-readiness.json`, sección `activeInterruption20261029`: resumen consolidado.

El emulador quedó **apagado limpiamente**, con la nueva release instalada y los resultados parciales conservados. Puede abrirse desde Device Manager. El AVD anterior se conserva en el respaldo; el ZIP de la guía contiene documentación, no los discos del AVD ni el APK.
