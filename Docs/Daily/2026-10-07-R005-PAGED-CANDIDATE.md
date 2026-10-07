# R005 — مرشح دمج الصفحات قبل تعديل المسار الساخن

7 أكتوبر2026، الرياض. المصدر المسموح الحيf09272dc5a194f4481b37b47350188153a40f865،
tree6d3ca63043081493ce6a9eaa1f22eac1059efebc؛ main38ce39cf ثابت. AGENTS
والاستمرارية قُرئا؛ المرجع والفروع المحظورة ليست مصادر تنفيذ. **مرشح تجريبي
مشروط، لا قبول C أو تنفيذ منتج**. يستمر نفس نموذجي SwiftWorld وHybridWorld؛
لا يعاد إنشاؤهما ولا يتغير اقتصادهما أو ترتيب الأحداث أو صيغة التقييم.

## الدليل الذي يبرر الاختبار التالي

Word/bulk micro run37539359684 SUCCESS، sourcef09272dc، artifact11447833132،
ZIP SHA256 `c0f089a134dc8983852f4b781c33cb451382fc4fd0827acb9173d66ef795987b`.
4096Debug/Release/TSan ثم100kRelease؛16legs×3epochs لكلmode، canonical frozen/live
equality وصفر scoped allocations فيRelease. TSan counters غيرمقاسةnull؛ الفشل
37537195946 محفوظ. الحدود1/3/7/8/9/15/255/256/257 أعطت10,543 field round-trips
مطابقة لـSnapshot.assetRecord الأصلي المستعاد من typed values.

bulk copy هي سبب تحسن النسخ: byteBulk0.240–0.467ms وwordSoA0.274–0.380ms
لكل6.5MB عند100k، مقارنةbyte-loop29–36ms. Word mutation4.283–5.804ms
لـ800kكتابة، مقابلrows1.175–1.350ms؛ أي قرار يحتاج تكلفة getters والمجدول.
الكاتب direct يلغي الوصول إلى mutable state والطابور المنسوخ، لكن التنازع
لم يغلق1.10 بعد. pacing يزيد زمنالحفظ، فلا يُختار دون دليل جديد.

## المالك ومسار التنفيذ المقترح

يبقى World مالكًا منفردًا للأصول والمجموعات وTimingWheel مالكًا للعقد. حفظ
واحد/epoch وكاتب واحد لكل دليل. خلف build flag تجريبي `EPOCH_PAGES` فقط:

- S: نفس13asset columns/7node columns ومجموعاتInt64، داخلword-packedSoA pages
  عند256/512/2048. متغيرات واجهات القراءة تصبح borrowed read-only views غير
  Sendable؛ لاsetter أومرجعmutable يهرب. أوامر المالك وحدها تكتبbuffer الخاص.
- H:HotAsset48B وEventNode32B داخلrow pages؛ cold fields20B فيword pages عند256،
  والمجموعاتInt64. نفس wire68/32/8 والحقولالمحجوزةصفر؛ لاcold row padding24B.
- Root منمستويين، pool metadata/pages يحضّر قبلsave ويحفظ تكلفته؛ freeze يحتفظ
  بroot قيمSendable ويثبت control record. first-write ينسخ إلىspare page محجوزة.
- الكاتب يستلمfrozen values فقط، يحولها إلىنفسv2 records وينفذنفسfooter/fsync/
  rename/dirsync/commit/cleanup. لاqueue copies95MB أوقراءةWorld منخيطالكاتب.
- الملكية المجمدة لا تُعاد للpool قبلrelease/acquire completion وإسقاطview.
  cancel للprepared writer غيرالمنشور يمنع thread leak عندرفضbegin. فشلwriter
  يبقىفشلًا ويتطلبrecover، ولا نجاح كاذب أوreuse مبكر.

الفرق فيsnapshot source والتمثيل والمجدول يوجب إعادةالقبول كاملة، حتىمعبقاء
الwire متطابقًا. النسخةالافتراضية دونEPOCH_PAGES تبقىمرجعالرجوع المسموح مننفس
الخطالحي، وليستنسخة منفرعمشطوب. تُقارن commands/transcript/errors/digests
والملفات canonical بين builds؛ لاperformance claim منالقيمةالمتطابقة فقط.

## التقدير قبل أي hot edit

