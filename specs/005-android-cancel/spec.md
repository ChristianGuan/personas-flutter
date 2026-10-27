# 005 — Cancelación Android y confirmación final

Observación física: snapshot privado active=false, cancelled=true y20/209 procesadas, mientras Flutter seguía mostrando análisis activo y botón Cancelar. La cancelación no se perdió en el botón: se perdió la publicación final de estado en memoria/EventChannel.

Causa: finally ejecutaba withContext(NonCancellable + storage) para persistir y después actualizaba run.active/job y emitía done. Al regresar a la corrutina original cancelada, el cambio de dispatcher puede descartar el resultado y lanzar CancellationException antes de publicar. Estado en disco final y UI en ejecución divergen. Cancelar otra vez no reactiva el finally ya terminado.

Solución: finalizar dentro de un único bloque NonCancellable en el dispatcher del llamador (Main), anidar IO sólo para persistencia y publicar/limpiar estado en finally dentro de ese bloque protegido. Reutilizar el mismo cierre en cancelación antes de arranque. Primer pedido de cancelación se marca/idempotente, publica status inmediato, se persiste en snapshot y no agrega más fotos. Flutter muestra Cancelando, deshabilita repetir solicitud y descarta progreso tardío mientras espera done; snapshot reanudado conserva parciales y estado de cancelación. Al concluir, resultados parciales accesibles y búsqueda nueva habilitada.

No fingir interrupción instantánea de una llamada nativa: decodificación/inferencia ya en vuelo puede finalizar antes de liberar recursos. No iniciar nuevas fotos después de cancelar. Mantener pipeline, caché, optimización de preparación, privacidad y consentimiento. No limpiar resultados del usuario para probar.

Validación: prueba nativa bajo job cancelado con cambio real a dispatcher de persistencia, publicación en Main y exactamente una finalización incluso si persistencia falla; regresiones Dart de petición, confirmación, progreso tardío, resultado parcial y nuevo intento; prueba nativa de reciclaje existente. Compilar en secuencia e instalar Android0.9.2+15, restaurar parcial real y comprobar que UI deja análisis. Pruebas de persistencia sintética sin modificar snapshot real del usuario.

Referencia primaria del comportamiento de cancelación al regresar de dispatcher: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/with-context.html . La prueba de ciclo completo instancia el runtime con ContextWrapper/cacheDir aislados, un PNG sintético y worker bloqueado; no lee/escribe el snapshot real ni usa fotos personales. Verifica done único, active=false, siguiente ejecución y cancelación previa al arranque.
