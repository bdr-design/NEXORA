# R005 — تحليل القياس المقترن S، 7 أكتوبر 2026، الرياض

قبل التحرير قُرئت AGENTS والاستمرارية، وHEAD الحي
`b2fb3bb5268ba7d5650d2aba1f256431f99822fa` على الفرع المسموح؛ main ما زال
`38ce39cf9322f47e4def5f6eddb425c5a66ea7f9`. لا مصدر من فرع محظور أو طريقة من
المرجع. قواعد المالك عن الفكرة فقط والواقعية والسلاسة منشورة في هذا HEAD.

القياس تشخيص مستقل عن بوابة C: source
`756d2e92b92b1f65b8e54cf05bc40529ed81bd67`، tree
`200520a6d5514dff5032fcc0d7dfc9913ba68fbc`، run37534787303 SUCCESS،
job112512863132، artifact11446371022. SHA256 للـZIP المنزّل والمقارن ببيانات
GitHub هو `d5fcf8fe72607cabbc717448299c0903193f462085299ce81158de8b38703c7c`.
حُفظ ZIP الأصلي كاملًا وتحليل آلي بأسماء ودجست كل ملف تحت Evidence/20261007.
Apple Swift6.1.2/Xcode16.4/macOS15.7.9، arm64. نفس عامل CI، لكن دون تثبيت
CPU أو الحالة الحرارية؛ لا ادعاء جهاز ثابت أو شهادة iPhone.

## ما ثبت

Debug/Release4096 smoke ثم Release1M ABBA. في كل ذراع984 استدعاء ومليون حدث؛
نفس fixture وevents/workUnits/stop/reached في كل استدعاء، ونفس output hash
ودجست النهاية والاسترجاع. كلا الذراعين يثبت StageCState عند64 ويكتب WAL
ويعيد الجدولة نفسها. حفظ واحد في كل ذراع save، دون evaluator C.

| قياس | زوج1: no-save ثمsave | زوج2: save ثمno-save |
| --- | ---: | ---: |
| advance كامل: control / save | 126.519 /202.099 ms | 167.436 /202.189 ms |
| نسبة advance للتشخيص فقط | 1.5974 | 1.2076 |
| فرق advance عند capture على نفس الاستدعاءات | +21.951 ms /39calls | +38.812 ms /25calls |
| فرق advance عند writer-only على نفس الاستدعاءات | +51.977 ms /812calls | −3.461 ms /764calls |
| barrier copy المقاس ضمن advance | 17.639 ms /55.835MB | 33.705 ms /55.051MB |
| تخصيص advance +service | 95,782,816 B | 95,782,816 B |
| service: control /save | 0.026 /20.569 ms | 0.031 /12.419 ms |
| reschedule: control /save | 49.435 /120.308 ms | 67.551 /60.861 ms |
| WALadvance: control /save | 11.008 /17.738 ms | 13.006 /14.120 ms |
| الحلقة كاملة: control /save | 192.574 /366.803 ms | 254.120 /295.525 ms |
| writer run /process-write /finalize | 225.450 /214.901 /8.425 ms | 202.176 /191.373 /8.282 ms |
| queue peak | 75,460,416 B | 74,576,448 B |

Capture يضيف عملًا وتخصيصات فعليين على خيط المحاكاة؛ يمكن استهدافهما.
Writer-only وreschedule يختلفان كثيرًا بين الزوجين؛ لا يثبت هذا القياس أن
تنازع الكاتب وحده سبب ثابت أو أن حذف النسخ يحقق1.10. المقارنات على الاستدعاءات
المطابقة أصح للتشخيص من نسب phases ذات workloads مختلفة، لكنها دون deadline
وتستعمل clocks لكل record وallocator interposition؛ ليست نسبة C الرسمية.
زمن الكاتب يتداخل مع خيط المحاكاة، فلا تُجمع أزمان الخيوط لإنتاج زمن الحلقة.
الاسترجاع والنقل خارج الحلقة ومثبتان منفصلًا في raw JSON؛ لا يُخفى ثمنهما.

## المرشح وتقديره قبل أي تغيير hot path

Micro أصلي معزول، لا يغير Core.swift أو Hybrid.swift أو تمثيل S/H أو بروتوكول
الحفظ. يختبر صفحات assets فقط عند4096 ثم100k إذا نجح المحدود؛ هذا لا يثبت
scheduler أو snapshot أو اقتصاد اللعبة. يقارن row بstride72 بpackedSoA65B،
ويختبر root من مستويين ونسخ first-write إلى buffers محجوزة قبل الزمن المقاس.
الكاتب يحصل على root ثابت Sendable بقيم Swift؛ لا يصل إلى state المالك.
لا unchecked Sendable أو pointers جديدة أو lock لكل أصل أو mutable root مشتركة.

