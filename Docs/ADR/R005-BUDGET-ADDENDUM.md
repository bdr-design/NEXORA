# R005 budget addendum — required with the proposed ADR

Status: PROPOSED; no production change. Date:2026-09-30.
This addendum supersedes ONLY the fixed-pool subdivision and full proposed total
in ADR section3.1. The measured C prototype and its published outputs are unchanged.
It closes two accounting omissions in the initial design estimate: compact-to-durable
ContractID mapping and explicit space for ledger/policy/control tables.

## Measured versus proposed

Measured owned C allocations remain:80N+40E+40G+ceil(N/8)+33,024.
At1M,E=N,G=62,500:122,658,024 bytes. This is NOT the whole future engine.
Add a proposed8G-byte UInt64 durable ContractID column/map, not present in that
prototype. The complete proposed variable formula becomes
80N+40E+48G+ceil(N/8)+33,024.

Proposed4MiB fixed hot reserve, explicitly subdivided:

| Pool | Capacity assumption | Bytes |
|---|---|---:|
| Command/WAL staging | <=1024 bounded commands plus framed staging |1,048,576|
| Old-page/checkpoint staging | bounded reserve; backpressure if full |1,048,576|
| Read-page cache | open invoices/history pages, not every open item |524,288|
| Ledger balances | <=1024 ledger entities x64 accounts x8 bytes |524,288|
| Entity descriptors/revisions/counters | <=1024 x32 bytes |32,768|
| Policy binding/version tables | bounded combined8192 x32 bytes |262,144|
| Chart descriptors | <=64 x32 bytes |2,048|
| Remaining control/free-list/index descriptors | hard reserve, not unlimited |751,616|
| **Total** | fixed hot pools |**4,194,304**|

Normal proposed1M total:127,352,328 bytes=127.352328B/asset.
At2M normal profile:250,477,328 bytes=125.238664B/asset.
At1M withE=2N:167,352,328 bytes=167.352328B/asset.
At1M withG=N,E=N:172,352,328 bytes=172.352328B/asset.
E=2N andG=N exceeds200B/asset and must fail configuration admission.
The original126.852328B/asset estimate omitted8G bytes and is superseded.

These additional pools/mapping are a design reservation, NOT new measured
allocations. A Stage2 full-path allocator/footprint measurement must validate them.
If entity/account/policy/cardinality limits are insufficient, the owner must approve
a measured re-budget; increasing these settings cannot silently escape the formula.
Reverse/search indexes are disk-resident with bounded page cache and transactional
index deltas; an extra full resident index must be added explicitly to the budget.
Presentation/GPU/catalog/media resources are reported in the full application
physical footprint, not silently included in this economic-hot-state number.
No claim that128B already covers every implemented future feature is made.
