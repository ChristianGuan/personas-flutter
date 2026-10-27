#!/usr/bin/env python3
"""Prepare public AT&T Laboratories Cambridge faces for developer QA, outside APK/Git."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path
import cv2
import numpy as np

URL = 'https://www.cl.cam.ac.uk/Research/DTG/attarchive/pub/data/att_faces.zip'
SHA256 = '509d763bd2276aa054d260d7f1000e8be212738134f2f83d8ff13bc2adf1c8ec'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    archive=args.output/'att_faces.zip'
    if not archive.is_file() or hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:
        subprocess.run(['curl','--fail','--silent','--show-error','--location','--max-time','90','--output',str(archive),URL],check=True)
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==SHA256
    with zipfile.ZipFile(archive) as z:
        for subject in range(1,41):
            for image in range(1,11):
                pixels=cv2.imdecode(np.frombuffer(z.read(f's{subject}/{image}.pgm'),np.uint8),cv2.IMREAD_COLOR)
                assert pixels is not None
                cv2.imwrite(str(args.output/f's{subject:02}-{image:02}.png'),pixels)
    manifest={'credit':'AT&T Laboratories Cambridge','source':URL,'sourcePage':'https://www.cl.cam.ac.uk/research/dtg/attarchive/facedatabase.html','archiveSha256':SHA256,'scope':'Historical 92x112 grayscale frontal faces, not family albums; QA only, never ship images','calibrationSubjects':[1,20],'evaluationSubjects':[21,40],'referenceCounts':[1,2,4],'selectionRule':'Lowest threshold in [0.50,0.55,0.60,0.65,0.70] with zero calibration false positives for all protocols'}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('400 public QA PNG prepared; credit AT&T Laboratories Cambridge. No embeddings exported.')

if __name__=='__main__': main()
