# NEXORA continuity — restart line

Current update: **NXR-R001**. Date: 2026-09-30.
Candidate branch: `rebuild/native-r001`.
Canonical working branch after gates pass: `foundation/clean-core`.
Recovery: `archive/before-radical-rebuild-20260930`.

The owner stopped NXR-0003 repair and ordered a radical restart. Do not resume
that repair, import its code, or regard old tests/measurements as new evidence.
Read AGENTS.md, Docs/RESET-RECORD.md, Docs/REQUIREMENTS.md, Docs/DESIGN-R001.md,
Docs/VALIDATION-R001.md and VERSION.json before changing source.

Implemented from scratch: EntitySpace ownership/lifetime, Timeline envelope,
identity-only check executable, positive/negative compiler contracts and tests.

Not implemented: domains, transactions, scheduler, persistence, iOS application,
renderer, Apple diagnostics adapter, or a full root-cause center. No IPA exists.

Next bounded milestone: design ONE tiny operational path and its invariant/tests
before implementation, with a synchronous reference behavior and bounded stage
measurements. Preserve financial documents/media and multi-industry extensibility
as product requirements. Do not reconstruct all discarded engines at once.

The user requires very-high effort for sensitive work. This chat does not expose
a verifiable runtime effort selector; do not claim one. R001 is isolated,
non-production scaffolding, not release authorization. Keep deployment and
sensitive game-state integration blocked until the execution gate is satisfied.

For handoff: record exact remote HEAD, CI run, changed files, test failures and
next safe step. Never infer them from this note when GitHub shows newer changes.
