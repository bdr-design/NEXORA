"""Verify the bounded disposable sealed-WAL micro and its Apple artifact."""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import argparse
import hashlib
import json
import math
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata


if not __debug__:
    raise RuntimeError("sealed WAL verifier requires Python assertions")

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).parent
sys.path.insert(0, str(ROOT / "Experiments/R005Swift"))
from candidate_proof_inputs import manifest

MODES = ("debug", "release", "tsan")
DECISION = "SEALED_WAL_MICRO_PARTIAL_BLOCKED"
INTEGRATION_DECISION = "NO_GO_INTEGRATION_C100"
CORRUPTION_BOOLEAN_CASES = {
    "wholeFrameSuffixDeletion", "tornFrame", "tornSeal", "sealWALMismatch",
    "wrongParent", "wrongBase", "wrongVersion", "wrongRoot",
    "missingLatestManifest", "staleManifestGeneration",
    "rolledBackManifestWithDescendant", "wholeSealStrip", "appendAfterSeal",
    "crossStoreValidFrameSplice", "successorHeaderLoss",
    "successorDirectoryEntryDeletion", "forkSuccessor", "duplicateSegment",
    "reorderedSegment", "futureSegment",
}
CRASH_PHASES = (
    "afterWALFsync", "afterSealTempFsync", "afterSealRename",
    "afterSealDirsync", "afterSuccessorTempFsync", "afterSuccessorRename",
    "afterSuccessorDirsync", "afterManifestTempFsync", "afterManifestRename",
    "afterManifestDirsync", "afterDurableManifestBeforeCallback",
)
TIMING_FIELDS = {
    "advanceNS", "walEncodeNS", "walWriteNS", "rescheduleNS", "serviceNS",
    "sealNS", "walFsyncNS", "manifestNS", "handleSwitchNS",
    "durableManifestPublishNS", "wholeLoopNS",
}
ALLOWED_STUDY_INPUTS = {
    ".github/workflows/r005-sealed-wal-micro.yml",
    "Checks/financial-diagnostics.py",
    "Experiments/R005Swift/Package.swift",
    "Experiments/R005Swift/candidate_proof_inputs.py",
    "Experiments/R005Swift/Evidence/20261007/SealedWALMicro.swift",
    "Experiments/R005Swift/Evidence/20261007/prepare-sealed-wal-micro.py",
    "Experiments/R005Swift/Evidence/20261007/verify-sealed-wal-micro.py",
}
ROOT_KEYS = {
    "status", "acceptance", "decision", "integrationDecision",
    "integrationEligible", "scope", "format", "publicationOrder", "happyChain",
    "corruption", "crashMatrix", "modeledIOFailureBranches",
    "syscallLevelFaultInjection", "recoverAppendSealRecover", "recoveryCadence",
    "nonAtomicAdmissionCheckAndGC",
    "pairedABBA", "pairedMeasurementGaps", "boundedIO", "semantics",
    "H1M", "C5", "C100", "safeToRunH1M", "safeToRunC",
    "crossProcessOwnerLock", "physicalPowerLoss", "limitations",
}
LIMITS = {
    "buildModes": ["debug", "release", "tsan"],
    "swiftLanguageMode": 6,
    "swiftDefines": ["SEALED_WAL_MICRO"],
    "warningsAsErrors": True,
    "runtimeWallSecondsPerMode": 300,
    "runtimeCPUSecondsPerMode": 120,
    "runtimeFileBytesPerProcess": 16 * 1024 * 1024,
    "scratchAllocatedBytesMaximumPerMode": 3 * 1024 * 1024 * 1024,
    "artifactBytesMaximum": 128 * 1024 * 1024,
    "maximumRecoverySegmentsExecuted": 25,
    "H1M": "NOT_RUN",
    "C5": "NOT_RUN",
    "C100": "NOT_RUN",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_hex(value, length):
    return (isinstance(value, str) and len(value) == length and
            all(character in "0123456789abcdef" for character in value))


def reject_true_acceptance(value, path="root"):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "acceptance":
                assert child is False, f"acceptance=true at {path}"
            reject_true_acceptance(child, path + "." + key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_true_acceptance(child, f"{path}[{index}]")


def validate_format(value):
    assert set(value) == {
        "headerBytes", "frameBytes", "sealBytes", "manifestBytes", "baseBytes",
        "globalLSN", "storeIdentifiersUniqueByDefault", "initialRootBoundToStore",
        "sealBindings", "immutableManifestGenerations",
        "latestGenerationAuthority", "durableCURRENT",
    }
    assert {key: value[key] for key in (
        "headerBytes", "frameBytes", "sealBytes", "manifestBytes", "baseBytes"
    )} == {
        "headerBytes": 192, "frameBytes": 128, "sealBytes": 320,
        "manifestBytes": 320, "baseBytes": 144,
    }
    for key in ("globalLSN", "storeIdentifiersUniqueByDefault",
                "initialRootBoundToStore", "immutableManifestGenerations"):
        assert value[key] is True
    assert value["latestGenerationAuthority"] == "NOT_PROVED_NO_DURABLE_CURRENT"
    assert value["durableCURRENT"] == "NOT_IMPLEMENTED"
    assert set(value["sealBindings"]) == {
        "exactByteLength", "frameCount", "epoch", "firstLSN", "lastLSN",
        "globalLSN", "parentSeal", "baseCheckpoint", "store", "schema",
        "engine", "layout", "terminalRoot", "WALDigest", "headerDigest",
    }
    assert len(value["sealBindings"]) == 15


def validate_crash_matrix(rows):
    assert [row["phase"] for row in rows] == list(CRASH_PHASES)
    assert all(set(row) == {
        "phase", "outcome", "comparedFields", "allowedOutcomes"
    } for row in rows)
    expected = {
        "afterWALFsync": ["OLD_DURABLE_TIP_EXACT"],
        "afterSealTempFsync": ["OLD_DURABLE_TIP_EXACT"],
        "afterSealRename": ["FAIL_CLOSED"],
        "afterSealDirsync": ["FAIL_CLOSED"],
        "afterSuccessorTempFsync": ["FAIL_CLOSED"],
        "afterSuccessorRename": ["FAIL_CLOSED"],
        "afterSuccessorDirsync": ["FAIL_CLOSED"],
        "afterManifestTempFsync": ["FAIL_CLOSED"],
        "afterManifestRename": ["NEW_DURABLE_TIP_EXACT", "FAIL_CLOSED"],
        "afterManifestDirsync": ["NEW_DURABLE_TIP_EXACT"],
        "afterDurableManifestBeforeCallback": ["NEW_DURABLE_TIP_EXACT"],
    }
    for row in rows:
        assert row["comparedFields"] == ["root", "value", "durableLSN", "generation"]
        assert row["allowedOutcomes"] == expected[row["phase"]]
        assert row["outcome"] in row["allowedOutcomes"]


def validate_paired(value):
    assert set(value) == {
        "order", "sameLogicalFixture", "finalLiveRoot", "finalLiveValue", "legs",
        "saveWholeLoopMedianNS", "noSaveWholeLoopMedianNS",
        "diagnosticWholeLoopRatio", "classification",
    }
    assert value["order"] == ["no-save", "save", "save", "no-save"]
    assert value["sameLogicalFixture"] is True
    assert is_hex(value["finalLiveRoot"], 64)
    assert type(value["finalLiveValue"]) is int
    assert value["classification"] == "BOUNDED_SYNTHETIC_DIAGNOSTIC_NOT_C"
    assert type(value["saveWholeLoopMedianNS"]) is int
    assert type(value["noSaveWholeLoopMedianNS"]) is int
    assert value["saveWholeLoopMedianNS"] > 0
    assert value["noSaveWholeLoopMedianNS"] > 0
    ratio = value["diagnosticWholeLoopRatio"]
    assert type(ratio) in (int, float) and math.isfinite(ratio) and ratio >= 0

    expected = (("0-no-save", False), ("1-save", True),
                ("2-save", True), ("3-no-save", False))
    assert len(value["legs"]) == len(expected)
    for leg, (label, save) in zip(value["legs"], expected):
        assert set(leg) == {
            "label", "save", "calls", "committedSegments", "liveGlobalLSN",
            "liveValue", "liveRoot", "selectedManifestTipExactWithinPresentDirectory",
            "components",
        }
        assert leg["label"] == label and leg["save"] is save
        assert leg["calls"] == 32 and leg["liveGlobalLSN"] == 32
        assert leg["committedSegments"] == (4 if save else 0)
        assert leg["liveValue"] == value["finalLiveValue"]
        assert leg["liveRoot"] == value["finalLiveRoot"]
        assert leg["selectedManifestTipExactWithinPresentDirectory"] is True
        components = leg["components"]
        assert set(components) == TIMING_FIELDS
        assert all(type(components[key]) is int and components[key] >= 0
                   for key in TIMING_FIELDS)
        assert components["wholeLoopNS"] > 0
        if save:
            for key in ("sealNS", "walFsyncNS", "manifestNS", "handleSwitchNS",
                        "durableManifestPublishNS"):
                assert components[key] > 0
        else:
            for key in ("sealNS", "manifestNS", "handleSwitchNS",
                        "durableManifestPublishNS"):
                assert components[key] == 0
            assert components["walFsyncNS"] > 0


def validate_row(row):
    reject_true_acceptance(row)
    assert set(row) == ROOT_KEYS
    assert row["status"] == "diagnostic-partial"
    assert row["acceptance"] is False
    assert row["decision"] == DECISION
    assert row["integrationDecision"] == INTEGRATION_DECISION
    assert row["integrationEligible"] is False
    assert row["H1M"] == row["C5"] == row["C100"] == "NOT_RUN"
    assert row["safeToRunH1M"] is False and row["safeToRunC"] is False
    assert row["crossProcessOwnerLock"] == "NOT_IMPLEMENTED"
    assert row["physicalPowerLoss"] == "NOT_TESTED"
    assert "no runtime source" in row["scope"]
    assert "H1M" in row["scope"] and "C" in row["scope"]
    validate_format(row["format"])
    assert row["publicationOrder"] == [
        "WAL_fsync", "seal_temp_fsync", "seal_rename", "seal_dirsync",
        "successor_temp_fsync", "successor_rename", "successor_dirsync",
        "manifest_temp_fsync", "manifest_rename", "manifest_dirsync",
        "caller_commit_callback",
    ]
    assert row["happyChain"] == {
        "segments": 3, "frames": 9, "generation": 3,
        "selectedManifestTipExactWithinPresentDirectory": True,
    }
    assert set(row["corruption"]) == CORRUPTION_BOOLEAN_CASES | {"cleanRollbackDeletion"}
    assert all(row["corruption"][name] is True for name in CORRUPTION_BOOLEAN_CASES)
    assert row["corruption"]["cleanRollbackDeletion"] == {
        "status": "EXPECTED_KNOWN_GAP",
        "reason": "NO_DURABLE_CURRENT_AUTHORITY",
        "deletedEntries": ["manifest-2.bin", "segment-1.seal", "segment-2.wal"],
        "latestGenerationBeforeDeletion": 2,
        "acceptedDurableGenerationAfterDeletion": 1,
        "formerCommittedTailReclassifiedAsPending": True,
    }
    validate_crash_matrix(row["crashMatrix"])
    assert row["modeledIOFailureBranches"] == {
        "EIO": "NO_COMMIT_OLD_DURABLE_TIP_EXACT",
        "shortWrite": True,
        "ENOSPC": "NO_COMMIT_OLD_DURABLE_TIP_PLUS_VALID_PENDING_FRAME",
        "manifestShortWriteAfterSeal": True,
        "modeledPrePublicationFailuresInvalidateLiveHandle": True,
    }
    assert row["syscallLevelFaultInjection"] == "NOT_IMPLEMENTED"
    assert row["recoverAppendSealRecover"] == {
        "firstRecoveryDurableValue": 0,
        "firstRecoveryPendingValue": 13,
        "resumedAtGlobalLSN": 2,
        "secondRecoveryDurableValue": 9,
        "secondRecoveryFrames": 3,
        "exact": True,
    }
    cadence = row["recoveryCadence"]
    assert [item["segments"] for item in cadence] == [0, 1, 5, 10, 25]
    for item in cadence:
        assert set(item) == {
            "segments", "frames", "elapsedNS", "selectedPresentTipExact", "streaming"
        }
        assert item["frames"] == item["segments"]
        assert type(item["elapsedNS"]) is int and item["elapsedNS"] >= 0
        assert item["selectedPresentTipExact"] is True and item["streaming"] is True

    gate = row["nonAtomicAdmissionCheckAndGC"]
    assert set(gate) == {
        "staleCompactorAdmissionCheckRejected",
        "currentCompactorAdmissionCheckAccepted", "admissionCheckNoManifestMutation",
        "atomicCAS",
        "compactionPayloadBuild", "compactionPublication", "cleanupFailureStatus",
        "cleanupFailureKeepsCommittedTip", "cleanupFailureKeepsLiveHandleUsable",
        "GCReachabilityRemovedUnreferenced",
        "GCUsesRetainedManifestReachability", "GCDeletesByEpochAlone",
        "classification",
    }
    for key in ("staleCompactorAdmissionCheckRejected",
                "currentCompactorAdmissionCheckAccepted", "admissionCheckNoManifestMutation",
                "cleanupFailureKeepsCommittedTip", "cleanupFailureKeepsLiveHandleUsable",
                "GCUsesRetainedManifestReachability"):
        assert gate[key] is True
    assert gate["atomicCAS"] == "NOT_IMPLEMENTED"
    assert gate["compactionPayloadBuild"] == "NOT_IMPLEMENTED"
    assert gate["compactionPublication"] == "NOT_IMPLEMENTED"
    assert gate["cleanupFailureStatus"] == "COMMITTED_GC_PENDING"
    assert gate["GCReachabilityRemovedUnreferenced"] == 2
    assert gate["GCDeletesByEpochAlone"] is False
    assert gate["classification"] == \
        "NON_ATOMIC_ADMISSION_CHECK_AND_GC_ONLY_NOT_COMPACTION_PROOF"
    validate_paired(row["pairedABBA"])
    assert row["pairedMeasurementGaps"] == {
        "allocationObserver": "NOT_MEASURED",
        "physicalFootprint": "NOT_MEASURED",
        "logicalVsAllocatedDisk": "NOT_MEASURED",
        "writeAmplification": "NOT_MEASURED",
        "backpressure": "NOT_IMPLEMENTED_OR_MEASURED",
        "compactorOverlap": "NOT_IMPLEMENTED_OR_MEASURED",
    }
    assert row["boundedIO"] == {
        "fullFileDataReads": 0, "streamedFrameReadBytes": 128,
        "streamedHashBlockBytes": 65_536, "writerReusableFrameBytes": 128,
        "writerReusableSealBytes": 320, "writerReusableManifestBytes": 320,
        "writerReusableHeaderBytes": 192,
        "fixedMetadataPools": "NOT_IMPLEMENTED",
        "directoryListingAllocation": "DYNAMIC",
        "manifestHistoryAllocation": "DYNAMIC",
        "activeTailValidation": "STREAMED_EXACT_FRAME_OR_FAIL_CLOSED",
        "reopenAppend": True, "secondWorlds": 0,
        "maximumRecoverySegmentsExecuted": 25,
    }
    assert row["semantics"] == {
        "recovery": "HIGHEST_CONTIGUOUS_PRESENT_MANIFEST_EXACT_OR_FAIL_CLOSED_WITH_KNOWN_CLEAN_ROLLBACK_GAP",
        "prePublicationAppendOrCommitError": "LIVE_HANDLE_INVALIDATED_RECOVERY_REQUIRED",
        "cleanupFailure": "COMMITTED_GC_PENDING",
        "staleCompactor": "NON_ATOMIC_ADMISSION_CHECK_ONLY",
        "activeUnpublishedSuffix": "VALIDATED_BUT_NOT_APPLIED_TO_DURABLE_ROOT",
        "callbackUncertainty": "DIRSYNC_MAY_COMMIT_BEFORE_CALLER_OBSERVES_RETURN",
        "requestID": "NOT_IMPLEMENTED",
        "idempotentStatusQuery": "NOT_IMPLEMENTED",
    }
    limitations = row["limitations"]
    for phrase in (
        "single-process", "scalar/root fixture", "no durable CURRENT authority",
        "Request IDs", "fixed metadata pools", "syscall-level fault injection",
        "do not certify physical power loss",
        "not implemented or measured", "bounded to 25 segments",
        "cross-process locking", "overheadRatio<=1.10", "remain unproved",
    ):
        assert phrase in limitations, phrase
    return {
        "status": row["status"], "decision": row["decision"],
        "integrationDecision": row["integrationDecision"],
        "pairedFinalRoot": row["pairedABBA"]["finalLiveRoot"],
        "pairedFinalValue": row["pairedABBA"]["finalLiveValue"],
        "corruptionCases": len(row["corruption"]),
        "crashPhases": len(row["crashMatrix"]),
    }


def raw_inputs():
    names = {
        "commit.txt", "tree.txt", "environment.txt", "runtime-inputs.json",
        "source-guard-before.txt", "source-guard-after.txt",
        "study-input-sha256.txt", "study-source.json", "limits.json", "scope.txt",
    }
    for mode in MODES:
        names.update({f"build-{mode}.txt", f"run-{mode}.json",
                      f"run-{mode}.stderr.txt", f"scratch-{mode}.json"})
    return names


def validate_study_input_hashes(path, compare_current):
    found = {}
    for line in path.read_text().splitlines():
        digest, name = line.split(None, 1)
        name = name.strip()
        assert name in ALLOWED_STUDY_INPUTS and name not in found
        assert is_hex(digest, 64)
        found[name] = digest
    assert set(found) == ALLOWED_STUDY_INPUTS
    if compare_current:
        for name, digest in found.items():
            candidate = ROOT / name
            assert candidate.is_file() and not candidate.is_symlink()
            assert sha(candidate) == digest
    return found


def validate_raw(raw, expect_summary, expect_manifest):
    expected = raw_inputs()
    if expect_summary:
        expected.add("SEALED-WAL-MICRO-STUDY.json")
    if expect_manifest:
        expected.add("RAW-MANIFEST.json")
    actual = {str(path.relative_to(raw)) for path in raw.rglob("*") if path.is_file()}
    assert actual == expected, (actual - expected, expected - actual)
    assert is_hex((raw / "commit.txt").read_text().strip(), 40)
    assert is_hex((raw / "tree.txt").read_text().strip(), 40)
    environment = (raw / "environment.txt").read_text()
    assert "Swift version" in environment and "Xcode" in environment
    for phase in ("before", "after"):
        assert "PASS baseline" in (raw / f"source-guard-{phase}.txt").read_text()
    assert json.loads((raw / "limits.json").read_text()) == LIMITS
    assert "C100 NOT_RUN" in (raw / "scope.txt").read_text()
    validate_study_input_hashes(raw / "study-input-sha256.txt", compare_current=False)
    sources = json.loads((raw / "study-source.json").read_text())
    assert set(sources) == {"actual", "temporary", "changed", "added"}
    assert len(sources["actual"]) == 24 and len(sources["temporary"]) == 25
    assert sources["changed"] == ["SwiftProbe/Main.swift"]
    assert sources["added"] == ["SwiftProbe/SealedWALMicro.swift"]

    rows = []
    signatures = []
    for mode in MODES:
        build = (raw / f"build-{mode}.txt").read_text()
        assert "Build complete!" in build
        stderr = (raw / f"run-{mode}.stderr.txt").read_text()
        assert not stderr, (mode, stderr)
        output = raw / f"run-{mode}.json"
        assert 0 < output.stat().st_size < 2 * 1024 * 1024
        row = json.loads(output.read_text())
        signatures.append(validate_row(row))
        rows.append({"mode": mode, "file": output.name, "sha256": sha(output)})
        scratch = json.loads((raw / f"scratch-{mode}.json").read_text())
        assert set(scratch) == {"mode", "allocatedBytes", "maximumBytes"}
        assert scratch["mode"] == mode
        assert scratch["maximumBytes"] == LIMITS["scratchAllocatedBytesMaximumPerMode"]
        assert type(scratch["allocatedBytes"]) is int
        assert 0 < scratch["allocatedBytes"] <= scratch["maximumBytes"]
    assert len({signature["pairedFinalRoot"] for signature in signatures}) == 1
    assert len({signature["pairedFinalValue"] for signature in signatures}) == 1
    assert all(signature["corruptionCases"] == 21 for signature in signatures)
    assert all(signature["crashPhases"] == 11 for signature in signatures)

    report = {
        "status": "diagnostic-partial",
        "acceptance": False,
        "decision": DECISION,
        "integrationDecision": INTEGRATION_DECISION,
        "integrationEligible": False,
        "modes": rows,
        "runtimeSourceFiles": 24,
        "runtimeInputs": 42,
        "actualRuntimeInputsUnchanged": True,
        "H1M": "NOT_RUN", "C5": "NOT_RUN", "C100": "NOT_RUN",
        "safeToRunH1M": False, "safeToRunC": False,
        "compactionPayloadBuild": "NOT_IMPLEMENTED",
        "compactionPublication": "NOT_IMPLEMENTED",
        "atomicCAS": "NOT_IMPLEMENTED",
        "durableCURRENT": "NOT_IMPLEMENTED",
        "cleanRollbackAuthority": "EXPECTED_KNOWN_GAP",
        "requestID": "NOT_IMPLEMENTED",
        "idempotentStatusQuery": "NOT_IMPLEMENTED",
        "fixedMetadataPools": "NOT_IMPLEMENTED",
        "syscallLevelFaultInjection": "NOT_IMPLEMENTED",
        "crossProcessOwnerLock": "NOT_IMPLEMENTED",
        "physicalPowerLoss": "NOT_TESTED",
        "scope": "Bounded disposable scalar/root protocol diagnostic only; no A/B/K/C, H1M, runtime integration, product, UI, IPA, device, or production durability acceptance.",
    }
    reject_true_acceptance(report)
    if expect_summary:
        assert json.loads((raw / "SEALED-WAL-MICRO-STUDY.json").read_text()) == report
    if expect_manifest:
        recorded = json.loads((raw / "RAW-MANIFEST.json").read_text())
        assert set(recorded) == {"files"}
        evidence = {str(path.relative_to(raw)): sha(path)
                    for path in sorted(raw.rglob("*"))
                    if path.is_file() and path.name != "RAW-MANIFEST.json"}
        assert recorded["files"] == evidence
    return report


def safe_extract(archive, destination):
    assert archive.stat().st_size <= 256 * 1024 * 1024
    with ZipFile(archive) as zipped:
        entries = zipped.infolist()
        assert 0 < len(entries) < 128
        assert sum(item.file_size for item in entries) <= 256 * 1024 * 1024
        seen = {}
        files = set()
        for item in entries:
            path = PurePosixPath(item.filename)
            assert item.filename and "\\" not in item.filename
            assert not path.is_absolute() and ".." not in path.parts
            parts = tuple(part for part in path.parts if part not in ("", "."))
            assert parts
            normalized = tuple(unicodedata.normalize("NFC", part).casefold()
                               for part in parts)
            assert normalized not in seen, (seen.get(normalized), item.filename)
            assert all(normalized[:index] not in files
                       for index in range(1, len(normalized)))
            if not item.is_dir():
                assert not any(len(other) > len(normalized) and
                               other[:len(normalized)] == normalized for other in seen)
                files.add(normalized)
            seen[normalized] = item.filename
            mode = (item.external_attr >> 16) & 0o170000
            assert mode != stat.S_IFLNK
        zipped.extractall(destination)


def verify_reproducible_sources(raw):
    inputs = json.loads((raw / "runtime-inputs.json").read_text())
    assert inputs == manifest() and len(inputs["paths"]) == 42
    validate_study_input_hashes(raw / "study-input-sha256.txt", compare_current=True)

    recorded = json.loads((raw / "study-source.json").read_text())
    actual = ROOT / "Experiments/R005Swift/Sources"
    with tempfile.TemporaryDirectory(prefix="nxr-sealed-source-") as temporary:
        package = Path(temporary) / ".sealed-wal-study/current"
        package.mkdir(parents=True)
        shutil.copyfile(ROOT / "Experiments/R005Swift/Package.swift",
                        package / "Package.swift")
        shutil.copytree(actual, package / "Sources")
        subprocess.run([
            sys.executable, "-B", str(HERE / "prepare-sealed-wal-micro.py"),
            str(package),
        ], check=True)
        actual_files = {str(path.relative_to(actual)): sha(path)
                        for path in sorted(actual.rglob("*")) if path.is_file()}
        disposable = package / "Sources"
        temporary_files = {str(path.relative_to(disposable)): sha(path)
                           for path in sorted(disposable.rglob("*")) if path.is_file()}
    assert recorded == {
        "actual": actual_files,
        "temporary": temporary_files,
        "changed": ["SwiftProbe/Main.swift"],
        "added": ["SwiftProbe/SealedWALMicro.swift"],
    }
    assert len(actual_files) == 24 and len(temporary_files) == 25
    assert set(temporary_files) == set(actual_files) | {"SwiftProbe/SealedWALMicro.swift"}
    changed = [name for name in actual_files
               if actual_files[name] != temporary_files[name]]
    assert changed == ["SwiftProbe/Main.swift"]
    for name, digest in actual_files.items():
        assert inputs["paths"]["Experiments/R005Swift/Sources/" + name] == digest


def raw_command(args):
    raw = args.directory.resolve()
    report = validate_raw(raw, expect_summary=False, expect_manifest=False)
    (raw / "SEALED-WAL-MICRO-STUDY.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "status": report["status"], "decision": report["decision"],
        "integrationDecision": report["integrationDecision"],
        "modes": [row["mode"] for row in report["modes"]],
        "H1M": report["H1M"], "C100": report["C100"],
    }, indent=2))


