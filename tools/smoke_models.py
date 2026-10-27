#!/usr/bin/env python3
"""Prueba de inferencia en host, no sustituye la validación Android ni mide precisión.
Uso: python tools/smoke_models.py /ruta/imagen-de-prueba.jpg
Requiere opencv-python-headless==4.12.0.88 y numpy==2.2.6.
No imprime fotos, rutas, landmarks ni embeddings.
"""
import sys
import time
from pathlib import Path
import cv2
import numpy as np

root = Path(__file__).resolve().parents[1] / 'app/src/main/assets/models'
cv2.setNumThreads(2)
image = cv2.imread(sys.argv[1])
if image is None:
    raise SystemExit('Imagen de prueba ilegible')
start = time.perf_counter()
detector = cv2.FaceDetectorYN.create(str(root / 'yunet.onnx'), '', (image.shape[1], image.shape[0]), 0.85, 0.3, 5000)
recognizer = cv2.FaceRecognizerSF.create(str(root / 'sface.onnx'), '')
_, faces = detector.detect(image)
assert faces is not None and len(faces) > 0, 'Se necesita una muestra con rostro detectable'
for face in faces:
    crop = recognizer.alignCrop(image, face)
    assert crop.shape == (112, 112, 3)
    vector = recognizer.feature(crop)
    assert vector.shape == (1, 128)
    assert np.isfinite(vector).all() and np.linalg.norm(vector) > 0
blank = np.zeros((512, 512, 3), dtype=np.uint8)
detector.setInputSize((512, 512))
_, empty = detector.detect(blank)
assert empty is None or len(empty) == 0
print(f'OpenCV {cv2.__version__}: inferencia real OK; {len(faces)} rostro(s); alineación 112x112; embedding finito de 128 dimensiones; imagen vacía sin caras; {1000*(time.perf_counter()-start):.1f} ms en host (incluye carga).')
