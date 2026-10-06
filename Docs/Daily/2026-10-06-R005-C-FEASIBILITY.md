# R005 Stage C feasibility checkpoint — 2026-10-06

This is a source/evidence review, **not** a C acceptance result. Repository
`bdr-design/NEXORA`, branch `diagnostic/r005-design-1m-20260930`. The original
run `36875130222` remains **FAILED** on S at 1M/100 saves: overhead
`1.5162503372173357 > 1.10`, while its begin, advance p99, and allocation
gates passed. C remains **OPEN on S and H**; A's choice varies across hosted
CI. The two subsequent writer candidates were rejected and their C runtime
files restored byte-for-byte. The B manifest repair at `a65a5912` has no C
performance claim.

The bounded 1M/five-save S evidence below uses its own idle baseline and event
count. `savingNS` is the sum of timed `advance` calls in capture and writer-only
phases. The `barrierNS` subtraction deliberately assumes the entire observed
copy time disappears with every other timing and event count unchanged; it is
a favorable arithmetic thought experiment, not a prospective improvement.

| Run | Idle ns/event | Saving ns / events | Barrier ns | Actual ratio | Zero-barrier ratio | Remaining above 1.10 budget |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `37473200899` | 282.8676073 | 383,322,879 / 637,690 | 70,549,217 | 2.1251 | 1.7340 | 114,353,633 ns |
| `37475368651` | 382.7490004 | 305,948,224 / 513,379 | 54,783,219 | 1.5570 | 1.2782 | 35,020,176 ns |

The later run spent 79,739,797 ns in capture for 43,605 events and
226,208,427 ns in writer-only for 469,774 events. Against its 382.749 ns/event
idle baseline, writer-only costs about 46.4 million ns extra. Copy removal
alone cannot close this measured gap; writer contention and the changed work
mix must be distinguished before changing the architecture. The earlier run
also fails the same optimistic subtraction.

The official ratio times `world.advance` only. WAL, `service`, waiting for a
commit, and some event checks happen outside that timer. Moreover the latest
idle calls averaged about 934 events, capture calls about 496, and writer-only
calls about 888; their work units/event also differ. That is a limitation of
attributing the measured delta to one cause, **not** evidence that the official
ratio is computed incorrectly or permission to move work outside its scope.
The 1M/100-save acceptance formula, cadence, deadlines, allocator gates and
all published thresholds stay unchanged.

The current S hot state has thirteen separate million-element asset columns
and seven node columns. A first-write copy-on-write of each column would add
many allocations per barrier chunk; whole-column copying risks an excessive
single-advance time. A composite paged representation changes the actual
Stage A layout and memory costs and must be tested afresh. A writer change by
itself was tried in bounded diagnostics and did not close the 1.10 gate. No
credible small C-only patch was identified, so no new 100-save campaign was
launched and the C runtime is unchanged.

The next engineering choices and their costs are:

1. Pair save/no-save replays from the same 1M fixture on an available fixed
   Apple Mac for one or two diagnostic saves. Record per-call events, work
   units, stop reason and `advance` time; separately record `service`, WAL,
   writer CPU/I/O and whole-loop wall time. This costs instrumentation and a
   stable machine and yields diagnosis, not C acceptance.
2. Redesign hot-state ownership into pinned immutable epoch pages and address
   writer contention. This touches S/H state, scheduling, snapshot, restore,
   and memory accounting. It costs a fresh A selection, B source-bound proof,
   exact v2/recovery tests, TSan, K1–K10, bounded micro, then 1M/100 saves for
   the named selected layout; a second layout needs equivalent C proof.
3. Hold R005 as an experiment until the first two paths yield a credible
   candidate. This incurs delivery delay but preserves production and the
   exact existing gate. The repository currently has no iOS app project or
   IPA; even a true C PASS precedes owner review and Stage2–4 integration.

Raw five-save phase JSON is stored under
`Experiments/R005Swift/Evidence/20261006/37473200899-MICRO-S.json` and
`37475368651-MICRO-S.json`. All recorded failed attempts remain in
`Experiments/R005Swift/failures.json`.
