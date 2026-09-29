# NEXORA execution contract

The owner's explicit current instructions take precedence over older project
notes. On 2026-09-30 the owner authorized a radical deletion and fresh start.

## Effort and continuity
Sensitive implementation requires the owner's very-high reasoning/effort gate.
Never claim a model setting that is not exposed or verifiable. If the gate cannot
be verified, stop sensitive work and limit work to safe inspection, isolated
non-production scaffolding, tests, documentation and handoff. No release may be
approved on an invented setting. Do not weaken this rule to pass a gate.

Keep work bounded. At any loss of source identity or context reliability, stop
sensitive changes and record the exact commit, files, test commands and results,
known failures, and next safe action in PROJECT_CONTINUITY.md. Do not promise
background continuation. Chat is not durable project storage.

## Clean start
Do not import code, schemas, runtime files, or patches from Global Holdings,
retired NEXORA NXR-0001/2/3, or the abandoned repair workspace. Product ideas and
user requirements survive; technical implementations do not. Public language and
platform documentation may inform newly written code.

## Work discipline
Before a change: identify the state owner, public entry points, caller/callee
path, side effects, failure behavior, dependencies and test evidence. Use primary
sources for uncertain platform facts. Do not broaden a fix into unrelated work.

Verify public misuse, exceptional inputs, concurrency and lifecycle, not just the
happy path. Run both Debug and Release. Compiler and sanitizer success do not
prove logical correctness. Do not disable checks to obtain a green result.

## Performance and evidence
Keep synchronous work off the future UI critical path. No task, actor, or lock per
entity; no normal-save full-world JSON; no visual-motion writes to economic truth.
Measure before selecting an optimization or adding parallel shared workspaces.
Never equate record count, element stride or a smoke test with complete gameplay,
physical memory, zero allocations, frame stability, or thermal certification.

Document each update, including failures and limits. A new domain is not complete
without diagnostic evidence and end-to-end acceptance. No force push, destructive
history rewrite, repository deletion, or change to another repository is implied
by this restart. Preserve an explicit recovery point before replacing a tree.
