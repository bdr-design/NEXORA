# R005 bitmap ownership micro — estimate before isolated preparation

PREPARED / NOT_RUN. Actual42runtime inputs remain observer source22e5428d.
H C5 overhead remains FAILED1.3822529614; no100-save campaign. The per-page
stamp study37565498376 was NOT_ADOPTED: H1M advance ratio1.24623 and extra9801
requested setup allocations. Its code/raw evidence are preserved unchanged.

Question: did thousands of boxed metadata entries erase the possible benefit of
avoiding mutable-array exclusivity? Test one UInt64 copy bitmap box per64pages,
not one per page. This is a different, bounded metadata hypothesis, not proof
that exclusivity caused the failed C ratio. There is no change to page payload,
root/leaf COW, frozen ownership, economics, scheduler, writer, WAL or cadence.

Allocation/time estimate before execution: H1M needs156 bitmap words/boxes
(62hot+62cold+31node+1group), S needs94. Allocate only during construction;
zero new begin/advance/service allocations expected. Removing UInt32/page
stamps reduces primitive metadata, but report the added constructor objects and
conservative64B/box allowance separately from actual requested setup bytes.
This cannot fix the full-image pool's210.77B/asset memory failure.

Unlike actual O(1) freeze, this temporary candidate clears those156words at
successful freeze; its cost is O(pageCount/64), measured in beginNS, not moved
out of the timer. No numeric timing promise. Rejected overlap/stale/foreign
begins cannot clear an active epoch's bits. Keep epoch monotonicity and every
precondition/check; first copy sets its bit, subsequent writes do not clone.
Relaxed atomic loads/stores are sole-simulation-owner metadata only; frozen
writer carries no bitmap. Existing release/acquire completion stays unchanged.

Use the same32case/96epoch Debug/Release/TSan S/H257/4096,12owner/cold lifecycle
and H100k/1M ABBA harness as the negative stamp study. Both arms retain identical
setup-allocation instrumentation and the explicit1M disposable test-size entry.
Require exact canonical snapshots/WAL/digests/transcripts, Release advance/service
zero and TSan null. Observe begin/reset, advance, copy, writer, full-loop and
requested setup costs; no favorable sample selection. The older per-page
preparer remains untouched so its evidence stays reproducible.

Study only. Green functional CI or this mixed ABBA ratio cannot qualify C100.
Any promising actual candidate still needs reviewed integration, fresh A/B and
Debug/Release/TSan S/H1M K1–K10 before actual C5/C100. No actual hot edit, main
merge, result files, Stage2–4/app/IPA or device acceptance from this preparation.
