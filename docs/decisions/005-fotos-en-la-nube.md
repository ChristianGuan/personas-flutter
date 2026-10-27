# ADR 005 — Google Fotos mediante acceso elegido por el usuario

El usuario necesita buscar también en fotografías guardadas en Google Fotos. MediaStore enumera imágenes locales autorizadas; instalar Google Fotos no convierte su biblioteca remota en carpetas locales ni concede acceso a la cuenta.

Se utiliza el Photo Picker de Android, ya integrado con AndroidX Activity: los proveedores cloud compatibles pueden entregar fotos y álbumes elegidos por el usuario. Añadimos una entrada explícita, guía de disponibilidad y apertura de ACTION_PICK_IMAGES_SETTINGS cuando existe la API/extensión necesaria, con mensaje y alternativa si falta actividad o acceso. No se fija EXTRA_LOCAL_ONLY, no se fuerza un paquete/proveedor ni se declara una conexión que no se ha comprobado.

La segunda vía es Compartir → Personas desde Google Fotos u otra galería. MainActivity recibe SEND/SEND_MULTIPLE image/* y reutiliza su tarea/ViewModel mediante singleTask y onNewIntent. Los URI deben ser content:// con autoridad; se validan extras, ClipData y MIME conocido en IO. No abrir rutas file://, URLs web ni datos de texto como imágenes. Los duplicados se fusionan por URI. Los grants son temporales y no se guardan credenciales, fotografías ni URI persistentes nuevos.

El usuario confirma antes de cambiar el conjunto o usar una única foto como referencia. Si el conjunto era un álbum local, se avisa de su sustitución. Una importación durante análisis queda pendiente, sin modificar el snapshot; tras terminar o cancelar se puede aceptar o descartar. El análisis y el compartir resultados continúan con el mismo pipeline/grants. Al volver del selector/configuración, se reconsulta el álbum local: se conserva si el conjunto autorizado sigue igual; si cambia, se invalidan los resultados, y ante pérdida de acceso o error se limpia el conjunto local. Las consultas siguen protegidas por generación.

No se implementa la Library API: la documentación vigente la limita a contenido creado por la aplicación. La Picker API HTTP requeriría proyecto OAuth/consentimiento; para Android con proveedor compatible el selector del sistema cubre este flujo sin claves, backend, dependencias nuevas ni INTERNET. Archivos conserva la vía SAF para Google Drive y otros proveedores disponibles.

Límites: el usuario selecciona el contenido, el proveedor puede limitar cada tanda y una foto remota puede necesitar conexión/descarga. La app no enumera ni sincroniza automáticamente toda la biblioteca de Google. Si falta el proveedor cloud, puede usarse Compartir → Personas o descargar previamente las fotografías. La disponibilidad/descarga real se verifica con la cuenta del usuario, separadamente de las pruebas locales de integración.

Fuentes oficiales consultadas el 2026-10-21:

- https://developer.android.com/training/data-storage/shared/photo-picker
- https://developer.android.com/reference/android/provider/MediaStore#ACTION_PICK_IMAGES_SETTINGS
- https://developer.android.com/training/sharing/receive
- https://developer.android.com/guide/topics/providers/document-provider
- https://developers.google.com/photos/overview/about
