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

قبل أي تعديل: اقرأ هذا التنبيه، وتحقق من فرع العمل وHEAD الفعليين، وأكد أن مصدر العمل هو R001 المصرح به وليس أحد الفروع المحظورة. سجّل التاريخ والفرع وHEAD ونتيجة المراجعة في Docs/Daily/YYYY-MM-DD.md، مع أحدث نقطة استمرارية في PROJECT_CONTINUITY.md. عند الشك في المصدر توقف عن التغييرات الحساسة. هذه قاعدة مراجعة موثقة وليست مهمة آلية مجدولة أو حماية GitHub تقنية.

Permanent exclusion: these three branches and their implementation content must never be used as development, build, repair, reference, recovery, test, schema, or benchmark sources. Their names appear solely as a denylist. This notice supersedes all earlier recovery-use language; it does not claim repository/history erasure. Check and record the allowed R001 source at every working-day/session handoff.

The owner's explicit current instructions take precedence over older project
notes. On 2026-09-30 the owner authorized a radical deletion and fresh start.

## Effort and continuity
Sensitive implementation requires the owner's very-high reasoning/effort gate.
Never claim a model setting that is not exposed or verifiable. If the gate cannot
be verified, stop sensitive work and limit work to safe inspection, documentation
and handoff. No release may be approved on an invented setting. Do not weaken
this rule to pass a gate.

Keep work bounded. At any loss of source identity or context reliability, stop
sensitive changes and record the exact commit, files, test commands and results,
known failures, and next safe action in PROJECT_CONTINUITY.md. Do not promise
background continuation. Chat is not durable project storage.

## Clean start
Do not import code, schemas, runtime files, or patches from Global Holdings,
retired NEXORA NXR-0001/2/3, or the abandoned repair workspace. Product ideas and
user requirements survive; technical implementations do not. Public language and
platform documentation may inform newly written code.

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
without diagnostic evidence and end-to-end acceptance. This notice authorizes
no force push, destructive history rewrite, repository deletion, or change to
another repository. It does not permit creating or retaining a recovery copy of
the disqualified implementation for future use.
