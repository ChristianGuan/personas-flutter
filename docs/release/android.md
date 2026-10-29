# Preparación Android para Google Play

Configuración preparada el 28-10-2026 en el repositorio `personas-flutter`. No implica aprobación de Google Play ni publicación.

## Configuración

- `compileSdk=36`, `targetSdk=36`, `minSdk=28`.
- Firma release desde `flutter_app/android/key.properties`; ninguna contraseña está en Gradle.
- Un build release sin ese archivo falla explícitamente; debug y sincronización de IDE siguen disponibles.
- `key.properties` y los keystores están ignorados por Git. `key.properties.example` documenta el formato sin secretos.

## Upload key

Antes de la primera publicación, para crear una identidad nueva:

```sh
python3 tools/setup_android_signing.py --create
```

Crea `.tooling/signing/personas-upload.jks` y `flutter_app/android/key.properties`, con permisos 600. No imprime las contraseñas. **Se niega a reemplazar archivos existentes.** Si la app ya existe en Play, usar la upload key registrada, no generar otra por perder la configuración local.

La clave y el archivo de propiedades generados son material local de custodia: respaldar ambos en una bóveda cifrada bajo control del titular antes de cargar a Play. El ejemplo de subject `Personas Upload Key` es una etiqueta técnica, no una certificación de identidad empresarial. No se registró todavía la clave con Play App Signing ni se creó una cuenta de tienda.

## Build y comprobaciones

Configurar en `flutter_app/.env` la URL HTTPS de producción antes del build definitivo. El helper incluye esa URL en el binario; no hay credenciales administrativas en ese archivo.

```sh
./tools/flutter.sh test
./tools/flutter.sh build appbundle --release
python3 tools/check_android_pages.py flutter_app/build/app/outputs/bundle/release/app-release.aab --output flutter_app/build/release-check-aab.json
python3 -m unittest discover -s tools/tests -v
```

El comprobador inspecciona los segmentos `PT_LOAD` de cada ELF64 y exige alineación compatible con 16 KB. Para APK también verifica offsets ZIP de las librerías sin comprimir. Los binarios de 32 bits se enumeran, pero la condición de 16 KB se aplica a 64 bits. Un archivo sin librerías ELF64 no pasa accidentalmente el control.

El AAB requiere comprobar además `BundleConfig` y los APK generados. Con bundletool oficial:

```sh
java -jar /ruta/bundletool-all.jar validate --bundle=flutter_app/build/app/outputs/bundle/release/app-release.aab
java -jar /ruta/bundletool-all.jar dump config --bundle=flutter_app/build/app/outputs/bundle/release/app-release.aab
```

Debe indicar `PAGE_ALIGNMENT_16K`. Generar un APK desde el AAB con bundletool y la upload key, usando entrada de contraseñas segura (archivo temporal con permisos 600, nunca argumento `pass:...` ni un log). Después comprobar ese APK con `check_android_pages.py`, `zipalign -c -P 16 -v 4` y `apksigner verify --verbose --print-certs`. Comparar el SHA-256 del certificado con el de la upload key.

## Prueba en dispositivo

```sh
adb -s <serial> shell getconf PAGE_SIZE
adb -s <serial> shell getprop ro.build.version.sdk
```

Para demostrar ejecución 16 KB, `PAGE_SIZE` debe ser **16384**. Si devuelve 4096, solo es una prueba en 4 KB. No cambiar propiedades del sistema ni reiniciar un teléfono personal para forzar un modo sin confirmar soporte.

Probar con un entorno 16 KB: arranque de build release, lectura/decodificación de JPEG y HEIF, carga de OpenCV, inferencia, caché, segundo plano y cancelación. La alineación estática y la firma no sustituyen esta prueba.

No instalar el APK firmado con upload key encima de una instalación debug de distinto certificado. Android lo rechazará; no desinstalar automáticamente porque se perdería el estado local. Usar un dispositivo/emulador de pruebas separado o decidir explícitamente cómo preservar los datos.

## Fuentes

- [Target API](https://developer.android.com/google/play/requirements/target-sdk).
- [Compatibilidad de páginas 16 KB](https://developer.android.com/guide/practices/page-sizes).
- [Firma y publicación Flutter Android](https://docs.flutter.dev/deployment/android).
- [Bundletool oficial](https://github.com/google/bundletool/releases).

## Resultado de ejecución

[Prueba en emulador oficial API 36 con páginas de 16 KB](android-emulator-16kb-2026-10-28.md): arranque y búsqueda release aprobados; 6 pruebas nativas adicionales aprobadas.
