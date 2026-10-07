# R005 bitmap ownership micro — estimate before isolated preparation

COMPLETED / NOT_ADOPTED. Actual42runtime inputs remain observer source22e5428d.
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

Run37570450804 SUCCESS on546d185f/tree72595926, artifact11460244153,
ZIP SHA256bbbe14a58364dc2b8cf1c1392e5703038fabff906c3794f700d093598da81c90
independently verified by reconstructing both temporary arms:32cases/96epochs/
12lifecycle, Release advance/service zero and TSan null. Actual42inputs unchanged.

| H fixture | Base median advance | Bitmap median advance | Bitmap/base advance | Full-loop ratio |
| --- | ---: | ---: | ---: | ---: |
| 100k | 38.012563ms | 31.968209ms | 0.840991 | 0.847819 |
| 1M | 611.818415ms | 665.103311ms | 1.087093 | 1.039285 |

At1M begin median9.375→8.417us, bitmap observed max16.625us across6small
begin samples; these are not C100p99. Copy median ratio0.722662 improves while
advance does not. Setup requested allocations add158; requested bytes decrease
34140 and conservative owned allowance decreases28720B to210743600B. Still
above200B/asset before excluded overhead. Samples overlap/limited; no precise
causal regression is asserted. Decision NOT_ADOPTED: no credible1M simulation
win. The100k gain cannot substitute for the owner's1M target. No hot integration,
new A/B/K/C campaign, memory/device acceptance or threshold change follows.
