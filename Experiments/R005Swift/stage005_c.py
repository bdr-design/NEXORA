#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile
from pathlib import Path

binary=Path(sys.argv[1]).resolve()
output=Path(sys.argv[2]).resolve()
stage_a=Path(sys.argv[3]).resolve()
a=json.loads(stage_a.read_text())
assert a["status"]=="pass",a.get("status")
chosen=a["decisionA"]["chosen"]
assert chosen in ("S","H"),a["decisionA"]

environment=dict(os.environ)
observer=Path(environment["NXR_ALLOCATOR_DYLIB"]).resolve()
assert observer.is_file(),observer
environment["DYLD_INSERT_LIBRARIES"]=str(observer)

with tempfile.TemporaryDirectory(prefix="nxr-stage005-c-") as temp:
    store=Path(temp)/"store"
    cp=subprocess.run([str(binary),"stage-c-h" if chosen=="H" else "stage-c",str(store),"1000000","100"],
        capture_output=True,text=True,timeout=10800,env=environment)
    if cp.returncode:
        raise RuntimeError((cp.returncode,cp.stderr[-8000:]))
    result=json.loads(cp.stdout)

assert result["status"]=="pass" and result["variant"]==chosen
assert result["saves"]>=100
assert result["beginSaveNS"]["p99"]<=100_000
assert result["advanceDuringSaveNS"]["p99"]<=1_100_000
assert result["overheadRatio"]<=1.10
assert result["allocationsIdleMaxPerAdvance"]==0
assert result["allocationsWhileSavingMaxPerAdvance"]<=result["barrierChunksMaxPerAdvance"]

payload={"status":"pass","sourceDecisionA":a["decisionA"],"C":result}
output.write_text(json.dumps(payload,indent=2)+"\n")
print(json.dumps({"status":"pass","variant":result["variant"],"saves":result["saves"],
 "beginP99":result["beginSaveNS"]["p99"],"advanceP99":result["advanceDuringSaveNS"]["p99"],
 "overheadRatio":result["overheadRatio"],"snapshotBytes":result["snapshotBytes"],
 "restoreNS":result["restoreNS"],"peakQueuedBytes":result["peakQueuedBytes"]},indent=2))
