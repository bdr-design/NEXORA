# 2026-10-11 / Asia-Riyadh — external-model tooling only

Owner authorized setup for NEXORA, not Global Holdings. Read AGENTS.md and
verified the allowed diagnostic/r005-design-1m-20260930 source HEAD:
aee6949e2fb7b14e9c1a49d96df580f57478b3fb, tree
ba5de8415256f45fd3f3e6118e4331c8097af808.
No excluded branch or other game's implementation was opened or imported.
The tooling branch derives only from this allowed source. No runtime source,
R005 threshold, test fixture, existing workflow or main merge is part of setup.

New work: bounded, read-only, free-only OpenRouter adapter; initial connection
smoke request; 16 offline safety tests; Linux-only branch-scoped workflow.
The bridge receives no model tools or repository write permission. Credentials
are referenced solely as an Actions secret, never embedded in the source tree.
Direct unauthenticated connectivity failed at DNS resolution in this session;
no live key validation, model response or project review has occurred here.
Local tests: 16/16 PASS; missing-secret execution exits 2 with BLOCKED and no
network call. These are tooling tests, not Swift/Apple/device acceptance.

Next: owner stores OPENROUTER_API_KEY using GitHub's secret UI. Check the actual
workflow result; rerun a missing-secret job only after the secret is saved.
Inspect actual model identities and smoke responses before requesting reviews.
No background monitoring, persistent MCP connection or Free Claude Code install
has been performed. See Tools/AIReview/README.md for the exact boundaries.
