# Verified Apple gate — NXR-R003

Date: 2026-09-30. Supersedes submission-time APPLE_GATES_PENDING notes.
Scope: bounded in-memory aircraft timed trips, NOT full gameplay/device approval.

Tested commit: 50a9fb82db7ea13f636b5c4b3e4f104d8bb7b113.
Tested tree: 604fef333991e71bc191abd17a19bc93afbaf08d.
CI run: 36655778966. Job: 109699695428. Conclusion: success.
Job completed: 2026-09-30 01:37:00 UTC / 04:37:00 Asia/Riyadh.
Apple Swift 6.1.2, arm64-apple-macosx15.0; Xcode 16.4 (16F6).

## Evidence downloaded, read and independently checked

Artifact ID11072940842, name nexora-r003-evidence, 396414 bytes.
Downloaded file: NEXORA_R003_Apple_Evidence.zip.
Recalculated SHA-256 matched GitHub's reported digest:
03141936e8e14948841424a6b16b10c850eb4ffd84a685beb9baed97e865885d

The artifact's source-commit.txt and source-tree.txt matched the exact source above.
All archived logs and raw samples were parsed, not inferred from a green label:
- Debug: 86 named tests PASS; test-summary time 5.331 seconds.
- Release: 86 named tests PASS; 2.023 seconds.
- TSan: 86 named tests PASS; 16.653 seconds; no TSan warning/error reported.
- Three valid external clients compile; 18 required misuse rejections (3+8+7).
- Eight required invariant fail-stop subprocesses, Debug and Release combined.
- NexoraIdentity, NexoraObservability, NexoraAviation and NexoraSimulation all
  compile for generic iOS Release. This is not real-device execution.
- Both earlier fixtures plus new timed-trip samples pass; five trip scales,
  three warmups and 30 measured repetitions each. Every expected arrival counted.

The separate incomplete local SwiftPM TSan invocation remains NOT_CONFIRMED; the
successful Apple run does not rewrite that local command as a pass. Full details
and corrected test-harness failures are retained in Docs/Updates/NXR-R003.md.

## Complete source export verified, not only selected code

Nested archive: NEXORA_R003_SOURCE.zip, 67 regular files, no Git history.
Its SHA-256 was recalculated and matched the workflow's source digest:
784fe213ecacf6b65a2284c8d18a5da3338e5177e910194747b43d722b655b90
The archive's commit comment was the exact tested commit. After safe extraction,
Git blobs, executable modes and directory trees were recomputed. The FULL root
matched 604fef333991e71bc191abd17a19bc93afbaf08d exactly, including documentation
and workflow. Selected subtrees also matched the pre-submission local workspace:
Sources ca904809dce06a62b9f8c5b1e9a657ebfcc61c2f
Tests c9a27bbb025a03aca0e4b1ef8524378fcd16eb2a
Checks 9edd1ccc9be83c2187a44d512eee85b663d708f4
Package.swift 9f334c443c0e16c989eda7558adbbc0d4e18e502

This is the permitted new source tree, not an archive of excluded implementations.
Later evidence-only documentation commits can change the root/HEAD; never confuse
them with the exact tested code or this exact exported source archive.

## Apple timed-trip samples — milliseconds

Budget: 256 arrivals/advance, with initialization/audits/export outside these
phases. Registration/departure/advance-all values are independent 30-run medians.
Largest advance is the maximum observed individual batch across all those runs,
NOT a certified p99 or a hard latency ceiling.

| Aircraft | Register all | Depart all | Advance all | Batches per run | Largest observed advance |
|---|---:|---:|---:|---:|---:|
| 1,000 | 0.053562 | 0.136104 | 0.216437 | 4 | 0.120667 |
| 5,000 | 0.275667 | 0.656687 | 1.1733335 | 20 | 0.372250 |
| 20,000 | 1.1051665 | 2.6511665 | 5.3831875 | 79 | 1.680583 |
| 50,000 | 2.787521 | 6.7656455 | 15.364937 | 196 | 1.911458 |
| 100,000 | 5.531125 | 13.0590415 | 32.954208 | 391 | 4.736583 |

All-record timing is not one frame. The core caller still must schedule batches
away from UI-critical work and honor blocked/budget results. R002 store timing is
a different workload, not a speedup baseline. No real routes, finance, payroll,
maintenance, deliveries, database, UI/map, FPS, physical memory, energy or heat is
in this fixture. The user's 20,000 COMPLETE asset acceptance and 100,000 design
goal are not certified by these results.

## Verification boundary

This passes the R003 core gate only. It is not an absence-of-defects proof or a
complete game release. The next financial extension must preflight its effects
before committing arrivals, not use fallible after-the-fact result callbacks.
Persistent identity and durable transactions remain separate required stages.
