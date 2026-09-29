# State & Transaction Contract

## State Kernel
Owns entity identity, revisions, transaction boundaries, invariants, atomic commit and post-commit event publication only.

## Mutation contract
`Command -> Validation -> Domain/Pure Calculation -> Proposed Delta -> Invariant Check -> Atomic Commit -> Domain Events`.

No partial authoritative mutation is allowed. A failed command leaves authoritative state unchanged.

## Ownership
A mutable record has one domain owner. Foreign domains cannot mutate it directly.

## Read/write discipline
Hot reads should use compact typed views/indexes. Cross-domain reads that can tolerate lag use read models/projections. Critical consistency uses explicit contracts.

## Rollback/recovery
In-memory atomicity and durable recovery are separate concerns and both must be tested. Recovery never silently invents state.
