# R005 copy-observer bounded candidate — 2026-10-07

Status: PRE-EDIT ESTIMATE, implementation and Apple execution NOT_RUN.
Only the permitted R001-derived line is a source. At02:26UTC full AGENTS and
continuity read, allowed live362d05b2/tree605a3967 and main38ce39cf verified.
No excluded branches or reference-game implementation opened.

## Preserved qualified successor failure

Run37560851575, source362d05b2a04b695046f994ae517899460e4c81d6, tree605a39670e8631880f41005c7675267b30d7703a,
artifact11457385059, ZIP SHA256b61949f461b2c6db507e9cbb3e92ff7d2dc08bdd7c410ae5cfa4c53df3ef7c85.
Workflow collection succeeded; actual five-save H1M eligibility FAILED:

| Gate | Observation | Unchanged limit |
| --- | ---: | ---: |
| beginSave p99 |211167ns,5samples|100000ns|
| advance p99 while capturing |1176625ns,1469samples|1100000ns|
| overheadRatio |1.4083114548742215|1.10|
| idle allocations / paired excess / queued record bytes |0 /0 /0|0 /0 /0|

Saving1153097events/878691386ns versus idle7846903events/4245903301ns.
Work-unit costs409.187 versus315.026ns are diagnostic, not a replacement gate.
Measured copy across five epochs totals68708638ns. Even subtracting all of it
from advance, including copies potentially outside the advance interval, gives
optimistic ratio1.298189558284>1.10. This is arithmetic feasibility, not a
measured alternative or accepted speed improvement. All raw observations remain.
S matched profiles on this host still have exact984calls/1M events and zero
advance/service allocations; variable full-loop ratios are not H/C proof.
The additional sampled execution is advisory only, cannot replace failed C5.

## Ownership, entry points and proposed change

Existing SwiftWorld and HybridWorld exclusively own mutable EpochBuffer values.
All element/word setters and synchronous inout row updates already execute
ensureWritable before changing state. FrozenEpochBuffer carries immutable value
roots only to the writer; the live owner is never Sendable. Current willWrite
hooks additionally load StageCState, capturing, page flags and perform a clone
before the setter checks the same epoch flags again. That repeated saving-only
work is a plausible cause of residual overhead; causality is not established.

Proposed: install the actual begin owner as a private copy observer in three S
or four H buffers after all begin reservations pass and before freeze. Record
physical copied bytes/time and first-barrier K2 inside ensureWritable's existing
first-copy branch, after clone and before the setter mutates. Remove redundant
EPOCH_PAGES pre-write caller hooks, preserving legacy STAGE_C branches. Keep
all COW guards, world validation, economics, deadlines, workload/cadence, v2
bytes, WAL, writer ownership and completion fences. No unsafe/shared mutable
views, per-entity tasks, closures, locks or allocations introduced.

The observer is attached at successful begin, not StageCState construction or
stageCInstall: multiple inactive states on the same owner must report copies
to the state that actually began the epoch. Add a held-epoch small test for
that ownership case; keep cold-page writes, partial-page physical padding and
failure/overlap/cancel/writer-completion checks. Failed begin must not replace
an active observer. Writer failure still releases only after completion and
keeps failed inFlight, requiring recovery. Observer is cleared at completion.
State retains owner identity only, no world/buffer; no ownership cycle added.

## Allocation and simulation-thread estimate before edits

| Scope | Expected effect, NOT yet measured |
| --- | --- |
| beginSave |3/4 pointer assignments, O(1), zero extra allocations; existing control record remains|
| ordinary mutation |same epoch/COW check in setter, eliminate duplicate state/page precheck|
| first copy |same root/leaf/payload bytes; two timer calls and one nonescaping state call per copied page|
| buffer ownership |one optional class reference per buffer, nominal24/32B S/H total; allocator-rounded capacity not predicted|
| writer / service / WAL |unchanged; independent wall costs still reported|

No numeric time reduction is promised. Current original C5 values stay failed
even if a bounded comparison improves. Full prepared H owned210772320B/1M
exceeds200B/asset before UI and allocator overhead; this change does not reduce
that full spare-image pool. Production memory and device smoothness are OPEN.

First run limited Debug/Release/TSan canonical/order/lifecycle matrix and same
host old36675c81/new H100k ABBA; exact canonical/WAL and scoped Release zero
allocation requirements remain. If credible, re-run fresh A, complete source-
bound B and Debug/Release/TSan×S/H1M K1–K10, then one real five-save diagnostic.
Prospectively select that fresh A only; never choose a favorable earlier run.
No C100 from a failed micro or mere sampled/paired result, no main merge or
closure result files, Stage2–4/app/IPA/device remain NOTIMPLEMENTED.

## Implementation checkpoint — Apple pending

After estimate was published live6de30940/treee4b24c11, exactly five runtime
files changed: EpochPages, Core, Hybrid, Stage005CSave, Stage005CPagedChecks.
Buffer observer installed by successful begin, cleared after completion;
first-copy callback preserves K2 before the actual setter mutation. Legacy
STAGE_C hooks unchanged after conditional compilation. New S/H held257 test
uses a second installed inactive state, rejects its begin during active save,
and checks actual owner metrics, frozen snapshot and exact WAL recovery.

Local guard/selftest,23existing gate tests, YAML/embedded shell/Python syntax
and exact changed-input set PASS. No Swift/Xcode locally: compilation, zero-
allocation and Debug/Release/TSan functional proof remain pending on Apple.
Bounded workflow compares allowed corrected36675c81 against the new source
in H100k ABBA, with identical8050000 physical hot/node/group copy bytes. Its
old/new manifest check requires exactly these five files. Source/micro pins
reset0/PENDING; no previous A/B/K proof accepted for this source, C100 blocked.
Copy timers now bracket actual root/leaf/payload clone inside ensureWritable;
prior prehook intervals are retained as measured, not retrospectively changed.
Full spare-image memory remains NOT_FIXED, no product/IPA/device acceptance.

### Original bounded build failure and correction

Run37562437344 FAILED: legacy Debug/Release built, but candidate Debug rejected
the new generic test's omitted advance arguments. Protocol requirements do not
provide the concrete owners' defaults. Artifact11457591361 ZIP SHA256
6918f04d6c6e1e32ae4cc829957ee61ee5a12a74fa91261042d19e31d37a3226 verified
against source/tree/all source hashes and guard logs; functional/ABBA NOT_RUN.
Only two generic test calls now pass work65536/checkLimit Int.max/deadline0/
injectnil explicitly, matching existing generic paged checks and real defaults.
No hot source, payload, workload or threshold changed after original failure.
Corrected limited Apple check remains pending; original stays FAILED.
