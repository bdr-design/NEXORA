# ADR R005 — persistent identity, representation, billing and recovery for 1M assets

**Status: PROPOSED — production implementation requires owner approval.**
Date: 2026-09-30 / Asia/Riyadh. Repository: bdr-design/NEXORA only.
Scope: design and disposable measurement, not R005 production code or an iPhone acceptance.
Canonical business baseline: 674c94e145f24dc6c4c9addaa5aa07d1c9d4a168.
Reviewed publication: 5384b58d193f90859a8f0efeaec6d28d6e93b89e.
Discovered newer, permitted, Apple-tested preparation baseline:
38ce39cf9322f47e4def5f6eddb425c5a66ea7f9 (includes auditor0706447 and hardening74d8a7f).
The owner authorized a single forward development line. Main was fast-forwarded,
without force, from5b559989 to38ce39cf after ancestry and source/evidence checks.
Active branch: diagnostic/r005-design-1m-20260930. Older permitted branches are
historical, not simultaneous work lines. Permanent exclusions in AGENTS remain.

## 1. Decision boundaries

1M is the design population; physical iPhone17ProMax acceptance is100k,250k,1M,
with the same agreed features and activity profile at each gate. 2M is capacity/
headroom testing, not a device-performance promise. Other domains are not added
before R005. Designing extensibility does not implement payroll, maintenance or delivery.
The former20k acceptance and100k architecture goal are superseded, not retroactively passed.

Stage0 is one bounded diagnostic iteration and a scoped verdict. Its completion
must not claim all causes are known. Equal instruction counts do not exclude
on-CPU memory stalls; zero PMU values follow an unavailable-reading policy, not a
hardware conclusion. Original facts/observations are retained without rerunning
the old artifact. The no-origins-optimization decision is binding independently
of whether every possible index cost has been scientifically excluded.

Stage1 is this ADR plus a disposable1M layout probe. Stages2–4 remain unimplemented
until this design is approved. No production library, economic rule or index is
changed by the preparation experiment. Generated instrumentation changes only a
new disposable copy, with the original source hashes recorded and checked unchanged.

## 2. Baseline, evidence and limits

FinanceStore currently caps invoices and journal entries separately at1,000,000,
keeps both in memory, and retains an origins dictionary entry per invoice. One
priced arrival and one full collection need two journal entries; 1M aircraft
therefore require at least2M entries for one complete cycle, plus capital/expenses.
At100k, five complete cycles already consume1M entries before other postings.
The cap is a backpressure boundary, not evidence of1M gameplay support.

The historical0.471146ms/1k and109.172292ms/100k arrival totals correspond to roughly
471.146ns and1091.723ns per aircraft in that fixture. They are wall-time averages
including outer-loop work, not CPU/event measurements on iPhone. They do not
isolate locality from heap depth, dictionary layout or other costs.
The quoted185B/aircraft and800MB/day are consultant estimates, not new physical
footprint or serialized-file measurements. Do not use them as acceptance baselines.

Source contracts, named test counts and historical raw data are described in
Docs/VALIDATION-R004.md, Docs/VALIDATION-R004-AUDIT.md and
Docs/VALIDATION-R004-HARDENING.md. Earlier failing/incomplete commands remain
in their ledgers. A passing compiler/sanitizer is not a causality or gameplay proof.

## 3. Budgets and accounting definitions

| Metric | Owner requirement | Where measured / current status |
|---|---:|---|
| Resident hot economic state | target<=128B/asset; hard<=200B/asset | Include asset columns, scheduled-node capacity, sorting scratch, active accruals and dirty state. Fixed shared pools reported separately AND in the total formula. |
| Full event steady-state at1M | <=0.5 microseconds | Physical device only; NOT measured by a row-update microkernel. |
| Heap allocations | zero/event; <=1/advance | Allocator-observed full path required; probe's owner allocator count is a narrower preliminary measurement. |
| Sustained simulation CPU | <=0.25 performance-core equivalent | Physical30-minute run; record QoS/core residency/clock conditions. Percent processCPU alone does not identify core type. |
| Visible save interruption | <=2ms | Main-thread/frame trace under saving, not disk-write duration. |
| Local campaign storage | proposed8GiB total | Hard quota/backpressure before commit. Unlimited lossless retention under this cap is NOT established; approval issueA1 below. |
| Capacity |1M supported design;2M probe margin | Constructor checks computed memory/event/accrual quotas, no simple global hardcoded max-only acceptance. |

