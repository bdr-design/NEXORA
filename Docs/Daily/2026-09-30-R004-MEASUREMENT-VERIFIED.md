# R004 measurement review completed — causal diagnosis open

2026-09-30, Asia/Riyadh. bdr-design/NEXORA only.
Work branch: diagnostic/r004-batch-counters-20260930.
Baseline canonical HEAD rechecked: 5b5599895fa1bdbf00e951104e0cd55dc00f9a56.
Tested diagnostic HEAD: b7d3deb8a8599ac382b69e431addf22acd0f4e7f.
Tested tree: 08ed6b709bc271080ee98e56927db9cce0c00bbf (102 files).

Apple run 36692367500/job 109812298525: success, artifact 11086348930.
Artifact SHA-256: 34317f1a041179325ac93a0f9925634df3d1736c6ae4b3f68e5185f66369b9e4.
Exported source bytes and modes reconstructed the tested tree. All source gates,
Debug/Release/TSan 142/11 each, compiler boundaries, corruption probes, five iOS
library compiles and diagnostic transcripts passed. Three complete measurements
and independent raw reanalysis passed; 372,600 measured batch records retained.

The >5ms spikes are NOT fixed: 20k arrival max 32.748166 ms with enclosing thread
CPU 0.527500 ms; three other arrivals have CPU near wall time. See the full results,
raw-data scope, counter units, calibration and preserved local failures in
Docs/VALIDATION-R004-MEASUREMENT.md. Old sample 15 is not retroactively diagnosed.

This publication changes only validation, this daily entry and continuity.
No financial/trip logic, test, check, package, workflow or release-identity changes.
No merge into main, old excluded sources, cleanup, archive of excluded code,
R005 work or application build. Next step remains targeted causal diagnostics.
