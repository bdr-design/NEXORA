# NEXORA continuity — NXR-R003 candidate

## Permanent exclusion / تنبيه دائم
These branch names are a denylist only, never development/reference/recovery:
- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`
المصادر الثلاثة مشطوبة نهائيًا؛ لا تُقرأ أو تُنسخ أو تُستخدم أو تُسترجع. أي إذن
قديم ملغى. التحذير ليس حذفًا لتاريخ Git. لا أرشيف بديل للتنفيذ المشطوب، ولا إعادة
تأسيس R001 بسبب انتقال المحادثة. اقرأ AGENTS.md وتحقق من الفرع وHEAD كل جلسة.

## Execution authorization
The owner said "الجهد الداخلي الان pro كمل لاتشيل همه" after the explicit request
to proceed with code/testing. The old setting-proof blocker is superseded by this
authorization, not by independent verification of an invisible runtime selector.
Source isolation, staged review, evidence and production/device gates remain.

## R003 current work
Repository bdr-design/NEXORA only. Development 0.0.3; no app build or IPA.
Branch feature/r003-bounded-trips-20260930, based on verified R002 evidence commit
63de835eef4b24b410703507986dbf84f5d6eeea. main/foundation were fast-forwarded to
that R002 checkpoint, not to the new R003 candidate. Always fetch actual refs.

Implemented, not merely designed: TripSimulation uniquely owns AircraftStore,
journey rows and a fixed-capacity arrival heap. Register/depart/retire inputs;
checked simulation time; due-time/operation-ID ordering; capped advance with
explicit committed prefix, actual time, next event and block/budget reasons.
Manual input sequence is separate from automatic time/arrival progress. Full queue
fails before aircraft start. Failed head remains queued. No per-entity tasks,
hot world scan, full snapshot or I/O in these operations. This is a narrow timed
trip fixture with numeric airports, not a complete route/business platform.

Read Docs/Design/TIMED-TRIPS-D002.md, Docs/Updates/NXR-R003.md and current validation
before changing this source. AircraftStore fixture/audit visibility is now package
scoped for compound tests; normal public mutation algorithms are unchanged and
external misuse gates still reject access.

## R003 evidence at submission
Linux Swift 6.2.1: Debug/Release each 86 named tests in six suites PASS.
35 new tests + previous 51; parameter expansions are not independent named tests.
New independent model: four seeds x5,000 requests, 3,213 automatic arrivals,
248 injected blocked-prefix results; exact logical/identity/queue states matched.
Earlier R002 model tests reran too. 18 required compiler rejections, three valid
clients, eight Debug/Release corruption processes, source guards and five timed
trip scales with 30 raw samples each passed. Local full SwiftPM TSan did not
complete within its configured observation window; it is NOT a successful run.
The full Apple TSan and all four iOS library gates are required before acceptance.

Local and prepared GitHub object identities matched exactly:
Sources ca904809dce06a62b9f8c5b1e9a657ebfcc61c2f
Tests c9a27bbb025a03aca0e4b1ef8524378fcd16eb2a
Checks 9edd1ccc9be83c2187a44d512eee85b663d708f4
Package.swift 9f334c443c0e16c989eda7558adbbc0d4e18e502
No R003 Apple run/artifact is assumed at submission; fetch actual results.

## Verified permitted R002 checkpoint
Code 4583de236d5aa25b06bbd3ed4a2492e8cb629835, tree
499ea18d3a9057f8329dce8346eb555efa697bb1. Apple run36653271004/job109691995765
passed 51 tests each Debug/Release/TSan, compiler/fail-stop/three iOS library gates.
Artifact11070708521 was downloaded and rehashed:
e1dfbb9c11d04421561d14dbb579a9699f7ba33b8bcf3cac69e8c7a868730509.
This evidence belongs to R002; never inherit it as R003 success.

## Remaining and safety of next extension
After actual R003 Apple verification: prepare and validate financial postings
before the arrival commit. Do not bolt fallible finance onto the result consumer
and call it atomic. Real route data/planning, revenue/invoices/payroll/maintenance/
delivery, persistent logical identity, transactional save/load, separate document/
blob storage, iOS presentation/map and full bounded diagnostics remain unfinished.
Preserve transfers/cheques/images/proofs/receipts/search and multi-industry scope
in Docs/REQUIREMENTS.md. 20,000 full-feature assets remains future acceptance;
100,000 is an architectural goal. Small Linux/Mac fixtures do not certify iPhone
FPS, memory, energy or heat. No physical history deletion or background delivery
is implied. At handoff record exact branch/HEAD, code/test failures and evidence.
