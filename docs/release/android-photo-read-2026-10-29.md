# Android 0.9.2 (19) — Preparación de fotos

Se optimiza el lector sin modificar el reconocimiento: evita una lectura descartada de 8 MiB en archivos grandes conocidos, reserva buffers según longitud acotada y calcula el hash en la misma lectura. Decisión, alternativas medidas y límites: [ADR013](../decisions/013-primer-escaneo-android-medido.md).

La mejora del escaneo completo de la muestra real fue pequeña y no consistente entre rondas. No se presenta el 78,5 % del microbenchmark de lectura como mejora de búsqueda. Se mantienen los modelos, píxeles de entrada, resolución, escalas, umbrales y planificación de memoria previos.

## Validación y artefactos

- 33 pruebas JVM y 75 Flutter aprobadas; una prueba opt-in de producción omitida. Analizador Flutter sin incidencias.
- Prueba Android de píxeles/claves idénticos y cuatro contratos nativos originales de filtrado/caché aprobados, con todas sus fixtures y sin omisiones.
- Bundletool y firma del AAB aprobados; versión 19 y URL HTTPS de producción verificadas.
- APK universal firmado con el mismo certificado de entrega. Alineación de 16 KiB del bundle, 14 bibliotecas ELF64 y zipalign del APK aprobados. No se ejecutó un nuevo emulador 16 KiB en esta entrega.
- `Halladin Pruebas`, paquete `co.local.personas.pruebas`, actualizado en CPH2637 conservando datos/permisos. La variante final vuelve a la configuración release normal; la variante sin R8 sólo se usó para perfilado. La app original `co.local.personas` de Google Play permanece instalada por separado.

Archivos principales: `app/src/main/java/co/local/personas/data/Photos.kt`, nuevo `BoundedPhotoRead.kt`, sus pruebas y `flutter_app/pubspec.yaml`. El banco de pruebas de `tools/android_scan_benchmark` está fuera de la app publicada. No se incorporó ONNX Runtime al producto.

Se compiló desde un checkout aislado basado en `745d350` más estos cambios nativos y versión 19. Se preservaron ediciones locales pendientes de `main.dart` y sus pruebas; no se incluyeron en esta compilación ni en este commit.

```sh
./tools/flutter.sh build appbundle --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

AAB oficial: `flutter_app/build/app/outputs/bundle/release/app-release.aab`; copia local estable en `.tooling/scan-read-release/halladin-0.9.2-19.aab`. Cargar manualmente como **0.9.2 (19)** en Prueba interna. No se publicó en Play Console desde este entorno.

SHA-256 AAB: `48c91507f792786e928edac7fe8510997fd8c1203eec15ae5d5934f2406b7372`.

SHA-256 APK universal: `4cc29d9c767617a062a033a4366011ccffb50698ee6084b42bc1fada4830d7c7`.

Certificado SHA-256: `c0e32c9d006af4c933853fb9fa70185a5057d4242389f9572db744b8f0e55780`.

Notas sugeridas:

```text
<es-419>
Optimizamos la preparación de las fotos para evitar lecturas innecesarias y reducir trabajo antes del reconocimiento. Conservamos el análisis local y los criterios de coincidencia.
</es-419>
```
