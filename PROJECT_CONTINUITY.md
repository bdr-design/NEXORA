# Resumed C fix — 2026-10-05

Owner says «حله!» after the alternatives were presented. Live base HEAD rechecked:
210875d0e96d4a4e0028d0997ee2c6de63954b88, tree e2ee8de6a88791c5b3065e025fe58933000b3cf2.
Resume bounded profiling on the same permitted branch; AGENTS/current continuity
and original directive reread. No production change or threshold relaxation.
Next: read uninstrumented S 1M/5-save phase totals and separate advisory stack
sample. Counters are outside advance/allocation timing and must reconcile every
call to unchanged acceptance totals. No performance fix is yet claimed.
Keep the entire earlier history below. New full acceptance attempts: 0 of 2.

---

# Execution candidate — 2026-10-05

Owner authorized the recommended bounded path with «نفذ بدقه».
Base live HEAD: 647d9c2559222f094b01f1341f4c5444c1b1e96b. Existing branch only.
A/C evidence gates and before/always-after CI guards are corrected as candidates.
Apple micro run 37308440794 on 1abc2fa11bd2160672b1467ed6c392e528fd7ecd is FAILED
at cleanup only (DYLD observer inherited by arm64e rm); measurement commands,
Debug/Release builds, exact A/B reuse and before/after guards completed.
Artifact 11344981195 is preserved with ZIP SHA-256
c52baa28d44246931581d073782afe455b241d71c642f0fa30f4e9d5d912c812.
Recovery run 37309407651 SUCCESS; artifact 11345341757 SHA-256
5594657c03d6ea67a99621a2b672c42b5b3bb48f96f8b38d5d34d94acb875769. Original micro
source remains 1abc2fa and its run stays FAILED. S diagnostic ratio=1.444214155,
H=1.229320289; zero paired allocation violations. Copy alone is insufficient.
Candidate micro run 37310351003 SUCCESS on 1c0c87151a0a3f39c0967da4c0f5ba6c5ab68547;
artifact 11345188872 SHA-256
0db7ad3cee68594f73c936884b68b8bab54bd24344c8409950ccfb2240f2b0b4.
Debug/Release transport lifecycle + S/H 100k restore PASS; zero paired allocation
violations. S diagnostic ratio=1.347911485, advance p99=1747583 ns; H=1.617218224,
p99=1755709 ns. Thus C is OPEN on both layouts despite workflow SUCCESS.
Candidate transport is functionally tested but NOT accepted as a performance fix.
Bounded TSan run 37311166676 SUCCESS on 2f8bd8b8b749562b5b88a84b3858c8a44dcb4b88;
artifact 11346245823 SHA-256
96f24e025c67875c5a8075f8b5da241433f97f09cc64affa3e16cbc371fb0f8a.
Queue/writer lifecycle + S/H 100k restore and guards PASS, empty TSan stderr.
This is not 1M K1-K10 or 100-save C acceptance for the candidate.
Next: owner chooses bounded profiling (recommended), chunk ownership/size redesign,
or rollback of unproven transport while retaining fixed gates. Costs and scope are
in Docs/Daily/2026-10-05-R005-EXECUTION.md; raw JSONs in
Experiments/R005Swift/Evidence/20261005 and review-20261005.json.
No more overhead attempts or 100-save campaign until the owner chooses a next path.
Keep candidate source and raw metrics reviewable; do not merge into production.
All thresholds remain unchanged.
See Docs/Daily/2026-10-05-R005-EXECUTION.md for owners, paths, estimates and evidence reuse.
No production changes/merge/IPA or device acceptance. Earlier failures stay FAILED.

---

# Current review checkpoint — 2026-10-05

Repository bdr-design/NEXORA, branch diagnostic/r005-design-1m-20260930.
Reviewed live source: fa9c44656d6a7544f5cd0255781c64fde3e9ce1f;
tree 13d773e230a8858dedc083280b80d35127b0a2b8;
main unchanged at 38ce39cf9322f47e4def5f6eddb425c5a66ea7f9.
Read AGENTS.md and recheck live HEAD before changing anything. All three denied
branches remain excluded; their implementation was not opened or used.

