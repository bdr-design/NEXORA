# Core Concurrency & Benchmark Rules

Date adopted: 2026-09-30
Status: Foundation rule

## 1. Entity identity
Use a global stable generational handle, conceptually `slot + generation`. The registry owns alive/dead/recycle state. Domain stores only attach/detach their own components.

## 2. Packed storage
Performance-sensitive domains may use packed SoA/data-oriented storage. Packed storage requires sparse↔dense mapping. Swap-and-pop is allowed only if the mapping for the moved row is updated atomically with the move.

## 3. Concurrency model
Do not create one Actor or Task per asset. Use a bounded number of workers/chunks chosen by measurement, not by assuming active processor count equals the optimal worker count.

Parallel stages are pure/read-only where possible. Authoritative mutation is single-writer per domain.

## 4. Compute then commit
`Read View -> Parallel Compute -> Deterministic Merge -> Validate -> Non-suspending Commit -> Events`

The commit section must be short, synchronous and bounded. No `await` inside it.

## 5. Determinism
TaskGroup completion order is not a simulation ordering contract. Every produced chunk/delta batch carries stable ordering metadata and is merged deterministically.

## 6. Cross-domain transactions
A Finance commit and an Asset commit are not automatically one atomic transaction. Multi-domain invariants require an explicit coordinator/prepare/commit contract with failure behavior defined before implementation.

## 7. Locks
Per-entity locks and high-contention hot-loop locks are prohibited. Lightweight synchronization primitives are not banned categorically; they may be used only when ownership is clear and measurement proves the design is appropriate.

## 8. Snapshot safety
Do not benchmark using a snapshot design that keeps shared Array buffers alive and then mutates the source, because Swift Copy-on-Write can move the copy cost into the measured commit path. Benchmark read views must have explicit lifetime/ownership semantics.

## 9. Allocation rule
“Zero allocation” means zero unexpected heap allocations inside a precisely defined steady-state hot section after setup/preallocation. It does not mean the whole application allocates nothing.

## 10. Benchmark evidence
Scale ladder:
`1k -> 5k -> 20k -> 50k -> 100k`

For each meaningful workload record:
- raw samples;
- p50 / p95 / p99 / max;
- compute time;
- merge time;
- commit time;
- end-to-end tick time;
- CPU;
- physical memory;
- heap allocations in the measured hot section;
- work/delta count;
- invariant failures/stale-handle rejection;
- scheduler/queue depth when available;
- thermal state on real-device certification.

Microbenchmarks and end-to-end XCTest metrics are both required. Fifty iterations alone are not considered strong p99 evidence.

## 11. Bottleneck rule
Do not predeclare memory bandwidth, cache misses, sorting, actor mailboxes, persistence, or any other subsystem as the bottleneck. Record hypotheses, then let Instruments/metrics decide.

## 12. Acceptance before Scheduler
No Scheduler design is considered validated by entity-array memory alone. The core benchmark must first demonstrate correct registry ownership, deterministic compute/merge/commit behavior, stable memory and credible scale measurements.
