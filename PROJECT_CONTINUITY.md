# NEXORA continuity — NXR-R001

## تنبيه إلزامي لكل مراجعة يومية أو دردشة جديدة — 2026-09-30

بأمر المالك، الفروع الثلاثة التالية مشطوبة من العمل نهائيًا ولا يجوز الرجوع إلى محتواها أو استخدامها أبدًا:

- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`

الأسماء قائمة منع فقط، وليست مصادر أو نقاط استرجاع. يمنع نسخ أو نقل أو دمج أو استعادة تنفيذها أو اختباراتها أو مخططاتها أو أرقامها. أي توجيه أقدم يصفها بأنها Recovery أو مرجع صالح للاستخدام ملغى. اقرأ التنبيه الدائم أعلى AGENTS.md وسجّل مراجعة المصدر في Docs/Daily/YYYY-MM-DD.md عند بداية كل يوم عمل أو جلسة استئناف.

شطب الاستخدام لا يعني حذف الفروع أو تاريخ Git. الحذف النهائي لم يثبت، ولا يجوز إعلان اكتماله أو الالتفاف على حجب أمان الأدوات. لا تُنشأ نسخة أرشيفية بديلة، ولا يُعاد تأسيس R001 من الصفر.

## Current source and scope

Current implementation update: **NXR-R001**. Development version: 0.0.1.
Repository: `bdr-design/NEXORA` only. No app build or IPA.
Working branches: `main` and `foundation/clean-core`.
R001 initial code checkpoint: `rebuild/native-r001` at
`c45d24e0445219fc0db4df5efd0e920b5e129c16`; this is not a moving work tip.

Before this documentation-only notice, main and foundation/clean-core were both
verified at `a4023fb365a628d8574b444b6e3d0501a1e8d6aa`, tree
`692958760caa6449015788fc64d0acfbc5f99e67`.
Read current remote HEADs again; documentation updates advance their tips.
Do not confuse a previously tested code commit with the current documentation tip.

Read AGENTS.md, Docs/REQUIREMENTS.md, Docs/DESIGN-R001.md,
Docs/VALIDATION-R001.md and VERSION.json before changing source.
Docs/RESET-RECORD.md and earlier daily/change records describe past events only;
any recovery-use language there is superseded by the permanent exclusion above.

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
GitHub job metadata shows Debug, Release, compiler, TSan, both iOS library
compile gates and identity lifecycle steps passed. Artifact ID: `11068408969`.
GitHub-reported digest:
`f830bb43248a162248e2980763c34381a4f9c971642831e8e9265813ac935db6`.
The second artifact was not downloaded/rehashed during this handoff review.
These are earlier R001 runs, not a claim that the new notice commit was tested.

## Remaining work — proposed order, not completed implementation

1. Repository governance: retain and review the permanent exclusion. Physical
   branch/history removal remains unresolved and must not be represented as done
   by a warning. Do not bypass the prior blocked destructive operation.
2. Next bounded design: ONE thin aviation lifecycle/store contract, with a single
   owner of identity and business records, explicit create/transition/retire
   invariants, failure-without-partial-mutation rules and a serial reference.
   Specify stale/foreign identity, exhaustion, duplicate commands and injected
   failure tests before code. Do not start the scheduler or recreate old engines.
3. After execution gates are satisfied: implement and test that small path, then
   add deterministic time/event scheduling and a minimal trip/result path with
   bounded work and diagnostic evidence. Broader shared parallel work comes only
   after a real serial workload and measurements.
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
