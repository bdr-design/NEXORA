#!/usr/bin/env python3
import json, subprocess, sys, tempfile
from pathlib import Path

binary=Path(sys.argv[1]).resolve(); out=Path(sys.argv[2]).resolve()

def call(*args, timeout=5400):
    cp=subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,timeout=timeout)
    if cp.returncode:
        raise RuntimeError((args,cp.returncode,cp.stderr[-4000:]))
    return json.loads(cp.stdout)

with tempfile.TemporaryDirectory(prefix='nxr-stage005-b-') as temp:
    root=Path(temp)
    g16=call('stage-b',root/'g16','G16')
    g1=call('stage-b',root/'g1','G1')
    g1w3=call('stage-b-window',root/'g1w3','G1',3)
assert g16['status']==g1['status']==g1w3['status']=='pass'
assert len(g16['days'])==30 and len(g1['days'])==30
for row in g16['days']+g1['days']:
    assert all(row['invariants'].values())
result={
    'status':'pass',
    'scope':'R005 proof-only Stage B; generated disposable finance data, no production record deletion',
    'B':g16['days']+g1['days'],
    'cases':{'G16_W7':{k:g16[k] for k in ('BdayMax','S30','Omax','peakBytes')},
             'G1_W7':{k:g1[k] for k in ('BdayMax','S30','Omax','peakBytes')},
             'G1_W3':{k:g1w3[k] for k in ('BdayMax','S30','Omax','peakBytes')}},
    'quotaInputs':{'capBytes':1073741824,'formula':'ceil64MiB(1.25*((W+1)*BdayMax+S30+Omax)+2*Snap); Snap supplied by Stage C'},
    'finalDiskVerification':{'G16':g16['finalDiskVerification'],'G1':g1['finalDiskVerification'],'G1_W3':g1w3['finalDiskVerification']}
}
out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'status':'pass','records':len(result['B']),'G16':result['cases']['G16_W7'],'G1':result['cases']['G1_W7']},indent=2))