| بند | التقدير والحد |
| --- | --- |
| S payload عند1M | 95.5MB، مع≤7B/page إضافية لكلمةجزئية؛ لاpadding9MB |
| H payload عند1M | 100.5MB وفق48hot+20cold+32node+0.5groups؛ لاcold row24B |
| pool | صورةpayload إضافية، buffers/directories/headers محسوبة؛ يحضرخارجbegin ولايخفىsetup |
| directories | حوالى5892pages/93leaves فيS؛ H يفصلhot/cold لذا refsأكثر، تقاسفعليًا |
| simulation idle | check page ownership زائدindirection/mask للword fields؛ خطر بطء A وليسمجانيًا |
| first write | copy صفحةواحدة ومعهاroot/leafmetadata أولمرة؛ zeroRelease allocations مستهدف، لا وعدزمن1M |
| begin | ثلاثةrootpins فيS، أربعةفيH وcontrol≈18.8KB؛ بنفسحد100µs، لاfull-world traversal |
| writer | scratch bounded للrecord/batch وcanonical digests؛ CPU/I/O الحقيقيانمقاسان خارجadvance وداخلloop |
| service completion | إعادةpool metadata O(pages)، تقاسمعallocations وزمنloop؛ لا تُنقللـUI |
| memory/device | process samples وowned capacities منفصلة؛ قبول17ProMax100k→250k→1M مازالNOT_RUN |

تقديرنسخ1M بضرب100k ليس بوابةقبول، والجدولةتلمسصفحات متناثرة، والكاتب ينافس
CPU/cache. لذلك التغيير يبدأ4096 functional/byte-exact/allocator micro تحت
Debug/Release/TSan، ثمfresh A. لا100-save حتى المرشحوالـA/B/K دليلهاصالح.

## ترتيب البوابات دون اختصار

1. بناء legacy وcandidate، تحقق byte/canonical/transcript والأخطاء والحدود،
   freeze/release والكاتبالفاشل/الإلغاء، micros4096 ثم100k للمسارالكامل.
2. A fresh علىS/H عند100k/1M/2M،10runs×3processes، controlsوالصفر والhealth
   والمفاضلةالقديمة نفسها. لا override لاختيارA أوإعادةتسميةfailure.
3. B source-bound:30days/60records والretentionquota وkill/continuation Debug/
   Release/TSan علىالمصدر الجديد أوإثباتتطابقكلinputs المرتبطةبـB. لاreuseلأرقام قديمة دونربط.
4. K1–K10 وtornWAL/recover→append→recover Debug/Release/TSan عند1M لكلlayout
   تغير. K10 يختبر peak retained epoch buffers صراحةإذازالqueue، معتسميةالدليل
   الصحيحة؛ لاادعاءqueued bytes غيرموجودة. SIGKILLليسpower-cut.
5. C unchanged1M/100save للتخطيطالذييسميهالدليل وA الصالح؛ overhead≤1.10،
   begin≤100µs، advance≤1.1ms والصفر/pairing دونتخفيف. artifact/source/flags
   وأدلةالدوراتتظلإلزامية. أيfailure يحفظوتتوقفقبلتوسعغيرمؤهل.
6. PASS حقيقي يعرضقرارالمالك قبلmain أوStage2–4. لاSTAGE-R005-RESULTS.md أوresults.json الآن.

التصورالبصريFIRST-LOOK مقترحقراءة فقط؛ لايشغلdomains جديدة أوأزرارغيرمنفذة.
تطويردورةالمنتج D005 لاحقلهذهالبوابة، معالسلاسةوالواقعية كشرطيقبول دائمين.

## تنفيذ محدود — Apple pending

المرشح الآن داخل World/TimingWheel الحاليين خلف EPOCH_PAGES. borrowed reads
لا setter لها، buffer ينسخ root/leaf/page إلى pool مُحضّر خارج begin، وrelease
يحتاج completion token لا يُنشأ قبل acquire للكاتب. frozen roots تُستهلك داخل
frame منفصل @inline(never) ينتهي قبل إعلان completion. prepared writers غير
المنشورين يُلغون عند الرفض/التدمير، وفشل الكاتب يمنع retry صامتًا حتى recover.
مسار v2 النهائي مشترك مع الكاتب الحي الحالي وبنفس footer/fsync/rename/marker/
cleanup. K10 token التاريخي يستهدف retained epoch buffers في المرشح صراحة،
مع queuedBytes=0؛ لا يغيّر دلالة نتيجة التشغيلات التاريخية.

القياس المحدود planned: baseline Release أمام candidate Debug/Release/TSan
على S/H عند1/3/257/513/4096 ثم100k Release؛ ثلاثة epochs متحركة مع WAL لكل
حالة، identical canonical fixture file/world digests/scripts/outputs/recovery،
Release zero advance/completion-service allocations، وTSan counters=null.
owner/overlap/stale/cancel/writer-error lifecycles تُرفض فعليًا. هذا لا يشغّل
A أو B أو C evaluator، ولا حملة100-save. Flags/source محفوظة لكل artifact.

