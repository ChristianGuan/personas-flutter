#!/usr/bin/env python3
"""Verifica o repone exclusivamente los modelos oficiales fijados por SHA-256."""
import argparse
import hashlib
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / "app/src/main/assets/models"
MODELS = [
    ("yunet.onnx", "face_detection_yunet/face_detection_yunet_2023mar.onnx", 232589, "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"),
    ("sface.onnx", "face_recognition_sface/face_recognition_sface_2021dec.onnx", 38696353, "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"),
]
def valid(path, size, digest):
    return path.is_file() and path.stat().st_size == size and hashlib.sha256(path.read_bytes()).hexdigest() == digest

def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--download", action="store_true")
    args = parser.parse_args()
    for name, upstream, size, digest in MODELS:
        path = ROOT / name
        if not valid(path, size, digest) and args.download:
            temp = path.with_suffix(".download")
            try:
                with urllib.request.urlopen("https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/" + upstream, timeout=120) as source, temp.open("wb") as dest:
                    while chunk := source.read(1024 * 1024):
                        dest.write(chunk)
                if not valid(temp, size, digest):
                    raise SystemExit("Modelo rechazado por tamaño o hash: " + name)
                temp.replace(path)
            finally:
                temp.unlink(missing_ok=True)
        if not valid(path, size, digest):
            raise SystemExit("Falta modelo válido: " + name)
        print(name + ": SHA-256 y tamaño correctos")
if __name__ == "__main__":
    main()
