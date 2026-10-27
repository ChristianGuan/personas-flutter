#!/usr/bin/env python3
"""Reproduce OpenCV 4.12 device/simulator slices inside ignored .tooling/."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
TOOLING = ROOT / ".tooling"
DEVICE_SHA = "86b42c9f141cd9169b91be2fc380b0e556a88a95c98ccc8e7aef8349ab74cf70"
SOURCE_SHA = "44c106d5bb47efec04e531fd93008b3fcd1d27138985c5baf4eafac0e1ec9e9d"
SOURCE_COMMIT = "49486f61fb25722cbcf586b7f4320921d46fb38e"


def download(url, destination, expected):
    print(f"Descargando {url}", flush=True)
    urllib.request.urlretrieve(url, destination)
    digest = hashlib.sha256()
    with destination.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise SystemExit("SHA-256 incorrecto; se detuvo la instalación.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", action="store_true", help="Añadir ARM64 de iPhone Simulator; requiere CMake 3.31.10 y Xcode.")
    args = parser.parse_args()
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = env.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    cmake = TOOLING / "cmake-python/cmake/data/bin"
    if cmake.is_dir():
        env["PATH"] = str(cmake) + os.pathsep + env["PATH"]
    TOOLING.mkdir(exist_ok=True)
    device = TOOLING / "opencv-ios/opencv2.framework"
    simulator = TOOLING / "opencv-simulator/opencv2.framework"
    with tempfile.TemporaryDirectory(prefix="personas-opencv-") as temporary:
        temp = Path(temporary)
        if not (device / "opencv2").is_file():
            archive = temp / "opencv-ios.zip"
            download("https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-ios-framework.zip", archive, DEVICE_SHA)
            device.parent.mkdir(exist_ok=True)
            # ditto preserves the framework's versioned symbolic links.
            subprocess.run(["ditto", "-x", "-k", str(archive), str(device.parent)], check=True, env=env)
        archs = subprocess.check_output(["xcrun", "lipo", "-archs", str(device / "opencv2")], env=env, text=True).split()
        if archs != ["arm64"]:
            thin = temp / "opencv2-arm64"
            subprocess.run(["xcrun", "lipo", str(device / "opencv2"), "-thin", "arm64", "-output", str(thin)], check=True, env=env)
            shutil.copyfile(thin, (device / "opencv2").resolve())
        if args.simulator and not (simulator / "opencv2").is_file():
            source = TOOLING / "opencv-4.12.0"
            if not (source / "CMakeLists.txt").is_file():
                archive = temp / "opencv-source.tar.gz"
                download("https://github.com/opencv/opencv/archive/refs/tags/4.12.0.tar.gz", archive, SOURCE_SHA)
                with tarfile.open(archive) as package:
                    # This exact hash is pinned above; reject unexpected paths too.
                    for member in package.getmembers():
                        path = Path(member.name)
                        if path.is_absolute() or ".." in path.parts:
                            raise SystemExit("Ruta de archivo inesperada.")
                    package.extractall(TOOLING)
            command = ["python3", str(source / "platforms/ios/build_framework.py"), str(simulator.parent),
                       "--build_only_specified_archs", "--iphonesimulator_archs", "arm64",
                       "--iphoneos_deployment_target", "16.0", "--legacy_build", "--disable-swift", "--disable-bitcode"]
            for module in ["highgui", "imgcodecs", "video", "videoio", "photo", "gapi", "ml", "stitching"]:
                command.extend(["--without", module])
            command.extend(["--disable", "OPENCL"])
            # The official builder uses every CPU by default. Bound compile
            # parallelism to avoid large compiler/swap peaks on small Macs.
            wrapper = "import multiprocessing,runpy,sys; multiprocessing.cpu_count=lambda:3; sys.argv=sys.argv[1:]; runpy.run_path(sys.argv[0],run_name='__main__')"
            subprocess.run(["python3", "-c", wrapper] + command[1:], check=True, env=env)
        output = temp / "opencv2.xcframework"
        command = ["xcrun", "xcodebuild", "-create-xcframework", "-framework", str(device)]
        if args.simulator:
            command.extend(["-framework", str(simulator)])
        subprocess.run(command + ["-output", str(output)], check=True, env=env)
        destination = TOOLING / "opencv-ios/opencv2.xcframework"
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(output, destination, symlinks=True)
    print(f"OpenCV listo: {destination}")


if __name__ == "__main__":
    main()
