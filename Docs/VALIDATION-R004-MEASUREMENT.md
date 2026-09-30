# R004 batch measurement — verified Apple evidence, diagnosis still open

2026-09-30, Asia/Riyadh. Repository bdr-design/NEXORA only.
Branch: diagnostic/r004-batch-counters-20260930. This is a diagnostic extension,
not R005, a business optimization, full gameplay acceptance or an application build.
Main and the two canonical R004 branches remain at the original published baseline.

## Source identity and independent verification

Baseline: 5b5599895fa1bdbf00e951104e0cd55dc00f9a56.
Tested diagnostic commit: b7d3deb8a8599ac382b69e431addf22acd0f4e7f.
Tested tree: 08ed6b709bc271080ee98e56927db9cce0c00bbf (102 files).
Apple run 36692367500, job 109812298525; all steps completed successfully.
Artifact 11086348930: nexora-r004-batch-diagnostics, 15,038,351 bytes.
Recomputed artifact SHA-256:
34317f1a041179325ac93a0f9925634df3d1736c6ae4b3f68e5185f66369b9e4
Nested source ZIP SHA-256:
cf171610aea628944235d6072fb09fa4878b5370859eebafd1436af0d7dc24bc

All 102 exported file contents and executable modes matched the local candidate;
reconstructing all Git objects reproduced the tested root above. Source, test,
original-check, package, AGENTS and original-workflow guards passed on Apple and
on independent local recheck. The original financial sample remains byte-identical;
only diagnostic dispatch and an appended executable extension are permitted.
No FinanceStore, TripSimulation, identity, aircraft, heap or existing test changes.
A later evidence-only publication changes documentation, not the tested code.

Apple Swift 6.1.2, Xcode 16.4 (16F6), arm64 macOS 15.7.9 (24G830), Darwin 24.6.0.
Reported machine: VirtualMac2,1; 3 CPUs; 7,516,192,768 bytes RAM; 16,384-byte pages.
This is a virtual Mac CI environment, not an iPhone measurement.

## Executed gates

| Gate | Actual result |
|---|---|
| Debug | 142 named tests / 11 suites PASS; 40.231 s reported test duration |
| Release | 142 / 11 PASS; 6.107 s |
| TSan | 142 / 11 PASS; 137.752 s; no sanitizer warning/error reported |
| External compiler contracts | 29 required rejections, five valid client objects |
| Corruption fail-stops | 12 expected stops with invariant markers |
| iOS Release library compilation | All five libraries succeeded; not device execution |
| Diagnostic Debug and Release | Both passed normalized transcripts at nine sizes through 100k |
| Three sequential full measurement processes | All raw streams complete, analyzer and legacy CLI check passed |

Transcript sizes: 64/255/256/257/1k/5k/20k/50k/100k. Full normalized public state
and arrival history match between wall and counters; both match original economic
aggregates. Full baseline-executable transcript comparison is not claimed.
The 142 original tests and independent financial/reference/partition tests remain.
Diagnostic checks are separate, not extra named library tests.

## Complete raw data and recomputation

Each process ran three warmup rounds and 30 measured rounds for each of five
sizes, with baseline, wall and counters on fresh worlds in alternating order.
Total: 1,350 measured worlds, 135 warmup worlds, 372,600 measured batch records,
37,260 warmup batch records and 12,000 empty calibration windows. Each size/mode
has 90 measured worlds. At 20k there are 7,110 actual batches per phase per
instrumented mode. No percentile below is inferred from old sample maxima.

The three raw NDJSON files are authoritative. They include every complete world,
all warmups, calibration windows, batch identities, counters and completion flags.
An independent local rerun of the published analyzer reproduced batch-summary.json
byte-for-byte; SHA-256:
cacb2a57f19b5921d0fac993ae6f7b785df9f83836e59a5442bb1a2563aa6567
All 186,300 measured counter-mode batches had valid deltas for the selected fields.
Including warmups, all 409,860 before/after snapshots reported successful thread
and process reads. No negative CPU delta was observed. This does not validate
uncollected fields or turn process-wide counters into thread-local evidence.

