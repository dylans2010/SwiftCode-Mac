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


class DummyAdapterServer:
    def __init__(self, port: int = 54321):
        self.actual_port = port
        self.targets = {}

    def register_target(self, model_name, provider, api_key=None, base_url=None, headers=None):
        self.targets[model_name] = {
            "provider": provider,
            "api_key": api_key,
            "base_url": base_url,
            "headers": headers or {},
        }


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

    async def test_antigravity_mode_authorizes_claude_catalog_models_with_oauth_token(self):
        adapter = DummyAdapterServer(port=54321)
        bridge = runner.AgentRunner(lambda *_: None, adapter_server=adapter)
        with patch.object(runner, "Agent", CapturingAgent):
            for claude_model in ("claude-sonnet-4-6", "claude-opus-4-6-thinking"):
                sess_id = f"ag-{claude_model}"
                await bridge.create_session(sess_id, {
                    "model": claude_model,
                    "provider": "anthropic",
                    "executionMode": "antigravity",
                    "oauthToken": "ya29.antigravity-token",
                    "enableSubagents": False,
                })
                config = bridge.sessions[sess_id].agent.config
                self.assertIsNone(config.api_key)
                proto = build_models_proto(config.models)[0].gemini_api_endpoint
                self.assertEqual(proto.api_key, "")
                self.assertEqual(proto.http_headers["Authorization"], "Bearer ya29.antigravity-token")
                self.assertEqual(proto.base_url, "http://127.0.0.1:54321/v1")
                self.assertEqual(adapter.targets[claude_model]["provider"], "antigravity")

    async def test_antigravity_mode_gemini_without_quota_project_routes_via_antigravity_adapter(self):
        adapter = DummyAdapterServer(port=54322)
        bridge = runner.AgentRunner(lambda *_: None, adapter_server=adapter)
        with patch.object(runner, "Agent", CapturingAgent), patch.dict(os.environ, {"GOOGLE_CLOUD_PROJECT": ""}):
            for gemini_model in ("gemini-3.8-flash", "gemini-3.1-pro", "gemini-3-flash", "gemini-3.1-pro-high", "gemini-3.1-pro-low"):
                sess_id = f"ag-{gemini_model}"
                await bridge.create_session(sess_id, {
                    "model": gemini_model,
                    "provider": "google",
                    "executionMode": "antigravity",
                    "oauthToken": "ya29.antigravity-token",
                    "enableSubagents": False,
                })
                config = bridge.sessions[sess_id].agent.config
                self.assertIsNone(config.api_key)
                proto = build_models_proto(config.models)[0].gemini_api_endpoint
                self.assertEqual(proto.api_key, "")
                self.assertEqual(proto.http_headers["Authorization"], "Bearer ya29.antigravity-token")
                self.assertEqual(proto.base_url, "http://127.0.0.1:54322/v1")
                self.assertEqual(adapter.targets[gemini_model]["provider"], "antigravity")

    def test_api_key_is_preserved_without_bearer(self):
        proto = build_models_proto([types.ModelTarget(
            name="gemini-test", types=[types.ModelType.TEXT],
            endpoint=types.GeminiAPIEndpoint(api_key="explicit-key"),
        )])[0].gemini_api_endpoint
        self.assertEqual(proto.api_key, "explicit-key")

    def test_module_and_bridge_execute_same_runner(self):
        self.assertEqual(ModuleRunner.create_session.__code__.co_filename,
                         runner.AgentRunner.create_session.__code__.co_filename)

    async def test_localharness_subprocess_receives_oauth_headers_on_all_models_and_never_fails_api_key_gate(self):
        """Verifies that when authenticated via OAuth account (including CLI Process env),
        all models in HarnessConfig (TEXT and default IMAGE) carry only OAuth headers with
        empty api_key on the wire proto, and localharness subprocess env satisfies its
        internal startup check so InitializeConversation never asks for GEMINI_API_KEY."""
        import io
        import struct
        from unittest.mock import AsyncMock, MagicMock
        from google.antigravity.proto import localharness_pb2

        adapter = DummyAdapterServer(port=54323)
        bridge = runner.AgentRunner(lambda *_: None, adapter_server=adapter)
        with patch.object(runner, "Agent", CapturingAgent), patch.dict(
            os.environ,
            {"GOOGLE_OAUTH_ACCESS_TOKEN": "ya29.cli-process-token", "GEMINI_API_KEY": ""},
            clear=False,
        ):
            await bridge.create_session("cli-oauth", {
                "model": "gemini-3.8-flash",
                "provider": "google",
                "thinkingLevel": "high",
                "enableSubagents": False,
            })
            config = bridge.sessions["cli-oauth"].agent.config
            self.assertIsNone(config.api_key)
            # Only 1 TEXT model + 1 default IMAGE model (no duplicate shorthand TEXT model)
            text_models = [m for m in config.models if types.ModelType.TEXT in m.types]
            self.assertEqual(len(text_models), 1)
            for m_proto in build_models_proto(config.models):
                self.assertEqual(m_proto.gemini_api_endpoint.api_key, "")
                self.assertEqual(
                    m_proto.gemini_api_endpoint.http_headers["Authorization"],
                    "Bearer ya29.cli-process-token",
                )

            # Verify LocalConnectionStrategy.__aenter__ feeds localharness subprocess
            # the internal sentinel while keeping wire model protos key-free.
            strategy = config.create_strategy(tool_runner=None, hook_runner=None)
            output_cfg = localharness_pb2.OutputConfig(port=57329, api_key="ws-handshake")
            raw_out = output_cfg.SerializeToString()
            mock_proc = MagicMock()
            mock_proc.stdin = MagicMock()
            mock_proc.stdout = MagicMock()
            mock_proc.stderr = io.BytesIO(b"")
            mock_proc.stdout.read.side_effect = [struct.pack("<I", len(raw_out)), raw_out]

            mock_ws = MagicMock()
            mock_ws.send = AsyncMock()
            mock_ws.recv = AsyncMock(return_value="{}")
            mock_ws.close = AsyncMock()
            mock_ws.__aiter__.return_value = []

            with patch("subprocess.Popen", return_value=mock_proc) as mock_popen, patch(
                "websockets.connect", new=AsyncMock(return_value=mock_ws)
            ):
                await strategy.__aenter__()
                _, popen_kwargs = mock_popen.call_args
                self.assertEqual(popen_kwargs["env"]["GEMINI_API_KEY"], "oauth-header-only")
                written = mock_proc.stdin.write.call_args[0][0]
                in_cfg = localharness_pb2.InputConfig()
                in_cfg.ParseFromString(written[4:])
                self.assertEqual(in_cfg.env["GEMINI_API_KEY"], "oauth-header-only")
                await strategy._connection.disconnect()


if __name__ == "__main__":
    unittest.main(verbosity=2)
