# R005 page-stamp ownership micro — estimate before isolated edits

COMPLETED / NOT_ADOPTED. Actual42 runtime inputs remain the verified observer source.
Current full qualification37563538884 on22e5428d/treee5fbde7e retains its sole
prospectively selected A; all failures and C<=1.10 unchanged. H paired37564011879
is a separate same-fixture component probe. No actual hot-source mutation here.

The advisory sample after failed37560851575 shows swift_beginAccess/exclusivity
under scheduler insertion and advancement. Sampling cannot establish a precise
cause or replace failed timing. Current EpochBuffer uses a mutable class-owned
ContiguousArray<UInt32> for page epochs; saving reads it on every mutation, idle
short-circuits that read. The proposed isolated experiment replaces only this
metadata with a let array of private non-Sendable page boxes, each containing a
let Atomic<UInt32>. Relaxed loads/stores run on the sole simulation owner; frozen
writer values carry no stamps or mutable owner. COW guards and mandatory runtime
checks remain enabled. No per-asset actors/tasks/locks, no unsafe, no new model.

Allocation/time estimate BEFORE preparation: one small object per page, not per
asset, allocated during world construction; zero new begin/advance/service
allocations expected. H1M has9799 stamps, S1M5892 for fixture E=N/G=ceil(N/16).
Reserve64B per box plus array references in diagnostic ownedBytes, explicitly a
conservative budget allowance rather than measured physical layout. Additional
requested setup allocations/bytes are measured independently in both arms;
scoped Release controls/zero requirements stay. Memory full-image pool still
exceeds200B/asset; this experiment does not fix it. No numeric speed promised.

Disposable base/stamp packages use current Package/Sources only. Both add the
same setup-allocation telemetry to the existing bounded harness. The stamp arm
changes EpochPages only; economics, API, scheduler, v2 writer, WAL, page sizes,
copy bytes and clocks/cadence stay fixed. Debug/Release/TSan S/H257 and4096 exact
canonical/WAL cases, six owner/cold lifecycle proofs per arm, then Release H100k
and H1M ABBA on one Apple host. All scripts/outputs/frozen/recovered digests,
positive controls and zero advance/service must agree. Overlapping samples or
ratios of this mixed harness do not qualify C100 or whole-game smoothness.

A promising result still needs an actual reviewed source candidate, bounded
integration and fresh A/B/TSan/S/H1M K1–K10 before real C5/C100. No source proof
is reused across changed inputs; no main/result files/app/IPA/device acceptance.

Primary API reference checked before Apple execution: Swift SE-0410, implemented
Swift6, https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md .
The diagnostic uses standard Synchronization Atomic.load/store with explicit
relaxed ordering for sole-thread stamps only. These stamps do not synchronize
ordinary payload writes; existing release/acquire writer-completion fences and
immutable value ownership remain the synchronization proof. Performance effect
of avoiding metadata access checks is a hypothesis to be measured, not a promise.
No proposal implementation code was copied; calls follow the existing repo API.

Original37564899240 FAILED before invoking Swift: macOS Bash with nounset
rejects expansion of the empty sanitizer array. Artifact11458437798 ZIP
SHA25619c9410e26e9ca5184a042c1ea238c1521552cf26e7a67a0242e55e6e93814b9
verified source/42inputs/temporary diff/guards/error. No build/matrix/ABBA
result exists. Explicit shell branches now preserve all same strict flags,
without an empty array. Original failure retained; actual runtime unchanged.

Before corrected execution, local review found the existing bounded diagnostic
command accepts up to100k. Only the disposable harness adds explicit1M to its
finite test-size list in BOTH arms; actual public command/owner limits and all
acceptance gates unchanged. This enables the owner's required1M study rather
than substituting a small smoke. Source differences remain setup harness only
in base, setup harness+EpochPages in stamp. No new simulation model.

Corrected37565498376 SUCCESS on91544240/tree29ee5f98, artifact11458713104,
ZIP SHA25642e9b16257da0d0fc288e134cd0fcf3f1ee36d04e80d65e53a864e41df632937.
Independent verifier reconstructs both disposable source transformations and
checks exact actual42inputs, all6builds,32canonical cases/96epochs,12lifecycle,
Release scoped zero and TSan null. No actual runtime source changed.

| H fixture | Base median advance | Stamp median advance | Stamp/base | Full-loop ratio | Additional requested setup bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100k | 30.261537ms | 32.494957ms | 1.073804 | 1.065345 | 23504B |
| 1M | 446.072699ms | 555.910497ms | 1.246233 | 1.227143 | 235240B |

At1M stamps add median9801 requested setup allocations (constructor's9799
boxes plus array/setup effects); declared owned allowance adds666688B, from
210772320 to211439008B. Observed requested allocation bytes differ from the
conservative64B/box budget, which is not phys_footprint. Writer median improved
in this held mixed harness (ratio0.845405) while simulation became slower; this
is not a contention diagnosis or C result. Samples overlap and are limited.
Decision: NOT_ADOPTED. No credible1M simulation gain and extra memory/setup work
violates the purpose of this candidate. Preserve its raw evidence and the first
shell FAILED run. Do not copy its metadata into the actual hot owner.
