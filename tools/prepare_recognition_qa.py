#!/usr/bin/env python3
"""Prepare optional PUBLIC test fixtures outside the repo. Never used by the app.
Requires opencv-python-headless==4.12.0.88, numpy==2.2.6.
Reference seeds and positive evaluation frames are disjoint, but from ONE VIDEO.
This is a targeted regression fixture, not an independent accuracy benchmark.
The reference choice was informed by this fixture, not selected blindly.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import subprocess
import cv2

SOURCES = {
    'david.webm': 'https://raw.githubusercontent.com/opencv/opencv_extra/4.x/testdata/cv/tracking/david/data/david.webm',
    'negative-0.jpg': 'https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/messi5.jpg',
    'negative-1.jpg': 'https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/lena.jpg',
}
POSITIVES = [59, 118, 177, 236, 295, 414, 532, 591, 650, 709, 769]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path(tempfile.gettempdir()) / 'personas-recognition-qa')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source_dir = args.output / 'sources'
    source_dir.mkdir(exist_ok=True)
    manifest = {'scope': 'Regression only: one video, two negative identities; not a product accuracy claim', 'sources': {}, 'references': [473, 354], 'positiveFrames': POSITIVES}
    for name, url in SOURCES.items():
        path = source_dir / name
        # Use the OS curl trust store; never disable HTTPS certificate validation.
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location', '--max-time', '90', '--output', str(path), url], check=True)
        manifest['sources'][name] = {'url': url, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    for name in ['negative-0.jpg', 'negative-1.jpg']:
        shutil.copyfile(source_dir / name, args.output / name)
    capture = cv2.VideoCapture(str(source_dir / 'david.webm'))
    try:
        for name, frame in [('ref-side.jpg', 473), ('ref-front.jpg', 354)] + [(f'positive-{i:02}.jpg', f) for i, f in enumerate(POSITIVES)]:
            capture.set(cv2.CAP_PROP_POS_FRAMES, frame)
            ok, image = capture.read()
            if not ok or not cv2.imwrite(str(args.output / name), image):
                raise SystemExit('Cannot extract public QA frame')
    finally:
        capture.release()
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Public fixtures ready: two reference frames, eleven positive frames, two negative images. No embeddings exported.')

if __name__ == '__main__':
    main()
