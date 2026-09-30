#!/usr/bin/env python3
"""Validate/aggregate COMPLETE raw per-batch data. No outlier filtering or causal verdicts."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
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
        if path.is_dir():
            entries = []
            for child in sorted(path.iterdir(), key=lambda p: p.name + ("/" if p.is_dir() else "")):
                if child == ROOT / "Checks/financial-diagnostics.py" or child.name == "__pycache__":
                    continue
                mode = "40000" if child.is_dir() else ("100755" if child.stat().st_mode & 0o111 else "100644")
                entries.append(mode.encode() + b" " + child.name.encode() + b"\0" + digest(child))
            return object_hash("tree", b"".join(entries))
        content = path.read_bytes()
        if path == ROOT / "Sources/NexoraFinancialCheck/main.swift":
            text = content.decode()
            check(text.count(MARKER) == 1 and text.count(DISPATCH) == 1, "ambiguous extension/dispatch")
            content = text.split(MARKER)[0].replace(DISPATCH, "").encode()
        return object_hash("blob", content)
    for name, wanted in expected.items():
        check(digest(ROOT / name).hex() == wanted, f"changed baseline object: {name}")
    print("PASS baseline Sources/Tests/Checks/Package/AGENTS/legacy-workflow objects and file modes; only diagnostic extension/dispatch")


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
    check(snapshot["beginOffsetNS"] <= snapshot["endOffsetNS"], "reversed counter-read envelope")
    for family, fields in (("thread", FIELDS[:1]), ("process", FIELDS[1:])):
        status = snapshot[family + "Status"]
        check(status in ("ok", "syscallFailure", "invalidValue", "unsupported"), "unknown reading status")
        if status == "syscallFailure":
            check(isinstance(snapshot.get(family + "Errno"), int), "failed call lacks errno")
        for field in fields:
            value = snapshot.get(field)
            if status == "ok":
                check(type(value) is int and value >= 0, f"successful {field} lacks nonnegative integer")
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
            check(type(row["wallNS"]) is int and row["wallNS"] >= 0, "invalid wall duration")
            if index:
                last = group[index - 1]
                check(last["startOffsetNS"] + last["wallNS"] <= row["startOffsetNS"], "overlapping wall windows")
            if mode == "counters":
                for side in ("before", "after"):
                    check(side in row, "missing requested counters")
                    validate_snapshot(row[side])
                check(row["before"]["endOffsetNS"] <= row["startOffsetNS"], "before counters enter bracket")
                check(row["startOffsetNS"] + row["wallNS"] <= row["after"]["beginOffsetNS"],
                      "after counters enter bracket")
            else:
                check(row.get("before") is None and row.get("after") is None, "wall-only read counters")


def phase_validation(item):
    rows = item["records"]
    if item["mode"] == "baseline":
        check(item["phases"] == [], "baseline phase schema")
        return
    check([p["phase"] for p in item["phases"]] == list(PHASES), "wrong phase list")
    for phase in item["phases"]:
        group = [r for r in rows if r["phase"] == phase["phase"]]
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
    check(len({p.resolve() for p in paths}) == len(paths), "duplicate input file")
    check(len({p.name for p in paths}) == len(paths), "ambiguous duplicate input basename")
    gaps, totals, extra = defaultdict(list), defaultdict(list), defaultdict(list)
    maxima, spikes, files, calibrations, pairs = {}, [], [], [], {}
    for path in paths:
        meta, completed = None, False
        seen, cal_modes = set(), set()
        expected_order = []
        with path.open() as reader:
            for number, line in enumerate(reader, 1):
                item = json.loads(line)
                kind = item["kind"]
                check(not completed, "data after completion marker")
                if kind == "metadata":
                    check(meta is None and number == 1, "metadata not first/unique")
                    meta = item
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
                    rows = item["records"]
                    check(len(rows) == item["iterations"] == 2000, "missing calibration windows")
                    for i, row in enumerate(rows):
                        check(row["batch"] == i and row["operations"] == 0 and row["phase"] == "empty", "bad calibration identity")
                        if item["mode"] == "counters":
                            validate_snapshot(row["before"]); validate_snapshot(row["after"])
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
        files.append({"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
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
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        print("PASS raw records, complete triples, exact phase sums, status-aware counters; summary", args.output)
    check(args.guard or args.selftest or args.raw, "no operation requested")


if __name__ == "__main__":
    main()
