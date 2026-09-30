#!/usr/bin/env python3
"""One bounded V4 campaign. No causal claim from instruction counts or absent PMU."""
import argparse, collections, hashlib, importlib.util, json, math, sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('prior_validator',ROOT/'Checks/financial-diagnostics.py')
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)

def require(c,m):
    if not c: raise ValueError(m)

def uint(v):
    require(type(v) is int and 0<=v<2**64,'bad unsigned value');return v

def value(v):
    require(set(v)=={'status','reason'} or set(v)=={'status','reason','value'},'counter fields')
    require(v['status'] in ('ok','unsupported','readFailure'),'counter status')
    require(type(v['reason']) is str and v['reason'],'counter reason')
    if v['status']=='ok': require(uint(v.get('value'))>0,'zero endpoint must follow zero-reading policy')
    else: require(v.get('value') is None,'unavailable counter masquerades as value')

def snapshot(s):
    require(set(s) in ({'beginNS','endNS','instructions','cycles','runnableRaw'},
                       {'beginNS','endNS','error','instructions','cycles','runnableRaw'}),'snapshot fields')
    require(uint(s['beginNS'])<=uint(s['endNS'])<2**64-1,'snapshot clock failure/order')
    for f in ('instructions','cycles','runnableRaw'): value(s[f])
    failed=any(s[f]['status']=='readFailure' for f in ('instructions','cycles','runnableRaw'))
    if failed: require(type(s.get('error')) is int and -2**31<=s['error']<2**31,'missing raw errno')
    else: require(s.get('error') is None,'unexpected errno')

def delta(pair,f):
    a,b=pair['before'][f],pair['after'][f]
    if a['status']!='ok' or b['status']!='ok': return None
    x,y=a['value'],b['value']
    return y-x if y>=x else None

def classify(instructions, peers):
    if instructions is None or not peers: return 'unavailable-or-no-comparable-peers'
    maximum=max(peers)
    if maximum<=0: return 'unavailable-or-no-comparable-peers'
    if instructions>=1.5*maximum: return 'instruction-growth-observed; symbolized-profile-needed'
    if instructions<=maximum: return 'within-peer-instruction-range; cause-unresolved'
    return 'above-peer-range-below-1.5; cause-unresolved'

