# Architecture

## Style
NEXORA is a modular monolith. Domains are strongly separated but remain in one application/process to avoid mobile microservice/network overhead.

Layers:
`Presentation -> Read Models -> Business Capabilities -> Simulation/Operations -> State Kernel/Scheduler -> Persistence/Diagnostics/Platform`.

## Ownership
Each mutable domain has one writer/owner. Other domains interact through commands/events/contracts. UI and Rendering are consumers/projections, not authoritative owners.

## Concurrency
Parallelize pure/independent computation, then apply bounded deterministic deltas through owned commit paths. Do not create a task/actor per asset.

## Hot/cold data
Hot state contains compact operational fields needed frequently. Cold state/history/documents are loaded on demand. Hot loops favor contiguous/data-oriented layouts and minimal allocations.

## Determinism
Simulation events carry sequence ID, simulation time, domain/entity and cause IDs. Random processes use seeded streams where deterministic replay is required.

## Failure model
Every mutation either commits atomically or fails without partial authoritative state. Persistence/recovery has explicit crash/interruption tests.