MB below is decimal; MiB/GiB use powers of1024. Requested allocation bytes,
committed/resident/phys_footprint, database mappings, GPU resources and transient
checkpoint memory are distinct measurements. No one substitutes for another.

### 3.1 Concrete proposed logical layout

The probe uses SoA primitive columns, not per-asset Swift objects. Each field has
one owner; references in array/column descriptors are outside stored rows.
PureSoA does not literally place every field of an asset adjacent. We group hot
columns by access set and keep each column contiguous. AoSoA/tiles are a future
measured alternative, not an unmeasured performance claim in this ADR.

| Owned region | Fields / density | Bytes |
|---|---|---:|
| Identity and command-visible columns | generation,lifeFlags,ownerEntity,policyVersion,contract,currentAirport,origin,destination,eventNodeIndex,changeEpoch:10xUInt32 |40N|
| Operation/flight columns | operation,lastAccruedOperation,departureTick,fareMinor,completedCount:5x64-bit |40N|
| Scheduler payload | dueTick,sequence:2xUInt64; assetIndex,generation,nextIndex,packedBucketKind:4xUInt32 |32E|
| Deterministic bucket ordering scratch | two index columns, UInt32 each; reserved, never allocated/event |8E|
| Active accrual groups | entity32,contract32,period64,amount64,lastOp64,invoiceSequence64 |40G|
| Dirty bitmap | one bit/asset |ceil(N/8)|
| Wheel heads/tails,occupancy,1024-result scratch |8x256 buckets; occupancy; fixed result workspace |33,024|

**Formula:80N+40E+40G+ceil(N/8)+33,024 bytes.**
Normal design profile:E=N;G=ceil(N/16), meaning an assumed average16 assets per
active contract-period. This is a workload assumption, not a guarantee about users.
For1M:122,658,024 requested bytes,122.658024B/asset.
For2M:245,283,024 requested bytes,122.641512B/asset.
WithE=2N:162.658024B/asset at1M;162.641512 at2M.
WithG=N,E=N:160.158024B/asset at1M. WithG=N,E=2N it exceeds200B once
shared state is added and MUST be refused or re-budgeted, not silently accepted.

Proposed further fixed hot pools:4MiB total (1MiB command/WAL staging,
2MiB bounded old-page/checkpoint staging,1MiB read-page cache). At1M normal profile,
total126,852,328 bytes=126.852328B/asset. At100k the same fixed pools make the
per-asset total larger; the allocator gate uses the full formula, not a constant
quotient claimed at all sizes. Framework/renderer/catalog/blob caches still require
a separate physical-memory envelope; proposed initial device test ceiling384MiB
is a planning trigger, NOT an iOS entitlement/available-memory guarantee.

**Measured prototype scope:** allocation of those proposed columns plus a checked
lookup/accrual/completion/dirty-output kernel, sequential and permuted traversal.
The prototype reserves scheduler/scratch slots but DOES NOT implement a wheel,
production API capabilities, full accounting, persistence, UI, GPU or all domains.
Its<=128B result therefore validates a representation candidate, not every feature.
The broader200B ceiling leaves expansion room, not permission for unlimited scopes.

## 4. Identity and public boundaries

AssetID is two UInt32 values(index,generation),8 bytes. UInt32.max is the invalid
index/sentinel. Slot retirement at generation exhaustion is permanent; no wrapping.
A world has a checked64-bit token in its header. Public capability wrappers carry
that token plus the packed ID; stored rows carry only local primitive IDs. Inputs
validate world,range,generation,life and expected entity revision before any write.
A private/non-public initializer blocks accidental external construction; compile
rejection tests remain. A world token is not cryptographic authentication against
malicious code, memory corruption or a party that already knows it.

OperationID,InvoiceID,ContractID are UInt64 persistent IDs. Local compact indices
may be UInt32 through checked mapping tables; an index is not a durable ID. The
operation allocator belongs to WorldCoordinator, not AircraftStore.revision. It
checks exhaustion, persists its high-water mark and is restored before new commands.
Invoice origins survive retirement/reuse. Old invoice queries compare world+full
identity, not the slot's current occupant. Invoice counters never silently wrap.

