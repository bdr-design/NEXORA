# NXR-0003 — Core Hardening

Date: 2026-09-30
Version: 0.1.0-dev.3
Build: 3
Branch: `foundation/clean-core`
Verified implementation commit: `1b0bfe7ce49f70a11d5ccb5c6aba731352902b43`
Verified implementation tree: `7e0ad5d3524e09f08908b8669c31d8fd1217c381`

## Purpose
Harden the NXR-0002 compute/commit foundation before Scheduler work by removing the fragile full-array CoW snapshot boundary, adding a minimal coordinated in-memory transaction contract, extending diagnostics, and proving iOS compilation and race-safety in CI.

## Read-view change
The former `AssetReadSnapshot` copied Swift Array references from authoritative packed storage. Even though the benchmark released the snapshot before commit, that design relied on CoW lifetime behavior and could move an O(N) copy into a mutation path if a snapshot survived.

NXR-0003 replaces it with `AssetReadBatch`:
- caller owns the batch buffers;
- buffers are pre-reserved and reused in the raw benchmark;
- the domain gathers only selected rows;
- authoritative domain arrays are never aliased into compute;
- gather latency is measured separately;
- future Scheduler work will replace stride selection with due-event/entity selection.

This is an explicit-copy design, not a claim of zero-copy. It intentionally pays bounded O(selected-work) gathering cost to remove hidden O(all-state) CoW risk.

## Coordinated transaction contract
Added `TransactionGate`, `TransactionStep`, and `TransactionCoordinator`.

Rules:
1. heavy computation occurs before the gate;
2. every participating domain shares the same gate;
3. duplicate participant steps are rejected;
4. all steps validate before the first authoritative mutation;
5. prepared apply sections do not suspend;
6. public participating-domain reads/mutations use the gate, so a reader cannot observe half of an in-memory coordinated commit;
7. durable crash atomicity is NOT claimed — Persistence/WAL must provide that later.

The current coordinator intentionally rejects multiple independent steps for the same domain; callers must combine same-domain deltas before coordination.

## Diagnostics
Added:
- `TraceDomain.transactionCoordinator`;
- `TraceOperation.readGather`;
- `TraceOperation.transactionPrepare`;
- `TraceOperation.transactionCommit`;
- coordinator rejection result codes.

The coordinator records prepare and commit timing outside the critical tracing path, preserving parent-child trace causality.

## CI history
Two failures were treated as design/test feedback:
1. the first NXR-0003 push failed because the benchmark still used the removed snapshot API;
2. the next push failed because Swift 6 correctly rejected a mutable `AssetReadBatch` captured across a sending XCTest `Task`.

Both were corrected without `@unchecked Sendable`, compiler suppression, or reverting the architecture.

## Final CI
Run: `36641949755`
Conclusion: PASS
Toolchain: Apple Swift 6.1.2 / Xcode 16.4
iOS compile target: arm64-apple-ios18.0, iPhoneOS 18.5 SDK
Release tests: 14/14 PASS
Thread Sanitizer tests: 14/14 PASS
iOS Release compile: PASS
Artifact ID: `11066353467`
Artifact digest: `sha256:b88aa31bf39ee2268d7fae79fe6dea34fd8065d4512abf8b7ca480a39a07c1d2`

## Final synthetic benchmark
500 measured iterations after warmup; diagnostics enabled.

| Stored | Selected/tick | Gather p99 ms | Compute p99 ms | Merge p99 ms | Commit p99 ms | End-to-end p99 ms | End-to-end max ms | RSS before/after MiB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 100 | 0.002 | 0.027 | 0.000 | 0.002 | 0.457 | 4.818 | 3.89 / 4.16 |
| 5,000 | 500 | 0.010 | 0.065 | 0.001 | 0.011 | 0.531 | 4.088 | 5.94 / 5.94 |
| 20,000 | 2,000 | 0.085 | 0.044 | 0.003 | 0.069 | 0.720 | 5.827 | 6.75 / 6.78 |
| 50,000 | 5,000 | 0.143 | 0.094 | 0.007 | 0.080 | 0.514 | 1.327 | 9.28 / 9.28 |
| 100,000 | 10,000 | 0.291 | 0.129 | 0.022 | 0.234 | 0.661 | 0.930 | 14.91 / 14.91 |

### Interpretation
The 100k case is the most relevant scale preflight and remained below the provisional 3 ms core-tick p99 target. Small-size max spikes show why p50/p95/p99/max and raw samples remain mandatory; a low median is not enough.

NXR-0003 is intentionally slower than the narrow NXR-0002 benchmark in some measurements because read gathering is now explicit, safe and included rather than relying on shared authoritative Array storage.

## Not proven
- 100k full gameplay assets;
- zero-allocation hot-loop proof with Instruments Allocations;
- real iPhone execution/thermal soak;
- persistence/WAL crash atomicity;
- Event Scheduler performance/cancellation;
- Metal map/rendering;
- Finance/HR/Aviation gameplay.

## Exit decision
NXR-0003 passes the pre-Scheduler core-hardening gate.

The next update may begin Scheduler/Simulation Clock design and benchmark work, but only with deterministic ordering, cancel/reschedule, backpressure, scheduler intents inside transaction plans, and replay-hash testing.
