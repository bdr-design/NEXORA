# NEXORA continuity — NXR-R001

## تنبيه إلزامي لكل مراجعة يومية أو دردشة جديدة — 2026-09-30

بأمر المالك، الفروع الثلاثة التالية مشطوبة من العمل نهائيًا ولا يجوز الرجوع إلى محتواها أو استخدامها أبدًا:

- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`

الأسماء قائمة منع فقط، وليست مصادر أو نقاط استرجاع. يمنع نسخ أو نقل أو دمج أو استعادة تنفيذها أو اختباراتها أو مخططاتها أو أرقامها. أي توجيه أقدم يصفها بأنها Recovery أو مرجع صالح للاستخدام ملغى. اقرأ التنبيه الدائم أعلى AGENTS.md وسجّل مراجعة المصدر في Docs/Daily/YYYY-MM-DD.md عند بداية كل يوم عمل أو جلسة استئناف.

شطب الاستخدام لا يعني حذف الفروع أو تاريخ Git. الحذف النهائي لم يثبت، ولا يجوز إعلان اكتماله أو الالتفاف على حجب أمان الأدوات. لا تُنشأ نسخة أرشيفية بديلة، ولا يُعاد تأسيس R001 من الصفر.

## آخر متابعة — D001 تصميم ومراجعة فقط — 30 سبتمبر 2026

طلب المالك إكمال المتبقي بدقة ومراجعة العمل على مراحل. بقي شرط التحقق من إعداد الجهد للتنفيذ الحساس غير محسوم؛ لذلك لم يُغيّر كود التشغيل ولم يُدّعَ إنجاز الأنظمة المتبقية.

أُضيفت [مواصفة دورة حياة أصل الطيران ومخزنه](Docs/Design/AVIATION-LIFECYCLE-D001.md) عند commit `44304236b51d267bebab550cca19345134f0aaed`، وبصمة ملف Git blob: `e605b151b2f855c9799b36b988fbec2b7184a84f`.

حالتها: DESIGN_REVIEWED / IMPLEMENTATION_BLOCKED / TESTS_NOT_RUN. تتضمن مالك الهوية والصفوف، وأوامر create/start/complete/retire، و12 ثابتًا، و32 سيناريو قبول غير منفذ. D001 رقم وثيقة تصميم، وليس إصدار تنفيذ جديدًا أو App Build.

أُجريت مراجعة ذاتية نصية على أربع مراحل: توافق المصدر، ودورة الحياة والفشل، والتكرار والأوامر المتأخرة، والتشخيص وحدود الأدلة. أهم القرارات: منع تعويض create بـdestroy، وربط الإكمال بمعرف العملية الحالية، وتوكن مراجعة خاص بالمخزن، وفصل فشل التشخيص عن نتيجة الأعمال. لم تُنفذ اختبارات المخزن أو نموذجه التسلسلي؛ لا تُحوّل السيناريوهات إلى أرقام PASS.

نقطة بداية هذه المتابعة: main وfoundation/clean-core عند `6bdf8529e389733ed85e6aa2d73231ad7c380a0b`، شجرة `e16e91c4f2b2d3ce70f091beeb0d2dd1aa28934f`. تحديثات التوثيق تحرك HEAD؛ أعد قراءته من GitHub ولا تعامل نقطة البداية أو commit الوثيقة بوصفه الطرف النهائي الحالي. لم يُجر حذف تاريخ أو قراءة محتوى الفروع المشطوبة.

## Current source and scope

Current implementation update: **NXR-R001**. Development version: 0.0.1.
Repository: `bdr-design/NEXORA` only. No app build or IPA.
Working branches: `main` and `foundation/clean-core`.
R001 initial code checkpoint: `rebuild/native-r001` at
`c45d24e0445219fc0db4df5efd0e920b5e129c16`; this is not a moving work tip.

Before the permanent-exclusion documentation notice, main and foundation/clean-core
were verified at `a4023fb365a628d8574b444b6e3d0501a1e8d6aa`, tree
`692958760caa6449015788fc64d0acfbc5f99e67`.
Read current remote HEADs again; documentation updates advance their tips.
Do not confuse a previously tested code commit with the current documentation tip.

Read AGENTS.md, Docs/REQUIREMENTS.md, Docs/DESIGN-R001.md,
Docs/VALIDATION-R001.md, Docs/Design/AVIATION-LIFECYCLE-D001.md and VERSION.json
before changing source. Docs/RESET-RECORD.md and earlier daily/change records
describe past events only; any recovery-use language there is superseded by the
permanent exclusion above.

Implemented from scratch: EntitySpace ownership/lifetime, Timeline envelope,
identity-only check executable, positive/negative compiler contracts and tests.
Not implemented: business stores, multi-domain transactions, scheduler, simulation
clock, persistence, iOS application, renderer, Apple diagnostics adapter, or a
full root-cause center. No gameplay scale or device-performance claim is made.

## Verified R001 checkpoints

Initial Apple CI: run `36646039605`, job `109669103488`, success.
Tested implementation commit: `c45d24e0445219fc0db4df5efd0e920b5e129c16`.
Tested tree: `3b3f8aee3e966dac3a330ff2f85b6ec4e2ebc910`.
Artifact ID: `11068189510`.
Recorded and previously verified artifact SHA-256:
`d801954fec29799915363762163eff1e9f3fc7eff94c8a783b21ebdd981f7a96`.

Second Apple CI: run `36646380334`, job `109670212517`, success, on
`a4023fb365a628d8574b444b6e3d0501a1e8d6aa` / tree
`692958760caa6449015788fc64d0acfbc5f99e67`.
GitHub job metadata previously reviewed shows Debug, Release, compiler, TSan,
both iOS library compile gates and identity lifecycle steps passed.
Artifact ID: `11068408969`. GitHub-reported digest:
`f830bb43248a162248e2980763c34381a4f9c971642831e8e9265813ac935db6`.
The second artifact was not downloaded/rehashed during the handoff review.
These are earlier R001 runs, not tests of the proposed D001 store. No new CI or
runtime-test result is claimed by this documentation entry.

## Remaining work — proposed order, not completed implementation

1. Repository governance: retain and review the permanent exclusion. Physical
   branch/history removal remains unresolved and must not be represented as done
   by a warning. Do not bypass the prior blocked destructive operation.
2. The bounded aviation lifecycle/store design is now documented in D001 with its
   failure boundaries and 32 NOT_RUN scenarios. Its implementation, independent
   serial reference, read-only test seams and executable tests remain outstanding.
   Do not restart the design merely because the chat changes. Resolve the owner's
   execution gate before sensitive code changes; review the documented limits.
3. After execution gates are satisfied: implement and test that small path, then
   add deterministic time/event scheduling and a minimal trip/result path with
   bounded work and diagnostic evidence. Broader shared parallel work comes only
   after a real serial workload and measurements. D001's serial revision token
   does not prescribe a game-wide revision-conflict bottleneck.
4. Incrementally extend the thin path with financial records, revenue, invoices,
   payroll, maintenance and delivery. Define persistent logical identity before
   persistence; design transactional save/load and separate document/blob storage
   for cheques, transfer proofs, receipts and other full-size media.
5. Add the native iOS presentation/map and bounded causal diagnostics, then test
   end-to-end correctness, save recovery, sustainable responsiveness, memory,
   energy and thermal behavior on the target iPhone. 20,000 complete assets is
   future acceptance; 100,000 is an architectural target, neither is proven.

The next allowed work while the user's very-high effort setting cannot be
verified is safe inspection, design documentation and handoff, not sensitive
implementation, integration, deployment or production approval. Do not claim
an inaccessible runtime setting or relax the gate to continue.

## Handoff discipline

For every working-day review and chat handoff: record date, actual branch/HEAD,
changed files, exact commands/results, known failures, limits and next safe step.
The excluded branches are never development or recovery sources. At any loss of
source identity or context reliability, stop sensitive changes. No background
continuation or scheduled daily execution is implied by these written rules.
