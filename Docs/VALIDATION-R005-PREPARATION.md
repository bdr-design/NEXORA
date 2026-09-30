# R005 preparation — actual gates and measured scope

Date:2026-09-30/Asia-Riyadh. Repository:bdr-design/NEXORA only.
Active branch:diagnostic/r005-design-1m-20260930. No production R005 implementation.
ADR and mandatory budget addendum remain PROPOSED; owner approval required.

## Source/work line

Main was fast-forwarded5b559989 ->38ce39cf after verified ancestry through
0706447/5384b58 and the existing hardening/trace commits. Its last checked value
is38ce39cf9322f47e4def5f6eddb425c5a66ea7f9. No force/history deletion or excluded
source access. Old permitted branches are historical,not active parallel work.
The121-file38ce39c snapshot came from prior Apple artifact11109917585; all bytes/
modes rebuilt tree0aaa246af5dc66008683f35754ec211da831e729.

New acquisition/code b097ae64ab539c60fc82f08ec4c60a79cb65c124 has135 files/tree
7aaa172bd3d1ea722ce7e3a66c8833a09a41a714, independently reconstructed from its
Apple source ZIP. The generated-source hash is
070b078cff6fa0acc6b5e5c260d32e07c391b7542a7ef6f51167bd439c04f717 and matches locally.
The compiler-wrapper correction357dcd4e0658d84b821b3fcd9360b7fc29255225/tree
6f559be380ed4b8320c6f423988bfbf7b6a856f8 changes only run_layout.py and its daily
record relative to b097ae64. No production Sources,Tests,Checks,Package or original
workflow was changed by this preparation. A documentation-only publication may
follow; it is not the acquisition's source commit. Re-read live HEAD.

## One bounded diagnostic iteration

Run36754290347: diagnostic job110020462756 SUCCESS, layout job110020462644 FAILED
at compile before any Apple layout measurements. Do not call the whole run green.
Raw acquisition artifact11115497993 SHA256:
6eb273848b9e37eb074dac106e6bf86269cbbfe4afb1337a1d2d8f286dd9354e.
540 measured worlds+54warmups,359640 measured batches; V4 enabled on179820.
All measured instructions/cycles endpoints were zero and retained as unavailable
under the requested policy. Runnable is raw,not a wait-only time measurement.
35>5ms observations preserved. Separate event study510000 event timestamps and1998
allocation brackets. Raw analysis rerun locally is byte-identical to Apple output.
See Docs/R004-BOUNDED-DIAGNOSTIC-VERDICT.md. No second hosted acquisition is requested.
Physical Apple Silicon fallback is not performed; no causal/instruction comparison
success is claimed. The review advances to design without inventing that result.

## Corrected Apple run36754835103 — all three jobs SUCCESS

Code357dcd4e0658d84b821b3fcd9360b7fc29255225.
Contracts job110022312317,layout110022312200,diagnostics110022312513.
Apple Swift6.1.2/arm64 macOS15.7.9/Xcode16.4 (16F6),AppleClang17.

| Executed gate | Actual result |
|---|---|
| Original Swift Debug |142 named tests/11 suites PASS; reported34.622s|
| Original Swift Release |142/11 PASS;5.005s|
| Original Swift TSan |142/11 PASS;125.096s; no sanitizer warning/error in retained log|
| Existing evidence-validator Python |92 PASS;17.526s|
| New counter contract Python |12 PASS|
| Original diagnostic transcript |9sizes through100k in Debug/Release/TSan PASS|
| Additional V4/event transcript |9sizes through100k in Debug/Release/TSan PASS|
| Exclusive writer |14tests each Debug/Release/TSan PASS|
| Trace-marker transcript |Debug/Release/TSan PASS|
| External compiler |29 required rejections;5 valid clients via unchanged scripts|
| Corruption boundary |12 expected fail-stops with invariant markers|
| iOS library build |all5 libraries BUILD SUCCEEDED; not device execution|
| Layout prototype |12cases Debug+12Release,including1M/2M andE/N1,2; PASS|
| C ASan/UBSan |internal boundary suite+100k/density2 PASS|

