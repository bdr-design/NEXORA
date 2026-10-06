# R005 legacy workflow routing incident — 2026-10-06

Commit `611a14efca6bb571887d4f5dc5189d51621b212d` only saved the fresh
Stage B evidence and used `[r005-evidence-only]`. The existing full executable
workflow did not exclude that marker, so GitHub unexpectedly started run
`37505451077` on that source (tree
`5b18f5f7590ba421be04905ac59839109c79eca7`). This was not a planned C
performance candidate or a new C fix. Commit
`389f5a9488a75081e3b4496449a0bb3e71a22c69` added the exclusion to
both legacy workflows; a subsequent evidence-only checkpoint had its heavy
jobs SKIPPED. The already-running job used its original workflow snapshot.

Run `37505451077`, job `112412833492`, finished **FAILED**. A selected S at
H/S `0.9261958004278472`. The selected smoke, TSan, B 60 daily records,
and Stage C K1–K10 in Debug/Release/TSan passed before the failing C
measurement step. The exact error was `mismatch: stage C save did not commit
within 2000 advance calls`. The command stopped before writing
`STAGE005-C.json`: no 100-save timing, p99, or overheadRatio is available from
this run. It must not be reclassified as C PASS or as another numeric overhead
miss. The original run `36875130222` remains a separate FAILED overhead case.

Artifact `11434785670` was downloaded, hashed at SHA-256
`74448035313bd58003158f72570adf213d8f3b1adfc8bff58652587f71e6556a`,
and its commit/tree, A/B/K raw JSON and C stderr verified. Selected raw files
and their digests are under `Experiments/R005Swift/Evidence/20261006/37505451077-*`.
The failure is appended to `Experiments/R005Swift/failures.json`. C remains open
on S and H; the later WAL-continuation functional run is a separate source
and cannot supply a timing result for this failed job.
