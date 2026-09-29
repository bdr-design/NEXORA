# Release Process

A NEXORA release is a traceable engineering artifact, not merely an IPA file.

## Release gates
1. Update records complete.
2. Architecture ownership rules reviewed.
3. Correctness tests pass.
4. Persistence/recovery tests pass.
5. Diagnostics cover new critical paths.
6. Appropriate scale test passes.
7. p50/p95/p99/max recorded.
8. Memory/thermal soak recorded when runtime exists.
9. CI build reproducible from cited commit.
10. Artifact SHA-256 recorded.

Published release records live under `Docs/Releases/` and name every included Update ID.

Never publish from uncommitted source, without commit identity, or from legacy-game source/binaries.
