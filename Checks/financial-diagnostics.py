#!/usr/bin/env python3
"""Validate/aggregate COMPLETE raw per-batch data. No outlier filtering or causal verdicts."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
import re
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKER = "\n// BEGIN R004 MEASUREMENT-ONLY EXTENSION\n"
DISPATCH = "        if try FinancialDiagnostics.dispatch(args) { return }\n"
FIELDS = ("threadCPUNS", "processUserNS", "processSystemNS", "processMinorFaults",
          "processMajorFaults", "processVoluntarySwitches", "processInvoluntarySwitches")
MODES = ("baseline", "wall", "counters")
PHASES = ("depart", "advance", "collect")


def check(condition, message):
    if not condition:
        raise ValueError(message)


def source_guard():
    # Git object identities from the published R004 source, independently rebuilt
    # from all 98 ZIP entries at resume. No dependency on git history or network.
    expected = {"Sources": "f9c19894cc77ea541101c82caa1defa383be3e72",
                "Tests": "83602394c3db51e9d6f43682dcb34a0a11f51c41",
                "Checks": "35903e43258a90f019f395035dab310436b177ec",
                "Package.swift": "9772a69021caed24dd9dac48c3aa32eb5d63207f",
                "AGENTS.md": "4b740a2712318dec0d9d9e3040447bb26f105e2b",
                ".github/workflows/restart.yml": "01668399e948242ebfd44ba3a89587dd1d647904"}
    def object_hash(kind, content):
        return hashlib.sha1(kind.encode() + b" " + str(len(content)).encode() + b"\0" + content).digest()
    def digest(path):
        # Do not follow links or omit names that SwiftPM may compile.
        check(not path.is_symlink(), f"symlink in guarded source: {path.relative_to(ROOT)}")
        if path.is_dir():
            entries = []
            for child in sorted(path.iterdir(), key=lambda p: p.name + ("/" if p.is_dir() else "")):
                check(not child.is_symlink(), f"symlink in guarded source: {child.relative_to(ROOT)}")
                if child == ROOT / "Checks/financial-diagnostics.py":
                    check(child.is_file(), "analyzer exception is not a regular file")
                    continue
                mode = "40000" if child.is_dir() else ("100755" if child.stat().st_mode & 0o111 else "100644")
                entries.append(mode.encode() + b" " + child.name.encode() + b"\0" + digest(child))
            return object_hash("tree", b"".join(entries))
        check(stat.S_ISREG(path.stat().st_mode), f"non-regular guarded source: {path}")
        content = path.read_bytes()
        if path == ROOT / "Sources/NexoraFinancialCheck/main.swift":
            text = content.decode()
            check(text.count(MARKER) == 1 and text.count(DISPATCH) == 1, "ambiguous extension/dispatch")
            content = text.split(MARKER)[0].replace(DISPATCH, "").encode()
        return object_hash("blob", content)
    for name, wanted in expected.items():
        check(digest(ROOT / name).hex() == wanted, f"changed baseline object: {name}")
    print("PASS baseline Sources/Tests/Checks/Package/AGENTS/legacy-workflow objects and file modes; only diagnostic extension/dispatch")



UINT64_MAX = (1 << 64) - 1
SOURCE_BASE = "5b5599895fa1bdbf00e951104e0cd55dc00f9a56"

# Schema 1 is a fixed contract. New counters/units require a separate schema.
COUNTER_DEFINITIONS = {'processInvoluntarySwitches': 'count; process; ru_nivcsw; Apple derives csw minus voluntary, clamps below zero', 'processMajorFaults': 'count; process; ru_majflt; Apple task pageins', 'processMinorFaults': 'count; process; ru_minflt; Apple faults minus pageins, not necessarily allocations', 'processSystemNS': 'ns converted from timeval microseconds; all process threads; getrusage(RUSAGE_SELF)', 'processUserNS': 'ns converted from timeval microseconds; all process threads; getrusage(RUSAGE_SELF)', 'processVoluntarySwitches': 'count; process; ru_nvcsw', 'threadCPUNS': 'ns; calling thread user+system; clock_gettime(CLOCK_THREAD_CPUTIME_ID); no mach conversion'}
SAMPLE_INDEXING = '1-based within warmup or measured stratum; batch is 0-based; calibration uses sample=0'
AGGREGATE_TIMES = ("initializationNS", "registerAllNS", "departAllNS", "advanceAllNS",
                   "maximumAdvanceNS", "collectAllNS", "maximumCollectionPageNS", "expensePostsNS")
AGGREGATE_COUNTS = ("advanceBatches", "invoiceCount", "journalCount")
LIFECYCLE_TIMES = ("bufferPreparationNS", "seedAndHandlePreparationNS", "finalAuditNS",
                   "explicitWorldReleaseNS", "workloadNS")


def object_fields(value, required, optional=()):
    check(type(value) is dict, "expected JSON object")
    missing, unknown = set(required) - value.keys(), value.keys() - set(required) - set(optional)
    check(not missing and not unknown, f"schema fields missing={sorted(missing)}, unknown={sorted(unknown)}")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        check(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"non-finite JSON number: {value}")


def validate_item_shape(item):
    check(type(item) is dict and type(item.get("kind")) is str, "missing record kind")
    kind = item["kind"]
    if kind == "metadata":
        object_fields(item, ("kind", "schema", "sourceBase", "sourceCommit", "runID", "processID",
                            "os", "sizes", "modes", "batchSize", "warmups", "repetitions",
                            "sampleIndexing", "mainThread", "counterDefinitions", "notCollected", "limitations"))
    elif kind == "calibration":
        object_fields(item, ("kind", "mode", "iterations", "loopNS", "records"))
        check(type(item["records"]) is list, "records must be an array")
    elif kind == "sample":
        object_fields(item, ("kind", "aircraft", "sample", "warmup", "mode", "runID", "executionOrder",
                            "aggregate", "records", "phases"),
                      () if item.get("mode") == "baseline" else LIFECYCLE_TIMES)
        check(type(item["records"]) is list and type(item["phases"]) is list, "records/phases must be arrays")
        aggregate = item["aggregate"]
        object_fields(aggregate, AGGREGATE_TIMES + AGGREGATE_COUNTS + ("revenueMinor", "cashMinor"))
        for field in AGGREGATE_TIMES + AGGREGATE_COUNTS:
            unsigned(aggregate[field], field)
        for field in ("revenueMinor", "cashMinor"):
            check(type(aggregate[field]) is int and -(1 << 63) <= aggregate[field] < (1 << 63),
                  f"invalid Int64 {field}")
        for phase in item["phases"]:
            object_fields(phase, ("phase", "startOffsetNS", "totalNS", "sumBatchWallNS", "outsideBatchWallNS"))
    elif kind == "complete":
        object_fields(item, ("kind", "status"))
    elif kind == "failure":
        object_fields(item, ("kind", "error"))
    else:
        raise ValueError(f"unknown record kind: {kind}")


def unsigned(value, name):
    # bool is an int subclass in Python, but is never a numeric measurement.
    check(type(value) is int and 0 <= value <= UINT64_MAX, f"invalid unsigned {name}")
    return value


def endpoint(start, duration, name):
    return unsigned(unsigned(start, name + ".start") + unsigned(duration, name + ".duration"),
                    name + ".end")


def validate_window(row, mode):
    object_fields(row, ("aircraft", "sample", "phase", "batch", "operations", "startOffsetNS", "wallNS"),
                  ("before", "after"))
    start = unsigned(row["startOffsetNS"], "window start")
    end = endpoint(start, row["wallNS"], "window")
    if mode == "counters":
        for side in ("before", "after"):
            check(isinstance(row.get(side), dict), "missing requested counters")
            validate_snapshot(row[side])
        check(row["before"]["endOffsetNS"] <= start, "before counters enter bracket")
        check(end <= row["after"]["beginOffsetNS"], "after counters enter bracket")
        return row["before"]["beginOffsetNS"], row["after"]["endOffsetNS"]
    check(mode == "wall", "unknown window mode")
    check(row.get("before") is None and row.get("after") is None, "wall-only read counters")
    return start, end


def validate_calibration(item):
    mode = item["mode"]
    check(mode in ("wall", "counters"), "unknown calibration mode")
    rows = item["records"]
    check(type(item["iterations"]) is int and len(rows) == item["iterations"] == 2000,
          "missing calibration windows")
    loop = unsigned(item["loopNS"], "calibration loop")
    previous_end, total = 0, 0
    for i, row in enumerate(rows):
        check(row["aircraft"] == 0 and type(row["aircraft"]) is int
              and row["sample"] == 0 and type(row["sample"]) is int
              and row["batch"] == i and type(row["batch"]) is int
              and row["operations"] == 0 and type(row["operations"]) is int
              and row["phase"] == "empty", "bad calibration identity")
        begin, end = validate_window(row, mode)
        check(previous_end <= begin <= end <= loop, "invalid calibration chronology")
        previous_end = end
        total += row["wallNS"]
    check(total <= loop, "calibration windows exceed loop")


def validate_lifecycle(item):
    aggregate = item["aggregate"]
    for field, value in aggregate.items():
        if field.endswith("NS"):
            unsigned(value, field)
    check(aggregate["maximumAdvanceNS"] <= aggregate["advanceAllNS"], "advance max exceeds phase")
    check(aggregate["maximumCollectionPageNS"] <= aggregate["collectAllNS"], "collection max exceeds phase")
    fields = ("bufferPreparationNS", "seedAndHandlePreparationNS", "finalAuditNS",
              "explicitWorldReleaseNS", "workloadNS")
    if item["mode"] == "baseline":
        check(all(item.get(field) is None for field in fields), "baseline unexpectedly has lifecycle probes")
        return
    for field in fields:
        unsigned(item.get(field), field)
    depart, advance, collect = item["phases"]
    check(depart["startOffsetNS"] == aggregate["initializationNS"]
          + item["seedAndHandlePreparationNS"] + aggregate["registerAllNS"],
          "initialization/registration lifecycle mismatch")
    check(depart["startOffsetNS"] + depart["totalNS"] == advance["startOffsetNS"],
          "nonadjacent depart/advance phases")
    check(advance["startOffsetNS"] + advance["totalNS"] <= collect["startOffsetNS"],
          "overlapping advance/collect phases")
    check(collect["startOffsetNS"] + collect["totalNS"] + aggregate["expensePostsNS"]
          + item["finalAuditNS"] + item["explicitWorldReleaseNS"] == item["workloadNS"],
          "final lifecycle/workload mismatch")


def validate_metadata(meta):
    validate_item_shape(meta)
    check(meta["counterDefinitions"] == COUNTER_DEFINITIONS, "changed counter definitions/units/scope")
    check(meta["sampleIndexing"] == SAMPLE_INDEXING, "changed sample indexing")
    check(type(meta["mainThread"]) is bool, "invalid thread identity")
    check(type(meta["sizes"]) is list and all(type(n) is int for n in meta["sizes"]), "invalid sizes")
    for field in ("notCollected", "limitations"):
        check(type(meta[field]) is list and bool(meta[field])
              and all(type(v) is str and bool(v) for v in meta[field]), f"missing or invalid {field}")
    check(meta["schema"] == "NXR-R004-BATCH-DIAGNOSTICS-1", "unknown schema")
    check(meta.get("sourceBase") == SOURCE_BASE, "wrong source base")
    check(type(meta.get("sourceCommit")) is str
          and re.fullmatch(r"[0-9a-f]{40}", meta["sourceCommit"]) is not None,
          "missing or invalid source commit; record NEXORA_SOURCE_COMMIT explicitly")
    check(meta.get("modes") == list(MODES) and type(meta.get("batchSize")) is int
          and meta["batchSize"] == 256, "changed mode/batch contract")
    check(type(meta.get("runID")) is int and 1 <= meta["runID"] <= 100, "invalid run ID")
    check(type(meta.get("processID")) is int and meta["processID"] > 0, "invalid process ID")
    check(type(meta.get("os")) is str and meta["os"], "missing OS identity")
    check(type(meta.get("warmups")) is int and type(meta.get("repetitions")) is int,
          "invalid sample schedule type")


def distribution(values):
    if not values:
        return {"count": 0}
    values = sorted(values)
    return {"count": len(values), "min": values[0], "max": values[-1],
            **{f"p{int(q*100)}": values[max(0, math.ceil(q * len(values)) - 1)]
               for q in (0.50, 0.90, 0.99)}}


def counter_delta(row, field):
    before, after = row.get("before"), row.get("after")
    if before is None or after is None:
        return None, "notRequested"
    status = "threadStatus" if field == "threadCPUNS" else "processStatus"
    if before[status] != "ok" or after[status] != "ok":
        return None, f"{before[status]}/{after[status]}"
    a, b = before.get(field), after.get(field)
    if a is None or b is None:
        return None, "missingValue"
    if b < a:
        return None, "decreased"
    return b - a, "ok"


def validate_snapshot(snapshot):
    object_fields(snapshot, ("beginOffsetNS", "endOffsetNS", "threadStatus", "processStatus"),
                  FIELDS + ("threadErrno", "processErrno"))
    unsigned(snapshot["beginOffsetNS"], "counter begin")
    unsigned(snapshot["endOffsetNS"], "counter end")
    check(snapshot["beginOffsetNS"] <= snapshot["endOffsetNS"], "reversed counter-read envelope")
    for family, fields in (("thread", FIELDS[:1]), ("process", FIELDS[1:])):
        status = snapshot[family + "Status"]
        check(status in ("ok", "syscallFailure", "invalidValue", "unsupported"), "unknown reading status")
        if status == "syscallFailure":
            # Preserve the raw Int32 errno, including zero when a failed clock
            # read did not set it. Failure status never becomes a numeric reading.
            error = snapshot.get(family + "Errno")
            check(type(error) is int and -(1 << 31) <= error < (1 << 31), "failed call lacks Int32 errno")
        else:
            check(snapshot.get(family + "Errno") is None, "successful/non-syscall read carries errno")
        for field in fields:
            value = snapshot.get(field)
            if status == "ok":
                unsigned(value, field)
            else:
                check(value is None, f"invalid {field} masquerading as measurement")


def validate_records(rows, *, count, sample, mode, phases=PHASES):
    batch_count = (count + 255) // 256
    if mode == "baseline":
        check(not rows, "baseline unexpectedly traced")
        return
    check(len(rows) == batch_count * len(phases), "missing/extra batches")
    for position, phase in enumerate(phases):
        group = rows[position * batch_count:(position + 1) * batch_count]
        for index, row in enumerate(group):
            check(row["aircraft"] == count and row["sample"] == sample and row["phase"] == phase,
                  "wrong batch identity")
            check(row["batch"] == index, "duplicate, missing or reordered batch")
            check(row["operations"] == min(256, count - index * 256), "wrong operation count")
            for field in ("aircraft", "sample", "batch", "operations"):
                unsigned(row[field], field)
            begin, end = validate_window(row, mode)
            if index:
                last = group[index - 1]
                last_end = (last["after"]["endOffsetNS"] if mode == "counters"
                            else last["startOffsetNS"] + last["wallNS"])
                check(last_end <= begin, "overlapping batch/counter windows")


def phase_validation(item):
    rows = item["records"]
    if item["mode"] == "baseline":
        check(item["phases"] == [], "baseline phase schema")
        return
    check([p["phase"] for p in item["phases"]] == list(PHASES), "wrong phase list")
    for phase in item["phases"]:
        for field in ("startOffsetNS", "totalNS", "sumBatchWallNS", "outsideBatchWallNS"):
            unsigned(phase[field], "phase " + field)
        end = endpoint(phase["startOffsetNS"], phase["totalNS"], "phase")
        group = [r for r in rows if r["phase"] == phase["phase"]]
        first_begin = (group[0]["before"]["beginOffsetNS"] if item["mode"] == "counters"
                       else group[0]["startOffsetNS"])
        last_end = (group[-1]["after"]["endOffsetNS"] if item["mode"] == "counters"
                    else group[-1]["startOffsetNS"] + group[-1]["wallNS"])
        check(phase["startOffsetNS"] <= first_begin <= last_end <= end, "counter/window exceeds phase")
        total = sum(r["wallNS"] for r in group)
        check(total == phase["sumBatchWallNS"], "batch sum mismatch")
        check(phase["totalNS"] - total == phase["outsideBatchWallNS"] >= 0, "negative or incorrect phase gap")
        check(phase["startOffsetNS"] <= group[0]["startOffsetNS"], "batch precedes phase")
        check(group[-1]["startOffsetNS"] + group[-1]["wallNS"] <= phase["startOffsetNS"] + phase["totalNS"],
              "batch exceeds phase")
        aggregate_key = {"depart": "departAllNS", "advance": "advanceAllNS", "collect": "collectAllNS"}[phase["phase"]]
        check(item["aggregate"][aggregate_key] == phase["totalNS"], "aggregate total mismatch")
    for phase, key in (("advance", "maximumAdvanceNS"), ("collect", "maximumCollectionPageNS")):
        check(max(r["wallNS"] for r in rows if r["phase"] == phase) == item["aggregate"][key], "incorrect maximum")


def analyze(paths):
    batches, first, full, partial, counter_values, coverage = (defaultdict(list) for _ in range(6))
    first_counters, first_coverage = defaultdict(list), defaultdict(list)
    check(bool(paths), "no input files")
    check(len({p.resolve() for p in paths}) == len(paths), "duplicate input file")
    check(len({p.name for p in paths}) == len(paths), "ambiguous duplicate input basename")
    gaps, totals, extra = defaultdict(list), defaultdict(list), defaultdict(list)
    maxima, spikes, files, calibrations, pairs = {}, [], [], [], {}
    source_identity, run_ids, hashes = None, set(), set()
    for path in paths:
        hasher = hashlib.sha256()
        with path.open("rb") as binary:
            for block in iter(lambda: binary.read(1 << 20), b""):
                hasher.update(block)
        file_hash = hasher.hexdigest()
        check(file_hash not in hashes, "duplicate raw bytes under a different filename")
        hashes.add(file_hash)
        meta, completed = None, False
        seen, cal_modes = set(), set()
        expected_order = []
        with path.open() as reader:
            for number, line in enumerate(reader, 1):
                item = json.loads(line, object_pairs_hook=unique_object, parse_constant=reject_constant)
                validate_item_shape(item)
                kind = item["kind"]
                check(not completed, "data after completion marker")
                if kind == "metadata":
                    check(meta is None and number == 1, "metadata not first/unique")
                    meta = item
                    validate_metadata(meta)
                    identity = (meta["sourceBase"], meta["sourceCommit"], meta["os"], meta["mainThread"],
                                json.dumps(meta.get("counterDefinitions"), sort_keys=True))
                    check(source_identity is None or identity == source_identity,
                          "mixed source/OS/counter definitions in one analysis")
                    source_identity = identity
                    check(meta["runID"] not in run_ids, "duplicate run ID in one analysis")
                    run_ids.add(meta["runID"])
                    check(item["schema"] == "NXR-R004-BATCH-DIAGNOSTICS-1", "unknown schema")
                    check(meta["sizes"] == [1000,5000,20000,50000,100000], "changed size fixture")
                    check((meta["warmups"], meta["repetitions"]) in ((0,1),(3,30)), "unknown sample schedule")
                    for n in meta["sizes"]:
                        for round_index in range(meta["warmups"] + meta["repetitions"]):
                            warm = round_index < meta["warmups"]
                            sample_index = round_index + 1 if warm else round_index - meta["warmups"] + 1
                            order = MODES if (round_index + meta["runID"]) % 2 == 0 else tuple(reversed(MODES))
                            expected_order.extend((n, sample_index, warm, mode) for mode in order)
                elif kind == "calibration":
                    check(meta is not None and item["mode"] not in cal_modes, "calibration duplicate")
                    cal_modes.add(item["mode"])
                    check(not seen, "calibration after sample data")
                    validate_calibration(item)
                    rows = item["records"]
                    calibrations.append({"file": path.name, "runID": meta["runID"], "mode": item["mode"],
                        "iterations": item["iterations"], "loopNS": item["loopNS"],
                        "loopMeanNSPerWindow": item["loopNS"] / item["iterations"],
                        "innerWallNS": distribution([r["wallNS"] for r in rows]),
                        "counterReadEnvelopeNS": distribution([
                            r[side]["endOffsetNS"] - r[side]["beginOffsetNS"]
                            for r in rows for side in ("before", "after") if side in r])})
                elif kind == "sample":
                    check(meta is not None, "sample before metadata")
                    n, s, warmup, mode = item["aircraft"], item["sample"], item["warmup"], item["mode"]
                    check(n in meta["sizes"] and mode in MODES and type(warmup) is bool, "unexpected sample")
                    check(1 <= s <= (meta["warmups"] if warmup else meta["repetitions"]), "sample index")
                    identity = (n, s, warmup, mode)
                    check(identity not in seen and item["runID"] == meta["runID"], "duplicate/wrong run")
                    check(cal_modes == {"wall", "counters"}, "sample precedes calibration")
                    check(len(seen) < len(expected_order) and identity == expected_order[len(seen)], "serialized execution order mismatch")
                    seen.add(identity)
                    round_index = s - 1 if warmup else meta["warmups"] + s - 1
                    order = MODES if (round_index + meta["runID"]) % 2 == 0 else tuple(reversed(MODES))
                    check(item["executionOrder"] == order.index(mode), "wrong alternating order")
                    validate_records(item["records"], count=n, sample=s, mode=mode)
                    phase_validation(item)
                    validate_lifecycle(item)
                    for field in ("aircraft", "sample", "runID", "executionOrder"):
                        unsigned(item[field], field)
                    agg = item["aggregate"]
                    income = sum(i % 97 + 101 for i in range(n))
                    check((agg["invoiceCount"], agg["journalCount"], agg["revenueMinor"], agg["cashMinor"], agg["advanceBatches"])
                          == (n, 2*n + 4, income, income - 5000, (n+255)//256), "changed economics")
                    # Warmups remain in raw data, explicitly separated from reported measured distributions.
                    if warmup:
                        continue
                    pair_key = (path.name, n, s)
                    pairs.setdefault(pair_key, {})[mode] = agg
                    for field, value in agg.items():
                        if field.endswith("NS"):
                            totals[(n, mode, field)].append(value)
                    for field in ("bufferPreparationNS", "seedAndHandlePreparationNS", "finalAuditNS",
                                  "explicitWorldReleaseNS", "workloadNS"):
                        if field in item:
                            extra[(n, mode, field)].append(item[field])
                    for phase in item["phases"]:
                        gaps[(n, mode, phase["phase"])].append(phase["outsideBatchWallNS"])
                    for row in item["records"]:
                        key = (n, mode, row["phase"])
                        wall = row["wallNS"]
                        batches[key].append(wall)
                        (full if row["operations"] == 256 else partial)[key].append(wall)
                        if row["batch"] == 0:
                            first[key].append(wall)
                        annotated = {"file": path.name, "runID": meta["runID"], "aircraft": n, "sample": s,
                                     "mode": mode, **row}
                        deltas = {}
                        for field in FIELDS:
                            value, status = counter_delta(row, field)
                            coverage[(n, mode, row["phase"], field)].append(status)
                            if value is not None:
                                counter_values[(n, mode, row["phase"], field)].append(value)
                            if row["batch"] == 0:
                                first_coverage[(n, mode, row["phase"], field)].append(status)
                                if value is not None:
                                    first_counters[(n, mode, row["phase"], field)].append(value)
                            deltas[field] = {"status": status, "value": value}
                        annotated["counterDeltas"] = deltas
                        cpu = deltas["threadCPUNS"]["value"]
                        annotated["wallMinusEnclosingThreadCPUNS"] = None if cpu is None else wall - cpu
                        annotated["causalVerdict"] = "unresolved; wider counter intervals/process scope"
                        if key not in maxima or wall > maxima[key]["wallNS"]:
                            maxima[key] = annotated
                        if wall > 1_000_000:
                            spikes.append(annotated)
                elif kind == "complete":
                    check(item.get("status") == "all-fixture-checks-passed", "invalid completion status")
                    completed = True
                elif kind == "failure":
                    raise ValueError(f"recorded fixture failure: {item}")
                else:
                    raise ValueError(f"unknown record kind: {kind}")
        check(completed and meta is not None, f"incomplete raw file: {path}")
        check(cal_modes == {"wall", "counters"}, "missing calibration mode")
        expected = {(n, s, warmup, mode) for n in meta["sizes"] for warmup in (False, True)
                    for s in range(1, (meta["warmups"] if warmup else meta["repetitions"]) + 1) for mode in MODES}
        check(seen == expected, "missing sample triples")
        files.append({"file": path.name, "sha256": file_hash,
                      "metadata": meta, "samplesIncludingWarmups": len(seen)})
    summaries = []
    for key, values in sorted(batches.items()):
        n, mode, phase = key
        summaries.append({"aircraft": n, "mode": mode, "phase": phase,
            "wallNS": distribution(values), "full256WallNS": distribution(full[key]),
            "partialBatchWallNS": distribution(partial[key]), "firstBatchWallNS": distribution(first[key]),
            "above1ms": sum(v > 1_000_000 for v in values), "above5ms": sum(v > 5_000_000 for v in values),
            "outsideBatchWallNSPerSample": distribution(gaps[key]), "maximumRecord": maxima[key],
            "firstBatchCounterDeltas": {f: {"distribution": distribution(first_counters[(*key, f)]),
                                         "coverage": dict(Counter(first_coverage[(*key, f)]))} for f in FIELDS},
            "counterDeltas": {f: {"distribution": distribution(counter_values[(*key, f)]),
                                  "coverage": dict(Counter(coverage[(*key, f)]))} for f in FIELDS}})
    comparisons = defaultdict(list)
    for (_, n, _), modes in pairs.items():
        check(set(modes) == set(MODES), "incomplete comparison trio")
        for numerator, denominator in (("wall", "baseline"), ("counters", "wall")):
            for field in ("initializationNS", "registerAllNS", "departAllNS", "advanceAllNS", "collectAllNS", "expensePostsNS"):
                a, b = modes[numerator][field], modes[denominator][field]
                comparisons[(n, numerator, denominator, field, "differenceNS")].append(a - b)
                if b:
                    comparisons[(n, numerator, denominator, field, "ratio")].append(a / b)
    return {"status": "complete-raw-files-validated", "units": "nanoseconds unless field says count/ratio",
        "percentiles": "nearest rank of actual per-batch observations; no extrapolated deadline or outlier removal",
        "files": files, "calibration": calibrations, "batchDistributions": summaries,
        "phaseAndLifecycle": [{"aircraft": n, "mode": m, "field": f, "distribution": distribution(v)}
                              for (n,m,f),v in sorted({**totals, **extra}.items())],
        "pairedAA": [{"aircraft": n, "numerator": a, "denominator": b, "field": f, "metric": metric,
                      "distribution": distribution(v)} for (n,a,b,f,metric),v in sorted(comparisons.items())],
        "allBatchesAbove1ms": spikes,
        "limits": ["Warmups preserved but stratified. No inference from old R004 sample maxima to batch percentiles.",
                   "No causality from coincidence; counter intervals wider than wall, process counters not thread-specific.",
                   "Ratios include order, cache/allocator/address variation; they are observations, not isolated causal estimates.",
                   "No iPhone/frame/temperature/full-game acceptance."]}


def selftest():
    check(distribution(range(1,101))["p99"] == 99, "nearest-rank percentiles")
    check(distribution([3])["p99"] == 3 and distribution([]) == {"count":0}, "small sample percentiles")
    row = {"before":{"threadStatus":"ok", "threadCPUNS":5}, "after":{"threadStatus":"ok", "threadCPUNS":4}}
    check(counter_delta(row,"threadCPUNS") == (None,"decreased"), "counter regression incorrectly clamped")
    row["after"]["threadCPUNS"] = 5
    check(counter_delta(row,"threadCPUNS") == (0,"ok"), "valid zero lost")
    row["after"]["threadStatus"] = "syscallFailure"
    check(counter_delta(row,"threadCPUNS")[0] is None, "failure not invalidated")
    check(counter_delta({},"threadCPUNS") == (None,"notRequested"), "unrequested not distinguished")
    bad = {"beginOffsetNS":0,"endOffsetNS":1,"threadStatus":"syscallFailure","threadErrno":22,
           "threadCPUNS":0,"processStatus":"unsupported"}
    try:
        validate_snapshot(bad)
    except ValueError:
        pass
    else:
        raise ValueError("accepted zero masquerading as failed measurement")
    print("PASS analysis probes: actual percentiles, valid zeros, missing/decreased/failed counters, invalid-zero rejection")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--guard", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("raw", type=Path, nargs="*")
    args = parser.parse_args()
    if args.guard:
        source_guard()
    if args.selftest:
        selftest()
    if args.raw:
        check(args.output is not None, "--output required with raw files")
        result = analyze(args.raw)
        # Never erase a prior result or replace a raw input through a reused path.
        # Serialize first; a failed I/O may leave an incomplete new file, never a replaced old one.
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        with args.output.open("x", encoding="utf-8") as writer:
            writer.write(text)
        print("PASS raw records, complete triples, exact phase sums, status-aware counters; summary", args.output)
    check(args.guard or args.selftest or args.raw, "no operation requested")


if __name__ == "__main__":
    main()