def artifact_command(args):
    assert is_hex(args.source, 40) and is_hex(args.tree, 40)
    assert is_hex(args.sha256, 64) and sha(args.archive) == args.sha256
    with tempfile.TemporaryDirectory(prefix="nxr-sealed-artifact-") as temporary:
        raw = Path(temporary) / "raw"
        safe_extract(args.archive, raw)
        assert (raw / "commit.txt").read_text().strip() == args.source
        assert (raw / "tree.txt").read_text().strip() == args.tree
        report = validate_raw(raw, expect_summary=True, expect_manifest=True)
        verify_reproducible_sources(raw)
        proof = {
            **report,
            "source": args.source,
            "tree": args.tree,
            "run": args.run,
            "artifact": args.artifact,
            "zipSHA256": args.sha256,
            "artifactEvidenceSHA256": json.loads(
                (raw / "RAW-MANIFEST.json").read_text())["files"],
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(proof, indent=2) + "\n")
    shutil.copyfile(args.archive,
                    args.output.with_name(f"{args.run}-r005-sealed-wal-micro.zip"))
    print(json.dumps({
        "status": proof["status"], "decision": proof["decision"],
        "integrationDecision": proof["integrationDecision"],
        "source": proof["source"], "run": proof["run"],
        "H1M": proof["H1M"], "C100": proof["C100"],
    }, indent=2))


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    raw = commands.add_parser("raw")
    raw.add_argument("directory", type=Path)
    raw.set_defaults(function=raw_command)
    artifact = commands.add_parser("artifact")
    artifact.add_argument("archive", type=Path)
    artifact.add_argument("--source", required=True)
    artifact.add_argument("--tree", required=True)
    artifact.add_argument("--run", required=True)
    artifact.add_argument("--artifact", required=True)
    artifact.add_argument("--sha256", required=True)
    artifact.add_argument("--output", required=True, type=Path)
    artifact.set_defaults(function=artifact_command)
    args = parser.parse_args()
    args.function(args)


if __name__ == "__main__":
    main()
