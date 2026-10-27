# Analítica opcional y declaraciones de privacidad

La búsqueda y el reconocimiento siguen funcionando localmente y sin internet. No salen fotos, miniaturas, referencias, plantillas, embeddings, IDs de fotos, claves de feedback, nombres de álbumes, rutas/URI, EXIF, ubicación, contactos ni identidad. No se entrenan modelos. La nueva API propia sólo recibe eventos cerrados y un UUID aleatorio de instalación, creado después de aceptar explícitamente. No se deriva de IDs del teléfono ni se vincula a una cuenta.

En Inicio, «Analítica opcional» explica finalidad y permite aceptar/revocar sin condicionar acceso a fotos. Sólo tras aceptar se guarda el token de propiedad y se encola actividad. No hay Firebase, Google Analytics, anuncios ni SDK facial remoto. Revocar detiene capturas, vacía la cola y pide borrado remoto autenticado. Offline sólo queda la solicitud y credencial necesaria para reintentarlo; el control muestra pendiente y no permite otro consentimiento hasta ACK. Un envío ya en vuelo puede haber sido recibido, pero el borrado serializado del servidor elimina esos eventos e impide futuros envíos del mismo UUID. Agregados anónimos antiguos no pueden relacionarse para eliminarlos.

SQLite outbox v1 (`personas_analytics.db`): analytics_state (consentimiento, installation_id, deletion_pending y backoff de borrado) y analytics_outbox (event_id UUID PK, installation_id, type, schema_version1, created_at hora UTC, payload, state pending, attempts, next_attempt). Transacciones y migración automática al crear. No es índice facial. Token de256bits fuera de SQLite, Android cifrado/Keychain iOS this-device-only tras primer desbloqueo; backup Android ya está desactivado. iOS base en Application Support/OptionalAnalytics, directorio completo excluido de backup mediante URLResourceValues (incluye WAL/SHM). 5000eventos/30d máximo inicial, eliminación por TTL/capacidad aunque no haya ACK (minimización). Errores de DB/red no bloquean búsqueda.

Se intenta enviar al encolar, recuperar conectividad, abrir/reanudar, cada15s con app viva y mediante tarea periódica15min. Wi-Fi no equivale a internet: la propia API debe contestar. Lote50, timeout10s, backoff5s..6h con jitter. No se prometen envíos inmediatos con app suspendida/cerrada, especialmente iOS. Tras reinicio previo al primer desbloqueo el token puede no estar disponible; reintentar después. Android e iOS mantienen sus límites de energía y tareas. La valoración1..5 es subjetiva; omitir no crea evento. La tasa de confirmadas sólo usa evaluaciones explícitas y presenta sin datos si no hay ninguna.

## Permisos de fotos

Android conserva READ_MEDIA_IMAGES y READ_MEDIA_VISUAL_USER_SELECTED (Android14+), READ_EXTERNAL_STORAGE limitado a32 y Photo Picker para selección individual. No acceso general a archivos. iOS PhotoKit para álbumes y PHPicker/documentos para selección contextual; acceso limitado permite ampliar selección desde la app. Reanudar vuelve a consultar permisos/catálogo y limpia una selección de álbum revocada. Permiso denegado mantiene selector individual y Archivos. Álbum vacío no habilita búsqueda. INTERNET y ACCESS_NETWORK_STATE habilitan únicamente transporte y señal de red de analítica; motor sin cambios.

