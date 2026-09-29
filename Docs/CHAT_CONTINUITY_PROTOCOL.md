# NEXORA — Chat / Session Continuity Protocol

Chat is a temporary working interface. The Git repository is the authoritative project memory.

## Purpose
Prevent loss of architectural context, duplicated work, wrong-source edits, and risky implementation when a long conversation becomes heavy, unstable, truncated, or ambiguous.

## Non-negotiable rule
If the active conversation begins to lose reliability, sensitive implementation stops before more code is changed.

## Warning signs
Stop sensitive implementation when one or more of these occur:
- repeated context confusion or contradiction;
- uncertainty about current branch/commit/source;
- inability to recall the current architecture contract with confidence;
- repeated tool failures or conversation interruptions that make state uncertain;
- very long session with many unrelated branches of work;
- user indicates freezes, missing messages, disconnections, or degraded continuity;
- the agent cannot verify that it is operating at the project's required very-high capability/effort level.

## Required pre-handoff checkpoint
Before moving to a new chat/session, update the repository with:
1. current repository and branch;
2. exact HEAD commit;
3. files changed;
4. current Update ID/version/build;
5. what was completed;
6. what is still incomplete;
7. tests run and exact results;
8. performance/thermal measurements gathered;
9. known failures/risks;
10. architectural decisions made;
11. rejected approaches and why;
12. exact next safe action;
13. any user instruction that must remain binding.

Required files to update when relevant:
- PROJECT_CONTINUITY.md
- Docs/Daily/YYYY-MM-DD.md
- current Docs/Updates/NXR-####-....md
- CHANGELOG.md / VERSION.json when version state changes.

## New-chat startup protocol
Before modifying code in a new chat/session:
1. read AGENTS.md;
2. read PROJECT_CONTINUITY.md;
3. read VERSION.json;
4. read the current Update record;
5. read the most recent Daily log;
6. verify current branch and HEAD from GitHub;
7. verify working tree/source identity;
8. only then resume implementation.

## Source-of-truth hierarchy
1. committed repository source and contracts;
2. AGENTS.md;
3. PROJECT_CONTINUITY.md;
4. current Update record / ADRs;
5. Daily log;
6. chat messages.

Chat memory never overrides a newer committed repository fact.

## No reconstruction from memory
If a detail is missing from the repository after a handoff, do not invent or infer it from vague recollection. Re-open the relevant source, test evidence, or previous documented record.

## Safe checkpoint cadence
A checkpoint should be committed after every meaningful architectural milestone, every risky refactor, every verified performance result, and before any likely chat/session transition.

## Sensitive-work freeze
When reliability is questionable, allowed work is limited to:
- reading;
- verification;
- documentation;
- preparing a handoff;
- non-destructive analysis.

Disallowed until continuity is restored:
- architectural mutation;
- destructive file operations;
- large refactors;
- source resets/checkouts that can discard work;
- release/build claims without verified source identity.

## Goal
A new chat should be able to continue NEXORA correctly from the repository without depending on hidden conversational memory.
