# R005 — دراسة كاتب مستقلة، ليست تعديلًا للمصدر المؤهل

المصدر الحي المسموح71432ea4/tree9abe6827، main38ce39cf ثابت. إعادة الإثبات
37555679620 تعمل على المصدر المحسن؛ A الخاصة بها اختيرت مسبقًا. AGENTS
والاستمرارية مقروءتان، ولا مصادر تنفيذ من المرجع أو الفروع المحظورة.

قبل أي تطبيق: الدراسة تنسخ Package/Sources الحالية فقط إلى مجلدي build
مؤقتين في job مستقل. لا تُغيّر أيًا من42runtime inputs الفعلية، ولا تستبدل
نتيجة A/B/K/C الجارية. patch الدراسة لهSHA مستقل وsource hashes لكل ذراع.
إثباته محدود4096 و100k؛ لا100save ولا qualification على1M.

## التقدير قبل القياس

الكاتب الحالي يكتب غالبية records بمكالمة write لكل نصف payload، ثم write
للـSHA32B. المقترح يجمع checksum في scratch الحالية بعد parse/hash، ثم
يكتب record كاملًا. عند5893chunks في1M، العدد الاسمي عند full writes دون
EINTR/short-write من17,678 إلى5893 body/checksum writes؛ prefix/footer/fsync
والـcommit/directory sync تبقى كما هي. هذه أعداد مستنتجة من المسار، وليست
syscall telemetry فعلية أو وعدًا بنسبة سرعة. helper write الأصلي يبقى
مسؤولًا عن EINTR/short write ولا يهرب pointer أو يأخذ mutable world.

المحاكاة لا يتغير كودها أو تخصيصاتها؛ الأثر المحتمل الوحيد تنازع الكاتب.
scratch32KiB الحالية تسع أكبر record مع32B checksum؛ لا صورة عالم إضافية
ولا pacing. append للـdigest يفترض uniqueness بعد عودة parseRecord؛ إذا
ولّد COW للـscratch فسيظهر في writer allocation bytes، ولا يُفترض صفرًا.
تُقاس كلفة الكاتب والتخصيصات والنتائج قبل اختيار دمج. لا تعطيل hash/parser
أو تحسين clock/cadence/idle للحصول على ratio.

K3 fixture يبقى split عند **نفس prefix payload** القديم، ثم hook نفسها؛
تختار بيئة kill الكسر مرة واحدة خارج loop. الوضع العادي record متصل مع
checksum. لا تغيير لتعريف recovery أو footer/canonical digest أوعدد bytes؛
حساب bytesWritten يتضمن checksum مرة واحدة. كل fixtures/mac modes تسجل
K3 SIGKILL فعلية عند4096 وتحقق نفس digest من snapshot1.

## دليل الدراسة وحدوده

Debug/Release/TSan × S/H × base/packet عند4096: canonical files وWAL recovery
ومقارنة digests/transcripts عبر3epochs لكل حالة، وK3 لكل جزء. Release يقيس
advance/service zero allocations مع positive controls؛ TSan counters غير
المتاحة null. بعده H100k base/packet/packet/base على المضيف نفسه، مع writer
time/allocated bytes لكلepoch. raw ملفات وSHA محفوظة. المقارنة تتضمن
mirror validation مثل bounded workload، ولا تعتبر C أوiPhone smoothness.

حالة هذه الوثيقة: **PREPARED / NOT_RUN**. حتى نجاحها لا يجيز دمج patch أو
تشغيل C100: إذا فشل المرشح الجاري C يُراجع السبب أولًا، وأي تطبيق في runtime
يلزمه bounded checks ثم A/B/TSan/K1–K10 S/H1M ومصدر مؤهل جديد. الصورة
الاحتياطية الكاملة والميزانية الإنتاجية والجهاز ما زالت مفتوحة.

## إخفاق إعداد الفحص وتصحيحه

run37557127125 FAILED، artifact11455177130، ZIP SHA256
`de778aa7e392ee4f23890e0fbea221e26d4dc3b41a159f76c48b7c43e12e375e`.
الستة builds اجتازت، وbase Debug S4096 canonical/WAL على ثلاثةepochs
اجتاز؛ الأمر الحالي crash-bootstrap رفض4096 بـinvalid: stage C crash
population. K3 والمقارنة ABBA لم يُنفذا، فلا نتيجة أداء لهذه المحاولة.

الفحص المباشر لعقد CLI أثبت أن crash-bootstrap يقبل1M فقط. التصحيح إعداد
workflow فقط:12حالة K3 لكلS/H×Debug/Release/TSan×base/packet عند1M، لا
توسيع للـguard. مصفوفةcanonical المحدودة تبقى4096، والمقارنةH100k كما
خُطط. لا تعديل للمصدر الفعلي أو بوابة أو معنى اختبار؛ التشغيل السابق
يبقى FAILED محفوظًا. الـ1M هنا SIGKILL محدودK3، وليس حملةC100.
