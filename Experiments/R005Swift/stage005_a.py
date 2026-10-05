#!/usr/bin/env python3
import json, os, statistics, subprocess, sys
from pathlib import Path
from proof_gates import stage_a_failures

binary = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()

def call(*args, timeout=900):
    environment=os.environ.copy()
    if args and args[0]=="stage-a-bench":
        observer=Path(environment["NXR_ALLOCATOR_DYLIB"]).resolve()
        assert observer.is_file(), observer
        environment["DYLD_INSERT_LIBRARIES"]=str(observer)
    cp = subprocess.run([str(binary), *map(str,args)], capture_output=True, text=True,
                        env=environment, timeout=timeout)
    if cp.returncode:
        raise RuntimeError(f"command failed {args}: {cp.stderr[-4000:]}")
    return json.loads(cp.stdout)

health = {
    "S": {
        "selftest": call("selftest"),
        "order100k": call("order", 100000),
        "order1M": call("order", 1000000),
    },
    "H": {
        "layout": call("hybrid-selftest"),
        "mutants": call("hybrid-mutants"),
        "order100k": call("hybrid-order", 100000),
        "order1M": call("hybrid-order", 1000000),
    }
}
assert len(health["S"]["selftest"]["mutations"]) == 8
assert all(x["detected"] for x in health["S"]["selftest"]["mutations"])
assert len(health["H"]["mutants"]) == 8
assert all(x["detected"] for x in health["H"]["mutants"])
for layout in ("S","H"):
    for key in ("order100k","order1M"):
        assert health[layout][key]["status"] == "pass"

rows=[]
for variant in ("S","H"):
    for assets in (100000,1000000,2000000):
        processes=[]
        for process in range(1,4):
            r=call("stage-a-bench",variant,assets,10,timeout=1800)
            assert r["status"]=="pass" and r["measuredRuns"]==10 and r["warmups"]==2
            r["process"]=process
            processes.append(r)
        samples=[s for p in processes for s in p["samples"]]
        assert len(samples)==30
        ns=[float(s["nsPerEvent"]) for s in samples]
        owned=[float(s["ownedBytesPerAsset"]) for s in samples]
        footprint=[float(s["physDeltaPerAsset"]) for s in samples if s["physDeltaPerAsset"] is not None]
        max_alloc=max(int(s["maxAllocationsPerAdvance"]) for s in samples)
        rows.append({
            "variant":variant,"assets":assets,"processes":3,"warmupsPerProcess":2,"measuredRuns":30,
            "bytesPerAsset":{"owned":statistics.median(owned),
                             "footprint":statistics.median(footprint) if footprint else None},
            "nsPerEvent":{"median":statistics.median(ns),"min":min(ns),"max":max(ns),"runs":30},
            "advanceCallNS":{"p50":statistics.median([int(s["advanceCallNS"]["p50"]) for s in samples]),
                             "p99":max(int(s["advanceCallNS"]["p99"]) for s in samples),
                             "max":max(int(s["advanceCallNS"]["max"]) for s in samples)},
            "allocationsMaxPerCall":max_alloc,
            "correctness":{"oracle100k":health[variant]["order100k"]["status"]=="pass",
                           "reference1M":health[variant]["order1M"]["status"]=="pass",
                           "partitionCases":health[variant]["order1M"].get("partitionCases",15) if variant=="H" else 15,
                           "mutantsKilled":8},
            "rawProcesses":processes
        })

def row(variant,assets):
    return next(x for x in rows if x["variant"]==variant and x["assets"]==assets)
s1=row("S",1000000); h1=row("H",1000000)
ratio=h1["nsPerEvent"]["median"]/s1["nsPerEvent"]["median"]
failures=stage_a_failures(rows, health)
health_ok=not failures
chosen=("H" if ratio <= 0.75 and h1["bytesPerAsset"]["owned"] <= 128.0 else "S") if health_ok else None
result={
    "status":"failure" if failures else "pass",
    "gateFailures":failures,
    "scope":"R005 proof-only Stage A; Apple CI VM, not iPhone acceptance",
    "A":rows,
    "decisionA":{"chosen":chosen,"ratioHtoS1M":ratio,
                 "rule":"H only if H median ns/event <= 0.75*S at 1M, H owned <=128 B/asset, and all health gates pass"},
    "health":health
}
out.write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps({"status":result["status"],"chosen":chosen,"ratioHtoS1M":ratio,
                  "S1M_ns":s1["nsPerEvent"]["median"],"H1M_ns":h1["nsPerEvent"]["median"],
                  "H1M_owned":h1["bytesPerAsset"]["owned"]},indent=2))

if failures:
    raise AssertionError("; ".join(failures))
