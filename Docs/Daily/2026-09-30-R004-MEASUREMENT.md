# R004 measurement-only resume

2026-09-30, Asia/Riyadh. Repository: bdr-design/NEXORA only.
Remote baseline: main / foundation/clean-core / feature/r004-atomic-finance-20260930
all re-read at 5b5599895fa1bdbf00e951104e0cd55dc00f9a56.
New remote branch: diagnostic/r004-batch-counters-20260930, created from that SHA.
Published ZIP SHA-256: 6ce5e148d94cc10c13946389aa1bd25d31a0564ddf7cdfd6cf52de5a9ae3f1ac.
All 98 file contents and executable modes reconstruct tree ba59efc7ceea44ded86542001374820b8a2bb080.
The local working tree is a content-verified snapshot, not a history clone. Its local
snapshot commit is not the published GitHub commit; remote commits use the actual
published parent. A local attempt to reconstruct the commit header did not match
(the API normalizes header metadata); no source mismatch or history write resulted.

AGENTS.md, PROJECT_CONTINUITY.md, VALIDATION-R004.md and ATOMIC-FINANCE-R004.md
were read before changes. The three excluded branches were not opened or used.
No reset, checkout, cleanup, alternate archive, history rewrite, or R005 work.

Immediate boundary: instrument the financial CHECK executable before changing
FinanceStore or TripSimulation. The owner's handoff makes this measurement step
newer than the old next-R005 wording. The consultant response is a hypothesis,
not executable evidence; it is not copied into this repository as an implementation.

Owner/call trace: the CLI fixture owns a local TripSimulation. Its public methods
own the complete aircraft/finance/arrival state transition. The measurement wrapper
reads clocks and process counters before/after those calls, writes only its own
fixed-size trace buffers, and exports after the measured workload. Failures from
the original fixture still fail the command; no business failure gate is removed.
Library sources, old tests/checks, Package.swift and legacy fixture are frozen.

Results and exact candidate/run identities are appended only after execution.

## Local staged review (Swift 6.2.1, x86_64 Linux; not Apple)

Debug: 142 named tests in 11 suites PASS, 22.244 s reported test duration.
Release standalone rerun: 142/11 PASS, 6.158 s. Separate diagnostic selftests in
Debug and Release passed all nine sizes through 100k, comparing normalized
transcripts and baseline economic aggregates. Original three source guards and
new frozen-object guard/analyzer selftests passed. A quick raw run validated all
five sizes, physical batch/phase identities and counter statuses. This is not a
full 30-sample Apple performance result.

Retained failures: initial split Swift helper files conflicted with @main in a
main.swift executable; combined them into the original file instead of altering
Package.swift. A Release build-tests command reused modules not built for testing
and failed; a fresh scratch-path `swift test -c release` then compiled successfully
but hit the local wrapper time cap during tests. The independent --skip-build rerun
above passed; the failed and timed-out invocations remain separate evidence.
An attempted streaming container invocation was unsupported and did not execute;
no test result is attributed to it. No safety or business check was disabled.

Apple validation, sanitizer, external compiler, fail-stop and iOS results for this
candidate are not claimed by this entry. The new workflow records them when run;
original R004 Apple evidence must not be relabelled as testing this extension.

A full local diagnostic invocation (three warmups/30 rounds/five sizes) reached
the 90-second wrapper limit before completion. It left 385 complete NDJSON lines
(24,189,821 bytes), ending during the 50k measured stratum. This is incomplete,
not a passing run; no complete-run percentiles are claimed from it. All partial
raw bytes remain in local-evidence/linux-batches-1.ndjson. No process remained
running after the wrapper terminated it. The independent Apple workflow is the
full multi-process gate; local timeout evidence must not be hidden by that result.
