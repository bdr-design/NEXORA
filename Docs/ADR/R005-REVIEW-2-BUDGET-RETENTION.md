# R005 design review 2 — headroom, Swift proof and bounded retention

Status: PROPOSED / NOT APPROVED FOR PRODUCTION.
Date: 2026-09-30, Asia/Riyadh. Repository: bdr-design/NEXORA only.
Reviewed branch: diagnostic/r005-design-1m-20260930.
Parent HEAD: 40b593b43bb921dbd477abffa8a6ae001495b2ef.
Main verified at 38ce39cf9322f47e4def5f6eddb425c5a66ea7f9.
AGENTS.md and PROJECT_CONTINUITY.md were read before this review. Excluded content
was not opened. No source, tests, workflows or financial records are changed; no history is rewritten.

This is a required companion to R005-MILLION-ASSET-DESIGN.md and
R005-BUDGET-ADDENDUM.md. It narrows their readiness claims and supersedes the 8 GiB
proposal as a default-storage recommendation. It does NOT replace the measured C
prototype or change the owner's 128/200-byte budgets. The consultant's supplied
recommendation is review input, not the owner's approval of lossy retention.

## 1. Findings that change the approval boundary

The existing 127.352328 B/asset total is a design reservation, not a measured Swift
engine. It includes future fixed pools and a ContractID map as well as the measured
C row kernel. It is too close to 128 to certify room for unimplemented behavior.
The exact remaining target headroom at N=1,000,000 is 647,672 bytes, or
0.647672 B/asset; headroom to the hard cap is 72,647,672 bytes. These are different
limits, not permission to call 167 B a 128 B result.

The C model implements a storage/update kernel. It reserves event arrays but has
no wheel implementation. Commutative accrual and independent asset completion
make the final state insensitive to traversal permutation in this fixture. Its
checksum/partition tests are useful for coverage and state-update consistency,
but do not prove scheduler ordering, atomic multi-ledger semantics, or Swift costs.
No existing test or historical claim of its actual scope is removed.

R005 production approval therefore still needs a Swift-path representation test,
order-sensitive scheduler proof, explicit active-state multiplicities, and a
retention contract that distinguishes exact totals from recoverable detail.
This review does not implement those missing components or advertise them as tested.

## 2. Budget arithmetic and candidate reductions

The current full proposed formula remains:

    B = 80*N + 40*E + 48*G + ceil(N/8) + 33,024 + 4,194,304

N is asset capacity, E is allocated event-node capacity, and G is concurrently
resident accrual-group capacity. The normal profile assumes G=ceil(N/16), not a
universal number of contracts. More policy/currency/period splits increase G.

| Profile at 1M assets and G=62,500 | Current proposal | Candidate with 8E scratch removed |
|---|---:|---:|
| E=N | 127,352,328 B / 127.352328 B per asset | 119,352,328 B / 119.352328 B per asset |
| E=2N | 167,352,328 B / 167.352328 B per asset | 151,352,328 B / 151.352328 B per asset |

The right-hand column is arithmetic only. No new allocations, scheduler, latency or
Swift results have been measured for it. It assumes the same fixed workspace;
any additional cursors/run descriptors must be added before accepting the number.
The measured C result stays 122,658,024 B at 1M/E=N, without the proposed future
pools/map. It is neither replaced nor relabeled by these candidate totals.

The 40E region is 32E event payload plus 8E ordering scratch, not a 40-byte event
record alone. The existing payload is due64, sequence64, asset32, generation32,
next32 and packed metadata32. metadata is intended to identify bucket/kind;
removing it requires a proved replacement for dispatch/cancellation, not just
zero use by the incomplete C kernel.

First candidate to compare in a disposable Swift scheduler: a bounded, resumable
intrusive stable merge sort using existing next links, versus the current proposed
index/radix scratch. It may remove two UInt32 scratch arrays without narrowing
time or sequence. It must count all sorting/cascade work and preserve cancellation,
failed-head retention, deterministic ties and partial-progress behavior. It can
cost more instructions or memory accesses; lower bytes do not imply faster events.
Do not select it from the arithmetic table alone.

### Width and price reductions are conditional, not free savings

* Retain UInt64 OperationID and deterministic global sequence in the approved
  baseline. UInt32 counts only 4,294,967,295 nonzero steps: at 10M scheduled events
  per game day that is about 429.497 game days. A timestamp in UInt32 seconds spans
  about 136.10 years, not an arbitrary campaign. Epoch/relative representations need
  checked reconstruction, horizons, cancellation/reuse and overflow tests. They
  cannot silently narrow accepted legacy inputs.
