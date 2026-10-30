# Android 0.9.3 (20) — Interfaz y revisión de fotos

Entrega preparada el 30-10-2026 desde el árbol actual de `personas-flutter`, incluyendo todos los cambios pendientes de la app. Sustituye el AAB 19, que se compiló desde un checkout aislado y excluyó las ediciones locales de interfaz.

## Cambios incluidos

- Menú de acciones al terminar el escaneo y acceso flotante para volver a abrirlo; búsqueda de otra persona conservando el conjunto de fotos.
- Secciones de resultados plegables y selección/confirmación múltiple de fotos por revisar.
- Progreso con estimación de tiempo, indicación de desplazamiento y animaciones que respetan movimiento reducido.
- Carga de miniaturas próximas a la vista y caché en memoria con límites de bytes y entradas.
- Solicitud inicial de permiso de fotos al entrar en álbumes; se respeta una denegación anterior.
- Más detalle en los recortes de referencia de Android/iOS, sin modificar el motor de reconocimiento.
- Versión visible `0.9.3`, código Android `20`.

## Validación

- Flutter analyze: sin incidencias.
- Flutter: 90 pruebas aprobadas; una prueba opt-in de producción omitida.
- Android release: 33 pruebas JVM aprobadas.
- Herramientas de alineación: 3 pruebas Python aprobadas.
- Sintaxis Swift de los dos archivos modificados: aprobada. No se realizó compilación iOS en esta entrega.
- AAB firmado generado con la upload key existente. Bundletool validate, versión/nombre del manifiesto, URL HTTPS de producción y `PAGE_ALIGNMENT_16K`: aprobados.
- APK universal generado desde este AAB: firma comparada con la upload key, zipalign y comprobaciones ELF64 de 16 KB aprobadas. No se realizó una nueva prueba de instalación ni ejecución física/emulada en esta entrega.

```sh
PERSONAS_FLUTTER_SDK=/Users/christianguantiva/Desktop/IA_FOTOS/.tooling/flutter ./tools/flutter.sh build appbundle --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

## Artefactos locales

- AAB para Google Play: `.tooling/release-20/halladin-0.9.3-20.aab`.
- Salida de compilación: `flutter_app/build/app/outputs/bundle/release/app-release.aab`.
- APK universal de validación: `.tooling/release-20/halladin-0.9.3-20.apk`.
- SHA-256 AAB: `aa44558c232326103b959260bf57435bc19a82ea0a2acbe0457e6a47b05917d4`.
- SHA-256 APK: `1236a8412cbdc41e6bf5584f373d0923f7f15d731726071897fcfcc2c25202f2`.
- Certificado SHA-256: `c0e32c9d006af4c933853fb9fa70185a5057d4242389f9572db744b8f0e55780`.

Los artefactos, claves, cachés y logs permanecen fuera de Git. Se liberaron intermediarios regenerables por falta de espacio, conservando los AAB 19 y 20 y el material de firma.

Cargar la versión 20 en el canal de testers correspondiente y completar su lanzamiento/revisión en Play Console. No se realizó carga ni publicación en Google Play desde este entorno.

## Notas sugeridas

```text
<es-419>
Renovamos las acciones de resultados y la revisión de fotos. Añadimos confirmación múltiple, estimación de tiempo y mejoras en la carga de miniaturas y permisos de álbumes.
</es-419>
```
