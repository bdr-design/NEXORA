# ADR-0007 — Explicit Read Batches and Coordinated In-Memory Transactions

Date: 2026-09-30
Status: Accepted for the pre-Scheduler core

## Context
The NXR-0002 benchmark used Swift Array CoW snapshots of authoritative storage. That was safe only while lifetimes were carefully controlled and risked hidden large copies when authoritative arrays mutated.

Cross-domain atomicity was also specified but not implemented.

## Decision
1. Replace full authoritative Array snapshots with explicit caller-owned read batches containing only selected/due rows.
2. Measure read gathering as its own phase.
3. Use a shared transaction gate for domains participating in coordinated in-memory commits.
4. Validate all transaction steps before the first mutation.
5. Keep prepared apply sections synchronous and non-suspending.
6. Make public participating-domain reads acquire the same gate so observers cannot see an intermediate coordinated state.
7. Do not claim durable crash atomicity until Persistence/WAL is implemented.

## Consequences
- hidden full-state CoW risk is removed from this path;
- read cost is explicit and proportional to selected work;
- a short global transaction gate exists and must be benchmarked as more domains are added;
- no per-entity locking is introduced;
- Scheduler intents can later participate in transaction plans instead of being applied after state commit.

## Deferred
Swift 6.2 Span/borrowing APIs remain candidates for future optimization after the project's toolchain floor supports them and benchmarks show a benefit.
