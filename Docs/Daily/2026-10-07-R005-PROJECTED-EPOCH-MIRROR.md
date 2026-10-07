# R005 — projected epoch mirror preflight

Status: PREPARED / NOT_RUN / NOT_INTEGRATED.  2026-10-07.

Repository `bdr-design/NEXORA`, branch
`diagnostic/r005-design-1m-20260930`, live source before this note
`765bf6af86536ad5599c49b28fed607067abecdc`, tree
`650a6be0dd09b926be67ee3a399a12a7c9dd205f`, and `main`
`38ce39cf9322f47e4def5f6eddb425c5a66ea7f9` were reverified.  The required
instructions, continuity, B/C notes, failures, reviews, and current evidence
were reread.  The denied branches and the external game's implementation were
not opened or used.  Every historical failure retains its classification.

This is the allocation and simulation-thread estimate before another isolated
micro.  The actual 24 Swift source files and 42 runtime proof inputs remain
unchanged.  It does not authorize a hot-path edit, A/B/K reuse, C5/C100, a
result file, `main`, Stage2–4, an app, an IPA, or device acceptance.

## Why the bounded K-slot candidate stops here

The verified run `37609776465` proves a flat cold-page ownership protocol, not
its compatibility with the current command transcript.  At H1M there are
3,907 cold pages.  `stageCHybridRescheduleAll` is one WAL command and calls
`schedule` for every asset before that WAL command is appended.  With a stalled
writer it can therefore require all 3,907 protected cold pages before any
service credit.  K=1, K=2, or the earlier illustrative K=204 must reject,
defer, or wait.  K=3,907 consumes 20,003,840B of reusable physical cold-page
capacity (20,000,000B canonical payload plus 3,840B tail slack) and is the full
cold spare in another form.

The all-page result is stricter.  H1M has 3,907 hot, 3,907 cold, 1,954 node,
and 31 group pages.  An early-release nested directory with enough slots to
preserve the existing transcript even when the writer makes no progress is
estimated at about 207–208MB including the known writer/state request charge,
before allocator headers or physical footprint.  It recreates the measured
full-image problem and exceeds the 200MB hard boundary.  In S, hot and cold
asset fields share the same 65-byte pages, so a cold-only integration is not
available without another representation change.

There is also an atomicity blocker: current `schedule` mutates the wheel before
writing cold and hot asset fields.  A late capacity rejection could leave a
partial command.  A production K-slot design would require non-mutating
preflight, reservation of every typed page before the first write, and an apply
phase that cannot fail for capacity.  The million-asset bulk command makes that
reservation unbounded with respect to a small K.  The K-slot design is therefore
`NO_GO_WITH_CURRENT_TRANSCRIPT`, not an integration candidate.

## Next isolated candidate: projected mirror

The new hypothesis keeps gameplay progress independent from snapshot ownership.
It separates the current H asset fields into:

- epoch-stable identity/configuration: destination, contract, entity, and
  policy, 16 logical bytes per asset;
- frequently changing asset state: 37 logical hot bytes plus origin/departure
  at 12 bytes, 49 bytes per asset;
- changing event nodes at 30 logical bytes per node and groups at 8 bytes per
  group.  Reserved wire bytes remain explicit zeroes.

"Epoch-stable" is only true for the current fixture paths.  It is not a promise
that policies, contracts, ownership, or destination can never change.  Any
future change needs a versioned, preflighted configuration path and independent
capacity/failure proof.  At begin the writer must pin a read-only static root
for the epoch because its canonical asset records still require these 16 bytes.
The micro must reject a static change while that version is writer-owned/in use
rather than silently treating mutable business facts as constants.

