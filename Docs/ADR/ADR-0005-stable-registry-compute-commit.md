# ADR-0005 — Stable Entity Registry and Deterministic Compute/Commit

Date: 2026-09-30
Status: Accepted

## Decision
NEXORA will separate global entity lifetime from domain component storage.

Global identity uses generational handles owned by a central registry. Performance-sensitive domains may keep packed sparse↔dense storage, but component removal does not destroy the entity.

Parallel domain computation occurs outside authoritative mutation. Results are merged deterministically, fully validated, then applied in a short non-suspending single-writer commit.

Cross-domain atomicity requires an explicit coordinator and cannot be inferred from independent domain locks/actors.

## Consequences
- stale handles are rejected in O(1);
- swap-and-pop remains possible without unstable public handles;
- no actor/task-per-asset architecture;
- commit sections remain bounded and await-free;
- benchmark harnesses must avoid hidden Copy-on-Write costs and nondeterministic task completion order.
