# Events & Scheduling

## Discrete-event principle
The scheduler executes work when something is due. Idle entities do not self-update continuously.

Examples: departure, arrival, invoice due, production completion, payroll, maintenance threshold, market batch.

## Scheduler candidates
Priority heap, bucketed calendar and hierarchical timing wheel are candidates. Selection requires NEXORA benchmarks; no implementation is chosen by taste.

## Event envelope
SequenceID, SimulationTime, Domain, EventType, EntityID/aggregate ID, CauseID/TraceID, payload reference.

## Ordering
Domains declare ordering requirements explicitly. Handlers that may be retried must define idempotency behavior.

## Multi-rate
Rendering, operations, markets, accounting, payroll, macroeconomy and maintenance run at their natural cadences rather than one global tick.
