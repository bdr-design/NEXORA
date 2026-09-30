# Evidence-owner contracts — R004 stage A

This changes evidence plumbing, not economic state or normal measured loops.
Source: permitted parent 5384b58d193f90859a8f0efeaec6d28d6e93b89e only.

Source guard: recursively enumerate frozen Sources/Tests/Checks plus package,
AGENTS and the original restart workflow. No name-based directory exclusion.
Reject symlinks/non-regular input before reading; hash file bytes and modes.
The existing explicit diagnostic extension/dispatch and analyzer-file exceptions
remain narrow, intentional and tested; this is not self-authentication of the guard.
Python caches must be prevented with -B, not hidden. Tests mutate isolated copies.

Analyzer: schema-1 NDJSON -> validated aggregates -> exclusive-create report.
Require exact numeric field set, types, units/scope/indexing and all producer metadata.
Reject duplicate JSON keys, non-finite numbers, missing/unknown fields and prior
invalid-source/duplicate/status/timing cases. Keep all valid zeros, failures,
unsupported readings, negative deltas as unavailable, and every original spike.
No percentile/math formula change. SourceCommit syntax does not prove its truth;
artifact/source hashes and actual run association remain mandatory.

Writer: CLI validates path/source syntax before workload. O_CREAT|O_EXCL|O_NOFOLLOW
opens the output once without O_TRUNC and owns that descriptor through FileHandle.
No check-then-reopen race. Permissions 0600, CLOEXEC, explicit close idempotent,
write-after-close fails. Existing regular, empty, linked and FIFO destinations reject.
The final component is protected; callers must control parent directories. Encoding
and I/O are outside measured phases. Partial new files are retained on failure,
not silently retried as complete and not described as crash-durable storage.
Legacy --json is deliberately unchanged; do not use it to overwrite evidence.

CI: no path filters on the reviewed branches. Separate library TSan and actual
instrumented check-executable/selftest/writer gates share an explicit sanitizer
scratch path. Preserve logs on failure. A quick raw generation is a schema/CLI
smoke, not a repeated performance campaign. Pinned prior reanalysis is not new timing.
Actual templates/help are recorded before choosing the causal-trace command.

Primary references inspected during implementation:
https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html
https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

Open: execution/scheduling cause, cold/warm allocation attribution, true device
performance and all durable-storage/full-game boundaries. No index replacement.
