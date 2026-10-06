import copy
import sys
import contextlib
import io
import json
import os
import runpy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from proof_gates import stage_a_failures, stage_c_failures


class ProofGateTests(unittest.TestCase):
    def a(self):
        rows = [{"variant": v, "assets": n, "allocationsMaxPerCall": 0,
                 "rawProcesses": [{"cAllocationPositiveControl": 1, "swiftAllocationPositiveControl": 1}]*3}
                for v in ("S", "H") for n in (100000, 1000000, 2000000)]
        health = {v: {k: {"status": "pass"} for k in ("order100k", "order1M")} for v in ("S", "H")}
        return rows, health

    def c(self):
        return {"saves": 100, "beginSaveNS": {"p99": 100000, "samples": 100},
                "advanceDuringSaveNS": {"p99": 1100000, "samples": 1000},
                "overheadRatio": 1.10, "allocationsIdleMaxPerAdvance": 0,
                "allocationPairing": {"samples": 1000, "violations": 0, "maxExcess": 0}}

    def test_a_clean_evidence(self):
        self.assertEqual(stage_a_failures(*self.a()), [])

    def test_a_allocations_cannot_fall_back_to_success(self):
        for i in range(6):
            rows, health = self.a(); rows[i]["allocationsMaxPerCall"] = 1
            self.assertTrue(stage_a_failures(rows, health))

    def test_a_missing_positive_control(self):
        rows, health = self.a(); rows[0]["rawProcesses"][0] = {"cAllocationPositiveControl": 0, "swiftAllocationPositiveControl": 1}
        self.assertTrue(stage_a_failures(rows, health))

    def test_c_limits_are_inclusive(self):
        self.assertEqual(stage_c_failures(self.c()), [])

    def test_c_counts_cover_every_save_and_advance(self):
        c = self.c()
        c["saves"] = 101
        c["beginSaveNS"]["samples"] = 101
        c["advanceDuringSaveNS"]["samples"] = 101
        c["allocationPairing"]["samples"] = 101
        self.assertEqual(stage_c_failures(c), [])

        for count in (1, 99, 101):
            c = self.c(); c["beginSaveNS"]["samples"] = count
            self.assertTrue(any("beginSaveNS samples" in failure for failure in stage_c_failures(c)))
        for count in (1, 99):
            c = self.c(); c["advanceDuringSaveNS"]["samples"] = count
            c["allocationPairing"]["samples"] = count
            self.assertTrue(any("advanceDuringSaveNS samples" in failure for failure in stage_c_failures(c)))

    def test_c_rejects_malformed_sample_counts(self):
        for field in ("saves", "beginSaveNS", "advanceDuringSaveNS", "allocationPairing"):
            for count in (0, -1, 100.0, True, "100", None):
                c = self.c()
                if field == "saves": c[field] = count
                else: c[field]["samples"] = count
                self.assertTrue(stage_c_failures(c), (field, count))

    def test_c_independent_maxima_cannot_hide_violation(self):
        c = self.c(); c.update(allocationsWhileSavingMaxPerAdvance=457, barrierChunksMaxPerAdvance=457)
        c["allocationPairing"].update(violations=1, maxExcess=1)
        self.assertTrue(stage_c_failures(c))

    def test_c_old_unpaired_evidence_is_rejected(self):
        c = self.c(); del c["allocationPairing"]
        self.assertTrue(stage_c_failures(c))

    def test_c_pair_count_must_cover_all_advances(self):
        c = self.c(); c["allocationPairing"]["samples"] -= 1
        self.assertTrue(stage_c_failures(c))

    def test_c_rejects_overhead_idle_allocation_and_short_workload(self):
        for key, value in (("saves", 5), ("overheadRatio", 1.100001), ("allocationsIdleMaxPerAdvance", 1)):
            c = self.c(); c[key] = value
            self.assertTrue(stage_c_failures(c))

    def test_c_rejects_nonfinite_ratio(self):
        for value in (float("nan"), float("inf")):
            c = self.c(); c["overheadRatio"] = value
            self.assertTrue(stage_c_failures(c))

    def test_c_rejects_latency_and_empty_samples(self):
        for key in ("beginSaveNS", "advanceDuringSaveNS"):
            c = self.c(); c[key]["p99"] += 1
            self.assertTrue(stage_c_failures(c))
            c = self.c(); c[key]["samples"] = 0
            self.assertTrue(stage_c_failures(c))

    def test_a_launcher_persists_failure_and_exits(self):
        class Reply:
            returncode = 0
            stderr = ""
            def __init__(self, value): self.stdout = json.dumps(value)
        def fake(argv, **kwargs):
            command = argv[1]
            if command == "stage-a-bench":
                sample = {"nsPerEvent": 1.0, "ownedBytesPerAsset": 100.0,
                          "physDeltaPerAsset": None, "maxAllocationsPerAdvance": 1,
                          "advanceCallNS": {"p50": 1, "p99": 1, "max": 1}}
                return Reply({"status": "pass", "measuredRuns": 10, "warmups": 2,
                              "cAllocationPositiveControl": 1, "swiftAllocationPositiveControl": 1,
                              "samples": [sample]*10})
            if command == "selftest": return Reply({"mutations": [{"detected": True}]*8})
            if command == "hybrid-mutants": return Reply([{"detected": True}]*8)
            return Reply({"status": "pass", "partitionCases": 15})
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/"A.json"; observer = Path(directory)/"observer"; observer.touch()
            with patch.dict(os.environ, {"NXR_ALLOCATOR_DYLIB": str(observer)}), \
                 patch.object(sys, "argv", ["stage005_a.py", "/fake", str(output)]), \
                 patch("subprocess.run", fake), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(AssertionError):
                    runpy.run_path(str(Path(__file__).resolve().parents[1]/"stage005_a.py"), run_name="__main__")
            result = json.loads(output.read_text())
            self.assertEqual(result["status"], "failure")
            self.assertIsNone(result["decisionA"]["chosen"])
            self.assertEqual(len(result["A"]), 6)

    def test_c_launcher_persists_pair_failure_and_exits(self):
        value = self.c()
        value.update(status="measured", variant="S", overheadRatioMargin=0,
                     snapshotBytes=1, restoreNS=1, peakQueuedBytes=1)
        for key in ("beginSaveNS", "advanceDuringSaveNS"): value[key]["marginNS"] = 0
        value["allocationPairing"].update(violations=1, maxExcess=1)
        class Reply:
            returncode = 0; stderr = ""; stdout = json.dumps(value)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/"C.json"; observer = Path(directory)/"observer"; observer.touch()
            a = Path(directory)/"A.json"; a.write_text(json.dumps({"status": "pass", "decisionA": {"chosen": "S"}}))
            with patch.dict(os.environ, {"NXR_ALLOCATOR_DYLIB": str(observer)}), \
                 patch.object(sys, "argv", ["stage005_c.py", "/fake", str(output), str(a)]), \
                 patch("subprocess.run", lambda *args, **kwargs: Reply()), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(AssertionError):
                    runpy.run_path(str(Path(__file__).resolve().parents[1]/"stage005_c.py"), run_name="__main__")
            self.assertEqual(json.loads(output.read_text())["status"], "failure")

    def test_paired_profile_is_diagnostic_and_cannot_route_to_full_c(self):
        root = Path(__file__).resolve().parents[3]
        runner = (root / "Experiments/R005Swift/Sources/SwiftProbe/Stage005CRunner.swift").read_text()
        diagnostic = runner[runner.index("private struct StageCPairedScriptCall"):runner.index("func stageCCrashBootstrap")]
        paired = runner[runner.index("private func stageCPairedProfileRun"):runner.index("func stageCCrashBootstrap")]
        self.assertIn('"status": "diagnostic"', paired)
        self.assertIn('"acceptance": false', paired)
        self.assertIn('"deadline": "none"', paired)
        self.assertIn('"postBoundaryNoSave": "installed idle StageCState"', paired)
        self.assertIn('"outputHashExact"', paired)
        self.assertIn('"finalDigestExact"', paired)
        self.assertIn('"stateInstallAligned"', paired)
        self.assertIn('"dispatchToRunNS"', diagnostic)
        self.assertNotIn("stage005_c.py", paired)

        targeted = (root / ".github/workflows/r005-stage-c-targeted.yml").read_text()
        self.assertIn("r005-marker-conflict", targeted)
        self.assertIn("Reject conflicting bounded-run markers", targeted)
        job = targeted[targeted.index("  stage-c-paired-profile:"):targeted.index("  stage-c:\n")]
        self.assertIn("[r005-paired-profile]", job)
        self.assertIn("PAIRED-PROFILE-S.json", job)
        self.assertNotIn("stage005_c.py", job)
        self.assertIn("!contains(github.event.head_commit.message, '[r005-micro]')", job)
        self.assertIn("!contains(github.event.head_commit.message, '[r005-c-targeted]')", job)
        self.assertIn("!contains(github.event.head_commit.message, '[r005-b-full]')", job)
        self.assertIn("!contains(github.event.head_commit.message, '[r005-c-functional]')", job)
        self.assertIn("outputHashExact", job)
        self.assertIn("finalDigestExact", job)
        self.assertIn("allocationObserverAvailable", job)
        self.assertIn("PAIRED-PROFILE-S.stderr.txt", job)

        full_c = targeted[targeted.index("  stage-c:\n"):]
        self.assertIn("!contains(github.event.head_commit.message, '[r005-paired-profile]')", full_c)

        legacy = (root / ".github/workflows/r005-swift-executable.yml").read_text()
        self.assertIn("!contains(github.event.head_commit.message, '[r005-paired-profile]')", legacy)


if __name__ == "__main__":
    unittest.main()
