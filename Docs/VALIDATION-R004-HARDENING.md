# R004 stage A — verified evidence-boundary hardening

Date: 2026-09-30 / Asia/Riyadh. Repository bdr-design/NEXORA only.
Tested code: 74d8a7f1d072209aee3d8e7e964d76468890a694.
Tree: c1ef6e3dc1581fc125e7f7b5f34985c74f7edd74, 116 files.
Parent: 5384b58d193f90859a8f0efeaec6d28d6e93b89e. Main unchanged.
Apple run 36737270689 / job 109962144323 SUCCESS, completed 15:37:39Z.
Artifact 11109145497 SHA256:
2f0737e4f72fe1386aebb2878031ce88614bccc6c6d1ca44d2a04c26a664f950.
Nested source ZIP SHA256:
6a7813dc03d249f286ed080005beb9b9e6ae84e73de039c7928008ce860d70dc.
Downloaded bytes and all executable modes reconstruct the exact tested tree and
match the local source byte-for-byte. No excluded implementation was used.

Apple Debug, Release and TSan each passed 142 named Swift tests / 11 suites.
77 Python tests passed (43 retained + 34 new; parameter subcases not extra tests).
The actual diagnostic executable completed its nine-size transcript selftest in
Debug, Release AND TSan. Actual writer tests: 14 in each of those three modes.
Eight processes competing for one destination produced exactly one successful
create; old regular/empty/link/FIFO destinations were preserved. Checks include
closed writes, idempotent close, embedded NUL, invalid/missing source identity.
29 compiler rejections, five valid clients and 12 invariant fail-stops passed.
The original 372600 measured records remain accepted and the summary is
byte-identical to its pinned original, including every outlier.
New quick NDJSON records the actual tested GITHUB_SHA; this is a schema/CLI smoke,
NOT a repeated latency campaign. No new iOS compilation or device test occurred.

Guards now reject hidden-directory Swift additions, deletion, mode changes and
symlinks. Schema 1 rejects incomplete/unknown/duplicate/nonfinite fields and wrong
counter units/scope. DiagnosticWriter and analyzer output use exclusive creation.
Legacy --json remains unchanged. The guard's explicit diagnostic exceptions are
not cryptographic self-attestation; source/run association is independently checked.
No production library, financial rule/index, original Swift test or Package change.

Local Swift 6.2.1/Linux Debug/Release passed 142/11; final writer 14/14 in each;
Python77 passed. Initial error-message expectations failed twice under stricter
validation and were corrected without accepting invalid data. A local quick smoke
mistakenly labeled modified code with its parent SHA remains quarantined and is
excluded from verified/performance evidence. See continuity and local failure log.

Actual xctrace templates and record/export help were captured on Apple. Time
Profiler and System Trace are listed; listing is not proof that recording/export
is permitted or useful. Next step is separate causal acquisition, not a speculative
optimization or R005. This validation remains tied to code74d8a7f1, not later tracing.
