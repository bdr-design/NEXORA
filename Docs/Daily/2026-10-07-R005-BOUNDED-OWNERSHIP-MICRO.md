# R005 — bounded cold ownership micro preflight

Status: PREPARED / NOT_RUN / NOT_INTEGRATED.  2026-10-07.

Pre-edit source review: repository `bdr-design/NEXORA`, branch
`diagnostic/r005-design-1m-20260930`, live HEAD
`56535ecca851a324087ed04d2fdf94767ceb6c49`, tree
`25e68f5098480e1ec74723694ca48c28f779652b`, and live `main`
`38ce39cf9322f47e4def5f6eddb425c5a66ea7f9` were reverified.  `AGENTS.md`,
`PROJECT_CONTINUITY.md`, the required B/C notes, failures, review, and current
functional proof were reread.  The three denied branches and the external game
implementation were not opened or used.  All historical failures retain their
recorded classifications.

This note records the allocation and simulation-thread estimate before any
hot-path edit.  The actual 42 Swift runtime inputs remain unchanged.  The
micro is one isolated H-cold buffer with the current canonical fields only:
`entity32`, `policy32`, `origin32`, and `departure64` (20 bytes/asset), packed
in 256-asset `UInt64` pages.  It is not another World, save format, economic
model, or product feature.

## Why the current owner cannot be edited directly

The accepted functional implementation reserves a second payload image in
`EpochBuffer.preparePool()`.  Its frozen roots are Copyable and the old page
references are also retained through `spareRoot` and `spareLeaves` until the
whole writer finishes.  A prefix counter therefore cannot prove early reuse:
an extra root, leaf, page, pending-view, or writer-local alias can still force
a hidden COW allocation.  `PendingEpochSnapshot.reserveBegin()` also has no
abort for the reserved-but-unpublished state.

The isolated candidate instead uses two separately prepared flat directories.
The owner keeps the live directory; the writer exclusively owns the snapshot
directory after publication and clears each entry in canonical order.  A
non-inlined retirement frame must return before the writer publishes a packed
`epoch/prefix` cursor with release ordering.  The owner uses an acquire load
before making a returned buffer eligible.  The owner token contains stable
owner, buffer, and epoch values and never relies on `ObjectIdentifier`.

One atomic owner/writer gate protects only bounded metadata handoff.  The owner
tries it once and rejects `busy` rather than waiting or spinning.  The writer
may wait for the short owner reservation.  No lock, wait, sleep, I/O, task, or
actor per entity/page is introduced.  The writer owns one preallocated scratch
buffer, serializes exactly one canonical page into it, and writes that page
sequentially to the evidence file before the page can retire or the prefix can
advance.  It never accumulates `[[UInt8]]`, and writer I/O never holds the
atomic gate.

`begin→publish` is one gate-held transition: a busy rejection cannot strand a
reserved token.  After publication, any injected or real writer I/O error
poisons that epoch under the same metadata gate.  Further writer records and
success/cancel terminals are rejected; only an explicit failed terminal may
reclaim it, and the poison resets only when the next epoch is reserved.

## Capacity and memory estimate before code

At 1M, H has 3,907 cold pages and 62 cold leaves.  The exact canonical cold
payload is 20,000,000B.  Reserving every physical page at the full reusable
capacity costs 20,003,840B; the 64-asset tail therefore adds 3,840B setup
slack.  One full slot is 5,120B.

Using the measured current H prepared ownership of 210,772,320B, the following
conservative source-owned ceiling deliberately retains current metadata while
subtracting only the old full cold spare payload.  It also charges a 64B
source-side allowance for every one of the 3,907 page wrappers and K slot
wrappers:

`Bc(K) = 191,105,404 + 5,208K bytes`.

This includes a second cold directory, an owner page map, reusable tail
capacity, slot records, the wrapper allowance, and a small control allowance.
The 64B charge is conservative source arithmetic, not a measurement of Swift
object layout.  Allocator/object headers and `phys_footprint` remain unmeasured,
as do restore worlds, UI, and other process state.

