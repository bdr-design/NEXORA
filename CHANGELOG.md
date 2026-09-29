# NEXORA Changelog

Every meaningful repository change must be represented by an Update ID and linked to a detailed update record.

## NXR-0001 — 2026-09-30 — Foundation Reference
Status: Foundation / development
Version: `0.1.0-dev.1`
Build: `1`

### Added
- Independent NEXORA repository as the technical source of truth.
- Clean-room rule: no technical reuse from the previous game.
- Mandatory working-method and safety guardrails.
- Architecture definitions for state, scheduling, jobs, persistence, diagnostics, rendering, UI read models, enterprise capabilities, industries and testing.
- Diagnostics-first root-cause requirement.
- Performance/thermal budgets.
- Scale gates: 1k, 5k, 20k, 50k, 100k.
- 20k full assets minimum acceptance; 100k architecture target.
- Capability-based company model.
- Financial-document requirements including incoming/outgoing transfers, cheque images, transfer proofs and receipts.
- Daily engineering journal, update records, release records and version metadata.
- Real project directory skeleton.

### Not yet implemented
No gameplay engine, runtime performance result, or IPA is claimed by this update.

Detailed record: `Docs/Updates/NXR-0001-2026-09-30-foundation-reference.md`


## NXR-0002 — 2026-09-30 — Core Foundation Benchmark
Status: Implemented / pre-Scheduler validation
Version: `0.1.0-dev.2`
Build: `2`

### Added
- Swift 6 language-mode package foundation targeting iOS 18+ / macOS 15+.
- Bounded diagnostics API and ring buffer plus Apple signpost adapter.
- Global generational `EntityID` registry with stale-handle rejection and slot recycling.
- Packed sparse↔dense asset storage with O(1) swap-and-pop mapping repair.
- Domain revisioning and all-or-reject validate-then-commit path.
- Bounded parallel compute with deterministic worker-index merge.
- CoW-aware benchmark discipline that releases read snapshots before authoritative mutation.
- Raw-sample benchmark executable for 1k/5k/20k/50k/100k.
- Apple XCTest Clock/CPU/Memory metric test.
- macOS GitHub Actions gate with warnings-as-errors and permanent benchmark artifact metadata.

### Validation
- Local Release: 8/8 tests PASS.
- Local Thread Sanitizer: 8/8 tests PASS; no reported data race.
- GitHub Actions run 36638640053: PASS.
- macOS Release suite: 9 tests PASS.
- macOS 100k synthetic preflight: compute p99 0.096 ms; merge p99 0.004 ms; commit p99 0.048 ms; end-to-end p99 0.155 ms; RSS 12.70→12.72 MiB.
- CI artifact SHA-256: `062d3c0aae0c8e52fd96b44f4b2e8ca644c7f3603f9998151f4320b3653c102c`.

### Important limits
These are synthetic core measurements, not proof of 100k full gameplay assets and not an iPhone thermal/performance certification. Scheduler, persistence, cross-domain transaction coordinator and real industry state are not implemented yet.

Detailed record: `Docs/Updates/NXR-0002-2026-09-30-core-foundation-benchmark.md`