Latest Apple runs: 36875130411 SUCCESS, 36875130222 FAILED in C on S.
Downloaded artifact 11170911262 ZIP SHA-256:
6517060278e24e0a8b3bdb0db0476ebe719543eac293bcb2b903dc22fc356d71.
A chose S (H/S=0.7855310255832999); A measured allocation maxima were all zero.
B's 60-record and existing crash proof passed.
C/S: begin p99 15125 ns, advance p99 1018375 ns / 35904 samples,
100 saves; overheadRatio 1.5162503372173357 > 1.10. C remains OPEN.
The failure is now recorded in Experiments/R005Swift/failures.json.

Review findings and exact scope: [2026-10-05 review](Docs/Daily/2026-10-05-R005-REVIEW.md).
Two evidence gaps reproduced with synthetic inputs against the real evaluators:
A nonzero allocations can fall back to S and still emit PASS;
C compares independent allocation/chunk maxima rather than paired per-advance bounds.
These findings do NOT establish an actual allocation violation in the latest Apple run.
The executable workflow also skipped its post-C source guard on failure; direct
comparison, local guard and companion design CI still confirm production unchanged.
A B manifest torn-tail/resume-write risk was identified by source review only.

104 local Python tests and baseline/source guards passed. All 183 fetched files
matched the reviewed Git blob hashes and file modes. No Swift/Xcode toolchain is
available in this review environment; no fresh Swift/TSan/device result is claimed.
Review publication changes documentation and the failure registry only.

Two consecutive overhead failures already exist (36864229515, 36875130222).
No third full campaign or hot-path edit was started. Present the bounded alternatives
in the review to the owner before another overhead attempt. Recommended next scope:
correct evidence gates, then a short copy/enqueue/hooks/writer micro-test. Do not
assume copy alone explains overhead: subtracting all recorded barrier time
arithmetically still leaves a ratio about 1.351 (diagnostic, not causal/predictive).
Keep the 1.10 gate unchanged and name S or H explicitly at closure.

No production merge, final R005 acceptance, iOS app/IPA, FPS or thermal certification.
Device target remains iPhone 17 Pro Max; newer design target 1M/capacity 2M supersedes
the older scale wording in Docs/REQUIREMENTS.md, without waiving full-feature goals.
The sections below are historical updates; this checkpoint is current.
Chat disconnect cause is unverified. Resume by checking live HEAD and this file;
do not rely on chat memory, promise background work, or repeat an uncertain write.

---

# R005 C evidence scope and predeclared numeric reporting

Run 36864229515 on `f70c0ea7d8efab06379b4eb07182493bf67fea6b`
selected **S**: H/S=0.8512443132482774, S1M=109.1513935 ns/event,
H1M=92.914503 ns/event, H owned=100.748672 B/asset. The immediately preceding
run 36855849336 selected **H** at H/S=0.7297648494141507. Therefore hosted A
selection is empirically not stable across these runs. Any C closure must name
its variant explicitly; S-only evidence is not H runtime evidence.

On 36864229515 the selected-layout 100k smoke passed on S, the allocation probe
measured asset-record producer allocations=1, preallocated queue 10,000 pushes=0,
and control-record p99=1,000 ns over 1,000 samples. K1-K10 passed at 1M in
Debug/Release/TSan on S. Full 1M/100-save measurement then failed only at the
unchanged overheadRatio <=1.10 gate. The old runner did not persist the exact
failing ratio.

Before the next measurement, numerical gates are explicitly predeclared:
beginSave p99 <=100,000 ns; advance-during-save p99 <=1,100,000 ns;
overheadRatio <=1.10; idle allocations/advance ==0; saving allocations/advance
<= barrier chunks emitted in that advance. Control-record probe p99 uses the
same 100,000 ns ceiling. Result JSON must include sample counts and signed margins.
snapshotBytes, writeNS, restoreNS, peakQueuedBytes and barrier byte/time series
are diagnostic-only measurements from the directive and are not assigned
post-hoc acceptance thresholds.

