import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
val releaseSigningFile = rootProject.file("key.properties")
val releaseSigning = Properties()
if (releaseSigningFile.isFile) {
    releaseSigningFile.inputStream().use { releaseSigning.load(it) }
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        require(!releaseSigning.getProperty(key).isNullOrBlank()) {
            "Falta $key en android/key.properties. No se puede firmar release."
        }
    }
    require(rootProject.file(releaseSigning.getProperty("storeFile")).isFile) {
        "No existe el keystore configurado en android/key.properties."
    }
}
// Debug/IDE sync remain available without secrets. Release must never fall back to debug signing.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.path.startsWith(":app:") && it.name.contains("Release") }) {
        check(releaseSigningFile.isFile) {
            "Release requiere android/key.properties. Configura tu upload key con tools/setup_android_signing.py."
        }
    }
}
android {
    namespace = "co.local.personas"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    defaultConfig {
        applicationId = "co.local.personas"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        minSdk = 28
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (releaseSigningFile.isFile) {
            create("release") {
                storeFile = rootProject.file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        getByName("release") {
            if (releaseSigningFile.isFile) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    sourceSets.getByName("main") {
        java.srcDirs("../../native_android", "../../../app/src/main/java/co/local/personas/data", "../../../app/src/main/java/co/local/personas/domain")
        assets.srcDir("../../../app/src/main/assets")
        res.srcDir("../../../app/src/main/res")
    }
    sourceSets.getByName("test").java.srcDirs("../../../app/src/test/java/co/local/personas/data", "../../../app/src/test/java/co/local/personas/domain")
    sourceSets.getByName("androidTest").java.srcDir("../../../app/src/androidTest/java/co/local/personas/data")
    androidResources { noCompress += "onnx" }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
flutter { source = "../.." }
dependencies {
    // Keep debug runtime aligned with instrumentation: Flutter integration_test exports an older runner.
    debugImplementation("androidx.test:runner:1.6.2")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.opencv:opencv:4.12.0")
    implementation("io.github.awxkee:avif-coder:3.0.0:release@aar")
}
