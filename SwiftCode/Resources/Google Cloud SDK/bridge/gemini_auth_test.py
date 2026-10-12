#!/usr/bin/env python3
"""Unit tests for the Gemini account-first auth contract in agent_runner.py.

The bridge module cannot be imported directly in this environment (the
vendored google.antigravity SDK ships compiled extensions for a different
interpreter), so the tests load the real `resolve_gemini_auth`,
`GeminiAuthConfigError`, and `USER_PROJECT_HEADER` definitions out of the
shipped agent_runner.py via AST and execute them in isolation. The logic
under test is the exact code that ships; the test fails if the definitions
cannot be found.

Covers (spec section 14):
  1. Account authentication is the default provider mode (oauth_token ->
     Developer API, never silently converted to API-key mode).
  2. API-key mode is explicit and separate (api_key only -> api_key mode).
  3. An OAuth token is never placed in the api_key slot (disjoint modes).
  4. Missing quota project on the OAuth path is an actionable error, not a
     fabricated project ("-") and not a silent Vertex reroute.
  5. Explicit vertex=True requires an explicit project and location.
  6. No credentials at all is an actionable error.

Covers (no-auth-errors hardening):
  7. Turn-error guidance is narrowed to scope-specific failures only (C-5):
     quota/billing 403s, PERMISSION_DENIED, 401s and API-key errors pass
     through verbatim for Swift's classifier.
  8. Custom-provider models without an explicit endpoint fail closed with an
     actionable error instead of silently routing to localhost (H-5).

Run: python3 "SwiftCode/Resources/Google Cloud SDK/bridge/gemini_auth_test.py"
"""

from __future__ import annotations

import ast
import os
import sys
import unittest

BRIDGE_DIR = os.path.dirname(os.path.abspath(__file__))
AGENT_RUNNER = os.path.join(BRIDGE_DIR, "agent_runner.py")

_WANTED = {
    "USER_PROJECT_HEADER",
    "GeminiAuthConfigError",
    "resolve_gemini_auth",
    "_wrap_turn_error",
    "_require_custom_endpoint",
}


def _load_auth_logic():
    """Exec the real auth definitions from the shipped agent_runner.py."""
    with open(AGENT_RUNNER, "r", encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=AGENT_RUNNER)
    wanted_nodes = [
        node
        for node in tree.body
        if isinstance(node, (ast.Assign, ast.ClassDef, ast.FunctionDef))
        and (
            (isinstance(node, ast.Assign)
             and any(isinstance(t, ast.Name) and t.id in _WANTED for t in node.targets))
            or (isinstance(node, (ast.ClassDef, ast.FunctionDef))
                and node.name in _WANTED)
        )
    ]
    found = {
        node.name if isinstance(node, (ast.ClassDef, ast.FunctionDef))
        else node.targets[0].id
        for node in wanted_nodes
    }
    missing = _WANTED - found
    if missing:
        raise AssertionError(
            "agent_runner.py no longer defines %s; auth contract moved?" % sorted(missing)
        )
    namespace: dict = {"os": os}
    module = ast.Module(body=wanted_nodes, type_ignores=[])
    exec(compile(module, AGENT_RUNNER, "exec"), namespace)  # noqa: S102 (test harness)
    return namespace


_AUTH = _load_auth_logic()
USER_PROJECT_HEADER = _AUTH["USER_PROJECT_HEADER"]
GeminiAuthConfigError = _AUTH["GeminiAuthConfigError"]
resolve_gemini_auth = _AUTH["resolve_gemini_auth"]
_wrap_turn_error = _AUTH["_wrap_turn_error"]
_require_custom_endpoint = _AUTH["_require_custom_endpoint"]


