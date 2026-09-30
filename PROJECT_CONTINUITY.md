# NEXORA continuity — NXR-R002 candidate

## Permanent exclusion / تنبيه دائم

The following three branch names are a denylist ONLY. Their implementation must
never be opened for development/reference/recovery, copied, built, merged,
cherry-picked, or reused for code, tests, schemas or measurements:

- `archive/before-radical-rebuild-20260930`
- `audit/nxr-0003-20260930`
- `fix/nxr-0003-contract-repair-20260930`

المصادر الثلاثة مشطوبة نهائيًا من العمل. أي إذن استرجاع قديم ملغى. التحذير ليس
حذفًا لتاريخ Git، ولا يُنشأ أرشيف بديل، ولا يُعاد تأسيس R001 بسبب انتقال المحادثة.
Read AGENTS.md before each work session and record the actual branch/HEAD.

## Owner authorization, 30 September 2026

The owner explicitly said "الجهد الداخلي الان pro كمل لاتشيل همه" after the
assistant requested authorization to proceed with implementation/testing on an
isolated branch. Actual implementation is now authorized. This is NOT independent
verification of an internal setting. The earlier documentation-only blocker is
superseded for this work; all source, review and evidence constraints remain.

## Exact source at start of R002

Repository: bdr-design/NEXORA only.
Starting commit: cf305b5a13cad67555dd18f129f23ffdecfd68d2.
Starting tree: dc6f7139f675cb22e692c470c4b3d5e562809051.
Implementation branch: feature/r002-aircraft-lifecycle-20260930.
main and foundation/clean-core were left at the starting commit while this
candidate was prepared. Always fetch current branch tips; do not infer them.

## Implemented now, not merely designed

NexoraAviation/AircraftStore is a noncopyable owner of EntitySpace and bounded
private rows, with create/start/complete/retire, private-store revision tokens,
operation matching, overflow handling, exact-state fault tests, detached audits,
internal fixtures, an independent serial model, external compiler clients and
isolated fail-stop probes. A separate CLI records 30 raw samples at five scales.
The existing R001 tests and implementation are retained, not rebuilt from any
excluded branch. EntitySpace adds package-only evidence/fixture entry points;
its existing public allocator mutation paths are unchanged.

D001 is the historical design baseline. Its previous IMPLEMENTATION_BLOCKED /
TESTS_NOT_RUN status describes its creation, not the new R002 results. Read
Docs/Updates/NXR-R002.md for implementation deviations, evidence and limits.
Development version: 0.0.2. App build: none. No IPA or playable game yet.

## Local gates actually completed

Swift 6.2.1, x86_64 Linux:
- Debug: 51 named tests in four suites PASS.
- Release: 51 named tests PASS.
- Direct execution of the TSan-instrumented test binary: 51 named tests PASS,
  exit 0, no ThreadSanitizer error reported. The initial SwiftPM TSan invocation
  timed out before reporting results; it is not claimed as a successful command.
- External compiler: original three required rejections plus eight new required
  rejections PASS; both ordinary clients compile.
- Two invariant-corruption processes in each Debug/Release: expected stop with
  the invariant marker, four of four PASS.
- All 32 D001 scenario IDs have evidence mappings: 30 scenario-named runtime
  tests, T25 external compiler, T31 mechanical/source review. Two extra runtime
  ownership tests plus R001's 19 give 51 total. Parameter expansions are not
  separate named tests. T29 uses four seeds x 5,000 commands.
- Five raw store lifecycle scales (1k/5k/20k/50k/100k), three warmups and 30 samples
  each PASS. This is not 20k full-feature gameplay or device certification.

Sources/Tests/Checks and Package.swift were matched exactly by Git object identity
between the local tested workspace and the prepared GitHub tree before the final
documentation update. Apple CI for this candidate must still be checked by run
ID and exact source SHA. Do not inherit R001 CI success as R002 acceptance.

## Previous permitted R001 evidence (not evidence for R002)

Initial CI 36646039605 / job 109669103488, on code
c45d24e0445219fc0db4df5efd0e920b5e129c16, tree
3b3f8aee3e966dac3a330ff2f85b6ec4e2ebc910; artifact 11068189510,
SHA-256 d801954fec29799915363762163eff1e9f3fc7eff94c8a783b21ebdd981f7a96.
Second CI 36646380334 / job 109670212517 on
a4023fb365a628d8574b444b6e3d0501a1e8d6aa was reported successful by GitHub.
Artifact 11068408969 reported digest
f830bb43248a162248e2980763c34381a4f9c971642831e8e9265813ac935db6;
that second archive was not rehashed in the earlier handoff.

## Next stage, not claimed complete

Verify R002 Apple Debug/Release/compiler/fail-stop/TSan/iOS gates and raw evidence.
Then implement bounded deterministic time/events and one small trip/result path,
with an independent reference and failure tests. Do not impose the serial store's
revision token as a global asynchronous contention/retry loop for the whole game.
Finance, invoices, payroll, maintenance, deliveries, persistent logical identity,
transactional save/load, separate document/blob storage, iOS application, map and
full causal diagnostics remain to be implemented and tested incrementally.
Keep incoming/outgoing transfers, cheques/images, proofs, receipts, searchable
history and multi-industry extensibility in Docs/REQUIREMENTS.md. Full-size media
never belongs in hot simulation rows. Device target is iPhone 17 Pro Max;
20,000 complete assets is future acceptance and 100,000 is an architectural goal.
Physical removal of excluded Git history is unresolved and is not part of this
non-destructive implementation update. No background-work promise is implied.
