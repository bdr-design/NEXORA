# NEXORA external-review rules — 2026-10-11

Read the repository-root AGENTS.md first. All source exclusions, economic and performance gates, cost and privacy limits, and the no-main-merge requirement remain in force.

## شرط المالك: جهد التفكير دائمًا أعلى مستوى

أمر المالك: «الشرط الاخر جهد التفكير دائما اعلى مستوى».
ينطبق على كل طلب نموذج خارجي في NEXORA، بما فيه اختبار الاتصال والمراجعة. لا تخفيض تلقائي للجهد من أجل السرعة أو المجانية أو اجتياز الاختبار. لا تغيير تلقائي للنموذج أو المزوّد عند الفشل. عند غياب دليل الإعداد أو تعارضه يتوقف الطلب.

تختار الأداة أعلى مستوى أصلي موثق يدعمه النموذج، وليس كلمة max عمياء. لا يُقبل high إذا كان xhigh أو max متاحًا. النماذج ذات وضع التفكير الوحيد تحتاج عقدًا أوليًا صريحًا وبيانات نموذج حية مطابقة. لا يعد نجاح الاتصال أو طول الإجابة أو عدد رموز التفكير دليلًا مستقلًا على أعلى جهد منفذ.

Keep model intelligence qualification separate from reasoning effort. Enabling max does not qualify a weak model or prove frontier performance. Do not add or substitute model IDs without the existing quality/cost review.

Require live reasoning support and provider.require_parameters=true. Remove no reasoning controls to make a failed request pass. Keep provider.allow_fallbacks=false, explicit free-model selection and zero-price restrictions. A timeout, quota error or truncated answer stays a failure; do not retry at lower effort.

Log requested configuration separately from verified execution. Never claim access to ChatGPT's internal effort selector: this bridge cannot inspect or change it. The historical owner authorization to continue careful local engineering remains distinct from evidence about external-model reasoning.

Read PROJECT_CONTINUITY.md in this directory for the tooling checkpoint. No NEXORA runtime, main branch, Apple acceptance or IPA result is authorized by a successful tooling check.
