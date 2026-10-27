# ADR 003 — Flujo visual y álbumes reales

La UI se divide en cinco pasos mantenidos en el ViewModel, sin añadir librería de navegación ni nuevas dependencias visuales de producción. Tokens de color, espacios, tipografía y formas viven en el tema. Fotografías y caras proceden de URIs autorizadas; no hay portadas, coincidencias ni búsquedas recientes inventadas.

Para ofrecer la cuadrícula de álbumes solicitada se incorpora MediaStore antes de terminar la calibración de reconocimiento pendiente en T10. Es una ampliación independiente: no cambia los modelos, el umbral ni la comparación. El índice Room e historial no se implementan en este incremento.

El permiso amplio de imágenes es opcional; acceso limitado se identifica y las cantidades se basan sólo en fotos visibles. La selección individual permanece sin permiso global. Nunca se usa una ruta física para obtener fotos. Clave de álbum: volumen + bucket ID, para aislar carpetas incluso con nombres idénticos. Se invalidan selecciones de álbum al refrescar acceso para evitar URIs obsoletas.

Transiciones finitas de 180 ms con APIs Compose, que respetan la duración de animación del sistema. Sin motion decorativo continuo. Check, texto y semántica refuerzan cada selección además del color. Texto escalable sin límites artificiales de líneas, celdas de una columna con fuente grande y acciones inferiores fuera del contenido desplazable.

Pruebas instrumentadas exclusivas de androidTest usan estados vacíos y un input sintético sin rostros; la prueba opcional real usa una muestra pública externa al repo, consulta dos álbumes temporales propios con igual nombre y ejecuta inferencia nativa. No hay inferencia simulada en producción. Las filas de MediaStore creadas por el test se eliminan en finally por su URI exacta.
