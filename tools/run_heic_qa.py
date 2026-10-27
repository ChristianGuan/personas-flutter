#!/usr/bin/env python3
"""Install debug APKs and run public HEIC regression on an explicitly chosen device."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial',required=True,help='ADB target; choose explicitly when several devices exist')
parser.add_argument('--fixtures',type=Path,required=True,help='Output of prepare_heic_qa.py')
parser.add_argument('--adb',default=shutil.which('adb'),help='Path to platform-tools/adb')
parser.add_argument('--output',type=Path,help='Public metrics/screenshots; defaults to a temporary directory')
args=parser.parse_args()
if not args.adb:parser.error('Provide --adb or add platform-tools to PATH')
root=Path(__file__).resolve().parents[1]
manifest=json.loads((args.fixtures/'manifest.json').read_text())
assert manifest['sourceSha256']=='7de7ed51a1594fff247f4cae2301eceacf5313d6011e37b4a4c8733f7bb72c07'
names=['face-srgb.HEIC','face-10bit.heic','face-p3.heic','face-p3-10bit.heic',
       'face-rotated-10bit.heic','face-mirrored-10bit.heic','blank.heic']
names += [f'orientation-{i}.heic' for i in range(1,9)]
for name in names:
    record=next(row for row in manifest['fixtures'] if row['name']==name)
    assert hashlib.sha256((args.fixtures/name).read_bytes()).hexdigest()==record['sha256'],name
assert (args.fixtures/'broken.heic').read_bytes()==(args.fixtures/'face-srgb.HEIC').read_bytes()[:64]
base=[args.adb,'-s',args.serial]
def run(*command):
    return subprocess.run(base+list(command),capture_output=True,text=True,check=True,timeout=180).stdout.strip()
for apk in ['debug/app-debug.apk','androidTest/debug/app-debug-androidTest.apk']:
    print(run('install','-r','-t',str(root/'app/build/outputs/apk'/apk)),flush=True)
bundle=io.BytesIO()
with tarfile.open(fileobj=bundle,mode='w') as tar:
    for name in names+['broken.heic','manifest.json']:tar.add(args.fixtures/name,arcname=name)
subprocess.run(base+['shell',"run-as co.local.personas sh -c 'mkdir -p cache/qa-heic && cd cache/qa-heic && tar -xf -'"],input=bundle.getvalue(),check=True)
output=args.output or Path(tempfile.mkdtemp(prefix='personas-heic-review-'))
output.mkdir(parents=True,exist_ok=True)
keys=['animator_duration_scale','transition_animation_scale','window_animation_scale']
original={key:run('shell','settings','get','global',key) for key in keys}
try:
    for key in keys:run('shell','settings','put','global',key,'0')
    result=run('shell','am','instrument','-w','-e','class',
        'co.local.personas.data.HeicPhotoTest,co.local.personas.ui.HeicUiTest',
        '-e','heicFixtures','qa-heic','co.local.personas.test/androidx.test.runner.AndroidJUnitRunner')
    print(result,flush=True);(output/'tests.txt').write_text(result+'\n')
    if 'OK (7 tests)' not in result:raise RuntimeError('HEIC regressions failed; see tests.txt')
    for name in ['decoder-metrics.json','preview.png']:
        data=subprocess.run(base+['exec-out','run-as','co.local.personas','cat','cache/qa-heic-'+name],capture_output=True,check=True).stdout
        (output/name).write_bytes(data)
    print(f'Public QA evidence: {output}',flush=True)
finally:
    for key,value in original.items():
        if value=='null':run('shell','settings','delete','global',key)
        else:run('shell','settings','put','global',key,value)
