# NEXORA — current state

Session date: 2026-09-30 / Asia/Riyadh. Repository bdr-design/NEXORA only.
AGENTS.md read and remains mandatory. Excluded branch names are a denylist only:
archive/before-radical-rebuild-20260930; audit/nxr-0003-20260930;
fix/nxr-0003-contract-repair-20260930. No content from these branches was read.
No destructive checkout/reset/history rewriting, force push or background promises.

Single active branch: diagnostic/r005-design-1m-20260930.
Session HEAD verified before work: 8d5036fb9f9294d24f11c7291ae3e07205db7166.
Main remains 38ce39cf9322f47e4def5f6eddb425c5a66ea7f9. No new main merge.
Latest owner instruction authorizes executable Swift/order/storage experiments and
requires results, not another ADR. Production design/billing/retention still await
owner decision after those results. Do not implement new HR/maintenance/delivery.
No production Sources, Tests, Checks, root Package.swift or AGENTS change.
Historical permitted branches remain historical. Preserve previous results/failures.

New work is isolated in Experiments/R005Swift, a Swift 6 executable package using
safe ContiguousArray-owned columns, an actual resumable hierarchical timing wheel,
atomic accrual, exact ordered reference comparisons, deliberate scheduler mutants,
canonical full checkpoint + command WAL, and disposable closed-detail compaction.
The C shim is only allocator/clock/footprint/hash/file-descriptor instrumentation;
no simulation state is stored through unsafe C or Swift pointers.
New .github/workflows/r005-swift-executable.yml supplements every existing gate.
It does not replace the old142 Swift tests, compiler, corruption or sanitizer gates.
CI records physical footprint, calibrated allocation-entry counts and ns/event;
wall-clock values are observations, not speed pass/fail thresholds.

Local source compiled on Swift6.2.1/Linux; exact R004 event comparisons caught and
corrected an initial prototype generation mismatch (1 versus actual0). A nested
map expression also required splitting for the Swift type checker. Original tests
were not normalized or changed. Codeload failed DNS; a verified permitted artifact
provided the identical unchanged production sources for local compilation.
Local Release tests passed eight real injected mutants (seven classes with +/-1
separate),nine boundary groups,exact event order through1M,23 real SIGKILL points,
47 torn WAL tails and15 storage/arithmetic negatives. Apple results for this NEW
source are pending at commit creation; never label upload as a passing run.

Scopes that must remain explicit: the new kernel accrues and does not issue the
same individual invoices as R004; elapsed comparisons are not full-engine speedups.
Owned column capacity is not phys_footprint. Allocator interposition is calibrated
on actual Swift arrays and counts covered entry calls on the measured thread,
not kernel VM activity. The typed checkpoint is a full copy, not incremental save.
Retention files are generated test data only; no real financial record was removed.
A one-day five-trips/90%-settled fixture and three-period correctness case do not
prove bounded lifetime storage with arbitrary open debt. No iPhone/device/heat/FPS,
0.5us production-event or2ms save-visible-pause achievement is claimed.

R004 bounded acquisition remains INCONCLUSIVE; no new spike acquisition.
Artifact11115497993 SHA2566eb273848b9e37eb074dac106e6bf86269cbbfe4afb1337a1d2d8f286dd9354e
is the only raw input for the requested cheap runnable reanalysis. XNU defines
runnable as including running and aggregates over the task. Missing recorded
mach timebase cannot be guessed; raw values cannot be called wait-only time.
Physical Mac fallback is optional if actual hardware becomes available, not a
prerequisite to this experiment. PMU instructions/cycles were unavailable on VM.

One short RESULTS.md from the executed suite is the next delivery, with all
metrics, failures, exact source and remaining scope. No new design document.
At resume re-read this branch HEAD and workflow results before further changes.
