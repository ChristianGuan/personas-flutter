# Personas en Flutter — 0.8.1+12

Aplicación compartida Android/iOS, en español, con cinco pasos y reconocimiento local real. El Android raíz sigue siendo la fuente del motor Kotlin y los modelos; ejecuta esta carpeta para usar la interfaz Flutter.

La actualización 0.7.1 usa trato de tú, inicio renovado, indicador de pasos y transiciones breves en selección, fotografías y barra inferior; respeta movimiento reducido. Antes y durante el análisis explica que el primer escaneo puede tardar más y repetir las mismas fotos puede ser más rápido durante la sesión. No implica aprendizaje ni un índice que sobreviva al cierre del proceso.

La versión 0.8.0 permite cambiar de app durante el análisis y solicita permiso para avisarte al terminar. Android mantiene un servicio con progreso real y acción de cancelar; la finalización permite banner por defecto y respeta canales bloqueados o personalizados. iOS 26+ solicita continuación del trabajo al sistema; si no la concede, o en versiones anteriores, el tiempo en segundo plano es limitado y la interfaz lo indica. iOS confirma el registro del aviso antes de liberar la tarea. Denegar notificaciones no impide buscar. El cierre forzado o la interrupción del sistema pueden detener el trabajo; se conservan resultados parciales, sin anunciarlos como un análisis completado. Consulta [ADR 010](../docs/decisions/010-analisis-en-segundo-plano.md).

La versión 0.8.1 permite cancelar la preparación de fotos/referencias en iPhone desde «Cancelar carga» o Volver. La preparación nativa y cada importación tras cerrar el selector tienen un plazo de 90 segundos; elegir fotos en el selector no tiene ese límite. Al fallar, cancelar o agotar el plazo se puede reintentar conservando la referencia anterior. Las respuestas tardías quedan aisladas por petición. El análisis de álbumes mantiene su cancelación y ciclo de vida propios.

## Preparación

Desde la raíz del repositorio, en macOS ARM64:

```sh
python3 tools/setup_flutter.py
python3 tools/models.py --check
tools/flutter.sh doctor -v
tools/flutter.sh analyze
tools/flutter.sh test
```

El instalador comprueba el SHA-256 de Flutter 3.47.7 estable y usa `.tooling/`, sin modificar PATH. Otra instalación compatible puede seleccionarse con `PERSONAS_FLUTTER_SDK`. Dart viene con Flutter. VS Code: instala las extensiones Dart/Flutter y selecciona `.tooling/flutter` como SDK; el punto de entrada es `flutter_app/lib/main.dart`.

## Android

Requiere JDK 17/21, Android SDK 36, platform-tools y licencias aceptadas. `flutter_app/android/local.properties` se genera localmente; no se versiona. Flutter/Gradle instala NDK 28.2.13676358 y CMake 3.22.1 cuando son necesarios. Reserva espacio suficiente para SDK y compilaciones (al menos 10 GB libres para una instalación nueva).

```sh
tools/flutter.sh devices
tools/flutter.sh run -d ID_ANDROID
tools/flutter.sh build apk --debug --target-platform android-arm64
adb install -r flutter_app/build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n co.local.personas/co.local.personas.flutter.MainActivity
```

Mínimo Android 9/API 28. Mantener `co.local.personas` y la firma permite actualizar la app anterior. Para actualizar instalaciones debug usa el APK sin `--split-per-abi`: Gradle asigna otros códigos de versión a los APK divididos. Una firma o versión incompatible requiere resolver la instalación antes de ejecutar Flutter, que puede ofrecer reinstalarla. Fotos originales no se modifican. El último análisis se guarda en caché privada para recuperarlo al volver o tocar el aviso; los embeddings y la caché de reconocimiento siguen sólo en RAM.

## iPhone y simulador

Instala y abre Xcode completo, acepta su licencia y descarga el runtime iOS del simulador. El wrapper usa `/Applications/Xcode.app/Contents/Developer` sin cambiar globalmente `xcode-select`. iOS mínimo 16; simulador soportado por este paquete: ARM64 (Mac Apple Silicon).

```sh
# Sólo para preparar el motor: CMake local, sin instalar paquetes globales.
python3 -m pip install cmake==3.31.10 --target .tooling/cmake-python --no-compile
python3 tools/setup_opencv_ios.py --simulator
tools/flutter.sh build ios --simulator --debug
tools/flutter.sh devices
tools/flutter.sh run -d ID_SIMULADOR

# Comprobación de compilación para iPhone, sin instalar ni distribuir:
tools/flutter.sh build ios --debug --no-codesign
```

El proyecto Xcode ya está configurado. Si cambias fuentes nativas o necesitas regenerar su configuración, instala `xcodeproj` 1.27.0 en un entorno Ruby local y ejecuta `tools/configure_ios.rb` (en este Mac: `GEM_PATH="$PWD/.tooling/gems" ruby tools/configure_ios.rb`). No requiere CocoaPods: usa la integración Swift Package Manager del SDK Flutter.

