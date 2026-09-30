# NEXORA change log — permitted foundation line

## NXR-R003 — 2026-09-30 — verified timed-trip core
Actual bounded clock/arrival coordinator and fixed-capacity heap, separate input
sequence, explicit prefix/block results, compound-state tests, sorted-list oracle,
compiler/fail-stop gates and scale CLI. Apple run36655778966 on
50a9fb82db7ea13f636b5c4b3e4f104d8bb7b113 passed 86 named tests each Debug/Release/
TSan, all 18 compiler misuse gates, eight corruption probes and four iOS library
compiles. Complete exported source and artifact hashes verified; see
Docs/VALIDATION-R003.md. Not complete gameplay or device approval.

## NXR-R002 — 2026-09-30 — verified aircraft lifecycle core
Actual AircraftStore lifecycle, revision/operation contracts, exact failure audits,
independent model and compiler/corruption probes. Apple code4583de236d5aa25b06bbd3ed4a2492e8cb629835,
run36653271004 passed 51 named tests each Debug/Release/TSan and all other core
gates. Evidence and limits: Docs/VALIDATION-R002.md. Not complete gameplay.

## NXR-R001 — 2026-09-30 — identity and bounded timeline
Initial permitted small identity/observability foundation, 19 named tests plus
compiler checks and identity-only scale fixture. It did not implement aircraft
business rows, time, finance, storage or presentation. Its measurements are not
results for the later modules. The permanent exclusion in AGENTS.md governs all
work; no older recovery-use wording grants permission to use excluded sources.
