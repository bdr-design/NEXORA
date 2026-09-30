# NEXORA continuity — NXR-R003 verified timed-trip core

## Permanent exclusion / تنبيه دائم
These branch names are a denylist ONLY, never development/reference/recovery:
- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`
المصادر الثلاثة مشطوبة نهائيًا؛ لا تُقرأ أو تُنسخ أو تُدمج أو تُستخدم أو تُسترجع.
أي إذن قديم ملغى. التنبيه لا يعني حذف تاريخ Git فعليًا. لا أرشيف بديل للتنفيذ
المشطوب، ولا إعادة تأسيس R001 بسبب انتقال الدردشة. اقرأ AGENTS.md وتحقق من
فرع العمل وHEAD عند بداية كل جلسة، وسجّل نقطة الاستئناف الدقيقة بعد المراجعة.

## Latest execution authorization
The owner explicitly said "الجهد الداخلي الان pro كمل لاتشيل همه" after the
assistant asked to proceed with code/testing on an isolated permitted branch.
The old setting-proof blocker is superseded by that authorization. It is NOT
independent inspection of an internal setting. Continue actual staged work;
source isolation and evidence/production/device gates remain mandatory.

## Current implementation and exact evidence
Repository: bdr-design/NEXORA only. NXR-R003, development 0.0.3. No app build/IPA.
R003 implementation branch: feature/r003-bounded-trips-20260930.
Tested code commit: 50a9fb82db7ea13f636b5c4b3e4f104d8bb7b113.
Tested tree: 604fef333991e71bc191abd17a19bc93afbaf08d.
R003 is based on permitted verified R002 evidence commit
63de835eef4b24b410703507986dbf84f5d6eeea. Evidence-only publication can advance
branch tips; re-read main/foundation/feature refs instead of inferring current HEAD.

Implemented: R001 unique identity and bounded timeline; R002 owned aircraft
lifecycle store; R003 single-owner timed-trip coordinator, fixed-capacity heap,
checked simulation clock, numeric fixture airport locations and register/depart/
retire commands. Advance returns actual reached time, completed prefix, next due,
and explicit target/budget/blocked reason. Failed events remain queued. User-input
sequence is independent of automatic arrivals. No per-aircraft task/actor/lock,
hot world scan, normal full snapshot, I/O or presentation in this core path.
This is not a complete enterprise platform or real route catalog.

## R003 Apple evidence verified in full
Read Docs/VALIDATION-R003.md and Docs/Updates/NXR-R003.md.
Run36655778966 / job109699695428 passed all gates on the tested code above.
Debug, Release and TSan each passed 86 named tests; no sanitizer error reported.
18 required compiler rejections, three valid clients, eight isolated corruption
processes, four iOS library compiles and five 30-sample trip scales passed.
New reference: four seeds x5,000 requests; 3,213 arrivals and 248 injected blocked
prefixes, matched against independent sorted-list state. R002's separate 20,000
model commands also reran. Parameter expansions are not extra named tests.
Local full TSan did not complete within its observation window; Apple success is
a separate verified run and does not erase that local incomplete invocation.

Artifact11072940842, NEXORA_R003_Apple_Evidence.zip, recalculated SHA-256:
03141936e8e14948841424a6b16b10c850eb4ffd84a685beb9baed97e865885d
Nested NEXORA_R003_SOURCE.zip, recalculated SHA-256:
784fe213ecacf6b65a2284c8d18a5da3338e5177e910194747b43d722b655b90
All 67 exported source files and executable modes recomputed to the exact tested
root tree, not merely selected files. This archive is permitted current source,
not an excluded-source recovery archive. Do not infer old sandbox paths in a new
chat; fetch the connector artifact or use an actually attached source export.

Local/published tested subtrees:
Sources ca904809dce06a62b9f8c5b1e9a657ebfcc61c2f
Tests c9a27bbb025a03aca0e4b1ef8524378fcd16eb2a
Checks 9edd1ccc9be83c2187a44d512eee85b663d708f4
Package.swift 9f334c443c0e16c989eda7558adbbc0d4e18e502
The current evidence-only documentation update does not change these code objects.

## Earlier permitted R002 checkpoint
Code4583de236d5aa25b06bbd3ed4a2492e8cb629835, tree499ea18d3a9057f8329dce8346eb555efa697bb1.
Apple run36653271004/job109691995765, 51 named tests each Debug/Release/TSan,
all compiler/corruption/three-library gates passed. Artifact11070708521 hash:
e1dfbb9c11d04421561d14dbb579a9699f7ba33b8bcf3cac69e8c7a868730509.
D001's old implementation-blocked/not-run wording records its creation only and
does not override actual R002/R003 implementation or the owner's new permission.

## Exact next engineering boundary — still unfinished

Prepare/validate financial postings BEFORE arrival commit. Do not bolt fallible
finance onto a consumer of completion results and call it atomic. Define a narrow
revenue/invoice path with independent accounting/failure evidence, followed by
payroll, maintenance and delivery obligations. Define persistent logical IDs
before save/load; current handles/tokens remain process-local. Durable transactions
and separate document/blob storage must preserve transfers, cheque images, proofs,
receipts and searchable history without swelling hot simulation state.

Real route data/planning, finance, payroll/maintenance/delivery, persistence,
iOS app/map and expanded bounded causal diagnostics remain unimplemented here.
The 20,000 full-feature acceptance and 100,000 architectural goal remain unproven.
Mac/Linux timings are not iPhone 17 Pro Max FPS, physical RAM, energy or heat.
Production approval is separate from this core gate. Physical excluded-history
deletion remains unresolved. No background continuation or automatic daily job is
implied. Preserve exact source/changes/failures/evidence at every handoff.
