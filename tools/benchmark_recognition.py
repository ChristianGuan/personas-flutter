#!/usr/bin/env python3
"""Developer-only host comparison; never label its timings as Android performance.

Requires tools/prepare_recognition_qa.py's public fixtures, numpy and OpenCV 4.12.
No photos or embeddings are exported; outputs counts and paired search timings.
"""
import argparse
import hashlib
import json
import platform
import statistics
import time
from pathlib import Path

import cv2
import numpy as np


def normalize(vector):
    vector = vector.reshape(-1)
    return (vector / np.sqrt(np.sum(vector.astype(np.float64) ** 2))).astype(np.float32)


def cosine(a, b):
    return float(np.sum(normalize(a).astype(np.float64) * normalize(b).astype(np.float64)))


def merge(rows):
    result = []
    for row in sorted(rows, key=lambda r: -float(r[14])):
        def overlap(other):
            x = max(0, min(row[0] + row[2], other[0] + other[2]) - max(row[0], other[0]))
            y = max(0, min(row[1] + row[3], other[1] + other[3]) - max(row[1], other[1]))
            intersection = x * y
            return intersection / (row[2] * row[3] + other[2] * other[3] - intersection)
        if not any(overlap(other) > .4 for other in result):
            result.append(row)
    return sorted(result, key=lambda r: (float(r[1]), float(r[0])))


class Engine:
    def __init__(self, models):
        self.detector = cv2.FaceDetectorYN.create(str(models / 'yunet.onnx'), '', (320, 320), .85, .3, 5000)
        self.recognizer = cv2.FaceRecognizerSF.create(str(models / 'sface.onnx'), '')
        self.cache = {}
        self.detections = self.embeddings = 0

    def detect(self, image):
        h, w = image.shape[:2]
        scales = [1, 960 / max(h, w)] if max(h, w) > 960 else [1]
        rows = []
        for scale in scales:
            small = image if scale == 1 else cv2.resize(image, (max(1, int(w * scale)), max(1, int(h * scale))))
            self.detector.setInputSize((small.shape[1], small.shape[0]))
            _, found = self.detector.detect(small)
            self.detections += 1
            for row in ([] if found is None else found):
                row = row.copy()
                sx, sy = np.float32(w / small.shape[1]), np.float32(h / small.shape[0])
                row[[0, 2, 4, 6, 8, 10, 12]] *= sx
                row[[1, 3, 5, 7, 9, 11, 13]] *= sy
                if row[2] >= 24 and row[3] >= 24:
                    rows.append(row)
        return merge(rows)

    def feature(self, image, row):
        crop = self.recognizer.alignCrop(image, row.reshape(1, 15))
        self.embeddings += 1
        return normalize(self.recognizer.feature(crop))

    def full(self, image):
        rows = self.detect(image)
        return [self.feature(image, row) for row in rows]

    def match(self, image, references):
        key = (image.shape, image.dtype.str, hashlib.sha256(image.tobytes()).digest())
        if key not in self.cache:
            rows = self.detect(image)
            self.cache[key] = (rows, [None] * len(rows))
        rows, vectors = self.cache[key]
        for i, row in enumerate(rows):
            if vectors[i] is None:
                vectors[i] = self.feature(image, row)
            if any(cosine(reference, vectors[i]) >= .363 for reference in references):
                return True, True
        return bool(rows), False


def benchmark(models, sources, references):
    full, fast = Engine(models), Engine(models)
    # Exclude one-time model initialization / native kernel warm-up from both searches.
    warm = sources[0]()
    full.full(warm)
    fast.full(warm)
    timings = {name: [] for name in ('fullMs', 'firstMs', 'repeatMs')}
    computations = {}
    decisions_equal = True
    vectors_equal = True
    for trial in range(3):
        expected = []
        baseline_vectors = []
        full.detections = full.embeddings = 0
        start = time.perf_counter()
        for load in sources:
            vectors = full.full(load())
            baseline_vectors.append(vectors)
            expected.append((bool(vectors), any(cosine(r, v) >= .363 for r in references for v in vectors)))
        timings['fullMs'].append((time.perf_counter() - start) * 1000)
        computations['full'] = {'detectionPasses': full.detections, 'embeddings': full.embeddings}
        fast.cache.clear()
        for phase in ('first', 'repeat'):
            fast.detections = fast.embeddings = 0
            start = time.perf_counter()
            actual = [fast.match(load(), references) for load in sources]
            timings[phase + 'Ms'].append((time.perf_counter() - start) * 1000)
            computations[phase] = {'detectionPasses': fast.detections, 'embeddings': fast.embeddings}
            decisions_equal &= actual == expected
        for load, vectors in zip(sources, baseline_vectors):
            image = load()
            key = (image.shape, image.dtype.str, hashlib.sha256(image.tobytes()).digest())
            stored = fast.cache[key][1]
            vectors_equal &= all(v is None or np.array_equal(v, original) for v, original in zip(stored, vectors))
        # An earlier positive may have left embeddings uncomputed. A different
        # reference must still inspect missing faces and reach the full-search decision.
        alternative = [-reference for reference in references]
        for load, vectors in zip(sources, baseline_vectors):
            expected_other = (bool(vectors), any(cosine(r, v) >= .363 for r in alternative for v in vectors))
            decisions_equal &= fast.match(load(), alternative) == expected_other
    assert decisions_equal and vectors_equal
    return {'photos': len(sources), 'milliseconds': timings,
            'medianMs': {k: round(statistics.median(v), 3) for k, v in timings.items()},
            'nativeWork': computations, 'sameDecisionsIncludingReferenceChange': decisions_equal, 'exactComputedVectors': vectors_equal}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert cv2.__version__.startswith('4.12.'), 'Use the same OpenCV 4.12 family as Android'
    cv2.setNumThreads(2)
    models = Path(__file__).resolve().parent.parent / 'app/src/main/assets/models'
    seed_engine = Engine(models)
    refs = [seed_engine.full(cv2.imread(str(args.fixtures / name)))[0] for name in ('ref-side.jpg', 'ref-front.jpg')]
    paths = sorted(list(args.fixtures.glob('positive-*.jpg')) + list(args.fixtures.glob('negative-*.jpg')))
    assert len(paths) == 13
    cases = [lambda path=path: cv2.imread(str(path)) for path in paths]
    # Deliberately synthetic group: tests logical early exit; not nine distinct people.
    lena = cv2.imread(str(args.fixtures / 'negative-1.jpg'))
    group = np.tile(lena, (3, 3, 1))
    group_reference = seed_engine.full(lena)[0]
    result = {'scope': 'HOST ONLY; public targeted fixtures, not an Android benchmark or product accuracy estimate',
              'opencv': cv2.__version__, 'architecture': platform.machine(),
              'distinctPhotos': benchmark(models, cases, refs),
              'nineCopyGroupPositive': benchmark(models, [lambda: group.copy()], [group_reference]),
              'nineCopyGroupNegative': benchmark(models, [lambda: group.copy()], [-group_reference])}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
