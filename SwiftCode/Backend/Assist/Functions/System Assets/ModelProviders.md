# ModelProviders.md — Provider Landscape (Capability Level)

Assist can reach models through several provider paths. The paths differ in how they
authenticate, what tool-calling they support, how they stream, and what context they
allow — but the agent's standards do not change between them.

---

## 1. Provider Paths

Assist abstracts the differences; the agent must still pick the right path and speak
its protocol honestly:

- **Antigravity SDK path (authenticated account flow).** Auth is a signed-in Google
  account via OAuth with the documented scopes. Requests on this path are
  *Antigravity* requests — and only requests on this path may be labeled as such.
- **Direct Gemini API key.** Key-based auth against the Gemini API. Same model family
  as Antigravity, different auth mechanism and often different quota/rate behavior.
- **OpenAI-compatible endpoints.** Any endpoint that speaks the OpenAI chat/completions
  protocol, including OpenRouter and self-hosted gateways. Auth is a bearer API key.
- **Claude and other external providers.** Provider-native APIs with their own key
  schemes, message shapes, and tool-calling conventions.
- **Local models.** Ollama, LM Studio, Apple Foundation Models — no network auth,
  latency and capability profiles differ sharply from cloud providers.
- **Custom endpoints.** User-configured providers with their own base URLs and
  credential kinds.

## 2. What Actually Differs Per Path

- **Auth mechanism:** OAuth session vs. bearer API key vs. no auth (local). Never
  cross them — an API key does not satisfy an OAuth-gated path and vice versa.
- **Tool-calling support varies.** Function-calling conventions, parallel tool-call
  support, and schema strictness differ by provider. Never assume a provider supports
  a tool-call shape another provider accepted; negotiate capability at session setup.
- **Streaming protocols differ.** Token delivery formats, keep-alive behavior, and
  cancellation semantics are provider-specific. The Streaming.md contract holds
  regardless — incremental, honest, never simulated.
- **Context windows differ.** Budget context for the active path; never assume the
  context of one provider applies to another.

## 3. Credential-Kind → Transport Matching

- Match the credential kind to the transport: OAuth credentials for OAuth flows, API
  keys for key flows. A mismatched credential produces confusing downstream failures.
- **Never label a non-Antigravity request as Antigravity.** Provider identity is a
  fact about the transport, not a branding choice.
- Credentials live in the Keychain, environment variables, or another secure store —
  never in code, logs, diffs, or chat.

## 4. Dynamic Model Discovery — Mandatory

- **Model discovery uses the real discovery mechanism** for the active provider: ask
  the provider (or its SDK/runtime) which models are currently available, then
  present and use those.
- **Never maintain a hardcoded model catalog as authoritative.** Static model lists
  go stale silently and mislead both the agent and the user. A static fallback list
  is acceptable only as a clearly-marked last resort when live discovery is
  unreachable — never as the source of truth.

## 5. Failover & Continuity

- When a provider rate-limits, exhausts quota, or fails, Assist may rotate credentials
  or fail over to an alternative path. A failover is **not a restart**:
  - Reuse the accumulated session trajectory and context history.
  - Inspect the live workspace state on disk as ground truth.
  - Continue directly from the last valid checkpoint — never repeat completed work.
- Report the switch transparently (which path is now active) rather than silently
  changing the model behind the user's back.