Stage2 requires exact legacy transcripts before economic changes. Introduce the
permanent-ID mapping in parallel with the existing externally visible IDs; retain
a compatibility view until the approved semantic boundary. Do not hide changed
visibleIDs by silently normalizing tests that formerly compared them. Removing the
compatibility layer and changing transcripts is an explicitly versioned step.

Data-only AccountID/LedgerEntityID/CurrencyID/PolicyVersionID references are checked
against loaded catalogs. Names and document blobs are outside hot rows. World/ID
serialization specifies width, endian and version; raw pointer/object bytes never
enter a save.

## 5. Bounded hierarchical timing wheel

Proposed wheel:8 levels x256 buckets,base tick1 simulation second to match current
UInt64-second timestamps. Absolute dueTick and global sequence retain exact order;
no rounding changes. Higher levels cover the64-bit horizon without arithmetic
wrap. ArrivalHeap currently orders(arrivesAt,operationID); the compatibility
scheduler must emit exactly this ordered transcript for every legacy fixture.

One generic32-byte event node stores due,sequence,asset identity,next and packed
bucket/kind. Domain rows reference its index; due time and full trip payload are
not duplicated in a journey and heap. Read views compose the single owned values.
Future event kinds get registered data IDs; no new domain behavior is added now.

Insertion uses bucket arithmetic and intrusive links, but O(1) insertion is NOT
O(1) dispatch for arbitrary simultaneous populations. Leaf processing sorts
indices deterministically by exact(due,sequence), using preallocated radix scratch.
Cascades,sort passes,dead-node reclamation and dispatch all consume the same bounded
work budget. A million tied events can require many calls; the reported reached
simulation time cannot skip them. Timer-window movement has its own resumable cursor.
No unbounded full-wheel scan across a large empty time jump: use occupancy bitmaps.

Cancellation is a checked tombstone/generation transition; lazy nodes count against
E until reclaimed. Repeated rescheduling cannot create unbounded memory: capacity
preflight/backpressure occurs before the old active operation is replaced. A failed
business event stays pending, while any previously committed prefix stays explicit.
Counter overflow,corrupt node index,cycles in intrusive lists and exhausted sorting
workspaces fail-stop rather than loop forever. The existing12 probes remain and
new wheel-specific corruption probes supplement them.

Stage2 proof includes dense ties,far-future deadlines,empty jumps,wrap boundaries,
cancellations/reused slots,op-order reversals across cascades,capacities0/1/full,
1/7/31/1024 work budgets and injected failures. The disposable layout probe does
NOT establish any of these wheel behavior properties.

## 6. Atomic preparation and actual progress

Single WorldCoordinator owns the economic state. Domains expose fallible prepare
(read-only expected-state checks and fixed-size plans) and consume-once commit
(no expected business failure). The coordinator prepares every participant and
reserves WAL/output/event slots before the first economic write, then commits
without await,callback,I/O or external writer between participants.

Plans carry owner/domain identity,expected revisions and validated deltas. Stale or
foreign plans fail-stop at internal boundaries. Pool exhaustion or expected lack
of cash/capacity fails in preparation. All domain primitives,including aircraft,
need separate preparation; adding fallible work after aircraft completion is not
atomicity. At an expected event failure, only earlier committed events are returned.

advance accepts a count/work budget and a wall-time deadline. The clock is checked
between atomic units,not halfway through a commit. Deadline stopping may select
different chunk boundaries but must not change event order,amounts or final truth.
For deterministic tests use an injected clock; replay records accepted input order
and logical simulation time,not the historical CPU scheduling of an advance call.
Sorting/cascades must be interruptible too. Device0.5us/event and2ms frame-visible
save budgets are tested later; an event is not promised interruptible at every CPU
instruction. Slow calls report actual progress and throttle,never pretend time advanced.

## 7. Finance semantics — APPROVAL REQUIRED

### 7.1 Multi-entity chart and atomic accrual

Chart of accounts is a validated table,not a compiled enum. Each ledger entity
(company,subsidiary,unit) has an immutable configured currency. Parent rollups are
maintained when committing deltas. Inter-entity postings form one prepared group:
all balances/limits are validated together. FX uses an explicit versioned rate and
rounding/remainder accounts; implicit conversion is prohibited. Designing these
contracts does not claim implementation of banks,treasury or other sectors.

