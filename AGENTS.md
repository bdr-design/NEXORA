# NEXORA execution contract

## تنبيه دائم وملزم — 30 سبتمبر 2026

بأمر صريح من مالك المشروع، الفروع الثلاثة التالية **مشطوبة نهائيًا من العمل وممنوع الرجوع إلى محتواها أو استخدامها أبدًا**:

- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`

وردت الأسماء هنا للتعرّف على المصادر المحظورة واستبعادها فقط، وليست مراجع تطوير أو نقاط استرجاع. يمنع فتح محتواها بغرض التطوير أو البناء، أو نسخه أو نقله أو دمجه أو استعادة أي تنفيذ أو اختبار أو مخطط أو أرقام أداء منها، بما في ذلك cherry-pick. لا يوجد استثناء للاستخدام تحت اسم المراجعة أو الإصلاح أو الاسترجاع.

هذا القرار يعلو على أي عبارة أقدم تصف هذه الفروع بأنها Recovery أو Archive صالح للاستخدام، بما في ذلك PROJECT_CONTINUITY.md وDocs/RESET-RECORD.md والسجلات الأقدم. المصدر المسموح هو أساس NXR-R001 الجديد وتحديثاته المصرح بها فقط؛ لا يُعاد إنشاؤه لمجرد انتقال المحادثة.

**هذا شطب للاستخدام وليس ادعاء حذف فعلي للفروع أو تاريخ Git.** وجود الأسماء أو الأسلاف في Git لا يمنح إذنًا باستعمال التنفيذ المشطوب. لا تُنشأ له نسخة أرشيفية بديلة.

### مراجعة إلزامية في كل يوم عمل وعند كل انتقال للدردشة

قبل أي تعديل: اقرأ هذا التنبيه، وتحقق من فرع العمل وHEAD الفعليين، وأكد أن مصدر العمل هو R001 المصرح به وتحديثاته وليس أحد الفروع المحظورة. سجّل التاريخ والفرع وHEAD ونتيجة المراجعة في سجل اليوم، مع أحدث نقطة استمرارية في PROJECT_CONTINUITY.md. عند الشك في المصدر توقف عن التغييرات الحساسة. هذه قاعدة مراجعة موثقة وليست مهمة آلية مجدولة أو حماية GitHub تقنية.

Permanent exclusion: these three branches and their implementation content must never be used as development, build, repair, reference, recovery, test, schema, or benchmark sources. Their names appear solely as a denylist. This notice supersedes all earlier recovery-use language; it does not claim repository/history erasure.

## Execution authorization — latest owner decision, 2026-09-30

After being asked explicitly whether implementation/testing could proceed on an
isolated R001-derived branch without assistant-side proof of an internal effort
selector, the owner replied: "الجهد الداخلي الان pro كمل لاتشيل همه".
This is the owner's authorization to proceed with actual implementation and
staged tests. It supersedes the earlier stop pending that setting's verification
for this work. The assistant has NOT independently inspected or verified the
internal setting and must never claim to have done so. High-care review,
source isolation, concrete evidence and separate production/device acceptance
remain mandatory. Do not keep stopping at documentation because of the
superseded setting-proof blocker, and do not treat authorization as test evidence.

## Effort and continuity

Keep work bounded and review failures before moving to the next stage. At any
loss of source identity or context reliability, stop sensitive changes and
record the exact commit, files, test commands and results, known failures, and
next safe action in PROJECT_CONTINUITY.md. Do not promise background continuation.
Chat is not durable project storage.

## Clean start

Do not import code, schemas, runtime files, or patches from other projects or
excluded implementations. Product ideas and user requirements survive; technical
implementations do not. Public language and platform documentation may inform
newly written code. Only the permitted R001 line and its authorized successors
are implementation sources.

## Work discipline

Before a change: identify the state owner, public entry points, caller/callee
path, side effects, failure behavior, dependencies and test evidence. Use primary
sources for uncertain platform facts. Do not broaden a fix into unrelated work.
Verify public misuse, exceptional inputs, concurrency and lifecycle, not just the
happy path. Run both Debug and Release. Compiler and sanitizer success do not
prove logical correctness. Do not disable checks to obtain a green result.

## Performance and evidence

Keep synchronous work off the future UI critical path. No task, actor, or lock per
entity; no normal-save full-world JSON; no visual-motion writes to economic truth.
Measure before selecting an optimization or adding parallel shared workspaces.
Never equate record count, element stride or a smoke test with complete gameplay,
physical memory, zero allocations, frame stability, or thermal certification.
Document each update, including failures and limits. A new domain is not complete
without diagnostic evidence and end-to-end acceptance. No force push, destructive
history rewrite, repository deletion, or change to another repository is authorized
by this implementation update. Do not create a recovery copy of excluded code.
