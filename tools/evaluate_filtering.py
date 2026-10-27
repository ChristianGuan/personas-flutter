#!/usr/bin/env python3
"""Host-only calibration and separate-identity evaluation; never a product accuracy claim."""
import argparse
import json
from pathlib import Path
import cv2
import numpy as np


def normal(vector):
    vector=vector.reshape(-1)
    return (vector/np.sqrt(np.sum(vector.astype(np.float64)**2))).astype(np.float32)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();cv2.setNumThreads(2)
    models=Path(__file__).resolve().parent.parent/'app/src/main/assets/models'
    detector=cv2.FaceDetectorYN.create(str(models/'yunet.onnx'),'',(92,112),.85,.3,5000)
    recognizer=cv2.FaceRecognizerSF.create(str(models/'sface.onnx'),'')
    refs={};queries={};missing=[]
    def vectors(pixels,threshold,reference=False):
        detector.setScoreThreshold(threshold);detector.setInputSize((pixels.shape[1],pixels.shape[0]))
        _,faces=detector.detect(pixels)
        rows=[] if faces is None else [f for f in faces if min(f[2],f[3])>=24]
        if reference and rows: rows=[max(rows,key=lambda f:float(f[2]*f[3]))]
        return [normal(normal(recognizer.feature(recognizer.alignCrop(pixels,f.reshape(1,15))))) for f in rows]
    for subject in range(1,41):
        for image in range(1,11):
            pixels=cv2.imread(str(args.fixtures/f's{subject:02}-{image:02}.png'))
            assert pixels is not None
            queries[subject,image]=vectors(pixels,.85)
            if image<=4: refs[subject,image]=vectors(pixels,.65,True)
            if not queries[subject,image]: missing.append([subject,image])
    report={'credit':'AT&T Laboratories Cambridge','opencv':cv2.__version__,'scope':'Internal host check; calibration subjects1-20, evaluation21-40; separate identities, not external blind evaluation or family calibration','missingQueryImages':len(missing),'splits':{}}
    all_pairs={}
    for split,subjects in [('calibration',range(1,21)),('evaluation',range(21,41))]:
        protocols={}
        for count in [1,2,4]:
            pairs=[]
            for target in subjects:
                references=[v for i in range(1,count+1) for v in refs[target,i]]
                for subject in subjects:
                    for image in range(count+1,11):
                        score=max([float(np.sum(a.astype(np.float64)*b.astype(np.float64))) for a in references for b in queries[subject,image]],default=-1.)
                        pairs.append((subject==target,score,target,subject,image))
            all_pairs[split,count]=pairs
            protocols[str(count)]={}
            for threshold in [.363,.5,.55,.6,.65,.7]:
                protocols[str(count)][str(threshold)]={'TP':sum(p and s>=threshold for p,s,*_ in pairs),'FP':sum(not p and s>=threshold for p,s,*_ in pairs),'FN':sum(p and s<threshold for p,s,*_ in pairs),'TN':sum(not p and s<threshold for p,s,*_ in pairs)}
        report['splits'][split]=protocols
        if split=='calibration':
            report['selectedThreshold']=next((t for t in [.5,.55,.6,.65,.7] if all(protocols[str(n)][str(t)]['FP']==0 for n in [1,2,4])),None)
            if report['selectedThreshold'] is None: raise RuntimeError('No threshold in the predeclared grid passed calibration')
    threshold=report['selectedThreshold']
    for split in ['calibration','evaluation']:
        for count in [1,2,4]:
            pairs=all_pairs[split,count]
            selected=report['splits'][split][str(count)][str(threshold)]
            selected['reviewPositive']=sum(p and .363<=s<threshold for p,s,*_ in pairs)
            selected['reviewNegative']=sum(not p and .363<=s<threshold for p,s,*_ in pairs)
    failures=[{'target':target,'otherSubject':other,'image':image} for p,s,target,other,image in all_pairs['calibration',1] if not p and s>=.363]
    (args.fixtures/'regression.json').write_text(json.dumps({'scope':'Directed calibration regressions, not held-out accuracy','cases':failures},indent=2)+'\n')
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'selectedThreshold':threshold,'missingQueryImages':len(missing),'atSelected':{split:{n:values[str(threshold)] for n,values in protocols.items()} for split,protocols in report['splits'].items()},'directedFailures':len(failures)}))

if __name__=='__main__':main()
