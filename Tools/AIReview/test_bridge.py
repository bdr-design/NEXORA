import json
import os
import unittest
from unittest.mock import patch
import bridge as b


def model(name="deepseek/example:free", **prices):
    return {"id": name, "pricing": {"prompt": "0", "completion": "0", **prices}}


class BridgeTests(unittest.TestCase):
    def test_free(self):
        self.assertTrue(b.free_model(model()))

    def test_missing_prices(self):
        self.assertFalse(b.free_model({"id": "a/b:free"}))

    def test_nonzero_additional_fee(self):
        self.assertFalse(b.free_model(model(request="0.1")))

    def test_paid_alias(self):
        self.assertFalse(b.free_model(model("deepseek/example")))

    def test_nonfinite_price(self):
        self.assertFalse(b.free_model(model(request="NaN")))

    def test_explicit_qualified_models(self):
        approved = sorted(b.QUALIFIED_FREE_MODELS)
        selected = b.choose_models([model(name) for name in approved], approved)
        self.assertEqual(selected, approved)

    def test_no_automatic_low_tier_fallback(self):
        with self.assertRaisesRegex(b.Blocked, "EXPLICIT_QUALIFIED_FREE_MODELS_REQUIRED"):
            b.choose_models([model("nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free")], [])

    def test_unqualified_small_model_rejected(self):
        with self.assertRaisesRegex(b.Blocked, "MODEL_NOT_QUALIFIED_FOR_NEXORA"):
            b.choose_models([model("apodex/apodex-1.1-mini:free")], ["apodex/apodex-1.1-mini:free"])

    def test_unavailable_qualified_model_rejected(self):
        with self.assertRaisesRegex(b.Blocked, "QUALIFIED_FREE_MODEL_UNAVAILABLE"):
            b.choose_models([model("apodex/apodex-1.1-mini:free")],
                            ["deepseek/deepseek-v4-flash-0731:free"])

    def test_explicit_paid_model_rejected(self):
        with self.assertRaises(b.Blocked):
            b.choose_models([model()], ["anthropic/paid"])

    def test_duplicates_rejected(self):
        with self.assertRaises(b.Blocked):
            b.choose_models([model()], ["deepseek/example:free"] * 2)

    def test_secret_in_prompt_rejected(self):
        with self.assertRaises(b.Blocked):
            b.validate_request({"mode": "review", "request_id": "test", "prompt": "sk-or-v1-" + "x" * 40})

    def test_secret_not_sent_in_smoke_prompt(self):
        body = b.request_body("deepseek/example:free", {"mode": "smoke", "prompt": "USER TEXT"})
        self.assertNotIn("USER TEXT", json.dumps(body))
        self.assertEqual(body["provider"]["max_price"], {"prompt": 0, "completion": 0})
        self.assertFalse(body["provider"]["allow_fallbacks"])
        self.assertEqual(body["provider"]["data_collection"], "allow")

    def test_review_stays_privacy_restricted(self):
        body = b.request_body("deepseek/example:free", {"mode": "review", "prompt": "Review public project evidence"})
        self.assertEqual(body["provider"]["data_collection"], "deny")
        self.assertEqual(body["provider"]["max_price"], {"prompt": 0, "completion": 0})
        self.assertFalse(body["provider"]["allow_fallbacks"])
        self.assertNotIn("tools", body)
        self.assertNotIn("tools", body)

    def test_reply_validation(self):
        response = {"model": "deepseek/example", "choices": [{"finish_reason": "stop", "message": {"content": "NEXORA_CONNECTION_OK"}}], "usage": {"cost": 0}}
        self.assertEqual(b.parse_answer(response, "deepseek/example:free", "smoke")["status"], "SMOKE_RESPONSE_OK")
        for change in ({"model": "wrong/model"}, {"usage": {"cost": 1}}, {"choices": []}):
            with self.assertRaises(b.Blocked):
                b.parse_answer({**response, **change}, "deepseek/example:free", "smoke")

    def test_no_redirect(self):
        with self.assertRaises(b.Blocked):
            b.NoRedirect().redirect_request(None, None, 302, None, None, "https://example.invalid")

    def test_no_secret_no_network(self):
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": ""}), patch.object(b, "api_call") as call, patch.object(b, "emit") as emit:
            self.assertEqual(b.main(), 2)
            call.assert_not_called()
            self.assertEqual(emit.call_args.args[0]["reason"], "MISSING_OPENROUTER_API_KEY_SECRET")

    def test_authentication_failure_blocks_generation(self):
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "sk-or-test"}), patch.object(b, "api_call", side_effect=b.Blocked("PROVIDER_HTTP_401")) as call, patch.object(b, "emit"):
            self.assertEqual(b.main(), 2)
            self.assertEqual(call.call_count, 1)

    def test_provider_error_is_metadata_only(self):
        value = {"code": 429, "message": "sk-or-v1-" + "x" * 40,
                 "metadata": {"error_type": "rate_limit_exceeded"}}
        self.assertEqual(b.safe_provider_error(value),
                         "PROVIDER_RESPONSE_ERROR_429_RATE_LIMIT_EXCEEDED")
        self.assertEqual(b.safe_provider_error({"code": "private-info"}),
                         "PROVIDER_RESPONSE_ERROR_UNKNOWN")

    def test_bad_endpoint(self):
        with self.assertRaises(b.Blocked):
            b.api_call("https://example.invalid", "test")


if __name__ == "__main__":
    unittest.main()