| Case | Source-owned ceiling | With known writer/state requests | Result |
| --- | ---: | ---: | --- |
| H1M, K=1 | 191,110,612B | 191,409,758B | below 200MB hard cap arithmetically; 63,409,758B above 128MB target |
| H1M, K=2 | 191,115,820B | 191,414,966B | below 200MB hard cap arithmetically; 63,414,966B above 128MB target |
| H1M, K=204 (about 1MiB payload) | 192,167,836B | 192,466,982B | 64,466,982B above the 128MB target |

The second column adds the same known 299,146B writer/state request charge in
every row.

The proposed 4MiB production reserve cannot be spent twice.  Charging its
remaining 3MiB makes the K=204 estimate 195,612,710B before the uncounted
process consumers.  All numbers above are requested-capacity arithmetic, not
`phys_footprint` evidence.  S does not have an independently measured prepared
1M total in current evidence, and its semantic cold fields are mixed into its
65B asset pages; no S prepared number or cold-only claim is invented here.

The mandatory small cases are:

| Fixture | Live full-capacity payload | Slots | Raw payload reserve before headers |
| --- | ---: | ---: | ---: |
| 257 assets | 10,240B | K=1 / 5,120B | 15,360B |
| 4,096 assets | 81,920B | K=2 / 10,240B | 92,160B |

The tail at 257 assets has 20 canonical bytes and 24 physical word bytes, but
its array capacity is prepared for 5,120B so it can later serve a full page
without allocation.

## Simulation-thread estimate and required observations

- `reserve/publish`: O(pageCount) reference-directory fill, prepared storage,
  no allocation.  At 1M this is 3,907 references and must still satisfy the
  unchanged beginSave limit if an integration is ever proposed.
- accepted first write: at most K page copies, 5,120B each.  All pages required
  by one command are reserved before the first payload/control/WAL write.
- rejected K+1/busy/stale/foreign write: O(command pages + K), zero allocation,
  no wait and byte/control/WAL identity.
- repeated write to an already separated page: in-place and zero allocation.
- service: one acquire cursor load plus O(K) fixed-slot inspection; no I/O.
- writer: one bounded page-to-scratch copy while it owns the page, followed by
  a sequential file write outside the atomic gate.  The write must complete
  before the writer retires the page-local alias and publishes prefix credit;
  only then may the scratch be reused.  Writer and owner wall times overlap and
  must never be added as if sequential.

No latency number is assumed.  Apple must measure begin/reserve-copy/reject,
service, writer, and whole-loop time separately.  Release requires calibrated
positive controls and zero allocations in owner reserve/copy/reuse/reclaim and
the next publication.  Debug records observations; TSan allocator values are
`null` when the interposer is unavailable.

## Fail-closed small gate

Run Debug/Release/TSan at 257/K1 and 4096/K2 for three epochs.  The gate must
prove all-or-nothing multi-page reservation; immediate K+1 rejection; monotone
contiguous owner/epoch prefix credit; a held writer-local alias cannot release
credit; partial-to-full reuse; release-before-first-live-write in-place reuse;
out-of-order/duplicate acknowledgement rejection; stale/foreign/replay and
overlap rejection; reserved-unpublished cancel; published cancel and injected
writer failure that poisons retry/success without a false commit; and independent frozen/live/recovered
digests with exact canonical page order.  In the 257/K1 geometry, attempting a
second-page owner mutation while the writer still holds page 0 must reject as
`writerReading`; K=1 cannot independently demonstrate a free-slot capacity
rejection because there is no third page.  The 4,096/K2 case supplies that
capacity proof while page 0 remains held.

Only a passing small gate may enable a separately recorded 100k diagnostic.
1M remains disabled unless that evidence explicitly says `safeToRunH1M=true`.
No C5/C100, A/B/K reuse, S/H representation edit, result file, main merge,
Stage2–4, app, IPA, or device claim follows from this micro.  A useful result is
`MICRO_PROTOCOL_PASS_NOT_INTEGRATION_ELIGIBLE`, not integration eligibility.
K+1/backpressure still lacks an unchanged production transcript, and full-H
memory and timing are not measured.  Any later integration proposal would
require a new design that closes those gaps plus the full fresh source-bound
sequence in `AGENTS.md`.
