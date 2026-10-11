"""Synthetic safety tests; these do not attest a provider's hidden computation."""
import copy
import json
import os
import unittest
from unittest.mock import patch
import bridge as b
from effort_policy import EffortPolicyError, maximum_reasoning, completion_budget

ID = "poolside/laguna-s-2.1:free"


def fixture(identifier=ID):
    return {"id": identifier, "canonical_slug": "poolside/laguna-s-2.1-20260720",
            "pricing": {"prompt": "0", "completion": "0"},
            "supported_parameters": ["reasoning", "max_tokens"],
            "reasoning": {"default_enabled": True}, "context_length": 262144,
            "top_provider": {"max_completion_tokens": 131072}}


def selected(efforts):
    meta = fixture("test/selector:free")
    meta["reasoning"] = {"supported_efforts": efforts}
    return maximum_reasoning(meta["id"], meta)


class MaximumEffortTests(unittest.TestCase):
    def test_native_on_is_max_without_invented_effort(self):
        request, evidence = maximum_reasoning(ID, fixture())
        self.assertEqual(request, {"enabled": True})
        self.assertEqual(evidence["maximum_supported_effort"], "max")

    def test_native_requires_exact_revision(self):
        meta = fixture(); meta["canonical_slug"] = "changed"
        with self.assertRaises(EffortPolicyError): maximum_reasoning(ID, meta)

    def test_native_requires_live_contract(self):
        meta = fixture(); meta["reasoning"]["default_enabled"] = False
        with self.assertRaises(EffortPolicyError): maximum_reasoning(ID, meta)

    def test_native_rejects_new_lower_ladder(self):
        meta = fixture(); meta["reasoning"]["supported_efforts"] = ["high", "low"]
        with self.assertRaises(EffortPolicyError): maximum_reasoning(ID, meta)

    def test_native_accepts_explicit_max(self):
        meta = fixture(); meta["reasoning"]["supported_efforts"] = ["none", "max"]
        self.assertEqual(maximum_reasoning(ID, meta)[0]["effort"], "max")

    def test_max_selected_when_supported(self):
        self.assertEqual(selected(["high", "max", "xhigh"])[0]["effort"], "max")

    def test_xhigh_selected_when_native_max(self):
        self.assertEqual(selected(["medium", "xhigh", "low", "high"])[0]["effort"], "xhigh")

    def test_high_only_when_native_max(self):
        self.assertEqual(selected(["low", "high"])[0]["effort"], "high")

    def test_disabled_or_low_only_rejected(self):
        for values in (["none"], ["low", "medium"], ["minimal"]):
            with self.subTest(values=values), self.assertRaises(EffortPolicyError): selected(values)

    def test_unknown_null_empty_duplicate_efforts_rejected(self):
        for values in (None, [], ["max", "max"], ["future"], [True], {"max": True}):
            with self.subTest(values=values), self.assertRaises(EffortPolicyError): selected(values)

    def test_generic_missing_effort_selection_blocks(self):
        meta = fixture("test/no-selector:free")
        with self.assertRaises(EffortPolicyError): maximum_reasoning(meta["id"], meta)

    def test_mismatched_model_blocks(self):
        with self.assertRaises(EffortPolicyError): maximum_reasoning("wrong/model", fixture())

    def test_missing_reasoning_support_blocks(self):
        for key, value in (("supported_parameters", []), ("reasoning", None)):
            meta = fixture(); meta[key] = value
            with self.subTest(key=key), self.assertRaises(EffortPolicyError): maximum_reasoning(ID, meta)

    def test_request_max_budget_and_required_parameters(self):
        for mode in ("smoke", "review"):
            body = b.request_body(ID, {"mode": mode, "prompt": "Public question"}, fixture())
            self.assertEqual(body["max_tokens"], 131072)
            self.assertTrue(body["provider"]["require_parameters"])
            self.assertFalse(body["provider"]["allow_fallbacks"])
            self.assertEqual(body["reasoning"], {"enabled": True})
            self.assertEqual(body["provider"]["max_price"], {"prompt": 0, "completion": 0})

    def test_missing_completion_limit_blocks(self):
        for value in (None, 0, -1, True, "131072"):
            meta = fixture(); meta["top_provider"]["max_completion_tokens"] = value
            with self.subTest(value=value), self.assertRaises(EffortPolicyError): completion_budget(meta, "p", "s")

    def test_no_budget_downgrade_on_context_conflict(self):
        meta = fixture(); meta["context_length"] = 131072
        with self.assertRaisesRegex(EffortPolicyError, "CONTEXT_CONFLICT"):
            completion_budget(meta, "public", "system")

    def test_configuration_is_not_hidden_execution_proof(self):
        _, evidence = maximum_reasoning(ID, fixture())
        self.assertIs(evidence["provider_execution_effort_verified"], False)

    def test_no_per_request_settings_override(self):
        for field in ("reasoning", "reasoning_effort", "provider", "max_tokens"):
            req = {"mode": "review", "request_id": "test", "prompt": "public", field: "low"}
            with self.subTest(field=field), self.assertRaisesRegex(b.Blocked, "OVERRIDE"):
                b.validate_request(req)

    def test_unknown_capability_stops_before_inference(self):
        meta = fixture(); meta.pop("reasoning")
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "sk-or-test"}), \
             patch.object(b, "api_call", side_effect=[{}, {"data": [meta]}]) as call, \
             patch.object(b, "emit") as emit:
            self.assertEqual(b.main(), 2)
            self.assertEqual([x.args[0] for x in call.call_args_list], ["/key", "/models"])
            self.assertEqual(emit.call_args.args[0]["reason"], "REASONING_CAPABILITIES_UNVERIFIED")

    def test_provider_failure_never_retries_at_lower_effort(self):
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "sk-or-test"}), \
             patch.object(b, "api_call", side_effect=[{}, {"data": [fixture()]}, b.Blocked("PROVIDER_HTTP_429")]) as call, \
             patch.object(b, "emit") as emit:
            self.assertEqual(b.main(), 2)
            self.assertEqual(call.call_count, 3)
            body = call.call_args.args[2]
            self.assertEqual(body["reasoning"], {"enabled": True})
            report = emit.call_args.args[0]
            self.assertEqual(report["reasoning_requests"][0]["maximum_supported_effort"], "max")
            self.assertEqual(report["responses"], [])

    def test_completed_response_remains_connection_only(self):
        reply = {"model": ID, "choices": [{"finish_reason": "stop", "message": {"content": "NEXORA_CONNECTION_OK"}}], "usage": {"cost": 0}}
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "sk-or-test"}), \
             patch.object(b, "api_call", side_effect=[{}, {"data": [fixture()]}, reply]), \
             patch.object(b, "emit") as emit:
            self.assertEqual(b.main(), 0)
            report = emit.call_args.args[0]
            self.assertEqual(report["status"], "SMOKE_COMPLETE_NOT_PROJECT_ACCEPTANCE")
            self.assertFalse(report["reasoning_requests"][0]["provider_execution_effort_verified"])

    def test_truncated_answer_cannot_pass(self):
        response = {"model": ID, "choices": [{"finish_reason": "length", "message": {"content": "NEXORA_CONNECTION_OK"}}], "usage": {"cost": 0}}
        with self.assertRaisesRegex(b.Blocked, "INCOMPLETE"):
            b.parse_answer(response, ID, "smoke")


if __name__ == "__main__":
    unittest.main()
