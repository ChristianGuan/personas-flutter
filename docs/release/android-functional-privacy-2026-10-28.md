# Pruebas funcionales y de privacidad — Android

Ejecución: **28-10-2026**. Se realizaron los puntos 1 y 2: funcionamiento con permisos restringidos/segundo plano y privacidad/sincronización. Resultado: **13 comprobaciones del arnés aprobadas, 7 pruebas automatizadas de analítica aprobadas y permisos denegados/limitados comprobados en release**.

## Entorno y separación de evidencias

- Emulador `Personas_API36_16KB`, Android API 36 ARM64, páginas **16384 bytes**. El arnés solicitó 1 GB de RAM y 2 núcleos; no se midió su RAM efectiva. El emulador actual impone un mínimo de 2 GB.
- APK release universal original: SHA-256 `96489e930c1974cc078900cc01b086b0309da74fb4df6e228dfe2cb87f372af8`. Se restauró al terminar la prueba instrumentada y se usó para los permisos de fototeca.
- Para controlar reinicios, SQLite y pérdida de confirmaciones se utilizó **otra variante debug de QA**, con `integration_test/readiness_probe.dart` como entrada y los plugins/motor nativos del APK debug existente. Se compilaron sus assets Dart; no se alteró el AAB ni el APK release para estos controles.
- El entrypoint exige `PERSONAS_QA_EMULATOR=true`, `ro.kernel.qemu=1` y exactamente `ANALYTICS_API_URL=http://10.0.2.2:3100`. No está importado por `lib/main.dart`.
- API NestJS real en loopback 3101, proxy de fallos en 3100 y control en 3199. PostgreSQL usó esquemas temporales exclusivos `qa_readiness_<UUID>`, con las migraciones reales. Al terminar: **0 esquemas temporales restantes**.
- Imágenes públicas de OpenCV y archivos sintéticos, incluidos JPEG, HEIC, PNG sin rostro y JPEG inválido. La carpeta final tenía 636 archivos; los lotes ampliados son variantes de una muestra, no una biblioteca representativa de usuarios ni un benchmark de precisión.
- Todas las operaciones ADB apuntaron a `emulator-5556`. El teléfono físico no se modificó.

## 1. Funcionamiento

| Caso | Resultado observado | Evidencia / alcance |
|---|---|---|
| Sin permiso amplio de fotos | La referencia se selecciona con Photo Picker y se detecta un rostro | APK release; el selector concede acceso a lo elegido |
| Rechazar acceso a álbumes | La app vuelve al paso 2 y conserva la alternativa de fotos individuales | Rechazo real en el diálogo Android; captura `permission-denied-release.png` |
| Conceder acceso limitado | El álbum `PersonasQA` muestra **2 fotos** y la app avisa que no es el álbum completo | APK release; `READ_MEDIA_IMAGES=false`, `READ_MEDIA_VISUAL_USER_SELECTED=true` |
| Notificaciones denegadas | Las búsquedas siguen funcionando; no se exige activar avisos | Flujo release previo y ejecución del arnés con permiso denegado |
| Buscar sin aceptar analítica | Lote de 6: **3 coincidencias, 1 ilegible**, sin identidad ni cola de analítica | Arnés con controlador y motor reales |
| Continuar al ir a Inicio | Se completaron **54/54 fotos** con la app en segundo plano | Arnés; al volver no cambió el resultado |
| Cancelar dentro de la app | La búsqueda termina cancelada y permite volver a buscar | Controlador y motor reales |
| Cancelar desde notificación | Se pulsó la acción real **Cancelar análisis** en el panel de Android | Captura y XML; se conservaron 232 fotos procesadas del lote largo |
| Recuperar resultados | Después de `force-stop` y relanzar, se restauraron los mismos resultados cancelados y el paso 3 | Este caso prueba recuperación de resultados parciales ya cancelados; no un reinicio del dispositivo ni la muerte de un análisis activo |

Las 6 pruebas nativas previas de finalización/prefetch siguen documentadas en [evidencia 16 KB](android-emulator-16kb-2026-10-28.md). No se vuelven a contar como pruebas nuevas en este reporte.

## 2. Privacidad y sincronización

| Caso | Resultado observado |
|---|---|
| Antes del consentimiento | **0 solicitudes** al proxy/API, **0 instalaciones**, **0 eventos**, cola vacía e identidad local ausente durante las búsquedas |
| Aceptar sin conexión | Modo avión, Wi-Fi desactivado y proxy cerrado a solicitudes; **2 eventos** quedaron en SQLite |
| Reiniciar sin conexión | La cola y el identificador de instalación persistieron; no se perdieron los pendientes |
| Perder una confirmación | El servidor aceptó un lote y el proxy cortó la respuesta; se bloquearon nuevos envíos hasta verificar que la cola conservaba el evento |
| Reintentar | Un ID se envió **2 veces** y ocupó **1 fila**. Al terminar había **3 eventos únicos**, contando el nuevo inicio de sesión; la cola quedó vacía |
| Revocar sin conexión | Se detuvo la captura y se vaciaron `analytics_outbox`, `analytics_runs` y `analytics_marks`; el borrado remoto quedó pendiente |
| Reiniciar tras revocar | Consentimiento desactivado, cola vacía y solicitud de borrado pendiente persistieron |
| Recuperar conexión | `DELETE` respondió 200 y quedaron **0 eventos individuales** en el esquema de QA; el borrado local dejó de estar pendiente |

