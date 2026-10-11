# NEXORA R005 / 11 Oct 2026 — atomic reschedule micro, NOT ENGINE ACCEPTANCE

## Proven permitted source and boundaries
- Repository `bdr-design/NEXORA`, isolated branch `experiment/r005-atomic-reschedule-20261011`.
- Parent of candidate branch `aee6949e2fb7b14e9c1a49d96df580f57478b3fb` on the permitted R001→R005 line.
- Original `main` independently verified at `38ce39cf9322f47e4def5f6eddb425c5a66ea7f9`.
- Excluded source branches and prior game's code, schema, algorithms, implementation, tests and assets not opened, imported, or reused.
- No changes to `Sources/`, `Tests/`, `Checks/`, original R005 24 hot source files, or 42 pinned proof inputs.

## Why this specific experiment exists
`Experiments/R005Swift/Sources/SwiftProbe/Stage005CHybridRunner.swift:9-25`
loops all assets in one logical reschedule command, checks operation overflow
**after** invoking schedule for each asset; `Hybrid.swift:609-622` inserts
a wheel node before asset fields. A predictable rejection after any of those
steps may leave a partially modified volatile world before the WAL
`appendRescheduleAll` call, unless the execution is terminated/recovered.
A naive 1000-item chunk loop would not fix atomicity or durable replay.

## Experiment performed locally, on new code only
A Swift 6 serial-owner **model**, built independently under
`Experiments/R005AtomicReschedule`, validates each row before staging,
reuses fixed event slots, gates all external reads/actions until its mock
journal commit, and transitions to recovery-required on staged exceptions
or ambiguous journal results. It tests idempotent status query and replay
to a *new model world*. It does not have a physical WAL or FS semantics.
- Environment: Linux x86_64, Swift 6.2.1, no Apple/iPhone metrics.
- `swift test -Xswiftc -warnings-as-errors`: 10/10 PASS.
- `swift test -c release -Xswiftc -warnings-as-errors`: 10/10 PASS.
- `swift test --sanitize=thread -Xswiftc -warnings-as-errors`: 10/10 PASS.
- TSan in a serial mock **does not prove** real multithread safety.

## Remaining independent blockers
- At 1M, two phases need 2,000,000 logical visits; at 2,000 calls the
  theoretical minimum is **1000 visits/call**, excluding WAL/fsync, actual
  wheel sorting, writer contention, gameplay, frames, memory and heat.
- Atomic visibility in a mock is not atomic recovery, WAL durability, or
  reliable snapshot/restore of actual S/H (not integrated, not run).
- Preflight O(N) and the existing live wheel's 1M event slots are not
  automatically bounded by current 100us begin / 1.1ms advance p99 gates.
- Real `schedule` mutates wheel before asset writes: production needs all
  capacities/preconditions proven upfront and no throw after first mutation,
  plus exact persisted tip; model cannot certify that.
- H prepared memory 210,772,320B still violates A and C5 ratio=1.3822529614
  still violates 1.10. No Stage A/B/K/C/device acceptance changed.

## Evidence policy
The Apple CI is distinct, isolated, and run on a new micro branch; its results
must be checked before saying Mac PASS. Keep all historical FAILED results.
No main merge, no IPA, no source-changed result attribution or model
quality claim. External agent review at max reasoning (tooling workflow)
received HTTP 429 and no answer; do not invent that critique.

## Verified Apple CI proof — 2026-10-11

- Code-proven source commit: `415f053ba6104cf78ee07cdb0afd7908cfb4e92b`; source tree `0a2f048cd08079be3ef016a48f1bd186218f1753`.
- Apple workflow `38140216852`: **SUCCESS**, job `114472380605`; macOS 15.7.9 (arm64), Xcode 16.4, Swift 6.1.2.
- Independent Swift 6 mock unit suite: Debug 10/10 PASS; Release 10/10 PASS; TSan 10/10 PASS. Tests run serially; TSan is not proof of real engine concurrency.
- Artifact ID `11703265647`, ZIP SHA-256 `ada727087f04e4e195a79bd70dd2a42af93d84d39f3ce7a9be146f1595937cf4`; downloaded and SHA recomputed byte-for-byte, commit/tree and exact three raw test logs independently inspected. ZIP GitHub digest matches.
- GitHub comparison from permitted R005 HEAD lists exactly seven paths (new micro, workflow, daily document and continuity), none in the original production-side `Sources/`, `Tests/`, or `Checks/`. Four micro blobs match locally tested sources by SHA.
- The explicit companion review issue is https://github.com/bdr-design/NEXORA/issues/1; no external-model review exists (Laguna max review run `38139581248` BLOCKED 429). No code changes have been integrated into R005.
- Classification remains: `ISOLATED_MICRO_PROTOCOL_PASS`, `NO_GO_ENGINE_INTEGRATION`, `C_OPEN_S_AND_H`, `DEVICE_NOT_TESTED`, `NO_IPA`. The failed R005 C and memory numbers are untouched.


## Independent red-team correction — 11 October 2026 (Apple CI pending)

A newly written regression was first run on the published 10-test mock and
**FAILED**: two worlds with equal `count` but unequal scheduled operations
could claim the same request's journal receipt without proving world state.
The test had a deliberate `XCTAssertThrowsError` which correctly exposed
that no error was thrown.

