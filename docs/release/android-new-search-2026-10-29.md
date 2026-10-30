# Android 0.9.2 (18) — Nueva búsqueda desde Resultados

En Resultados aparece un botón fijo **Nueva búsqueda**, disponible también sin coincidencias o después de una búsqueda cancelada. Permite ir directamente a elegir una referencia sin retroceder por los pasos anteriores. Compartir selección continúa disponible por separado.

La acción limpia la sesión de búsqueda: referencia, ejemplos adicionales, álbum/fotos elegidas, resultados, selecciones y correcciones manuales. Utiliza la limpieza nativa existente para descartar el snapshot, referencias temporales y caché facial; conserva las fotos originales, permisos y preferencias de analítica. No activa otra búsqueda ni comparte fotos automáticamente.

Mientras se prepara la sesión se deshabilitan los botones para evitar acciones duplicadas. Si la limpieza nativa falla, se conserva el estado visible de Resultados y se informa del error. Una respuesta tardía de restauración de la sesión anterior no puede reemplazar la nueva búsqueda.

## Validación

- Analizador Flutter: sin incidencias.
- AAB firmado y validado con bundletool; versión 18 y URL HTTPS de producción verificadas. APK universal firmado, firmas comprobadas y compatibilidad estática de 16 KB aprobada (14 bibliotecas ELF64 y zipalign).
- Suite Flutter: 75 pruebas aprobadas; una prueba opt-in contra producción omitida.
- Pruebas añadidas: acceso desde resultados con/sin coincidencias tras desplazar la cuadrícula; pantalla de 320×640 con texto al 200 %; limpieza y navegación directa; doble toque durante limpieza; error nativo con conservación de resultados; snapshot anterior que llega después de empezar otra búsqueda.
- No se instaló esta versión en el teléfono: la instalación existente tiene otra firma. Actualizar desde Google Play conserva el camino de firma correspondiente.

## Compilar y distribuir

```sh
./tools/flutter.sh build appbundle --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

Subir `flutter_app/build/app/outputs/bundle/release/app-release.aab` como versión **0.9.2 (18)** en Prueba interna. La publicación en Play Console y la prueba final del flujo en el teléfono están pendientes.

SHA-256 AAB: `31265374c27894dc074cdee4e8b3b91a150c56b38c010b5da1451427d1f17b77`.

Notas sugeridas:

```text
<es-419>
Ahora puedes iniciar una nueva búsqueda directamente desde Resultados, sin retroceder por las pantallas anteriores. Esta versión también incluye las mejoras de reconocimiento de personas.
</es-419>
```
