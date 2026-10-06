# R005 C — WAL continuation and acceptance coverage, 2026-10-06

Repository `bdr-design/NEXORA`, branch `diagnostic/r005-design-1m-20260930`.
Before the change, AGENTS and PROJECT_CONTINUITY were read; live HEAD was
`611a14efca6bb571887d4f5dc5189d51621b212d`, descended from the permitted
R001 line. Excluded branches were not used. C remains open on S and H, and the
original `36875130222` stays FAILED at overhead ratio 1.51625 > 1.10.

Source review found two separate functional proof holes:

- `stage_c_failures` accepted a claim of 100 saves with one begin and one saving
  advance sample. It now requires integer saves >=100, exactly one begin sample
  per save, at least one saving advance sample per save, and identical paired
  allocation coverage. Two negative/boundary test groups raise local coverage
  to 14 tests. No performance threshold or 100-save requirement changed.
- Recovery read a partial terminal WAL frame and ignored it, but the writer
  opened that same epoch exclusively. Recovered state could not safely append
  then recover again. A complete 72-byte frame with corrupted length 73 was
  previously classifiable as an ignored tail. The new parser checks canonical
  length and any available kind/reserved/sequence before classifying a short
  suffix; a complete malformed frame fails closed. Recovery exposes terminal
  epoch, per-epoch sequence, valid prefix length and file digest. Resume
  verifies unchanged file bytes, archives the discarded suffix and syncs the
  archive and directory, truncates/syncs the WAL, then seeds the sequence and
  appends within that same epoch. A writer with a partial I/O error is closed
  and must recover before another append.

Ownership is per WAL epoch and a single recovery/append owner of its directory.
Restart estimate before the edit: one WAL read/hash outside `advance`, one
handle, and at most 71 archived tail bytes; zero new per-event/advance
allocations. Restart thread work is O(current WAL bytes) validation plus
tail archive/truncation/sync only when torn. The `advance` and `beginSave`
timers, their thresholds and the normal hot-state barrier remain untouched.

Bounded 4,096-asset S/H fixtures use three authentic 2/8/54-byte partial
second frames after one valid command; each requires resume sequence 2,
exact archived tail and exact second recovery. Complete frame hash and length
corruption are rejected. The existing one-million-asset real SIGKILL K9 case
adds recover→append in WAL epoch 2→recover again with exact digest; K1–K10
remain intact. The targeted Apple job compiles Debug/Release/TSan and runs
these functional fixtures on S/H, without a 100-save timing run.

Local 14 proof-gate tests, Python syntax, YAML/bash syntax and production
source guard passed. Apple Swift compilation, sanitizer and crash results are
pending. This change does not close C or qualify an iPhone app.
