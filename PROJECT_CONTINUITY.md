# NEXORA continuity — R004 evidence hardening, not a performance fix

## Permanent exclusion / تنبيه دائم
The following names are a denylist only. Their implementation, tests, schemas,
benchmarks and history content must never be opened, copied, merged, cherry-picked,
built, repaired from, or used as a recovery/archive source:
- archive/before-radical-rebuild-20260930
- audit/nxr-0003-20260930
- fix/nxr-0003-contract-repair-20260930
هذه مصادر مشطوبة نهائيًا وليست مراجع. لا أرشيف بديل ولا حذف تاريخ أو force push.
Read AGENTS.md and live branch tips at every resume. The permitted line is the
new R001 and authorized successors; do not restart it because chat changes.

## Authorization and source ownership
Repository bdr-design/NEXORA only; game name NEXORA only. The owner authorized
actual careful implementation/testing with "الجهد الداخلي الان pro كمل لاتشيل همه".
Do not reopen the old hidden-setting verification blocker. No independent hidden
setting verification is claimed. The consultant supplies hypotheses, not merge
approval or test evidence. Preserve local changes and exact evidence; no background
promises. Trace inputs, owner, writes, callees and failure behavior before changes.

## Current engineering work — 2026-09-30 / Asia/Riyadh
Working branch: fix/r004-evidence-hardening-20260930.
Parent live HEAD verified: 5384b58d193f90859a8f0efeaec6d28d6e93b89e.
Parent tree reconstructed from all 112 files/modes:
cfb4e4d41a960154878e0280abf8cc4a2413e64b.
Re-read this branch's current HEAD; this document cannot name its own future commit.
Main/foundation/feature-R004 remain at 5b5599895fa1bdbf00e951104e0cd55dc00f9a56.
Review branch remains separate; no main merge, history cleanup, or excluded access.
Local direct clone failed DNS; the verified mounted permitted source ZIP was used.
No pre-existing local working tree or uncommitted changes were discarded.

Stage A edits are inside the existing diagnostic owners:
1. Source guard no longer ignores any __pycache__ directory. Added/removed files,
   changed modes, symlinks and non-regular files are checked. Run Python with -B or
   PYTHONDONTWRITEBYTECODE=1; generated caches are not hidden by a blanket exemption.
2. Schema 1 requires the complete producer fields, exact counter units/scope and
   indexing, integer amounts/counts/times, no unknown/duplicate JSON keys or NaN.
   Valid zero, unsupported, failed and decreased-counter meanings are retained.
   Analyzer output is exclusive-create and cannot replace raw input or old output.
3. DiagnosticWriter uses a single O_CREAT|O_EXCL descriptor, no truncate/reopen race,
   rejects final-component symlinks/NUL paths, preserves old bytes and owns close.
   The parent directory must be controlled by the caller. This is not durable save.
4. Review CI has no path filter and runs the actual diagnostic executable and writer
   checks under TSan, not only the 142 library tests. The existing diagnostic
   workflow's narrow path filter was also removed in this source.

No production Swift library, original Swift test, economic rule, origins index,
normal measurement loop, or Package.swift change. The legacy --json CLI remains
untouched; exclusive file protection applies to --diagnostics and analyzer output.
The new tiny --diagnostic-writer-probe is a test-only command of the check executable.

## Local stage A evidence and retained failures
Swift 6.2.1/Linux: Debug 142 named tests/11 suites PASS; Release 142/11 PASS.
Diagnostic normalized transcripts pass in both modes at nine boundary/scale sizes.
Python suite: 77 named tests PASS (43 existing, 34 added); subcases are not extra tests.
Actual writer: 14 tests in each Debug/Release PASS, including eight-process race,
existing files/links/FIFO, missing identity, closed writes and embedded NUL handling.
29 compiler rejections/five valid clients and 12 corruption fail-stops passed.
Pinned old Apple reanalysis remains byte-identical for 372600 measured batch records.
No new local TSan, Apple gate or performance cause is claimed at this source commit.
The new Apple workflow must finish and its complete artifacts must be checked.