Para un iPhone físico abre `flutter_app/ios/Runner.xcworkspace`, selecciona tu equipo de firma en Runner y PersonasShare, configura identificadores que pertenezcan a ese equipo y registra el mismo App Group en ambos targets (`PERSONAS_APP_GROUP`). Conecta y autoriza el iPhone, activa su modo de desarrollador y ejecuta desde Xcode o Flutter. Una compilación sin firma no se instala en el teléfono. La recepción desde Google Fotos y otras apps necesita la capacidad App Groups; compilar no valida esa recepción con una cuenta real.

Para dejar una versión que abra desde el icono sin depurador, usa Release. Una vez creados los certificados y perfiles en Xcode, desde la raíz define `PERSONAS_TEAM_ID` y `PERSONAS_IPHONE_ID` sólo en tu terminal y ejecuta:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PUB_CACHE="$PWD/.tooling/pub-cache"
tools/flutter.sh build ios --config-only --release --no-codesign --target lib/main.dart
xcrun xcodebuild -workspace flutter_app/ios/Runner.xcworkspace \
  -scheme Runner -configuration Release -destination "id=$PERSONAS_IPHONE_ID" \
  -derivedDataPath flutter_app/build/iphone \
  "DEVELOPMENT_TEAM=$PERSONAS_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  FLUTTER_BUILD_MODE=release FLUTTER_TARGET=lib/main.dart build
codesign --verify --deep --strict flutter_app/build/iphone/Build/Products/Release-iphoneos/Runner.app
xcrun devicectl device install app --device "$PERSONAS_IPHONE_ID" \
  flutter_app/build/iphone/Build/Products/Release-iphoneos/Runner.app
xcrun devicectl device process launch --device "$PERSONAS_IPHONE_ID" \
  --terminate-existing co.local.personas
```

Si la consola indica `missing Xcode-Username`/`No Accounts` incluso con la sesión renovada, comprueba la firma compilando primero desde la interfaz de Xcode: en este Mac esa vía creó correctamente el certificado y los dos perfiles; después la compilación Release de consola pudo usar los perfiles locales. No borres el llavero. Si Xcode informa que el certificado del desarrollador no es de confianza, autoriza tu cuenta en Configuración del iPhone → General → VPN y gestión de dispositivos antes de reintentar la apertura. El perfil personal de la instalación comprobada caduca el 30 de octubre de 2026; habrá que renovar la firma. No se guardan Team ni UDID personales en el proyecto.

## Regresiones con fotos públicas

`test/` cubre sesión, feedback, cancelación, carreras, permisos, más de 30 fotos, nueve opciones de rostro, texto al 200 % y estados vacíos. También cubre la selección cloud pendiente y el borrado de resultados durante una transición. Sus dobles son exclusivos de tests. `integration_test/migration_test.dart` usa los adaptadores y modelos nativos reales.

`ios/Tests/PhotoPreparationTests.swift` comprueba cancelación, plazo, respuesta única y reintento sin depender de Photos/iCloud. Desde macOS puede ejecutarse con `xcrun swiftc -parse-as-library flutter_app/ios/Runner/PhotoPreparation.swift flutter_app/ios/Tests/PhotoPreparationTests.swift -o /tmp/personas-photo-preparation-tests` y `/tmp/personas-photo-preparation-tests`. `integration_test/reference_recovery_test.dart` se ejecuta en simulador iOS con el puente real: al comenzar la prueba, copia sólo `face-10bit.heic` pública a `Library/Caches/PersonasSession/qa-reference-recovery/` y crea allí el archivo `ready`. Comprueba cancelación, cancelación obsoleta, nueva detección y preview HEIC; retira únicamente sus copias públicas. El protocolo iOS de `pick`/`reference` incluye `requestId`, usado por `cancelPreparation` para no cancelar una petición posterior.

Prepara los juegos públicos con `tools/prepare_heic_qa.py` y `tools/prepare_recognition_qa.py` (consulta `--help` para rutas/entorno). No uses fotografías personales en estas carpetas. El test trabaja con 50 entradas: seis variantes HEIC de Lena más 40 alias idénticos, Messi/David, una imagen sin rostro y un archivo roto. Los alias comprueban selección y caché, no equivalen a 46 fotografías independientes para evaluar precisión.

```sh
# Primero instala un APK debug con el mismo código/firma; carga sólo caché QA.
python3 tools/prepare_flutter_qa.py --android /ruta/al/adb
PERSONAS_QA_OUTPUT=/tmp/personas-flutter-android tools/flutter.sh drive \
  --keep-app-running --driver test_driver/integration_test.dart \
  --target integration_test/migration_test.dart -d ID_ANDROID
