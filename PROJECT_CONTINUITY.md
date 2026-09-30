# NEXORA continuity — NXR-R004 verified development core

## Permanent exclusion / تنبيه دائم
These branch names are a denylist ONLY, never development/reference/recovery:
- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`
المصادر الثلاثة مشطوبة نهائيًا؛ لا تُقرأ أو تُنسخ أو تُدمج أو تُستخدم أو تُسترجع.
أي إذن قديم ملغى. التنبيه ليس حذفًا لتاريخ Git؛ لا أرشيف بديل للتنفيذ المشطوب.
اقرأ AGENTS.md وتحقق من الفرع وHEAD عند كل جلسة. لا تُعد إنشاء الأساس بسبب انتقال
الدردشة، ولا تستخدم رقم التحديث المشابه في فرع مشطوب بوصفه مصدرًا مسموحًا.

## Authorization and work boundary
The owner explicitly authorized implementation/testing with
"الجهد الداخلي الان pro كمل لاتشيل همه". The old assistant-side effort-setting
verification blocker was superseded. This is not independent proof of a hidden
setting. Keep high-care staged review and evidence gates; do not return to a
documentation-only loop or imply production/device acceptance from this permission.

## Current source — read live refs before changing anything
Repository bdr-design/NEXORA only. NXR-R004 / development 0.0.4. No app build/IPA.
R004 working branch: feature/r004-atomic-finance-20260930.
Canonical branches: main and foundation/clean-core after verified fast-forward.
Tested code: 674c94e145f24dc6c4c9addaa5aa07d1c9d4a168.
Tested root: f1273cf58de998cad9256581474edbe1c8f85261 (95 files).
The evidence-only publication commit is a descendant. Re-read remote tips; do not
mistake the tested code SHA or this note for the final remote HEAD.

Implemented: unique identity and bounded timeline; owned aircraft lifecycle;
bounded timed arrivals with separate manual-input sequence; and single-currency
finance with invoices at priced arrival, partial/full collection, capital and
cash-expense primitives, bounded journal and pages. Finance preparation precedes
aircraft completion; expected failure keeps the failed event unchanged and
explicitly returns any already-committed prefix. See Docs/Design/ATOMIC-FINANCE-R004.md.
No normal hot full snapshot, per-aircraft task/actor/lock, I/O or UI is in this path.

## Verified final R004 evidence
Apple run 36679204017/job 109770742356 succeeded on the tested code above.
Apple Swift 6.1.2, arm64 macOS 15, Xcode 16.4. Debug/Release/TSan each 142 named tests
in 11 suites. 29 required compiler rejections, 5 valid clients, 12 isolated corruption
probes and 5 iOS library compiles passed. Four raw fixture reports each contain
five sizes and 30 samples per size. No iPhone execution is implied.
Artifact 11080779599, NEXORA_R004_Apple_Evidence.zip, recomputed SHA-256:
df71ac8bf51e8b8cbf0be4bb061b0b66619f2cb8ed12aff479abc385e4b7211c
Nested NEXORA_R004_SOURCE.zip, recomputed SHA-256:
a815f730f4a6b5d663dbfcc8763d22df5307892469048503354c8f6427fd91a1
All 95 exported file contents and modes matched local source and rebuilt the
complete tested Git tree. Fetch artifacts or use actual attachments; never infer
an old sandbox path in a new chat. Source/test/check/package/CI object IDs and
complete evidence are in Docs/VALIDATION-R004.md.

The final review added CurrencySpec input-bound validation and F31/D01/D02 tests.
Local final Debug/Release passed 142/11. Local wrapper timeouts and successful
standalone reruns are recorded, not suppressed. Earlier incomplete local TSan is
not a passing result; the full Apple TSan evidence is separate.

## Performance findings — not closed
At 20k the financial fixture recorded a 20.050916 ms arrival batch and 16.267500 ms
collection page. Do not discard them or attribute them to CI noise without data.
No hard under 5 ms/under 1 ms, FPS, physical-memory, energy or heat guarantee is proven.
The 95-file source has a functioning narrow finance boundary, not 20k full-feature
assets. 100k remains an architectural target, not whole-game acceptance.

## Earlier permitted checkpoints and auxiliary branch
R003 publication ca0351757ce158c6320f962d1285c6f4aca2cf13 is the allowed R004 base.
R003 code 50a9fb82db7ea13f636b5c4b3e4f104d8bb7b113/run 36655778966 passed 86 named
tests per mode. See its retained validation record; do not reuse its numbers as R004.
The recovered R004 candidate 53cb86222f1529f8f48be4d00993c4ef03900311/tree 69a9dceedcf973c02bd0d59d091f399095558ee1
passed its own 139-test Apple run 36677404314 before the final revision.
review/r004-source-20260930 only exported that exact candidate when local direct
retrieval failed. Its run 36678040118 is not test evidence or a development branch.
Do not build future work from that export-only tip.

## Immediate diagnostic boundary — newer owner handoff, 2026-09-30

The handoff explicitly prioritizes measurement before R005 or any FinanceStore
optimization. Work branch: diagnostic/r004-batch-counters-20260930, based on the
published 5b5599895fa1bdbf00e951104e0cd55dc00f9a56 (98 files). Re-read its live tip;
this paragraph cannot contain its own future commit hash.

The measurement-only candidate extends Sources/NexoraFinancialCheck/main.swift.
The original sample and CLI are unchanged except a new diagnostic dispatch.
Checks/financial-diagnostics.py rebuilds original source/test/check/Package/AGENTS
and original workflow object hashes. No origin-index or business code change.
New .github/workflows/r004-diagnostics.yml runs independent Apple gates and three
sequential A/A processes; an uploaded candidate or a started run is NOT a pass.
See Docs/Design/R004-BATCH-DIAGNOSTICS.md and today's measurement ledger for actual
results/failures. Original R004 evidence above remains separate and unchanged.

Next safe action: validate the candidate on Apple, inspect complete raw per-batch
records, first batches, counters and calibration, then decide whether a targeted
causal experiment is warranted. No cause or deadline is certified by this patch.
Do not switch the invoice index or begin R005 until this diagnostic boundary has
been reviewed. Do not discard spikes, unsupported/failed reads or wrapper failures.

## Later engineering boundary — R005 not implemented
First design/implement permanent world/entity/operation/invoice identity distinct
from process-local handles. Preserve old invoice origins after aircraft retirement
or slot reuse, with explicit mapping and invalid-input/restart tests. Then define
and implement durable transaction/recovery semantics before claiming save/load.
Do not append fallible saving after an already-committed arrival and call it atomic.
Keep full media in separate document/blob storage with checked references.

Fixed in-memory history currently backpressures permanently at its configured
capacity; it cannot yet be drained to disk. This remains a long-session blocker.
Scheduled payroll/HR, maintenance/delivery obligations, treasury/cheques/transfers,
images/proofs/search, real route catalog, iOS app/Metal map and expanded causal
instrumentation are unimplemented. Expense categories are not full domain engines.
Track performance spikes with actual stage/device evidence as these systems grow.

For every handoff record the real branch/HEAD, files, tests, failures and next
safe step. At source/context uncertainty stop sensitive changes and preserve a
precise handoff. No destructive history cleanup or background continuation.

## Latest checkpoint — Apple measurement review completed, 2026-09-30

This section supersedes the pending validation/next-action wording above.
Tested diagnostic code: b7d3deb8a8599ac382b69e431addf22acd0f4e7f.
Tested tree: 08ed6b709bc271080ee98e56927db9cce0c00bbf, 102 files.
Apple run 36692367500 / job 109812298525 completed successfully. Artifact
11086348930, nexora-r004-batch-diagnostics, SHA-256:
34317f1a041179325ac93a0f9925634df3d1736c6ae4b3f68e5185f66369b9e4
All exported bytes/modes reconstruct the tested tree. Debug/Release/TSan each
142 tests/11 suites passed, as did 29 compiler rejections, five valid clients,
12 fail-stops, five iOS library compiles and both diagnostic transcript modes.
Three complete A/A processes produced 372,600 measured batch records; independent
raw recomputation matched the Apple summary byte-for-byte. See
Docs/VALIDATION-R004-MEASUREMENT.md and Docs/Daily/2026-09-30-R004-MEASUREMENT-VERIFIED.md.
A subsequent publication is documentation-only; do not call its own commit tested.

Performance is NOT closed: 20k counters-mode arrival max 32.748166 ms, CPU
0.527500 ms (run 1 / sample 14 / batch 43). Three other >5ms arrivals have CPU
near elapsed time. First-use faults occur in some warmups; measured first-batch
faults at 20k/50k/100k are zero. Neither external pauses nor origins first-touch
is a universal proven cause. The wall-only 100k arrival max 57.649334 ms is retained.

Next safe work: symbolized execution/scheduling attribution for the three near-CPU
arrivals and a controlled cold-versus-warm diagnostic experiment. Do not change
FinanceStore's index without evidence; do not start R005 as if this diagnosis were
closed. Main/foundation/feature-R004 stay at 5b5599895fa1bdbf00e951104e0cd55dc00f9a56.
Work remains on diagnostic/r004-batch-counters-20260930; re-read its actual HEAD.
Two incomplete local full-measurement runs and earlier build/wrapper failures are
preserved separately; Apple success does not convert them into local successes.
No iPhone execution, application/IPA, thermal or full-game acceptance is claimed.
