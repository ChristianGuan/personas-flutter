# ADR 010 — Análisis iniciado por ti en segundo plano

Estado: implementado en R23 (Flutter 0.8.0+11). Evidencia y límites por plataforma en `docs/validation.md`.

## Ejecución y límites

Android usa `AnalysisRuntime`, propiedad de la aplicación, y `AnalysisService`, servicio en primer plano `dataSync`. El procesamiento local de archivos está incluido en ese tipo. Se inicia al pulsar Buscar desde la app visible; destruir la Activity o desconectar el canal Flutter no cancela la búsqueda. El servicio publica progreso real, permite cancelar, mantiene CPU mediante un wake lock acotado y libera recursos al finalizar. `START_NOT_STICKY`, sin reinicio al arrancar el teléfono ni trabajos programados ocultos. El timeout del sistema o el límite local de seis horas interrumpen el trabajo con resultados parciales.

iOS 26+ registra una solicitud única `BGContinuedProcessingTaskRequest` de CPU con estrategia `fail`. El trabajo de reconocimiento comienza al concederse la tarea; mantiene progreso real y maneja cancelación/expiración. Si no puede concederse o tarda en iniciar, se cancela esa solicitud y se utiliza el tiempo limitado de `beginBackgroundTask`. En iOS 16–25 sólo existe esa alternativa limitada. La interfaz indica el modo concedido. El sistema controla duración y recursos; no se promete continuidad después de cierre forzado ni una ejecución indefinida. La inferencia sigue en la cola nativa, con los mismos modelos, umbrales y preprocesamiento.

## Avisos y recuperación

Permiso de notificación opcional, solicitado al iniciar la primera búsqueda; denegarlo conserva el análisis y muestra una acción para habilitar avisos. Android separa canal silencioso de progreso y canal de finalización. iOS usa notificación local y omite su banner propio si la app ya está visible. Los avisos no contienen retratos, nombres de persona/álbum ni URIs. Una cancelación explícita no genera un aviso de éxito. Tocar el aviso abre y reconcilia la última búsqueda.

Revisión física 2026-10-24: el canal Android de finalización usa importancia alta para permitir banner. Android no permite elevar la importancia de un canal ya creado: se crea `personas_analysis_results` para sustituir el valor inicial normal de `personas_analysis_done` sólo si no hay elección de importancia/sonido del usuario. Canales bloqueados, personalizados o de versiones sin esa comprobación se conservan; se copian sonido, vibración, luces, distintivo y visibilidad. Un canal nuevo ya existente siempre conserva su configuración. No se emplea pantalla completa ni se evita No molestar; la presentación final la decide el sistema. [Comportamiento de los canales](https://developer.android.com/develop/ui/compose/notifications/channels), [preferencias explícitas del usuario](https://developer.android.com/reference/android/app/NotificationChannel#hasUserSetImportance()).

iOS espera al callback de `UNUserNotificationCenter.add` antes de liberar la tarea, evitando depender de que la cola de envío alcance al proceso antes de su suspensión. El estado puede consultar entrega y configuración de avisos propios y un indicador local de fallo; no lee notificaciones de otras apps ni añade analítica. La entrega confirmada no implica un banner permanente o saltarse las preferencias del sistema.

MethodChannel añade `searchSnapshot`, `updateSearch`, `notifications`, `requestNotifications`, `notificationSettings`; `initialize` incluye el último snapshot y capacidades. `search` recibe contexto de visualización sin embeddings y responde con el modo de segundo plano. EventChannel añade `status` y `openAnalysis`. El controlador reconcilia por runId y foto, descarta duplicados/respuestas obsoletas y conserva selección y decisiones manuales.

Se guarda **únicamente el último análisis** en caché privada: contexto de referencia (cajas/URI), fotos elegidas, resultados, feedback y selección. Escrituras atómicas en una cola de almacenamiento serial, checkpoints cada 25 fotos y estado final antes de emitir `done`/notificar. Al morir el proceso, un estado activo se recupera como interrumpido; no se reanuda automáticamente ni se presenta como completado. Los handles de referencia caducados requieren elegir de nuevo una referencia; los resultados siguen revisables. No se persisten embeddings ni el índice de reconocimiento. La caché puede ser purgada por el sistema.

iOS conserva las copias privadas que ya hacía del proveedor para poder mostrar/compartir resultados después de un arranque nuevo. **Borrar datos de esta sesión** elimina esas copias, el último análisis, feedback, referencias en RAM y avisos. Android conserva grants persistibles sólo cuando el selector los permite; un proveedor puede revocar acceso y requerir volver a elegir las fotos. Los originales no se alteran. No hay backend ni dependencias nuevas.

## Fuentes de plataforma

- [Android: tipos de servicio, dataSync y procesamiento local](https://developer.android.com/develop/background-work/services/fgs/service-types).
- [Android: límites y onTimeout](https://developer.android.com/develop/background-work/services/fgs/timeout).
- [Android: permiso de notificaciones y servicios en primer plano](https://developer.android.com/develop/ui/compose/notifications/notification-permission).
- [Apple: BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask).
- [Apple: trabajo prolongado iniciado en primer plano](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados).
