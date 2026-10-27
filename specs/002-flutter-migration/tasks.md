# Tareas — Flutter

- [x] F01 Inspeccionar proyecto, entorno y motor; definir R21/V17/protocolo y estrategia SDD.
- [x] F02 Instalar SDK local verificado y generar proyecto Flutter Android/iOS con dependencias fijadas.
- [x] F03 Controlador y modelos compartidos, carreras/cancelación, feedback y selección protegida.
- [x] F04 Migrar cinco pantallas, tema, referencias/rostros, álbumes, análisis y revisión accesible.
- [x] F05 Adaptador Android real para inferencia/caché/HEIC, fotos/permisos/nube y compartir/recepción.
- [x] F06 Adaptador iOS real de fotografías e inferencia OpenCV, configuración de proyecto y modelos/avisos.
- [x] F07 Análisis estático y tests Dart; compilar Android y regresión nativa contra QA público.
- [x] F08 Instalar/revisar Flutter en Android, fuente grande/tamaño pequeño/oscuro/HEIC y estados vacíos.
- [x] F09 Compilar y probar iOS en simulador/iPhone cuando Xcode esté disponible; registrar bloqueo exacto si falta.
- [x] F10 Documentar comandos de ejecución, arquitectura, evidencia y límites pendientes.
- [x] F11 Configurar Team, identificadores y App Group; instalar Release en un iPhone físico autorizado y verificar arranque sin depurador (2026-10-23).


Cierre técnico: 0.7.0+9, SDK local fijado, 18 pruebas Dart y escenario real de 50 entradas aprobado en Android físico e iOS Simulator ARM64. Compilaciones Android, iOS Simulator e iPhone aprobadas; Release firmada instalada y abierta en iPhone 15 Pro Max/iOS 27.0.1. Evidencia y límites en `docs/validation.md`; no se atribuye una mejora de precisión/rendimiento a esta migración.

Aceptación externa pendiente (no bloquea el código/compilación comprobados):

- [ ] F12 Probar fototeca/álbum familiar, permisos iOS completo/limitado, proveedores cloud y recepción/compartir originales con cuentas reales. Mantener T49/T10/T31/T35 del incremento Android.
- [ ] F13 Índice persistente, memoria y escalabilidad con grandes bibliotecas (T12/T13 anteriores).

Incremento R22 — UI cercana y dinámica:

- [x] F14 Revisar pantallas/tema/caché y definir lenguaje de tú y aviso honesto del primer escaneo.
- [x] F15 Centralizar estilos/componentes y mejorar inicio, pasos, selecciones, progreso, fotografías y barra inferior con movimiento reducido.
- [x] F16 Verificar regresiones, texto 200 %, pantalla pequeña, estados vacíos y animaciones desactivadas; compilar Android/iOS, revisar en simulador y actualizar ambos teléfonos. Evidencia R22/V18 en `docs/validation.md`.

Incremento R23 — Segundo plano y notificaciones:

- [x] F17 Contratos/SDD y límites reales de Android/iOS, recuperación y permiso de avisos.
- [x] F18 Runtime y servicio Android independientes de Activity, progreso/cancelación/timeout y aviso final.
- [x] F19 Tarea continua iOS 26+, fallback limitado, progreso/expiración y notificación local.
- [x] F20 UI de permiso/estado, snapshot al reanudar y recuperación del último análisis sin embeddings persistidos.
- [x] F21 Compilar/probar cambios de app, finalización, notificaciones denegadas, cancelación y restauración; actualizar dispositivos disponibles y documentar límites.

F21 parcial (2026-10-23): 29 tests Dart, análisis estático y compilaciones Android/iOS aprobados. En iOS Simulator se completaron 370 fotos públicas fuera de la app, con decisiones idénticas al repetir, restauración tras muerte del proceso y cancelación real con 26 resultados parciales. El simulador concede el fallback `iosLimited`; la continuación ampliada y entrega/apertura real de avisos requieren iPhone disponible. Android bloqueado rechazó correctamente el inicio automático de QA (FGS exige inicio visible); no equivale a una prueba de continuación Android. Aplicación normal restaurada en Android; iPhone desconectado, Release normal firmada preparada. Pendiente desbloquear Android/reconectar iPhone, conceder avisos en el sistema y verificar progreso, cancelación desde aviso y apertura de resultados en ambos teléfonos. Detalles en `docs/validation.md`.

