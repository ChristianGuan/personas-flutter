#!/usr/bin/env python3
"""Copy existing PUBLIC HEIC/recognition QA fixtures into the test app cache."""
import argparse
import io
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--android", metavar="ADB")
    destination.add_argument("--ios-container", type=Path)
    parser.add_argument("--heic", type=Path, default=Path("/tmp/personas-heic-qa"))
    parser.add_argument("--recognition", type=Path, default=Path("/tmp/personas-qa-repro"))
    parser.add_argument("--background", action="store_true", help="Add 320 distinct public-image variants so a real background transition can be measured")
    args = parser.parse_args()
    fixtures = {name: args.heic / name for name in ["face-srgb.HEIC", "face-10bit.heic", "face-p3.heic", "face-p3-10bit.heic", "face-rotated-10bit.heic", "face-mirrored-10bit.heic", "blank.heic", "broken.heic"]}
    fixtures.update({f"batch-{i:02d}.heic": args.heic / "face-srgb.HEIC" for i in range(40)})
    # HEIC reference is Lena. Recognition QA's negative-1 is ALSO Lena,
    # so use David instead; both negatives must be different identities.
    fixtures.update({"negative-0.jpg": args.recognition / "negative-0.jpg",
                     "negative-1.jpg": args.recognition / "ref-front.jpg"})
    if args.background:
        from PIL import Image, ImageEnhance
        source = args.recognition / "negative-1.jpg"  # pinned public OpenCV Lena
        if hashlib.sha256(source.read_bytes()).hexdigest() != "7de7ed51a1594fff247f4cae2301eceacf5313d6011e37b4a4c8733f7bb72c07":
            raise SystemExit("La fuente de variantes debe ser la muestra pública fijada de OpenCV.")
        folder = Path("/tmp/personas-background-qa"); folder.mkdir(exist_ok=True)
        image = Image.open(source).convert("RGB")
        for i in range(320):
            # Different decoded pixels and encoded hashes; preserve the identity.
            variant = ImageEnhance.Brightness(image).enhance(.85 + (i % 80) / 260)
            variant = ImageEnhance.Color(variant).enhance(.9 + (i // 80) / 15)
            name = f"background-{i:03d}.jpg"
            variant.save(folder / name, quality=92)
            fixtures[name] = folder / name
    for source in fixtures.values():
        if not source.is_file():
            raise SystemExit(f"Falta QA pública: {source}. Ejecuta prepare_heic_qa.py y prepare_recognition_qa.py; nunca uses fotos personales aquí.")
    if args.android:
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w") as archive:
            for name, source in fixtures.items():
                archive.add(source, arcname="qa-flutter/" + name)
            marker = tarfile.TarInfo("qa-flutter/ready"); marker.size = 0; archive.addfile(marker)
            if args.background:
                marker = tarfile.TarInfo("qa-flutter/background-ready"); marker.size = 0; archive.addfile(marker)
        subprocess.run([args.android, "shell", "run-as", "co.local.personas", "mkdir", "-p", "cache"], check=True)
        subprocess.run([args.android, "shell", "run-as", "co.local.personas", "tar", "xf", "-", "-C", "cache"], input=data.getvalue(), check=True)
    else:
        # Run after the QA entrypoint explicitly clears its private session.
        if not (args.ios_container / "Library/Caches/PersonasSession").is_dir():
            raise SystemExit("Inicia primero el test iOS y espera a que cree PersonasSession.")
        folder = args.ios_container / "Library/Caches/PersonasSession/qa-flutter"
        folder.mkdir(exist_ok=True)
        for name, source in fixtures.items():
            shutil.copyfile(source, folder / name)
        (folder / "ready").touch()
        if args.background:
            (folder / "background-ready").touch()
    print(f"Preparadas {len(fixtures)} fotos públicas para la prueba Flutter.")


if __name__ == "__main__":
    main()