Recommendation boundary before production: because A has flipped between S and H,
either the owner fixes one production layout and C is closed explicitly on that
layout, or the other layout must receive equivalent C runtime proof. Do not claim
one variant's C evidence for the other.

# R005 Stage C selected-layout execution — H support candidate

Run 36855849336 on source `2b09f59c55ce3005849af13a00826438bbabbba4`
is preserved as FAILED. A/TSan/B and C K1-K10 passed, but current A measured
H/S=0.7297648494141507 with H owned 100.748672 B/asset, so the directive selected
H. The S-only C launcher correctly cannot be used as proof for that result.

This candidate does not force S or alter the <=0.75 decision rule. C now follows
the A artifact: S keeps the existing path; H gets the same chunk-before-first-write
barrier, one-allocation producer record, preallocated queue, writer-side SHA-256,
v2 snapshot/footer, WAL chain recovery, K1-K10, and 1M/100-save thresholds.
A selected-layout allocation probe plus exact 100k snapshot/restore smoke runs
immediately after A, before the expensive TSan/B/C campaign.

Hot-path estimate before writing: STAGE_C-disabled A builds remain free of these
hooks. In the C build, idle H advance adds only nil/capturing barrier checks and
targets zero allocations; during an active save each first-touched chunk is allowed
exactly one producer allocation, with hashing and file I/O off the simulation
thread. No production source/main/iPhone acceptance is changed.

# R005 Stage C allocation-root correction — candidate, not yet accepted

Live source before this change: `5a6e83541092970625713e386751e87dc09834cf`.
Run 36847772963 preserved as FAILED after A/TSan/B and C K1-K10 had passed;
the 1M/100-save measurement failed only at the unchanged gate
`allocations on saving advance <= barrier chunks`.

The producer-side source is bounded: Stage C built each record as Foundation
Data and hashed it before enqueue, while AsyncStream also buffered producer-side
items. This correction does not relax the gate. It builds each record in one
pre-reserved [UInt8] buffer, moves SHA-256 to the background writer, replaces
AsyncStream with a preallocated Mutex queue, and removes literal-array/control
serialization overhead. UnsafeMutable remains forbidden; read-only Unsafe access
stays confined to Snapshot.swift as required.

New evidence is mandatory before acceptance: a release allocation probe must show
one producer allocation for one asset record and zero producer allocations for
10,000 preallocated-queue submissions; the normal 1M/100-save run records barrier
bytes and barrier time per save. K1-K10, Debug/Release/TSan, A/B, production guards,
and all original thresholds remain unchanged. No production source/main/iPhone
claim is changed.

# R005 proof closure — A/B accepted on green source; C candidate starts

The corrected full-layout A and the full B proof both passed on Apple CI source
`670d462016f12b490f3dd475106970bc0f17fbf1`.
Swift run 36837182928 and companion existing-gates run 36837182920 both completed
SUCCESS. Artifact 11149973992 was downloaded and verified locally as ZIP SHA-256
`2de69b88da75701d7091aab324077d153b863e652c03e0e4c431543f9e0b149d`.

Final accepted A decision for this stage source:
- S @1M: 96.160704 owned B/asset; median 99.2767825 ns/event.
- H @1M: 100.748672 owned B/asset; median 83.4846225 ns/event.
- H/S = 0.8409279631921995, so H does NOT meet the required <=0.75*S threshold.
- all measured allocation maxima/advance were zero; corrected layout/order/mutant
  and TSan gates passed. Chosen layout is **S** by the directive rule.
STAGE005-A.json SHA-256:
`7618f3a0bcc1dfe4489c361153a3d1463f1e761aac82886cd58bfda140c0317a`.

