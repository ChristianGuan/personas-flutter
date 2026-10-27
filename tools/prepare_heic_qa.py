#!/usr/bin/env python3
"""Create real HEIC QA files from the existing public OpenCV sample; never ship them."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import pillow_heif
from PIL import Image,ImageCms

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
# This helper is for the pinned public QA image, not private photo collection.
expected='7de7ed51a1594fff247f4cae2301eceacf5313d6011e37b4a4c8733f7bb72c07'
pixels=np.asarray(Image.open(args.source).convert('RGB'))
source_sha=hashlib.sha256(args.source.read_bytes()).hexdigest()
assert source_sha==expected, 'Use the pinned public OpenCV sample for this QA helper'
records=[]
def save(name,mode,data,**kwargs):
    image=pillow_heif.from_bytes(mode=mode,size=(data.shape[1],data.shape[0]),data=data.tobytes())
    path=args.output/name
    image.save(path,quality=95,enc_params={"x265:pools":"1","x265:frame-threads":"1"},**kwargs)
    decoded=pillow_heif.open_heif(path,convert_hdr_to_8bit=False)
    records.append({'name':name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bitDepth':decoded.info.get('bit_depth'),'mode':decoded.mode,'size':decoded.size})
save('face-srgb.HEIC','RGB',pixels)
save('face-10bit.heic','RGB;16',pixels.astype(np.uint16)*257)
# P3 values are color-managed from the public sRGB sample, not just retagged.
srgb=ImageCms.createProfile('sRGB')
p3=ImageCms.getOpenProfile('/System/Library/ColorSync/Profiles/Display P3.icc')
image=Image.fromarray(pixels)
wide=ImageCms.profileToProfile(image,srgb,p3,outputMode='RGB')
save('face-p3.heic','RGB',np.asarray(wide),icc_profile=p3.tobytes())
save('face-p3-10bit.heic','RGB;16',np.asarray(wide).astype(np.uint16)*257,icc_profile=p3.tobytes())
orientation=Image.Exif();orientation[274]=6
save('face-rotated-10bit.heic','RGB;16',np.ascontiguousarray(np.rot90(pixels)).astype(np.uint16)*257,exif=orientation.tobytes())
mirror=Image.Exif();mirror[274]=2
save('face-mirrored-10bit.heic','RGB;16',np.ascontiguousarray(np.fliplr(pixels)).astype(np.uint16)*257,exif=mirror.tobytes())
# Non-square geometry covers all eight orientations and transform composition.
portrait=Image.fromarray(pixels[32:480,64:448])
inverse={2:Image.Transpose.FLIP_LEFT_RIGHT,3:Image.Transpose.ROTATE_180,
         4:Image.Transpose.FLIP_TOP_BOTTOM,5:Image.Transpose.TRANSPOSE,
         6:Image.Transpose.ROTATE_90,7:Image.Transpose.TRANSVERSE,8:Image.Transpose.ROTATE_270}
for value in range(1,9):
    stored=portrait if value==1 else portrait.transpose(inverse[value])
    exif=Image.Exif();exif[274]=value
    save(f'orientation-{value}.heic','RGB;16',np.asarray(stored).astype(np.uint16)*257,exif=exif.tobytes())
save('blank.heic','RGB' ,np.full((128,128,3),230,np.uint8))
(args.output/'broken.heic').write_bytes((args.output/'face-srgb.HEIC').read_bytes()[:64])
manifest={'source':'https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/lena.jpg','sourceSha256':source_sha,'credit':'OpenCV public sample, existing development QA; transformed copies stay outside APK/Git','encoder':'pillow-heif 1.1.1 / Pillow 11.3.0','fixtures':records}
(args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'fixtures':records},indent=2))