## نتيجة الدمج المحدود ومراجعة K قبل التوسع

run37542773160 SUCCESS على1c4f9b84/treeac796a07، artifact11449188442 ZIP SHA256
141c0db68d817d62cf147dfab7b26606d78449d5d6f5aa8021b4b8903c5b98ea تحقق مستقل.
44حالة/132epochs/32مقارنة cross-build، six S/H lifecycle proofs، صفر allocations
لـadvance وخدمة completion فيRelease، معTSan null. S عند100k copy0.76–1.21ms
لـ9.55MB؛ H1.32–1.39ms لـ10.05MB. begin S5.25–5.54µs/H6.25–11.5µs.
الدوال التجريبية أبطأ فيadvance منbaseline فيهذااختبارالمقارنة؛ ليسقياس A
مضبوطًا، ولا يدّعي تحسنًا مطلقًا أو C. الأثر جزء من قرار A التالي.

الكاتب الجديد مستقل، فيمكنهcommit بينماmain متوقف عندkill hook. اختبار
K1 الآن بعدfreeze وقبلhandoff، وK2 وchain-after-WAL يحتفظان بالكاتب قبل
إطلاقه لتكوين incomplete snapshot حتمي؛ الوضع خاص بتجهيز kill fixture،
والحفظ المقاس يطلق الكاتب مباشرة. K3–K8 تتوقف فيخيطالكاتب نفسه، K9 بعد
commit ثمWAL torn frame، K10 قبلrelease للepoch retained. لاتُغيّر expected
recovery أوعتباتالأداء، ولا تعاد تسمية نتائجالتشغيلات القديمة. Prepared sink
له atomic reservation يمنع cancel/reuse بعدbegin؛ cancelled reuse يُرفض قبل
أيWorld write. جميعذلكيعاد فحصه bounded علىالمصدر الجديد قبلB/K.

Fresh proof التالي يبني A بـEPOCH_PAGES فقط، B/K بـSTAGE_C EPOCH_PAGES.
A100k/1M/2M×S/H و3processes×10runs بالصفر والhealth؛ ثمB30days/60records
وquotaمنحجمsnapshot1M جديد للتخطيط المختار، وكلB recovery وK1–K10/WAL
Debug/Release/TSan علىS/H. الـ1M fixtures ليستحملة100-save. C100 ممنوعة
فيهذاworkflow؛ لاreuseلـA/B قديمة، artifact يحتفظبsource/flags/inputs كاملة.

## مراجعة الذاكرة وأهلية C — ليست قبولًا إنتاجيًا

قبل نشر حملة C، أُعيدت مراجعة ADR وBUDGET-ADDENDUM وREVIEW-2. احتياطي
الصفحات القديم المقترح1MiB ليس ما ينفذه هذا المرشح: المرشح يحضر صورة
payload إضافية كاملة، ويُسجل ذلك صراحة. A يقيس الصورة الحية قبل تركيب
StageCState؛ لذلك نجاح128B/asset فيA لا يثبت ميزانية الحفظ أو التطبيق.
عند100k، القياس المحدود أعطى S live9,826,336B/prepared19,569,904B، وH
live10,619,328B/prepared21,157,456B. هذه owned capacities منWorld؛ لا تشمل
كل heap headers أوState أوكاتب/restore/واجهة، ولا تعني phys_footprint.

payload مجرد عند1M: S95.5MB/H100.5MB. صورتا H تتطلبان201MB قبل directories
والcontrols وبقية الحالة، فتتجاوزان وحدهما سقف200B/asset إذا حُسبت الصورة
الإضافية ضمن الميزانية الكاملة. لا يُستثنى pool من قبول الذاكرة الإنتاجي،
ولا يُرفع السقف. قبول الأداء التجريبي C، إذا حدث، لا يمنح هذا المرشح قبول
Stage2 أوDevice أوشهادة السلاسة. أي دمج إنتاجي يحتاج حسابًا وقياسًا كاملين
للذاكرة، وإعادة تصميم staging محدود إذا تجاوز الميزانية؛ لا حذف حقول أو
حقوق مالية للحصول على رقم أقل. لا توجد الآن قراءة peak physical memory
لـ1M أثناء الحفظ على الجهاز.

