# NXR-0003 Benchmark Evidence

CI run: `36641949755`
Implementation commit: `1b0bfe7ce49f70a11d5ccb5c6aba731352902b43`
Implementation tree: `7e0ad5d3524e09f08908b8669c31d8fd1217c381`
Artifact: `11066353467`
Artifact digest: `sha256:b88aa31bf39ee2268d7fae79fe6dea34fd8065d4512abf8b7ca480a39a07c1d2`

## Gates
- Release tests with warnings-as-errors: 14/14 PASS.
- Thread Sanitizer: 14/14 PASS.
- iOS Release compile: PASS.
- 100k raw benchmark: PASS.

## 100k result
Stored entities: 100,000
Selected/deltas per tick: 10,000
Measured iterations: 500

- gather p50/p95/p99/max: 0.068 / 0.205 / 0.291 / 0.772 ms
- compute p50/p95/p99/max: 0.037 / 0.089 / 0.129 / 0.267 ms
- merge p50/p95/p99/max: 0.004 / 0.013 / 0.022 / 0.060 ms
- commit p50/p95/p99/max: 0.043 / 0.141 / 0.234 / 0.394 ms
- end-to-end p50/p95/p99/max: 0.194 / 0.478 / 0.661 / 0.930 ms
- RSS before/after: 14.91 / 14.91 MiB

These are CI/macOS synthetic-core figures, not iPhone runtime certification and not full-game scale proof.
