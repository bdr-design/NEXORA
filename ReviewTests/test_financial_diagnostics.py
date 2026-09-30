#!/usr/bin/env python3
"""Offline evidence-contract regressions. Synthetic records are NOT performance measurements."""
import copy
import importlib.util
import json
import sys
from pathlib import Path
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("financial_diagnostics", ROOT / "Checks/financial-diagnostics.py")
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)
SOURCE = "b7d3deb8a8599ac382b69e431addf22acd0f4e7f"


def snapshot(begin, end):
    return {"beginOffsetNS": begin, "endOffsetNS": end,
            "threadStatus": "ok", "threadCPUNS": begin,
            "processStatus": "ok", "processUserNS": begin, "processSystemNS": 0,
            "processMinorFaults": 0, "processMajorFaults": 0,
            "processVoluntarySwitches": 0, "processInvoluntarySwitches": 0}


def window(offset, mode, aircraft=0, sample=0, phase="empty", batch=0, operations=0):
    row = {"aircraft": aircraft, "sample": sample, "phase": phase, "batch": batch,
           "operations": operations, "startOffsetNS": offset + 3, "wallNS": 4}
    if mode == "counters":
        row.update(before=snapshot(offset, offset + 2), after=snapshot(offset + 8, offset + 10))
    return row


def calibration(mode):
    return {"kind": "calibration", "mode": mode, "iterations": 2000, "loopNS": 40_000,
            "records": [window(i * 20, mode, batch=i) for i in range(2000)]}


def sample(count, mode, position, run_id):
    batches = (count + 255) // 256
    records, phases, start = [], [], 350
    for phase in diag.PHASES:
        if phase == "collect":
            start += 20
        records.extend(window(start + i * 20, mode, count, 1, phase, i,
                              min(256, count - i * 256)) for i in range(batches))
        phases.append({"phase": phase, "startOffsetNS": start, "totalNS": batches * 20,
                       "sumBatchWallNS": batches * 4, "outsideBatchWallNS": batches * 16})
        start += batches * 20
    revenue = sum(i % 97 + 101 for i in range(count))
    result = {"kind": "sample", "aircraft": count, "sample": 1, "warmup": False,
              "mode": mode, "runID": run_id, "executionOrder": position,
              "aggregate": {"initializationNS": 100, "registerAllNS": 200,
                            "departAllNS": batches * 20, "advanceAllNS": batches * 20,
                            "collectAllNS": batches * 20, "maximumAdvanceNS": 4,
                            "maximumCollectionPageNS": 4, "expensePostsNS": 50,
                            "advanceBatches": batches, "invoiceCount": count,
                            "journalCount": count * 2 + 4, "revenueMinor": revenue,
                            "cashMinor": revenue - 5000},
              "phases": [] if mode == "baseline" else phases,
              "records": [] if mode == "baseline" else records}
    if mode != "baseline":
        result.update(bufferPreparationNS=20, seedAndHandlePreparationNS=50, finalAuditNS=100,
                      explicitWorldReleaseNS=50, workloadNS=start + 200)
    return result


def raw_fixture(run_id=1):
    meta = {"kind": "metadata", "schema": "NXR-R004-BATCH-DIAGNOSTICS-1",
            "runID": run_id, "processID": 10000 + run_id,
            "warmups": 0, "repetitions": 1, "sizes": [1000, 5000, 20000, 50000, 100000],
            "modes": list(diag.MODES), "batchSize": 256, "sourceBase": diag.SOURCE_BASE,
            "sourceCommit": SOURCE, "os": "SYNTHETIC UNIT-TEST FIXTURE; NOT A MEASUREMENT",
            "counterDefinitions": dict(diag.COUNTER_DEFINITIONS), "mainThread": True,
            "sampleIndexing": diag.SAMPLE_INDEXING,
            "notCollected": ["synthetic fixture, no real counters"],
            "limitations": ["synthetic schema test, NOT performance evidence"]}
    rows = [meta, calibration("wall"), calibration("counters")]
    order = diag.MODES if run_id % 2 == 0 else tuple(reversed(diag.MODES))
    for count in meta["sizes"]:
        for position, mode in enumerate(order):
            rows.append(sample(count, mode, position, run_id))
    rows.append({"kind": "complete", "status": "all-fixture-checks-passed"})
    return rows


