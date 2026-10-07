# R005 — نتيجة المرشح المؤهل وخطوة التحسين المحدودة

مصدر التنفيذ الحي المسموح عند فحص النتيجة:
`2b37ac12095a533d0a5e510e5f305998a127ca4e`، tree
`9b4c792af4ffeaf4b4a6f3a6521778760c8de880`؛ main `38ce39cf` ثابت.
AGENTS والاستمرارية قُرئا كاملًا قبل هذا العمل. لم يستخدم تنفيذ المرجع
أو أي فرع محظور. كل الإخفاقات السابقة وقاعدة 1.10 ثابتة.

## نتيجة خمس عمليات حفظ: فشل أهلية، وليست C100

run37553171073/job112573228179 أكمل workflow التشخيصي SUCCESS. نتيجة
المرشح نفسها **FAILED** في MICRO-ELIGIBILITY؛ نجاح جمع التشخيص لا يعيد
تصنيفها. Artifact11454046472، ZIP SHA256
`b075bb45943e3d0ac89fa82d3db8c96c23bdaf06c32e304400f8cad4555f0224`، طابق
التنزيل والتحقق المستقل. المصدر مؤهل وظيفيًا عبر artifact11453486037
على d415c96c؛ كل42runtime inputs وflags مطابقة، ولا تغيير للصيغة أو cadence.

| البوابة على H / 1M / 5 saves | القياس | الحد | النتيجة |
|---|---:|---:|---|
| beginSave p99 | 63,791ns | 100,000ns | PASS |
| advance أثناء الحفظ p99 | 1,340,417ns / 1435 عينة | 1,100,000ns | FAILED |
| overheadRatio | 1.464887101264954 | 1.10 | FAILED |
| paired allocations | 1435 عينة، violations0/maxExcess0 | تغطية كاملة وصفر تجاوز | PASS |
| idle allocations | 0 | 0 | PASS |
| queued bytes | 0 | تشخيص فقط | صفر، ليس بوابة C إضافية |

idle 7,343,049 events /772.718889ns per event؛ saving 990,822 events /
1131.945933ns per event. في الوضع الجديد capturing يغطي احتفاظ epoch حتى
إكمال الكاتب، وليس زمن النسخ وحده؛ writerOnly صفر calls. النسخ المقاس
212,405,831ns لخمس عمليات. طرحه كله من savingNS يعطي حدًا نظريًا يقارب
1.18745، أعلى من1.10. لا يكفي تحسين memcpy وحده، ولا هذا الطرح تجربة أداء.

## القياس المقارن ومحدداته

S فقط: fixture واحد1M، ABBA، نفس984calls و1M events والترتيب والـdigests
والاسترجاع بالضبط. advance والخدمة كلاهما zero allocations في كل الأذرع.
الحلقة الكاملة save/control تعطي1.517144688 و0.958237862، مع اختلاف توقيت
الأذرع حتى قبل حد الحفظ؛ لا استنتاج سرعة مستقر، ولا مقارنة C أو قبول H.
save-active advance المقارن أضاف189.448ms و143.849ms، بينما copy المقاس
6.666ms و9.930ms. service delta2.967ms و0.725ms، والكاتب294.931ms و292.675ms
بـ95801772B، queue0. أزمنة الكاتب تتداخل مع المحاكاة ولا تجمع معها.

تركيب pool خارج advance وbegin في كلا الأذرع تخصيص95,811,576B/6000calls؛
begin يخصص سجل control واحد18,876B. هذه الكلفة معلنة ولا تثبت قبول ذاكرة
التطبيق. sample الاستشاري بعد فشل المرشح نجح؛ snapshot النصي يسجل physical
footprint/peak210.4M في CI أثناء تشغيل H، وليس قياسًا مضبوطًا على الجهاز.
لا تستخدم timings تحت sample لتأهيل C، ولا تمزجها مع التشغيل الأصلي.

sample يُظهر EpochRowsView getter وSwift dynamic exclusivity/COW checks في
مسار المحاكاة. هذا دليل مواضع عمل، وليس نسبة سببية خاصة بالحفظ. الحذف
التام للنسخ لا يكفي؛ لا إذن لتعطيل exclusivity أو تغيير deadline أو إبطاء
idle عمدًا للحصول على ratio أفضل.

## الخطوة التالية قبل تعديل المسار الساخن

مرشح محدود داخل المالكين الحاليين: forced inlining للقراءات القصيرة،
تعديل صف H عبر inout محدود بدل read/modify/set متكرر، ونسخ hot/cold كلٌ
عند كتابة حقوله فعلًا. writer يستمر بامتلاك قيم immutable؛ لا يُرسل owner
mutable، ولا Unsafe أو unchecked Sendable. لم يُنفذ هذا المرشح في هذه النقطة.

التوقع: صفر تخصيصات advance/service كما قبل، freeze O(1) وسجل control نفسه.
inout لا يُسمح له بالهروب؛ ensureWritable يسبق كل تعديل، والـpre-write hook
يسجل النسخ فقط. mutable cold لا يُنسخ عند اكتمال حدث يعدل hot فقط، لكنه
يُنسخ عند origin/departure/reschedule ويحافظ على canonical epoch bytes.
لا تغيير معلن في نموذج الاقتصاد أو ترتيب wheel أو شكل snapshot.

تقليل getter calls وفحوص mutation قد يخفض زمن المحاكاة، لكنه تقدير مشروط؛
لا رقم speedup مضمون من sample. يُقارن source القديم والجديد في bounded
Debug/Release/TSan وcanonical/WAL/lifecycle أولًا. أي تقدم يؤهل إعادة A/B
على المصدر نفسه وTSan/K1–K10 S/H1M، ثم micro خمس عمليات، ثم100save للتخطيط
المحدد فقط عند أهلية حقيقية. لا timing retry للمصدر الفاشل ولا حملة100save.

قيود الإنتاج باقية: صورة spare كاملة لا تحقق ميزانية200B/asset على H بعد
احتساب كل الحالة، ولا تعادل احتياطي ADR القديم1MiB. تحسين وصول الصفوف لا
يعالج ذلك وحده. Stage2–4 وiPhone/IPA ودمج main وملفات النتائج النهائية
تبقى وراء C الحقيقي وقرار المالك؛ التصور الأولي منفصل ومعلن.
