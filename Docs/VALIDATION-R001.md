# Validation ledger — NXR-R001

## Local evidence available before remote submission

Environment: Swift 6.2.1, x86_64 Linux.
- Debug: 19 named tests / 2 suites passed.
- Release with warnings-as-errors: 19 named tests / 2 suites passed.
- TSan: 19 named tests / 2 suites passed after the initializer correction.
- Three negative compiler contracts rejected as required.
- Positive external API client compiled.
- Identity lifecycle fixture: 1k / 5k / 20k / 50k / 100k; 3 warmups and 30 samples.

Parameterized tests expand to 28 cases; they are not 28 separate named tests.

## Remote gates

The restart workflow must pass Debug, Release, negative compiler contracts,
TSan, both iOS library compile checks, and the raw identity fixture. Its artifact
contains commands/logs, raw samples, toolchain and exact source commit.
Record the actual run ID and result after verification; never infer success from
submission or an artifact name.

## Not established

No actual iPhone execution, IPA, UI/Metal frame rate, energy/thermal soak, memory
footprint metric, zero-allocation proof, scheduler, storage, financial correctness
or full-feature asset scale result. The new foundation has no gameplay values.
The retired project's benchmark numbers do not apply to this tree.

## Verified Apple CI evidence

Run: `36646039605` (success), job `109669103488`.
Tested implementation commit: `c45d24e0445219fc0db4df5efd0e920b5e129c16`.
Tested tree: `3b3f8aee3e966dac3a330ff2f85b6ec4e2ebc910`.
Apple Swift 6.1.2, arm64 macOS 15; Xcode 16.4 (16F6).

- Debug: 19 named tests PASS.
- Release: 19 named tests PASS.
- TSan: 19 named tests PASS; no sanitizer error reported.
- Compiler gates: 3 required rejections PASS; valid client compiled.
- NexoraIdentity iOS Release compile: BUILD SUCCEEDED.
- NexoraObservability iOS Release compile: BUILD SUCCEEDED.
- Identity smoke: all five scales, 30 raw samples each, PASS.

Artifact ID: `11068189510`, `nexora-r001-evidence`.
Downloaded artifact SHA-256 (verified against GitHub digest):
`d801954fec29799915363762163eff1e9f3fc7eff94c8a783b21ebdd981f7a96`.
The artifact's source-commit.txt and source-tree.txt matched the above exactly.
The locally tested and remotely submitted 24-file trees matched exactly by Git
object identity before the later evidence-only documentation update.

This passes the initial scaffold gate only. It is not production authorization,
proof of absence of all defects, or a completion claim for other subsystems.