A limited corrective model change now:
- binds mock journal receipts to a rolling state fingerprint, and checks the
  published world marker on idempotent receipt queries;
- prevents an unqualified fresh-empty recovery from silently replacing a
  nonempty pretransaction world; explicit caller-supplied baseline identity is
  required, and unsupported recovery fails closed;
- adds regression coverage of foreign-world receipt substitution, nonempty/
  mismatched baseline, and long-running read starvation.

**Limits:** 64-bit noncryptographic marker and caller-supplied baseline are
not a durable/secure root or filesystem proof. In fact the read-starvation
test demonstrates that merely splitting work across ticks is not production
viable. A real design needs durable baseline, immutable reader views and
source-bound state ownership, while still meeting unchanged R005 A/B/C gates.

Local Swift 6.2.1 Linux Debug/Release/TSan **14/14** each; Apple CI still
`NOT_VERIFIED` for this new commit. Original model's 10/10 Apple evidence
stays tied to `415f053b` and must not be reused as new source evidence.
`Sources/`, `Tests/`, `Checks/` and the original R005 engine files are
still untouched. No external Laguna review was received (429).

## Refined exact theoretical 2,000-call bound (mock only)

The first-order two-pass bound `2N/2000 = 1000` visits/call is
**not sufficient** in the micro: each phase rounds up separately and
mock journal publication consumes one additional call. For N=1,000,000,
the exact modeled call count is
`2 * ceil(1,000,000 / budget) + 1`.
At budgets 1000 and 1001 this is **2001 calls** (fails a 2000-call
comparison); budget 1002 yields **1999 calls**, and budget 1024 gives
**1955 calls**. These are analytical call counts, *not* 1M Apple
measurements, production scheduler parity, or official Stage C timings.
A dedicated assertion was run locally: Debug/Release/TSan 14/14 each.
New source-bound Apple CI must be checked before Apple PASS is asserted.

## Exact Apple source-bound follow-up / 2026-10-11

1. Red-team corrected source commit `63fbee880b2294112abf99710976a74b5f63bd22`:
   [GitHub Apple CI 38145934383](https://github.com/bdr-design/NEXORA/actions/runs/38145934383) **SUCCESS**.
   14/14 named Debug, 14/14 Release, 14/14 TSan PASS on Apple Swift 6.1.2,
   Xcode 16.4/macOS 15.7.9 arm64. Artifact 11705201013, independently
   downloaded ZIP SHA-256 `66ed17477f1eb556b21344ec1e354861276482984d40d20ca8a3c9e53f3be30e`.
   Code/test remote blob SHA match the locally compiled files:
   `30dc8a83669d451c1a89024f0d2c257ef03e463b` and
   `5683a363bab9b41b96374afed798c26d47fc6892`.

2. Further source-limited arithmetic assertion commit
   `bb131774a9498275718818bf747f6af24fb82a09`, tree
   `e1e06ea0c8fc8a27bccd049cdd33f1530c17af31`:
   [Apple CI 38146201687](https://github.com/bdr-design/NEXORA/actions/runs/38146201687) **SUCCESS**.
   Debug 14/14, Release 14/14, TSan 14/14 PASS, all steps complete. Artifact
   `11704457735`, GitHub digest and independently downloaded ZIP SHA-256
   `6abe1dfd5588637b6b5ca01fda76312a8415a07edbcde15e4a141732be99ddea`.
   ZIP internal `commit.txt`/`tree.txt` match exact source; debug/release/tsan
   logs each confirm 14 named tests, 0 failures.

3. An independent strongest-allowed external Laguna Max review was requested
   using *public product/performance evidence only*. One controlled replay of
   [workflow 38139581248](https://github.com/bdr-design/NEXORA/actions/runs/38139581248)
   failed `PROVIDER_HTTP_429` again (attempt 3). Its 44 offline safety tests and
   free catalog check passed, but **no model response** was produced. Neither
   its max-request setting nor smoke-test connectivity is an independent review.
   No smaller model substituted; no secrets or code from the previous game sent.

### Narrow conclusion — do NOT turn a passing micro into an engine upgrade

The **cross-world receipt substitution** was a real fail in the isolated model,
then was prevented in the revised mock, evidenced by a regression test. However
the mock FNV-64 marker is not a durable, cryptographic state root. The recovery
method still only handles a fresh empty base and requires caller-supplied
expected-base identity. It does **not** reconstruct a prior nonempty state
or verify it after a physical crash. These boundaries must remain fail-closed.

The read-starvation test is explicitly **negative evidence**: all business
reads are blocked throughout two passes plus mock publication, even when
per-call work is bounded. This is not a playable-world visibility design.
Source changes to a real `HybridWorld`, `SwiftWorld`, scheduler, WAL, save
contract, or financial state have NOT occurred and are not justified by this
experiment.

**Current integration decision: NO_GO.** Original R005 H memory
`210,772,320B`, H1M/C5 overhead `1.3822529614`, and all other C failures
remain unchanged. No Stage A/B/K/C proof, release-ready gameplay, IPA or iPhone
certificate is claimed. Before another candidate, independently prove
nonblocking published views (not second world), stable durable request ID and
manifest authority, real recovery from nonempty base, source-bound memory and
latency budgets. Keep main unmodified and preserve the fixed `<=1.10` gate.
