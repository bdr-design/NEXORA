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
