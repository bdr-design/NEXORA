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

## تنفيذ مرشح محدود — Apple pending

تقدير الخطوة السابقة نُشر عند11907a64/tree059bd870 قبل تعديل hot path.
التنفيذ الجديد يحافظ على payload وcanonical bytes: getter قصير inline،
updateElement عبر borrow غير هارب بعد ensureWritable، وتجميع تعديلي node
consume وH schedule في mutation واحدة. لا تعطيل exclusivity أو COW أو أي
تحقق، ولا فرع timing يبطئ idle. cold setters الأربع تسجل أول نسخها؛ hot
completion لا ينسخ cold. بارير H يعد الآن الصفحتين الفيزيائيتين عند الحاجة
كلًا مستقلة؛ المقاييس التاريخية لم تتغير ولا يعاد وصفها.

أضيف فحص held-epoch حتمي257: اكتمال كل الأحداث ينسخ hot/nodes/groups فقط،
ثم reschedule قبل إطلاق الكاتب ينسخ cold20B/asset. يتطابق frozen snapshot
مع الحالة السابقة، وWAL recovery مع live mirror بعد إعادة الجدولة. هذا
حالة سلامة فعلية للحد الجديد، وليس استنتاجًا من compilation.

توقع حجم النسخ لفحص H100k كامل: السابق10,050,000B مقابل الجديد8,050,000B
لكل epoch لا يكتب cold. يبقى pool المحجوز كاملًا؛ هذه20% من payload copy
في هذه الحالة فقط، وليس وعدًا20% في الأداء أو الذاكرة. لا تخصيص advance/
service متوقع، لكنه يحتاج Release observer مع ضوابطه الموجبة وTSan مستقلًا.

bounded workflow يحفظ Default/Debug/Release/TSan canonical/mirror checks ثم
يفتح فقط commit d415c96c المسموح للمقارنة، دون قراءة أي فرع ممنوع. previous
runtime manifest يجب أن يختلف عن الجديد في أربعة ملفات hot/test المحددة
فقط، مع نفس flags. H100k old/new/new/old على المضيف نفسه، نفس ثلاثة epochs
والـfixture/transcript/digests؛ هذا workload يتضمن mirror تحققًا ولا يدعي
pure timing أو A/C. المجلد السابق يُحذف بعد الفحص، ولا يصبح تنفيذًا بديلًا.

local guard/selftest و23gate tests وdiff-check PASS. Swift/TSan والـborrow
والنسخ/الأزمنة ما زالت Apple pending. pins C صارت0/PENDING لأن42runtime
inputs تغيرت؛ دليل d415 لا يؤهل المصدر الجديد. لا micro1M أوC100 قبل إعادة
AB/K الكاملة على المصدر المؤهل التالي.

مراجعة حدود partial page بعد النشر e2b5e52f: فحص257 الجديد توقع5140B من
cold payload، لكن كلمة UInt64 الأخيرة تنسخ padding4B أيضًا، فالحجم الفيزيائي
5144B. الحساب صُحح إلى ceil8Bytes دون تغيير serialized payload أو التنفيذ
أو بوابات الأداء. تشغيل37554438056 الأصلي يستمر، وأي فشل لا يُعاد تصنيفه.

النتيجة الفعلية37554438056 **FAILED** عند00:57Z في Debug H257 بالرسالة
`cold mutation must copy and report every changed cold page`. كل5builds
اجتازت وS Debug lifecycle اجتازت؛ bounded matrix والمقارنة لم تنطلقا.
Artifact11453563427 ZIP SHA256
`d2abf84c48ca7347348ed7f58e96cd35f3655675e526c30a2a27e86944f74aab` تحقق
مستقلًا وحُفظ مع FAILED-COLD-TEST.json وfailures.apple. تصحيح الاختبار على
36675c81/treea57532c1 يجري في run37554761173؛ لا قبول من build وحدها.

## نتيجة المقارنة المصححة وخطة الإثبات التالية

run37554761173 **SUCCESS** على36675c8163191b58b6d39fe64654ee0327372165 /
treea57532c1470e62063d46cb04962496e2ec02a3cd. Artifact11453529085 ZIP SHA256
`84f5f1fc37363078f6faf6a6d6a876a3d54b88ee0030bb305005554c60f437aa` فُحص
مستقلًا:42inputs، guard/source hashes، schema/raw44cases و132epochs وكل
32canonical comparisons،6lifecycle مع cold held-epoch فيDebug/Release/TSan.
Release advance/service تخصيصات صفر؛ TSan unavailable=null كما في المصدر.
التشغيل37554438056 السابق يبقى FAILED في سجله وartifact محفوظًا.

H100k على host نفسه، old/new/new/old مع مطابقة ثلاثةepochs في كل ذراع:
median advance44,241,833.5ns مقابل37,116,332.5ns، ratio0.8389420049691204.
نسخ payload من10,050,000B إلى8,050,000B في كلepoch كما توقع العقد. كل raw
ملف وSHA وSource previous42inputs منd415 متطابق مع الإثبات السابق؛ الجديد
يختلف فقط بأربعة ملفات محددة. تباين الأذرع والأزمنة محفوظ، وworkload يتضمن
mirror/order verification؛ لا pure timing claim ولا تأهيلC من هذه النسبة.

قبل إطلاق أي A جديدة على المصدر: يُختار الآن run fresh-parallel التالي
وA الوحيدة فيه لاتخاذ قرار C لهذا المصدر. لا انتخاب بين تشغيلين أو بين
قرار d415 القديم وA جديدة. جميع42runtime inputs ثابتة بعد36675c81؛ تغيير
workflow/docs/evidence فقط يسمح بربطها. المسار الموازي السابق37551200872
له5/6أجزاء وظيفية ناجحة، وTSan S ما زال يعمل؛ ليس ادعاء إثباته المجمع بعد.

الخطوة التالية هي A كاملة/B60records/quota/recovery وDebug/Release/TSan×S/H
K1–K10/WAL عند1M دون تخفيف. C source/micro pins صفر/PENDING؛ لا خمس عمليات
مؤهلة أو100save قبل نجاح وإعادة فحص artifact كامل لهذا المصدر. الصورة
الاحتياطية الكاملة وقبول الذاكرة/الواجهة/الجهاز ما زالت مسائل منفصلة مفتوحة.
