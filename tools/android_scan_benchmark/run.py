#!/usr/bin/env python3
"""Public-fixture benchmarks; explicit opt-in can profile an inactive authorized selection."""
import argparse,json,os,shutil,subprocess,tempfile
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture',required=True,type=Path,help='Public AT&T s01-01.png prepared in /tmp; packaged only in test APK')
    parser.add_argument('--allow-album',action='store_true',help='Explicitly allow profiling the inactive selection in a matching unminified .pruebas build')
    parser.add_argument('--device',help='Explicit adb serial; omit to build only')
    parser.add_argument('--test',choices=['DetectorThroughputTest','MixedInferenceTest','PhotoReadOptimizationTest','OrtSfaceProbeTest','AlbumReadProfile','FilteringRegressionTest'],default='MixedInferenceTest')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2];out=root/'.tooling/android-scan-benchmark';project=out/'project';app=project/'app'
    fixture=args.fixture.resolve(strict=True)
    album=args.test=='AlbumReadProfile'
    if album and not args.allow_album:parser.error('Album profiling requires --allow-album and an unminified development build')
    sdk=Path(os.environ.get('ANDROID_HOME',Path.home()/'Library/Android/sdk'))
    env={**os.environ,'ANDROID_HOME':str(sdk)}
    java=Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home')
    if 'JAVA_HOME' not in env and java.is_dir():env['JAVA_HOME']=str(java)
    def kotlin_path(p):return json.dumps(str(p)).replace('$','\\$')
    project.mkdir(parents=True,exist_ok=True)
    (project/'settings.gradle.kts').write_text('''pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
plugins { id("com.android.application") version "8.13.2" apply false; id("org.jetbrains.kotlin.android") version "2.2.20" apply false }
rootProject.name="HalladinScanBenchmark"
include(":app")
''')
    (project/'gradle.properties').write_text('android.useAndroidX=true\norg.gradle.jvmargs=-Xmx1536m\n')
    main_src=app/'src/main/java/shared';main_src.mkdir(parents=True,exist_ok=True)
    for old in main_src.glob('*.kt'):old.unlink()
    for name in ['data/OpenCvFaces.kt','data/AnalysisCache.kt','data/ContentHash.kt','domain/Search.kt','domain/FaceDetections.kt','data/Photos.kt','data/BoundedPhotoRead.kt','data/SoftwarePhoto.kt','data/HeifFallback.kt','data/HeifOrientation.kt','data/BatchPhotoSearch.kt']:
        link=main_src/Path(name).name
        if link.is_symlink():link.unlink()
        link.symlink_to(root/'app/src/main/java/co/local/personas'/name)
    if album:
        for name in ['AlbumReadProfileInstrumentation.kt','LegacyContentPhotos.kt','ParallelPrepareSearch.kt']:shutil.copy2(Path(__file__).parent/name,main_src/name)
    test_src=app/'src/androidTest/java/co/local/personas/flutter';test_src.mkdir(parents=True,exist_ok=True)
    for old in test_src.glob('*.kt'):old.unlink()
    for file in Path(__file__).parent.glob('*.kt'):
        if file.name.startswith('Ort') and args.test!='OrtSfaceProbeTest':continue
        if file.name.startswith('Filtering') and args.test!='FilteringRegressionTest':continue
        shutil.copy2(file,test_src/file.name)
    if args.test=='FilteringRegressionTest':
        shutil.copy2(root/'app/src/androidTest/java/co/local/personas/data/FilteringTest.kt',test_src/'FilteringTest.kt')
    assets=app/'src/androidTest/assets';assets.mkdir(parents=True,exist_ok=True);shutil.copy2(fixture,assets/'face.png')
    if args.test=='FilteringRegressionTest':
        qa=assets/'qa-filter';qa.mkdir(exist_ok=True)
        for photo in fixture.parent.glob('s??-??.png'):shutil.copy2(photo,qa/photo.name)
    (app/'src/main/AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="Halladin Scan Benchmark" android:allowBackup="false"/>'+ ('<instrumentation android:name="co.local.personas.speedbench.AlbumReadProfileInstrumentation" android:targetPackage="co.local.personas.pruebas"/>' if album else '')+'</manifest>')
    (app/'build.gradle.kts').write_text('''plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
 namespace="co.local.personas.speedbench";compileSdk=36
 defaultConfig {applicationId="co.local.personas.speedbench";minSdk=28;targetSdk=36;testInstrumentationRunner="androidx.test.runner.AndroidJUnitRunner";ndk {abiFilters += "arm64-v8a"}}
 compileOptions {sourceCompatibility=JavaVersion.VERSION_17;targetCompatibility=JavaVersion.VERSION_17}
 sourceSets.getByName("main").assets.srcDir(MODELS)
}
kotlin {compilerOptions {jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)}}
dependencies {implementation("org.opencv:opencv:4.12.0");implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2");implementation("io.github.awxkee:avif-coder:3.0.0:release@aar");androidTestImplementation("androidx.test:runner:1.6.2");androidTestImplementation("androidx.test.ext:junit:1.2.1")}
'''.replace('MODELS',kotlin_path(root/'app/src/main/assets')).replace('dependencies {','dependencies {implementation("com.microsoft.onnxruntime:onnxruntime-android:1.31.1");' if args.test=='OrtSfaceProbeTest' else 'dependencies {'))
    def run(command,log):
        result=subprocess.run(list(map(str,command)),cwd=root,env=env,capture_output=True,text=True)
        (out/log).write_text(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError(f'{log}: command failed; see local log')
        return result.stdout
    run([root/'flutter_app/android/gradlew','-p',project,':app:assembleDebug']+([] if album else [':app:assembleDebugAndroidTest']),'build.log')
    if not args.device:
        print(f'APKs prepared in {app}/build/outputs/apk');return
    apk=app/'build/outputs/apk/debug/app-debug.apk'
    if album:
        props={k.strip():v.strip() for line in (root/'flutter_app/android/key.properties').read_text().splitlines() if '=' in line and not line.startswith('#') for k,v in [line.split('=',1)]}
        ks=(root/'flutter_app/android'/props['storeFile']).resolve()
        signed=out/'album-benchmark.apk'
        with tempfile.TemporaryDirectory(prefix='halladin-sign-') as td:
            for name,key in [('store','storePassword'),('key','keyPassword')]:
                fd=os.open(td+'/'+name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
                with os.fdopen(fd,'w') as f:f.write(props[key])
            run([sdk/'build-tools/36.0.0/apksigner','sign','--ks',ks,'--ks-key-alias',props['keyAlias'],'--ks-pass','file:'+td+'/store','--key-pass','file:'+td+'/key','--out',signed,apk],'sign.log')
        apk=signed
    adb=[sdk/'platform-tools/adb','-s',args.device]
    packages=['co.local.personas.speedbench.test','co.local.personas.speedbench']
    # Dedicated disposable packages; never installs/replaces co.local.personas or .pruebas.
    try:
        run(adb+['install','-r','-t','--no-incremental',apk],'install-app.log')
        if album:
            services=run(adb+['shell','dumpsys','activity','services','co.local.personas.pruebas'],'preflight.log')
            if 'isForeground=true' in services:raise RuntimeError('Do not interrupt an active scan')
            output=run(adb+['shell','am','instrument','-w','-e','localBenchmark','true','co.local.personas.speedbench/co.local.personas.speedbench.AlbumReadProfileInstrumentation'],'device-profile.log')
        else:
            run(adb+['install','-r','-t','--no-incremental',app/'build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'],'install-tests.log')
            output=run(adb+['shell','am','instrument','-w','-r','-e','class','co.local.personas.flutter.'+args.test,'-e','localBenchmark','true','-e','filterFixtures','qa-filter','-e','faceFixture','qa-filter/s01-01.png',packages[0]+'/androidx.test.runner.AndroidJUnitRunner'],'device-profile.log')
        if ('INSTRUMENTATION_CODE: -1' if album else 'OK (1 test)') not in output:raise RuntimeError('Benchmark failed; see device-profile.log')
        if 'AssumptionViolatedException' in output or 'INSTRUMENTATION_STATUS_CODE: -4' in output:raise RuntimeError('Benchmark skipped; required fixtures missing')
        for line in output.splitlines():
            if ': metrics=' in line:
                report=json.loads(line.split('metrics=',1)[1]);(out/'metrics.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
    finally:
        for package in packages:
            subprocess.run(list(map(str,adb+['uninstall',package])),env=env,capture_output=True)

if __name__=='__main__':main()
