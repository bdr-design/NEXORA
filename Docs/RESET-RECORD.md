# Radical restart record — 2026-09-30

The owner interrupted NXR-0003 repair and explicitly requested deletion and a new
implementation. Repair work stopped. No repair code is used in this tree.

## Recovery references (not active source)

- Old foundation: `9913d741a9b7aeec1e5a7f3b7bcfcc3cb226519d`.
- Recovery branch: `archive/before-radical-rebuild-20260930`.
- Old audit: `35736cf41abff55fd5323559786ae4908e667f88`.
- Old repair branch tip: `bf8bd11a8271d3408cb3b5e785d883679ddfd8ea`.
- Local interrupted-work archive SHA-256:
  `f4fda213a0f0a412765ad9e18252615eda16328916632f6628ed7e74a80b15db`.
  This local backup is supplementary, not the canonical remote source.

## Exact scope

Replace the complete ACTIVE source tree, including prior engines, tests,
workflows, manifests, and architecture documents. New requirements and working
notes are written anew. No old performance number or acceptance status is
carried forward. NXR-R001 is a new numbering line, not a passing NXR-0003.

This is a file-tree replacement, not erasure of Git history. The replacement
commit has the old foundation as parent solely for recovery/audit continuity.
It is NOT an orphan root, and the repository itself is not deleted. Old audit
and repair branches are historical only; they must never be used as a build
source for the restart. No Global Holdings/METSE repository is changed.

## New scope

Start with identity ownership and bounded observability, plus contract tests.
Do not re-create the discarded transaction gate, actor/lock arrangement, domain
storage, shared parallel buffers or scheduler spec merely to match old filenames.
The narrow foundation is intentionally not a game or a production simulation.
