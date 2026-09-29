# Performance & Thermal Budgets

## Principles
- Remove unnecessary work before micro-optimizing.
- Stable frame pacing beats unstable peak FPS.
- Main/render-critical paths stay tiny.
- Simulation work is scheduled by due events and multi-rate domain cadence.
- No O(allAssets) work per render frame.

## Frame targets
60 FPS baseline budget is 16.67 ms. Internal target: main/UI and render preparation remain only a small fraction of this budget; heavy simulation/persistence does not enter it.

Higher refresh modes are allowed only when sustained on real hardware. Adaptive degradation may reduce visual work, labels, effects, map LOD or frame target under thermal pressure.

## Forbidden
- synchronous disk I/O on main thread;
- full-state serialization in normal save;
- full-world scans in render/UI paths;
- task/actor per entity;
- route recalculation every tick;
- state mutation for animation;
- large transient allocations in hot loops.

## Measurement
For relevant workloads record p50/p95/p99/max, frame/hitches, main-thread stalls, CPU/GPU, memory, allocations, I/O, scheduler backlog, queue depth and thermal state.

## Scale ladder
1k -> 5k -> 20k -> 50k -> 100k.

20k acceptance requires real routes, schedules, revenue/costs, payroll, maintenance, invoices, deliveries, persistence, queries and map activity—not synthetic IDs alone.