Accepted B:
- exactly 60 day records (30 G16/W7 + 30 G1/W7);
- G16 BdayMax 8,000,016; S30 99,840; Omax 120,016 bytes;
- G1/W7 BdayMax 128,000,016; S30 99,840; Omax 1,920,016 bytes;
- exact final disk totals pass and all S1-S5 kills pass in Debug/Release/TSan.
STAGE005-B.json SHA-256:
`9f01ed06a76bd37a9d5e21d7e048a4c2336686edb04aaa45963b00ec30f590c2`.
A quota-only G1/W3 aggregate is now added because the directive's final quota table
requires it; it does not add rows to the 60-record B matrix.

Stage C candidate now targets the chosen S layout only. It is compiled behind
`STAGE_C`, so normal A builds have no save-hook hot-path code. It adds the
chunk-before-first-write barrier, v2 typed little-endian snapshot records with
SHA-256 payloads and canonical footer, background AsyncStream writer, generation
commit markers, WAL/replay, K1-K10 recovery and the 1M/100-save workload. Unsafe
Swift is confined to Snapshot.swift, read-only BitwiseCopyable serialization.
No production source, production save path, main merge or iPhone acceptance is
changed. C is not accepted until its Apple CI runs and measured thresholds pass.

# R005 Stage B retry — period-bound correction and CI ordering

Run 36836005603 on commit `717093a8a5ce71bb08de8f5a4fccc310e1223a90`
FAILED in the full G16 Stage B measurement with `corruption: ledger row`.
The five Stage B SIGKILL points had already passed in Debug and Release.
The cause is exact and bounded: the reusable experimental LedgerRow decoder was
created for the earlier 1-3 period retention fixture and still rejected periods
4...30, while Stage B explicitly uses one period per day for 30 days.

The correction changes only that parser bound from 3 to the Stage B 30-day horizon.
It does not change row encoding, money, delay distribution, summary invariants,
manifest commit semantics, retention window, or any success threshold. The failed
run and artifact remain recorded in failures.json.

The workflow is also reordered so Stage A's TSan evidence completes before the
full Stage B measurement. Stage B kill tests still run under Debug, Release and
TSan. The current Stage A fidelity correction remains mandatory; no A/B decision
is accepted until the next source passes the whole ordered workflow.

# R005 Stage A fidelity correction — supersedes the provisional A decision below

A directive-compliance review after run 36834086456 found that the S benchmark
still used the earlier thin 45-byte asset columns. The attached directive requires
the full S layout to include five additional UInt32 columns: contract, changeEpoch,
entity, policy, and origin, making the per-asset S fields 65 bytes before wheel,
group, output and fixed overhead. Therefore the green run 36834086456 remains valid
evidence for the code it measured, but it is NOT valid for the final Stage A
S-vs-H design decision and its provisional choice must not be used.

This correction adds those five columns to SwiftWorld, initializes contract/entity/
origin deterministically, reads contract on the event hot path, writes changeEpoch
on completion, records origin on schedule, and extends the typed full checkpoint
and restore path by exactly those five UInt32 fields. Hybrid schedule also records
origin for semantic parity. No adoption threshold, oracle, mutation, allocation,
deadline, compiler or sanitizer gate is changed.

Stage A must be remeasured on Apple CI before A is accepted. Stage B code may exist
on the branch, but B/C are not accepted from any source whose A decision was based
on the thin S layout. Any already-running B workflow for the prior commit is
historical/superseded for final proof closure. Production remains untouched.

# R005 proof closure — Stage A accepted, Stage B candidate starts

Stage A completed successfully on Apple CI run 36834086456 at source
`33c8ed1e0d7b72e66932839e3c8bdd1888abd7b5`; the companion existing-gates run
36834086513 also completed successfully. The failed predecessor run 36833504981
remains FAILED and preserved in failures.json.

