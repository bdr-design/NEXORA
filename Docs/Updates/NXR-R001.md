# NXR-R001 — Fresh ownership foundation

Date: 2026-09-30. Development version: 0.0.1. App build: none.

Replaces the active NXR-0001/2/3 tree rather than amending it. Prior Git history
is retained only for recovery, not as source for the new implementation.
The source replacement is c45d24e0445219fc0db4df5efd0e920b5e129c16.

New code: uniquely owned identity space, bounded timeline and lifecycle checker.
New tests cover foreign/stale identity, recycling, capacity failure, generation
retirement, randomized lifecycle/model consistency, isolation and ring behavior.
Compiler checks reject forged handles, use after consume and concurrent mutation.

CI 36646039605 passed Debug, Release, TSan, compiler boundaries, both iOS library
builds and five identity fixture scales. See ../VALIDATION-R001.md for evidence.

The prototype deliberately has no business state, domain transaction system,
parallel shared compute workspace, scheduler, database, iOS app or renderer.
20k gameplay acceptance and 100k architectural scale remain unachieved targets.
Effort/release gates remain separate from passing scaffold tests.
