#!/usr/bin/env python3
"""Install the pinned development SDK locally; never alter global SDKs or PATH."""
import hashlib
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VERSION = "3.47.7"
URL = f"https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_{VERSION}-stable.zip"
SHA256 = "dd9da574c3168460550117eb0e8dd0313ae934fabf64a82a6d557fff5fd1422e"


def main():
    sdk = ROOT / ".tooling/flutter"
    if (sdk / "bin/flutter").is_file():
        print(f"SDK local existente: {sdk}")
    else:
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            raise SystemExit("Este instalador fija macOS ARM64. Instala Flutter 3.47.7 oficial y configura PERSONAS_FLUTTER_SDK en otra plataforma.")
        sdk.parent.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="personas-flutter-") as directory:
            archive = Path(directory) / "flutter.zip"
            print(f"Descargando Flutter {VERSION}…", flush=True)
            urllib.request.urlretrieve(URL, archive)
            with archive.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hash_stream(stream)
            if digest != SHA256:
                raise SystemExit("SHA-256 incorrecto; no se extraerá el SDK.")
            subprocess.run(["ditto", "-x", "-k", str(archive), str(sdk.parent)], check=True)
    env = dict(os.environ, PUB_CACHE=str(ROOT / ".tooling/pub-cache"))
    subprocess.run([str(sdk / "bin/flutter"), "--disable-analytics"], env=env, check=True)
    subprocess.run([str(ROOT / "tools/flutter.sh"), "pub", "get"], env=env, check=True)


def hash_stream(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    main()
