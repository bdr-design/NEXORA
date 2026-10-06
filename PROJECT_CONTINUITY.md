# Repository continuation — 2026-10-06 / Asia-Riyadh

Owner «استخدم المستودع» resumes repository/Apple CI work. Base 37c0203; AGENTS and
live continuity read, five C blobs verified against live tree before modification.
First writer candidate 5fd2a7e8813814269a33a4b55cc3c3343d083d79, tree
574e5d6010e64837cd33cbf8cea8e3d914e8bc06, run 37473200899 SUCCESS diagnostics;
artifact 11418475143 ZIP SHA-256
c67f64790a653348565f84d1538763606d686831d7b5810148697dbbedb1ec2c.
Exact-file/malformed-record checks Debug/Release/TSan, S/H 100k Debug/Release,
S 100k TSan and real K3 1M Debug/Release PASS. No full K1-K10 rerun.
S 5-save ratio=2.125063528589722 FAIL; begin=10959 ns PASS; advance=1027750 ns /
750 samples PASS; paired violations=0, idle alloc=0. C remains OPEN.

Only one remaining bounded candidate: detach and explicitly assign utility writer
QoS, record actual qos_class_self diagnostic. Copy hooks/producer records, all
thresholds/calculation/cadence/service fixed. No pool/background QoS/artificial delay.
Details/estimates in Docs/Daily/2026-10-06-R005-REPO-WRITER.md. Attempts 1 of 2;
if the blocker remains, stop and give measured alternatives. No full 100-save run
unless every micro timing/allocation gate supports it. S proof never accepts H.
A/B revalidated, not freshly measured. No production change/main merge/IPA.
Read live HEAD before any next write; all earlier failures retained below/in registry.

---

# NEXORA — current checkpoint / نقطة الاستئناف

Updated 2026-10-05. Only bdr-design/NEXORA, diagnostic/r005-design-1m-20260930.
Read AGENTS.md then recheck live HEAD before edits. Main unchanged:
38ce39cf9322f47e4def5f6eddb425c5a66ea7f9. All denied branches remain forbidden.

C is OPEN on S and H. Original 36875130222 stays FAILED, ratio 1.516250337 >1.10.
A/B evidence from fa9c446/run36875130222 revalidated against unchanged inputs;
not newly measured. Gate fixes reject unhealthy A and pair C allocations per advance.

Owner «حله!» authorized bounded profiling/fix. Phase run 37313101995 completed;
copy/write candidate 37315706838 had S ratio 1.887304621, p99 1172542 ns and zero
saving allocations, with ~98 MB S physical scratch cost. Priority run 37316669619
FAILED on ec695084cba1aa63a563602549c2a96f80418cc9 / tree
569a5c6bb43794ae9964155882fd37fe33acb397: save did not commit within 2000 advances.
H failed at the cadence. S completed 5 saves: ratio 1.309202510965811,
advance p99 1267959 ns /1629 samples; both miss. Artifact 11348271339 ZIP SHA-256
4978fd9a2040e2af497a2d3c1276d00275d169b30b8baeb84635dbf11645f53d.
No complete H timing result exists; empty stdout retained. Initial log-only S
attribution corrected after exact ZIP recovery; do not repeat the old claim.

Both bounded candidates failed; STOP performance retries at owner limit.
No new 100-save campaign. Four C files restored verbatim from allowed 3b3711de
(tree 6c04893b16c17492e2b7d74a9dc4a57751f2468b); pooling/batching/background QoS
removed from live path. SHA/K3 regressions, fixed gates and source guards retained.
Rollback/recovery CI 37317983436 SUCCESS on 0b2d2b9be023c74bddc7055618aec8c9ec8e74a9,
tree 16b92b8d642578655c60a22b7b790f7146eeb0f2. Artifact 11348731266 ZIP SHA-256
837e044786e2c4551a47785b7949074a69f6ba3a0cbda3caa95e4ec574400beb. Four restored
files verified exactly; guards/A-B reuse passed. Metadata-only, no fresh timing.
Next: owner chooses broader ownership redesign or fixed-Mac diagnosis.
See Docs/Daily/2026-10-05-R005-FIX-OUTCOME.md for 3 options and costs.
Do not produce closure files until genuine C PASS names S or H. All thresholds
unchanged. B torn-tail resume-write finding still needs resolution before production.
No production change, main merge, IPA or iPhone acceptance.

Raw data/failures: Experiments/R005Swift/review-20261005.json and failures.json.
Daily execution has full identities/estimates. Previous continuity retained verbatim:
Docs/History/2026-10-05-R005-CONTINUITY-HISTORY.md, SHA-256
0f4611589718941d2e4594226a4aa06d29fdbf6e7e7c465e25c48cb79ad1db56.
Short checkpoint reduces resume overhead; app disconnect cause remains unverified.
