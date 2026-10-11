# NEXORA R005 — budgeted reschedule transaction micro (independent)

**Status: RED_TEAM_FIX_LOCAL_14_PASS / NOT_RUNTIME_INTEGRATED / NO_GO_C100.**

This is a self-contained Swift 6 reference-state-machine experiment designed
**exclusively from NEXORA's permitted R005 source and public Swift guidance**.
It contains no code or implementation scheme obtained from the previous game.
It is **not** a new production World, scheduler, snapshot, WAL implementation,
or an iPhone game.

## Source observation and hypothesis

In the permitted R005 snapshot, `Stage005CHybridRunner.swift:9-25` loops over
all `world.count` assets, calls `world.schedule(...)`, increments `operation`
with wraparound, then checks overflow, and emits one WAL `rescheduleAll` frame
only after the loop. `Hybrid.swift:609-622` schedules on the wheel before
writing asset fields. A future capacity failure, old operation, or arithmetic
overflow must not be treated as if the whole million-asset command rolled back.
This observation is source analysis, not an executed production regression test.

The micro explores two bounded phases, preflight and staging, followed by
an explicit journal-acknowledged publication. While the transaction is active,
all external reads and business commands must reject. Staging uses already
allocated event slots; no second full world is constructed. Preflight rejects
predictable invalid inputs before the first write; any exceptional fault after
writing requires process recovery, not a fabricated rollback. Publication
becomes observable only after mock-durable record append and staged completion.

The mock journal proves **logical test semantics only**, not filesystem
persistence or crash safety. The real save format, physical fsync/dirsync,
manifest high-watermark, CAS compaction, cross-process authority, bounded replay,
backpressure, and exact application integration are absent.

## Commands (in this folder)

```
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
swift test --sanitize=thread -Xswiftc -warnings-as-errors
```

Unit tests cover bounded work, no partial view, operation/time overflow,
late validation failure, staging failure, journal failures before/after
nominal durable publication, idempotent request status and mismatch, deterministic
replay across different budgets, 100k bounded fixture, and 2k-call algebra.

### What remains unproved

At 1M assets this two-phase model requires **2,000,000** loop work units,
meaning an ideal minimum **1,000 units per call over 2,000 calls** before any
real scheduler work, WAL I/O, writer contention, thermal headroom, finance,
UI, or per-call latency. This is an arithmetic *lower bound*, not performance.
The model has no measurable H/S Stage A size, Stage B recovery durability,
Stage C overhead ratio, p99, production read policy, or iPhone FPS data.
No alteration to the 24 tracked R005 hot source files or 42 pinned proof inputs
is authorized by a passing micro. No integration until independent scrutiny
and full A/B/TSan/K/C gates, with unchanged thresholds and owner approval.

## Red-team follow-up / 11 October 2026 — before Apple verification

A new local regression proved that a foreign committed world with the **same
asset count** could reuse a receipt from another journal with a matching request
ID: the original mock accepted it because it checked only request equality and
`visiblePending`, not the committed state. The single red-team test
**FAILED** on the previously published Swift source as expected.

The independent model now records an incremental 64-bit *noncryptographic*
fingerprint of staged rows and binds this marker to the mock receipt.
An idempotent requery must match the locally published fingerprint and the
journal's marker. The model also requires a caller-supplied expected initial
world view before replay; recovery from a nonempty initial state that has
no independent durable base is **rejected** rather than silently replaced by
a fresh empty world. The caller-supplied view is NOT a persisted authority,
and FNV-64 is NOT a cryptographic/collision-resistant state root.

Four added named tests cover cross-world receipt substitution, nonempty-base
fail-closed behavior, wrong-base rejection, and prolonged blocking of regular
reads. The last is a **negative viability observation**: budgeted staging
still blocks all business reads during the transaction, unacceptable for
a playable long-running million-asset simulation without a new visibility
protocol. None of this proves the actual production scheduler, save,
durability, crash restore, 1M cadence or UI smoothness.

Linux Swift 6.2.1 local results: Debug **14/14 PASS**, Release **14/14 PASS**,
TSan **14/14 PASS**; the Linux serial mock TSan result is not proof of real
concurrency. Apple source-bound CI to be checked separately. No imported
implementation or method from the earlier game; only NEXORA's source and the
owner's product lessons informed the test. All original R005 C failures remain.
