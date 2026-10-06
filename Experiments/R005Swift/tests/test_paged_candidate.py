import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paged_candidate import comparable, validate


class CandidateEvidenceTests(unittest.TestCase):
    def row(self, policy="zero"):
        observed = policy != "functional"
        return {"status": "diagnostic", "acceptance": False, "schemaVersion": 1, "variant": "H", "assets": 257,
                "allocationPolicy": policy, "allocationAvailable": observed,
                "cAllocationPositiveControl": 1 if observed else None,
                "swiftAllocationPositiveControl": 1 if observed else None,
                "independentReferenceEvents": 257, "fixtureSHA256": "a"*64, "fixtureDigest": "b"*64,
                "snapshotBytes": 50000, "liveOwnedBytes": 40000,
                "epochs": [{"epoch": epoch, "events": 257, "calls": 2, "scriptHash": "123",
                            "frozenDigest": "b"*64, "liveDigest": "c"*64, "recoveredDigest": "c"*64,
                            "sequenceHash": "456", "snapshotBytes": 50000, "snapshotSource": "immutable_epoch_pages",
                            "peakQueuedBytes": 0, "retainedEpochBufferBytes": 80000,
                            "beginNS": 100, "advanceNS": 200, "writerNS": 500, "fullLoopNS": 600,
                            "serviceCalls": 1, "allocationAvailable": observed,
                            "advanceAllocationsMax": 0 if observed else None, "advanceAllocationBytes": 0 if observed else None,
                            "serviceAllocationsMax": 0 if observed else None, "idleServiceAllocations": 0 if observed else None}
                           for epoch in (2, 3, 4)]}

    def check(self, row, policy="zero"):
        validate(row, variant="H", count=257, policy=policy, candidate=True)

    def test_zero_requires_observer_and_positive_controls(self):
        self.check(self.row())
        for field, value in (("allocationAvailable", False), ("cAllocationPositiveControl", 0),
                             ("swiftAllocationPositiveControl", None)):
            row = self.row(); row[field] = value
            with self.assertRaises(AssertionError): self.check(row)
        for field in ("advanceAllocationsMax", "advanceAllocationBytes", "serviceAllocationsMax"):
            row = self.row(); row["epochs"][1][field] = 1
            with self.assertRaises(AssertionError): self.check(row)

    def test_sanitizer_unavailable_counts_are_null(self):
        row = self.row("functional"); self.check(row, "functional")
        row["epochs"][0]["advanceAllocationsMax"] = 0
        with self.assertRaises(AssertionError): self.check(row, "functional")

    def test_transport_identity_and_ownership_claims_are_required(self):
        for field, value in (("recoveredDigest", "d"*64), ("peakQueuedBytes", 1),
                             ("retainedEpochBufferBytes", 0), ("snapshotSource", "record_queue")):
            row = self.row(); row["epochs"][0][field] = value
            with self.assertRaises(AssertionError): self.check(row)
        row = self.row(); other = copy.deepcopy(row)
        other["epochs"][0]["beginNS"] += 1
        self.assertEqual(comparable(row), comparable(other))
        other["epochs"][0]["scriptHash"] = "789"
        self.assertNotEqual(comparable(row), comparable(other))

    def test_isolated_routing_cannot_run_c_evaluator(self):
        root = Path(__file__).resolve().parents[3]
        workflow = (root / ".github/workflows/r005-paged-candidate.yml").read_text()
        self.assertIn("[r005-evidence-only]", workflow)
        self.assertIn("--sanitize=thread", workflow)
        self.assertNotIn("stage005_c.py", workflow)
        launcher = (root / "Experiments/R005Swift/paged_candidate.py").read_text()
        self.assertNotIn("stage005_c.py", launcher)
        source = (root / "Experiments/R005Swift/Sources/SwiftProbe/EpochPages.swift").read_text()
        self.assertNotIn("@unchecked", source)
        self.assertNotIn("withUnsafe", source)


if __name__ == "__main__": unittest.main()
