# NXR-R002 — Executable aircraft lifecycle

Date: 2026-09-30 (Asia/Riyadh). Development 0.0.2, no app build.
Branch: feature/r002-aircraft-lifecycle-20260930.
Base: cf305b5a13cad67555dd18f129f23ffdecfd68d2.
Status at submission: LOCAL_GATES_PASSED / APPLE_GATES_PENDING / NOT_GAMEPLAY.

## Authorization and source review

The owner answered the explicit execution question with
"الجهد الداخلي الان pro كمل لاتشيل همه". Work proceeded on a new isolated
branch from the permitted R001 source. This records authorization, not independent
verification of an invisible model setting. No excluded implementation was read
or reused and no history/branch deletion was attempted.
Thirteen baseline code/build/test files were materialized from already-read R001
content and verified by their Git blob IDs before editing. Baseline Debug passed
19 named tests. Source ZIP download was unavailable; no old archive was substituted.

## Ownership, paths and failure boundaries

Caller -> AircraftStore.apply -> token validation -> identity/row/state/limits ->
prepared replacement -> contiguous mutation -> immutable receipt. One store owns
both its private identity space and fixed-length optional rows. There is no await,
callback, I/O, logging, full snapshot or per-entity task/actor/lock on this path.
Expected errors leave identities (including generation/free-list), rows, revision
and counts unchanged. Creation exhaustion remains before allocator mutation.
Never undo create using destroy. Internal invariant corruption deliberately stops
rather than continuing with partially inconsistent state, in Debug and Release.
This is not crash durability or a multi-domain rollback system.

An old token is rejected, not replayed as a cached success. A completion must also
match the active operation ID. Tokens and handles remain process-local. Reading
returns a small value, not a mutable row/array. Deep audits allocate detached
arrays and are outside timed/hot work. A store-wide token is only this serial
reference's contract, not a prescription for an async global revision bottleneck.

## Explicit additions to D001

EntitySpace has a package-only detached audit and new-space generation fixture
initializer. No public mutable columns or handle constructor was opened. The
existing public create/contains/destroy implementation is unchanged. AircraftStore
has internal fault/overflow/corruption fixtures; external clients cannot access
them. Mutation fixtures exist only to test otherwise unreachable boundaries, are
not general data APIs, and are never called by normal apply/read.
T28 tests a caller-side logging failure after successful application. It does not
claim a production diagnostics adapter or a completed root-cause engine.
T31 is a deliberately narrow mechanical/source inspection, not compiler analysis
or a formal zero-allocation proof.

## Executed staged checks

Linux x86_64 / Swift 6.2.1:
1. Baseline identity/timeline: 19 named tests PASS before changes.
2. Full Debug and Release: 51 named tests, four suites, PASS in both.
3. Independent model: 4 recorded seeds (1, 73, 12345, 998), 5,000 commands each;
   results/errors/rows/revisions/epochs/flags/free-list/retired counts checked after
   every step. Seed 998 also exercises generation retirement.
4. Compiler: original 3 and new 8 required misuse rejections; valid public clients
   compile. Includes consumed/concurrent owner, private state, forged token,
   fixtures, audit access, package boundary and immutable read view.
5. Fail-stop: missing live row / occupied allocated slot, each in Debug and
   Release as separate processes. All four stopped with the required marker.
6. TSan: the initial `swift test --sanitize=thread` command timed out without a
   test summary. A 20-second direct probe also timed out. The complete direct run
   of the same instrumented test binary with `TSAN_OPTIONS=verbosity=1` and
   `--testing-library swift-testing` exited 0: 51 tests PASS in 33.032 seconds;
   no ThreadSanitizer warning/error was reported. No sanitizer was disabled.
7. Source-path checks and all 32 D001 scenario mappings PASS. There are 30
   scenario-named runtime tests, 2 external/source gates and 2 extra runtime
   ownership tests. With R001's 19: 51 named runtime tests, not 32+51 tests.
8. Raw lifecycle CLI: five scales, 3 warmups + 30 samples each, PASS.

## Findings and corrections during review

The release crash harness initially failed to compile because an intervening
ordinary release build replaced the testable module. The harness now explicitly
rebuilds each configuration with `-enable-testing` before linking its internal
fixture client; all four actual corruption runs then passed.
The source reviewer initially confused Swift's `record(for:)` argument label
with a for-in loop. The matcher was corrected and given positive/negative controls;
no production check was removed to turn a failure green.
The local SwiftPM TSan timeout is retained as a limitation of that invocation;
the successful direct sanitized run is separately identified.
No production logic defect was exposed by these tests; this is not a claim that
no defects remain.

## Raw measurements: local Linux, median milliseconds for the entire indicated set

| Records | Initialize | Create all | Start all | Complete all | Read all | Retire all |
|---|---:|---:|---:|---:|---:|---:|
| 20,000 | 0.2162 | 1.8815 | 3.0901 | 3.0303 | 1.4813 | 3.1819 |
| 100,000 | 1.2776 | 10.1663 | 15.8931 | 15.9576 | 7.7861 | 15.9317 |

These are independent phase medians, not a summed end-to-end percentile.
The CLI includes loop/receipt/result-check overhead in relevant phases and keeps
initialization, handle-array reservation, deep audit and JSON export separate.
No source-equivalent earlier aircraft store exists in R001 for a before/after
speedup claim. This benchmark has no routes, income, invoices, payroll, maintenance,
persistence, UI or Metal. It proves neither 20k full assets nor FPS/heat/RAM/energy.

## Publication identity and required Apple gate

Before this documentation update, prepared tree 122ee4c80558c602e0747bd94ca7a73afbabfd4b
matched the local tested workspace exactly for:
Sources: ed8814e6500763fcb0c2e86b999c3ac1658a9689
Tests: e64543a63b8a6fff575c78610bcc401c864508f1
Checks: afdd225481506ee50dde1df45f3cdcfdb484dca3
Package.swift blob: 54b95d82df62895828820a2e12d4d1af756695fa
The updated workflow retains baseline gates and adds R002 compiler, source,
fail-stop, three-library iOS compilation and raw aircraft lifecycle evidence.
At submission Apple success is NOT yet asserted; record the actual run/job/commit
and artifact digest only after retrieving results.

## Primary language references reviewed

- https://developer.apple.com/videos/play/wwdc2024/10170/ — ownership and noncopyable values.
- https://docs.swift.org/latest/documentation/the-swift-programming-language/declarations/ — package access scope.

Language references guided access/ownership decisions; actual syntax and behavior
were tested, not inferred as a performance result from documentation.
