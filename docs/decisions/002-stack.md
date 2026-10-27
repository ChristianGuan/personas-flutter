# ADR 002 — Stack y entrega incremental

Carpeta inicialmente vacía. Un módulo Android, sin backend, analítica ni permiso de internet. API mínima 28 para ImageDecoder; target/compile 35 disponible en el SDK local. JDK 21 instalado ejecuta Gradle; bytecode JVM 17.

Dependencias fijadas, sin versiones dinámicas: AGP 8.13.2 / Gradle 8.13 / Kotlin y plugin Compose 2.2.10; Compose BOM 2025.08.00; Activity 1.10.1; Lifecycle 2.9.2; coroutines 1.10.2; OpenCV 4.12.0; JUnit 4.13.2. Se prefieren versiones estables conocidas del conjunto, no se pretende usar siempre la última. La resolución/compilación valida su combinación.

Fuentes oficiales consultadas:
- https://developer.android.com/build/releases/agp-8-13-0-release-notes (Gradle 8.13, JDK mínimo 17, Build Tools 35).
- https://developer.android.com/jetpack/androidx/releases/compose-kotlin (Kotlin 2+ usa plugin Compose de la misma versión).
- https://developer.android.com/jetpack/compose/bom/bom-mapping
- https://developer.android.com/jetpack/androidx/releases/activity
- https://developer.android.com/jetpack/androidx/releases/lifecycle
- https://github.com/Kotlin/kotlinx.coroutines/releases/tag/1.10.2
- https://opencv.org/blog/opencv-4-12-0-is-now-available/

No persistir embeddings en la prueba técnica permite validar inferencia antes de adoptar Room. Índice, álbumes y permisos amplios quedan en T11/T12 después de T10; no reemplazarlos por implementaciones simuladas. El botón actual borra datos de sesión en memoria; no se presenta como borrado de un índice que todavía no existe.
