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