مسار القياس المؤهل بعد artifact كامل: خمس عمليات حفظ فعلية على تخطيطA
المختار، ثم paired S ABBA منfixture واحد يفصل advance/service/WAL/الكاتب/
الحلقة. MICRO-ELIGIBILITY يبقى خمس عمليات وacceptance=false، ويحفظ أسماء
بوابات الفشل؛ لا يعدل counts أويحوله إلىC. إذا فشل، يُجمع sample اختياري
لمواضع التنفيذ؛ أزمنة التشغيل تحتsample ليست مؤهلة للقبول. C100 لا يعمل
حتى تطابق42runtime inputs وflags، وثبوت A/B/S/H1M K/WAL، وartifact حقيقي
لـmicro مؤهل. لا تغيير للعتبات أوcadence أوdeadline أوالصيغة الأصلية.

نطاق الكاتب الجديد: writeNS يبدأ بعدhandoff؛ queueWaitNS هو انتظارhandoff
قبله، بينماrecordProcessWriteNS وfinalizeNS داخلwriteNS. لا يجمع الانتظار
معها بوصفه جزءًا داخلwriteNS، ولا تجمع wall times للكاتب والمحاكاة لأنهما
يتداخلان. service completion وpool setup يظهران في القياس، ولا تُنقل هذه
الكلفة إلىUI أوتُخفى تحت ادعاء تحسنadvance فقط.

التصور FIRST-LOOK HTML فُحص كمصدر قراءة بلاbuttons/inputs. محاولة screenshot
محلية توقفت قبلrender لأن Playwright لا يملك browser executable فيهذه
البيئة. لا يوجد ادعاء screenshot أوتحقق layout مرئي أوقبول iPhone. الملف
الأصلي يبقى متاحًا للمراجعة، ولا ربط بمحرك اللعبة أوأثر مالي له.

## تسريع إعادة الإثبات مع إبقاء التغطية كاملة — prepared / NOT_RUN

مراجعة اليوم عند2026-10-07T00:00Z: AGENTS والاستمرارية قُرئا كاملًا؛ الفرع
diagnostic/r005-design-1m-20260930 الحي73dffa999e902db6cdebcb66fc02c6eeb9ef10c1،
tree63b9a0fc3492498943375cc2cfe804a31858750c، main38ce39cf ثابت. المصدر هو
R001 وتحديثاته المسموحة فقط؛ لم يُفتح تنفيذ المرجع أوالفروع المحظورة.

workflow بديل prepared خلف marker مستقل `[r005-paged-parallel-proof]`:
يشغل A/B/bounded matrix بالأوامر الأصلية نفسها أولًا، ثم ستة jobs مطلوبة
Debug/Release/TSan × S/H لـK1–K10 عند1M وWAL continuation. fail-fast=false
يحفظ نتائج الأجزاء الأخرى عند فشل جزء؛ لا continue-on-error. job جمع أخير
يطلب نجاح جميع الأجزاء، ويطابق commit/tree و42runtime inputs وflags لكل
جزء، ثم يعيد التحقق من A/B/quota وكل ملفات التعافي. ملفات الأجزاء مستقلة
الأسماء، فلا يُستبدل دليل تخطيط بدليل آخر عند الجمع. Artifact قبول وظيفي
مجمع لا يكتسب صلاحية C حتى يمر verifier الكامل؛ الفشل أوالنقص يبقي C مفتوحة.

لم يُشغَّل هذا البديل بعد، ولم يُلغَ التشغيل التسلسلي37544554772. القياسات
الحساسة A وpaired/C تبقى داخل Apple host واحد لكل تشغيل/مقارنة؛ الأجزاء
الوظيفية المستقلة تسجل بيئات hosts مختلفة، ولا تُمزج أزمانها كقياس أداء.
Static YAML/Python/shell وexact A/B/bounded command equality اجتازت محليًا.
فشل harness أولًا بـKeyError:name لخطواتcheckout/upload غيرالمسماة؛ أصلح
harness فقط وحُفظ الفشل فيfailures.json. لا نتيجة Apple أوgate قديمة تغيرت.

مراجع أدوات المنصة الأولية فقط، لا مصادر تنفيذ لعبة:
https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
https://github.com/actions/upload-artifact/blob/main/docs/MIGRATION.md

قبل تشغيل البديل، ثبت القرار: إعادة A فيه تختبر wiring وقابلية التكرار،
ولا تختار نتيجة أكثر ملاءمة. مصدر قرار A المخطط لـC يبقى d415c96c / run
37544554772. pins في qualified-C تشير لهذا المصدر؛ لا تفتح حملة C100 من
فحص المسار الموازي. كل42runtime inputs متطابقة، والمصدر الساخن والصيغة
والـcadence لم تتغير. أي فشل وظيفي جديد يحفظ ويُراجع قبل تأهيل C.