Arrival updates the contract-period unbilled receivable and recognized revenue
atomically with aircraft completion. The fare/policy version is captured when
committing departure. A later pricing-policy update cannot change prior arrivals.
A period-close operation materializes the accounting summary without recognizing
revenue twice. Invoice issue is a separate atomic reclassification from unbilled
receivable to billed receivable,NOT new revenue. Collection debits cash/credits
billed receivable,NOT revenue. Partial collections and unpaid balances remain exact.

A proposed daily invoice groups(entity,contract,line if needed,period,currency,
policy-version/tax regime). Incompatible currencies or accounting treatments never
share an aggregate. Period boundaries use simulation time,not device clock. Business
commands are ordered explicitly around same-tick closes; tests fix the precedence.

### 7.2 Exact proposed disk record sizes and growth

ProposedInvoiceRecord64B: id64,entity32,currency32,contract64,periodStart64,
periodEnd64,issuedTick64,amount64,paid64. This is a defined binary payload,not native
Swift MemoryLayout. Settlement updates append deltas; no historical invoice rewrite.
ProposedJournalRecord64B: record64,operation64,invoice64,tick64,entity32,currency32,
debit32,credit32,amount64,CRC32C32,flags32. Segment headers/checksums and indexes are extra.
With62,500 active contract-periods/day,oneinvoice andthree64B postings
(accrual summary,invoice reclassification,onecollection) give16,000,000B/day.
A25% INDEX/FRAMING RESERVE gives20,000,000B/day. The25% is proposed,not measured.
At1M distinct daily contracts,the same payload is256MB/day before index overhead.
Partial collections,inter-entity groups and corrections increase these figures.
Actual segment/index/WAL growth per game day is a mandatory Stage3 measured gate.

The old "800MB/day" is not reused as a measured comparator. With this candidate
64B invoice andtwo64B journal rows,5M individual-trip invoices would be960MB of
payload/day before indexes; that is a hypothetical format calculation only.

### 7.3 Deduplication and out-of-order safety

lastAccruedOperation per asset is valid ONLY when priced operations for that asset
are accepted in increasing ID order and at most one active operation is admissible.
An older unseen operation after a newer one must not be silently dropped; it is
an order violation or needs an explicitly bounded gap table. Reversals/corrections
are new operations,not reusing an oldID. A separate durable idempotency receipt
supports customer commands. The historicalorigin->invoice query moves to a paged
disk index; a last-operation watermark does not answer arbitrary old invoice lookups.
This origins replacement belongs to an APPROVED billing redesign,never a spike fix.

### 7.4 Open items are not bounded by asset count

At1M assets,five invoices/day and30-day payment delay,150M invoices could be open
under the old model. Do NOT keep every open invoice resident. The hot state holds
balances/aging totals,bounded active accruals and a bounded page cache. Full open
and paid item records live in indexed storage; due processing uses a persisted
ordered queue. Queries/disk prefetch happen outside economic atomic sections.
A missing required page delays preparation with backpressure,not synchronous I/O
inside commit and not treating the debt as zero.

## 8. Policies and external commands

An asset references a policy version. A bulk fleet change creates one immutable
policy version and changes the fleet's policy reference once. Current flights
retain their effective terms; future dispatch resolves the latest eligible policy.
Per-asset overrides are explicit sparse data with quota accounting. Version retention
is bounded by live references and persistence; unbounded policy edits cannot silently
consume unbounded hot memory. Reference reconciliation is incremental,not a fleet scan.

Replace one global revision precondition for all queued UI commands with a checked
world epoch,per-target expected revision and(clientSession,monotoneCommandSequence).
A bounded serial mailbox (proposed1,024 pending commands) assigns canonical input
order. Unrelated successful commands do not automatically invalidate all waiting
commands. A conflict only rejects the affected precondition; the response states
whether it was rejected,accepted,committed or durable. Retries never create duplicate
money. Old dedup receipt eviction cannot authorize replay; a persistent watermark
rejects already-processed commands whose detailed response is no longer cached.
User intent arrival time and actual commit time are distinguished in logs.

## 9. Read models and rendering

Each committed slice publishes a bounded immutable list of changedIDs/field masks,
with a cursor if more than one page. Company totals and status counters update as
part of commit. Search and lists page through indexes; no recurring full-world scans.
Long-running index rebuilds or migrations are explicitly background bounded tasks,
not work hidden in every query. queryRevision/watermark makes staleness visible.

