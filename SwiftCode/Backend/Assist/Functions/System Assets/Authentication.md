# Authentication — Credential Kinds and Correct Transports

Assist deals with several **distinct** credential kinds. They are not
interchangeable, and each request path must use the mechanism its transport
actually requires.

## Credential kinds

1. **Google OAuth client configuration** — the OAuth *client ID* (and, where
   Google's token endpoint requires it, the *client secret*) that identifies
   SwiftCode to Google's authorization server. SwiftCode uses its own
   user-owned Desktop OAuth client as the sign-in default; overrides may come
   from Settings, environment, or Info.plist. A client ID is a public
   identifier, not a secret — but the client secret is a secret and must be
   treated as one.
2. **Google account session** — the OAuth access/refresh tokens obtained from
   the browser sign-in flow, stored securely (Keychain). Powers the
   Antigravity account flow. Sessions expire; refresh handles renewal, and
   expired/invalid sessions must surface honestly, never as a fabricated
   signed-in state.
3. **Direct Gemini API key** — a provider API key for direct Gemini API
   access, stored securely per-provider. Used only by the direct-Gemini
   transport.
4. **Antigravity SDK authentication** — whatever credential the Antigravity
   SDK's supported mechanism requires for the account flow (the authenticated
   Google account session above). Do not invent SDK auth APIs.
5. **Provider-specific API credentials** — OpenAI-compatible keys, Claude
   keys, local-model endpoints (often keyless), custom endpoint credentials.
   Each lives in the provider's own secure settings.

## Routing rules

- A request on the **Antigravity SDK path** uses the SDK's supported
  authentication (the signed-in Google account session). Do **not** demand a
  separate Gemini API key for this path.
- A request on the **direct Gemini path** validates and uses the configured
  Gemini API key. A Google account session is not a substitute.
- **Third-party / local / custom** paths use their own configured
  credentials or endpoints. A missing credential is a descriptive error, not
  a silent fallback to another provider — never switch providers in
  violation of the user's routing preference.
- Never label a request as "Antigravity" when another provider actually
  handles it.

## Secure handling

- Store secrets in the macOS Keychain (or env/secure stores for overrides).
  Never hardcode them in source, and never log tokens, keys, secrets, or
  full authorization headers.
- Diagnostics may show *which* credential kind was used and its state
  (present/missing/expired) — never the value.
- Validate missing or malformed configuration early with actionable
  guidance (e.g. where in Settings to paste a client secret), rather than
  failing deep in the request with an opaque provider error.

## Sign-in lifecycle states

The Google account UI must reflect the real states the implementation
exposes: not configured, signed out, in progress, authenticated, failed,
expired/invalid, and sign-out/credential removal where supported. Display
verified account information only when actually available. Advanced
low-level fields (OAuth Project ID, Client ID) belong in an Advanced
settings section and must remain a single source of truth with the live
authentication implementation.
