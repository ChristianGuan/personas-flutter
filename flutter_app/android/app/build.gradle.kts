plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "co.local.personas"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    defaultConfig {
        applicationId = "co.local.personas"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        minSdk = 28
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    sourceSets.getByName("main") {
        java.srcDirs("../../native_android", "../../../app/src/main/java/co/local/personas/data", "../../../app/src/main/java/co/local/personas/domain")
        assets.srcDir("../../../app/src/main/assets")
        res.srcDir("../../../app/src/main/res")
    }
    sourceSets.getByName("test").java.srcDir("../../../app/src/test/java/co/local/personas/data")
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
