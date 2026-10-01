#!/usr/bin/env python3
import json, os, selectors, shutil, signal, subprocess, sys, tempfile, time
from pathlib import Path

binary=Path(sys.argv[1]).resolve(); out=Path(sys.argv[2]).resolve()
points=[
 ('b.s1.mid_summary_append',-1),
 ('b.s2.after_summary_sync',-1),
 ('b.s3.after_carry_sync',-1),
 ('b.s4.after_manifest_sync',0),
 ('b.s5.after_delete_before_dirsync',0),
]

def run(*args):
    cp=subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,timeout=180)
    if cp.returncode: raise RuntimeError((args,cp.returncode,cp.stderr[-4000:]))
    return json.loads(cp.stdout)

def kill_at(directory,point):
    p=subprocess.Popen([str(binary),'stage-b-crash-action',str(directory)],env={**os.environ,'NXR_KILL_AT':point},stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    sel=selectors.DefaultSelector();sel.register(p.stdout,selectors.EVENT_READ);seen=b'';deadline=time.monotonic()+180
    try:
        while time.monotonic()<deadline:
            if sel.select(timeout=1):
                chunk=os.read(p.stdout.fileno(),4096);seen+=chunk
                if ('KILL_POINT:'+point+'\n').encode() in seen:
                    os.kill(p.pid,signal.SIGKILL);p.communicate(timeout=10)
                    if p.returncode != -signal.SIGKILL: raise AssertionError((point,p.returncode))
                    return
                if not chunk: break
        raise AssertionError(('point not reached',point,seen[-1000:],p.poll()))
    finally:
        sel.close()
        if p.poll() is None: p.kill();p.communicate(timeout=10)

results=[]
with tempfile.TemporaryDirectory(prefix='nxr-stage005-b-kill-') as temp:
    root=Path(temp);base=root/'base';run('stage-b-crash-bootstrap',base)
    for point,expected in points:
        case=root/point;shutil.copytree(base,case);kill_at(case,point)
        restored=run('stage-b-recover-crash',case)
        assert restored['totalsExact'] is True
        assert restored['committedSegment']==expected,(point,restored,expected)
        results.append({'point':point,'signal':'SIGKILL','expectedCommittedSegment':expected,'restored':restored})
report={'status':'pass','points':5,'results':results,'limit':'process SIGKILL, not physical power cut'}
out.write_text(json.dumps(report,indent=2)+'\n')
print('PASS Stage B',len(results),'SIGKILL points')