## Per-batch observations, not deadlines

All times below are milliseconds. Percentiles use nearest rank of actual batch
records; each phase includes its final partial batch. Full/partial and first-batch
strata, departures, lifecycle times and all spikes remain in the full JSON report.

| Aircraft | Mode | Phase | Batches | p50 ms | p99 ms | Max ms | >1 ms | >5 ms |
|---|---|---|---:|---:|---:|---:|---:|---:|
| 1,000 | counters | advance | 360 | 0.124584 | 0.392791 | 0.440875 | 0 | 0 |
| 1,000 | counters | collect | 360 | 0.049459 | 0.153542 | 0.219458 | 0 | 0 |
| 5,000 | counters | advance | 1,800 | 0.141791 | 0.437042 | 0.851666 | 0 | 0 |
| 5,000 | counters | collect | 1,800 | 0.048292 | 0.171333 | 1.610041 | 1 | 0 |
| 20,000 | counters | advance | 7,110 | 0.174167 | 0.614500 | 32.748166 | 27 | 4 |
| 20,000 | counters | collect | 7,110 | 0.048416 | 0.147250 | 3.479625 | 4 | 0 |
| 20,000 | wall | advance | 7,110 | 0.173667 | 0.609709 | 26.065958 | 28 | 3 |
| 20,000 | wall | collect | 7,110 | 0.048583 | 0.157708 | 1.126916 | 1 | 0 |
| 50,000 | counters | advance | 17,640 | 0.203000 | 0.831625 | 32.279542 | 110 | 6 |
| 50,000 | counters | collect | 17,640 | 0.048750 | 0.168959 | 20.669167 | 7 | 1 |
| 100,000 | counters | advance | 35,190 | 0.234041 | 0.829750 | 17.098166 | 198 | 9 |
| 100,000 | counters | collect | 35,190 | 0.048375 | 0.150042 | 3.131917 | 11 | 0 |
| 100,000 | wall | advance | 35,190 | 0.235042 | 0.827125 | 57.649334 | 221 | 13 |
| 100,000 | wall | collect | 35,190 | 0.048834 | 0.171500 | 13.982209 | 28 | 5 |

Across both instrumented modes and all three phases: 828 batches exceeded 1 ms,
52 exceeded 5 ms. These are retained, including the 57.649334 ms wall-only arrival.
The untouched baseline also remains in raw data; its 20k observed largest arrival
was 3.007291 ms and collection 2.278292 ms in these runs. Different mode maxima
are not a causal before/after comparison and do not establish an improvement.

## What the counters distinguish — and what remains unresolved

The largest counter-enabled 20k arrival is run 1, measured sample 14, batch 43
(zero-based): wall 32.748166 ms; enclosing thread CPU 0.527500 ms; process user
0.512 ms, system 0.017 ms, minor/major faults zero, involuntary switches +1.
The before/after read envelopes are 0.000584/0.011250 ms. In that world, arrivals
total 95.335750 ms, sum of inner batches 94.080628 ms, outside-batch difference
1.255122 ms. Most of this world's elapsed time is inside the recorded batches,
not an inferred unmeasured 70 ms gap. It is NOT the old R004 sample 15.

Among 22 counter-enabled batches exceeding 5 ms, 19 have enclosing thread CPU
below 1 ms. This supports substantial elapsed delay not accounted as CPU use by
the measured thread; it does not identify host scheduling, guest descheduling,
blocking or another cause without a trace. All 22 have zero reported process
minor/major-fault deltas; 21 have positive involuntary-switch deltas. Those wider,
process-scoped intervals do not locate a switch at an exact event instruction.

Three arrival batches must NOT be dismissed as purely external pauses:

