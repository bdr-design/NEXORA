# NEXORA — Mandatory Agent Operating Contract

This file is binding for any coding/research agent working on NEXORA.

## Capability / effort gate
Sensitive implementation may proceed only when the active model/agent is operating at the project's required very-high reasoning/effort level or an equivalently verified high-capability mode. If that cannot be verified, or context quality degrades, STOP sensitive code changes and continue only safe reading, analysis, documentation, or handoff preparation.

No agent may claim an effort/capability setting it cannot actually verify.

## Clean-room wall
The previous Global Holdings game is an idea/feature reference only. Forbidden technical reuse includes code, engines, data models, schemas, persistence layout, transaction logic, route algorithms, runtime files, performance fixes, WebApp structure, or technical assumptions derived from legacy behavior.

## No patch-first work
Before modifying a sensitive path, trace and document: functional owner, callers, callees, state reads, state writes, side effects, transaction/commit boundaries, persistence effects, rendering/UI effects, dependent engines, rollback/error path, and diagnostic evidence proving root cause.

## Research-before-design
For architecture, performance, concurrency, persistence, Metal, thermal behavior, Swift performance, or other high-impact decisions, consult current authoritative sources first and record the engineering conclusion.

## State ownership wall
- Every mutable domain has one declared owner.
- No engine writes directly into another engine's mutable state.
- Cross-domain change uses commands/events/contracts.
- Kernel coordinates state; it does not contain business logic.
- Visual interpolation never mutates simulation truth.

## Main-thread wall
No synchronous disk I/O, full-world scans, large serialization/allocation bursts, route planning, business batches, save checkpoints, or mass entity mutation loops on the main/render-critical path.

## Performance proof wall
Performance-motivated changes require before/after measurements under the same scenario, including p50/p95/p99/max where meaningful, main-thread impact, memory/allocation impact, persistence/I/O impact, and thermal observation where applicable.

## Diagnostic completeness gate
A core engine is incomplete unless bounded diagnostics can answer what ran, who triggered it, timing by stage, executor/thread, state reads/writes, work count, failure, and causal/root chain.

## Scale gates
`1k -> 5k -> 20k -> 50k -> 100k`

20k full-feature assets is the minimum acceptance gate. 100k is the architecture design target.

## Conversation/context continuity
When a working conversation becomes heavy or unstable: stop sensitive edits, preserve work, update `PROJECT_CONTINUITY.md`, update the daily log, record branch/commit/files/tests/measurements/decisions/risks/next action, then continue in a new session.

## Documentation is part of the product
Every material change updates the relevant contracts and history records.