Measured Stage A decision under the directive's exact rule: **S is chosen**.
At 1M, S median was 124.413588 ns/event and H median was 105.266487 ns/event,
so H/S = 0.8461012072089746. H owned 100.748672 B/asset and all health gates
passed, but H did not meet the required <=0.75*S speed threshold. Therefore the
documented fallback selects S; this is a measured rule outcome, not a preference.
At 2M the medians were S 219.5568585 ns/event and H 138.56497075 ns/event; that
trend is recorded only as confirmation and does not alter the 1M decision.
All Stage A measured advance allocation maxima were zero. These are Apple CI VM
measurements, not iPhone acceptance.

Stage A artifact: run 36834086456, artifact 11148603361; downloaded ZIP SHA-256
b68b5ae47c82448f9c56ec12d5b99d0e7ccd2ae92b776cb156142327705b7bd5.
STAGE005-A.json SHA-256:
6dc57f1b24294c07402cd071d26df5a46093db8dd48846d593c2cdd9f03900f0.

Stage B may now start. The candidate implements only generated proof data: the
30-day G16/G1 accrual-billing fixture, seven-day detail window, open-item carry,
40-byte summary deltas, append+fsync manifest commit point, exact per
(entity,account,period) invariants, full final disk reread, and S1-S5 SIGKILL
recovery. The full Release measurement must produce exactly 60 day records; the
five kill points must pass in Debug, Release and TSan. Real financial data is
never touched. Quota is not finalized until Stage C supplies measured Snap.

This section is still a candidate notice for B. Do not claim B passed until its
new Apple run is green and its artifact is inspected. Production integration,
billing policy approval and iPhone acceptance remain untouched.

# R005 Stage A retry after preserved CI failure

Run 36833504981 on commit `2ce64ce0e798d99df676d5bf7f87cfa9eeb6f44e`
FAILED during the Stage A measurement step. Debug/Release compilation and the
pre-existing Swift behavior/mutation/recovery/storage step had already passed.
The failure was not a layout or oracle failure: `stage005_a.py` inherited
`NXR_ALLOCATOR_DYLIB` but did not translate it into `DYLD_INSERT_LIBRARIES`
for its `stage-a-bench` child processes, so the unchanged positive allocator
gate correctly rejected the measurement. The failed run and artifact
11148427856 / SHA-256 dbf56ebb49fcd95dae1175bdca7ad2dafe9e333b3301a75c5137b15925c42ed8
are preserved in failures.json and must remain failed.

The retry changes only subprocess environment injection for Stage A measurement.
No threshold, oracle, mutation, allocation gate, production source, or result is
weakened or rewritten. Stage B remains blocked until the corrected Stage A run
finishes successfully.

# R005 proof-closure execution update — Stage A candidate

Updated: 2026-10-01 / Asia/Riyadh.
Live branch was rechecked before this change at `74bc02b717cae0a80c5014c92b33c0c8d273dfe1`;
main remained `38ce39cf9322f47e4def5f6eddb425c5a66ea7f9`.
AGENTS.md was reread. The three excluded branches remain denylist-only and none
of their implementation content was opened or used.

The owner supplied the 18-page directive “R005 — التوجيه الهندسي التنفيذي لإغلاق
مرحلة الإثبات” and explicitly ordered completion in stages without stopping. It
authorizes proof-only experiments A/B/C inside Experiments/R005Swift and still
forbids production integration until the measured results are presented and approved.

Current candidate work is Stage A only: it adds the complete S-vs-H layout experiment.
H uses a 48-byte BitwiseCopyable HotAsset record and 32-byte EventNode record with
explicit zeroed padding, keeps cold fields in columns, preserves the hierarchical
wheel semantics, exact event oracle, all eight injected faults, and the 15 partition
cases. The measurement runner requests 3 independent processes per (variant,size),
2 warmups then 10 measured runs in each process at 100k/1M/2M, budget 256. The
documented rule is enforced exactly: H is selected only if its 1M median ns/event
is <= 0.75*S, its owned bytes are <=128 B/asset, and all health gates pass.

This section records a CANDIDATE, not a passing result. Apple CI must compile and
run it under Debug, Release and TSan. Do not advance to B until Stage A CI has
completed successfully and the measured decision is read from its artifact.
No production Sources/Tests/root Package, no main merge and no iPhone claim.

