#!/usr/bin/env python3
"""Run the disposable layout suite. No host-latency pass/fail threshold."""
import argparse,json,math,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--debug',action='store_true');a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    binary=a.output/'layout-probe'
    cmd=['cc','-std=c11','-D_POSIX_C_SOURCE=200809L','-O0' if a.debug else '-O2','-g','-Wall','-Wextra','-Werror',str(HERE/'layout_probe.c'),str(HERE/'Platform/platform.c'),'-I'+str(HERE/'Platform/include'),'-o',str(binary)]
    subprocess.run(cmd,check=True,capture_output=True)
    with (a.output/'selftest.txt').open('w') as f:subprocess.run([str(binary),'--selftest'],check=True,stdout=f,stderr=subprocess.STDOUT)
    results=[]
    cases=[(n,d,256) for n in (100_000,250_000,1_000_000,2_000_000) for d in (1,2)]
    cases += [(1_000_000,1,b) for b in (1,7,31,1024)]
    for n,d,b in cases:
        r=subprocess.run([str(binary),str(n),str(d),str(b)],check=True,capture_output=True,text=True)
        x=json.loads(r.stdout);assert x['assets']==n and x['eventCapacity']==n*d
        expected=80*n+40*n*d+40*math.ceil(n/16)+math.ceil(n/8)+33024
        assert x['ownedAllocatedBytes']==expected and x['bytesPerAsset']<=200
        if d==1:assert x['bytesPerAsset']<=128
        assert len(x['runs'])==2 and len({r['checksum'] for r in x['runs']})==1
        for run in x['runs']:
            assert run['processed']==n and run['advanceCalls']==math.ceil(n/b)
            assert run['ownedAllocationCallsInEvents']==0 and run['maxOwnedAllocationsPerAdvance']==0
        (a.output/f'layout-{n}-{d}-{b}.json').write_text(r.stdout);results.append(x)
    assert len({x['runs'][0]['checksum'] for x in results if x['assets']==1_000_000})==1
    (a.output/'summary.json').write_text(json.dumps({'status':'layout-kernel-checks-passed','cases':len(results),'build':'debug' if a.debug else 'release','results':results,'scope':'disposable storage/update prototype; not R005 production or full-game budget acceptance'},indent=2)+'\n')
    print('PASS',len(results),'layout cases including1M/2M; source-owned bytes/allocation gates only')
if __name__=='__main__':main()