F21 cerrada (2026-10-24): ambos teléfonos completan 370 fotos públicas con Ajustes abierto, con las mismas decisiones que las referencias en primer plano. iPhone concede `iosContinued`; iOS confirma aviso entregado, banners permitidos y sin error de registro; el usuario confirma que tocarlo abre resultados. Android confirma aviso publicado y mejora de canal a importancia alta sin sobreescribir decisiones del usuario; recuperación fría íntegra y recursos liberados. 29 tests/análisis estático aprobados. Versiones normales finales instaladas y abiertas en ambos, sin flags/entrada QA. Fotos de prueba retiradas y ajuste de pantalla Android restaurado; la búsqueda real iniciada durante la comprobación se dejó terminar y se conservaron sus resultados. La captura automatizada no confirmó el banner/tap Android; la cancelación desde la acción del aviso no se ejercitó físicamente. Se conserva esa limitación de comprobación visual en la validación, sin afirmar que se probó.

Incremento R24 — Retirar indicador decorativo:

- [x] F22 Inspeccionar la barra inferior y especificar la eliminación del círculo y «Elige fotos», conservando selección, contador accesible y compartir.
- [x] F23 Simplificar la barra, comprobar regresiones y compilaciones; actualizar los dispositivos disponibles sin interrumpir búsquedas.

V20 (2026-10-24): eliminado el círculo decorativo y el texto «Elige fotos» de la barra de resultados. El contador accesible aparece sólo con selección; se conservan selección individual, selección total y compartir. Análisis estático sin incidencias y 29 pruebas aprobadas, incluidas pantalla de 320×480 dp, texto 200 %, tema oscuro, movimiento reducido y resultados vacíos. APK Android y Release iPhone compilados; firma iOS verificada. Actualización instalada y abierta en el iPhone después de comprobar que no había análisis activo. Android desconectado: APK preparado, sin instalación. No se realizó una revisión visual manual del cambio en el teléfono.

Incremento R25 — Flecha de regreso tras recuperar resultados:

- [x] F24 Inspeccionar flecha, restauración iOS y prerrequisitos de navegación; definir regreso útil con referencia caducada.
- [x] F25 Reproducir el fallo mediante el toque de Volver, corregir la ruta y verificar conservación de resultados/selección y bloqueos durante operaciones.
- [x] F26 Ejecutar análisis estático/regresiones, compilar e instalar en iPhone disponible; documentar comprobaciones y límites.

V21 (2026-10-24): reproducido el fallo antes de corregirlo: tocar Volver desde resultados iOS recuperados con `referencesAvailable=false` dejaba la pantalla en resultados. La misma prueba pasa después del cambio y confirma regreso a referencia, continuación hasta inicio y conservación de fotografías, resultados y selección. Con referencias disponibles se conserva el regreso a álbumes; el selector pendiente sigue bloqueando la navegación. 31 pruebas aprobadas y análisis estático sin incidencias. Release iPhone compilada, firma verificada, instalada y abierta después de comprobar que no había análisis activo; el resultado anterior se conserva tras actualizar. La interacción de la flecha se verificó mediante widget tests, sin comprobación manual del toque en el teléfono.

Seguimiento Android de R24/R25:

- [x] F27 Al reconectar Android, compilar e instalar la aplicación normal con la barra corregida y navegación actual, conservando el último resultado y sin interrumpir análisis; comprobar la barra de resultados si la pantalla es accesible.

F27 (2026-10-24): el Android reconectado aún mostraba «Elige fotos» en la versión instalada. APK normal actual recompilado e instalado después de confirmar que no había análisis activo. App abierta y resultado anterior conservado (209 fotos procesadas). Comprobación de accesibilidad y revisión visual de la pantalla real: la barra inferior ya no contiene el círculo ni «Elige fotos»; conserva Compartir selección. Sin cambios adicionales de código ni nuevas pruebas repetidas para esta instalación.

Incremento R26 — Recuperar la preparación de referencia en iPhone:

- [x] F28 Inspeccionar carga/selector, confirmar barra persistente y definir cancelación y errores recuperables.
- [x] F29 Añadir cancelación/plazo/finalización única nativa, identidad de peticiones y recuperación de la UI ante respuestas tardías.
- [x] F30 Probar cargas pendientes, cancelación, reintento y plazos; compilar, instalar en iPhone disponible y documentar límites.

V22 (2026-10-24), 0.8.1+12: 40 pruebas Flutter y análisis estático aprobados. Pruebas nativas de petición pendiente, plazo, respuesta única, cancelación, respuesta tardía y reintento aprobadas. Integración con adaptador iOS y HEIC público en simulador: cancelación inmediata, cancelación obsoleta, nueva detección de rostro y preview correctos. Compilaciones Android, simulador iOS y Release iPhone aprobadas; app normal restaurada en simulador. Release firmada instalada y abierta en iPhone, sin análisis activo y conservando el resultado anterior. Se verificaron Cancelar carga/Volver en widgets con pantalla pequeña y texto 200 %; no se repitió manualmente el bloqueo con la foto concreta ni con una descarga cloud real. Evidencia en `docs/validation.md`.
