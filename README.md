# Halladin · Flutter

App Android/iOS de búsqueda local de fotografías por persona. Repositorio independiente de [la API y el dashboard](https://github.com/ChristianGuan/personas-api-dashboard). El reconocimiento y las fotos permanecen en el teléfono; la analítica requiere consentimiento.

## Estructura

- `flutter_app/`: app Flutter, plataformas nativas y pruebas.
- `app/src/main/java/co/local/personas/data/` y `domain/`: motor Android compartido que compila el módulo Flutter.
- `app/src/main/assets/` y `res/`: modelos, licencias y recursos nativos.
- `tools/`: preparación de Flutter, modelos y OpenCV iOS.
- `docs/` y `specs/`: diseño y contratos de privacidad.

Estas carpetas forman parte de este mismo repositorio. No es necesario descargar código desde el repositorio de la API.

## Preparación

Instala Flutter compatible con Dart >=3.11 y las herramientas de Android/iOS. El helper busca Flutter en `.tooling/flutter`, en `PERSONAS_FLUTTER_SDK` o en el PATH.

```sh
cp flutter_app/.env.example flutter_app/.env
./tools/flutter.sh pub get
./tools/flutter.sh run -d <device-id>
```

Configura la dirección del backend en `flutter_app/.env`:

```dotenv
ANALYTICS_API_URL=https://tu-api
```

El helper y VS Code cargan este archivo al compilar. Si cambia la URL, recompila la app. Un archivo vacío deja la analítica sin transporte; nunca se incluyen `DATABASE_URL`, contraseñas ni `ADMIN_TOKEN` en Flutter. En teléfonos físicos se necesita HTTPS accesible desde el dispositivo; `127.0.0.1` del teléfono no corresponde al Mac.

Para iOS, prepara OpenCV con `python3 tools/setup_opencv_ios.py`; configura tu equipo de firma en Xcode. El proyecto referencia el framework local en `.tooling/opencv-ios/` y los modelos del propio repositorio. Consulta [la guía de Flutter](flutter_app/README.md) para detalles nativos.

## Validación

```sh
./tools/flutter.sh test
./tools/flutter.sh build apk --debug
./tools/flutter.sh build ios --release --no-codesign
```

Las pruebas Android instrumentadas necesitan un dispositivo/emulador. `.env`, SDKs, dependencias descargadas y resultados de compilación no se versionan.

Separado desde `busqueda_fotos_app`, commit móvil `2d91909`. El historial del repositorio anterior permanece disponible como referencia.

## Preparación Android para tienda

Ver [firma release, target SDK 36 y validación de 16 KB](docs/release/android.md). La upload key y `key.properties` son locales, no se suben a Git. La alineación estática no sustituye una prueba de ejecución en un dispositivo de 16 KB.

Ver también [pruebas funcionales y privacidad Android](docs/release/android-functional-privacy-2026-10-28.md): permisos release, segundo plano, cancelación y sincronización con API aislada.

La [prueba de interrupción activa y recuperación del 29-10](docs/release/android-active-interruption-2026-10-29.md) está aprobada en una nueva release QA; conserva el último checkpoint cada 25 fotos.
