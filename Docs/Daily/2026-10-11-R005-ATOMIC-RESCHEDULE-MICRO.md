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
