# R004 — bounded diagnostic iteration verdict

Date:2026-09-30 / Asia/Riyadh. Repository:bdr-design/NEXORA.
**Status: bounded acquisition completed; causal verdict INCONCLUSIVE; physical
Apple Silicon fallback NOT PERFORMED. No production performance fix.**
The old investigation is not an indefinite prerequisite for reviewing R005's ADR.
This is a stopping decision for this iteration, not proof that all causes are known.

## Source and actual execution

Old reference artifact11086348930/run36692367500 remains pinned to SHA256
34317f1a041179325ac93a0f9925634df3d1736c6ae4b3f68e5185f66369b9e4.
It was not re-benchmarked or filtered in this iteration. The no-origins-spike-fix
instruction was followed. No financial/business library was edited.
New acquisition source:b097ae64ab539c60fc82f08ec4c60a79cb65c124;
tree7aaa172bd3d1ea722ce7e3a66c8833a09a41a714,135 files.
Apple run36754290347/diagnostics job110020462756 SUCCESS. The overall run also
contains a failed layout compiler job, which must not be called a successful run.
Artifact11115497993/r005-bounded-study SHA256:
6eb273848b9e37eb074dac106e6bf86269cbbfe4afb1337a1d2d8f286dd9354e.
All source bytes/modes reconstructed the exact tree. Generated instrumentation
SHA256070b078cff6fa0acc6b5e5c260d32e07c391b7542a7ef6f51167bd439c04f717
matches the independently generated local copy. Original Sources/Tests/Package
remain byte-identical to the permitted baseline; instrumentation is in a separate
created copy and normalized transcripts pass through100k in Debug/Release/TSan.

Environment:Apple Swift6.1.2,arm64 macOS15; actual hw.model VirtualMac2,1,
3 virtual CPUs,7GiB advertised RAM; kernel RELEASE_ARM64_VMAPPLE.
This is not physical Mac or iPhone evidence.

## Acquired observations, not inferred historical counters

Three processes;20k/50k/100k;30 measured worlds/mode/size/process after3 warmups;
alternating control/V4 on the same generated source. Control retains existing
thread/process counters but does not call V4. Total540 measured worlds plus54
warmup worlds;359,640 measured batch/page records,179,820 in V4 mode.
Instructions and cycles endpoints were zero in EVERY measured V4 batch. They were
encoded as unsupported/no value with the explicit zero-policy reason. This is an
availability classification for this experiment,not proof of all hardware support.
359,640 before/after endpoints per field retain this status. Runnable endpoints
were positive and are retained RAW; no guessed Mach conversion or wait-only label.

Consequently,none of the historical three target positions has usable instruction
counts for the requested peer comparison. No 1.5x classification can be made.
There are35 new >5ms batch observations:control19 arrivals/3collections;
V4 9arrivals/4collections. They are preserved,not treated as failed CI budgets.
Largest new wall observation37.524958ms/control/100k/run2/sample22/batch51.
This is a new observation,not proof of a universal code/external cause.
Empty V4 enclosing-window medians:959ns,958ns,2375ns across the three processes.
These intervals include observer work and are not subtracted blindly from events.

Separate per-event mode:9 worlds,510,000 event start timestamps and1,998 allocation
brackets,all preallocated. Largest allocation bracket30,083ns; largest within-batch
next-start gap3,536,625ns. Last-event duration is not independently measured; gaps
include other work and observer effects. This separate sample did not capture the
old three events and cannot retrospectively assign their causes.

Both raw analyzers were rerun locally; outputs matched Apple summaries byte-for-byte.
No old outlier was dropped. No 0.5us/device/FPS/thermal/save acceptance is implied.

## Judgment boundary and next action

Low threadCPU relative to wall supports an off-CPU/unaccounted interval,not naming
who ran instead. Equal retired instructions do not exclude cache/memory stalls or
other on-CPU costs. Zero page faults excludes only that observed mechanism,not
every possible index cost. These limits do not change the decision to avoid an
origins replacement as a speculative spike fix. New measurements cannot recover
instruction counters that were never collected on the historical events.

The requested one-time physical Apple Silicon fallback remains outstanding.
No connected physical-machine execution was performed. A remote-terminal plugin
was found as a possible future connection,not installed or used; it does not supply
a physical Mac by itself. See Experiments/R005/PHYSICAL-FALLBACK.md for the pinned
source/reproduction procedure. Do not silently relabel a hostedVM as physical.

Stop repeating hosted acquisitions for this question. Preserve this inconclusive
verdict and proceed to design review. R005 production awaits explicit ADR approval,
including storage-retention interpretation; causal closure or device acceptance
must not be fabricated to pass that gate.
