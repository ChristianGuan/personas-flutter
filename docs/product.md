# Personas — producto

La persona que conserva las fotografías quiere encontrar a un familiar en un conjunto concreto y compartir las fotos elegidas. Los destinatarios no instalan la app.

Flujo: referencia → tocar rostro → definir conjunto → buscar localmente → revisar → seleccionar → compartir mediante el sistema Android/iOS.

MVP: rostros múltiples, álbumes locales cuando el permiso lo permita, alternativa mediante selector, progreso/cancelación, cuadrícula y ampliación, selección múltiple, índice privado reutilizable y borrado de datos derivados. Nunca modificar originales.

Fuera de alcance: cuentas propias, sincronización automática de bibliotecas cloud, pagos, vídeos, reconocimiento en internet, destinatarios automáticos, filtro de persona sola y edición/limpieza de originales.

Entrega incremental actual: prueba técnica con selector del sistema (tandas acumulables sin máximo total de la app y alternativa desde Archivos), detección YuNet y reconocimiento SFace reales. Todavía no representa el MVP completo. Android 9/API 28 mínimo como supuesto reversible para usar ImageDecoder con orientación EXIF nativa.

Rediseño 0.2 (R14): cinco pasos claros, tema claro/oscuro cálido con acento índigo y fotografías reales protagonistas. Los álbumes locales ya se consultan mediante MediaStore con permiso opcional; se conserva selección individual sin permiso global. El índice y el historial siguen pendientes, por lo que no hay búsquedas recientes ficticias.

Incremento 0.3 (R16): referencias complementarias de la misma persona, confirmadas manualmente, para cubrir distintas poses e iluminaciones sin relajar el criterio de identidad. Se puede partir de una foto descartada, seleccionar su rostro y repetir sobre el mismo conjunto. Los ejemplos permanecen sólo durante la sesión; no implican entrenamiento del modelo ni historial persistente.

Incremento 0.4 (R17): fotografías de Google Fotos mediante el selector cloud de Android, configurado por el usuario, o Compartir → Personas. Se procesan localmente sólo las imágenes elegidas; los álbumes de nube se navegan en el proveedor y no se presentan como carpetas locales. Archivos permite también Google Drive si está disponible. La descarga requiere conexión del proveedor, sin añadir cuentas, credenciales ni servidor a Personas.

Incremento 0.5 (R18): búsqueda con parada después de encontrar una coincidencia válida, preparación anticipada acotada y reutilización de detecciones/embeddings de imágenes idénticas durante la sesión. Mantiene modelos, escalas, resolución y umbrales; una foto negativa debe comparar todas sus caras. La caché RAM se borra con la sesión y no equivale al índice persistente. La aceleración inicial depende de las fotos; las mediciones host no son una promesa de rendimiento del teléfono.

Incremento 0.6 (R19): filtro automático más estricto para reducir fotos de otras personas; casos dudosos separados en **Por revisar**, con confirmación/exclusión manual sin aprendizaje automático. Sólo las coincidencias aceptadas se seleccionan y comparten. La sesión recuerda la decisión para contenido idéntico de la misma persona. Una caché por bytes completos puede evitar decodificar en repeticiones, manteniendo comprobación de acceso/contenido y fallback cuando faltan datos. Calibración pública separada por sujetos, pendiente evaluación con álbum familiar real.

Corrección 0.6.1 (R20): lectura HEIC compartida por referencia, búsqueda y ampliación, con conversión de color y alternativa local si el lector Android falla. Conserva giros/espejos y los archivos originales. Los archivos incompletos o variantes no compatibles muestran error de lectura; no se consideran fotos de otra persona. Modelos y criterios de reconocimiento se conservan. Alcance y límites en ADR 008 y validación.

Incremento 0.7 (R21): migración a Flutter de interfaz y sesión para Android/iOS. Android reutiliza directamente el motor existente; iOS integra PhotoKit/PHPicker/ImageIO y OpenCV con los mismos ONNX/criterios. Conserva revisión manual, selección, permisos opcionales, nube mediante proveedores y compartir originales. La recepción en iOS usa una extensión con App Group y firma adecuados. Alcance, preparación y evidencia en `specs/002-flutter-migration/`, ADR 009 y la guía de `flutter_app/`; no implica evaluación de precisión familiar ni publicación en tiendas.

UI 0.7.1 (R22): lenguaje de tú, inicio «Encuentra tus mejores momentos», orientación por pasos y transiciones breves al elegir rostros/álbumes/fotos, cargar miniaturas y actualizar la selección. Aviso en álbumes/análisis: el primer escaneo puede tardar más y repetir las mismas fotos puede acelerar el reconocimiento durante la sesión. Conserva criterios y caché existentes, sin prometer aprendizaje, precisión creciente ni aceleración persistente. Respeta texto grande, tema oscuro y movimiento reducido.