class ResolveGeminiAuthTests(unittest.TestCase):
    def test_api_key_only_selects_api_key_mode(self):
        mode, project, location = resolve_gemini_auth(
            api_key="AIza-test-key",
            oauth_token=None,
            vertex=False,
            project=None,
            location=None,
            http_headers={},
        )
        self.assertEqual(mode, "api_key")

    def test_oauth_token_selects_oauth_developer_api_mode(self):
        # Account authentication is the default mode when an OAuth token is
        # present: Developer API, never silently converted to API-key mode.
        mode, project, location = resolve_gemini_auth(
            api_key=None,
            oauth_token="ya29.test-token",
            vertex=False,
            project="my-quota-project",
            location=None,
            http_headers={},
        )
        self.assertEqual(mode, "oauth")
        self.assertEqual(project, "my-quota-project")

    def test_oauth_uses_user_project_header_when_present(self):
        mode, project, _ = resolve_gemini_auth(
            api_key=None,
            oauth_token="ya29.test-token",
            vertex=False,
            project=None,
            location=None,
            http_headers={USER_PROJECT_HEADER: "header-project"},
        )
        self.assertEqual(mode, "oauth")
        self.assertEqual(project, "header-project")

    def test_oauth_without_quota_project_is_actionable_error(self):
        # Must NOT fabricate a project ("-") and must NOT silently reroute to
        # Vertex: the operator has to configure a quota project.
        with self.assertRaises(GeminiAuthConfigError) as ctx:
            resolve_gemini_auth(
                api_key=None,
                oauth_token="ya29.test-token",
                vertex=False,
                project=None,
                location=None,
                http_headers={},
            )
        message = str(ctx.exception)
        self.assertIn("quota project", message)
        self.assertIn("x-goog-user-project", message)
        self.assertNotIn('"-"', message)

    def test_oauth_with_explicit_vertex_requires_project_and_location(self):
        mode, project, location = resolve_gemini_auth(
            api_key=None,
            oauth_token="ya29.test-token",
            vertex=True,
            project="my-gcp-project",
            location="us-central1",
            http_headers={},
        )
        self.assertEqual(mode, "vertex")
        self.assertEqual(project, "my-gcp-project")
        self.assertEqual(location, "us-central1")

    def test_vertex_without_project_is_actionable_error(self):
        with self.assertRaises(GeminiAuthConfigError) as ctx:
            resolve_gemini_auth(
                api_key=None,
                oauth_token="ya29.test-token",
                vertex=True,
                project=None,
                location="us-central1",
                http_headers={},
            )
        self.assertIn("project", str(ctx.exception).lower())

    def test_vertex_without_location_is_actionable_error(self):
        with self.assertRaises(GeminiAuthConfigError) as ctx:
            resolve_gemini_auth(
                api_key=None,
                oauth_token="ya29.test-token",
                vertex=True,
                project="my-gcp-project",
                location=None,
                http_headers={},
            )
        self.assertIn("location", str(ctx.exception).lower())

    def test_no_credentials_is_actionable_error(self):
        with self.assertRaises(GeminiAuthConfigError) as ctx:
            resolve_gemini_auth(
                api_key=None,
                oauth_token=None,
                vertex=False,
                project=None,
                location=None,
                http_headers={},
            )
        self.assertIn("API key", str(ctx.exception))

    def test_blank_strings_treated_as_missing(self):
        with self.assertRaises(GeminiAuthConfigError):
            resolve_gemini_auth(
                api_key="   ",
                oauth_token="",
                vertex=False,
                project=None,
                location=None,
                http_headers={},
            )

    def test_env_project_fallback_for_oauth(self):
        os.environ["GOOGLE_CLOUD_PROJECT"] = "env-quota-project"
        try:
            mode, project, _ = resolve_gemini_auth(
                api_key=None,
                oauth_token="ya29.test-token",
                vertex=False,
                project=None,
                location=None,
                http_headers={},
            )
        finally:
            del os.environ["GOOGLE_CLOUD_PROJECT"]
        self.assertEqual(mode, "oauth")
        self.assertEqual(project, "env-quota-project")

    def test_vertex_with_api_key_is_express_mode(self):
        # Explicit Vertex + API key (no OAuth) is Vertex Express mode:
        # project/location are optional, never fabricated.
        mode, project, location = resolve_gemini_auth(
            api_key="AIza-test-key",
            oauth_token=None,
            vertex=True,
            project=None,
            location=None,
            http_headers={},
        )
        self.assertEqual(mode, "vertex")

    def test_both_credentials_prefers_account_mode(self):
        # Defense in depth: if both ever arrive, the account path wins so an
        # OAuth session is never silently downgraded to API-key mode.
        mode, _, _ = resolve_gemini_auth(
            api_key="AIza-test-key",
            oauth_token="ya29.test-token",
            vertex=False,
            project="my-quota-project",
            location=None,
            http_headers={},
        )
        self.assertEqual(mode, "oauth")


