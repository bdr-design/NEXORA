# NXR-R004 — verified in-memory finance boundary

Date: 2026-09-30 (Asia/Riyadh). This is a development-core gate, not production,
full gameplay, durable-save, or iPhone performance approval.

## Exact tested source and evidence

Repository: bdr-design/NEXORA only.
Tested commit: 674c94e145f24dc6c4c9addaa5aa07d1c9d4a168.
Tested tree: f1273cf58de998cad9256581474edbe1c8f85261 (95 source files).
Apple run: 36679204017. Job: 109770742356. All workflow steps succeeded.
Toolchain: Apple Swift 6.1.2, arm64 macOS 15, Xcode 16.4 (16F6).
Artifact: 11080779599, nexora-r004-evidence.
Recomputed artifact SHA-256:
`df71ac8bf51e8b8cbf0be4bb061b0b66619f2cb8ed12aff479abc385e4b7211c`.
Recomputed nested NEXORA_R004_SOURCE.zip SHA-256:
`a815f730f4a6b5d663dbfcc8763d22df5307892469048503354c8f6427fd91a1`.

The artifact commit/tree records were checked. All 95 file contents and executable
modes matched the locally tested source byte-for-byte. Reconstructing Git blobs
and directory objects from the ZIP reproduced the complete tested tree above.
This is stronger than merely trusting the artifact filename or checking a subset.

Tested code objects:
- Sources: f9c19894cc77ea541101c82caa1defa383be3e72
- Tests: 83602394c3db51e9d6f43682dcb34a0a11f51c41
- Checks: 35903e43258a90f019f395035dab310436b177ec
- Package.swift: 9772a69021caed24dd9dac48c3aa32eb5d63207f
- CI workflow: 01668399e948242ebfd44ba3a89587dd1d647904

## Completed executable gates

| Gate | Verified result |
|---|---|
| Debug | 142 named tests, 11 suites; PASS, reported test duration 29.059 s |
| Release | 142 named tests, 11 suites; PASS, reported test duration 4.904 s |
| Thread Sanitizer | 142 named tests, 11 suites; PASS, 90.482 s; no sanitizer warning/error reported |
| Compiler misuse | 29 required rejections: 3 identity, 8 aircraft, 7 trip, 11 finance |
| Valid compiler clients | 5 object outputs, including the package financial-plan client |
| Isolated corruption probes | 12 expected fail-stops with invariant markers: 4 aircraft, 4 trip, 4 finance |
| iOS Release compilation | NexoraIdentity, NexoraObservability, NexoraAviation, NexoraFinance, NexoraSimulation; all BUILD SUCCEEDED |
| Source-path guards | R002/R003/R004 guards passed; textual checks, not a formal proof |
| Raw fixtures | Identity, aircraft, trip and financial reports each contain five scales and 30 raw samples per scale |

Parameterized cases are not extra named tests. iOS compilation is not device
execution. Test durations are not gameplay/frame durations. Earlier R001/R002/R003
contracts remain enabled rather than being replaced by finance-only tests.

The independent finance oracle ran four seeds x 5,000 commands, comparing accepted
and rejected results, invoices, balances and unchanged failed state. In Release:
seed 19: 1,878 accepted / 3,122 rejected / 201 collections; seed 1009: 1,815 / 3,185 /
197; seed 77777: 1,876 / 3,124 / 181; seed 888111: 1,770 / 3,230 / 178.

D01 and D02 add three seeds each. Two waves of 97 aircraft mix priced/unpriced
trips, tied arrival times, partial collections and all three expense categories.
Every normalized invoice and journal entry is checked against independently
constructed records across budgets 1/7/31/1024 and target partitions. Injected
zero/one-prefix failure and retries match uninterrupted financial history. F31
rejects oversized/multibyte currency inputs. These three added named tests passed
in all three Apple modes. They are not a full-game reference model.

## Measured financial fixture — report all observed spikes