El servidor conserva **una marca de instalación eliminada** para impedir que reenvíos vuelvan a incorporarla. Eso no equivale a eliminar toda fila de la BD; las estadísticas agregadas tienen su propia política. Los registros del proxy guardaron tipos y nombres de campos, sin cuerpos completos ni tokens: en esta prueba sólo se observaron `sessionId` y `durationMs`; no fotos, rutas de biblioteca, álbumes ni representaciones faciales.

Se ejecutaron además **7/7** pruebas de `analytics_test.dart` y `analytics_v2_test.dart`: consentimiento, cola durable, ACK parcial/ajeno, revocación, caducidad/capacidad y migración/deduplicación v2. Son pruebas con SQLite FFI y transporte simulado; complementan la prueba real anterior.

## Evidencia y repetición

Rutas relativas a la raíz de este repositorio:

- `flutter_app/build/android-release-readiness.json`: resumen consolidado; sección `functionalPrivacy20261028`.
- `.tooling/release-checks/readiness/report.json`: 13 comprobaciones y fase `complete`.
- `no-consent-server.json`, `lost-ack-server.json`, `synced-server.json`, `deleted-server.json`, `server-final.json`: estados del servidor temporal en esa carpeta.
- `notification-cancel.png`, `notifications.xml`, `analytics-tests.log`: cancelación y pruebas automatizadas.
- `.tooling/release-checks/emulator-16kb/permission-{picker,denied-release,limited-release}.png`: permisos release.
- `flutter_app/integration_test/readiness_probe.dart`: fuente del entrypoint exclusivo de QA.

El orquestador, proxy, APK de QA y fixtures de esta ejecución se conservan localmente bajo `.tooling/`; no son un servicio de producción ni se suben con la app. Para repetir, preparar un esquema temporal nuevo, ejecutar el proxy sólo en loopback, instalar la variante QA sólo en el emulador y usar las puertas del entrypoint para cada transición. El proxy debe mantener bloqueados los envíos **después** de cortar el ACK hasta inspeccionar la cola: de otro modo, la conectividad y el temporizador pueden reintentar antes de la aserción. Restaurar siempre release, red y limpiar el esquema al terminar.

## Incidencias del entorno y límites

Flutter y una sincronización Gradle volvieron a crear cachés, agotando el disco del Mac. Se limpiaron únicamente cachés/intermedios regenerables y se recuperaron Docker/PostgreSQL y el emulador. Los intentos afectados no se tomaron como aprobados; se repitió la matriz completa desde una instalación QA limpia. La ejecución final terminó satisfactoriamente, PostgreSQL quedó disponible y no quedó el servicio temporal abierto. No se borraron las tablas reales para preparar las pruebas.

La build release quedó restaurada, no depurable, sin aceptar analítica; fotos con acceso limitado y notificaciones denegadas. No se subió nada a GitHub ni a las tiendas.

**Pendiente antes de publicar:** repetir sobre la candidata descargada de Play, teléfonos de distintas marcas, biblioteca real diversa, análisis activo interrumpido por el sistema/reinicio y políticas de batería; hacer la matriz iOS por separado. El dominio HTTPS definitivo, backups y las declaraciones de privacidad también requieren su validación de producción. Esta prueba local no certifica toda la candidata de tienda ni el endpoint público.

## Seguimiento del arranque del emulador — 28-10-2026

Al continuar la comprobación adicional de interrupción activa, el AVD ya estaba detenido. Se liberaron cachés regenerables y se intentó arrancarlo de nuevo, también con Vulkan desactivado. El diagnóstico de kernel confirmó **corrupción EXT4 en `/data`** (directorio de instalación incremental y metadatos verity), con `Kernel panic - not syncing` y reinicios antes de completar Android. No se pudo iniciar esa búsqueda: **este caso no se ejecutó ni se marca aprobado**.

El emulador se dejó detenido para evitar más escrituras. No se borró ni reinicializó su disco. La matriz de 13 comprobaciones y las 7 pruebas de analítica de la ejecución anterior conservan su evidencia; este seguimiento no es una repetición de esa matriz. El APK release había sido restaurado durante aquella ejecución, pero actualmente el AVD no está operativo.

Evidencia adicional: `.tooling/release-checks/readiness/avd-boot-failure.txt` y `active-interruption-pending.json`. El entrypoint QA pasó `dart analyze` sin incidencias y los enlaces Markdown y `git diff --check` fueron verificados.

Para completar el caso pendiente se necesita recuperar o recrear **únicamente el AVD de QA**, reinstalar una candidata release identificada por hash y repetir la interrupción con el análisis activo. Los APK/AAB del repositorio móvil que se usaron en la ejecución anterior ya no están en sus rutas locales al continuar esta sesión; conservar el reporte histórico y generar/identificar de nuevo los binarios antes de repetir. No sustituir esta comprobación por un resultado de otra build.

## Cierre del pendiente — 29-10-2026

El AVD se respaldó y se reinicializaron sus datos. La prueba de interrupción activa terminó aprobada sobre **una nueva release de QA identificada por hash**, con recuperación de 50/201 fotos. Ver [reporte 11](android-active-interruption-2026-10-29.md), incluido el límite de checkpoints cada 25 fotos. El estado de emulador bloqueado descrito arriba es histórico; actualmente quedó apagado limpiamente y operativo para nuevas sesiones.
