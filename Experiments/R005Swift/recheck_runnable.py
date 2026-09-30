"""Re-read pinned historical artifact only. No new workload or guessed time conversion."""
import zipfile,json,hashlib,collections,sys
from pathlib import Path
p=Path(sys.argv[1]);out=Path(sys.argv[2]);sha=hashlib.sha256(p.read_bytes()).hexdigest()
assert sha=='6eb273848b9e37eb074dac106e6bf86269cbbfe4afb1337a1d2d8f286dd9354e'
report={'artifact':11115497993,'sha256':sha,'measuredBatches':0,'v4Batches':0,'allSpikesAbove5ms':0,'v4Spikes':[], 'runnableDeltaStatus':{},'files':[]}
counts=collections.Counter()
with zipfile.ZipFile(p) as z:
 for name in ['v4-1.ndjson','v4-2.ndjson','v4-3.ndjson']:
  h=hashlib.sha256();samples=0;complete=False
  for raw in z.open(name):
   h.update(raw);a=json.loads(raw)
   if a.get('kind')=='complete':complete=True
   if a.get('kind')!='sample' or a['warmup']:continue
   samples+=1
   rows=a['fixture']['records'];report['measuredBatches']+=len(rows)
   report['allSpikesAbove5ms']+=sum(r['wallNS']>5000000 for r in rows)
   if a['mode']!='v4':continue
   report['v4Batches']+=len(rows);assert len(rows)==len(a['v4'])
   for r,v in zip(rows,a['v4']):
    b,e=v['before']['runnableRaw'],v['after']['runnableRaw']
    assert b['status']==e['status']=='ok';delta=e['value']-b['value']
    counts['decreased' if delta<0 else 'zero' if delta==0 else 'positive']+=1
    if r['wallNS']>5000000:
     report['v4Spikes'].append({'file':name,'run':a['run'],'sample':a['sample'],'size':a['size'],'phase':r['phase'],'batch':r['batch'], 'wallNS':r['wallNS'],'enclosingThreadCPUNS':r['after']['threadCPUNS']-r['before']['threadCPUNS'],'runnableBeforeRaw':b['value'],'runnableAfterRaw':e['value'],'runnableDeltaRaw':delta,'contextSwitchProcessDelta':r['after']['processInvoluntarySwitches']-r['before']['processInvoluntarySwitches']})
  assert complete and samples==180
  report['files'].append({'name':name,'sha256':h.hexdigest(),'measuredWorlds':samples})
report['runnableDeltaStatus']=dict(counts)
assert report['measuredBatches']==359640 and report['v4Batches']==179820 and len(report['v4Spikes'])==13
report['meaning']='XNU runnable_timer includes running; exported value aggregates task threads. This artifact has no captured Mach timebase; values remain raw, not wait-only nanoseconds. Counter windows differ. No causal classification from raw subtraction.'
report['sourceReferences']=['apple-oss-distributions/xnu osfmk/kern/thread.h runnable_timer','apple-oss-distributions/xnu osfmk/kern/task.c task_power_info_locked','apple-oss-distributions/xnu osfmk/kern/bsd_kern.c fill_task_rusage']
report['status']='historical-reanalysis-complete; causal verdict unchanged'
out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['v4Spikes','files','sourceReferences']},indent=2))
