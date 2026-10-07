# R005 concurrent writer-packet study — estimate before execution

PREPARED / NOT_RUN. Actual42 runtime inputs remain the fully qualified observer
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
