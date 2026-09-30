# R004 comprehensive audit — verification record

Date: 2026-09-30, Asia/Riyadh. Repository: bdr-design/NEXORA.
Scope: permitted R001–R004 core and the subsequently published batch diagnostics.
This is an implementation/evidence audit, not a diagnosis of hidden model settings.

## Source identity and safety boundary

Canonical R004: 5b5599895fa1bdbf00e951104e0cd55dc00f9a56; rebuilt tree
ba59efc7ceea44ded86542001374820b8a2bb080 (98 files).
Diagnostic base: 96db1cebc38798a81f0315ec16e20136de7ce8da; tested diagnostic
parent b7d3deb8a8599ac382b69e431addf22acd0f4e7f, rebuilt tree
08ed6b709bc271080ee98e56927db9cce0c00bbf (102 files).
Review branch: review/r004-comprehensive-audit-20260930.
Review code: 0706447fceaca594d7dd897d98fe406dd926e352.
Review tree: 27a428eb9b2df227706ff9165f8c72cba748aa62.
Main, foundation and the canonical R004 feature branch were not merged or modified.
The permanent excluded branches were not opened. No reset, destructive checkout,
history rewriting, excluded-code archive, IPA extraction or old implementation reuse.

All production Sources, original Swift Tests, Package.swift, AGENTS.md and original
checks remain unchanged from the diagnostic base. The measurement extension also
remains byte-identical. The sole existing executable logic changed by this review
is the offline Python evidence analyzer. New regression/verification files reside
in ReviewTests; this does not relax the frozen-original-source guard.

## Review coverage and contract findings

EntitySpace/EntityHandle: ownership stamp, foreign/stale handles, generations,
free-slot linkage and permanent retirement at generation exhaustion.
Timeline: bounded ring, sequence ordering, parent constraints and overwrite count.
AircraftStore: single-owner create/start/complete/retire, revision and operation
checks, numerical bounds and expected rejection before mutation.
ArrivalHeap/TripSimulation: bounded queue, time and input sequence, ordering of
tied arrivals, event budgets, successful-prefix reporting and failure retention.
FinanceStore: integer amounts/currency input, capital vs revenue, prepared invoices
before aircraft completion, fallible checks before commit, partial collection,
no repeated revenue, cash expenses, bounded journal/page/index invariants.
Check executables and tests: baseline timing brackets, normalized public transcripts,
independent reference models, compiler ownership rejection and corruption fail-stop.

No new business-state/atomicity defect was established in the reviewed narrow core.
This is not exhaustive formal verification, complete coverage of every possible
input, persistence/crash safety or full-game acceptance. The in-memory bounded
history and process-local identity limitations remain as documented before this audit.

## Established defects in evidence acceptance

Owner: Checks/financial-diagnostics.py. Reads: offline NDJSON. Writes: summary file
only after successful analysis. On failure it must reject, not silently score bad
or repeated evidence. It does not access or mutate a running world.

A01 — Independent-evidence identity. The old analyzer accepted an exact process
file copied under a different filename, mixed source commits across files, and a
wrong sourceBase. It could double-count or combine incomparable evidence.
A02 — Completion state. It accepted kind=complete with status=failed.
A03 — Numeric/chronological validity. It accepted negative calibration wall time,
negative calibration loop time and negative explicit-world-release time.
These are seven demonstrated bad-input acceptances, grouped by contract; they are
not seven economic defects, nor proof that the original Apple data was corrupt.

Reproduction used a complete quick-format control derived from original run 1:
original calibration and first measured triples for all five sizes, with the
metadata/scheduling order adjusted to the documented quick schedule. Control and
mutation records are explicitly validation fixtures, NOT new timing runs.
Before patch: all seven accepted. After patch: all seven rejected. The 41-test
regression suite adds positive controls and checks for duplicates, source/status,
unsigned overflow, chronology/envelopes, lifecycle sums, existing economics/order,
and valid zero/missing/unsupported/failed/decreased counters.

Review-of-review correction: the first audit patch required errno > 0 for a failed
read. That could incorrectly reject a faithfully recorded zero-errno failure.
Inspection of Apple's published Libc clock_gettime zero-result failure path showed
that it can return -1 without assigning errno in that path. We now retain the raw
signed Int32 errno, including zero; the read stays syscallFailure with no numeric
counter. Two additional regressions bring the final Python suite to 43 tests.
This source inspection is not a claim that zero-errno failure occurred in our data
or that the exact inspected Libc revision was installed on the runner.
Primary source:
https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/gen/clock_gettime.c

## Fresh local evidence

Linux x86_64, Swift 6.2.1: Debug 142 named tests / 11 suites passed in 11.809 s;
Release 142 / 11 passed in 3.060 s. These durations are test-suite runtimes, not
asset/frame latency. All 29 compiler rejection gates and five valid clients passed.
The 12 corruption fail-stops (six cases in Debug and Release) passed. Source guards
were retained and passed. No new local TSan or iOS compilation is claimed.
Final Python: 43 named tests, 4.187 s, PASS. Initial 41-test local run also passed;
its missing errno boundary was subsequently found by review and corrected.

