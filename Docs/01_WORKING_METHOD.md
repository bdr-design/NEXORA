# Working Method

## Before implementation
1. State the product requirement without referencing legacy implementation.
2. Identify the owning domain/engine.
3. Trace callers, callees, state reads/writes, side effects, transaction and persistence boundaries.
4. Research authoritative sources for platform/architecture-sensitive decisions.
5. Write/confirm invariants and diagnostics required to prove correctness.
6. Define test and performance acceptance criteria.
7. Only then modify code.

## During implementation
- Small, reviewable commits.
- No unrelated cleanup mixed into a sensitive change.
- No cross-engine state writes.
- No main-thread heavy work.
- No performance claim without measurement.
- Update Update/Daily records with each meaningful milestone.

## After implementation
- correctness tests;
- deterministic/recovery tests where relevant;
- before/after performance;
- scale test;
- persistence verification;
- diagnostic verification;
- update continuity and changelog.

## Stop conditions
Stop sensitive work if context is degraded, source state is uncertain, required dependencies are not traced, root cause is not proven for a fix, or model/agent capability cannot meet the project's very-high execution gate.
