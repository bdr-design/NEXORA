# R005 — bounded epoch ownership after measured failures

Status: PROPOSED / NOT_IMPLEMENTED / NOT_APPROVED_FOR_PRODUCTION.
2026-10-07. This continues the permitted R001 owners. It does not replace a
failed result, change C, authorize Stage2–4, or introduce a new game/domain.

## Problem established by current evidence

Observer source22e5428d/treee5fbde7e has fresh A/B and Debug/Release/TSan S/H1M
K1–K10 proof37563538884. Qualified H1M5-save37567830698 still fails:
overhead1.3822529614>1.10. Subtracting all53.916214ms measured copy would give
only an optimistic1.2740145515. Therefore reducing copy time alone is insufficient.
Paired H and S samples vary in sign; they do not establish one precise cause.

The current full spare image is a separate feasibility failure. H1M main-world
owned capacities are210772320B, excluding allocator headers, StageCState,
writer, restore worlds and UI. H live payload100.5MB and another full100.5MB
spare already total201MB before metadata. A's live105.408880B/asset PASS does
not cover saving. The fixed128B target/200B hard cap remain unchanged.

No field narrowing, dropped obligation, weakened invariant, hidden setup pool,
or changed normalizer can solve those requirements legitimately.

## Candidate distinction and estimates before any hot edit

| Candidate | Allocation estimate at H1M | Simulation-thread consequence | Scope |
| --- | --- | --- | --- |
| Current full spare | measured owned210772320B | first-touch copy and ownership checks; no capacity backpressure | functional prototype; hard memory failure |
| Cold-only bounded spare | rough owned191.82MB before new metadata, headers and command reservations:210772320−20000000+1048576 | cold-write credit/reservation; hot advance keeps its current spare/guards | possible hard-cap reduction, still above128B target; not a C solution |
| All-page bounded spare | approximate live105.41MB+1MiB staging before complete additional structures | arbitrary dirty pages can exhaust staging inside advance; cannot preserve current public behavior by hiding a wait | broad unproved redesign, not ready for integration |
| Durable immutable page store | memory/storage unknown until an encoded-page micro | bounded transaction/page preparation and explicit writer progress; save publication may avoid whole-image serialization | architectural research candidate only; v2/B/retention compatibility unresolved |

All rows after the first are arithmetic/hypotheses, not measured Swift memory,
speed, physical footprint, or a new accepted profile. Existing4MiB production
reserve subdivisions remain proposed; do not spend the same1MiB twice.
State cardinality E/G, maps, outstanding requests, metadata, both generations,
writer scratch and compaction slack must appear in a complete formula.

## Cold-only ownership micro to resolve one concrete question

Cold fields are not assumed immutable. A user command, recovery, or next operation
can change them. The bounded cold candidate retains all20bytes/asset and exactly
the current canonical v2 payload; it proposes no semantic truncation.

One simulation owner would reserve an owner-local spare slot before a protected
cold page changes. One writer would serialize frozen asset pages in canonical
order and acknowledge only a contiguous prefix after dropping every payload
reference to those pages. A single epoch-tagged atomic cursor could report this
prefix; it is not one lock/task/actor per asset. Relaxed metadata alone is not a
payload synchronization mechanism. Existing writer completion still requires
release/acquire and a matching owner/epoch token.

An acknowledgement counter is insufficient on its own. Current spareRoot and
spareLeaves intentionally retain old value roots until completion. They would
prevent an old payload held in a bounded slot from becoming unique for reuse.
The micro must explicitly prove transfer/drop of root/leaf/page references,
including writer-local temporaries and rejected/cancelled handoffs. It must not
infer uniqueness from elapsed time or disable Swift exclusivity/COW checks.

The proposed micro has one cold buffer, not another World or economic model.
Use UInt64 word pages with the current20-byte canonical cold encoding. Test
one/two spare slots first at257/4096, then optional100k; retain three epochs.
Full page capacity for partial last pages must be reserved during setup so a
recycled partial page cannot allocate when reused for a full page. Charge that
capacity, slot/page maps, directories, cursor and headers explicitly.

| Condition | Required behavior/evidence before implementation |
| --- | --- |
| Writer held; one slot already used; second distinct protected page requested | reservation rejects before any payload/control/WAL write; previous accepted prefix stays exact |
| Several fields/pages form one command | reserve every required slot before the first mutation; no partial command |
| Writer releases a prefix before first live copy | prove shared root/leaf/page metadata no longer causes a hidden COW allocation |
| Live copy occurs before writer releases that page | recycle its old payload only after all writer/root aliases have gone |
| Partial final page later reused for a full page | zero mutation allocation; exact canonical length and padding |
| Writer error or cancellation | no forged release credit, early reuse, or false successful save |
| Stale/foreign epoch and owner | reject with unchanged bytes; cursor cannot authorize another epoch |
| End of epoch and next freeze | all live/pool buffers unique as required, counted and reusable without service allocation |

Require independent frozen/live/recovered digests and order; Release calibrated
allocation observations and positive controls; Debug/Release/TSan. Unavailable
TSan allocator counters remain null. Measure advance, service, writer, loop and
setup separately. Only then can this be an actual source candidate.

## Backpressure cannot be disguised as performance

With K spare pages and a stalled writer, requests touching K+1 distinct protected
pages require additional storage or rejection/deferment. An unbounded wait inside
advance is incompatible with fixed latency. Moving that wait into service or UI
does not remove the whole-loop cost. This is a concrete capacity case the micro
must exercise, not evidence that a proposed page store has solved it.

The current acceptance runners require exact transcripts and existing failure/
progress behavior. No new IO stop reason, silently delayed economic operation,
or sampling/cadence change is authorized as a way to pass their gates. A cold
transaction reservation must fit existing preparation semantics; any wider
public-contract change is a separate proposed decision, not an automatic patch.

Likewise, changing to a durable immutable-page format requires new recovery,
checksums/canonical roots, retention quotas, corrupt/torn cases and compaction
proof. The accepted B artifacts bind the current source/format; their numbers
cannot be reused to certify another store. No financial history retirement or
loss of detail is approved by this note.

## Safe progression

Finish the separate1M writer-contention study37568520463 without changing actual
runtime. Keep every unfavorable result. Then select a bounded ownership micro
from evidence and the complete allocation/simulation estimate, not from the
deadline. A promising micro requires reviewed integration, fresh A/B and S/H
Debug/Release/TSan1M K1–K10, and actual C1M100 for the named layout. C<=1.10,
begin/advance/allocation limits and the owner's realism/smoothness remain fixed.

No result file, main merge, Stage2–4, app/IPA or device acceptance follows from
this proposal. Final device remains17 Pro Max100k→250k→1M with actual gameplay,
UI/save interaction, frame/input, memory, CPU and thermal evidence.

Primary language references checked2026-10-07, no implementation code copied:
https://docs.swift.org/latest/documentation/the-swift-programming-language/declarations/
https://docs.swift.org/latest/documentation/the-swift-programming-language/memorysafety/
https://www.swift.org/blog/swift-5-exclusivity/
Borrowing/consuming specify parameter ownership; a copyable value may still have
other aliases, so adding consuming alone does not prove a page reusable. Swift's
exclusive modification rules remain enabled in Release. Language semantics are
not measured Swift storage performance or evidence of this proposed algorithm.