# NEXORA — previous reference / المرجعية السابقة

Updated: 2026-10-01 / Asia/Riyadh. Repository: bdr-design/NEXORA only.
Game name: NEXORA. Read AGENTS.md before every resumed work session.

**Current result: the executable Swift experiment passed its specified Apple CI
checks. R005 production integration, billing and retention approval remain pending.**
**نتائج تجربة Swift نجحت؛ ليست معلّقة. نجاح التجربة لا يعني اعتماد الإنتاج أو حل اللاق على iPhone.**

Single active branch: `diagnostic/r005-design-1m-20260930`.
Code commit tested directly: `c0e19bfe995f2b6bcbd51407cc2cf39384ee0b10`.
Tested tree: `3ad48aa8509f93f1782bc6fb390df728284a7ea8` (158 files).
Live branch HEAD was checked at that commit before this reference-only update.
This publication is a documentation-only descendant; read live HEAD on resumption
and distinguish its publication SHA from the tested code SHA above.
Main was rechecked at `38ce39cf9322f47e4def5f6eddb425c5a66ea7f9` and is unchanged.
No new main merge, release, application or IPA has been produced by this update.
Older permitted branches are historical, not concurrent work lines.

## Results and evidence — start here

The one final numerical report is [Experiments/R005Swift/RESULTS.md](Experiments/R005Swift/RESULTS.md).
It is the exact report already delivered in the conversation, now stored in Git:
SHA-256 `2f45c1a494039d1deb5bb3f8a12db01d8ccc8c678b50f5f6ae715861664eef0a`.
Its references to attached ZIPs and `verification/verify_delivery.py` mean the
previous delivery bundle, not extra files claimed to exist in this repository.

