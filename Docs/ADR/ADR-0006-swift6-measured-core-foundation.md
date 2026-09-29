# ADR-0006 — Swift 6 measured core foundation
Date: 2026-09-30
Status: Accepted for core preflight; not a final gameplay architecture freeze.

## Decision
Implement NEXORA's first executable core as a Swift 6 package with Synchronization primitives, global generational identity, packed sparse↔dense domain storage, deterministic bounded parallel compute and synchronous validate-then-commit.

## Evidence
Local Release/TSan and GitHub macOS CI passed. The 100k synthetic path remained sub-millisecond at p99 on the tested environments.

## Constraints
No claim is made about full gameplay, iPhone thermals, allocation-free execution, persistence or rendering. The current CoW snapshot boundary must be hardened before Scheduler integration.
