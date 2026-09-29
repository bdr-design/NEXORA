# Update, Build, and Daily Record Policy

NEXORA is maintained as a real game project, not as an unstructured code dump.

## Every meaningful change belongs to an Update ID
Format: `NXR-####`.

Every update record must include date, version/build, branch and commit, purpose, exact additions/changes/removals, domains touched, dependency paths inspected, tests/results, performance/thermal/memory measurements where applicable, persistence impact, diagnostics impact, known limitations, rollback notes, and next authorized step.

## Daily journal is separate
`Docs/Daily/YYYY-MM-DD.md` records research, decisions, rejected approaches, blockers, permission changes, measurements and commits. A day may contain multiple updates; an update may span multiple days.

## Published builds
A published build must record semantic version, build number, included Update IDs, Git commit, source-tree/reproducible manifest, CI run, artifact name, artifact SHA-256, supported device/OS target, test matrix result, performance certification, and known issues.

## Performance-motivated updates
Must include before/after numbers under an identical scenario. “Faster” or “fixed lag” is invalid without evidence.

## Continuity
Before a session becomes unreliable/heavy: stop sensitive changes and update `PROJECT_CONTINUITY.md`, the current Daily entry, and the current Update record.
