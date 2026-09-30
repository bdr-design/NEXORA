# R004 — atomic priced-arrival financial boundary

Date: 2026-09-30 (Asia/Riyadh). This document describes the implemented narrow
in-memory financial boundary, not persistent accounting or full game acceptance.
Only the permitted R001-derived line is used. The permanent exclusion remains in
AGENTS.md. R003 publication base: ca0351757ce158c6320f962d1285c6f4aca2cf13.
Prepared R004 tree recovered intact: 69a9dceedcf973c02bd0d59d091f399095558ee1.
The first review candidate is 53cb86222f1529f8f48be4d00993c4ef03900311.

## Ownership and callers

TripSimulation exclusively owns AircraftStore, FinanceStore, journey rows and the
arrival heap. Standalone FinanceStore is separately useful for contract tests.
Neither owner exports its mutable stores. Public reads return detached values or
bounded pages. Process-local identity stamps are not persistent IDs.

The FinanceStore public apply path is prepare -> commit. Preparation validates
the ledger token, revision limit, positive minor-unit amount, chronological time,
remaining journal capacity, command-specific conditions and checked arithmetic.
A PreparedFinance plan is opaque outside its module and noncopyable. The package
coordinator may consume it once; a stale or foreign plan causes explicit fail-stop,
not a recoverable business error or silent repair.

## Economic meaning in this fixture

| Operation | Debit | Credit | Recognizes revenue? |
|---|---|---|---|
| Capital contribution | Cash | Contributed capital | No |
| Priced arrival | Receivables | Revenue | Once at arrival |
| Invoice collection | Cash | Receivables | No |
| Expense payment | Expense account | Cash | No |

All amounts are Int64 in minor units, in one immutable ledger currency. Currency
input validates shape, not membership of an ISO catalog. Balances never wrap;
credit magnitudes cannot reach the non-negatable Int64 minimum. Input time cannot
move backwards. Insufficient cash and overpayment leave the full state unchanged.
InvoiceOrigin consists of an aircraft capability and operation ID. The ledger
checks uniqueness; the trip coordinator authenticates the actual live operation.
Standalone invoice issuance is a caller-authorized ledger API, not proof of a
real completed flight. Receipts, views and journal rows are not image documents.

## Arrival transaction path

1. Validate the queued trip against the aircraft and journey row, including its
   due time and operation ID, before any event mutation.
2. For a positive fare, prepare the invoice/receivable/revenue posting without
   changing finance. Expected failures return a blocked progress result.
3. Complete the aircraft using its current token. Expected aircraft failure drops
   the unconsumed plan; finance, journey and heap remain unchanged for that event.
4. Consume and commit the prepared posting, change the journey destination, pop
   the exact heap head, publish actual reached time and append the completion.

There is no await, external callback, I/O or normal full-world snapshot inside
this path. No fallible user-supplied work is appended after aircraft completion.
The surrounding owner excludes intervening writers. Corruption, out-of-memory
termination or process death are not recoverable business failures and are NOT
made durable by this in-memory boundary.

Advance commits an explicit prefix. On a later block it returns all earlier
completions, the actual reached time and the remaining due event. It never claims
that the target time was reached over unprocessed events. Automatic arrivals do
not increment the manual input token. The token rejects stale resubmission but
is not a durable idempotency receipt or an asynchronous command queue.

## Bounded work and history

Invoice and journal capacities are fixed at initialization; the origin index is
reserved accordingly. History is not silently dropped or overwritten. Full
capacity backpressures before the corresponding event writes. It cannot currently
be drained to disk or enlarged through a persistence service, so capacity
exhaustion is a known stopping boundary, not a solved long-session save problem.
The page size limit is 256; no public read returns the entire history. Allocation
and timing guarantees beyond measured fixtures are not inferred from this design.
The allocating deep audit stays outside apply/prepare/commit/advance hot work.

## Staged review and regression evidence

The review reads source ownership first, then arithmetic/error precedence, then
cross-module arrival ordering, then independent-reference and corruption tests.
FinanceReferenceTests uses positive account totals and invoice dictionaries as an
independent model, four seeds and 5,000 commands per seed. It compares successful
and rejected results, invoices, balances and retained state. Earlier lifecycle
and unpriced-trip reference tests remain enabled.

FinancialPartitionTests adds a separate sorted-list financial oracle: two waves
of 97 aircraft, mixed priced/unpriced trips, deliberately tied arrival times,
partial and full collections, and three expense categories. It compares every
posted journal row and invoice to independently constructed expected records.
D01 varies event budgets (1, 7, 31 and 1,024) and target-time partitions. D02 injects
zero-prefix and one-prefix failures and compares retry output with uninterrupted
execution. This tests the declared serial ordering, not arbitrary reordering of
external commands or concurrent writers. Test results and counts belong in the
validation ledger only after the corresponding source has actually run.

## Remaining boundaries

No persistent world/entity/invoice identity, save/load, durable journal, database,
blob/document store, cheque/transfer workflow, scheduled payroll/maintenance,
delivery-obligation system, route catalog, iOS application or Metal renderer is
implemented by R004. Expense categories are postings, not full HR/maintenance
engines. The narrow 100k fixtures do not establish 20k full-feature gameplay,
physical memory, zero allocation, iPhone frame rate, energy or thermal behavior.
The next storage work must preserve old invoice origins after aircraft retirement
and keep document media outside hot economic state. Do not bolt fallible storage
onto an already-committed arrival and describe it as an atomic durable save.
