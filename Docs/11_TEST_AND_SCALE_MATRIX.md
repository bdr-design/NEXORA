# Test & Scale Matrix

## Correctness
Unit/invariant tests, transaction success/failure, idempotency/retry where needed, persistence round-trip and migrations.

## Determinism
Identical seed + event sequence must produce identical authoritative outcome where determinism is promised.

## Recovery
Kill during write, restart with journal/WAL state, migration interruption, document-media loss/hash mismatch, rejected transaction after calculation.

## Scale gates
1k, 5k, 20k, 50k, 100k.

## Mandatory 20k acceptance
20k assets with operations, routes, schedules, invoices, revenue/costs, payroll, maintenance, deliveries/logistics, saves, read queries and map activity.

## Performance scenarios
World map pan/zoom, filter/search, mass purchase/dispatch, fast simulation, payroll/financial close, invoice spikes, manufacturing batch spikes, save while UI active, large load, foreground/background, long document history.

## Metrics
p50/p95/p99/max latency, frame/hitches, main-thread stalls, CPU/GPU, memory, allocations, I/O, scheduler backlog, queue depth, transaction conflict/retry and thermal state.

Final performance/thermal certification requires real-device runs.
