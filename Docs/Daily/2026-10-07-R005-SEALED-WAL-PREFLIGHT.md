# R005 — sealed-WAL checkpoint preflight

Status: `CONDITIONAL_GO_ISOLATED_DISK_MICRO_ONLY` / `NO_GO_INTEGRATION_C100`.
2026-10-07.

This is a source-bound design preflight only.  It does not change the 24 Swift
runtime sources or 42 proof inputs, does not run H1M/C5/C100, does not reclassify
either historical C failure, and does not claim a durable checkpoint.  The
denied branches and the external game's implementation were not opened or used.

## Why the current WAL is not a checkpoint seal

`StageCWAL` writes a 16-byte generic header and restarts its sequence at one for
each file.  The header does not bind the file to a base snapshot, prior segment,
global sequence/watermark, store/schema/engine version, or expected final byte
length and frame count.  `close()` closes without `synchronize()`.  Replay loads
the whole file with `Data(contentsOf:)`, trusts a contiguous filename sequence,
and accepts every complete valid prefix.  Therefore deletion at a frame boundary
can look like a valid shorter WAL: there is no seal proving that an acknowledged
terminal frame existed.

The current snapshot commit marker does not solve that problem.  A WAL-only
checkpoint needs an authoritative manifest and immutable segment seal; otherwise
renaming a segment or counting `close()` as a save would weaken durability and
would change C's meaning merely to obtain a better ratio.

## Source arithmetic at H1M

For `N` assets, `E` event nodes, `g=ceil(N/16)` groups, and H record count
`R=1+ceil(N/256)+ceil(E/512)+ceil(g/2048)`, the current canonical H snapshot is:

`S_H = 18,908 + 68N + 32E + 8g + 48R`.

For S the corresponding source formula is:

`S_S = 18,908 + 65N + 30E + 8g + 48R`.

At `N=E=1,000,000`, H is exactly `100,801,772B` and S is
`95,801,772B`.  For `A` advance frames,
`r` reschedule frames, and `K` save rollovers (one initial WAL plus `K`
successors), the raw WAL chain is:

`W_raw(A,r,K) = 72A + 64r + 16(K+1)`, with
`r <= floor(1024A / 1,000,000)` for this fixture.

At the exact `A=200,000`, `K=100` scenario, `r<=204`, so `W_raw` is
`14,401,616...14,414,672B` before seals and the manifest.  This comprises 101
WAL files: 100 closed ancestors plus the newly opened active successor header;
it does not claim that save 100 has committed at that instant.  H base plus the
chain is therefore `115,203,388...115,216,444B`, while S plus the chain is
`110,203,388...110,216,444B`, on disk.  There is no
source-proved final-`A` upper bound: after save 100 starts at call 200,000,
`savesStarted < requestedSaves` becomes false, so the runner no longer applies
the 2,000-call in-flight check while its outer loop continues until that save
commits.  Thus the exact scenario is not an upper bound.  These are disk
figures, not owned memory or recovery latency.

Copying the current restore path into a concurrent compactor is disallowed.  A
live H world (`105,408,880B`) plus a second builder H world and one full snapshot
buffer is already at least `311,619,532B`.  Even builder plus full snapshot,
without the live world, is `206,210,652B`.  In the proposed retained-generation
design at exactly 200,000 advances, keeping old and new snapshots plus the raw
chain (including the active header) has a minimum disk peak of
`216,005,160...216,018,216B` for H and `206,005,160...206,018,216B` for S.
These are projection figures, not the current finalize behavior, which removes
prior snapshots.  The actual runner peak is not source-bounded after the final
save starts.  This excludes seals, the manifest, temporary files, additional
retained generations, and filesystem overhead.

A genuinely disk-native plan is arithmetically different: current live H plus a
proposed fixed 4MiB pool is `109,603,184B`, leaving `18,396,816B` to the Stage A
`128,000,000B` boundary.  This is only planning arithmetic.  It is not a new A
result and does not prove allocator or physical footprint.  The proposed pool is
`1,048,576B` WAL + `1,048,576B` checkpoint + `524,288B` read cache + `524,288B`
ledger + `32,768B` entity + `262,144B` policy + `2,048B` chart + `751,616B`
control = `4,194,304B`.

