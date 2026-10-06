# NEXORA — current checkpoint / 2026-10-06

Owner «كملها كلها الان بدقه عاليه جدًا» resumes bounded engineering after the
two failed C writer candidates; the earlier STOP and all failures remain history.
Live source rechecked at f4f8e167feebb9c0908281f8720a5a3235e520bf, tree
e7c1b69da2974974fb076a7dee38e360b09f8b5a. Stage B torn-manifest
recover→append→recover repair passed Apple Debug/Release/TSan SIGKILL proof:
run37503555309 SUCCESS, artifact11430977253 SHA256
32618114c48dec880bda4dd70e9daeb282aa508dcd664ff6c4d0856c7ee014ef.
Five old kill points, eight new continuation cases, and three fail-closed cases
passed; this is not a physical power-cut test. Fresh complete 30-day/60-record
B and G16/W7, G1/W7, G1/W3 quota measurement on the repaired source passed:
run37504841364 SUCCESS, artifact11431716398 ZIP SHA256
0981a0dc3526aae985786aa1dc890fa7732c62ec941c4cbda8d5b1d8a293bf26.
Quotas with pinned 95,801,772-byte snapshot:320MiB PASS,1408MiB REJECT,
832MiB PASS respectively; all final disk verifications exact. See
Docs/Daily/2026-10-06-R005-B-RECOVERY.md and proof metadata under
Experiments/R005Swift/Evidence/20261006/. C remains OPEN on S/H with unchanged
1.10 gate and no new performance result. Current repo has no iOS app/IPA project;
Stage2–4 production/gameplay/device work follows genuine layout-specific C proof.

Only bdr-design/NEXORA; branch diagnostic/r005-design-1m-20260930.
Read AGENTS.md and recheck live HEAD before editing. All denied branches remain forbidden.
Main unchanged: 38ce39cf9322f47e4def5f6eddb425c5a66ea7f9.
Owner «استخدم المستودع» resumed repository/Apple CI from allowed 37c0203.

C is OPEN on S and H. Original run 36875130222 stays FAILED; S 1M/100 saves
ratio1.516250337>1.10. A chose S; original B and K1-K10/TSan evidence retained.
Unchanged A/B inputs revalidated in new CI; not freshly measured.
A health rejection, per-advance C allocation pairing and always-after CI guard repaired.

Bounded repository attempts STOP at 2/2; no further timing retries.
1) 5fd2a7e8813814269a33a4b55cc3c3343d083d79 / tree
574e5d6010e64837cd33cbf8cea8e3d914e8bc06 / run37473200899 SUCCESS diagnostics.
Artifact11418475143 SHA256 c67f64790a653348565f84d1538763606d686831d7b5810148697dbbedb1ec2c.
S 5-save ratio2.125063528589722 FAIL; begin10959ns; advance1027750ns/750.
2) f85808c12f89a56566da5494ba98c0bb71de0ffc / tree
f6bb5085bf336f6fdb38d81ab02a589f3f950a59 / run37475368651 SUCCESS diagnostics.
Artifact11418154134 SHA256 a12c29b668702410b877a9964491f798b115c15d95e76607283d2db1dc169796.
S 5-save ratio1.557025666617678 FAIL; begin81083ns; advance1099084ns/617
(margin916ns); paired violations0; idle allocations0; actual writer QoS utility.
Both candidates passed exact v2/malformed-record Debug/Release/TSan, S/H100k
Debug/Release, S100k TSan and K3 1M Debug/Release. Not full K1-K10 or C proof.

Four C runtime files restored byte-for-byte to allowed 37c0203: Snapshot,
Stage005CSave, Stage005CRunner, Stage005CHybridRunner. Unproved metadata/batching
and detached-QoS changes removed; exact-file/known-SHA/K3 regressions retained.
Rollback functional CI37476738141 SUCCESS on a16a4befd610a3d6d4157a29ac3fbe165f1ced60,
treeacbb938c94fdea67e78b4e8fb254433a6d2ad744; artifact11419118234 SHA256
e975025ad4148013ece4a2fcfdef7c70ead4a60ae2f65b3ce09b650df9a67cd3.
Debug/Release/TSan, S/H100k and exact four-file equality PASS. No timing retry.
No thresholds/formula/cadence/workload change, production/main merge or IPA.
No closure STAGE-R005-RESULTS.md/results.json until true 1M/100-save C PASS names layout.
Next: C needs a fixed-runner paired profile and broader snapshot ownership plus
writer-contention redesign. A new A selection and B source-bound proof precede
any C 100-save campaign after changing hot state; prior copy-only and writer
candidates cannot meet the original 1.10 gate. Keep old STOP as history.
Requirements now match 1M/capacity2M and iPhone17ProMax100k→250k→1M;
full-feature gameplay is still required. B torn-tail and full retention have
source-bound proof, while Stage2–4 and physical iPhone acceptance remain
unimplemented.

Reports: Docs/Daily/2026-10-06-R005-OUTCOME.md and 2026-10-06-R005-REPO-WRITER.md.
Raw evidence/all failures: Experiments/R005Swift/review-20261005.json and failures.json.
Original continuity retained verbatim: Docs/History/2026-10-05-R005-CONTINUITY-HISTORY.md,
SHA256 0f4611589718941d2e4594226a4aa06d29fdbf6e7e7c465e25c48cb79ad1db56.
Short checkpoint helps resume; chat disconnect root cause unverified.
