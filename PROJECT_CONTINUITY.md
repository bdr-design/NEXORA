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

## Verified restart checkpoint

R001 initial scaffold gates passed in Apple CI run `36646039605`.
Verified code commit: `c45d24e0445219fc0db4df5efd0e920b5e129c16`.
Verified code tree: `3b3f8aee3e966dac3a330ff2f85b6ec4e2ebc910`.
Artifact SHA-256: `d801954fec29799915363762163eff1e9f3fc7eff94c8a783b21ebdd981f7a96`.
The final publication commit only records evidence and this handoff; source,
tests, compiler checks and CI workflow are unchanged from the verified code.
The requested active-tree replacement applies to main and foundation/clean-core.
Verify their exact remote tips before beginning the next session.
