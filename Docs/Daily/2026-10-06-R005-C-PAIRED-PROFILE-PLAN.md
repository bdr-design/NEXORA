# R005 C — paired S diagnostic and epoch-page estimate — 2026-10-06

This is a design-and-measurement plan, not a Stage C result.  It is limited to
S because the reproducible quantitative failure is S in run `36875130222`.
It makes no claim about H; C remains OPEN independently on S and H.  The
existing 1M/100-save formula, cadence, deadlines, timer scope and all gates
remain unchanged.  This plan will not create `STAGE005-C.json`, `results.json`
or `STAGE-R005-RESULTS.md`.

## Fixed-fixture paired diagnostic

Create one canonical 1M S fixture (initial committed snapshot, WAL prefix,
fixture digest and fixed target/budget/work-budget).  Restore copies of that
one fixture for two alternating diagnostic pairs: no-save→save, then
save→no-save.  Every leg uses the same advance script with no deadline so its
per-call events, work units and stop reason can be asserted equal.  This is
deliberately different from the official 1 ms deadline-shaped C measurement,
so it diagnoses components only and can never substitute for C acceptance.

The no-save control still appends the same WAL frames, validates output and
runs the same one-million-item reschedule.  At the identical boundary both
legs install `StageCState`; the no-save leg keeps it idle so the Stage-C
write hooks remain present without capture, while the save leg additionally
creates `SnapshotSink` and begins one epoch-2 snapshot.  Record separately:

| Component | Measurement scope |
|---|---|
| advance | Only `world.advance`; per-call events, units, stop, elapsed and allocations |
| WAL | `appendAdvance`, `appendRescheduleAll`, open/close separately; never folded into advance |
| service | Each `StageCState.service` call, split by capture / writer-completion state |
| reschedule | One-million-item `stageCRescheduleAll`, including its allocations and barrier deltas |
| writer | Dispatch-to-run delay, writer run lifetime, queue-wait, record processing/write, and finalize/sync/rename cleanup components |
| full loop | Profile loop from WAL resume through final close; fixture copy/recovery and full end-to-end time are reported separately so transport cache/I/O variance is not folded into the paired loop delta |

The profile checks equal initial and final logical digests, output hash,
recovery digest and advance transcript within a pair, and records the matched
idle-state installation boundary.  A 4,096-asset paired smoke runs first in Debug and
Release; only then may the release 1M paired diagnostic run on the same Apple
`macos-15` class.  It is not a 100-save campaign and it records an observation
rather than changing any historical failure classification.

The writer telemetry is intentionally intrusive: it inserts per-record clocks
and uses the allocation observer on the writer thread through
`DYLD_INSERT_LIBRARIES`.  Therefore its timing is a paired diagnostic signal,
not an uninstrumented production-C estimate, and it cannot be presented as a
C improvement or acceptance result.

## Current chunk budget and page-cost estimate

At 1M assets the current capture chunk sizes are 256 assets, 512 nodes and
2,048 groups.  There are 3,907 asset chunks, 1,954 node chunks and 31 group
chunks: 5,892 mutable data chunks plus one control record.  The exact current
snapshot sizes follow from the wire payloads and are already evidenced.

| Layout | Asset payload | Node payload | Group payload | Exact snapshot bytes |
|---|---:|---:|---:|---:|
| S | 65,000,000 | 30,000,000 | 500,000 | 95,801,772 |
| H | 68,000,000 | 32,000,000 | 500,000 | 100,801,772 |

If the paired evidence shows capture/writer contention is materially causal,
the candidate is immutable epoch pages at those same chunk boundaries.  `begin`
would publish a retained page-directory root and one copied control block;
before a simulation-owner write, `ensureMutable` would copy just the affected
page and replace it in the live root.  The writer would walk only the frozen
root in canonical order and keep a reusable writer-side record buffer.  It
would never lock or traverse mutable live state.  One active epoch and one
writer remain required; completion releases the frozen root only after the
existing commit protocol has completed.

This is **not** assumed to remove copying.  With full dirty coverage it must
copy up to the equivalent of one whole payload image: about 95.5 MB for S or
100.5 MB for H, plus page/object/directory headers.  A flat 5,892-reference
snapshot table alone is about 47,136 bytes before ARC traffic; the candidate
must use a persistent two-level directory so `begin` is O(1) rather than
copying that table on the simulation path.  Lazy COW can allocate up to 5,892
pages in a fully dirty epoch; a preallocated clone pool trades that allocation
pressure for approximately another full state image kept resident.  Neither is
an accepted optimization without a micro-test.

A packed row-page implementation would pad S assets from 65 to 72 bytes and S
nodes from 30 to 32 bytes, adding roughly 9 MB of payload before headers; H
would pad assets from 68 to 72 bytes, roughly 4 MB.  A paged SoA design avoids
that padding but has more page references and memcpy operations.  The future
page micro must compare both at 4,096 assets first, then optionally 100k;
measure clone ns/byte, allocations/page, peak retained bytes, frozen/live
digest equality and writer ownership under TSan.  No S/H representation will
change until the paired profile identifies a credible causal target.

## Simulation-thread estimate before a hot-path change

The only added operation proposed for a real page design is one epoch/ownership
check per page write; the first write also pays a page clone.  A single
`advance` can touch many pages, so the safe upper bound is the full 5,892-page
set, not an assumed one-page cost.  The present measured barrier median
(`53,088,736` bytes / `10,117,087` ns in the second rejected diagnostic) is
not used to promise a new p99 or ratio: COW allocation, pointer indirection,
cache locality and writer contention can make it worse.  The paired profile
will establish the current simulation-thread component times first; only then
does the 4,096 page micro get permission to test the estimate.

All existing failures, especially `36875130222` and `37505451077`, remain
unchanged.  Any later S/H representation change requires a new A decision,
source-bound B proof, Debug/Release/TSan, K1–K10 and a layout-named 1M/100-save
C result before owner review.
