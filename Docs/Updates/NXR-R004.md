# NXR-R004 — priced-arrival finance core

Date: 2026-09-30. Development version: 0.0.4. App build: none. No IPA.

Implemented FinanceStore with a single owner, exact minor-unit amounts, bounded
invoices/journal, unique invoice origins, partial collection, cash expenses,
checked limits and detached paged reads. Capital is not revenue; collection does
not recognize invoice revenue again. Invoice history survives aircraft retirement.
TripSimulation prepares finance before completing a priced arrival, then commits
both within the non-suspending owner. Expected failures preserve the current event
and return the exact already-completed prefix. This is in-memory atomicity, not
durable commit or recovery after process death.

The resume review removed whole-input byte-array copying in CurrencySpec and added
oversized-input and independent financial partition/retry tests. The 95-file
reviewed tree matched locally and in Apple exports. Source and limitations are in
../Design/ATOMIC-FINANCE-R004.md and ../VALIDATION-R004.md.

Final tested code: 674c94e145f24dc6c4c9addaa5aa07d1c9d4a168.
Apple run 36679204017/job 109770742356: 142 named tests in each Debug/Release/TSan,
29 compiler rejections, five valid clients, 12 isolated probes and five iOS library
compiles passed. Full raw fixture evidence and hashes were verified.

Performance is NOT accepted as a hard bound: a 20k fixture observed an arrival
batch at 20.050916 ms and a collection page at 16.267500 ms. Their causes are not
established. The other successful gates do not erase these observations.

Still absent: persistent identity/storage/recovery, documents/media and treasury
workflows, scheduled HR/maintenance/delivery, real routes, iOS app/map and phone
acceptance. The permanent exclusion and explicit implementation permission in
AGENTS.md remain unchanged. No force push, retired-code use or destructive cleanup.
