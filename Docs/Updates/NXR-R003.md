# NXR-R003 — bounded deterministic timed trips

Date 2026-09-30. Development 0.0.3; no app build or IPA.
Base: 63de835eef4b24b410703507986dbf84f5d6eeea, the permitted verified R002 line.
Branch: feature/r003-bounded-trips-20260930.
Submission status: LOCAL_DEBUG_RELEASE_GATES_PASSED / APPLE_GATES_PENDING.

## What was implemented

NexoraSimulation owns an AircraftStore, fixed-length per-slot journey rows and a
fixed-capacity binary min-heap. Public commands register an aircraft at a numeric
fixture airport, depart to another airport for a positive duration, and retire a
ready aircraft. This is not financial purchase/sale or a real geographic network.

The clock uses checked UInt64 simulation seconds. Arrival ordering is due time
then unique operation ID. advance returns completed events, actually reached time,
next due time and an explicit stop reason. Its budget is 1...1,024 events. It never
jumps beyond pending due events or silently removes a rejected event. A failure
returns its already committed prefix; retry cannot redo events removed earlier.
Expected INPUT failures leave all component/identity/heap state unchanged.

Manual-input tokens advance only on accepted user inputs; automatic arrivals do
not invalidate them. The coordinator obtains the inner aircraft token just before
its synchronous call. No game-wide async revision retry loop was introduced.
There is no await, per-aircraft task/actor/lock, file I/O, full snapshot or hot world
scan in input/advance. The heap sifts O(log pending); result arrays are capped by
the requested event budget. This is not a certified hard wall-time deadline.

## Ownership changes to R002

AircraftStore's new-space test initializer and detached audit types/access are now
package scoped so compound-state tests can inspect exact nested state and seed
an otherwise unreachable revision limit. They are still inaccessible to ordinary
external clients. No public mutable storage, handle constructor or test mutation
control was exposed. Existing R002 public mutation algorithms are unchanged.
The baseline compiler rejection gates were rerun after this visibility change.

## Staged local checks, Swift 6.2.1 x86_64 Linux

- Debug: 86 named tests / six suites PASS (5.433 seconds in the final summary).
- Release: 86 named tests PASS (2.155 seconds).
- 35 new runtime tests: 32 scenario-named tests plus independent reference, heap
  oracle and owner-move tests. Existing 51 R001/R002 tests remain. Parameterized
  expansions are not additional named tests.
- Reference seeds 17, 701, 123456, 703710: 5,000 requests each, 20,000 total,
  comparing logical time, input sequence, nested aircraft revision, rows, identity
  generations/flags/free-list and sorted pending events after every request.
  Across these seeds: 3,213 automatic arrivals and 248 injected blocked-prefix
  results; all matched. The prior R002 model's separate 20,000 commands also reran.
- External compiler gates: original 3 + R002's 8 + R003's 7 required rejections,
  and all three valid clients compile. Includes forbidden clock assignment,
  concurrent/consumed owner, private store, forged input token, fixtures and audits.
- Corruption: two R002 and two R003 probes in each Debug/Release, eight processes
  total. All stopped with the required invariant markers. R003 probes cover read
  and advance after deliberately corrupting the paired active journey.
- Narrow source guards passed. They are text-level checks, not formal memory or
  optimizer proofs. Runtime model/edge tests are separate evidence.
- Five timed-trip scales (1k/5k/20k/50k/100k), three warmups and 30 measured samples
  each, completed; every aircraft arrived once at its expected destination.

The full local SwiftPM TSan invocation did not finish within its configured
execution/observation window. Its partial log has no completed test summary; it
is NOT counted as PASS. The complete Apple sanitizer gate is still required at
submission. No sanitizer or correctness gate was disabled.

## Findings and corrections

The independent test model's first build bound destination/duration in a combined
switch case whose retirement alternative did not contain those fields. The
compiler rejected it. Bindings were moved into the nested departure case; then
all Debug and Release tests passed. No failed test was removed or assertion
weakened. No runtime correctness defect was exposed by the completed local gates;
this is not a claim that all possible defects are absent.

Review emphasized queue-capacity preflight before changing aircraft state,
retaining failed head events, reporting partial progress instead of throwing away
successful prefixes, same-time tie order, overflow, slot reuse and input/time
sequence separation. Internal corruption fail-stop is NOT persistence recovery.

## Local timings, milliseconds for all indicated timed-trip records

Fixture budget: 256 arrivals per advance. Independent 30-run medians.

| Records | Register all | Depart all | Advance all | Batches/run | Largest advance observed across runs |
|---|---:|---:|---:|---:|---:|
| 20,000 | 3.650482 | 9.498385 | 17.286370 | 79 | 2.098252 |
| 100,000 | 18.507499 | 48.417501 | 98.825558 | 391 | 4.359982 |

Advance-all includes result/loop overhead, while initialization, deep audit and
JSON export are outside these phases. Largest observed is not p99 certification.
R002's aircraft-store measurements are a different workload, not a before/after
baseline for these trips. No real route planning, financial posting, payroll,
maintenance, deliveries, save/load, UI/FPS, physical RAM, energy or heat was tested.
These Linux numbers are not an iPhone or complete 20k-asset acceptance claim.

## Publication proof

Local tested and prepared GitHub trees matched by exact Git object identity:
Sources: ca904809dce06a62b9f8c5b1e9a657ebfcc61c2f
Tests: c9a27bbb025a03aca0e4b1ef8524378fcd16eb2a
Checks: 9edd1ccc9be83c2187a44d512eee85b663d708f4
Package.swift: 9f334c443c0e16c989eda7558adbbc0d4e18e502
Prepared root before documentation: 869ef5e36acf729754ff2f06475c7a72d8c4837a.

The read-only Apple workflow now tests four libraries, retains all earlier gates,
and exports the exact current Git source tree (no Git history) with its digest
inside the evidence artifact. That archive is permitted R003 source, not an
archive of an excluded implementation. Record actual CI source/run/artifact only
after verification. main must not be advanced to this candidate before its gates.

## Required next boundary

Financial posting must be prepared before aircraft arrival is committed. Do not
append fallible financial side effects to the consumer of advance's completions
and call that an atomic cross-domain transaction. Define persistent logical
identity before save/load. Full-size documents belong in separate blob storage.
Real routes, finance/invoices/payroll/maintenance/delivery, persistence, the iOS
application/map and device acceptance remain unfinished.
