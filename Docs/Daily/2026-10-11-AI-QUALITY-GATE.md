# NEXORA external-model quality rule — 2026-10-11

Owner requirement: only sufficiently strong coding/reasoning models may review NEXORA; connection tests are not quality proof. Preserve the earlier no-paid-API requirement. Do not silently route to low-tier models.

- Restricted approved free pilot identifiers: `deepseek/deepseek-v4-flash-0731:free` and `poolside/laguna-s-2.1:free`. These are research candidates, not a claim of matching the absolute frontier.
- Evidence: OpenRouter DeepSeek V4 0731 Artificial Analysis Coding Index 69.1 at max reasoning effort; Poolside Laguna S 2.1 vendor-reported Terminal-Bench 2.1 70.2%. Metrics are not directly comparable, and neither substitutes for in-repo tests.
- IDs and $0 pricing must be present in the live catalog before either can run; no automatic fallback to small/mini/nano, paid aliases, or `openrouter/free`.
- No source code, save data, credentials or NEXORA project details in smoke prompts. Review mode continues to request `data_collection=deny`.
- This is an isolated tooling test and cannot approve the engine, change C thresholds, execute work in the app, or authorize merging into main.
- Public references: https://openrouter.ai/deepseek/deepseek-v4-flash-0731 and https://openrouter.ai/poolside/laguna-s-2.1%3Afree
- Source before tooling change: `a80af36c8e3ff8c42587a995c632fe3b833776a0`; verify workflow logs before claiming connectivity.


## Current provider catalog proof / run 38137107908

- Repository: `bdr-design/NEXORA`; source `fc19c3ef27e8fe6a28d2cdcd661075622d357b9c`, tooling only.
- Offline tests: 20/20 PASS. Strong-model smoke BLOCKED as designed, no inference: `QUALIFIED_FREE_MODEL_UNAVAILABLE`.
- Live API returned 15 free text models for this key; `deepseek/deepseek-v4-flash-0731:free` absent while `poolside/laguna-s-2.1:free` is present. Do not silently substitute another model.
- Next bounded action: attempt static handshake with Laguna S 2.1 **only**. No code review until quality/privacy are independently accepted. No source, data or gameplay code sent.
- Comparison basis: Poolside's published July 21, 2026 agentic harness evaluation reports Laguna S 2.1 70.2% Terminal-Bench 2.1 and 59.4% public SWE-bench Pro; vendor-reported metrics, not a validated NEXORA evaluation.
- Absolute frontier models exceed current free tier; remain blocked from paid API until owner explicitly authorizes spend.
