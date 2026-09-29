# NXR-0003 Adversarial Re-Review — 2026-09-30

Status: **BLOCKING FINDINGS CONFIRMED**

Audit branch: `audit/nxr-0003-20260930`

## Why this audit exists
After NXR-0003 initially passed its normal Release/TSan/iOS/benchmark gates, the implementation was reviewed again with tests aimed at contracts that the original suite did not exercise.

## Finding A — Global entity lifetime is not enforced by AssetDomain
Confirmed by CI run `36642880284`.

Scenario:
1. create an entity through the global `EntityRegistry`;
2. attach it to `AssetDomain`;
3. destroy it in the global registry;
4. attempt an AssetDomain commit using the now-dead EntityID.

Observed:
`AssetDomain.commit` returned `committed(newRevision: 2, applied: 1)`.

Required:
a globally dead EntityID must not remain writable.

Root cause:
`EntityRegistry` has its own lock/lifecycle boundary and `AssetDomain` validates only its local sparse↔dense storage. Registry liveness is not part of domain validation or the shared transaction gate.

## Finding B — A domain accepts a forged / never-created EntityID
Confirmed by CI run `36642880284`.

`AssetDomain.attach` accepted `EntityID(slot: 999, generation: 0)` even though the global registry had never created it.

Root cause:
attach validates local slot occupancy but not global EntityRegistry ownership/liveness.

## Finding C — Concurrent reuse of ParallelAssetComputer corrupts logical results
Confirmed by CI run `36643024182`.

Two simultaneous `compute` calls on the same `ParallelAssetComputer`, using different input values, produced mixed/incorrect delta values. The adversarial test reported repeated assertion failures.

Root cause:
`ParallelAssetComputer` is `Sendable` and exposes an async `compute`, but worker buffers and the merged buffer are reusable shared workspace. Mutexes prevent raw data races on each buffer, so TSan can pass, while two overlapping compute invocations can still overwrite each other's logical workspace between fill and merge.

This is a **logical concurrency race**, not necessarily an unsynchronized-memory race.

## Additional architecture risks found by inspection

### Global TransactionGate scalability
All participating public reads/mutations currently acquire the same non-recursive gate. This guarantees a simple visibility boundary but can serialize independent domain reads and commits. It has not been benchmarked under multi-domain contention.

### Non-recursive gate contract
Swift `Mutex` is non-recursive. A future prepared transaction step that accidentally calls a public domain method which reacquires the gate can deadlock/panic depending on platform. Current AssetDomain uses private no-gate methods correctly, but the contract is convention-based rather than structurally enforced.

### Deterministic coordinator order
`TransactionCoordinator` applies steps in caller array order. A stable canonical order is not yet encoded in `TransactionStep`; future callers must not construct step arrays from nondeterministic sources.

### Shallow storage invariant
`PackedAssetStorage.invariantHolds()` verifies column counts only. It does not deeply verify sparse↔dense round-tripping. A separate deep invariant/fuzz test is required outside the hot commit path.

## Decision
NXR-0003 is **reopened**. Scheduler/Simulation Clock implementation is blocked until:
1. Registry lifetime and domain attachment/mutation are one enforceable contract.
2. Concurrent `ParallelAssetComputer` use is either safely isolated or explicitly single-flight with enforced behavior.
3. Multi-domain gate contention is benchmarked and the intended scope of the gate is frozen.
4. Deterministic transaction-step ordering is enforced.
5. Deep sparse↔dense invariants are added to adversarial tests.
6. The original NXR-0003 gates and the new adversarial gates all pass.

The previously recorded performance numbers remain valid for the narrow workload they measured, but they do not override these correctness findings.
