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


## Global entity registry and domain storage
Global entity lifetime is owned by an Entity Registry using stable generational handles. A domain does not mint or destroy global identity.

A domain that uses packed storage maintains:
- `slot -> denseIndex` sparse mapping;
- `denseIndex -> EntityID/slot` reverse mapping;
- packed hot columns owned only by that domain.

Swap-and-pop must update the moved entity's reverse/sparse mapping in the same mutation. Detaching a component from a domain must not increment the global entity generation. Generation changes only when the global entity is destroyed/recycled.

## Compute / commit law
1. Capture a safe immutable/read view without introducing hidden full-buffer Copy-on-Write cost.
2. Perform bounded pure computation in parallel.
3. Produce bounded deltas with deterministic chunk identity/order metadata.
4. Validate revision/entity/invariant requirements before mutation.
5. Enter a short synchronous single-writer commit section.
6. Do not suspend or `await` once authoritative commit starts.
7. Apply all-or-reject according to the transaction contract; stale/invalid deltas cannot be silently skipped if the operation promises atomicity.
8. Publish events only after successful commit.

Cross-domain operations require an explicit transaction/coordinator contract; a revision check inside one domain is not sufficient to claim global atomicity.