The live owner keeps one packed dynamic primary and one packed dynamic mirror.
When the mirror is synchronized, ordinary mutations update both.  At save begin
the complete mirror root transfers exclusively to the writer; the simulation
continues on the primary without waiting, rejecting, or lending mutable state,
and marks touched pages dirty.  After the writer has copied a canonical record
into its one reusable scratch and dropped every page-local and root/leaf alias,
it returns those mirror buffers.  Owner-thread service catches a returned dirty
page up from the primary within a fixed budget, then later mutations may update
both again.  A single world coordinator is permitted; there is no lock, task,
actor, or queue per asset or page.

The next save may begin only when every returned page is caught up and the
mirror is exact.  A slow or failed writer may make a save unavailable, but may
not reject, delay inside, or partially apply an ordinary dynamic mutation in
the current fixture.  Static/configuration mutation is outside this transcript
and remains explicitly unsupported/rejected by this micro until its separate
versioned lifecycle is designed and proved.  The normal 1M fixture must prove
mirror readiness before the unchanged 2,000-call save cadence.  Writer error
poisons the save epoch and cannot become a success or a same-epoch retry.
Recovery remains required after a failed published save.

## Memory estimate before code

The current measured H1M live ownership is 105,408,880B for a 100.5MB logical
payload; run `37565498376` binds that number to hashes that still exactly match
the five relevant current runtime files.  This is owned source capacity, not
physical footprint.  Packing the live static/dynamic split can remove 5,000,000
logical explicit reserved-zero wire bytes (3,000,000 asset plus 2,000,000 node
bytes), but this is arithmetic, not compiler-padding removal or a measured
Swift saving.
One dynamic mirror contains exactly:

`49,000,000 + 30,000,000 + 500,000 = 79,500,000B`.

Even before capacity slack or metadata, the permanent representation has an
exact logical lower bound of `16,000,000 + 79,500,000 + 79,500,000 =
175,000,000B` for static state, dynamic primary, and dynamic mirror.  Stage A's
H selection rule at 1M requires owned memory at or below 128B/asset.  The
permanent mirror therefore cannot pass A and is `NO_GO` for integration even if
the isolated concurrency protocol succeeds; a pass can only answer the writer
contention research question.

Its exact full-tail page capacities are 49,009,408B asset, 30,013,440B node,
and 507,904B group: 79,530,752B.  For a deliberately conservative source
preflight, charge 10% above that capacity (87,483,828B), 1,000,000B for
page/leaf/directory wrappers and coordination, the complete proposed 4,194,304B
fixed hot reserve, and a 299,146B proposed writer/state capacity charge.  The
latter reconstructs canonical page records, one scratch, the 18,844B control
record, page/stamp identifiers, and fixed state arrays; it is not an observed
resident-allocation measurement:

`105,408,880 - 5,000,000 + 87,483,828 + 1,000,000 + 4,194,304 + 299,146`

`= 193,386,158B`.

This leaves only 6,613,842B below the 200MB hard boundary and is 65,386,158B
above the Stage A 128B/asset selection limit before allocator headers, `phys_footprint`, restore
state, UI, or media.  If the live packed saving does not materialize, the same
arithmetic is 198,386,158B, leaving 1,613,842B.  Replacing the proposed
299,146B charge with the observed maximum cumulative writer-request total and
granting no 5MB saving produces 199,592,866B before separate begin/sink charges;
run `37564011879` binds its 1,505,854B maximum to the current relevant runtime
hashes.  That request total is cumulative rather than resident memory, but the
stress arithmetic shows how little margin exists.  No physical-memory upper
bound below 200MB is established.  Thus the candidate is eligible only for a
bounded micro.  It is not memory-fixed or integration-eligible even if its
protocol works.

## Simulation-thread estimate and fail-closed gate

- no active writer: one ownership-state test plus the required primary/mirror
  field writes; no allocation;
- active writer: primary write plus a prepared dirty-bit update; no gate wait;
- begin: control encoding and exclusive root handoff only, with the unchanged
  100us limit as a future requirement;
- service: only returned pages, bounded by time/count, no global scan or I/O;
- writer: one canonical record in one reused scratch, then alias drop/return,
  then I/O; writer and simulation wall times remain overlapping;
