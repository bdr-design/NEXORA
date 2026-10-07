# R005 — إعادة إثبات مرشح الوصول والنسخ

عند2026-10-07T01:29Z قُرئا AGENTS.md وPROJECT_CONTINUITY.md كاملين،
وفُحص المصدر الحي المسموح75b87557bece8985ae1759f4d7f2b3aec32be269 /
tree82ead4e1e956964b2eb0620eae79bf3fa4cecb3e. main ثابت38ce39cf9322f47e4def5f6eddb425c5a66ea7f9.
الفروع المحظورة وتنفيذ المرجع لم يُفتحا ولم يُستخدما. السلاسة والواقعية
وعدم نقل الكود أو الطرق تبقى قواعد ملزمة، وكل الإخفاقات السابقة محفوظة.

## الأساس الوظيفي والقرار المسبق

اختيرت A الوحيدة فيrun37555679620 قبل إطلاقه لقرار C التالي لهذا المصدر.
لا اختيار بين تشغيلات أو بين A الجديدة وقرار المصدر السابق. مصدر التشغيل
71432ea4b8fd73f3f79f6518eec43d8aa35c973f /
tree9abe68272432be9f4c26509b4efd5ac60eb484c7. كل42runtime inputs تطابق
مصدر36675c81 المصحح؛ الإضافات اللاحقة workflow/docs/evidence فقط.

source-base-proof **SUCCESS**، artifact11454882063، ZIP SHA256:
`d4747d376b8ac25dbf8e1293fac2bcf8ab933bf02b5ef9a5afc57aa7d16fcaa2`.
فُحص ZIP مستقلًا، ومطابقة المصدر والشجرة والـ42inputs والـguard والـraw
samples وحساب decisionA والأزمنة والـquotas ومقارنات الاسترجاع كلها PASS.

| القياس في A عند1M | S | H |
|---|---:|---:|
| median ns/event،30عينة/3عمليات | 525.7838705 | 244.401579 |
| owned B/asset،live فقط | 97.485536 | 105.408880 |
| أسوأ p99 advance من العمليات | 828125ns | 427375ns |

ratioHtoS1M=0.46483278151454827؛ اختيار **H** وفق قاعدة A غير المعدلة.
هذه مقارنة S/H لهذا التشغيل، وليست speedup قبل/بعد أو قياس RSS أو شهادة
سلاسة اللعبة. الصورة الاحتياطية الكاملة ما زالت مشكلة ذاكرة منفصلة.

B:30يومًا/60سجلًا على المصدر نفسه، snapshot H1M100801772B، quotas320MiB
PASS/1472MiB REJECT/832MiB PASS. Debug/Release/TSan:5SIGKILL points و8حالات
manifest recover→append→recover لكل mode، وحالات الفساد والرفض PASS.
bounded44cases/132epochs/32canonical comparisons و6lifecycle PASS، بما فيها
H cold mutation قبل إطلاق الكاتب في257asset. Release advance/service
zero allocations؛ TSan unavailable=null، وليس صفرًا مفترضًا.

## ما زال معلقًا

الأجزاء الستة المطلوبة K1–K10/WAL عند1M لم تكتمل جميعها وقت هذا السجل.
نجاح الأساس لا يؤهل C وحده؛ prerequisite pins ما زالت0/PENDING. بعد اكتمال
المصفوفة يلزم تحقق مستقل للـaggregate وraw والمصدر قبل خمس عمليات حفظ
حقيقية.100save فقط إذا اجتازت الخمس كل البوابات، ومنها overheadRatio<=1.10.

دراسة writer-packet المنفصلةrun37557127125 نُشرت على75b87557؛ تنسخ فقط
المصدر الحالي المسموح إلى حزمتين مؤقتتين. لا تعديل لمدخلات42runtime الجاري
إثباتها، ولا تأهيل C من هذه الدراسة. C OPEN على S/H، ولا result files أو
دمج main أو تنفيذ Stage2–4/iPhone/IPA قبل بواباتها وقرار المالك.

## اكتمال الإثبات المجمع قبل قياس خمس عمليات

run37555679620 كله **SUCCESS**: الأساس والأجزاءالستةDebug/Release/TSan×
S/H1M والـaggregate. Artifact11456810824، ZIP SHA256
`a5c8f89a56b8b40c51e2da8fbe8a2f460953a6a15b89b2d07672d6aea8c0d52a`.
verify-source-proof.py أعادتحققكلملفbase معhashه، وجميعmetadata source/
tree/42inputs/flags لكلجزء،10points المطلوبةبالترتيبوالـepochs،15raw
functional hashes، وA/B/quota.60kills/6chains/18tornWAL و12complete-corrupt
rejections كلهاPASS؛ لا تغييردونإعادةمصدر، ولاانتخابA بديلة.

C workflow source pins تربطهذاartifact فقط، والـmicro pins تبقى0/PENDING.
الخطوةالآن H1M خمسعملياتحفظ حقيقية، ثم paired S منالمصدر نفسه. هذا قياس
أداءتشخيصي فقط؛ مشكلةmemory الجديدة210.77232B/asset معلنةفيH paired،
ولا يجوزاعتبارنجاحC المحتمل قبولًاللمنتجأومراعاةللقاعدةالدائمةدونإصلاحها.
C100 مازالNOT_RUN وS/H C OPEN، وكلالإخفاقاتوالبوابات1.10 ثابتة.
