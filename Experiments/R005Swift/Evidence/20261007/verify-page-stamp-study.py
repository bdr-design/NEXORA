"""Independently verify a disposable page-metadata study; never qualifies C."""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import argparse
import hashlib
import json
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "Experiments/R005Swift"))
from candidate_proof_inputs import manifest
from paged_candidate import comparable, validate


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(archive, sha256, source, tree, run, artifact, output):
    assert digest(archive) == sha256
    with tempfile.TemporaryDirectory(prefix="nxr-stamp-verify-") as temporary:
        scratch = Path(temporary)
        extracted = scratch / "raw"
        with ZipFile(archive) as zipped:
            names = zipped.namelist()
            assert len(names) == len(set(names))
            assert sum(item.file_size for item in zipped.infolist()) < 64 * 1024 * 1024
            for item in zipped.infolist():
                name = PurePosixPath(item.filename)
                assert not name.is_absolute() and ".." not in name.parts
                assert (item.external_attr >> 16) & 0o170000 != 0o120000
            zipped.extractall(extracted)
        assert (extracted / "commit.txt").read_text().strip() == source
        assert (extracted / "tree.txt").read_text().strip() == tree
        inputs = json.loads((extracted / "runtime-inputs.json").read_text())
        assert inputs == manifest() and len(inputs["paths"]) == 42
        for phase in ("before", "after"):
            assert "PASS baseline" in (extracted / f"source-guard-{phase}.txt").read_text()

        actual = ROOT / "Experiments/R005Swift/Sources"
        temporary_source = json.loads((extracted / "study-source.json").read_text())
        assert set(temporary_source) == {"base", "stamp"}
        for arm in ("base", "stamp"):
            package = scratch / ".page-stamp-study" / arm
            shutil.copytree(actual, package / "Sources")
            subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("prepare-page-stamp-study.py")),
                            str(package)], check=True, capture_output=True, text=True)
            assert set(temporary_source[arm]) == {str(p.relative_to(actual)) for p in actual.rglob("*") if p.is_file()}
            changed = []
            for name, hashes in temporary_source[arm].items():
                assert hashes["actual"] == digest(actual / name)
                assert hashes["temporary"] == digest(package / "Sources" / name)
                path = "Experiments/R005Swift/Sources/" + name
                assert inputs["paths"][path] == hashes["actual"]
                if hashes["actual"] != hashes["temporary"]:
                    changed.append(name)
            expected = {"SwiftProbe/Stage005CPagedChecks.swift"}
            if arm == "stamp":
                expected.add("SwiftProbe/EpochPages.swift")
            assert set(changed) == expected
            for mode in ("debug", "release", "tsan"):
                assert "Build complete!" in (extracted / f"build-{arm}-{mode}.txt").read_text()

        study = json.loads((extracted / "PAGE-STAMP-STUDY.json").read_text())
        assert study["status"] == "diagnostic-verified" and study["acceptance"] is False
        assert study["C100"] == "NOT_RUN"
        expected_files = [f"{arm}-{mode}-{variant}-{count}.json"
                          for arm in ("base", "stamp") for mode in ("debug", "release", "tsan")
                          for variant in ("S", "H") for count in (257, 4096)]
        expected_files += [f"abba-{count}-{ordinal}-{arm}.json" for count in (100000, 1000000)
                           for ordinal, arm in enumerate(("base", "stamp", "stamp", "base"), 1)]
        assert [row["file"] for row in study["rows"]] == expected_files
        references, measured = {}, []
        for raw in study["rows"]:
            path = extracted / raw["file"]
            assert digest(path) == raw["sha256"]
            assert not path.with_name(path.stem + ".stderr.txt").read_text()
            row = json.loads(path.read_text())
            policy = "functional" if raw["mode"] == "tsan" else "zero" if raw["mode"] == "release" else "observe"
            validate(row, variant=raw["variant"], count=raw["assets"], policy=policy, candidate=True)
            observed = policy != "functional"
            assert row["worldSetupAllocationAvailable"] is observed
            for key in ("worldSetupAllocations", "worldSetupAllocationBytes"):
                assert (type(row[key]) is int and row[key] > 0) if observed else row[key] is None
            key = raw["variant"], raw["assets"]
            if key in references:
                assert comparable(row) == references[key]
            else:
                references[key] = comparable(row)
            count = raw["assets"]
            groups = ((count + 15) // 16) * 8
            physical = count * 80 + groups if raw["variant"] == "H" else ((count * 65 + 7) // 8) * 8 + ((count * 30 + 7) // 8) * 8 + groups
            assert all(epoch["barrierBytes"] == physical for epoch in row["epochs"])
            measured.append((raw, row))

        expected_lifecycle = [f"lifecycle-{arm}-{mode}-{variant}.json" for arm in ("base", "stamp")
                              for mode in ("debug", "release", "tsan") for variant in ("S", "H")]
        assert [row["file"] for row in study["lifecycles"]] == expected_lifecycle
        for raw in study["lifecycles"]:
            path = extracted / raw["file"]
            assert digest(path) == raw["sha256"] and not path.with_name(path.stem + ".stderr.txt").read_text()
            row = json.loads(path.read_text())
            assert row["status"] == "pass" and row["assets"] == 257
            assert all(value is True for key, value in row.items() if key not in ("status", "assets", "scope"))
            assert row["copyObserverOwnerExact"] is True
            if raw["file"].endswith("-H.json"):
                assert row["coldMutationDuringFrozenEpochExact"] is True

        summaries = {}
        for count in (100000, 1000000):
            arms = {}
            for arm in ("base", "stamp"):
                rows = [row for raw, row in measured if raw["assets"] == count and raw["arm"] == arm]
                assert len(rows) == 2
                arms[arm] = {field: statistics.median(epoch[field] for row in rows for epoch in row["epochs"])
                             for field in ("advanceNS", "barrierNS", "writerNS", "fullLoopNS")}
                arms[arm].update({field: statistics.median(row[field] for row in rows)
                                  for field in ("worldSetupNS", "worldSetupAllocations", "worldSetupAllocationBytes",
                                                "liveOwnedBytes", "preparedOwnedBytes")})
                arms[arm]["advanceSamplesNS"] = [epoch["advanceNS"] for row in rows for epoch in row["epochs"]]
            summaries[str(count)] = {"medians": arms,
                                     "stampToBase": {field: arms["stamp"][field] / arms["base"][field]
                                                     for field in ("advanceNS", "barrierNS", "writerNS", "fullLoopNS")},
                                     "additionalSetupRequestedAllocations": arms["stamp"]["worldSetupAllocations"] - arms["base"]["worldSetupAllocations"],
                                     "additionalSetupRequestedBytes": arms["stamp"]["worldSetupAllocationBytes"] - arms["base"]["worldSetupAllocationBytes"],
                                     "additionalDeclaredOwnedBytes": arms["stamp"]["preparedOwnedBytes"] - arms["base"]["preparedOwnedBytes"]}
        proof = dict(status="pass", acceptance=False, source=source, tree=tree, run=run, artifact=artifact,
                     zipSHA256=sha256, runtimeInputs=42, canonicalCases=32, epochs=96, lifecycleCases=12,
                     HSameHostABBA=summaries, C100="NOT_RUN", CPerformance={"S": "OPEN", "H": "OPEN"},
                     decision="NOT_ADOPTED: no credible 1M simulation gain; memory/setup cost increases",
                     allocationScope="requested setup counters; conservative owned box allowance is not physical footprint",
                     scope="same-fixture mixed bounded harness only; no runtime mutation, C qualification, or device proof",
                     evidenceSHA256={str(p.relative_to(extracted)): digest(p) for p in sorted(extracted.rglob("*")) if p.is_file()})
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(proof, indent=2) + "\n")
        shutil.copyfile(archive, output.with_name(f"{run}-r005-page-stamp-study.zip"))
        return proof


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    for option in ("sha256", "source", "tree"):
        parser.add_argument("--" + option, required=True)
    for option in ("run", "artifact"):
        parser.add_argument("--" + option, required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    result = verify(arguments.archive, arguments.sha256, arguments.source, arguments.tree,
                    arguments.run, arguments.artifact, arguments.output)
    print(json.dumps({key: result[key] for key in ("status", "canonicalCases", "epochs", "lifecycleCases", "HSameHostABBA", "decision")}, indent=2))