The following existing runs were rechecked as completed successfully during this
reference update. They tested c0e19bfe, not this future documentation publication:
- [Swift experiment 36768973949](https://github.com/bdr-design/NEXORA/actions/runs/36768973949), job 110070201715.
- [Existing gates 36768974078](https://github.com/bdr-design/NEXORA/actions/runs/36768974078), jobs 110070202211 / 110070202540 / 110070202684, all successful.

Artifact retrieval identities from the verified delivery:
- `r005-swift-executable-results`, 11122388129, run 36768973949;
  SHA-256 `5daae4cd08fafd9511b22cca843c11a7e8052559547dc1481d1ebdad39cbc258`.
- `r005-contract-logs`, 11121784741, run 36768974078;
  SHA-256 `5b1e2a10701b1a501cac77e6b4abc3f185a39b35782462b8f5161dc2664a0c97`.
- `r005-bounded-study`, 11121704078, run 36768974078, includes the tested source;
  SHA-256 `3a51146af8c3b0190925c34229ad4766ce327d97a1c9de107d24a81b8e945c11`.
This last artifact is NOT the older raw acquisition 11115497993. Do not mix them.
Check artifact availability and downloaded bytes on reuse; never infer a sandbox
path from a title or an earlier session. The handoff ZIP retains tested c0e19bfe
and remains valid for that code; this reference supersedes its stale-doc warning.

## Implemented experiment and measured scope

Working code is isolated in `Experiments/R005Swift`: Swift 6, ContiguousArray-owned
columns, a resumable hierarchical timing wheel, atomic accrual, exact order oracles,
full typed checkpoint + command WAL, recovery, and generated-data compaction.
No unsafe Swift pointers own simulation state; C is platform/measurement support.
No original production Sources, Tests, Checks, root Package.swift or AGENTS were
changed by the experiment or by this reference update.

Event transcripts match TripSimulation through 100k and a sorted independent
reference through 1M. Count budgets 1/7/31/256/1024, injected-clock and actual-clock
partitions pass. Eight injected mutants in seven required classes were detected;
none survived that test set. Snapshot/replay checks, 23 SIGKILL sites per mode,
47 torn WAL tails and 15 corruption/arithmetic cases are recorded in RESULTS.
TSan ran the new model/mutations/recovery and 1k order cases; not all performance
sizes ran under TSan. Original 142 named tests / 11 suites per build mode and
compiler, fail-stop and iOS library-compile gates remain separate evidence.

At 1M on Apple CI VM Release: owned-column capacity 76.008544 B/asset,
median process phys_footprint delta 75.825280 B/asset, median mean 174.241310 ns/event.
The measured kernel accrues only; R004 issues individual invoices. These are NOT
same-work full-finance speedups, complete-engine memory or physical-iPhone results.
Zero covered allocation-entry calls were observed across 44,515 advance calls,
with positive C/Swift calibration; this is not all kernel virtual-memory activity.
Full snapshot at 1M: 62,166,767 bytes. It is not incremental save. One-day generated
retention fixture: 608,000,016 detail bytes -> 32,011,596 summary/open-item bytes,
plus 358 manifest bytes; 500,000 open items retained. No real financial record was
deleted. The one-day fixture is not an indefinite campaign/storage-cap proof.
Use RESULTS for the remaining sizes, timings, assumptions, peaks and limits.

## Failures, remaining decisions and safe continuation

Keep failed run 36767779910 as FAILED: allocator positive calibration did not
observe actual allocations. Later observer correction and successful runs do not
retroactively pass it. Keep `Experiments/R005Swift/failures.json`, previous reports,
raw artifacts and local verification failures; no sample filtering or evidence loss.

R004 causal acquisition remains INCONCLUSIVE as a bounded investigation. No new
spike acquisition in this reference update. Runnable reanalysis uses only original
artifact 11115497993 (SHA-256 6eb273848b9e37eb074dac106e6bf86269cbbfe4afb1337a1d2d8f286dd9354e).
Runnable includes running/task aggregation; missing timebase was not guessed.
Do not change origins as a speculative spike fix or repeat hosted campaigns.
Physical Mac fallback is optional when a real device is available, not a blocker.

The owner authorized working experiments and then said: "بعدها أقرر التصميم والفوترة والاحتفاظ".
The experiments/results have been delivered. A handoff or reference update is NOT
approval to merge R005 production code, change periodic billing or retire real
financial detail. Next boundary is the owner's decision on production adoption,
billing semantics and retention/granularity/quota, using the delivered results.
Do not rebuild this experiment or create another ADR merely because the chat changed.
Until that decision, preserve the working source and existing acceptance tests.
No new HR, maintenance or delivery domain. Incremental save, final storage quota,
complete economic feature integration and iOS application/device acceptance remain open.

Design population: 1M; capacity headroom: 2M. Device gates on iPhone 17 Pro Max:
100k, 250k, then 1M, with declared activity/features/history. Owner budgets remain
128 B/asset target / 200 B hard hot-state cap, <=0.5 us/full event on device,
zero heap allocations/event and <=1/advance, <=quarter performance-core equivalent,
<=2 ms visible save pause. These are NOT all achieved by this prototype.
No device FPS, heat, energy, 30-minute endurance or full-game acceptance is claimed.

Permanent exclusions, names as denylist ONLY:
`archive/before-radical-rebuild-20260930`, `audit/nxr-0003-20260930`,
`fix/nxr-0003-contract-repair-20260930`. Never open/use/copy their implementation.
No force push, destructive reset/checkout/history rewrite or excluded-code archive.
Preserve local changes; do not assume an unpublished local candidate equals this source.
The earlier effort-setting blocker is superseded; no hidden-setting verification is claimed.

Previous continuity is preserved verbatim in
[Docs/History/2026-10-01-PRE-RESULTS-CONTINUITY.md](Docs/History/2026-10-01-PRE-RESULTS-CONTINUITY.md).
It contains the now-historical pending-Apple note and is not current status.
This reference update is recorded in
[Docs/Daily/2026-10-01-R005-REFERENCE-SYNC.md](Docs/Daily/2026-10-01-R005-REFERENCE-SYNC.md).
No new performance or Swift test run is claimed by this documentation publication.
