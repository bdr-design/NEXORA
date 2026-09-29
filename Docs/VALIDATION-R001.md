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
