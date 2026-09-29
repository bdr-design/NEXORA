# NEXORA

**Repository:** `bdr-design/NEXORA`
**Project:** NEXORA
**Architecture status:** Clean-room foundation
**Technical ancestry:** None. NEXORA is a new implementation from zero.

NEXORA is a native, high-performance enterprise simulation platform designed for deep global business simulation while preserving sustained smoothness, low thermal pressure, traceability, and long-term extensibility.

## Non-negotiable goals
- Smoothness and sustained performance are first-class requirements.
- 20,000 fully functional assets is the minimum scale acceptance gate.
- 100,000 assets is the architectural design target.
- The previous game is a product-idea reference only. No technical implementation is reused.
- Companies are composable from capabilities so future industries do not require a kernel rewrite.
- Diagnostics/black-box tracing is built from day one.
- Large documents/images never inflate hot simulation state.
- Simulation, rendering, persistence, and UI query work are separated.
- No patch-first development.

## Project history
Every meaningful change receives an Update ID under `Docs/Updates/`, every working day is recorded under `Docs/Daily/`, and published builds receive a release record under `Docs/Releases/`.

## Start here
1. `AGENTS.md`
2. `PROJECT_CONTINUITY.md`
3. `Docs/00_MASTER_REFERENCE.md`
4. `Docs/UPDATE_POLICY.md`
5. `CHANGELOG.md`
6. `VERSION.json`