An active-flight presentation buffer changes on departure,arrival,cancellation and
explicit route changes. The GPU derives visual interpolation from endpoints and
simulation times. That does not mutate economic position truth per frame. Rendering
still costs GPU/memory bandwidth: cull,cluster and useLOD; never draw1M full icons
just because economic state contains1M assets. The renderer consumes detached data
or a bounded double/triple buffer with ownership/ACK rules; it cannot retain unlimited
old snapshots. No iOS/Metal implementation is delivered by this ADR.

## 10. Persistent storage, replay and crash semantics

Proposed8GiB LOCAL quota allocation:1GiB for two checkpoint generations;
512MiB for WAL;3GiB ledger+indexes;1GiB document/blob quota;
1GiB operational detail;1.5GiB compaction/recovery reserve. These are initial
engineering allocations,not verified final compressed sizes. Required slack must
exist BEFORE acceptance of a transaction that needs it. Full media uses checked
blob references outside hot state. A full blob quota rejects the attachment operation;
it cannot silently discard proof or block-until-OOM.

Checkpoints serialize typed primitive columns with a versioned little-endian schema,
world token,ID high-water marks,configuration,policy versions,clock,queue order and
commit watermark. Directory headers,per-column lengths and checksums are explicit.
Do not memcpy native Swift structs/padding as a cross-version save format. On the
supported little-endian scalar representation,bulk column copying may be possible;
that remains a validated encoding path,not an ABI promise.

WAL contains accepted external commands and nondeterministic inputs(policy/rate/
random-seed material),commit order and sufficient commit-watermark information.
Deterministic autonomous events can be replayed from the checkpoint under the exact
recorded engine/schema version. Do not log every automatically regenerated movement
frame. Only a verified deterministic event engine permits this reduction. An engine
upgrade first migrates/validates a checkpoint before replaying with changed semantics.

Atomic durable boundary: prepare all plans and fixed WAL records; append complete
framed transaction groups with length,sequence andchecksum; a single storage worker
publishes durable ACK after required OS synchronization; expose durableCommit separately
from inMemoryCommit. Until ACK,UI must not say the operation is safely saved. Crash
recovery replays only complete verified committed groups. A truncated tail is retained
for diagnosis and excluded,not interpreted as committed or silently rewritten.

Snapshots use a stable committed epoch with bounded page/version staging. Writer
and simulation communicate via bounded queues and generation/ACK; no concurrent
read of mutating Swift arrays. When the old-page reserve fills,producer yields/
backpressures rather than allocating a full-world snapshot. Disk encoding/sync is
off the UI thread. Persistent ledger compaction copies records/index pages without
changing financial meaning,then atomically publishes the new manifest after verification.
Checksums detect corruption,not malicious authentication. Process-kill tests do not
prove every power-loss/storage-controller scenario; those limits remain documented.

Stage3 failure matrix: kill before/after each framed write,commit marker,flush,
checkpoint-page write,manifest replacement and old-generation retirement; inject
short write,disk full,corrupt length/checksum,bad ID/overflow and incompatible version.
Compare continuous execution with checkpoint+replay,including blocked-event prefixes,
partial payments and not-yet-durable UI state. No automatic deletion of financial rows.

### Approval issue A1: fixed storage versus unlimited detailed history

Finite fixed storage cannot preserve an unbounded arbitrary sequence of distinct
financial records losslessly. Compression does not remove this information bound.
At20MB/day even the proposed3GiB ledger/index allocation lasts only about161 game
days before other variation/reserves; it is not an infinite-campaign solution.

The two owner requirements, "fixed total storage for any campaign length" and
"no deletion of any financial record", need an explicit interpretation. DEFAULT
until approved: retain every financial record, use hard local quotas, and backpressure
before exhaustion. This preserves correctness but does NOT satisfy unlimited play.
Possible approved extension: verified immutable external archives (local cap then
excludes external storage),or an explicitly authorized change of history semantics
that replaces detail with aggregates. Neither deletion nor an external service is
authorized by this ADR itself. Storage-unlimited acceptance is therefore BLOCKED,
not green. Operational-detail retention cannot be used to silently relabel/delete
financial proofs. This is the principal product decision needed before Stage3.

## 11. CI/device acceptance and evidence policy

