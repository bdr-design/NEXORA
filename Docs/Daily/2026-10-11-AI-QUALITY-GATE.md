# NEXORA external-model quality rule — 2026-10-11

Owner requirement: only sufficiently strong coding/reasoning models may review NEXORA; connection tests are not quality proof. Preserve the earlier no-paid-API requirement. Do not silently route to low-tier models.

- Restricted approved free pilot identifiers: `deepseek/deepseek-v4-flash-0731:free` and `poolside/laguna-s-2.1:free`. These are research candidates, not a claim of matching the absolute frontier.
- Evidence: OpenRouter DeepSeek V4 0731 Artificial Analysis Coding Index 69.1 at max reasoning effort; Poolside Laguna S 2.1 vendor-reported Terminal-Bench 2.1 70.2%. Metrics are not directly comparable, and neither substitutes for in-repo tests.
- IDs and $0 pricing must be present in the live catalog before either can run; no automatic fallback to small/mini/nano, paid aliases, or `openrouter/free`.
- No source code, save data, credentials or NEXORA project details in smoke prompts. Review mode continues to request `data_collection=deny`.
- This is an isolated tooling test and cannot approve the engine, change C thresholds, execute work in the app, or authorize merging into main.
- Public references: https://openrouter.ai/deepseek/deepseek-v4-flash-0731 and https://openrouter.ai/poolside/laguna-s-2.1%3Afree
- Source before tooling change: `a80af36c8e3ff8c42587a995c632fe3b833776a0`; verify workflow logs before claiming connectivity.