One priced trip, one invoice and full collection per aircraft, plus capital and
three expense postings. Three warmups, 30 samples, event budget/page size 256.
The maximum batch is a maximum observation, not a deadline or p99 certification.

| Aircraft | Invoices | Journal entries | Median all-arrivals ms | Largest arrival batch ms | Median all-collections ms | Largest collection page ms |
|---|---|---|---|---|---|---|
| 1,000 | 1,000 | 2,004 | 0.471146 | 0.244792 | 0.189250 | 0.068834 |
| 5,000 | 5,000 | 10,004 | 2.818542 | 0.761250 | 0.956042 | 0.152291 |
| 20,000 | 20,000 | 40,004 | 13.133896 | 20.050916 | 3.793042 | 16.267500 |
| 50,000 | 50,000 | 100,004 | 45.589230 | 6.808834 | 10.037645 | 2.311083 |
| 100,000 | 100,000 | 200,004 | 109.172292 | 3.033458 | 21.595625 | 1.200250 |

The 20.050916 ms arrival and 16.267500 ms collection-page observations at 20k are
retained, not discarded. No causal attribution to the runner, memory, scheduling
or code is established by these wall-clock samples. No under-5-ms or under-1-ms
hard guarantee is met/proved. Different sample statistics need not be monotonic
with scale. This is not an optimization comparison with an earlier run.
Initialization, capital seeding, deep audits and serialization are separate from
reported hot phases. All-arrival timing includes loop/completion checks; maximum
advance timing measures the advance call. Collection-page timing includes page
retrieval and its postings. The raw financial-samples.json is authoritative.

## Review changes and retained failure evidence

Recovered prepared tree 69a9dceedcf973c02bd0d59d091f399095558ee1 was preserved as
candidate 53cb86222f1529f8f48be4d00993c4ef03900311 without rebuilding retired code.
Its separate Apple run 36677404314/job 109765248844 passed 139 named tests per mode.
Artifact 11080364450 was rehashed as
b82646d39a7c2d78f5d07dd0320e74dfc24dd51126eb45ce7f9e210889c7fff2.
That run does not substitute for the final 142-test evidence above.

The resume review traced ownership, arithmetic and error precedence, compound
arrival writes, and failure/retry semantics. Currency validation no longer copies
an entire rejected UTF-8 input into a temporary array; it reads three bytes and
checks termination. This source change is not an allocation/energy benchmark.
D01/D02/F31 and the implementation-boundary document were added. VERSION was
corrected from stale R003 identity to an explicitly unverified R004 candidate
before the final Apple run. No business posting rule or safety gate was removed.

Local Swift 6.2.1/Linux Debug passed 142 tests/11 suites (12.848 s). The standalone
Release rerun passed 142/11 (3.355 s). A combined command hit its 45 s execution cap
during Release compilation; the successful rerun is separate, not a rewritten
history. A combined compiler/corruption invocation also hit that cap after all 29
compiler rejections; individual corruption scripts completed all 12 probes.
No new local full TSan result is claimed. Earlier incomplete local TSan remains
incomplete; successful Apple TSan is separate evidence.

Direct local source retrieval was unavailable. A read-only source-export workflow
on review/r004-source-20260930 exported the exact permitted candidate; its success
is source-transfer evidence only. It is not a source for future development.
No excluded implementation was read, no history cleanup was attempted, and no
checks were disabled to pass the gate.

## Publication and remaining acceptance

An evidence-only publication may advance branch tips. Its code/test/check/package
and CI objects must remain those above. Re-read branch heads, do not substitute
the tested SHA for a newer documentation SHA or claim the latter was this run.

No durable IDs, save/load, database, document/blob images, transfers/cheques,
scheduled payroll/maintenance/delivery, real route catalog, iOS app or Metal map
exist in this boundary. Expense primitives are not those complete systems.
Fixed history capacity still stops new postings/arrivals when full; it is not a
long-session storage solution. 20k full-feature gameplay and 100k architecture,
real-device frames/physical memory/energy/heat and zero allocations remain unproven.