- the paired full-loop report must include mirror catch-up and duplicated idle
  writes.  Work cannot be moved out of `advance` and then omitted from the
  decision.

Under the proposed production geometry, H1M has separate 256-asset,
512-node, and 2,048-group pages: 3,907 asset + 1,954 node + 31 group = 5,892
projected pages.  The replacement micro must use these typed page widths.
Because 4,096 assets cannot reach directory slots 63/64 under that geometry, a
separate 65-slot tiny-page metadata case is labeled `payloadGeometry=false` and
cannot stand in for a payload or H1M result.  Catch-up is live only if each returned dirty page moves
on the owner thread from `writerOwned` to `returnedDirty` to `syncedDual`, after
which normal dual writes keep it synchronized and the backlog is monotone.
Finiteness alone does not meet the 2,000-call cadence.  Service runs before the
readiness check at call 2,000, so the lower bound is phase-sensitive.  If `B_r`
dirty pages become eligible before service at relative call `r` in 1...2,000,
there are `2,001 - r` opportunities; after service there are `2,000 - r`.
Eligibility before the first service has 2,000 opportunities.  In the worst
case where none of 5,892 pages became eligible earlier, calls 0, 1,000, 1,500,
and 1,900 require 3, 6, 12, and 59 pages/service.  At call 1,999 the bound is
2,946 before service but all 5,892 after service; at call 2,000 only a
before-service return can still be caught.  A future H1M gate therefore needs
raw return phase/timing and backlog plus catch-up throughput, not only an
eventual-ready assertion.

The existing run `37539359684` accessor comparison is also adverse evidence,
not a reusable speed claim: in the no-writer mutation arms at 100k, 800k
word-packed mutations measured 4.283–5.804ms versus 1.175–1.350ms for rows.  An
integration candidate must therefore compare the old H no-save loop with the
projected representation's no-save loop in absolute time, including dual writes
and service, before the unchanged C ratio.  Save/idle ratio alone could conceal
a permanently slower idle baseline.

### Red-team stop before execution

The first disposable implementation draft was rejected before commit or Apple
execution.  It advanced writer work serially, retained the complete writer root
while owner service mutated its pages, and therefore did not establish alias
drop, exclusive transfer, or meaningful TSan overlap.  Its failure path also
performed an unbounded full reconcile and allowed a new epoch without explicit
recovery.  None of its literal PASS labels are evidence.

The replacement must use a real asynchronous writer and independently typed
value pages.  Before publishing return credit, the writer must tombstone its
root slot, finish all reads, and move its sole page value through one
coordinator-owned return directory; owner service then takes the value, releases
the coordinator, catches it up, and alone enables dual writes.  Ordinary dynamic
mutation may not acquire that coordinator.  Failure/cancel returns remaining
buffers progressively through the same bounded path and blocks begin until an
explicit recovery transition.  File completion alone cannot make the mirror
ready or count a save.

The first micro runs only at 257/K-like pressure and 4,096 assets under
Debug/Release/TSan for three epochs, then a conditional Release 100k diagnostic.
It must prove exclusive root transfer, typed asset 255/256, node 511/512,
conditional 100k group 2,047/2,048, explicit metadata slots 63/64, and all tails;
dirty while writer-held, writer-release before/after owner mutation, catch-up and dual-write,
no credit while an alias is held, canonical static-root pinning, rejection
without side effects of a static change while pinned, pin release/reuse after
success, failure, cancel, and the next epoch, canonical frozen/live/recovered
digests, writer failure/cancel/foreign/stale/overflow cases, and Release zero
allocations in measured post-setup owner paths.  Debug is observational;
unavailable TSan allocation counters remain `null`.

H1M, C5, and C100 stay disabled unless the artifact explicitly establishes a
credible memory and readiness bound.  A passing protocol result is named
`PROJECTED_MIRROR_PROTOCOL_PASS_NOT_INTEGRATION_ELIGIBLE`.
