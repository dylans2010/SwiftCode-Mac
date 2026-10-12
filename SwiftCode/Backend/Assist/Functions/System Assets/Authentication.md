<!-- system-index-depends: Safeguards.md -->
# Authentication — Credential Kinds and Correct Transports

Assist deals with several **distinct** credential kinds. They are not interchangeable, and each request path must use the mechanism its transport actually requires.

---

## 1. Credential Kinds

1. **Google OAuth client configuration** — the OAuth *client ID* (and, where Google's token endpoint requires it, the *client secret*) that identifies SwiftCode to Google's authorization server. SwiftCode uses its own user-owned Desktop OAuth client as the sign-in default; overrides may come from Settings, environment, or Info.plist. A client ID is a public identifier, not a secret — but the client secret is a secret and must be treated as one.
2. **Google account session** — the OAuth access/refresh tokens obtained from the browser sign-in flow, stored securely in Keychain. Powers the Antigravity account flow using `https://www.googleapis.com/auth/cloud-platform` scope (along with standard identity scopes `openid`, `email`, `profile`). Note: `https://www.googleapis.com/auth/generative-language` is NOT a valid OAuth scope URI on Google's server. Sessions expire; refresh handles renewal, and expired/invalid sessions must surface honestly, never as a fabricated signed-in state.
3. **Direct Gemini API key** — a provider API key (`GEMINI_API_KEY`) for direct Gemini API access, stored securely per-provider. Used only by the direct-Gemini transport.
4. **Antigravity SDK authentication** — whatever credential the Antigravity SDK's supported mechanism requires for the account flow (the authenticated Google account session above). In `agent_runner.py`, when a user is authenticated via Google OAuth (`oauth_token` present without `api_key`), execution routes through `VertexEndpoint` (`use_vertex = vertex or bool(oauth_token and not api_key)`).
5. **Provider-specific API credentials** — OpenAI-compatible keys, Claude keys, local-model endpoints (often keyless), custom endpoint credentials. Each lives in the provider's own secure settings.

---

## 2. Routing Rules & Runtime Session Probe

- A request on the **Antigravity SDK path** uses the SDK's supported authentication (the signed-in Google account session). Do **not** demand a separate Gemini API key for this path.
- A request on the **direct Gemini path** validates and uses the configured Gemini API key. A Google account session is not a substitute.
- **Strict Mode Guard:** `buildSDKConfiguration` strictly checks `googleAuthMode == "google_oauth"` in addition to `GoogleAccountAuthService.shared.isAuthenticated` before attaching OAuth tokens, preventing unintended override of configured API keys when in `api_key` mode.
- **Runtime Session Probe (`verifyRuntimeSession`):** Probes the Antigravity runtime to validate OAuth session usability before message dispatch.
- **Third-party / local / custom** paths use their own configured credentials or endpoints. A missing credential is a descriptive error, not a silent fallback to another provider — never switch providers in violation of the user's routing preference.
- Never label a request as "Antigravity" when another provider actually handles it.

---

## 3. Secure Handling & Key Isolation

- Store secrets in the macOS Keychain (`KeychainService`) or env/secure stores for overrides. Never hardcode them in source, and never log tokens, keys, secrets, or full authorization headers.
- Diagnostics may show *which* credential kind was used and its state (present/missing/expired) — never the value.
- URL Protocol Normalization: `model_adapter_server.py` and `GoogleCloudSDKConfiguration.swift` normalize target base URLs to guarantee `http://` or `https://` schemes, preventing `httpcore`/`httpx` `UnsupportedProtocol` errors.
- Validate missing or malformed configuration early with actionable guidance (e.g. where in Settings to paste a client secret), rather than failing deep in the request with an opaque provider error.

---

## 4. Sign-In Lifecycle States

The Google account UI must reflect the real states the implementation exposes: not configured, signed out, in progress, authenticated, failed, expired/invalid, and sign-out/credential removal where supported. Display verified account information only when actually available. Advanced low-level fields (OAuth Project ID, Client ID) belong in an Advanced settings section and must remain a single source of truth with the live authentication implementation.