```

En iOS, inicia el mismo `drive` con el ID del simulador. Durante los dos minutos de espera inicial, obtén el contenedor mediante `xcrun simctl get_app_container ID_SIMULADOR co.local.personas data` y ejecuta `python3 tools/prepare_flutter_qa.py --ios-container RUTA_CONTENEDOR`. El test borra explícitamente su sesión antes de esperar las fotos: carga después de que exista `Library/Caches/PersonasSession`. No se añade ninguna API de fixtures a producción. Las capturas se guardan fuera del repositorio.

`integration_test/background_probe.dart` es una entrada QA separada para probar el ciclo de vida sin un driver que mantenga activa la app. Compílala como target y espera `phase: waiting-fixtures` en `cache/background-probe.json` (Android) o `Library/Caches/background-probe.json` (iOS). Usa el preparador con `--background` y un Python que tenga Pillow: añade 320 variantes públicas distintas a las 50 fotos anteriores. Al aparecer `running`, abre Ajustes; comprueba checkpoints y finalización en `personas-last-analysis.json` (Android) o `PersonasLastAnalysis.json` (iOS). Vuelve a Personas y crea el archivo `compare` dentro de `qa-flutter`: compara todas las decisiones con una repetición en primer plano. Tras `complete`, relanza el proceso para comprobar recuperación sin handles de rostro válidos. `--dart-define=PERSONAS_QA_SKIP_NOTIFICATIONS=true` omite únicamente la solicitud de permiso de esta entrada QA y permite comprobar denegación; nunca cambia permisos del sistema. `--dart-define=PERSONAS_QA_CANCEL=true` cancela tras al menos 25 fotos y registra el estado parcial. La prueba espera una app visible para iniciar; desbloquea el teléfono. Obtén de nuevo la ruta del contenedor iOS después de cada instalación, ya que puede cambiar. Instala al finalizar el target normal `lib/main.dart`.

## Código y límites

Pantallas: `lib/main.dart`; tema/movimiento: `lib/app_theme.dart`; componentes y aviso del escaneo: `lib/ui_components.dart`; fotografías acotadas: `lib/photo_widgets.dart`; sesión: `lib/search_controller.dart`; protocolo: `lib/native_bridge.dart`. Android: `native_android/`; iOS: `ios/Runner/` y `ios/ShareExtension/`. Modelos y licencias: assets Android existentes, enlazados en ambas plataformas.

SDD: [especificación](../specs/002-flutter-migration/spec.md), [plan](../specs/002-flutter-migration/plan.md), [tareas](../specs/002-flutter-migration/tasks.md), [ADR 009](../docs/decisions/009-migracion-flutter.md), [validación](../docs/validation.md).

Faltan evaluación de precisión con álbumes familiares reales, índice persistente e historial. Los proveedores cloud requieren red y disponibilidad del proveedor; los álbumes de nube se eligen en el selector, no aparecen como carpetas locales propias. La migración conserva pesos y criterios, pero no promete idénticas decisiones de todos los decodificadores/dispositivos ni mayor velocidad por usar Flutter.

## Analítica opcional

Desactivada por defecto, cola SQLite y sincronización con API propia sin enviar fotos ni datos faciales. Configurar `--dart-define=ANALYTICS_API_URL=https://...`; no incluir claves administrativas. Ver [privacidad y ejecución](../docs/analytics-privacy.md), [Backend](https://github.com/ChristianGuan/personas-api-dashboard/blob/main/Backend/README.md) y [SDD](../specs/003-optional-analytics/spec.md).

## URL de la API y configuración local

Edita `flutter_app/.env` para cambiar la URL base de todos los endpoints de analítica:

```dotenv
ANALYTICS_API_URL=https://tu-dominio-o-tunel
```

Si el archivo no existe, copia `.env.example` a `.env`. `tools/flutter.sh run` y `tools/flutter.sh build` cargan este archivo automáticamente; la configuración de ejecución de VS Code también lo carga. Ejemplos desde la raíz del repositorio:

```sh
./tools/flutter.sh run -d <device-id>
./tools/flutter.sh build apk --debug
```

Con Flutter directamente, añade `--dart-define-from-file=.env` desde `flutter_app/`. Al cambiar la URL es necesario recompilar/reiniciar la ejecución; hot reload no actualiza estos valores. Los Quick Tunnels cambian de URL al recrearlos. `.tooling/public-api.env` es una referencia auxiliar; la fuente usada para compilar la app es `flutter_app/.env`.

La BD se configura en `Backend/.env` del repositorio independiente `personas-api-dashboard`: `DATABASE_URL` para Node; `POSTGRES_DB`, `POSTGRES_USER` y `POSTGRES_PASSWORD` para Docker. `HOST` y `PORT` definen la API local y `ADMIN_TOKEN` protege las métricas. Nunca copies credenciales de BD ni el token administrador al `.env` de Flutter, porque sus valores se incluyen en el binario. Los archivos `.env` están ignorados por Git.
