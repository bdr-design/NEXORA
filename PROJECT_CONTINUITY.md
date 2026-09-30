# NEXORA continuity — NXR-R002 verified core

## Permanent exclusion / تنبيه دائم

These are a denylist ONLY, never development/reference/recovery sources:
- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`

المصادر الثلاثة مشطوبة نهائيًا من العمل؛ لا نسخ ولا نقل ولا دمج ولا استرجاع
ولا استخدام لتنفيذها أو اختباراتها أو مخططاتها أو أرقامها. أي إذن قديم ملغى.
التحذير ليس حذفًا لتاريخ Git. لا أرشيف بديل ولا إعادة تأسيس R001 عند نقل الدردشة.
Read AGENTS.md at each working-day/session start and record the actual branch/HEAD.

## Latest owner authorization

On 2026-09-30, after the assistant's explicit execution question, the owner said
"الجهد الداخلي الان pro كمل لاتشيل همه". Actual code implementation and staged
testing are authorized on the permitted line. This is not independent inspection
of an internal setting. The earlier documentation-only blocker is superseded;
source isolation, careful review and evidence/production/device gates remain.

## Current implemented core

NXR-R002, development 0.0.2. No app build or IPA.
Repository: bdr-design/NEXORA only.
R002 implementation branch: feature/r002-aircraft-lifecycle-20260930.
Base: cf305b5a13cad67555dd18f129f23ffdecfd68d2 (permitted R001 plus D001 docs).
Tested implementation: 4583de236d5aa25b06bbd3ed4a2492e8cb629835.
Tested tree: 499ea18d3a9057f8329dce8346eb555efa697bb1.
Evidence-only commits can advance HEAD. Re-read branches before starting; neither
a previously tested commit nor this prose is a substitute for current ref checks.

Implemented: noncopyable AircraftStore with identity+private rows, four lifecycle
commands, store-bound revision tokens, active-operation matching, overflow and
stale/foreign identity rejection, detached internal audit, fault fixtures,
independent serial model, external misuse clients, fail-stop probes and raw scale
CLI. Existing R001 identity/timeline code and all 19 tests remain. Public allocator
mutation paths are unchanged; package-only diagnostic/fixture access was added.
D001's earlier NOT_RUN/IMPLEMENTATION_BLOCKED labels describe its creation only.

## Completed verification

Read Docs/VALIDATION-R002.md and Docs/Updates/NXR-R002.md.
Apple CI 36653271004 / job 109691995765 passed on the tested implementation above.
Debug, Release and TSan each passed 51 named tests. Compiler gates rejected the
original 3 + new 8 invalid clients and compiled valid clients. Four isolated
corruption probes passed; three iOS libraries compiled; five raw lifecycle scales
(1k/5k/20k/50k/100k), 30 samples each, passed.
Artifact 11070708521 was downloaded and source identities were checked.
SHA-256 independently recalculated and matched GitHub:
e1dfbb9c11d04421561d14dbb579a9699f7ba33b8bcf3cac69e8c7a868730509

Local Swift 6.2.1 Linux also passed Debug/Release and direct TSan execution.
The initial local SwiftPM sanitizer timeout remains a failed-to-complete command,
not erased by the later direct/Mac success. Harness fixes are documented.
All 32 D001 scenarios map to evidence: 30 scenario-named runtime tests, T25 compiler,
T31 source inspection; 2 extra ownership tests + R001's 19 = 51 runtime tests.
Parameter cases are not additional named tests. Random model coverage: 20,000
commands across four recorded seeds. No formal absence-of-defects claim.

Code identity checked between local and published implementation:
Sources ed8814e6500763fcb0c2e86b999c3ac1658a9689
Tests e64543a63b8a6fff575c78610bcc401c864508f1
Checks afdd225481506ee50dde1df45f3cdcfdb484dca3
Package.swift 54b95d82df62895828820a2e12d4d1af756695fa

## Remaining implementation

Next: bounded deterministic simulation time/events and one small trip/result path,
with prefix/failed-event semantics, independent reference and staged tests. The
serial store's revision must not become a whole-game asynchronous retry bottleneck.
Then incrementally add financial records/invoices/revenue/payroll/maintenance and
delivery, persistent logical identity, transactional save/load, independent full-
size document/blob storage, native iOS presentation/map and bounded diagnostics.
Keep incoming/outgoing transfers, cheques/images, proofs/receipts, searchable
history and extensible company industries in Docs/REQUIREMENTS.md.

20,000 COMPLETE assets remains future acceptance; 100,000 is an architecture goal.
R002 timings measure a small store on Linux/Mac, not flights, finance, persistence,
UI/FPS, memory footprint, energy or heat on the target iPhone 17 Pro Max.
Physical old-history deletion remains unresolved and must not be claimed complete.
Preserve exact next branch/commit, changes, failures, commands and evidence at handoff.
No background continuation is promised.