def first_sample(rows, mode="counters"):
    return next(r for r in rows if r["kind"] == "sample" and r["mode"] == mode)


class CompleteInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.control = raw_fixture()

    def analyze(self, *groups):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for i, rows in enumerate(groups):
                path = Path(directory) / ("synthetic-%d.ndjson" % i)
                with path.open("w") as writer:
                    for row in rows:
                        writer.write(json.dumps(row, separators=(",", ":")) + "\n")
                paths.append(path)
            return diag.analyze(paths)

    def rejection(self, change, text=None):
        rows = copy.deepcopy(self.control)
        change(rows)
        if text:
            with self.assertRaisesRegex(ValueError, text):
                self.analyze(rows)
        else:
            with self.assertRaises(ValueError):
                self.analyze(rows)

    def test_valid_complete_input(self):
        result = self.analyze(self.control)
        self.assertEqual(result["status"], "complete-raw-files-validated")
        self.assertEqual(sum(s["wallNS"]["count"] for s in result["batchDistributions"]), 4140)

    def test_valid_two_distinct_runs(self):
        result = self.analyze(self.control, raw_fixture(run_id=2))
        self.assertEqual(len(result["files"]), 2)

    def test_wrong_source_base(self):
        self.rejection(lambda x: x[0].update(sourceBase="0" * 40), "source base")

    def test_unrecorded_source(self):
        self.rejection(lambda x: x[0].update(sourceCommit="unrecorded-local-snapshot"), "source commit")

    def test_mixed_source_commits(self):
        other = raw_fixture(run_id=2)
        other[0]["sourceCommit"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "mixed source"):
            self.analyze(self.control, other)

    def test_mixed_os(self):
        other = raw_fixture(run_id=2)
        other[0]["os"] = "other synthetic OS"
        with self.assertRaisesRegex(ValueError, "mixed source/OS"):
            self.analyze(self.control, other)

    def test_mixed_counter_definitions(self):
        other = raw_fixture(run_id=2)
        other[0]["counterDefinitions"]["threadCPUNS"] = "wrong units"
        with self.assertRaisesRegex(ValueError, "counter definitions"):
            self.analyze(self.control, other)

    def test_renamed_duplicate_raw_file(self):
        with self.assertRaisesRegex(ValueError, "duplicate raw bytes"):
            self.analyze(self.control, copy.deepcopy(self.control))

    def test_duplicate_run_not_hidden_by_metadata_edit(self):
        other = copy.deepcopy(self.control)
        other[0]["processID"] += 10
        with self.assertRaisesRegex(ValueError, "duplicate run ID"):
            self.analyze(self.control, other)

    def test_failed_completion_status(self):
        self.rejection(lambda x: x[-1].update(status="failed"), "completion status")

    def test_missing_completion_status(self):
        self.rejection(lambda x: x[-1].pop("status"), "schema fields")

    def test_incomplete_stream(self):
        self.rejection(lambda x: x.pop(), "incomplete raw file")

    def test_failure_marker(self):
        self.rejection(lambda x: x.__setitem__(-1, {"kind": "failure", "error": "synthetic failure"}), "fixture failure")

    def test_negative_calibration_wall(self):
        self.rejection(lambda x: x[1]["records"][0].update(wallNS=-1), "invalid unsigned")

    def test_negative_calibration_loop(self):
        self.rejection(lambda x: x[1].update(loopNS=-1), "invalid unsigned")

    def test_negative_lifecycle_duration(self):
        self.rejection(lambda x: first_sample(x).update(explicitWorldReleaseNS=-1), "invalid unsigned")

    def test_inconsistent_lifecycle_total(self):
        self.rejection(lambda x: first_sample(x).update(workloadNS=1), "lifecycle/workload mismatch")

    def test_calibration_overlap(self):
        self.rejection(lambda x: x[1]["records"][1].update(startOffsetNS=1), "calibration chronology")

    def test_calibration_past_loop(self):
        self.rejection(lambda x: x[1].update(loopNS=1), "calibration chronology")

    def test_calibration_wrong_identity(self):
        self.rejection(lambda x: x[1]["records"][0].update(sample=1), "calibration identity")

    def test_calibration_wall_mode_cannot_have_counters(self):
        self.rejection(lambda x: x[1]["records"][0].update(before=snapshot(0, 1)), "wall-only")

    def test_calibration_counter_inside_wall(self):
        self.rejection(lambda x: x[2]["records"][0]["before"].update(endOffsetNS=4), "enter bracket")

    def test_negative_snapshot_offset(self):
        self.rejection(lambda x: x[2]["records"][0]["before"].update(beginOffsetNS=-1), "invalid unsigned")

    def test_negative_baseline_duration(self):
        self.rejection(lambda x: first_sample(x, "baseline")["aggregate"].update(initializationNS=-1), "invalid unsigned")

    def test_boolean_duration(self):
        self.rejection(lambda x: first_sample(x)["records"][0].update(wallNS=True), "invalid unsigned")

    def test_duration_overflow(self):
        self.rejection(lambda x: first_sample(x)["records"][0].update(wallNS=1 << 64), "invalid unsigned")

    def test_changed_mode_contract(self):
        self.rejection(lambda x: x[0].update(modes=["wall", "counters"]), "mode/batch")

    def test_changed_batch_contract(self):
        self.rejection(lambda x: x[0].update(batchSize=255), "mode/batch")

    def test_invalid_run_id(self):
        self.rejection(lambda x: x[0].update(runID=True), "run ID")

    def test_duplicate_batch(self):
        self.rejection(lambda x: first_sample(x)["records"][1].update(batch=0), "reordered batch")

    def test_economic_mismatch(self):
        self.rejection(lambda x: first_sample(x)["aggregate"].update(cashMinor=0), "economics")

    def test_sample_mode_order_mismatch(self):
        self.rejection(lambda x: first_sample(x).update(executionOrder=1), "alternating order")

    def test_zero_failed_read_rejected(self):
        self.rejection(lambda x: x[2]["records"][0]["before"].update(
            threadStatus="syscallFailure", threadErrno=22, threadCPUNS=0), "masquerading")


