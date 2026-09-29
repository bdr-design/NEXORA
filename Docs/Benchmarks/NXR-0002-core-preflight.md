# NXR-0002 Benchmark Evidence

## macOS CI
Run: `36638640053`
Status: PASS
Commit: `2012cfd45f5187ace7641d88d3c973763554f0a9`
Swift: 6.1.2
Target: arm64-apple-macosx15.0
Artifact ID: `11065373863`
Artifact SHA-256: `062d3c0aae0c8e52fd96b44f4b2e8ca644c7f3603f9998151f4320b3653c102c`

| Size | Deltas/tick | Compute p99 ms | Merge p99 ms | Commit p99 ms | End-to-end p99 ms | RSS before/after MiB |
|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 100 | 0.018 | 0.001 | 0.002 | 0.043 | 4.19 / 4.19 |
| 5,000 | 500 | 0.025 | 0.001 | 0.003 | 0.052 | 4.56 / 4.58 |
| 20,000 | 2,000 | 0.037 | 0.001 | 0.011 | 0.068 | 5.41 / 5.41 |
| 50,000 | 5,000 | 0.056 | 0.002 | 0.029 | 0.101 | 8.84 / 8.84 |
| 100,000 | 10,000 | 0.096 | 0.004 | 0.048 | 0.155 | 12.70 / 12.72 |

All figures are synthetic core preflight measurements with diagnostics enabled and 500 measured iterations after 20 warmup iterations. They are not iPhone certification or full-game scale proof.

## Local Linux verification
Swift 6.2.1, x86_64 Linux. Release tests and Thread Sanitizer tests both passed 8/8. Final 100k preflight with 5 workers: compute p99 0.195 ms; merge 0.009 ms; commit 0.084 ms; end-to-end 0.302 ms; RSS 15.99→16.14 MiB.

## Interpretation
The current narrow compute/merge/commit architecture does not show an early scaling collapse at 100k synthetic entities. This supports continuing core work, but not declaring the 100k gameplay objective achieved.
