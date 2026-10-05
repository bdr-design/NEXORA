"""Pure acceptance rules shared by measurement, revalidation and negative tests."""
import math

THRESHOLDS = {
    "beginSaveP99NS": 100_000,
    "advanceDuringSaveP99NS": 1_100_000,
    "overheadRatio": 1.10,
    "idleAllocationsPerAdvance": 0,
}


def stage_a_failures(rows, health):
    failures = []
    for row in rows:
        if row["allocationsMaxPerCall"] != 0:
            failures.append(f"{row['variant']}@{row['assets']} allocations {row['allocationsMaxPerCall']} != 0")
        for sample in row["rawProcesses"]:
            if sample["cAllocationPositiveControl"] <= 0 or sample["swiftAllocationPositiveControl"] <= 0:
                failures.append(f"{row['variant']}@{row['assets']} allocator positive control failed")
    for variant in ("S", "H"):
        for key in ("order100k", "order1M"):
            if health[variant][key]["status"] != "pass":
                failures.append(f"{variant} {key} correctness failed")
    return failures


def stage_c_failures(result):
    failures = []
    if result["saves"] < 100:
        failures.append(f"saves {result['saves']} < 100")
    for key, threshold in (("beginSaveNS", "beginSaveP99NS"), ("advanceDuringSaveNS", "advanceDuringSaveP99NS")):
        if result[key]["samples"] <= 0:
            failures.append(f"{key} has no samples")
        if result[key]["p99"] > THRESHOLDS[threshold]:
            failures.append(f"{key} p99 {result[key]['p99']} > {THRESHOLDS[threshold]}")
    ratio = result["overheadRatio"]
    if not math.isfinite(ratio) or ratio > THRESHOLDS["overheadRatio"]:
        failures.append(f"overheadRatio {ratio:.9f} > {THRESHOLDS['overheadRatio']:.2f} or non-finite")
    if result["allocationsIdleMaxPerAdvance"] != 0:
        failures.append(f"idle allocations {result['allocationsIdleMaxPerAdvance']} != 0")
    pairs = result.get("allocationPairing")
    if not pairs:
        failures.append("paired per-advance allocation evidence is missing")
    else:
        if pairs["samples"] != result["advanceDuringSaveNS"]["samples"]:
            failures.append("allocation pairs do not cover every saving advance")
        if pairs["violations"] != 0 or pairs["maxExcess"] != 0:
            failures.append(f"saving allocation bound violated in {pairs['violations']} advances; max excess {pairs['maxExcess']}")
    return failures
