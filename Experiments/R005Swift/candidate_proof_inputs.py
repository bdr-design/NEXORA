"""Source binding and functional summary. This does not launch C measurement."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def manifest():
    exp = ROOT / "Experiments/R005Swift"
    paths = [ROOT / "AGENTS.md", exp / "Package.swift", exp / "AllocationObserver.c"]
    paths += sorted(p for p in (exp / "Sources").rglob("*") if p.is_file())
    paths += sorted(exp.glob("*.py"))
    return {"schemaVersion": 1, "sourceFlags": {"A": ["EPOCH_PAGES"], "B": ["STAGE_C", "EPOCH_PAGES"],
            "K": ["STAGE_C", "EPOCH_PAGES"]},
            "paths": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}


def quotas(source, snapshot_source):
    b = json.loads(source.read_text())
    assert b["status"] == "pass" and len(b["B"]) == 60
    for case, window in (("G16", 7), ("G1", 7)):
        assert sorted(r["day"] for r in b["B"] if (r["case"], r["window"]) == (case, window)) == list(range(1, 31))
    assert all(all(r["invariants"].values()) for r in b["B"])
    assert all(v["status"] == "pass" and v["totalsExact"] for v in b["finalDiskVerification"].values())
    measured = json.loads(snapshot_source.read_text())
    a = json.loads((source.parent / "STAGE005-A.json").read_text())
    layout = a["decisionA"]["chosen"]
    assert a["status"] == "pass" and layout in ("S", "H")
    assert measured["status"] == "pass" and measured["epoch"] == 1
    snapshot = measured["snapshotBytes"]
    assert snapshot == (95801772 if layout == "S" else 100801772)
    result = {}
    mib = 1024 * 1024
    for name, window in (("G16_W7", 7), ("G1_W7", 7), ("G1_W3", 3)):
        c = b["cases"][name]
        raw = (5 * ((window + 1) * c["BdayMax"] + c["S30"] + c["Omax"]) + 3) // 4 + 2 * snapshot
        result[name] = ((raw + 64 * mib - 1) // (64 * mib)) * 64
    assert result["G16_W7"] <= 1024 and result["G1_W7"] > 1024 and result["G1_W3"] <= 1024
    return {"status": "pass", "quotaMiB": result, "snapshotBytesInput": snapshot, "selectedLayout": layout,
            "snapshotScope": "fresh 1M fixture on this source; not a C performance result",
            "G16_W7Accepted": result["G16_W7"] <= 1024,
            "G1_W7Rejected": result["G1_W7"] > 1024,
            "G1_W3Accepted": result["G1_W3"] <= 1024}


def functional_summary(directory):
    a = json.loads((directory / "STAGE005-A.json").read_text())
    b = json.loads((directory / "STAGE005-B.json").read_text())
    assert a["status"] == b["status"] == "pass"
    assert a["decisionA"]["chosen"] in ("S", "H")
    files = []
    for mode in ("debug", "release", "tsan"):
        name = f"B-RECOVERY-{mode}.json"
        row = json.loads((directory / name).read_text())
        assert row["status"] == "pass" and len(row["recoverAppendRecoverCases"]) == 8
        assert row["directAppendBeforeRecoveryRejectedAndHealed"]
        files.append(name)
        for variant in ("S", "H"):
            name = f"KILLS-1M-{mode}-{variant}.json"
            row = json.loads((directory / name).read_text())
            assert row["status"] == "pass" and row["population"] == 1000000
            assert row["variant"] == variant and row["points"] == len(row["results"]) == 10
            assert all(r["signal"] == "SIGKILL" and r["exactDigest"] for r in row["results"])
            k9 = next(r for r in row["results"] if r["point"] == "c.k9.mid_wal_record")
            assert k9["continuedSameEpoch"]["secondRecoveryExact"]
            assert row["chainFallback"]["exactDigest"]
            files.append(name)
            name = f"WAL-CONTINUATION-{mode}-{variant}.json"
            row = json.loads((directory / name).read_text())
            assert row["status"] == "pass" and row["variant"] == variant and row["population"] == 4096
            assert sorted(r["discardedBytes"] for r in row["continuationCases"]) == [2, 8, 54]
            assert all(r["secondRecoveryExact"] and r["finalSequence"] == 2 for r in row["continuationCases"])
            assert row["completeFrameCorruptionRejected"] and row["completeLengthCorruptionRejected"]
            files.append(name)
    proof = {"status": "pass", "C100": "NOT_RUN", "sourceDecisionA": a["decisionA"],
             "layoutsWithFreshFunctionalProof": ["S", "H"],
             "K10Scope": "historical point token; fully retained immutable epoch and preallocated spare buffers, queue bytes=0",
             "evidenceSHA256": {name: hashlib.sha256((directory / name).read_bytes()).hexdigest() for name in files},
             "scope": "new source A/B/Debug Release TSan K1-K10; not C performance closure or iPhone proof"}
    (directory / "SOURCE-FUNCTIONAL-PROOF.json").write_text(json.dumps(proof, indent=2) + "\n")
    return proof


if __name__ == "__main__":
    command, path = sys.argv[1], Path(sys.argv[2])
    if command == "write": path.write_text(json.dumps(manifest(), indent=2) + "\n")
    elif command == "check": assert json.loads(path.read_text()) == manifest(), "runtime inputs/flags changed"
    elif command == "quota": Path(sys.argv[4]).write_text(json.dumps(quotas(path, Path(sys.argv[3])), indent=2) + "\n")
    elif command == "functional-summary": print(json.dumps(functional_summary(path)))
    else: raise AssertionError(command)