## نتيجة قاعدة المسار الموازي — تحقق مستقل، ليس تأهيل C

مراجعة انتقال السياق عند2026-10-07T00:34Z: AGENTS.md وPROJECT_CONTINUITY.md
قُرئا كاملًا، live8603ca2580b4a6925c5eaed3c42274686ac75314/tree
c76bdb127985f6d16b570104564a5d9ff4e70817 مطابق لشجرة local6cde9f6c؛
main38ce39cf9322f47e4def5f6eddb425c5a66ea7f9 ثابت. المصدر المسموح فقط.

run37551200872/base job112566869260 SUCCESS. Artifact11453345274، ZIP
SHA25685c5cba318b05ce7dc4fe03a098bdf8295a91d50d2e3adcea0d938d795dfa59c
طابق التنزيل المستقل. فُحصت commit/tree، كل42runtime inputs/flags، SHA كل
ملف مصدر، guards قبل/بعد، raw A180samples وإعادة حساب medians/قرار A، كل
B60records والديسك/quota، B recovery بكل3modes، raw bounded44cases/132epochs
و32canonical equalities، وكل6lifecycle بما فيها cancelledReuseRejected.

| تخطيط A عند1M | median ns/event | owned B/asset قبل pool |
|---|---:|---:|
| S | 646.224005 | 97.485536 |
| H | 338.369115 | 105.408880 |

هذه إعادة قابلية تكرار لمسار CI فقط؛ قرارها H بنسبة0.5236096344022378 لا
يستبدل قرار A المختار مسبقًا من serial37544554772. الحصص على snapshot H
الحقيقي100,801,772B هي320MiB PASS /1472MiB REJECT /832MiB PASS. لا تُفرض
1408MiB الخاصة بصورة S السابقة على H، ولا يُعاد تصنيف رفض G1/W7 كقبول.

Release S وH1M K1–K10/WAL jobs SUCCESS وقت هذا checkpoint؛ Debug وTSan
لم يكملا، فلا SOURCE-FUNCTIONAL-PROOF كامل ولا C micro أوC100 بعد. raw ZIP
و37551200872-BASE-PROOF.json محفوظان تحتEvidence/20261007. لا قبول physical
memory أوiPhone أوإغلاق C على أي تخطيط من artifact الجزئي.

## الإثبات الكامل المحدد مسبقًا — مؤهل لفحص خمس عمليات حفظ

Serial run37544554772/job112545301174 SUCCESS عند2026-10-07T00:36:15Z؛
source d415c96c3b05b721960b3679c02f05a2aa3024da، tree
66842b4bcad9e9f145f956d050fcbe7cc7457aed. Artifact11453486037 ZIP SHA256
3897da2ed0201f4ab3adc8630900b261d11e967dfbb632f5e014bb2e75a1ab13 طابق
التنزيل المستقل. فُحصت42runtime inputs وكلsource hashes/guards/flags؛
raw A/B/bounded كما فيالتحقق السابق، وكل15recovery JSON معSHA مستقل.

A المختارة مسبقًا تختارH: S1M904.553076ns/event، H1M345.3889065ns/event،
ratio0.3818337648326122، H owned105.408880B/asset قبلpool. Raw180samples
3processes×10runs×6rows و2warmups/process، وضوابط allocator موجبة والصفر
لكلadvance، وhealth/mutants/order100k/1M. هذه ملكية live capacities وليست
شهادةذاكرةالحفظ. B60records وquotaH320/1472REJECT/832MiB وفق snapshot
100,801,772B. رفضG1/W7 باقٍ، وليسفشلًامعادتصنيفه.

Debug/Release/TSan×S/H:60K1–K10 SIGKILL points بepoch/digest المحددين،
6chain fallbacks عبرWAL، K9append→secondrecover فيepoch2 نفسه لكلجزء،
18torn2/8/54byte cases و12complete-corruption rejects. لاcut/power-loss
فيجهازحقيقي ولاcross-process lock. K10 token القديم يستهدف epoch retained
معsparebuffers وqueuebytes0، ولا يعاد وصفالنتائج القديمة.

SOURCE-PROOF.json وrawZIP محفوظان. Workflow C حُدّثتpins مصدره فقط؛
42runtime inputs ثابتة. الخطوةالتالية H1M/five-save diagnostic واحد، ثم
paired SABBA component diagnosis علىApple نفسه. C100 pins مازالت0/PENDING؛
لاينطلق100save مننجاحوظيفي. كلأداءC علىS/H OPEN إلىقبولحقيقي100save
ببواباتهاالثابتة، معقيدpoolmemory/مالك/main/Stage2–4/iPhone منفصل.
