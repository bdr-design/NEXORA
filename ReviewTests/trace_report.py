#!/usr/bin/env python3
"""Validate the separate causal-acquisition stream. No scheduling/causal inference."""
import argparse
from collections import defaultdict
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fdiag', ROOT/'Checks/financial-diagnostics.py')
diag = importlib.util.module_from_spec(spec); spec.loader.exec_module(diag)
BASE = '74d8a7f1d072209aee3d8e7e964d76468890a694'


def analyze(path):
    metadata, complete = None, False
    calibration, seen = set(), []
    distribution, totals, first = defaultdict(list), defaultdict(list), defaultdict(list)
    spikes, first_warmups = [], []
    with Path(path).open() as reader:
        for lineno, line in enumerate(reader, 1):
            item = json.loads(line, object_pairs_hook=diag.unique_object, parse_constant=diag.reject_constant)
            diag.check(not complete, 'data after completion')
            diag.check(type(item) is dict, 'record must be object')
            kind = item.get('kind')
            if kind == 'traceMetadata':
                diag.check(metadata is None and lineno == 1, 'metadata not unique/first')
                diag.object_fields(item, ('kind','schema','sourceCommit','sourceBase','aircraft','repetitions',
                    'warmups','processID','os','profileLabel','counters','limitations'))
                diag.check(item['schema']=='NXR-R004-CAUSAL-1' and item['sourceBase']==BASE, 'wrong trace protocol/base')
                diag.check(type(item['sourceCommit']) is str and re.fullmatch('[0-9a-f]{40}',item['sourceCommit']), 'source SHA')
                diag.check(type(item['aircraft']) is int and item['aircraft'] in (20000,50000,100000), 'size')
                diag.check(type(item['repetitions']) is int and 1<=item['repetitions']<=30 and item['warmups']==3, 'schedule')
                diag.check(item['profileLabel'] in ('unprofiled','time-profiler','system-trace'), 'profile label')
                diag.validate_metadata(item['counters'])
                diag.check(item['counters']['sourceCommit']==item['sourceCommit']
                    and item['counters']['processID']==item['processID'] and item['counters']['os']==item['os'], 'source/process consistency')
                metadata = item
            elif kind == 'traceCalibration':
                diag.check(metadata is not None and not seen, 'calibration order')
                diag.object_fields(item,('kind','marked','loopNS','samplesNS','begins','ends'))
                for field in ('begins','ends'): diag.unsigned(item[field], field)
                marked = item['marked']; diag.check(type(marked) is bool and marked not in calibration, 'duplicate calibration')
                diag.check(type(item['samplesNS']) is list and len(item['samplesNS'])==2000, 'calibration count')
                for value in item['samplesNS']: diag.unsigned(value,'calibration duration')
                diag.unsigned(item['loopNS'],'calibration loop')
                diag.check(sum(item['samplesNS'])<=item['loopNS'], 'calibration chronology')
                diag.check(item['begins']==item['ends']==(2000 if marked else 0),'unpaired calibration marks')
                calibration.add(marked)
                totals[(marked,'markerCalibrationNS')].extend(item['samplesNS'])
            elif kind == 'traceSample':
                diag.check(metadata is not None and calibration=={False,True}, 'missing metadata/calibration')
                diag.object_fields(item, ('kind','marked','world','fixture','begins','ends'))
                for field in ('begins','ends'): diag.unsigned(item[field],field)
                marked, world, fixture = item['marked'], item['world'], item['fixture']
                diag.check(type(marked) is bool and type(world) is int, 'sample identity types')
                expected_world = len(seen)//2+1
                order = (False,True) if expected_world%2==0 else (True,False)
                diag.check(world==expected_world and marked==order[len(seen)%2], 'missing/reordered/duplicate world')
                diag.check(world<=metadata['repetitions']+3, 'extra world')
                n=metadata['aircraft']
                diag.validate_item_shape(fixture)
                diag.check(fixture['aircraft']==n and fixture['sample']==world and fixture['warmup']==(world<=3)
                    and type(fixture['warmup']) is bool and fixture['mode']=='counters' and fixture['runID']==1
                    and fixture['executionOrder']==order.index(marked), 'fixture identity')
                diag.validate_records(fixture['records'],count=n,sample=world,mode='counters')
                diag.phase_validation(fixture); diag.validate_lifecycle(fixture)
                diag.check(item['begins']==item['ends']==(len(fixture['records']) if marked else 0),'unpaired batch marks')
                agg=fixture['aggregate']; income=sum(i%97+101 for i in range(n))
                diag.check((agg['invoiceCount'],agg['journalCount'],agg['advanceBatches'],agg['revenueMinor'],agg['cashMinor'])
                    ==(n,2*n+4,(n+255)//256,income,income-5000),'changed economics')
                seen.append((world,marked))
                for row in fixture['records']:
                    annotated={'world':world,'marked':marked,**row,
                        'counterDeltas':{f:{'value':diag.counter_delta(row,f)[0],'status':diag.counter_delta(row,f)[1]} for f in diag.FIELDS}}
                    if world<=3:
                        if row['batch']==0: first_warmups.append(annotated)
                        continue
                    key=(marked,row['phase']); distribution[key].append(row['wallNS'])
                    if row['batch']==0: first[key].append(row['wallNS'])
                    if row['wallNS']>1_000_000: spikes.append(annotated)
                if world>3:
                    for field in diag.AGGREGATE_TIMES: totals[(marked,field)].append(agg[field])
                    for field in diag.LIFECYCLE_TIMES: totals[(marked,field)].append(fixture[field])
            elif kind=='traceComplete':
                diag.object_fields(item,('kind','status'));diag.check(item['status']=='all-fixture-checks-passed','failed completion')
                complete=True
            else:
                raise ValueError('unknown or failed trace record: '+str(kind))
    diag.check(metadata is not None and complete and len(seen)==2*(metadata['repetitions']+3),'incomplete trace stream')
    return {'status':'valid-raw-acquisition-not-causal-proof','file':Path(path).name,
        'sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'metadata':metadata,
        'batches':[{'marked':m,'phase':p,'wallNS':diag.distribution(v),'firstBatchNS':diag.distribution(first[(m,p)]),
            'above1ms':sum(x>1_000_000 for x in v),'above5ms':sum(x>5_000_000 for x in v)}
            for (m,p),v in sorted(distribution.items())],
        'totals':[{'marked':m,'field':f,'ns':diag.distribution(v)} for (m,f),v in sorted(totals.items())],
        'spikesAbove1ms':spikes,'warmupFirstBatches':first_warmups,
        'limits':['Marked and unmarked worlds alternate; changed addresses/hashes/cache state still confound pairs.',
                  'Counter brackets include marker cost; wall brackets exclude it, phase/lifecycle totals include it.',
                  'Raw data valid does not mean xctrace recorded usable stacks/scheduler events or that markers were captured.',
                  'Never combine these new measurements with old schema-1 batch statistics as one campaign.']}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('raw',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args(); result=analyze(args.raw)
    with args.output.open('x') as writer: json.dump(result,writer,indent=2,sort_keys=True);writer.write('\n')
    print('PASS complete causal raw stream; profiler usability/causality must be checked separately')
