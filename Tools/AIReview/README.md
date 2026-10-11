# NEXORA free-model review bridge

Status: prepared and offline-tested; live authentication/inference NOT VERIFIED.
This is a GitHub Actions/OpenRouter adapter, NOT Free Claude Code, a persistent
MCP server, a new ChatGPT connection, or an autonomous code-writing agent.

## One-time owner action

In bdr-design/NEXORA, open Settings > Secrets and variables > Actions >
New repository secret. Name: OPENROUTER_API_KEY. Paste the API key into the
Secret field, never into a tracked file, issue, request prompt or chat message.
Prefer a replacement for any key already disclosed in chat. This connector has
no supported secret-setting action; an operator must perform this one step.

The workflow's first missing-secret failure is expected and is NOT a model test.
After saving the secret, rerun the failed job; no merge into main is required.
The connected GitHub tool supports rerunning failed workflow jobs.

## Scope and operation

Only the tooling/nexora-ai-review-20261011 branch triggers the new workflow.
It runs on a standard Linux runner, with repository read permission only.
The secret is available only to the external-call step, not to offline tests.
The script authenticates against OpenRouter, discovers currently listed :free
models with ALL advertised price fields zero, and makes at most two generation
calls. No retries, paid-model fallback, arbitrary endpoint or redirect is allowed.
The provider request requires zero prompt/completion prices and denies providers
that collect data. If no qualifying route exists, the run stops rather than
relaxing cost/privacy constraints. Provider availability and account quotas apply.
An optional models list pins one or two exact catalog IDs; an unavailable or
non-free choice is rejected. Empty list selects different model families using
a documented family preference, NOT a measured quality ranking.

The initial request is a tiny connection smoke test. No project files or chat
history are sent. Successful responses must say NEXORA_CONNECTION_OK. This proves
only that the reported model responded, not coding quality or NEXORA acceptance.

For a later explicitly requested review, set request.json mode to review, give it
a new request_id, and place an owner-approved bounded question/source excerpt in
prompt (max 16,000 characters). Exact source commits/paths/lines should accompany
excerpts. Only this prompt and the fixed review policy are sent; no automatic
repository scan occurs. Never use another game's implementation or denied sources.
Model replies are untrusted advice. Nothing they return is executed or committed.
The response, actual model ID and available billing metadata appear in the job's
JSON log and summary. Logs may be visible to repository readers. Do not place
private material or credentials in a prompt. Missing cost metadata is reported
as unverified, never as measured zero. Failures retain completed partial replies.

## Local tests

python3 -B -m unittest discover -s Tools/AIReview -p 'test_*.py' -v

16 offline tests passed in preparation. They use mocks; no real API key was used.
The local environment could not resolve openrouter.ai before authentication.
No real model review, engine test, Apple run, device result or IPA is claimed.

## Primary references checked 2026-10-11

https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key
https://openrouter.ai/docs/guides/routing/model-variants/free
https://openrouter.ai/docs/guides/routing/provider-selection
https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
