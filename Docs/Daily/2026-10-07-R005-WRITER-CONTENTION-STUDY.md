# R005 concurrent writer-packet study — estimate before execution

COMPLETED / NOT_ADOPTED. Actual42 runtime inputs remain the fully qualified observer
source. Qualified H1M five-save37567830698 FAILED overhead1.3822529614>1.10;
beginp9942042ns and advancep991009583ns pass, zero/paired/queue gates pass.
Artifact11459687324 ZIP SHA256
73a2d95dcbab056dd053924587457a39b83f66680039b48c839a20ae8d747374
independently verified. Removing every measured copy NS gives only an optimistic
theoretical1.2740145515, not a measured alternative or acceptance. No C100.

Earlier packet study37557593873 measured a modest overlapping8% writer median
change at100k with held writer; it did not measure simulation/IO contention at1M.
This new study answers that missing question on the current observer source,
without editing actual runtime or trying another official timing run.

Ownership/call path: existing single simulation owner retains only live pages;
one background writer takes frozen values through the existing one-save handoff.
Only disposable packet EpochSnapshot groups body/checksum into one scratch write
in normal operation. Canonical order/hash/count/footer, WAL, durability, error
propagation, root lifetime and completion release/acquire remain identical. K3
still writes the original half-body prefix before the kill hook. No scheduler,
record formats, hot page sizes, economic logic, QoS or clock/cadence change.

Pre-execution allocation/time estimate: existing32KiB writer scratch is reused,
the appended32-byte checksum fits every existing record; no new simulation,
begin or service allocation expected. Writer environment capture is once per
save and previously showed roughly45KB extra requested allocation, so all writer
counts/bytes must remain visible. It is not a memory improvement; the full spare
image still210772320B/1M and NOT_FIXED. Up to two normal write calls per record
are removed, but prior8% writer-only observation cannot predict the1M simulation
effect. No numeric speed gain or C eligibility is promised.

Plan: both arms Debug/Release/TSan S/H4096 exact canonical3epochs/zero scopes,
all12small owner/cold lifecycle cases and12limited K3 at1M with raw boot/recovery
retention. Retain100k held ABBA as a secondary observation. Reuse the existing
H paired harness in both arms: Release4096 and1M outer base/packet/packet/base,
each with identical fixture and internal save/no-save orders. Independently
verify transcripts/output/final/recovered digests, allocator positive controls,
advance/service zero, separate advance/service/WAL/writer/full-loop timings and
post-profile owned capacities. Writer and simulation overlap; never add their
wall times or use the paired ratio as official C. All checks remain enabled.

Decision rule: no adoption from green CI or a lower writer median alone. A
simulation regression or inconsistent matched evidence rejects adoption. Any
promising actual-source candidate needs bounded integration then fresh source-
bound qualification before real C5/C100. S/H C OPEN; no main/results, Stage2–4,
app/IPA or iPhone smoothness acceptance. All old failures remain immutable facts.

Run37568520463 SUCCESS on49dcf47e/treeac9e37db, artifact11460367509,
ZIP SHA25607a5707b9545060f5ceb8f45858df6e0e7117405c08515922901410e44a4df80
independently verified. Exact3/4temporary source changes reconstructed, actual42
unchanged,16canonical cases/48epochs,12owner/cold lifecycles and12limited K3
source-bound SIGKILL assertions with raw bootstrap/recovery equality PASS.
Release advance/service zero; TSan observations null. H profiles8outer cases
(4096/1M×ABBA), with4matched pairs/arm at1M, exact984calls/1M events and recovery.

| H1M matched observation | Base | Packet |
| --- | ---: | ---: |
| Median writer run | 209.684771ms | 169.696334ms |
| Median all-call save minus own-control advance | +19.837637ms | +49.538309ms |
| Median full-loop save minus own-control | −21.073855ms | +38.124979ms |
| Median save-active matched ratio (diagnostic only) | 1.139260 | 1.399770 |
| Median requested writer bytes | 1505914B | 1551225B |

Writer median ratio0.80929 improves while the measured matched simulation delta
increases. Controls also vary across arms, so this does not establish a precise
causal regression, and save-active intervals differ with asynchronous finish.
All-call deltas use the same full transcript to avoid interval selection. Held
H100k writer median33.922479→27.721855ms is secondary, not a contention win.
Extra requested writer bytes45311 remain disclosed; main-world owned210772320B
unchanged. Decision NOT_ADOPTED: no credible1M simulation gain. Keep actual
writer, full C5 failure and all source proof. No C100/memory/game/device acceptance.
