# NEXORA — Master Reference

NEXORA is a clean-room, native, global enterprise-management simulation. It is not a rewrite or migration of the previous game.

## Founding directives
- Never break an execution path or build randomly.
- Never patch a symptom before tracing the whole functional path and dependencies.
- Research authoritative sources before high-impact technical design.
- Maintain a preventive architecture/performance wall.
- Sensitive implementation stops if the active agent cannot meet the required very-high capability/effort gate.
- When context becomes heavy/unreliable, stop sensitive changes and write a repository handoff.
- Record how the game, engines and functions work in the repository.
- Previous game = ideas/features only; absolutely no technical reuse.
- New company/industry types must be addable without rebuilding the kernel.
- Smoothness, sustained thermals and realistic depth are primary goals.

## Product identity
The player may build holdings, subsidiaries, business units and facilities across aviation, maritime, road transport, banking, energy, manufacturing, retail, logistics and future industries such as cars, dairy and mobile-device manufacturing/sales.

## Scale contract
- 20,000 fully functional assets = minimum acceptance.
- 100,000 assets = architecture design target.
- 100k stored assets never implies 100k updates per frame.
- Only due simulation work is processed; only relevant/visible objects are rendered at detail.

## Architectural thesis
- Native iOS, Swift-first.
- Metal-backed high-density map/rendering.
- Modular monolith with strict bounded domains.
- Single-owner mutable state.
- Discrete-event and multi-rate simulation.
- Data-oriented hot paths.
- Event-driven cross-domain integration.
- Indexed read models for UI.
- Incremental persistence.
- Diagnostics/black-box tracing from day one.
- Thermal-aware workload/render adaptation that never changes simulation outcomes.

## Core rule: avoid work
Do not update every asset every frame, recalculate unchanged routes, rebuild finance books every tick, write state for visual motion, load cold history into hot memory, decode document images when only metadata is needed, or scan the whole world for a 50-row UI query.

## Organizational model
`Holding -> Subsidiary -> Business Unit -> Facility`

There is no closed `CompanyType` switch. Companies are composed from reusable capabilities such as Finance, Treasury, HR, Payroll, Sales, Procurement, Inventory, Manufacturing, BOM/Recipe, Logistics, Facilities, Maintenance, Quality, Contracts, Compliance, Tax, R&D, Warranty, Customer Service, Marketing and Pricing.

Industry extensions supply sector-specific rules but cannot duplicate generic engines.

## Simulation model
Render time and simulation time are separate. Assets schedule meaningful future events instead of self-updating continuously. A flight stores departure/arrival/route operational truth; visual position is derived by rendering and does not mutate simulation state.

Different domains operate at natural frequencies: rendering 60/120-class, UI event-driven, operations scheduled, markets aggregated hourly/daily, accounting event/close driven, payroll scheduled, macroeconomy daily/monthly, maintenance usage-triggered.

## State and transaction law
The State Kernel is intentionally small: entity identity, ownership, revisions, transactions, invariants, atomic commits and post-commit event publication. It contains no airline, finance, HR, route or rendering business logic.

Cross-domain mutation follows:
`Command -> validate -> pure/domain calculation -> proposed delta -> invariant check -> atomic commit -> domain events`.

## Persistence
Normal saves must not serialize the entire world to giant JSON. The design direction is structured incremental storage, measured SQLite/WAL or equivalent, bounded transactions, explicit checkpoint control, recovery journal and background I/O. No checkpoint or sync disk I/O in a frame-critical path.

## Financial/document requirements
Treasury/Finance/Documents must support incoming/outgoing transfers, cheque records/images, transfer proof images, receipts, future letters of credit/guarantees and searchable history. Media bytes live outside hot simulation state; database rows keep immutable IDs, hashes, metadata and links. Lists use metadata/thumbnails and lazy-load full media.

## Diagnostics
Every important operation propagates TraceID/ParentTraceID and records engine, operation, simulation time, start/end/duration, executor/thread, work count, reads/writes summary, allocations where measured, I/O, queue depth, result/error and cause chain. Diagnostics use bounded buffers/sampling so the black box cannot become the bottleneck.

## Rendering/UI
The map uses spatial indexing, visible-set extraction, LOD, clustering and GPU instance/route buffers. SwiftUI is for management UI, not tens of thousands of annotations/views. UI receives indexed/paginated read models; it never scans or mutates authoritative world state.

## Performance/thermal
Stable frame pacing is more important than a nominal FPS number. 60 is the baseline mode; higher refresh modes are allowed only when sustainable. Performance tests record p50/p95/p99/max, main-thread stalls, allocations, I/O, memory, scheduler backlog and thermal state. Thermal governor may lower visual detail/update frequency but must never alter economy, time, arrivals, production or financial truth.

## Initial engineering order
1. State Kernel
2. Simulation Clock
3. Event Scheduler
4. Job System
5. Transaction/Commit
6. Incremental Persistence
7. Diagnostics/Black Box
8. Performance/Thermal Governor
9. Query/Read Models
10. Synthetic scale harness

Only after these are measured does deep industry gameplay begin.