CI gates correctness/format/structural budgets,not elapsed-wall thresholds. Compiler,
TSan and the original12 fail-stops remain enabled. Text/hash guards are retained
for the unchanged baseline during Stage0/1; differential behavioral tests supplement
them. Replacement during production refactoring must cover the same property before
a guard is retired,not disable it to get a green build. Operational job timeouts
are resource limits and are not marketed as microsecond performance gates.

Before changed semantics: exact legacy transcripts for all existing fixtures through
100k,including result/error precedence and prefix behavior. Stage2 adds permanent-ID,
wheel/cancel/reuse tests. After approved billing semantics: versioned oracle checks
at1M,checkpoint+replay equivalence,number/time partition invariance,injected failure
and process-kill recovery. Independent aggregate/accounting totals must equal detailed
reference results where the semantics overlap. Do not count parameter cases as
additional named tests or call a C microkernel a production integration test.

Per-change metrics: logical/physical bytes,complete-path allocator counts,full snapshot
size and changed-page count,segment/WAL/index growth/day,instruction counts when
supported. Instructions vary with compiler/CPU/input layout; they are controlled
observations,not universally deterministic across machines. Absent counters remain
unavailable. Host timing may be recorded to find regressions but does not pass/fail
on the user's device budget. All spikes and calibration data are retained.

PhysicaliPhone17ProMax gates each run30minutes at default speed with declared activity:
1M assets,5trips/day/asset implies10M departure+arrival events/day BEFORE settlement,
period-close,save and other features. Accept100k then250k then1M; record feature matrix,
active fraction,contracts,payment lag,history age,event density and game speed.
Collect frame p99,simulation thread CPU/core residency,thermalState transitions,
energy,phys_footprint andsave-visible interruption. Include warm/cold/recovery and
app background/resume cases. Do not infer these from macOSCI or theoreticalquarterCPU.
At0.5us x10M events,5core-seconds/day divided by0.25core gives20seconds/day ONLY
for that assumed event work; not an actual device speed or thermal prediction.

Full release/device evidence bundles are milestone artifacts. Routine commits keep
CI logs,source/generated identities and compact budget summaries; Stage0 raw acquisition
is retained once as the requested diagnostic milestone,not repeated to hunt green timing.
No code changes on historical branches;PROJECT_CONTINUITY has one current section,
with append-only handoff/execution history inDocs/History and daily records.

## 12. Stage delivery and approval gates

| Stage | Deliverable / truth condition | This preparation |
|---|---|---|
|0|One V4/event acquisition; scoped verdict; physical fallback if required and available; no invented attribution|Instrumented disposable build; source unchanged; result recorded separately after run. Physical device not presumed.|
|1|ADR with measured layout prototype at1M and2M margin; owner approval before production|This ADR+Experiments/R005; proposed billing/retention need approval.|
|2|Permanent identity+representation+generic wheel; exact old transcripts|NOT implemented.|
|3|Approved accrual/periodic invoices+durable storage/replay+crash matrix|NOT implemented;A1 unresolved.|
|4|Read model+thin iPhone aviation slice;100k/250k/1M device gates|NOT implemented.|

Approval request: confirm periodic contract billing while retaining exact arrival
accrual,choose A1's storage/retention interpretation,and approve layout/workload quotas.
Until then do not merge a production replacement or claim R005 complete.

## Primary references and source context

- Current contracts:AGENTS.md;Docs/Design/ATOMIC-FINANCE-R004.md;Sources/NexoraFinance/FinanceStore.swift;Sources/NexoraSimulation/ArrivalHeap.swift.
- AppleCPU profiling (instructions versus stalls):https://developer.apple.com/videos/play/wwdc2025/308/
- XNU runnable timer includes running:https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/thread.h
- XNU process aggregation/optionalPMU:https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c
- XNU rusage implementation reference:https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_resource.c
- SQLite atomic-commit/WAL design references,not an implementation selection:https://www.sqlite.org/atomiccommit.html and https://www.sqlite.org/wal.html
- MetalGPU-driven culling reference:https://developer.apple.com/documentation/metal/encoding-indirect-command-buffers-on-the-gpu

Platform references inform the design; no Apple/SQLite implementation source is
copied into NEXORA. Main-branch documentation is not proof of the runner's exact
kernel build; record that separately before assigning counter units or causes.
