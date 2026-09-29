# NEXORA — Project Continuity

**Status:** NXR-0002 core foundation implemented and macOS-CI verified
**Official repository:** `bdr-design/NEXORA`
**Default branch:** `main`
**Foundation work branch:** `foundation/clean-core`
**Independent root commit:** `ec00fd8c025199b4151796e8a9cabe2c11f2abcd`
**Technical ancestry:** none; no technical implementation is inherited from the previous game.

## Current update
`NXR-0002` — Core Foundation Benchmark — 2026-09-30 — `0.1.0-dev.2` / Build 2.

## Current code state
Implemented:
- Swift 6 package foundation.
- Diagnostics contracts, bounded trace ring, Apple signpost adapter.
- Global generational entity registry.
- Packed sparse↔dense asset benchmark storage.
- Revisioned all-or-reject domain commit.
- Deterministic bounded parallel compute/merge.
- Cross-platform raw benchmark executable.
- Apple XCTest performance metrics.
- GitHub Actions macOS gate.

Not implemented:
- production cross-domain Transaction Coordinator;
- Simulation Clock;
- Event Scheduler;
- Job System production policy;
- persistence/recovery;
- iOS app shell;
- Metal renderer;
- enterprise/business engines;
- real aviation or other industries.

## Latest verified source
Core implementation commit: `2012cfd45f5187ace7641d88d3c973763554f0a9`
Core implementation tree: `3fcb99789084d619cc4662b1e6f5ee4f516b939c`

## CI evidence
Run: `36638640053` — PASS.
Artifact: `11065373863`.
Artifact SHA-256: `062d3c0aae0c8e52fd96b44f4b2e8ca644c7f3603f9998151f4320b3653c102c`.
macOS 100k synthetic p99: compute 0.096 ms, merge 0.004 ms, commit 0.048 ms, end-to-end 0.155 ms.

## Critical limitations
This proves only the current synthetic core path on macOS/Linux. It does not prove 100k full-feature game assets, iPhone thermals, Metal performance, persistence performance or zero allocations.

The current benchmark read snapshot uses Swift Array Copy-on-Write semantics and explicitly releases the snapshot before commit. Before Scheduler integration, benchmark/compare a production read-view strategy (borrowed/leased view or equivalent) so correctness/performance do not depend on fragile lifetime assumptions.

## Next safe action
Do not begin industry gameplay. The next engineering gate is to harden the read-view/lifetime model, implement the minimal production Transaction Coordinator contract, and add iPhone-capable app/test harness before Event Scheduler design is accepted.

## Mandatory startup
New sessions must read `AGENTS.md`, this file, `VERSION.json`, `Docs/Updates/NXR-0002-2026-09-30-core-foundation-benchmark.md`, the latest Daily log, and verify branch/HEAD before sensitive edits.
