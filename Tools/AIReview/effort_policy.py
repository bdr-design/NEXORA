"""Maximum-supported thinking requests; no inference or hidden-effort attestation.

Primary contracts verified 2026-10-11:
https://openrouter.ai/docs/guides/best-practices/reasoning-tokens
https://openrouter.ai/docs/guides/routing/provider-selection
https://poolside.ai/blog/introducing-laguna-s-2-1#thinking-effort
"""
from __future__ import annotations

LEVELS = ("none", "minimal", "low", "medium", "high", "xhigh", "max")
NATIVE_MAX_PROFILE = {
    "poolside/laguna-s-2.1:free": "poolside/laguna-s-2.1-20260720",
}


class EffortPolicyError(ValueError):
    """Fixed status codes only; never include input, credentials or provider text."""


def maximum_reasoning(identifier: str, metadata: dict) -> tuple[dict, dict]:
    """Choose from declared native support; never assume a generic 'max' works."""
    if not isinstance(metadata, dict) or metadata.get("id") != identifier:
        raise EffortPolicyError("REASONING_MODEL_METADATA_MISMATCH")
    params = metadata.get("supported_parameters")
    if not isinstance(params, list) or "reasoning" not in params:
        raise EffortPolicyError("REASONING_PARAMETER_SUPPORT_UNVERIFIED")
    info = metadata.get("reasoning")
    if not isinstance(info, dict):
        raise EffortPolicyError("REASONING_CAPABILITIES_UNVERIFIED")
    efforts = info.get("supported_efforts")
    profile = NATIVE_MAX_PROFILE.get(identifier)
    if profile and metadata.get("canonical_slug") != profile:
        raise EffortPolicyError("NATIVE_MAX_MODEL_REVISION_CHANGED")
    # The vendor documents exactly off/max for this immutable checkpoint.
    # Explicit enabled=true selects its sole thinking mode; do not invent xhigh.
    if profile and efforts is None:
        if info.get("default_enabled") is not True:
            raise EffortPolicyError("NATIVE_MAX_ROUTE_CONTRACT_UNVERIFIED")
        return {"enabled": True}, {
            "maximum_supported_effort": "max",
            "selection_basis": "VENDOR_OFF_MAX_CONTRACT_AND_LIVE_METADATA",
            "provider_execution_effort_verified": False,
        }
    # null means gateway values accepted, not proof of native effort selection.
    if (not isinstance(efforts, list) or not efforts
            or any(not isinstance(x, str) or x not in LEVELS for x in efforts)
            or len(set(efforts)) != len(efforts)):
        raise EffortPolicyError("MAXIMUM_NATIVE_EFFORT_UNVERIFIED")
    highest = max(efforts, key=LEVELS.index)
    if highest not in ("high", "xhigh", "max"):
        raise EffortPolicyError("MAXIMUM_EFFORT_BELOW_QUALITY_FLOOR")
    if profile and highest != "max":
        raise EffortPolicyError("NATIVE_MAX_ROUTE_CONTRACT_CHANGED")
    return {"enabled": True, "effort": highest}, {
        "maximum_supported_effort": highest,
        "selection_basis": "LIVE_EXPLICIT_SUPPORTED_EFFORTS",
        "provider_execution_effort_verified": False,
    }


def completion_budget(metadata: dict, prompt: str, system: str) -> int:
    """Use advertised maximum output, not the former 1K/4K application cap.

UTF-8 bytes plus an envelope reserve is a conservative input preflight, not a
claim to have run the provider's tokenizer. Provider context errors block too.
"""
    top = metadata.get("top_provider")
    limit = top.get("max_completion_tokens") if isinstance(top, dict) else None
    context = metadata.get("context_length")
    if type(limit) is not int or limit <= 0 or type(context) is not int or context <= 0:
        raise EffortPolicyError("MAXIMUM_COMPLETION_BUDGET_UNVERIFIED")
    reserve = len(prompt.encode("utf-8")) + len(system.encode("utf-8")) + 4096
    if limit + reserve > context:
        raise EffortPolicyError("MAXIMUM_BUDGET_CONTEXT_CONFLICT")
    return limit
