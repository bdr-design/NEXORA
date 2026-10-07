# R005 — sealed-WAL bounded diagnostic

Status: `VERIFIED_WORKFLOW_SUCCESS` / `SEALED_WAL_MICRO_PARTIAL_BLOCKED` /
`NO_GO_INTEGRATION_C100`.  2026-10-07.

This report records one disposable protocol diagnostic.  It is not a Stage A,
B, K, H1M, C5, C100, durability, application, IPA, or device result.  It does
not reclassify either historical C failure, relax `overheadRatio <= 1.10`, or
authorize a runtime hot-path change.

## Exact identity

- repository: `bdr-design/NEXORA`
- branch: `diagnostic/r005-design-1m-20260930`
- source: `44e47245c09b33b89d9c246bfe7940ab45d57a73`
- tree: `04379368ac2b803fbe04f948816dbe6291d74ecd`
- workflow run: `37619163175` (`SUCCESS`)
- artifact: `11481530720` (`r005-sealed-wal-micro`)
- artifact ZIP SHA256:
  `1044c90f28a2e620056d72fac4a14974f196a50659be4fe6045d0316c8f9bf4b`
- micro source SHA256:
  `66f35a8234d197f793d4558309f1bd8f3e392432957b3e3acd9f857264f04811`
- Apple toolchain: Swift 6.1.2, Xcode 16.4, arm64 macOS 15 runner

The verified archive and derived proof are retained as
`37619163175-r005-sealed-wal-micro.zip` and
`37619163175-SEALED-WAL-PROOF.json` under the same evidence date directory.

All eleven unrelated workflows for the commit completed as `skipped`.  The
marked sealed-WAL workflow alone executed.  The actual 24 runtime source files
and 42 pinned proof inputs remained byte-identical before and after the
disposable copy.  `main` remained
`38ce39cf9322f47e4def5f6eddb425c5a66ea7f9`.

## What executed successfully

Debug, Release, and Thread Sanitizer builds used Swift 6,
`-DSEALED_WAL_MICRO`, warnings-as-errors, and C warnings-as-errors.  All three
bounded runs exited zero with empty stderr.  The verifier independently opened
the artifact, checked its raw manifest and hashes, rejected any
`acceptance=true`, and reproduced the declared partial/no-go decision.

The scalar/root fixture established only the following bounded facts:

- 20 corruption cases failed closed, including whole-frame loss, torn frame and
  seal, exact seal stripping, append after seal, store splice, parent/base/
  version/root mismatches, missing successor directory entry, forks, ordering,
  duplicate/future segments, and manifest inconsistencies;
- the clean deletion of the latest manifest and all visible descendants was
  reproduced as `EXPECTED_KNOWN_GAP`, not relabeled as success;
- all 11 modeled publication crash boundaries recovered only the exact old tip,
  the exact new tip, or an explicitly allowed fail-closed outcome, comparing
  root, value, durable LSN, and generation;
- every modeled pre-publication I/O branch invalidated the live writer handle;
- recover→append→seal→recover was exact;
- streamed recovery ran at 0, 1, 5, 10, and 25 segments;
- GC failure after a durable manifest returned `COMMITTED_GC_PENDING` and kept
  the committed tip; the compactor check remained explicitly non-atomic.

This is process-bound fault injection around real fsync/rename/dirsync calls,
not physical power-loss certification.  EIO/ENOSPC/short-write cases are modeled
branches, not syscall-level fault injection.

## Performance observation, not C

The paired ABBA fixture contains only 32 scalar calls and four saves in each
save leg.  It is intentionally classified
`BOUNDED_SYNTHETIC_DIAGNOSTIC_NOT_C`.

| mode | no-save median | save median | diagnostic ratio | recovery at 25 segments |
|---|---:|---:|---:|---:|
| Debug | 6,472,750ns | 16,544,417ns | 2.55601050558109 | 8,387,416ns |
| Release | 227,292ns | 29,600,000ns | 130.22895658448164 | 2,375,541ns |
| TSan | 9,245,666ns | 24,846,792ns | 2.6873988309765893 | 27,909,667ns |

The large Release ratio is adverse diagnostic evidence dominated by durable
publication in a tiny baseline; it is neither the Stage C formula nor a valid
1M/100-save measurement.  It gives no permission to run C100.

## Remaining hard blockers

- no separately durable CURRENT/high-watermark authority;
- no stable request ID or idempotent commit-status query;
- no syscall-level fault injector or physical power-loss campaign;
- no fixed metadata pools; directory/manifests/GC metadata remain dynamic;
- allocation observation, physical footprint, logical-versus-allocated disk,
  and write amplification are `NOT_MEASURED`;
- no atomic CAS, compaction payload, compaction publication, backpressure, or
  writer/compactor overlap proof; backpressure and overlap are explicitly
  `NOT_IMPLEMENTED_OR_MEASURED`;
- no bounded production recovery SLA for the source-shaped transcript, which
  can require up to 204.8M completion units plus 204M reschedule insertions in
  the exact-200k projection;
- no cross-process owner lock, authentication, full S/H state, Stage A, Stage C,
  application smoothness, or iPhone proof.

Therefore the only valid decision is to keep integration and C100 stopped.  A
future candidate must close authority/idempotency/compaction/backpressure first,
then re-enter the required A, source-bound B, TSan, K1–K10, and layout-specific
C gates without weakening any threshold.