| Aircraft / run / sample / batch | Wall ms | Enclosing thread CPU ms |
|---|---:|---:|
| 50k / 1 / 6 / 95 | 6.398625 | 6.446041 |
| 50k / 2 / 30 / 126 | 6.259125 | 6.492625 |
| 100k / 2 / 16 / 98 | 5.109917 | 5.036667 |

CPU brackets are wider and sequential, explaining why CPU can exceed inner wall.
These observations do not identify a code function, allocation cost, frequency
change or VM accounting effect. Symbolized attribution and scheduling evidence
remain necessary; no hypothesis is certified from a single coincident counter.

First-arrival-batch median wall times in counters mode: 20k 0.288625 ms,
50k 0.591166 ms, 100k 0.699792 ms. All 90 measured first batches at each of those
sizes had zero minor-fault delta. The nine warmup first batches per size retained
nonzero fault deltas in some worlds (maxima 80/252/361 respectively). This supports
separating cold/first-use and reused-allocation conditions; it does not prove an
origins-specific cause or justify replacing the index. No MallocPreScribble or
cold-world causal experiment was executed in this update.

## Diagnostic overhead and unhidden lifecycle costs

Empty recording-loop mean cost per window, three processes: wall 0.146-0.305 us;
counters 1.742-2.642 us. Inner clock-bracket median was 42 ns. These are measured
loop costs, not guaranteed per-syscall prices; raw maxima and empty windows remain.
At 20k, median paired phase ratios counters/wall: departures 1.100614, arrivals
1.012798, collections 1.020806. Wall/baseline ratios: departures 0.987453, arrivals
0.996515, collections 1.010850. The dispersion is large; neither a ratio below 1
nor these medians prove zero overhead or isolate cache/allocator/scheduler effects.

For context, 20k counters-mode median lifecycle values: initialization 1.009500 ms,
registration 1.446875 ms, all arrivals 18.674500 ms, all collections 4.892166 ms,
final audit 3.873791 ms, explicit world release 1.156916 ms, whole measured workload
36.726042 ms. Separate medians do not add to a median total. Trace preparation,
seed/handle setup, expenses and all other recorded fields are available in JSON.
No cost was removed by changing business code or hidden as a claimed optimization.

## Preserved failures and scope limits

Local Swift 6.2.1/Linux: independent Debug/Release 142/11 passed; both diagnostic
transcript modes, 29 compiler rejections, five valid clients and 12 corruption
probes passed. Five additional analyzer adversarial probes rejected reordered,
missing, incomplete and invalid-zero data as expected. This is separate evidence.
The initial multi-file @main conflict, non-testing-module Release build failure,
fresh Release wrapper timeout with a later independent passing rerun, and unsupported
streaming invocation remain recorded. Two full local measurement invocations hit
their requested wrapper caps (90/180 seconds), leaving 385 complete NDJSON lines
each (24,189,821 / 23,782,682 bytes). Neither is a completed full performance run;
no process remained running. Apple success does not rewrite these local outcomes.
No new local TSan result is claimed; the Apple TSan result above is independent.

No durable IDs, database/save/recovery, real routes, scheduled payroll/maintenance,
full documents/media, treasury, iOS application or map is implemented here. No
physical footprint, hardware instruction/cycle counters, runnable-time, allocation,
frequency, energy/temperature, iPhone frame or full-game acceptance is measured.

## Decision and exact next step

The measurement-only patch is verified on its isolated branch. Do not merge an
index redesign, declare the old spikes solved, or call under-5-ms/under-1-ms or
thermal goals achieved. Main remains the permitted published R004 foundation.
Next: retain this evidence, obtain symbolized execution/scheduling attribution
for the three near-CPU arrivals, and separate cold-first-use from warmed worlds
in a controlled diagnostic experiment. Select a minimal owner-local optimization
only after the evidence supports it. R005 stays after this diagnostic decision.
