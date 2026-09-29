# NEXORA — Project Continuity

**Status:** NXR-0003 core hardening implemented and CI verified
**Official repository:** `bdr-design/NEXORA`
**Default branch:** `main`
**Foundation work branch:** `foundation/clean-core`
**Independent root commit:** `ec00fd8c025199b4151796e8a9cabe2c11f2abcd`
**Technical ancestry:** none; no technical implementation is inherited from the previous game.

## Current update
`NXR-0003` — Core Hardening — 2026-09-30 — `0.1.0-dev.3` / Build 3.

## Verified implementation source
Commit: `1b0bfe7ce49f70a11d5ccb5c6aba731352902b43`
Tree: `7e0ad5d3524e09f08908b8669c31d8fd1217c381`

## Implemented
- Swift 6 package foundation.
- Global generational Entity Registry.
- Packed sparse↔dense benchmark domain storage.
- Explicit detached selected-row `AssetReadBatch`; no authoritative Array snapshot aliasing in the core benchmark path.
- Deterministic bounded parallel compute/merge.
- Revisioned all-or-reject single-domain commit.
- Shared TransactionGate and minimal multi-domain TransactionCoordinator.
- Prepare-all-before-first-mutation behavior for coordinated in-memory transactions.
- Bounded diagnostics ring + Apple signposts.
- Read-gather and coordinator prepare/commit tracing.
- Raw benchmark harness with gather/compute/merge/commit/end-to-end percentiles.
- CI warnings-as-errors, Thread Sanitizer, iOS arm64 compile gate, benchmark artifact.

## Final NXR-0003 CI
Run: `36641949755` — PASS
Release: 14/14 PASS
TSan: 14/14 PASS
iOS Release compile: PASS
Artifact: `11066353467`
Artifact SHA-256: `b88aa31bf39ee2268d7fae79fe6dea34fd8065d4512abf8b7ca480a39a07c1d2`

100k stored / 10k selected synthetic p99:
- gather 0.291 ms
- compute 0.129 ms
- merge 0.022 ms
- commit 0.234 ms
- end-to-end 0.661 ms
- end-to-end max 0.930 ms
- RSS 14.91 → 14.91 MiB

## Not implemented / not proven
- Simulation Clock.
- Event Scheduler.
- scheduler cancel/reschedule/backpressure/replay.
- durable Persistence/WAL and crash atomicity.
- real iOS app runtime harness and on-device thermal soak.
- Metal renderer.
- enterprise/business engines.
- aviation vertical slice.
- 100k full-game claim.
- Instruments allocation-free proof.

## Next safe action
Begin the next update with Scheduler/Simulation Clock architecture and benchmark only after re-reading the current contracts.

Mandatory Scheduler requirements already identified:
- integer simulation ticks;
- deterministic total order;
- stable generational EventHandle;
- cancel/reschedule without linear search;
- same-tick phase law;
- transaction-integrated scheduler intents;
- 30x backpressure without dropping/changing simulation results;
- replay hash;
- benchmark Heap baseline before considering Hybrid/Timing Wheel.

## Mandatory startup
Read `AGENTS.md`, this file, `VERSION.json`, `Docs/Updates/NXR-0003-2026-09-30-core-hardening.md`, the latest Daily log, and verify branch/HEAD before sensitive edits.