A complete hash-pinned reanalysis of Apple diagnostic artifact 11086348930 from
run 36692367500 reproduced the existing summary byte-for-byte, including all spikes.
372600 measured batch records were accepted by the strict validator; 37260 warmup
batch records remain in the original files and are kept separate from distributions.
The original three files, nested tested source ZIP and summary are individually
SHA256-pinned in ReviewTests/revalidate_apple.py.
Summary SHA256: cacb2a57f19b5921d0fac993ae6f7b785df9f83836e59a5442bb1a2563aa6567.

A second independent raw-arithmetic script, without importing the analyzer,
recomputed all 30 distribution groups: count, min/max, nearest-rank p50/p90/p99,
counts above 1/5 ms and first-batch maxima. All matched. This is arithmetic
validation of existing observations, NOT an independent performance run.

## Apple review execution

Earlier 41-test review code 8a269169bd3df2b1ef8e2581c19a4bbb935fa370:
run 36697172613 / job 109827799932 completed successfully. It is retained as an
earlier stage and is not substituted for the final source's acceptance.
Final review run 36697715699 is associated with code 0706447fceaca594d7dd897d98fe406dd926e352.
Final job 109829567389 completed SUCCESS at 2026-09-30T09:46:33Z. Every workflow
step succeeded. Downloaded artifact 11089180650 (nexora-r004-comprehensive-audit)
SHA256: 4fe2a49c41c14331e8706d706888129c512ec1837dec5077c6e194aeecb7723d.
Nested NEXORA_R004_AUDIT_SOURCE.zip SHA256:
01483c371f087c3fede04dcd713c1f45c92da24984779c2e995461629787ad06.
Rebuilding all 110 source files and their executable modes gives the exact review
tree 27a428eb9b2df227706ff9165f8c72cba748aa62. Commit/tree records match the run.

Apple Swift 6.1.2, arm64 macOS 15.7.9, Xcode 16.4 (16F6), Python 3.14.7:
- Debug: 142 named tests / 11 suites PASS; reported 36.542 s.
- Release: 142 named tests / 11 suites PASS; reported 4.462 s.
- TSan: 142 named tests / 11 suites PASS; reported 105.946 s; no sanitizer warning
  or error reported in the retained complete test log.
- Python evidence regression tests: 43 PASS; reported 4.254 s.
- Compiler: 29 required rejections; five valid clients compiled by the unchanged
  successful scripts. Valid clients are not separately printed in the logs.
- Corruption fail-stops: 12 PASS, with expected invariant markers.
- Frozen-source guard and pinned raw reanalysis: PASS. Final Apple summary is
  byte-identical to the original pinned report and to local final reanalysis.

Counts were checked against named test and suite start/pass records, not inflated
by parameterized input cases. Two post-download verifier assertions failed while
parsing the logs: one incorrectly expected an inline suite count in Apple's final
summary; another counted the overall Test run started banner as a named test.
After correcting those parser assumptions, explicit named records give 142 tests
and 11 suites in each mode. These were review-verifier parsing errors, not failed
Swift tests. Source/archive hashes had passed independently. The parser correction
and its final verification result are retained in the downloadable review evidence.
No new iOS compilation or performance benchmark was run by this audit workflow.
A documentation-only publication may follow; it is not itself the tested commit.

## Reproduce and limits

Run from the review source root:

```sh
python3 -m unittest discover -s ReviewTests -p 'test_*.py' -v
python3 Checks/financial-diagnostics.py --guard --selftest
python3 ReviewTests/revalidate_apple.py PRIOR_ARTIFACT_DIRECTORY revalidated-summary.json
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
```

The revalidation command requires the exact downloaded artifact files from run
36692367500/artifact 11086348930. It refuses wrong hashes. New raw traces must
record the real NEXORA_SOURCE_COMMIT; unrecorded-local-snapshot is no longer
accepted evidence. Metadata consistency alone is not cryptographic producer
attestation; an arbitrary benchmark producer still requires separate source/run
provenance. This validator is specifically for the existing five-size/256-batch
contract. It is not a general hostile-input sandbox or proof against all forgery.

No Swift business/measurement behavior, hash index, asset economics or reporting
formula was optimized. No original outlier was deleted or reassigned a cause.
The previous 20k counters-mode 32.748166 ms arrival remains, as does the 100k
wall-mode 57.649334 ms arrival. Counter intervals enclose wider windows; process
counters cannot be assigned directly to a single thread. Causal attribution is open.
No new performance benchmark, physical iPhone run, FPS, energy/heat, under-1/5 ms,
durable save/load or 20k full-game acceptance is claimed. R005 was not started.

Next permitted engineering work remains causal profiling and controlled cold/warm
experiments before changing FinanceStore. Re-read live branch tips and this record
at resumption; the review branch is not an automatic merge to canonical main.
