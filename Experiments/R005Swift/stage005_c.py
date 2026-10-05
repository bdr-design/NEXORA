#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile
from pathlib import Path

binary=Path(sys.argv[1]).resolve()
output=Path(sys.argv[2]).resolve()
stage_a=Path(sys.argv[3]).resolve()
from proof_gates import THRESHOLDS, stage_c_failures
DIAGNOSTIC_ONLY=[
    "snapshotBytes","writeNS","restoreNS","peakQueuedBytes",
    "barrierCopy.bytesPerSave","barrierCopy.nsPerSave",
]

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

assert result["status"]=="measured" and result["variant"]==chosen
failures=stage_c_failures(result)

payload={
    "status":"failure" if failures else "pass",
    "sourceDecisionA":a["decisionA"],
    "thresholds":THRESHOLDS,
    "diagnosticOnly":DIAGNOSTIC_ONLY,
    "gateFailures":failures,
    "C":result,
}
output.write_text(json.dumps(payload,indent=2)+"\n")
summary={
    "status":payload["status"],"variant":result["variant"],"saves":result["saves"],
    "beginP99":result["beginSaveNS"]["p99"],
    "beginSamples":result["beginSaveNS"]["samples"],
    "beginMarginNS":result["beginSaveNS"]["marginNS"],
    "advanceP99":result["advanceDuringSaveNS"]["p99"],
    "advanceSamples":result["advanceDuringSaveNS"]["samples"],
    "advanceMarginNS":result["advanceDuringSaveNS"]["marginNS"],
    "overheadRatio":result["overheadRatio"],
    "overheadMargin":result["overheadRatioMargin"],
    "snapshotBytes":result["snapshotBytes"],
    "restoreNS":result["restoreNS"],
    "peakQueuedBytes":result["peakQueuedBytes"],
    "failures":failures,
}
print(json.dumps(summary,indent=2))
if failures:
    raise AssertionError("; ".join(failures))
