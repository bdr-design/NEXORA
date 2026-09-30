# R004 measurement-only contract

2026-09-30, Asia/Riyadh. Development diagnostics, not an optimization or R005.
Baseline: 5b5599895fa1bdbf00e951104e0cd55dc00f9a56, tree
ba59efc7ceea44ded86542001374820b8a2bb080. AGENTS permanent exclusions remain.

## Ownership and isolation

The executable owns one local TripSimulation per fixture. It calls the same
registration, priced departures, bounded advance, invoice-page collections and
three cash expenses as the original R004 fixture. The library owns all economic,
aircraft, queue and clock writes. The diagnostic extension writes only its trace
buffers and, after the completed world, its output stream. It does not enter
prepare/commit, change a library's public interface, install callbacks, add a
per-entity actor/task/lock, or alter failure/retry semantics. Original success and
failure checks remain. All original Sources/Tests/Checks, Package.swift, AGENTS.md
and restart.yml identities are mechanically guarded, stripping only the single
new CLI dispatch and appended measurement extension from the financial executable.

## Three modes on the same source

- baseline calls the untouched original sample; it retains its original aggregates.
- wall groups departures into control batches of 256 and records every departure,
  advance and collection page. Arrival budget and page size stay 256.
- counters uses the same wall-mode loops, adding resource snapshots outside each
  inner wall bracket. No counter read is inside the measured business call.

Each process has three warmup rounds and 30 measured rounds at each of
1k/5k/20k/50k/100k. Every round executes all three modes on fresh worlds. Order
alternates baseline/wall/counters and counters/wall/baseline by round and run ID;
three sequential processes reverse which mode runs first across processes.
Inputs, fares, destinations, durations and sequence are unchanged. Fresh identities
and randomized dictionary hashing mean address/hash placement is not identical.
This is an A/A diagnostic-overhead experiment, not an old/new library comparison.

A separate Debug/Release correctness mode compares full normalized public
transcripts between wall and counters at 64/255/256/257/1k/5k/20k/50k/100k: all
advance fields and ordered completions, arrival invoices, final aircraft states,
all invoice/journal pages and final summary. Local slot/generation/operation and
invoice numbers replace process pointer identities. Both also match the original
fixture's economic aggregates. Normalization is NOT computed in performance runs.
It is not a claim of full transcript comparison against an unmodified baseline
executable; library/legacy byte guards and the retained reference tests provide
separate evidence for that boundary.

## Brackets, storage and output

The exact trace capacity is three times ceil(aircraft/256). Optional record slots
are allocated and initialized before world initialization; no trace growth occurs
in any phase. Slot writes and counter reads occur outside inner wall brackets,
but inside the corresponding phase totals. Export, JSON encoding, text and file
I/O occur after world release. One NDJSON line holds one completed world, preserving
previous complete worlds if a later one fails. A failure marker invalidates the
run. An in-progress failing world's partial trace is not currently exported;
do not describe such a failed artifact as a complete set of raw batches.

Every batch has world size, 1-based sample, mode, 0-based phase-local batch,
operation count, start offset and elapsed wall nanoseconds. Parent records add
process/run ID, execution position and warmup classification. Source/OS/toolchain
and kernel metadata accompany Apple artifacts. All warmups, read failures, zeros
and spikes are retained. The analyzer validates physical serialized execution
order, complete triples, exact batch totals, phase sums and original economic
formulas; it rejects incomplete files or invalid readings pretending to be zero.

Advance wall measures the advance call. Collection wall includes page retrieval,
collection postings and offset update, as in the legacy bracket. Phase totals also
include loop/check/result-release/recording/counter work. Their nonnegative
arithmetic difference from summed inner windows is reported without a causal
label. Initialization, trace preparation, capital/handle preparation, registration,
expenses, audit, workload total and explicit consuming world release are separate.
Detached handles/views can retain stamps; the world-release measurement is NOT
all remaining ARC or process teardown. No cost is declared eliminated or moved
out of sight. 2,000 empty windows in each instrumented mode measure both inner
clock cost and the enclosing probe/recording loop. No calibration is subtracted
from the raw samples.

## Counter definitions and limits

| Fields | Source | Unit and scope |
|---|---|---|
| threadCPUNS | clock_gettime(CLOCK_THREAD_CPUTIME_ID) | ns, calling thread user + kernel CPU |
| processUserNS / processSystemNS | getrusage(RUSAGE_SELF), timeval | microseconds converted to ns, all process threads |
| processMinorFaults / processMajorFaults | ru_minflt / ru_majflt | counts, process; not an allocation count |
| processVoluntarySwitches / processInvoluntarySwitches | ru_nvcsw / ru_nivcsw | counts, process; not event-specific |

Each read records begin/end offsets, success/failed/invalid/unsupported status,
errno for syscall failures and nullable values. Time conversion is checked for
negative fields, fractional bounds and overflow. Valid zeros remain zero. Missing
or failed values stay absent, and decreasing counters produce an invalid delta,
not a clamped zero. Snapshot reads are sequential and not atomic. Their intervals
enclose more than the inner wall bracket and include probe work. A wall/CPU gap,
page fault or switch can support an investigation but does not by itself identify
the cause or exact point inside the measured event. No automatic causal verdict.

The first probe deliberately does NOT collect proc_pid_rusage V4 runnable time,
instructions/cycles, thread-local page faults/switches, frequency, scheduler trace,
physical footprint, allocation counts or thermal/energy data. These omissions are
explicit metadata, not successful zeros or a claim that the hardware lacks them.

Primary platform references reviewed during implementation:
- Apple getrusage manual: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html
- Apple Libc gen/clock_gettime.c and gen/clock_gettime.3 at 71bbe350ab79eef58113991d817ccc6165061a64:
  https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/gen/clock_gettime.c
- Apple XNU bsd/kern/kern_resource.c at f6217f891ac0bb64f3d375211650a4c1ff8ca1ea, calcru/getrusage:
  https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_resource.c

The Libc code converts raw thread usage internally; timespec is already seconds
plus nanoseconds and is not converted with mach_timebase again. The reviewed XNU
revision derives minor faults from task faults minus pageins, major faults from
pageins and involuntary switches from total minus voluntary, clamping internally.
That source revision is not asserted to be the runner's exact kernel build; the
artifact records its actual kernel and toolchain. Interpret process values as the
OS-reported counters, not a thread/event allocation or scheduler trace.

## Reporting and acceptance

Report actual per-batch nearest-rank p50/p90/p99/max, full/partial batch separation,
first-batch distributions and counter coverage, all observations above 1 and 5 ms,
phase/lifecycle totals and paired A/A observations. Keep the complete raw stream.
Do not derive batch percentiles from the 30 old R004 sample maxima. No iPhone
execution, 20k full-game acceptance, 100k complete simulation, heat reduction or
hard 1/5-ms deadline is established. Finance index changes remain a later separate
experiment only after adequate evidence; persistence/R005 remains unimplemented.
