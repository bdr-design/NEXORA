# NEXORA maximum-effort tooling checkpoint — 2026-10-11 / Asia-Riyadh

Pre-edit source: bdr-design/NEXORA, tooling/nexora-ai-review-20261011,
47ca260f09fafd52af27cdabb9aebdcd49ac6bc0; base tree d8b97c39a7db7db74c4496bba80e89a3839f2220.
Root AGENTS.md was read. The permitted R001-derived tooling line is the sole
implementation source. No excluded source or other game's code was opened.

Owner requested always-highest reasoning effort, in addition to model intelligence.
The old bridge sent no explicit reasoning configuration and capped completions
at 1024/4096. Prior handshake successes do not prove maximum thinking.

Changes are limited to AI-review tooling: maximum native reasoning selection,
strict live capability/revision checks, provider parameter enforcement, maximum
advertised completion budget with a context-conflict stop, no per-request
configuration override, no model/provider/effort fallback, and distinct requested
configuration versus unverified hidden execution fields. No raw reasoning is logged.
The existing quality allowlist, $0 requirement and review privacy rule remain.

Laguna S 2.1's vendor documents exactly off/max; its explicit enabled thinking
request is accepted only with the pinned canonical model and matching live
reasoning metadata. Other eligible models need an explicit supported effort
ladder; unknown/gateway-only declarations fail closed. This is configuration
validation, not a cryptographic attestation of the provider's computation.

Local verification: current bridge/test Git blob hashes were matched to connected
GitHub before editing (024b0f6ed4cde8b21b480faa4edfc010e8419deb and
4c7dcaf2d7a0cd4a4d0c23e510733d65259d5281). Original 20 tests passed first.
42/42 tests passed after the change under both normal Python and python -O.
Command: python3 -B -m unittest discover -s Tools/AIReview -p 'test_*.py' -v
Optimized command: python3 -B -O -m unittest discover -s Tools/AIReview -p 'test_*.py' -q
Tests use synthetic metadata/mocks, not actual reasoning or engine acceptance.
Remote CI and provider result: NOT_VERIFIED at preparation; inspect the actual
new source-bound workflow before claiming success. Previous 429 remains history.
No main merge, engine tests, Apple runs, paid inference or IPA is claimed.

Primary sources verified 2026-10-11:
https://openrouter.ai/docs/guides/best-practices/reasoning-tokens
https://openrouter.ai/docs/guides/routing/provider-selection
https://poolside.ai/blog/introducing-laguna-s-2-1#thinking-effort
https://huggingface.co/poolside/Laguna-S-2.1#controlling-reasoning