def analyze(paths):
    seen_hashes=set();run_ids=set();source=None;environment=None;rows=[];meta_out=[];calibration=[]
    require(paths, "no input streams")
    for p in paths:
        digest=hashlib.sha256(p.read_bytes()).hexdigest();require(digest not in seen_hashes,'duplicate raw stream')
        seen_hashes.add(digest);meta=None;done=False;seen=set();cal=set();seen_v4_cal=False
        with p.open() as reader:
            for line in reader:
                x=json.loads(line,object_pairs_hook=d.unique_object,parse_constant=d.reject_constant)
                require(not done,'data after completion')
                kind=x.get('kind')
                if kind=='metadata':
                    require(meta is None,'duplicate metadata');meta=x
                    d.object_fields(x, ('kind','schema','sourceCommit','transformedSourceSHA256','os','processID','run','repetitions','sizes','warmups','modes','scope','runnableUnit','zeroPolicy'))
                    require(type(x['os']) is str and x['os'] and type(x['processID']) is int and x['processID']>0,'invalid producer environment')
                    env=(x['os'],x['scope'],x['runnableUnit'],x['zeroPolicy'])
                    require(environment is None or env==environment,'incomparable counter/OS semantics');environment=env
                    require(x['schema']=='NXR-R004-V4-1' and x['sizes']==[20000,50000,100000] and x['warmups']==3,'fixture schema')
                    require(x['modes']==['control','v4'] and type(x['repetitions']) is int and 1<=x['repetitions']<=30,'schedule')
                    require(type(x['run']) is int and 1<=x['run']<=3 and x['run'] not in run_ids,'duplicate/invalid run')
                    run_ids.add(x['run'])
                    identity=(x['sourceCommit'],x['transformedSourceSHA256'])
                    require(len(identity[0])==40 and len(identity[1])==64 and all(c in '0123456789abcdef' for c in ''.join(identity)),'source identity')
                    require(source is None or source==identity,'mixed source');source=identity
                    meta_out.append({'file':p.name,'sha256':digest,'metadata':x})
                elif kind=='calibration':
                    require(meta is not None and not seen and x['mode'] not in cal,'calibration order')
                    d.validate_calibration(x);cal.add(x['mode'])
                elif kind=='v4Calibration':
                    require(meta is not None and not seen and not seen_v4_cal,'V4 calibration order');seen_v4_cal=True
                    require(len(x['records'])==2000,'missing calibration')
                    elapsed=[]
                    for pair in x['records']:
                        snapshot(pair['before']);snapshot(pair['after'])
                        require(pair['before']['endNS']<=pair['after']['beginNS'],'calibration envelope')
                        elapsed.append(pair['after']['endNS']-pair['before']['beginNS'])
                    calibration.append({'run':meta['run'],'enclosingNS':d.distribution(elapsed)})
                elif kind=='sample':
                    require(meta is not None and cal=={'wall','counters'} and seen_v4_cal,'sample before calibration')
                    d.object_fields(x, ('kind','size','run','sample','warmup','mode','fixture','v4'))
                    n,s,mode=x['size'],x['sample'],x['mode'];identity=(n,s,mode)
                    require(n in meta['sizes'] and type(s) is int and 1<=s<=3+meta['repetitions'] and mode in meta['modes'],'sample identity')
                    require(identity not in seen and x['run']==meta['run'],'duplicate sample');seen.add(identity)
                    require(type(x['warmup']) is bool and x['warmup']==(s<=3),'warmup stratum')
                    f=x['fixture'];d.validate_item_shape(f)
                    expected_order=['control','v4'] if (s+x['run'])%2==0 else ['v4','control']
                    require((f['aircraft'],f['sample'],f['runID'],f['warmup'],f['mode'],f['executionOrder'])==(n,s,x['run'],s<=3,'counters',expected_order.index(mode)),'inner fixture identity/order')
                    d.validate_records(f['records'],count=n,sample=s,mode='counters')
                    d.phase_validation(f);d.validate_lifecycle(f)
                    expected_income=sum(101+i%97 for i in range(n))
                    require((f['aggregate']['invoiceCount'],f['aggregate']['journalCount'],f['aggregate']['cashMinor'],f['aggregate']['revenueMinor'])
                            ==(n,2*n+4,expected_income-5000,expected_income),'changed economics')
                    require(len(x['v4'])==(len(f['records']) if mode=='v4' else 0),'counter/batch cardinality')
                    for i,row in enumerate(f['records']):
                        pair=x['v4'][i] if mode=='v4' else None
                        if pair:
                            snapshot(pair['before']);snapshot(pair['after'])
                            require(pair['before']['endNS']<=pair['after']['beginNS'],'counter bracket')
                        if not x['warmup']:
                            rows.append({'size':n,'run':meta['run'],'sample':s-3,'mode':mode,
                                         'phase':row['phase'],'batch':row['batch'],'operations':row['operations'],
                                         'wallNS':row['wallNS'],'threadCPUNS':d.counter_delta(row,'threadCPUNS')[0],
                                         'instructions':None if pair is None else delta(pair,'instructions'),
                                         'cycles':None if pair is None else delta(pair,'cycles'),
                                         'runnableRaw':None if pair is None else delta(pair,'runnableRaw')})
                elif kind=='complete':
                    require(x.get('status')=='success','failed completion');done=True
                else: raise ValueError('unknown/failure record: '+str(kind))
        require(done and meta is not None,'incomplete stream')
        expected={(n,s,m) for n in meta['sizes'] for s in range(1,4+meta['repetitions']) for m in meta['modes']}
        require(seen==expected,'missing sample')
    groups=collections.defaultdict(list)
    for r in rows:
        if r['mode']=='v4': groups[r['size'],r['phase'],r['batch']].append(r)
    spikes=[]
    for r in rows:
        if r['wallNS']>5_000_000:
            peers=[q['instructions'] for q in groups[r['size'],r['phase'],r['batch']]
                   if (q['run'],q['sample'])!=(r['run'],r['sample']) and q['instructions'] is not None]
            spikes.append({**r,'peerCount':len(peers),'peerMaxInstructions':max(peers) if peers else None,
                           'verdict':classify(r['instructions'],peers) if r['mode']=='v4' else 'control-has-no-V4-counters'})
    dist=collections.defaultdict(list)
    for r in rows:dist[r['size'],r['mode'],r['phase']].append(r['wallNS'])
    availability=collections.Counter('observed' if r['instructions'] is not None else 'not-measured'
                                     for r in rows if r['mode']=='v4')
    return {'status':'bounded-iteration-complete','causalConclusion':'unresolved unless independently attributed; peer instruction ranges are not execution proof',
        'source':source,'files':meta_out,'calibration':calibration,'records':len(rows),
        'historicalTargetPositions':[{
            'size':n,'phase':'advance','batch':b,'instructions':d.distribution([q['instructions'] for q in groups[n,'advance',b] if q['instructions'] is not None]),
            'cycles':d.distribution([q['cycles'] for q in groups[n,'advance',b] if q['cycles'] is not None]),
            'note':'new peer observations only; historical instruction counts were not collected'}
             for n,b in ((50000,95),(50000,126),(100000,98))],
        'instructionAvailability':dict(availability),'physicalFallbackRequired':availability['not-measured']>0,
        'spikesAbove5ms':spikes,'distributions':[{'size':n,'mode':m,'phase':p,'wallNS':d.distribution(v)} for (n,m,p),v in sorted(dist.items())],
        'limits':['new observations cannot classify the historical three events retroactively','process PMU includes other threads/observer work',
                  'runnable raw is not wait-only; no undocumented unit conversion','no wall-clock CI acceptance gate','no physical iPhone measurement']}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('raw',type=Path,nargs='+');a=ap.parse_args()
    result=analyze(a.raw)
    with a.output.open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
    print('PASS complete bounded V4 streams; causal limits retained')
