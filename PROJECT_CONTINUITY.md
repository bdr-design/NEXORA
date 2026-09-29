# NEXORA — Project Continuity

**Status:** Foundation/reference publication
**Official repository:** `bdr-design/NEXORA`
**Default branch:** `main`
**Foundation work branch:** `foundation/clean-core`
**Independent root commit:** `ec00fd8c025199b4151796e8a9cabe2c11f2abcd`
**Technical ancestry:** none; the root commit has no parents from the previous project.

## Authority order
1. Repository source and committed contracts.
2. `AGENTS.md`.
3. `Docs/00_MASTER_REFERENCE.md`.
4. ADRs and Update records.
5. Daily engineering logs.
6. Chat is temporary working context only.

## Current update
`NXR-0001` — Foundation Reference — 2026-09-30 — `0.1.0-dev.1` / Build 1.

## Primary goals
- sustained smoothness;
- low thermal pressure;
- deep realistic business simulation;
- composable companies/industries;
- correctness/recovery/determinism;
- built-in root-cause diagnostics;
- 20,000 fully functional assets minimum acceptance;
- 100,000 asset architecture design target.

## First engineering milestone
State Kernel, Simulation Clock, Event Scheduler, Job System, Transaction/Commit layer, Incremental Persistence, Diagnostics/Black Box, Performance/Thermal Governor, Query/Read Model layer, Synthetic scale harness.

## Recorded product requirements
Aviation, maritime, road transport, banking/treasury/finance, HR/crew/payroll, maintenance, logistics/cargo, facilities, world markets/economy, manufacturing/supply chains, future car/dairy/mobile-device companies, incoming/outgoing transfers, cheque images, transfer proof images, receipts/business documents, and searchable financial history.

## History rule
Every meaningful change updates its `NXR-####` record and the current `Docs/Daily/YYYY-MM-DD.md`. Published builds additionally require a release record with commit, CI and artifact hashes.

## Next safe action
Verify publication of NXR-0001, then begin the minimal measured core implementation.

## Verified NXR-0001 content snapshot
- Commit: `e83ceb843548f196c8bd37d64d7c3285bd43b77e`
- Tree: `5d6fb1068eeb4228429168fcbe9a3811fe24496e`
- Files: 47

## Chat continuity rule
`Docs/CHAT_CONTINUITY_PROTOCOL.md` is mandatory. If a session becomes heavy, unstable or ambiguous, stop sensitive changes, checkpoint repository state, and continue only after a new session verifies the authoritative repository context.