## Required seal and publication order

An isolated micro may proceed only with one active terminal segment and immutable
sealed ancestors.  Each seal explicitly binds `storeUUID`, `segmentID`, epoch,
`firstGlobalLSN`, `lastGlobalLSN`, `recordCount`, exact byte length, parent seal,
base checkpoint, store/schema/engine/layout versions, the WAL digest, and a final
state root.  A sealed segment rejects any truncation or append; only an active,
unacknowledged tail may use torn-tail truncation.  The current `worldDigest`
obtains a final root only by an O(N) scan, so production needs a measured
incremental root or the micro must explicitly remain a same-binary
transcript-integrity proof rather than a live/recovered-state-equivalence proof.
The order is fail-closed:

1. finish frames and `fsync` the WAL;
2. write and `fsync` a seal temp, rename it, then directory-sync;
3. durably create the successor active segment;
4. write and `fsync` a new manifest generation, rename, then directory-sync;
5. acknowledge only the manifest's exact tip.

Recovery must restore exactly the tip in the latest durably published manifest
or fail closed; it may not silently fall back to an older generation.  A crash
after manifest directory-sync but before the callback makes ACK delivery
uncertain, not the commit itself.  Each save therefore needs a stable request ID
and an idempotent status query so retry cannot create a second logical save.
Compaction started at tip `L`
publishes with a manifest-generation CAS/serialized transition and must preserve
any newer descendant `L'`.  Commit followed by cleanup failure is
`COMMITTED_GC_PENDING`, not a failed save.  Garbage collection marks reachability
from retained manifests and never deletes by epoch alone.  A single production
directory also still needs an explicit cross-process owner lock.

Compaction publication is independently ordered: create a temporary base,
stream-replay the pinned chain, write and verify its footer, file-sync, rename,
directory-sync, then publish with manifest-generation CAS.  Only after that CAS
may reachability GC run.  A stale CAS, cleanup EIO, or delete-source-before-current
injection must preserve the authoritative old or new generation without a gap.

## Micro gate before any integration

The next permitted experiment is a bounded disk-native micro with fixed pools,
streaming verification, no second world, and no full-file `Data`.  It must cover
loss of a whole otherwise-valid terminal frame, exact seal stripping, torn frame
and seal tails, append after seal, seal/WAL mismatch, cross-store valid-frame
splice, wrong parent/base/version/root, forked successors, successor-header
directory-entry loss, duplicate/reordered/future segments, missing and stale
manifest generations, EIO/ENOSPC/short write, every crash point in the publication
order, stale compactor CAS, commit-then-GC failure, delete-source-before-current,
`recover -> append -> seal -> recover`, and exact durable-tip recovery.

Performance is a paired ABBA report from one fixture.  It separately times
advance, WAL encode/write, reschedule, service, seal, WAL `fsync`, manifest,
handle switch, durable acknowledgement, and the whole loop.  Recovery is measured
at 0/1/5/10/25 segments before considering 100.  Current C times only `advance`
and leaves WAL/reschedule/service/durability outside that timer; a sealed-WAL
candidate needs an explicit full-loop gate and owner approval for any change in
what `savesCommitted` means.  It also reports allocations, physical footprint,
logical versus allocated disk, write amplification, backlog/backpressure, and
compactor overlap.  The existing gates remain exact: `beginSave p99 <= 100us`,
saving `advance p99 <= 1.1ms`, `overheadRatio <= 1.10`, 100 begins and 100 durable
commits, and each commit within 2,000 advance calls.  Retention count, byte quota,
and worst-case disk growth must be bounded and tested before any 100-save run.

Recovery work is not bounded by WAL bytes.  Its source-shaped cost is
`T = restore(base) + hash(W) + sum(simulationUnits) + sum(reschedule_i * N)`.
At the exact-200,000 scenario, the transcript can require up to 204.8 million
completion units plus 204 million reschedule insertions.  A production compactor
therefore needs a disk-backed exact scheduler or a redesigned WAL delta with its
own equivalence and latency proof; streaming the current bytes alone is not a
bounded compaction algorithm.

Until that evidence exists, sealed WAL is not integrated, H1M/C are not run, and
Stage C remains open independently for S and H.
