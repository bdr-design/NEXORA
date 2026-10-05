"""Pin accepted A/B evidence to unchanged inputs; never claim new A/B measurements."""
import hashlib
import json
import re
import statistics
import subprocess
import sys
from pathlib import Path
from proof_gates import stage_a_failures

BASE = "fa9c44656d6a7544f5cd0255781c64fde3e9ce1f"
root = Path(__file__).resolve().parents[2]
evidence = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
assert (evidence / "commit.txt").read_text().strip() == BASE
paths = ["Package.swift", "AGENTS.md", "Experiments/R005Swift/Package.swift",
         "Experiments/R005Swift/AllocationObserver.c"]
paths += [str(p.relative_to(root)) for directory in ("Sources", "Tests", "Checks")
          for p in (root / directory).rglob("*") if p.is_file()]
paths += ["Experiments/R005Swift/Sources/SwiftProbe/" + name for name in
          ("Core.swift", "Hybrid.swift", "Checks.swift", "DeadlineChecks.swift",
           "Stage005BModel.swift", "Stage005BRunner.swift", "Stage005BStore.swift")]
paths += [str(p.relative_to(root)) for p in (root / "Experiments/R005Swift/Sources/ProbePlatform").rglob("*") if p.is_file()]
for path in paths:
    old = subprocess.check_output(["git", "show", BASE + ":" + path], cwd=root)
    assert old == (root / path).read_bytes(), f"A/B input changed: {path}"
main = "Experiments/R005Swift/Sources/SwiftProbe/Main.swift"
old = subprocess.check_output(["git", "show", BASE + ":" + main], cwd=root).decode()
strip_c = lambda s: re.sub(r"#if STAGE_C\n.*?#endif", "", s, flags=re.S)
assert strip_c(old) == strip_c((root / main).read_text()), "normal A/B dispatch changed"
a = json.loads((evidence / "STAGE005-A.json").read_text())
b = json.loads((evidence / "STAGE005-B.json").read_text())
assert a["status"] == b["status"] == "pass"
failures = stage_a_failures(a["A"], a["health"])
assert not failures, failures
for row in a["A"]:
    samples = [s for process in row["rawProcesses"] for s in process["samples"]]
    assert len(samples) == 30
    assert row["nsPerEvent"]["median"] == statistics.median(s["nsPerEvent"] for s in samples)
    assert row["allocationsMaxPerCall"] == max(s["maxAllocationsPerAdvance"] for s in samples)
s = next(r for r in a["A"] if r["variant"] == "S" and r["assets"] == 1000000)
h = next(r for r in a["A"] if r["variant"] == "H" and r["assets"] == 1000000)
ratio = h["nsPerEvent"]["median"] / s["nsPerEvent"]["median"]
chosen = "H" if ratio <= .75 and h["bytesPerAsset"]["owned"] <= 128 else "S"
assert a["decisionA"]["chosen"] == chosen and a["decisionA"]["ratioHtoS1M"] == ratio
assert len(b["B"]) == 60 and all(all(r["invariants"].values()) for r in b["B"])
assert all(v["status"] == "pass" and v["totalsExact"] for v in b["finalDiskVerification"].values())
for mode in ("debug", "release", "tsan"):
    assert json.loads((evidence / ("STAGE005-B-KILLS-"+mode+".json")).read_text())["status"] == "pass"
out.write_text(json.dumps({"status":"pass","scope":"revalidated prior A/B evidence, not new measurements",
    "source":BASE,"run":36875130222,"artifact":11170911262,"chosen":chosen,
    "unchangedInputFiles":len(paths)+1,"A":a["decisionA"],"BRecords":60},indent=2)+"\n")
print("PASS reused A/B inputs and evidence; chosen", chosen)