class CounterUnitTests(unittest.TestCase):
    def test_uint64_bounds(self):
        self.assertEqual(diag.unsigned(0, "zero"), 0)
        self.assertEqual(diag.unsigned((1 << 64) - 1, "maximum"), (1 << 64) - 1)
        for value in (-1, 1 << 64, True, 1.0, None, "1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                diag.unsigned(value, "invalid")

    def test_interval_overflow(self):
        with self.assertRaises(ValueError):
            diag.endpoint((1 << 64) - 1, 1, "overflow")

    def test_valid_zero_counters_retained(self):
        row = {"before": snapshot(0, 0), "after": snapshot(0, 0)}
        self.assertEqual(diag.counter_delta(row, "threadCPUNS"), (0, "ok"))

    def test_decreasing_counter_is_not_zero(self):
        row = {"before": snapshot(5, 5), "after": snapshot(4, 4)}
        self.assertEqual(diag.counter_delta(row, "threadCPUNS"), (None, "decreased"))

    def test_valid_failed_read_stays_absent(self):
        row = snapshot(0, 0)
        row.update(threadStatus="syscallFailure", threadErrno=22)
        del row["threadCPUNS"]
        diag.validate_snapshot(row)
        self.assertEqual(diag.counter_delta({"before": row, "after": row}, "threadCPUNS"),
                         (None, "syscallFailure/syscallFailure"))

    def test_success_must_not_carry_errno(self):
        row = snapshot(0, 0)
        row["threadErrno"] = 22
        with self.assertRaises(ValueError):
            diag.validate_snapshot(row)

    def test_unsupported_is_not_successful_zero(self):
        row = {"beginOffsetNS": 0, "endOffsetNS": 0, "threadStatus": "unsupported",
               "processStatus": "unsupported"}
        diag.validate_snapshot(row)
        self.assertEqual(diag.counter_delta({"before": row, "after": row}, "threadCPUNS"),
                         (None, "unsupported/unsupported"))

    def test_nearest_rank_actual_batch_distribution(self):
        self.assertEqual(diag.distribution(range(1, 101))["p99"], 99)
        self.assertEqual(diag.distribution([0]), {"count": 1, "min": 0, "max": 0,
                                               "p50": 0, "p90": 0, "p99": 0})


if __name__ == "__main__":
    unittest.main(verbosity=2)
