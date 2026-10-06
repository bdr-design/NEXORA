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

def kill_at(directory,point,action='stage-b-crash-action'):
    p=subprocess.Popen([str(binary),action,str(directory)],env={**os.environ,'NXR_KILL_AT':point},stdout=subprocess.PIPE,stderr=subprocess.PIPE)
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
continuations=[]
with tempfile.TemporaryDirectory(prefix='nxr-stage005-b-kill-') as temp:
    root=Path(temp);base=root/'base';run('stage-b-crash-bootstrap',base)
    for point,expected in points:
        case=root/point;shutil.copytree(base,case);kill_at(case,point)
        restored=run('stage-b-recover-crash',case)
        assert restored['totalsExact'] is True
        assert restored['committedSegment']==expected,(point,restored,expected)
        results.append({'point':point,'signal':'SIGKILL','expectedCommittedSegment':expected,'restored':restored})
    committed_first=root/'committed-first';shutil.copytree(base,committed_first)
    run('stage-b-crash-action',committed_first)
    first_frame=(committed_first/'manifest.log').read_bytes()
    assert len(first_frame)==64
    committed_second=root/'committed-second';shutil.copytree(committed_first,committed_second)
    full=run('stage-b-recover-append',committed_second,1)
    assert full['committedSegment']==1
    both_frames=(committed_second/'manifest.log').read_bytes()
    assert len(both_frames)==128 and both_frames[:64]==first_frame

    # Both fixtures contain synchronized, uncommitted summary/carry files from a real SIGKILL.
    # Only the manifest tail is synthesized, byte-for-byte from the valid next frame.
    for segment,baseline,frame in ((0,base,first_frame),(1,committed_first,both_frames[64:])):
        prepared=root/f'prepared-{segment}';shutil.copytree(baseline,prepared)
        action='stage-b-crash-action' if segment==0 else 'stage-b-crash-append-action'
        kill_at(prepared,'b.s3.after_carry_sync',action)
        for cut in (1,7,31,63):
            case=root/f'append-{segment}-tail-{cut}';shutil.copytree(prepared,case)
            with (case/'manifest.log').open('ab') as h:h.write(frame[:cut])
            appended=run('stage-b-recover-append',case,segment)
            recovered=run('stage-b-recover-crash',case)
            assert appended['committedSegment']==recovered['committedSegment']==segment
            assert recovered['totalsExact'] and (case/'manifest.log').read_bytes()==both_frames[:64*(segment+1)]
            continuations.append({'previousCommittedSegment':segment-1,'tornTailBytes':cut,
                                  'newCommittedSegment':segment,'manifestBytes':appended['manifestBytes'],
                                  'secondRecoveryExact':recovered['totalsExact']})

    corrupt=root/'corrupt-full-frame';shutil.copytree(committed_first,corrupt)
    damaged=bytearray(both_frames[64:]);damaged[10]^=1
    with (corrupt/'manifest.log').open('ab') as h:h.write(damaged)
    p=subprocess.run([str(binary),'stage-b-recover-crash',str(corrupt)],capture_output=True,text=True,timeout=180)
    assert p.returncode!=0 and 'B manifest committed record' in p.stderr
    assert (corrupt/'manifest.log').read_bytes()==first_frame+damaged

    short=root/'short-committed-summary';shutil.copytree(committed_first,short)
    summary=short/'summary.delta';summary.write_bytes(summary.read_bytes()[:-1])
    p=subprocess.run([str(binary),'stage-b-recover-crash',str(short)],capture_output=True,text=True,timeout=180)
    assert p.returncode!=0 and 'B committed summary truncated' in p.stderr

    direct=root/'direct-append-torn';shutil.copytree(committed_first,direct)
    with (direct/'manifest.log').open('ab') as h:h.write(both_frames[64:77])
    before=(direct/'manifest.log').read_bytes()
    p=subprocess.run([str(binary),'stage-b-crash-append-action',str(direct)],capture_output=True,text=True,timeout=180)
    assert p.returncode!=0 and 'B manifest requires recovery before append' in p.stderr
    assert (direct/'manifest.log').read_bytes()==before
    healed=run('stage-b-recover-append',direct,1)
    assert healed['committedSegment']==1 and (direct/'manifest.log').read_bytes()==both_frames
    assert run('stage-b-recover-crash',direct)['totalsExact']

report={'status':'pass','points':5,'results':results,'recoverAppendRecoverCases':continuations,
        'fullCorruptFrameRejected':True,'shortCommittedSummaryRejected':True,
        'directAppendBeforeRecoveryRejectedAndHealed':True,
        'limit':'process SIGKILL, not physical power cut'}
out.write_text(json.dumps(report,indent=2)+'\n')
print('PASS Stage B',len(results),'SIGKILL points,',len(continuations),'recover-append-recover cases')
