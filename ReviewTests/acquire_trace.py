#!/usr/bin/env python3
"""Bounded, nonprivileged xctrace acquisition. Every attempted command keeps its status/log."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import xml.etree.ElementTree as ET
sys.dont_write_bytecode=True
from trace_report import analyze


def invoke(args, log, timeout=180):
    result={'command':list(map(str,args)), 'log':str(log), 'timedOut':False}
    with Path(log).open('xb') as stream:
        process=subprocess.Popen(result['command'],stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            result['timedOut']=True
            os.killpg(process.pid,signal.SIGINT)
            try:process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL);process.wait()
        result['returncode']=process.returncode
    return result


def dump(path,value):
    with Path(path).open('x') as stream:json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('binary',type=Path);parser.add_argument('source');parser.add_argument('output',type=Path)
    args=parser.parse_args();binary=args.binary.resolve(strict=True); out=args.output.resolve()
    if not re.fullmatch('[0-9a-f]{40}',args.source):raise ValueError('actual source SHA required')
    out.mkdir(exist_ok=False)
    manifest={'sourceCommit':args.source,'binarySHA256':hashlib.sha256(binary.read_bytes()).hexdigest(),
              'requests':[],'limits':['No privilege escalation. Requested template is not proof of useful data.',
                'All raw spikes/warmups retained; no automatic cause verdict or corrected latency.',
                'Profiler and unprofiled acquisitions must remain separate.']}
    try:
        for verb in ('record','export'):
            cmd=invoke(['xcrun','xctrace','help',verb],out/f'help-{verb}.txt');manifest['requests'].append(cmd)
            if cmd['returncode']!=0:raise RuntimeError('profiler help unavailable')
        cmd=invoke(['xcrun','xctrace','list','templates'],out/'templates.txt');manifest['requests'].append(cmd)
        if cmd['returncode']!=0:raise RuntimeError('template discovery failed')
        templates=(out/'templates.txt').read_text()
        for needed in ('--template','--output','--time-limit','--launch','--no-prompt'):
            if needed not in (out/'help-record.txt').read_text():raise ValueError('unverified xctrace option '+needed)
        # Independent unprofiled processes use the same binary and alternate marks per world.
        for n in (20000,50000,100000):
            raw=out/f'unprofiled-{n}.ndjson'
            cmd=invoke([binary,'--causal-trace',raw,args.source,str(n),'30','unprofiled'],out/f'unprofiled-{n}.txt')
            manifest['requests'].append(cmd)
            if cmd['returncode']!=0:raise RuntimeError('unprofiled correctness/acquisition failed')
            report=analyze(raw);dump(out/f'unprofiled-{n}-summary.json',report)
        attempts=[]
        for label,template,n in [('time-profiler','Time Profiler',20000),('time-profiler','Time Profiler',50000),
                                 ('time-profiler','Time Profiler',100000),('system-trace','System Trace',50000)]:
            entry={'label':label,'template':template,'aircraft':n,'usableRaw':False,'tocExported':False,'exports':[]}
            attempts.append(entry)
            if template not in [line.strip() for line in templates.splitlines()]:
                entry['status']='template-unavailable';continue
            stem=f'{label}-{n}';raw=out/(stem+'.ndjson');trace=out/(stem+'.trace')
            cmd=invoke(['xcrun','xctrace','record','--template',template,'--output',trace,'--time-limit','120s',
                        '--no-prompt','--launch','--',binary,'--causal-trace',raw,args.source,str(n),'30',label],out/(stem+'-record.txt'),160)
            manifest['requests'].append(cmd);entry['record']=cmd
            try:
                report=analyze(raw);dump(out/(stem+'-summary.json'),report);entry['usableRaw']=True
            except Exception as error:entry['rawError']=str(error)
            if trace.exists():
                toc=out/(stem+'-toc.xml')
                export=invoke(['xcrun','xctrace','export','--input',trace,'--toc','--output',toc],out/(stem+'-toc.txt'))
                manifest['requests'].append(export)
                if export['returncode']==0:
                    try:
                        root=ET.parse(toc).getroot();entry['tocExported']=True
                        schemas=sorted({t.attrib['schema'] for t in root.iter('table') if 'schema' in t.attrib})
                        entry['availableSchemas']=schemas
                        selected=[s for s in schemas if any(k in s.lower() for k in ('signpost','time-profile','cpu-profile','thread-state','context-switch','sched'))][:8]
                        entry['selectedSchemas']=selected
                        for schema in selected:
                            xml=out/f'{stem}-{schema}.xml'
                            xp=f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
                            exported=invoke(['xcrun','xctrace','export','--input',trace,'--xpath',xp,'--output',xml],out/f'{stem}-{schema}-export.txt')
                            manifest['requests'].append(exported)
                            record={'schema':schema,'returncode':exported['returncode'],'rows':None}
                            if exported['returncode']==0:
                                count=0
                                for _,element in ET.iterparse(xml,events=('end',)):
                                    if element.tag=='row':count+=1
                                    element.clear()
                                record['rows']=count
                            entry['exports'].append(record)
                    except Exception as error:entry['exportError']=str(error)
            entry['status']='recorded-needs-causal-review' if cmd['returncode']==0 and entry['usableRaw'] and entry['tocExported'] else 'acquisition-incomplete'
        manifest['attempts']=attempts
        manifest['status']='acquisition-requests-completed' if all(e['status']=='recorded-needs-causal-review' for e in attempts) else 'partial-or-unavailable-acquisition'
    except Exception as error:
        manifest['status']='acquisition-failed';manifest['error']=str(error)
    finally:
        dump(out/'acquisition.json',manifest)
    if manifest['status']!='acquisition-requests-completed':raise SystemExit(1)
    print('Acquisition complete; actual stacks, markers and scheduling must be reviewed before any causal verdict.')


if __name__=='__main__':main()
