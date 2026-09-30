#!/usr/bin/env python3
"""Validate the separate event-timestamp trace; do not attribute gaps to a cause."""
import argparse,hashlib,importlib.util,json
from pathlib import Path
s=importlib.util.spec_from_file_location('extra',Path(__file__).with_name('analyze.py'))
a=importlib.util.module_from_spec(s);s.loader.exec_module(a)

def analyze(path):
    seen=set();identity=None;done=False;result=[]
    with path.open() as reader:
        for line in reader:
            x=json.loads(line,object_pairs_hook=a.d.unique_object,parse_constant=a.d.reject_constant)
            a.require(not done,'trailing data')
            if x.get('kind')=='complete':
                a.require(x=={'kind':'complete','status':'success'},'completion state');done=True;continue
            a.require(x.get('kind')=='events','unknown/failure record')
            a.d.object_fields(x,('kind','sourceCommit','transformedSourceSHA256','size','sample','fixture','eventStartNS','allocationNS','interpretation'))
            key=x['size'],x['sample'];a.require(key not in seen and key[0] in (20000,50000,100000) and key[1] in (1,2,3),'event identity');seen.add(key)
            ident=x['sourceCommit'],x['transformedSourceSHA256']
            a.require(len(ident[0])==40 and len(ident[1])==64 and all(c in '0123456789abcdef' for c in ''.join(ident)),'source format')
            a.require(identity is None or identity==ident,'mixed source');identity=ident
            f=x['fixture'];a.d.validate_item_shape(f);a.d.validate_records(f['records'],count=key[0],sample=key[1],mode='counters');a.d.phase_validation(f);a.d.validate_lifecycle(f)
            times=x['eventStartNS'];alloc=x['allocationNS']
            a.require(len(times)==key[0] and len(alloc)==(key[0]+255)//256,'event/allocation count')
            for v in times+alloc:a.require(a.uint(v)<2**64-1,'clock failure')
            a.require(all(u<=v for u,v in zip(times,times[1:])),'event chronology')
            within=[times[i+1]-times[i] for i in range(len(times)-1) if (i+1)%256]
            boundaries=[times[i+1]-times[i] for i in range(len(times)-1) if (i+1)%256==0]
            result.append({'size':key[0],'sample':key[1],'events':len(times),'allocationBracketNS':a.d.distribution(alloc),'withinBatchNextStartGapNS':a.d.distribution(within),'betweenBatchNextStartGapNS':a.d.distribution(boundaries)})
    a.require(done and seen=={(n,s) for n in (20000,50000,100000) for s in (1,2,3)},'incomplete event study')
    return {'status':'event-trace-validated','source':identity,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'worlds':result,'limits':['next-start gaps include observer work; not pure event latency','last event duration not measured separately','allocation bracket includes clock overhead','separate observation, not causal identification of historical spikes']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('raw',type=Path);p.add_argument('output',type=Path);x=p.parse_args()
    y=analyze(x.raw)
    with x.output.open('x') as w:json.dump(y,w,indent=2,sort_keys=True);w.write('\n')
    print('PASS nine event worlds and preallocated allocation/event cardinality')
