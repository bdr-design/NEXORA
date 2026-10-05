import copy
import sys
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
