<!-- system-index-depends: Authentication.md -->
# ModelProviders.md — Provider Landscape, Capability Matrix & Dynamic Discovery

Assist can reach models through several provider paths. The paths differ in how they authenticate, what tool-calling they support, how they stream, and what context they allow — but the agent's standards do not change between them.

---

## 1. Provider Paths & Architectures

Assist abstracts provider differences through `AssistAvailableModel` and `AssistModelRouter`; the agent must still pick the right path and speak its protocol honestly:

- **Antigravity SDK path (authenticated account flow).** Auth is a signed-in Google account via OAuth with `https://www.googleapis.com/auth/cloud-platform` scope. Requests on this path are *Antigravity* requests — and only requests on this path may be labeled as such.
- **Direct Gemini API key.** Key-based auth against the Gemini API (`GEMINI_API_KEY`). Same model family as Antigravity, different auth mechanism and often different quota/rate behavior.
- **OpenAI-compatible endpoints (`LocalOpenAIAgentConfig`).** Any endpoint that speaks the OpenAI chat/completions protocol, including OpenRouter, LM Studio, and self-hosted gateways. Auth is a bearer API key.
- **Claude and other external providers.** Provider-native APIs with their own key schemes, message shapes, and tool-calling conventions.
- **Local offline models.** Ollama (`http://localhost:11434/v1`), LM Studio, Apple Foundation Models — no network auth, latency and capability profiles differ sharply from cloud providers.
- **Custom endpoints.** User-configured providers with their own base URLs and credential kinds.

---

## 2. What Actually Differs Per Path

- **Auth mechanism:** OAuth session vs. bearer API key vs. no auth (local). Never cross them — an API key does not satisfy an OAuth-gated path and vice versa.
- **Tool-calling support varies:** Function-calling conventions, parallel tool-call support, and schema strictness differ by provider. Never assume a provider supports a tool-call shape another provider accepted; negotiate capability at session setup.
- **Thinking Levels (`ThinkingLevel`):** Models may support configurable thinking levels (`off`, `low`, `high`) exposed in UI pickers.
- **Streaming protocols differ:** Token delivery formats, keep-alive behavior, and cancellation semantics are provider-specific. The `Streaming.md` contract holds regardless — incremental, honest, never simulated.
- **Context windows differ:** Budget context for the active path; never assume the context of one provider applies to another.

---

## 3. Credential-Kind → Transport Matching

- Match the credential kind to the transport: OAuth credentials for OAuth flows, API keys for key flows. A mismatched credential produces confusing downstream failures.
- **Never label a non-Antigravity request as Antigravity.** Provider identity is a fact about the transport, not a branding choice.
- Credentials live in the Keychain (`KeychainService`), environment variables, or another secure store — never in code, logs, diffs, or chat.

---

## 4. Dynamic Model Discovery & Hidden Provider Filtering

- **Dynamic Model Discovery (`AssistModelDiscoveryService`):** Asks live provider endpoints for currently available models. Model discovery is decoupled from message submission to prevent blocking user turns.
- **Provider Filtering (`hiddenProviderNames`):** Providers can be persistently hidden or restored via `hiddenProviderNames` (persisted under `UserDefaults` key `com.swiftcode.assist.hidden_provider_names`), filtering visible model options in `AssistSettingsView`.
- **Default Model Safeguard:** Antigravity SDK default models (`Self.sdkDefaultModelIDs`) are explicitly treated as configured, agentic, and capable of tool calling regardless of whether discovery calls succeed, preventing unintended model shifts.

---

## 5. Quotas, Failover & Continuity

- **Quota Tracking (`AntigravityQuotaService`):** Tracks live account limits and reset countdowns displayed in `AntigravityLimitsModelsUI`.
- When a provider rate-limits, exhausts quota, or fails, `AssistModelRouter` rotates credentials or fails over to an alternative path. A failover is **not a restart**:
  - Reuse the accumulated session trajectory and context history.
  - Inspect the live workspace state on disk as ground truth.
  - Continue directly from the last valid checkpoint — never repeat completed work.
- Report the switch transparently (which path is now active) rather than silently changing the model behind the user's back.
