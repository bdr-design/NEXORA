#!/usr/bin/env python3
import argparse, json, os, selectors, shutil, signal, subprocess, tempfile, time
from pathlib import Path

POINTS=[
 ("c.k1.after_begin",1),("c.k2.after_first_barrier",1),("c.k3.mid_record",1),
 ("c.k4.before_footer",1),("c.k5.after_footer",1),("c.k6.after_fsync",1),
 ("c.k7.after_rename",1),("c.k8.after_dirsync",2),
 ("c.k9.mid_wal_record",2),("c.k10.peak_queue",1),
]

def env_for(binary):
    e=dict(os.environ)
    observer=e.get("NXR_ALLOCATOR_DYLIB")
    if observer:
        e["DYLD_INSERT_LIBRARIES"]=str(Path(observer).resolve())
    return e

def run(binary,*args,timeout=900):
    cp=subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,
                      timeout=timeout,env=env_for(binary))
    if cp.returncode:
        raise RuntimeError((args,cp.returncode,cp.stderr[-4000:]))
    return json.loads(cp.stdout)

def kill_at(binary,directory,point,command="stage-c-crash-action"):
    e=env_for(binary);e["NXR_KILL_AT"]=point
    argv=[str(binary),command,str(directory)]
    if command=="stage-c-crash-action": argv.append(point)
    p=subprocess.Popen(argv,
        env=e,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
    seen=b"";deadline=time.monotonic()+1800
    try:
        while time.monotonic()<deadline:
            if selector.select(timeout=1):
                chunk=os.read(p.stdout.fileno(),4096);seen+=chunk
                if ("KILL_POINT:"+point+"\n").encode() in seen:
                    os.kill(p.pid,signal.SIGKILL);p.communicate(timeout=30)
                    if p.returncode != -signal.SIGKILL:
                        raise AssertionError(("not SIGKILL",point,p.returncode))
                    return
                if not chunk: break
        raise AssertionError(("kill point not reached",point,seen[-2000:],p.poll()))
    finally:
        selector.close()
        if p.poll() is None:
            p.kill();p.communicate(timeout=30)

def main():
    a=argparse.ArgumentParser();a.add_argument("binary",type=Path);a.add_argument("output",type=Path)
    args=a.parse_args();binary=args.binary.resolve()
    results=[]
    with tempfile.TemporaryDirectory(prefix="nxr-stage005-c-kill-") as temp:
        root=Path(temp);base=root/"base"
        bootstrap=run(binary,"stage-c-crash-bootstrap",base,1000000,timeout=3600)
        baseline=bootstrap["digest"]
        for point,epoch in POINTS:
            case=root/("case-"+point.replace(".","-"));shutil.copytree(base,case)
            kill_at(binary,case,point)
            restored=run(binary,"stage-c-recover",case,timeout=1800)
            assert restored["epoch"]==epoch,(point,restored,epoch)
            assert restored["digest"]==baseline,(point,"digest mismatch")
            results.append({"point":point,"signal":"SIGKILL","expectedEpoch":epoch,
                            "restoredEpoch":restored["epoch"],"exactDigest":True,
                            "ignoredWALTailBytes":restored["ignoredWALTailBytes"]})
            shutil.rmtree(case)

        reference=root/"chain-reference";shutil.copytree(base,reference)
        expected=run(binary,"stage-c-chain-expected",reference,timeout=1800)
        chain=root/"chain-crash";shutil.copytree(base,chain)
        kill_at(binary,chain,"c.chain.after_wal",command="stage-c-chain-crash")
        chained=run(binary,"stage-c-recover",chain,timeout=1800)
        assert chained["epoch"]==1,(chained,"fallback must use previous snapshot")
        assert chained["processed"]==expected["processed"],(chained,expected)
        assert chained["digest"]==expected["digest"],("chained WAL digest mismatch",chained,expected)
        assert chained["replayedCommands"]>=1,chained
        chain_fallback={"point":"c.chain.after_wal","signal":"SIGKILL",
                        "baseSnapshotEpoch":1,"replayedThroughWAL":2,
                        "exactDigest":True,"processed":chained["processed"]}
    report={"status":"pass","population":1000000,"points":10,"results":results,
            "chainFallback":chain_fallback,
            "limit":"real process SIGKILL, not physical power loss"}
    args.output.write_text(json.dumps(report,indent=2)+"\n")
    print("PASS Stage C",len(results),"SIGKILL points at 1M")

if __name__=="__main__":main()
