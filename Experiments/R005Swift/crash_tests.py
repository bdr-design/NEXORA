#!/usr/bin/env python3
"""Real SIGKILL tests against disposable, caller-owned fixture directories only."""
import argparse, json, os, selectors, shutil, signal, subprocess, tempfile, time, zlib
from pathlib import Path

WAL_POINTS = ['wal.before_header','wal.after_header','wal.mid_payload','wal.before_commit','wal.mid_commit',
              'wal.after_commit','wal.after_sync','wal.after_directory_sync','transaction.after_apply']
SNAPSHOT_POINTS = ['snapshot.before_header','snapshot.after_header','snapshot.mid_columns','snapshot.after_columns',
                   'snapshot.after_footer','snapshot.after_sync','snapshot.before_rename','snapshot.after_rename','snapshot.after_directory_sync']
SUMMARY_POINTS = ['summary.after_temp','summary.before_manifest','summary.after_manifest','summary.before_reclaim','summary.after_reclaim']

def run(binary, *args, ok=True):
    p = subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,timeout=90)
    if ok and p.returncode != 0:
        raise AssertionError((args,p.returncode,p.stdout,p.stderr))
    if not ok:
        if p.returncode == 0: raise AssertionError(('accepted corrupt storage',args,p.stdout))
        return p.stderr.strip()
    return json.loads(p.stdout)

def kill_at(binary, args, point):
    p = subprocess.Popen([str(binary),*map(str,args)],env={**os.environ,'NXR_KILL_AT':point},stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    selector = selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
    seen = b''; deadline=time.monotonic()+90
    try:
        while time.monotonic()<deadline:
            if selector.select(timeout=1):
                chunk=os.read(p.stdout.fileno(),4096);seen += chunk
                if ('KILL_POINT:'+point+'\n').encode() in seen:
                    os.kill(p.pid,signal.SIGKILL);out,err=p.communicate(timeout=10)
                    if p.returncode != -signal.SIGKILL:raise AssertionError(('not SIGKILL',p.returncode,err))
                    return {'point':point,'actualSignal':'SIGKILL','returnCode':p.returncode}
                if not chunk:break
        raise AssertionError(('injection point not reached',point,seen,p.poll()))
    finally:
        selector.close()
        if p.poll() is None:p.kill();p.communicate(timeout=10)

def main():
    a=argparse.ArgumentParser();a.add_argument('binary',type=Path);a.add_argument('output',type=Path);args=a.parse_args()
    binary=args.binary.resolve();results=[];rejections=[]
    with tempfile.TemporaryDirectory(prefix='nxr-r005-crash-') as temp:
        root=Path(temp);base=root/'base';run(binary,'bootstrap',base,32)
        for point in WAL_POINTS+SNAPSHOT_POINTS:
            case=root/point;shutil.copytree(base,case)
            kind='snapshot' if point.startswith('snapshot.') else 'wal'
            observed=kill_at(binary,['crash-action',case,kind],point)
            restored=run(binary,'recover',case)
            expected=0 if point in WAL_POINTS[:5] else 1
            assert restored['sequence']==expected and restored['processed']==expected*5,(point,restored,expected)
            observed.update(restored, expectedCommittedSequence=expected);results.append(observed)
        complete=root/'complete';shutil.copytree(base,complete);run(binary,'crash-action',complete,'wal')
        raw=(complete/'commands.wal').read_bytes();assert len(raw)==48
        for cut in range(1,48):
            case=root/f'torn-{cut}';shutil.copytree(base,case);(case/'commands.wal').write_bytes(raw[:cut])
            r=run(binary,'recover',case);assert r['sequence']==0 and r['ignoredUncommittedTailBytes']==cut
        for pos in (0,8,12,20,28,36,40,47):
            case=root/f'wal-corrupt-{pos}';shutil.copytree(base,case);damaged=bytearray(raw);damaged[pos]^=1
            (case/'commands.wal').write_bytes(damaged);rejections.append({'fault':f'wal-byte-{pos}','error':run(binary,'recover',case,ok=False)})
        raw_snapshot=(base/'checkpoint.bin').read_bytes()
        for pos in (0,12,24,80,len(raw_snapshot)-1):
            case=root/f'snapshot-corrupt-{pos}';shutil.copytree(base,case);bad=bytearray(raw_snapshot);bad[pos]^=1
            (case/'checkpoint.bin').write_bytes(bad);rejections.append({'fault':f'snapshot-byte-{pos}','error':run(binary,'recover',case,ok=False)})
        ledger=root/'ledger';run(binary,'make-ledger',ledger,128)
        for point in SUMMARY_POINTS:
            case=root/point;shutil.copytree(ledger,case)
            observed=kill_at(binary,['compact-ledger',case,128],point)
            restored=run(binary,'recover-ledger',case,128)
            expected=0 if point in SUMMARY_POINTS[:2] else 1
            assert restored['generation']==expected,(point,restored)
            observed.update(restored,expectedManifestGeneration=expected);results.append(observed)
        compact=root/'compacted';shutil.copytree(ledger,compact);run(binary,'compact-ledger',compact,128)
        # Recompute the CRC after altering money: arithmetic validation, not only checksum protection.
        case=root/'bad-summary-total';shutil.copytree(compact,case)
        summary=bytearray((case/'summary.bin').read_bytes());offset=56+16
        amount=int.from_bytes(summary[offset:offset+8],'little',signed=True)+1
        summary[offset:offset+8]=amount.to_bytes(8,'little',signed=True)
        summary[-4:]=(zlib.crc32(summary[:-4]) & 0xffffffff).to_bytes(4,'little')
        (case/'summary.bin').write_bytes(summary);rejections.append({'fault':'summary amount with valid CRC','error':run(binary,'recover-ledger',case,128,ok=False)})
        # Attempt to falsely mark a protected item as collected; compactor must reject it.
        case=root/'bad-open';shutil.copytree(ledger,case)
        detail=bytearray((case/'detail.bin').read_bytes());detail[16+56:16+60]=(2).to_bytes(4,'little')
        (case/'detail.bin').write_bytes(detail);rejections.append({'fault':'open item falsely settled','error':run(binary,'compact-ledger',case,128,ok=False)})
    report={'status':'pass','realSIGKILLCases':len(results),'killPoints':results,'tornTailLengthsRejectedFromReplay':47,
            'corruptionOrArithmeticRejections':rejections,'limits':'process kill, not power cut; entire prepared frame is committed when its verified marker is present; post-sync is the durability ACK. No partial frame replay.'}
    with args.output.open('x') as f:json.dump(report,f,indent=2);f.write('\n')
    print('PASS',len(results),'SIGKILL points; 47 torn tails;',len(rejections),'corruption/summary negatives')
if __name__=='__main__':main()
