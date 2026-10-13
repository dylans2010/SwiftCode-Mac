#!/usr/bin/env python3
"""Run with runtime/bin/python3: real SDK configs, no provider requests."""
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agent_runner as runner
from google.antigravity import types
from google.antigravity.connections.local.local_connection import build_models_proto
from google.antigravity.server.agent_runner import AgentRunner as ModuleRunner


class CapturingAgent:
    def __init__(self, config):
        self.config = config
        self.conversation_id = "test-conversation"

    async def __aenter__(self):
        return self


class SessionAuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_account_config_has_bearer_and_no_api_key_on_wire(self):
        bridge = runner.AgentRunner(lambda *_: None)
        with patch.object(runner, "Agent", CapturingAgent), patch.dict(os.environ, {"GEMINI_API_KEY": "stale-key"}):
            await bridge.create_session("oauth", {
                "model": "gemini-test", "provider": "google", "oauthToken": "test-token",
                "project": "quota-project", "enableSubagents": False,
            })
            config = bridge.sessions["oauth"].agent.config
            self.assertIsNone(config.api_key)
            proto = build_models_proto(config.models)[0].gemini_api_endpoint
            self.assertEqual(proto.api_key, "")
            self.assertEqual(proto.http_headers["Authorization"], "Bearer test-token")
            self.assertEqual(proto.http_headers["x-goog-user-project"], "quota-project")
            self.assertEqual(os.environ["GEMINI_API_KEY"], "stale-key")

    async def test_missing_anthropic_key_fails_before_network(self):
        bridge = runner.AgentRunner(lambda *_: None)
        with patch.object(runner, "Agent", CapturingAgent), patch.dict(os.environ, {"GOOGLE_OAUTH_ACCESS_TOKEN": "google-token"}):
            with self.assertRaisesRegex(runner.GeminiAuthConfigError, "only authorizes Gemini"):
                await bridge.create_session("claude", {"model": "claude-sonnet-test", "provider": "anthropic"})
        self.assertNotIn("claude", bridge.sessions)

    def test_api_key_is_preserved_without_bearer(self):
        proto = build_models_proto([types.ModelTarget(
            name="gemini-test", types=[types.ModelType.TEXT],
            endpoint=types.GeminiAPIEndpoint(api_key="explicit-key"),
        )])[0].gemini_api_endpoint
        self.assertEqual(proto.api_key, "explicit-key")

    def test_module_and_bridge_execute_same_runner(self):
        self.assertEqual(ModuleRunner.create_session.__code__.co_filename,
                         runner.AgentRunner.create_session.__code__.co_filename)


if __name__ == "__main__":
    unittest.main(verbosity=2)