* A UInt32 flight duration with UInt64 due time could reconstruct departure time
  for a bounded duration profile. This is a candidate with an explicit maximum;
  exceptional long durations need counted storage or documented rejection.
* A UInt32 completion counter also needs overflow behavior. Five trips per day
  make exhaustion remote in that workload, but do not make UInt64 legacy boundary
  tests or arbitrary command streams disappear. No wrapping or hidden saturation.
* Do not delete fareMinor and read the current mutable policy at arrival. An active
  flight retains departure-time terms. Shared immutable terms can replace a stored
  amount only if all determining inputs are captured, old versions remain available,
  rounding is identical, and version/mapping/cache memory is budgeted. A new 4-byte
  terms index does not save the full 8-byte amount without other proven reuse.

Approval must report G/N and E/N limits, stale/cancelled nodes, credit backlog,
policy-version cardinality, maps, sort workspace and peak checkpoint staging.
GPU/catalog/media memory remains separately visible in total physical footprint;
it is not silently discarded from application-memory acceptance. Future domains
must use the same complete budget accounting, not another uncounted pool.

## 3. The Swift and ordering proof still required

The C model is retained as a reference and preliminary layout experiment. A
matching disposable Swift implementation must allocate all intended columns,
initialize/touch them, run the same update workload at 100k/250k/1M/2M, and report
MemoryLayout.stride, requested capacity and observed physical footprint separately.
Swift arrays/descriptors, sharing/COW, runtime overhead and temporary buffers must
not be inferred from C sizeof or the C owner's allocation-call counter.

Run Debug/Release and allocator-observed complete paths. Report allocations during
creation, events, sorting/cascades, commit output, checkpoint staging and teardown.
MemoryLayout is not a process-heap profiler, and owner-local counters are not global
allocation interposition. PMU unavailability stays unavailable; do not derive a
Swift instruction or device timing result from C or a documentation calculation.

The order oracle must compare emitted ordered records, not only final sums. A
minimal sensitivity control starts with cash=5 and equal-tick events ordered by
sequence: credit 5 (sequence 1), debit 8 (sequence 2). Correct order ends at cash=2;
reversing the events rejects/blocks the debit first. A test must deliberately
reverse a tie and fail, demonstrating that its oracle detects the defect.

Extend this to period-close versus arrival, conflicting debits, injected failures
with committed prefixes, cancellations, generation reuse, cascades, far deadlines,
empty jumps, and events created by other events. Compare against an independent
sorted-list reference across count budgets 1/7/31/256/1024 and an injected deadline
clock. Stop/resume may change chunk boundaries but not the ordered transcript or
accepted/rejected operations. Existing compiler/TSan/fail-stop gates stay enabled.
These are acceptance requirements, not new tests executed in this review.

## 4. Additional interpretation of the existing raw study only

No new hosted benchmark or acquisition was run. Existing artifact 11115497993 from
run 36754290347 is SHA-256 pinned to:
6eb273848b9e37eb074dac106e6bf86269cbbfe4afb1337a1d2d8f286dd9354e.
Its three V4 files and event file were independently rehashed and reread in this
review. Counts remain 359,640 measured batches, 179,820 in V4 mode, 35 total >5ms
observations and 13 of those in V4 mode. This is not the old 22-spike dataset.

The 13 V4 spikes have positive raw runnable endpoints. Eleven have enclosing
thread CPU below 1ms; one is about 1.080666ms versus 6.808666ms elapsed; another is
5.114875ms versus 5.017459ms elapsed. These are descriptive comparisons, not a
runnable-based causal classification. The data contains no hardware timebase
record, and process endpoints enclose different/wider windows than the wall bracket.

Apple's XNU reference defines runnable_timer as including running time;
task_power_info_locked aggregates it across task threads, and fill_task_rusage
exports that aggregate. Therefore runnableRaw is NOT queue-wait-only. Do not
subtract it directly from wallNS or threadCPUNS, infer a missing timebase, or label
all 13 causes from it. The inspected public source is a semantic reference, not
attestation of the exact custom VM kernel binary used by the runner. Instructions
and cycles remain unavailable; the physical fallback remains unperformed.

In the separate event-start study the largest allocation bracket is 30,083 ns,
not a universal bound. In 20k/event-sample 3/batch 67, the gap between starts 17,261
and 17,262 (zero-based) is 3,536,625 ns within a 3,760,750 ns wall bracket: 94.04%.
That batch's allocation bracket is 250 ns and enclosing thread CPU is 244,750 ns.
The other within-batch next-start gaps sum to 220,417 ns; the largest is 13,042 ns.
This localizes most of THAT observation outside its initial allocation bracket.
It does not identify a function inside the gap, measure the last event separately,
or exclude allocations as a mechanism in other samples/historical spikes. Start
gaps include observer/control work and can contain descheduling.