Fuentes oficiales revisadas: [Android acceso parcial](https://developer.android.com/about/versions/14/changes/partial-photo-video-access), [Apple selector limitado](https://developer.apple.com/documentation/photos/phphotolibrary/presentlimitedlibrarypicker(from:)), [connectivity_plus](https://pub.dev/packages/connectivity_plus), [Workmanager](https://pub.dev/packages/workmanager).

## Google Play: datos de esta implementación

Declaración a trasladar al formulario de la versión publicada por el titular; no se ha enviado un formulario de tienda. Según [definiciones oficiales de Seguridad de los datos](https://support.google.com/googleplay/android-developer/answer/10787469), el ID aleatorio de instalación también se considera «Dispositivo u otros IDs», aunque no sea Android ID.

| Categoría | Datos enviados | Finalidad / control |
|---|---|---|
| Dispositivo u otros IDs | UUID aleatorio por instalación, no IDs de hardware | Analítica, opcional, borrado autenticado |
| Actividad en la app / interacciones | sesiones, búsquedas, cantidades agrupadas, confirmadas/rechazadas | Analítica, opcional |
| Información y rendimiento de la app / diagnósticos y otros datos de rendimiento | duraciones y categorías generales de error, sin trazas | Analítica, opcional |
| Actividad / otro contenido generado por usuario | estrellas1..5 y valoración de coincidencias en totales | Analítica, opcional; nunca fotos |

Recopilados sólo si se acepta; no procesados efímeramente (persisten hasta30d). No compartidos con terceros en esta implementación propia; un futuro hosting/proxy/SDK requiere revisar su función y términos. No publicidad, no tracking, no localización ni información personal de cuenta. Cifrado en tránsito sólo si se configura HTTPS en la versión distribuida (Flutter release rechaza HTTP). Documentar URL pública de privacidad y borrado según configuración real del servicio antes de publicar. Verificar declaraciones contra el binario final y las políticas vigentes.

## Apple

PrivacyInfo.xcprivacy declara identificador de instalación, interacciones/uso, rendimiento y valoración, finalidad Analytics, linked=true de forma conservadora por vínculo entre eventos de instalación y tracking=false. No declarar «sin datos recopilados» en una versión con API activa. Revisar la etiqueta de vinculación de datos en App Store Connect: un UUID persistente permite relacionar eventos de una instalación aunque no permita identificar a la persona; usar la clasificación conservadora de datos vinculados al dispositivo. [Valores oficiales del manifiesto](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype). Los manifiestos de los plugins se incluyen mediante Swift Package Manager. Se conserva declaración de APIs nativas ya existentes; cada plugin mantiene sus motivos de acceso. El token nunca se comparte con la extensión de fotos.

## Ejecución Flutter

```sh
python3 tools/setup_flutter.py # sólo si falta SDK local
./tools/flutter.sh pub get
./tools/flutter.sh run # sin URL: búsqueda normal, analítica offline si se acepta
./tools/flutter.sh run --dart-define=ANALYTICS_API_URL=https://tu-api-local-confiable
./tools/flutter.sh analyze
./tools/flutter.sh test
```

Android emulador debug puede usar `http://10.0.2.2:3000`; iOS simulador debug `http://127.0.0.1:3000`, sujeto a política de red del SO. En dispositivos físicos usar HTTPS confiable, sin excepciones globales ATS ni cleartext en release. No incluir tokens del backend en dart-define. iOS registra co.local.personas.analytics.sync en AppDelegate/Info.plist (fetch), manteniendo tarea de análisis existente (processing). Keychain usa grupo privado de app; actualizar firma/perfil si el equipo lo necesita. No se han instalado builds en dispositivos físicos ni validado entrega de BGTask real; probar con consentimiento, modo avión, reanudación, muerte de proceso, cambios de permisos y borrado antes de publicación.

## Ampliación v2 — plataforma, conteos y correlación

La app0.9.0+13 requiere renovar explícitamente el consentimiento previo antes de capturar los campos ampliados. Conserva ID/token de instalación y eventos v1 pendientes; éstos siguen sujetos al consentimiento anterior y no se enriquecen. Se puede revocar y solicitar borrado aunque no se acepte la ampliación. No se aceptó el consentimiento en nombre del usuario.

Nuevos campos permitidos: iOS/Android, versión+build reales (package_info_plus; sólo version/build, sin installerStore, nombre, identificadores ni modelo), conteos exactos de fotos previstas/procesadas/no legibles/coincidencias, tiempos de ejecución/presentación, UUID aleatorios de sesión/búsqueda y reintentos. ID de búsqueda no deriva ni identifica una fotografía o persona. Fecha v2 redondeada al minuto. No se reciben fotos, embeddings, nombres/rutas/URI o IDs de imágenes. Mantener las categorías de uso, rendimiento, otros IDs aleatorios y valoración declaradas en las tiendas; actualizar la descripción de privacidad al publicar la versión ampliada.

SQLite migra v1→v2 transaccionalmente, conserva cola v1 y añade consent_version, plataforma/versión de outbox, analytics_runs y analytics_marks (sólo UUID de búsqueda/sesión, flags y métricas permitidas). Seguimiento/marcas caducan en30d, revocación los borra y la deduplicación sobrevive reinicios. No se exporta el contexto nativo de fotografías al outbox. Restaurar resultados no crea eventos nuevos para búsquedas sin seguimiento local (por ejemplo tras revocar). Las duraciones no medibles se omiten; interrupción sólo se registra cuando el inicio durable ya no corresponde a una ejecución nativa activa ni tiene final observado.

Especificación y límites: [incremento v2](../specs/003-optional-analytics/v2.md). Contrato y nuevos reportes: [Backend](../Backend/README.md#eventos-relacionados-v2-app09013).

## Diagnóstico de rendimiento por búsqueda

Los finales v2 admiten contadores opcionales `cacheHits`, `cacheMisses` y tiempos `readMs`, `decodeMs`, `engineMs`, `timeToCancelMs`, `cancelLatencyMs`. No incluyen identificadores de fotos, hashes, rutas, modelos de teléfono ni datos faciales. Su retención sigue siendo la de los eventos (hasta 30 días); no se reconstruyen mediciones ausentes en eventos antiguos.

Lectura incluye acceso y hash; en Android algunas rutas de proveedor decodifican directamente y no pueden desglosar lectura. El motor agrupa detección, extracción y comparación. Las etapas suman trabajo observado por foto; prefetch puede solaparlas y no deben sumarse como si fueran duración total de pared. Las fotos ilegibles pueden tener diagnóstico parcial. Los contadores de caché cubren fotos analizadas con éxito, no necesariamente todas las previstas.

La latencia de cancelación mide desde la solicitud hasta observar el final con reloj vivo; Android también persiste la demora nativa cuando se cancela desde la notificación. Un final restaurado sin ese reloj conserva el dato como ausente. El dashboard distingue sin final observado de un fallo, permite filtros de resultado/versión/lote y une valoraciones y revisiones por búsqueda e instalación sin exponer esos IDs al navegador.

No se miden aún el tiempo exclusivo de detección frente a comparación, la duración de suspensión ni la presión de memoria. El servidor no puede conocer el tamaño de una cola local desconectada ni los intentos que nunca llegaron; reintentos y retrasos representan eventos recibidos.