Existing and new parameter cases are not added to the142 named tests. Prototype
internal subcases are not advertised as separate Swift tests. Test durations are
not event/frame timing. The bounded acquisition step is intentionally not repeated
in this correction run; it is an experiment,not a disabled correctness gate.
All correctness/transcript/sanitizer/source/allocator gates remain enabled.

Corrected-run artifacts, bytes independently rehashed:
- r005-contract-logs11115619710:45c65dc5b2a88fe63c98e5d98bef264a1bafb18b60cfe71730f3f0ebc3b817a9.
- r005-layout-metrics11115618651:6a761223f1493c88d7d69a547983813c490b6c89f3401db471b05c3ed766eff4.
- Additional transcript/source artifact11115883776 is listed by GitHub as791373ea005595b60b467b602bee042f1efc1095ed3867b36ddb807fea2fe0db; not independently downloaded in this check.

## Prototype budget results — NOT complete-engine acceptance

| N assets | Event capacity | Requested owned bytes | B/asset |
|---:|---:|---:|---:|
|1000000|1000000|122658024|122.658024|
|1000000|2000000|162658024|162.658024|
|2000000|2000000|245283024|122.641512|
|2000000|4000000|325283024|162.641512|

The same numbers were observed in Debug and Release and match the explicit column
formula.29 owned allocations at creation; zero OWNER-tracked allocations in the
kernel/advance calls. This is not a process-wide allocator interposition result
and does not establish zero allocations for the future Swift/finance/save path.
Sequential/permuted traversals give identical final checksums.1M results also match
across budgets1/7/31/256/1024 and both reserved event densities.
PMU instructions/cycles are unavailable on this Apple VM as well. No instructions/
full-event value,physicalfootprint or device0.5us acceptance is claimed.
No actual durable snapshot is produced; snapshotBytes is null. The column payload
upper bound is separately labeled. Reserve formulas for further ID mappings and
fixed ledger/policy/cache/WAL state are proposals in R005-BUDGET-ADDENDUM.md,
not extra measured allocations hidden inside these prototype numbers.

## Preserved failures and local evidence

The first layout wrapper requested POSIX-only declarations while including Darwin
libproc headers. The repeated labeled preflight now retains19 compiler errors,
including hidden BSD types,rusage_info_t,RUSAGE_INFO_V4 andCLOCK_UPTIME_RAW.
The accepted Darwin build omits that POSIX-only feature macro while preserving
-Wall,-Wextra,-Werror and all tests; Linux retains its required POSIX feature flag.
This is a platform declaration fix,not relaxing a failed runtime/logic check.
The first wrapper also failed to print captured compiler stderr; fixed and documented.
The old failed job/artifact are retained,not reclassified.

Local Linux/Swift6.2.1: original Debug142/11 PASS26.543s,Release142/11 PASS6.025s;
additional Release transcript9sizes PASS; original generated Debug transcript9sizes
PASS before the later clock/metadata-only refinement. Final production source stayed
unchanged. New Python12 PASS. Layout12Debug+12Release PASS; final owner-wrapper
Release rerun12 PASS;C ASan/UBSan internal suite+100k PASS.
A local protocol smoke (1measured repetition,not a full performance campaign) and
9event worlds were validated; Linux counters remained unavailable. Their host
latencies are not merged with Apple distributions.
Initial generator anchor failure,partial generated build,warning-as-error failure,
Debug/Release tool timeouts and an incomplete local92-test Python command remain
in Docs/Daily/2026-09-30-R005-LOCAL-FAILURES.md. Successful independent reruns and
Apple92-test results do not convert those failed/incomplete commands into successes.

## Remaining approval and physical gates

The ADR covers identity,layout,wheel,finance,storage,replay,prepare/commit,deadlines,
read model,policies,UI commands and configurable quotas. It does not implement them.
Mandatory A1 decision: fixed storage for unlimited arbitrary financial history
versus no deletion. Default is lossless retention with quota backpressure. No
financial record was deleted and no production billing rule changed.
Stage0's physical fallback,Stage2–4 implementation,full-path allocator/footprint,
crash recovery and all physicaliPhone frame/CPU/thermal/energy/save measurements
remain unperformed. No IPA/app/20k-or1M full-game acceptance is implied.
