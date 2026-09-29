# NXR-0002 — Core Foundation Benchmark

Date: 2026-09-30
Version: 0.1.0-dev.2
Build: 2
Branch: `foundation/clean-core`
Core implementation commit: `2012cfd45f5187ace7641d88d3c973763554f0a9`
Core implementation tree: `3fcb99789084d619cc4662b1e6f5ee4f516b939c`

## Purpose
Turn NEXORA from architecture-only documentation into a measured executable core without crossing into Scheduler or gameplay implementation.

## Implemented
- Swift tools 6.0 package in Swift 6 language mode.
- iOS 18 / macOS 15 deployment floor for the foundation package.
- Diagnostics abstraction independent from Apple logging implementation.
- Bounded `TraceRingBuffer` using Swift Synchronization `Mutex`.
- Apple `OSSignposter` event adapter.
- Stable `EntityID(slot,generation)`.
- Global entity registry with stale-handle rejection and generation-safe slot reuse.
- Packed asset test domain with sparse↔dense mapping and SoA columns.
- O(1) swap-and-pop component removal with mapping repair.
- Domain revisions.
- Full validation of every delta before first mutation.
- Short synchronous non-suspending commit phase.
- Bounded TaskGroup workers; no actor/task per asset.
- Deterministic merge by worker index rather than task completion order.
- Reused per-worker/merged delta buffers.
- Raw benchmark JSON output and p50/p95/p99/max.
- macOS GitHub Actions gate and benchmark artifact upload.

## Correctness tests
Local Release: 8/8 PASS with compiler warnings treated as errors.
Local Thread Sanitizer: 8/8 PASS with no reported data race.
GitHub macOS Release: 9 tests PASS.

Covered:
- 100,000 unique live entity handles;
- destroy/recycle generation invalidation;
- stale-handle rejection;
- packed swap-and-pop mapping repair;
- generation collision rejection in occupied domain slot;
- all-or-reject commit when a delta is invalid;
- revision conflict rejection without mutation;
- deterministic parallel output ordering;
- diagnostic ring-buffer wrap order;
- Apple XCTest Clock/CPU/Memory performance metric path.

## Local Linux preflight
Environment: Swift 6.2.1, x86_64 Linux.
100k entities, 10k deltas/tick, 5 workers, 20 warmup + 500 measured iterations, diagnostics enabled:
- Compute: p99 0.195 ms
- Merge: p99 0.009 ms
- Commit: p99 0.084 ms
- End-to-end: p99 0.302 ms
- RSS: 15.99 MiB → 16.14 MiB

Worker sweep also demonstrated that higher worker count is not automatically faster; worker count remains benchmark-selected.

## macOS GitHub Actions preflight
Run: `36638640053`
Runner toolchain: Swift 6.1.2; target arm64-apple-macosx15.0.
100k entities, 10k deltas/tick, 3 workers, 20 warmup + 500 measured iterations:
- Compute p50/p95/p99/max: 0.051 / 0.074 / 0.096 / 0.184 ms
- Merge p50/p95/p99/max: 0.004 / 0.004 / 0.004 / 0.007 ms
- Commit p50/p95/p99/max: 0.040 / 0.041 / 0.048 / 0.058 ms
- End-to-end p50/p95/p99/max: 0.106 / 0.133 / 0.155 / 0.242 ms
- RSS: 12.70 MiB → 12.72 MiB
Artifact ID: `11065373863`
Artifact ZIP SHA-256: `062d3c0aae0c8e52fd96b44f4b2e8ca644c7f3603f9998151f4320b3653c102c`

## Apple XCTest metric note
The 20k XCTest metric ran successfully. Peak physical memory averaged about 15073 kB during those CI iterations. The measured block is extremely short, so CPU/clock relative deviation is high and is not treated as a stable performance baseline yet.

## What this does NOT prove
- It is not 100k real game assets.
- No Finance, HR, route, invoice, payroll, maintenance, persistence or rendering work is included.
- No iPhone thermal soak was run.
- No Instruments Allocations proof exists yet; “zero allocation hot loop” is NOT claimed.
- The production cross-domain Transaction Coordinator is not implemented.
- Event Scheduler is intentionally not implemented.

## Known design issue to resolve before Scheduler
The benchmark read snapshot uses Swift Array CoW sharing and explicitly drops its references before commit so authoritative arrays can regain unique ownership. This avoids the known benchmark trap but is not yet the final production read-view contract. A borrowed/leased/double-buffer alternative must be benchmarked before this boundary is frozen.

## Decision
NXR-0002 passes the synthetic core preflight and is strong enough to continue core hardening. It is not authorization to build industry gameplay yet.
