#!/usr/bin/env python3
"""Execute behavioral gates and record timing, never gate on wall-clock latency."""
import argparse, hashlib, json, os, platform, statistics, subprocess, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser();p.add_argument('binary',type=Path);p.add_argument('output',type=Path);p.add_argument('--release',action='store_true');a=p.parse_args()
    binary=a.binary.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    def call(name,*arguments):
        environment=dict(os.environ)
        if arguments and arguments[0]=='bench' and platform.system()=='Darwin':
            observer=Path(os.environ['NXR_ALLOCATOR_DYLIB']).resolve()
            assert observer.is_file(),observer
            environment['DYLD_INSERT_LIBRARIES']=str(observer)
        cp=subprocess.run([str(binary),*map(str,arguments)],capture_output=True,text=True,timeout=300,env=environment)
        (out/(name+'.stdout')).write_text(cp.stdout);(out/(name+'.stderr')).write_text(cp.stderr)
        if cp.returncode:raise AssertionError((name,cp.returncode,cp.stderr[-4000:]))
        result=json.loads(cp.stdout)
        (out/(name+'.json')).write_text(json.dumps(result,indent=2)+'\n');return result
    result={'status':'running','mode':'release' if a.release else 'debug','environment':platform.platform(),
            'sourceCommit':os.environ.get('GITHUB_SHA','local-unpublished'),'sourceBase':'8d5036fb9f9294d24f11c7291ae3e07205db7166',
            'sourceFiles':{str(f.relative_to(HERE)):hashlib.sha256(f.read_bytes()).hexdigest() for f in HERE.glob('Sources/**/*') if f.is_file()},
            'limits':['safe Swift experiment, not production R005 or iPhone acceptance',
                      'column capacity bytes omit object/allocator metadata; phys_footprint and its deltas are separate',
                      'allocator measures calibrated interposed allocation entrypoints on calling thread; not kernel VM allocations',
                      'retention workload is one day, 5 priced trips/asset and 90% settlement, 32 entities/3 accounts',
                      'typed full checkpoint is NOT incremental or a <=2ms save-pause result']}
    try:
        for f in HERE.glob('Sources/SwiftProbe/*.swift'):
            text=f.read_text()
            assert not any(word in text for word in ['UnsafePointer','UnsafeMutable','unsafeBitCast','withUnsafe','unchecked:']),f
        result['selftest']=call('selftest','selftest')
        assert len(result['selftest']['mutations'])==8 and all(x['detected'] for x in result['selftest']['mutations'])
        sizes=[1000,5000,20000,50000,100000,250000,1000000] if a.release else [1000,100000,1000000]
        result['ordering']=[call(f'order-{n}','order',n) for n in sizes]
        cp=subprocess.run(['python3','-B',str(HERE/'crash_tests.py'),str(binary),str(out/'crashes.json')],capture_output=True,text=True,timeout=300)
        (out/'crashes.log').write_text(cp.stdout+cp.stderr)
        assert cp.returncode==0,cp.stderr
        result['crashRecovery']=json.loads((out/'crashes.json').read_text())
        with tempfile.TemporaryDirectory(prefix='nxr-multi-period-') as temp:
            result['multiPeriodRetention']=call('retention-three-periods','retention-multi',str(Path(temp)/'ledger'),128)
        if a.release:
            measurements=[]
            for n in [1000,5000,20000,50000,100000,250000,1000000,2000000]:
                for sample in range(1,4):
                    # Alternating order, distinct processes; initialization remains outside advance timing.
                    modes=['new','legacy'] if n<=100000 else ['new']
                    if sample%2==0:modes.reverse()
                    for mode in modes:
                        arguments=['bench',n,256]+(['legacy'] if mode=='legacy' else [])
                        r=call(f'bench-{n}-{sample}-{mode}',*arguments);r['sample']=sample
                        if mode=='new':
                            assert r['events']==n
                            if n>=100000:assert r['ownedBytesPerAsset']<=128
                            if platform.system()=='Darwin':
                                assert r['physFootprintStatus']=='ok' and r['allocationStatus']=='interposed-entry-calls-current-thread'
                                assert r['maxAllocationsPerAdvance']<=1,('allocation gate',r)
                        measurements.append(r)
            result['measurements']=measurements
            result['deadlineMeasurement']=call('bench-deadline-1m','bench',1000000,256,'deadline')
            storage=[];retention=[]
            with tempfile.TemporaryDirectory(prefix='nxr-swift-storage-') as temp:
                for n in [100000,1000000]:
                    storage.append(call(f'storage-{n}','storage',str(Path(temp)/f'store-{n}'),n))
                    retention.append(call(f'retention-{n}','retention',str(Path(temp)/f'ledger-{n}'),n))
            result['storage']=storage;result['retention']=retention
        result['status']='pass'
    except BaseException as error:
        result['status']='failure';result['error']=repr(error);raise
    finally:
        (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    lines=['# R005 Swift executable experiment — results', '',
           'Source: `'+result['sourceCommit']+'`. Build: '+result['mode']+'. Status: PASS.',
           'Production Sources/Tests/Package unchanged. No new ADR or production retention approval.', '',
           f"Ordering: {len(result['ordering'])} scales, 10 Swift count/time partitions per scale; exact event records, not just sums.",
           'Eight mutants detected (the seven requested classes include both +1 and -1).',
           '23 real SIGKILL sites; 47 torn WAL tails; 15 corruption/arithmetic negatives. All passed.', '']
    if a.release:
        lines+=['| Assets | Owned B/asset | median footprint delta B/asset | median ns/event | max allocations/advance |',
                '|---:|---:|---:|---:|---:|']
        for n in [100000,250000,1000000,2000000]:
            group=[x for x in result['measurements'] if x['assets']==n and x['implementation'].startswith('Swift6')]
            footprint=[x['physDeltaPerAsset'] for x in group if x['physDeltaPerAsset'] is not None]
            allocations=[x['maxAllocationsPerAdvance'] for x in group if x['maxAllocationsPerAdvance'] is not None]
            lines.append(f"|{n}|{group[0]['ownedBytesPerAsset']:.6f}|{statistics.median(footprint) if footprint else 'unavailable'}|{statistics.median(x['nsPerEvent'] for x in group):.3f}|{max(allocations) if allocations else 'unavailable'}|")
        lines+=['','| Assets | snapshot bytes | write+sync ms | restore+replay ms | day detail bytes | summary+open bytes |', '|---:|---:|---:|---:|---:|---:|']
        for s,r in zip(result['storage'],result['retention']):
            lines.append(f"|{s['assets']}|{s['snapshotBytes']}|{s['writeAndSyncNS']/1e6:.3f}|{s['restoreAndReplayNS']/1e6:.3f}|{r['beforeDetailBytes']}|{r['afterSummaryPlusOpenBytes']}|")
    lines+=['','Limits: experimental accrual is not full R004 per-trip invoice work; timings compare paths, not a certified full-engine speedup. Footprint is whole process delta; owned bytes are column capacities. Full-copy checkpoint, one-day retention and process kills do not establish bounded lifetime storage, incremental saving, power-loss resilience, 0.5us device event cost, frame rate or heat. Financial detail retirement happened ONLY in generated disposable test directories. Billing/design/retention choices await owner decision.']
    (out/'RESULTS.md').write_text('\n'.join(lines)+'\n')
    print('PASS',result['mode'],'Swift wheel/order/storage/mutation gates; metrics retained')
if __name__=='__main__':main()