| تكلفة متوقعة | قبل القياس |
| --- | --- |
| freeze | احتفاظ O(1) بجذر قيمة؛ صفر تخصيص داخل freeze؛ إنشاء الكاتب يقاس منفصلًا |
| أول كتابة بعدfreeze | نسخ root directory صغير ثمleaf metadata عند أول لمس؛ buffers محجوزة مسبقًا |
| أول كتابة لصفحة | نسخ صفحة كاملة؛ لا ادعاء اختفاء النسخ أو مجانية الصفحة |
| كتابات لاحقة | فحص epoch/page ثم تعديل ملكية واحدة؛ يُقارن بمرجع دونحفظ |
| assets عند1M: packedSoA /rows | 65MB /72MB للصورة؛ spare image تضاعف هذا الجزء |
| full S image تقديري | 95.5MB payload قديم؛ rowassets+nodes تزيد قرابة9MB قبلheaders |
| metadata عند1M full world | 5892pages، 93leaves من64، refs≈47.1KB لكل directory كاملة |
| الثمن خارجadvance | إعداد pool +استعادة الملكية بعد الكاتب يقاسان منفصلًا وضمن زمن دورة micro |
| writer contention | direct frozen walk مقابل paced batches؛ زمن الكاتب والنوم والحلقة يظل ظاهرًا |

يبدأ اختبار تنازع الكاتب دون IO ثم hashing/writing محدود من نفس fixture؛
قراءة صف أو نصف حقوله لا تعد إثباتًا لبروتوكول v2. pacing لا يغير أحداث
المحاكاة ولا timer C؛ قد يقلل الضغط ويطيل الحفظ، فيُقاس الثمن كاملًا. الاختبار
يتحقق من ثبات frozen digest وتطور live digest بمقارنة مرجع مستقل، تكرار epoch
وعدم إعادة استعمال buffers قبل انتهاء الكاتب، رفض freeze المتداخل، Debug
وRelease وTSan. أي إخفاق يُحفظ ولا يُعاد تصنيفه. لا حملة100-save من هذه الوثيقة.

C مفتوحة على S/H و1.10 ثابتة؛ 36875130222 و37505451077 وكل المرشحين المرفوضين
يبقون failures. تمثيل جديد، إن ثبت مرشحه، يستلزم A وB المرتبط بالمصدر وTSan
وK1–K10 ثمC1M/100 للتخطيط المحدد ومراجعة المالك قبلStage2–4.

نتيجة تحقق محلية محفوظة: بعد إضافة أوامر المالك إلى AGENTS فشل source guard
عند hash الوثيقة القديم. عُدّل pin الوثيقة فقط إلى SHA المنشور453bd7d0؛ لم
تُغيّر pins كود Sources/Tests/Checks/Package أو workflow القديم. guard وselftest
نجحا بعد الإصلاح. الفشل مسجل فيfailures.json ولا يختلط ببوابةC. تشغيل التحضير
37534787220 على756d2e92 نجح في jobs contracts/diagnostics/layout؛ ليس تطبيقiOS.
المحلل الجديد يقبل الدليل الأصلي ويرفض ست حالات عبث بالهوية/deadline/transcript/
recovery/writer/control hooks. micro الملكية لم يُبن على Apple بعد.

## أول نتيجة micro محفوظة — فشل لا يُعاد تصنيفه

run37537195946 عند7ad7ab58/treee41a430e **FAILED**. Debug/Release/TSan builds
نجحت؛ Debug/Release4096 أعادا24epoch مطابقين للمرجع لكلmode. Release رصد صفر
تخصيص ضمن freeze/mutation/release؛ Debug رصد تخصيصات generic loops غير محسنة،
فلا ادعاء صفر فيه. تشغيل TSan فشل معايرة C/Swift allocator، ملف JSON فارغ
وstderr محفوظ؛ validator لم ينفذ و100k SKIPPED. Artifact11447265073، ZIP SHA256
`d42c2fafa1fc4a070f3f58443c1a4b247caf260680337fcf378f0e2c15c68261`.

تصحيح القياس، دون تغيير مرشح الملكية: Release يبقى بمعايرة إلزامية وبوابة
صفر تخصيص micro؛ Debug يعرض الملاحظات الحقيقية دون ادعاء صفر؛ TSan يتحقق
التزامن والدورة بنفس التنفيذ دون interposer، مع null وتصريح عدم إتاحة
التخصيصات. هذا الفصل لا يقبل قياسات مفقودة ولا يمس1.10 أو البوابات الأصلية.
يحتفظ التشغيل الأول بحالة FAILED ودليله. وثيقة D005 تصنف دورة المنتج المقترحة
NOT_IMPLEMENTED؛ لا قسم أو زر مضاف للعبة منها.