Keep the bounded diagnostic verdict INCONCLUSIVE. No origins change, no repeat
hosted acquisition, and no fabricated off-CPU or physical-device certification.

## 5. Retention proposal — exact money, explicitly bounded detail

The consultant recommends summarization and optional external export. This direction
is a proposal for approval, not authorization to delete existing financial records.
Replace the 8 GiB suggested default with a quota-selection experiment. Test total
local quotas of 256/512/1024 MiB against real encoded checkpoints, WAL, indexes,
open-item backlog, summary trees, media and compaction slack. None is the approved
default yet, and an infeasible quota/profile must be reported as infeasible.

The following contract is proposed:

1. Never approximate money. Maintain checked debit/credit totals, balances, entity,
   account and currency separation. New/late corrections append explicitly to the
   relevant close/revision; they cannot silently rewrite a closed financial fact.
2. Keep detailed records for a moving, byte-budgeted window. Candidate test windows
   are 3/7/30 game days, not an unconditional retention promise. Only settled,
   finalized periods without open items, disputes, pending reversals or undurable
   work may be condensed. Open-item detail remains authoritative in paged storage.
3. Use bounded daily/monthly/yearly summary slots, eventually coalescing older
   closed periods into exact cumulative totals for an explicit wider interval.
   Exact amounts survive; original per-trip and per-period drill-down eventually
   does not. The UI must show available granularity and the summary interval.
4. Canonical summary input order and encoding, child coverage/counts, totals and
   content commitments must be validated before atomic publication. Require debit,
   credit, balances and counts to match an independent detailed oracle; detect
   missing/duplicate children, currency mixing and interrupted publication.
5. Keep leaf block hashes with detailed blocks while retained. Coalesced levels
   retain bounded parent/root commitments, not an ever-growing list of all leaf
   hashes. A root cannot reconstruct removed detail or independently verify its
   arithmetic without the needed original/proof data. Verification occurs before
   approved detail retirement; external proof/detail export is optional.
6. After manifest publication and verification, reclaim only the explicitly
   authorized closed detail. Preserve old/current generations within measured
   compaction slack and test kills at each step. Until owner approval, reclamation
   of financial detail remains forbidden. Checksums are not power-loss guarantees.

### Important feasibility limits

"Exact totals for each original period forever" plus "a hash for every summarized
block forever" is STILL unbounded storage. The bounded contract must permit losing
older period granularity while retaining exact wider-interval/cumulative amounts.
Keeping all original periods requires unbounded/external storage; it is not solved
by calling them summaries. Finite-width monetary totals also need checked overflow;
"forever" cannot authorize silent wrap or saturation.

Likewise, never summarizing an unbounded population of open obligations is
incompatible with fixed local storage. A design must bound live exposure/cardinality
or backpressure issuance of NEW credit-bearing operations before capacity is
exceeded, while allowing settlement and other safe work. This is not permission to
forgive debt or force every player to export. Arbitrarily growing unpaid debt or
arbitrary protected media cannot have an unlimited fixed-space guarantee.

At the proposed normal 62,500 invoices/day, 64-byte invoice payload alone is
120,000,000 bytes for 30 unsettled days and 1,460,000,000 bytes for 365 days,
before indexes, journals and attachments. The earlier 20,000,000 B/day closed-flow
figure includes an UNMEASURED 25% framing/index allowance. Seven detailed days at
that estimate is 140MB; thirty is 600MB. These are formula examples, not measured
storage growth or a reason to approve a particular default quota.

Stage-1 disposable serialization experiments must measure actual bytes/day, real
compressibility, active-group/payment-lag extremes, correction frequency, retained
hash/summary growth and compaction peaks. Checkpoint/scheduler/policy versions and
media must share the same admitted total. Select a default only after these results.

## 6. Result and next bounded action

This revision is documentation plus offline analysis. Production source, original
tests, workflows and financial data are unchanged; no model or retention policy is
approved or implemented. R004 bounded investigation stays closed as an iteration,
not scientifically resolved. Do not hold design work hostage to further VM repeats.

Next design evidence: one matching Swift representation candidate and an
order-sensitive scheduler oracle, then a disposable encoded-retention workload.
Use those to select the scheduler workspace and local quota. Keep the owner's
128/200B, allocation, device event/CPU/save and staged iPhone gates unchanged.
No HR/maintenance/delivery expansion and no production R005 before approval.

Primary semantic references (inspected, not proof of the running VM binary):
- https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/thread.h
- https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c
- https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c
- https://developer.apple.com/documentation/swift/memorylayout