class WrapTurnErrorTests(unittest.TestCase):
    """C-5: only scope-specific failures get re-auth guidance."""

    def test_scope_insufficient_is_relabeled(self):
        err = (
            "agent executor error: Error 403, Message: Request had insufficient "
            "authentication scopes., Status: PERMISSION_DENIED, Details: "
            "[reason:ACCESS_TOKEN_SCOPE_INSUFFICIENT]"
        )
        wrapped = _wrap_turn_error(err)
        self.assertIn("Authentication error", wrapped)
        self.assertIn(err, wrapped)  # original preserved for Swift's classifier
        self.assertIn("re-authenticate", wrapped)

    def test_quota_403_passes_through_verbatim(self):
        # A valid token can 403 on quota/billing: re-authenticating cannot fix
        # it, so the bridge must not suggest it.
        err = "Error 403: Quota exceeded for quota metric 'GenerateContent Requests'"
        self.assertEqual(_wrap_turn_error(err), err)

    def test_billing_permission_denied_passes_through(self):
        err = "Error 403 PERMISSION_DENIED: The caller does not have permission (billing disabled)"
        self.assertEqual(_wrap_turn_error(err), err)

    def test_401_passes_through_verbatim(self):
        err = "Error 401 UNAUTHENTICATED: Request had invalid authentication credentials"
        self.assertEqual(_wrap_turn_error(err), err)

    def test_invalid_api_key_passes_through(self):
        err = "API_KEY_INVALID: API key not valid. Please pass a valid API key."
        self.assertEqual(_wrap_turn_error(err), err)

    def test_incidental_403_mention_not_relabeled(self):
        # Tool output merely mentioning "403" must not be relabeled as an
        # auth failure (old false-positive).
        err = "tool fetch_url returned HTTP 403 from https://example.com/data"
        self.assertEqual(_wrap_turn_error(err), err)

    def test_non_auth_error_passes_through(self):
        err = "model returned an empty response"
        self.assertEqual(_wrap_turn_error(err), err)


class RequireCustomEndpointTests(unittest.TestCase):
    """H-5: custom-provider models without an explicit endpoint fail closed."""

    def test_custom_without_endpoint_is_actionable_error(self):
        with self.assertRaises(GeminiAuthConfigError) as ctx:
            _require_custom_endpoint(provider="custom", model="my-model", base_url="")
        message = str(ctx.exception)
        self.assertIn("my-model", message)
        self.assertIn("endpoint", message.lower())

    def test_custom_with_blank_endpoint_is_actionable_error(self):
        with self.assertRaises(GeminiAuthConfigError):
            _require_custom_endpoint(provider="custom", model="my-model", base_url="   ")

    def test_custom_provider_case_insensitive(self):
        with self.assertRaises(GeminiAuthConfigError):
            _require_custom_endpoint(provider="Custom", model="my-model", base_url="")

    def test_custom_with_explicit_endpoint_is_allowed(self):
        # Saved custom endpoints carry an explicit base_url: unaffected.
        _require_custom_endpoint(
            provider="custom", model="my-model", base_url="https://api.example.com/v1"
        )

    def test_local_providers_keep_their_defaults(self):
        # ollama/lmstudio localhost defaults are intentional, not guessing.
        _require_custom_endpoint(provider="ollama", model="llama3", base_url="")
        _require_custom_endpoint(provider="lmstudio", model="qwen", base_url="")

    def test_gemini_without_base_url_is_allowed(self):
        _require_custom_endpoint(provider="gemini", model="gemini-2.5-flash", base_url="")
        _require_custom_endpoint(provider="google", model="gemini-2.5-flash", base_url="")


if __name__ == "__main__":
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(unittest.defaultTestLoader.loadTestsFromName("__main__"))
    sys.exit(0 if result.wasSuccessful() else 1)
