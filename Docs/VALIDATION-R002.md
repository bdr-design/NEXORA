# Verified Apple gate — NXR-R002

Date: 2026-09-30. This supersedes submission-time APPLE_GATES_PENDING notes.
Scope: executable aircraft lifecycle store; NOT full gameplay or production/device certification.

Tested commit: 4583de236d5aa25b06bbd3ed4a2492e8cb629835.
Tested tree: 499ea18d3a9057f8329dce8346eb555efa697bb1.
CI run: 36653271004. Job: 109691995765. Conclusion: success.
Apple Swift 6.1.2, arm64-apple-macosx15.0, Xcode 16.4 (16F6).

The artifact was downloaded and read, not inferred from a green label:
- debug.txt: 51 named tests PASS, 3.243 seconds in its test summary.
- release.txt: 51 named tests PASS, 1.241 seconds.
- tsan.txt: 51 named tests PASS, 6.758 seconds; no TSan error reported.
- Original three and new eight required compiler rejections PASS; valid clients compile.
- Missing-row and occupied-slot corruption probes stopped with the invariant marker
  in both Debug and Release (four processes, exit -5 on this Mac).
- NexoraIdentity, NexoraObservability, NexoraAviation iOS Release compilation succeeded.
- Five lifecycle scales, 3 warmups and 30 raw samples each, passed.

Artifact: 11070708521, nexora-r002-evidence.
Downloaded file name: NEXORA_R002_Apple_Evidence.zip.
Downloaded archive SHA-256 was independently recalculated and matched GitHub:
e1dfbb9c11d04421561d14dbb579a9699f7ba33b8bcf3cac69e8c7a868730509
source-commit.txt and source-tree.txt exactly matched the tested identities above.

## Apple raw phase medians, milliseconds for ALL indicated records

| Records | Initialize | Create | Start | Complete | Read | Retire | Deep audit |
|---|---:|---:|---:|---:|---:|---:|---:|
| 20,000 | 0.072396 | 0.553458 | 0.750583 | 0.758437 | 0.296604 | 0.754417 | 0.067125 |
| 100,000 | 0.591792 | 2.836416 | 3.799583 | 3.784187 | 1.482708 | 3.850687 | 0.348292 |

Independent phase medians must not be added and called an end-to-end percentile.
No R001 aircraft-store baseline exists for a speedup claim. These samples exclude
financial operations, real routes, storage, UI/map and device energy/heat. They
are not p99, RAM footprint, zero-allocation, FPS or 20k full-gameplay certification.

All original local limitations and harness corrections remain recorded in
Docs/Updates/NXR-R002.md. Successful Apple TSan is a separate verified run; it
does not turn the earlier local SwiftPM timeout into a passed command.
Subsequent evidence-only documentation commits do not change the tested Sources,
Tests, Checks or Package.swift. Verify subtree identities before relying on that.
