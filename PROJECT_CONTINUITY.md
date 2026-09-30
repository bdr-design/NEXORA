# NEXORA — current reference / المرجعية الحالية

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
