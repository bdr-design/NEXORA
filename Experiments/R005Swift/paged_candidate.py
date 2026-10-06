"""Bounded full-state comparison; never runs A, B or the C evaluator."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def validate(row, *, variant, count, policy, candidate):
    assert row["status"] == "diagnostic" and row["acceptance"] is False
    assert row["schemaVersion"] == 1 and row["variant"] == variant and row["assets"] == count
    assert row["allocationPolicy"] == policy
    assert row["independentReferenceEvents"] == count
    assert len(row["fixtureSHA256"]) == 64 and len(row["fixtureDigest"]) == 64
    assert row["snapshotBytes"] > 0 and row["liveOwnedBytes"] > 0
    assert [r["epoch"] for r in row["epochs"]] == [2, 3, 4]
    observed = policy != "functional"
    assert row["allocationAvailable"] is observed
    for field in ("cAllocationPositiveControl", "swiftAllocationPositiveControl"):
        if observed:
            assert type(row[field]) is int and row[field] > 0
        else:
            assert row[field] is None
    for r in row["epochs"]:
        assert r["events"] == count and r["calls"] > 0
        assert len(r["frozenDigest"]) == len(r["liveDigest"]) == 64
        assert r["recoveredDigest"] == r["liveDigest"]
        assert r["snapshotBytes"] == row["snapshotBytes"]
        assert r["snapshotSource"] == ("immutable_epoch_pages" if candidate else "record_queue")
        assert r["allocationAvailable"] is observed
        assert r["beginNS"] >= 0 and r["advanceNS"] > 0 and r["writerNS"] > 0
        assert r["fullLoopNS"] >= r["advanceNS"] and r["serviceCalls"] > 0
        if candidate:
            assert r["peakQueuedBytes"] == 0
            assert r["retainedEpochBufferBytes"] >= row["liveOwnedBytes"]
        for field in ("advanceAllocationsMax", "advanceAllocationBytes", "serviceAllocationsMax", "idleServiceAllocations"):
            if not observed:
                assert r[field] is None
            else:
                assert type(r[field]) is int and r[field] >= 0
                if policy == "zero":
                    assert r[field] == 0


def comparable(row):
    return {"variant": row["variant"], "assets": row["assets"],
            "fixtureSHA256": row["fixtureSHA256"], "fixtureDigest": row["fixtureDigest"],
            "snapshotBytes": row["snapshotBytes"],
            "epochs": [{k: r[k] for k in ("epoch", "events", "calls", "scriptHash", "frozenDigest",
                                         "liveDigest", "recoveredDigest", "sequenceHash", "snapshotBytes")}
                       for r in row["epochs"]]}


def run_matrix(bins, directory, observer):
    directory.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["TSAN_OPTIONS"] = "halt_on_error=1"
    report = {"status": "running", "acceptance": False, "scope": "bounded full-state integration only",
              "raw": [], "exactComparisons": [], "failure": None}
    output = directory / "PAGED-CANDIDATE.json"

    def save():
        output.write_text(json.dumps(report, indent=2) + "\n")

    def size(count, modes):
        for variant in ("S", "H"):
            reference = None
            for mode in modes:
                candidate = mode != "baseline-release"
                policy = "functional" if mode == "candidate-tsan" else "zero" if mode == "candidate-release" else "observe"
                label = f"{mode}-{variant}-{count}"
                call_env = env.copy()
                if policy != "functional":
                    call_env["DYLD_INSERT_LIBRARIES"] = str(observer)
                else:
                    call_env.pop("DYLD_INSERT_LIBRARIES", None)
                store = directory / ("store-" + label)
                command = [str(bins[mode]), "paged-candidate-checks", str(store), variant, str(count), policy]
                result = subprocess.run(command, text=True, capture_output=True, env=call_env, timeout=900)
                raw = directory / (label + ".json")
                raw.write_text(result.stdout)
                (directory / (label + ".stderr.txt")).write_text(result.stderr)
                report["raw"].append({"mode": mode, "variant": variant, "assets": count, "exit": result.returncode,
                                      "file": raw.name, "sha256": hashlib.sha256(raw.read_bytes()).hexdigest()})
                save()
                assert result.returncode == 0, (label, result.stderr)
                assert not result.stderr, (label, result.stderr)
                row = json.loads(result.stdout)
                validate(row, variant=variant, count=count, policy=policy, candidate=candidate)
                if reference is None:
                    reference = comparable(row)
                else:
                    assert comparable(row) == reference, label
                    report["exactComparisons"].append({"baseline": "baseline-release", "candidate": mode,
                                                        "variant": variant, "assets": count, "exact": True})
                # After proof retention, temporary stores can be discarded.
                import shutil
                shutil.rmtree(store)
    try:
        save()
        for count in (1, 3, 257, 513, 4096):
            size(count, tuple(bins))
        size(100000, ("baseline-release", "candidate-release"))
        report["status"] = "pass"
    except Exception as error:
        report["status"] = "failure"; report["failure"] = repr(error)
        save()
        raise
    save()
    return report


if __name__ == "__main__":
    names = ("baseline-release", "candidate-debug", "candidate-release", "candidate-tsan")
    assert len(sys.argv) == 7, "baseline-release candidate-debug candidate-release candidate-tsan output-directory observer"
    bins = {name: Path(path).resolve() for name, path in zip(names, sys.argv[1:5])}
    print(json.dumps(run_matrix(bins, Path(sys.argv[5]).resolve(), Path(sys.argv[6]).resolve())))