Two initial Python assertions failed because stricter schema rejection preceded
old error-message expectations. The valid failure fixture and expected missing-field
error were corrected; no rejected input was reclassified as valid to pass tests.
One local quick smoke mistakenly used the parent SHA for locally modified code.
Its raw stream/summary are retained unchanged in quarantine and excluded from
source-verified/performance evidence. A 40-hex field is not producer attestation.
The fresh CI smoke uses GITHUB_SHA and exported source-tree verification instead.

## Prior verified checkpoints — do not mix evidence
Canonical R004 business code: 674c94e145f24dc6c4c9addaa5aa07d1c9d4a168;
Apple run 36679204017, artifact 11080779599. Debug/Release/TSan each 142/11,
29 compiler rejections, five valid clients, 12 fail-stops, five iOS library compiles.
Publication 5b5599895fa1bdbf00e951104e0cd55dc00f9a56 is documentation-only.
See Docs/VALIDATION-R004.md and Docs/Design/ATOMIC-FINANCE-R004.md.
Diagnostic code b7d3deb8a8599ac382b69e431addf22acd0f4e7f, run 36692367500,
artifact 11086348930, SHA256
34317f1a041179325ac93a0f9925634df3d1736c6ae4b3f68e5185f66369b9e4.
Review code 0706447fceaca594d7dd897d98fe406dd926e352, run 36697715699,
artifact 11089180650, SHA256
4fe2a49c41c14331e8706d706888129c512ec1837dec5077c6e194aeecb7723d.
Its 43 Python tests fixed seven evidence-acceptance cases, not every later finding.
Docs/VALIDATION-R004-MEASUREMENT.md and Docs/VALIDATION-R004-AUDIT.md retain
full checkpoint details, prior failures, exact hashes and scopes. Source-export-only
review/r004-source-20260930 is NOT a development or test-evidence source.

## Next boundary: causal trace, not speculative finance optimization
After stage A gates, use a separate branch for symbolized execution/scheduling
traces and calibrated batch markers. Keep profiling output separate from unprofiled
A/A data. Confirm xctrace templates/options on the actual runner, record unavailable
capabilities as such, and do not claim a successful trace from a created filename.
The 22 counters-mode >5ms batches comprise 19 with <1ms thread CPU and three near-CPU
arrivals. Another 30 wall-only >5ms batches cannot be CPU-classified. No universal
cause or index exoneration follows. Low CPU versus wall supports off-CPU time, not
identification of the responsible process. Equal instructions do not rule out
on-CPU stalls. Runnable time includes running; process counters are not per-thread.
Old peaks 32.748166ms (20k/counters) and 57.649334ms (100k/wall) remain in evidence.
Do not replace origins or start R005 as though these questions were closed.

## Product/storage boundaries still open
R001 identity/timeline, R002 aircraft, R003 bounded trips, R004 single-currency
in-memory atomic finance exist as a narrow development core, version 0.0.4.
No application/IPA. Identity handles are process-local, not save/replay identities.
Finance history is bounded and blocks at capacity; no disk draining yet.
R005 later: permanent world/entity/operation/invoice IDs, then durable transaction,
save/recovery and crash tests; old invoices must retain origins across retirement
and slot reuse. Never append fallible storage after arrival and call it durable atomicity.
Documents/images belong in separate blob storage, not hot economic state.
HR/scheduled payroll, maintenance/delivery, transfers/cheques/images/proofs/search,
real airports/routes, other sectors, iOS application/Metal map and physical-device
acceptance remain unimplemented. Expense categories are not those full systems.
20k full-feature assets on iPhone 17 Pro Max is the acceptance target; 100k remains
architectural. No FPS, heat, energy, physical-memory, under-1/5ms or full-game claim.
