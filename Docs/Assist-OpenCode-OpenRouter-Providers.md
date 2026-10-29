# Assist Providers: OpenCode & OpenRouter

Implemented on `main` (see commit history for the exact change). This note
records the audit, the integration decision, and what is still unverified
because this environment has no macOS/Xcode build and no live provider
credentials. It is documentation only — nothing in `Docs/` is bundled
into the application.

## Audit findings (what already existed)

- **The live Assist loop is `AssistAgentSession`.** It builds a turn prompt
  from the real system prompt (`AssistManager.getSystemPrompt()` →
  `SystemIndexService.baselinePrompt()` from `AgentSystemAsset.md` and
  related system assets), task instructions, history, skills, and the
  serialized schemas of `AssistToolRegistry` tools, then streams it
  through `AgentModelAdapter.streamQueryModel(prompt:modelId:)`. The
  model is expected to answer with a JSON `toolId`/`input`/`explanation`
  (or `finalResponse`). The session validates the tool against the
  registry, checks phase metadata via `AssistToolRouter`, executes the
  real tool through `AssistExecutionEngine`/`AssistContext` (which carries
  the permissions manager), and feeds the result back on the next turn.
  Streaming, cancellation (`Task.isCancelled` / `isCancelled`), and
  error propagation are already part of that loop.
- **Model routing was identifier-driven, not provider-selected.**
  `LLMService.provider(for:)` infers the provider from the model id
  (a `/` means OpenRouter), and `AgentModelAdapter.specification(for:)`
  infers a provider from name fragments. There was no explicit,
  persisted provider choice for OpenRouter or OpenCode in Assist
  Settings — OpenRouter worked only implicitly, by picking a `/` model
  id from the Available Models list.
- **OpenRouter already had three overlapping native paths**
  (`LLMService` OpenAI-compatible chat completions,
  `OpenRouterClient`, `OpenRouterService`) plus the deprecated
  `AgentOrchestrator`/`AIProvider` native-function-call path used by
  `AgentChatView`. None of them owned provider-level concerns such as a
  connection test or a no-substitution model validation.
- **OpenCode did not exist anywhere in the repo.** No client, no
  settings, no model ids.
- **Credentials already had a pattern:** OpenRouter keys resolve via
  `APIKeyManager` → Keychain (`openrouter_api_key`), never hardcoded.
  OpenCode needs no SwiftCode-managed key at all (see below).
- **Provider selection already had a key:** `assist.selectedProvider`
  (raw value of `AssistModelProvider`), read by `AssistAgent`,
  `AssistManager`, and `TasksAIPlanner`. The new Settings section reuses
  it instead of inventing another persistence mechanism. The selected
  model id remains the routing source of truth for a running session.

## Decision: native HTTP adapters, no JS runtimes, no TS SDKs

Both documented SDKs are TypeScript (`@opencode-ai/sdk`,
`@openrouter/agent`). Importing either into Swift would require
bundling a Node/Bun runtime, with signing/notarization, startup-time,
resource, and lifecycle costs — and, for OpenRouter, it would hand the
tool-calling loop to the SDK, which is exactly what this task forbids.
Both SDKs speak plain HTTP under the hood, so Swift speaks HTTP
directly:

- **OpenRouter** → its OpenAI-compatible
  `https://openrouter.ai/api/v1/chat/completions` endpoint, through the
  existing `LLMService`/`OpenRouterClient` path. No new runtime, no
  new loop. `OpenRouterAssistProvider` adds only the missing
  provider-level operations: a connection test against live `/models`
  (401/402/429 mapped to specific errors) and a model validation that
  throws `.modelNotFound` instead of substituting another model. Native
  tool-calling support (`supported_parameters` containing `tools`) is
  reported in Settings; it is not a gate, because Assist's JSON tool
  protocol works for models without native function calling, and
  gating on it would either block working models or invite silent
  substitution.
- **OpenCode** → the OpenCode server's HTTP + SSE API
  (`GET /global/health`, `POST /session`,
  `POST /session/{id}/prompt_async`, `GET /event?directory=…`,
  `POST /session/{id}/abort`, `GET /config/providers`), implemented
  natively in `OpenCodeClient`. No JS runtime, no bundled server.

## How OpenCode preserves SwiftCode's ownership of tools

This is the subtle part, and it is enforced in three layers:

1. **System prompt:** `AssistAgentSession` now passes its real asset
   system prompt to `streamQueryModel(systemPrompt:directory:)`. Only
   the OpenCode branch uses it, in the prompt's `system` field, so an
   OpenCode default never replaces SwiftCode's prompt. Other providers
   keep their existing behaviour exactly (the prompt they already
   received already contains the system prompt inline).
2. **Model identity:** OpenCode models are stored as
   `opencode:<providerID>/<modelID>`. The prefix is load-bearing: a
   bare `anthropic/claude-…` id routes to OpenRouter, and a bare
   `claude-…` name would match the Anthropic branch of
   `specification(for:)`. `AgentModelAdapter.specification(for:)`
   checks the prefix first, and `AssistAgentSession`'s validation
   health-checks the OpenCode server instead of falling through to an
   OpenRouter key check.
3. **Tools:** SwiftCode sessions always name the `swiftcode` agent,
   which must be configured server-side with every permission denied
   (definition shown in Settings and in
   `OpenCodeConfiguration.swiftcodeAgentDefinition`). With tools
   denied, the server acts as a pure model: it returns text, the
   session parses the JSON tool request, and SwiftCode validates,
   permission-checks, executes, and returns the result — the same loop
   as every other provider. `OpenCodeClient` additionally fails a run
   closed if a tool part ever appears on the event stream, instead of
   surfacing a provider-executed result as a SwiftCode tool result.
   Sessions are directory-scoped to the workspace root, streamed via
   `/event`, and aborted on cancellation.

## Files changed

- `SwiftCode/Backend/Assist/AssistProviderConfiguration.swift` (new):
  `OpenCodeModelID`/`OpenCodeModel`, `OpenCodeConfiguration`
  (UserDefaults-backed server URL, agent name, managed-server opt-in),
  `AssistProviderSelection` (persisted `assist.selectedProvider`).
- `SwiftCode/Backend/Assist/OpenCodeClient.swift` (new): native actor
  client — health, model discovery from live `/config/providers`
  (defensive parsing, no hardcoded catalog), session create,
  `prompt_async`, SSE text deltas, idle/error/tool handling, abort on
  cancellation, opt-in managed `opencode serve` on 127.0.0.1 only.
- `SwiftCode/Backend/Assist/OpenRouterAssistProvider.swift` (new):
  connection test, model validation, tool-calling support reporting.
- `SwiftCode/Backend/Assist/AssistModels.swift`:
  `AssistModelProvider.openCode`; its stored-key provider is `nil`
  (OpenCode holds no SwiftCode-managed key); `AssistLLMService`
  fails closed for `.openCode` so the legacy LLM path can never
  silently route an OpenCode model to OpenRouter.
- `SwiftCode/Backend/Assist/AgentModelAdapter.swift`: `opencode:`
  specification branch (checked before name-fragment branches) and
  the `streamQueryModel` OpenCode branch (new optional
  `systemPrompt`/`directory` parameters, backward compatible).
- `SwiftCode/Backend/Assist/AssistAgentSession.swift`: OpenCode
  validation (server health instead of an API-key check) and passing
  the real system prompt + workspace root to the model stream.
- `SwiftCode/Backend/Assist/AssistAgent.swift`,
  `TasksAIPlanner.swift`,
  `Assist Frameworks/_AssistCriticalValidationEngine.swift`,
  `Tools/AssistAutoFixErrorsTool.swift`,
  `Tools/AssistExplainCodeTool.swift`,
  `Tools/AssistRefactorTool.swift`: stored-key lookups now go through
  `AssistModelProvider.storedAPIKey()`, which returns `nil` for
  OpenCode instead of borrowing another provider's key.
- `SwiftCode/Views/Settings/AssistSettingsView.swift`: the
  "OpenRouter & OpenCode" section (see below).
- `SwiftCode/Backend/Assist/AssistProviderTests.swift` (new, wired
  into `AssistRuntimeTestSuite`): offline cases for id parsing,
  specification routing, catalog/event parsing, configuration
  persistence, key isolation + fail-closed routing, persisted
  provider round-trip, and OpenRouter id validation.
- `SwiftCode.xcodeproj/project.pbxproj`: the three new Swift files
  registered in the Assist group and the app target's Sources phase.

## Settings

Assist Settings → **OpenRouter & OpenCode** (after Assist
Configuration):

- **OpenRouter:** key status (key itself is entered in API Keys, not
  here), Test connection, Discover models (live `/models`, first 50
  shown with Select), Validate selected model (existence + native
  tool-calling support). Selecting a model sets
  `selectedAssistModelID` and `assist.selectedProvider = OpenRouter`.
- **OpenCode:** server URL (default `http://127.0.0.1:4096`), agent
  name (default `swiftcode`), Managed server toggle (off by default),
  Save, Check server, Discover models (live server catalog), manual
  `provider/model` entry, and the required `swiftcode` agent
  definition with install instructions. Selecting a model stores
  `opencode:provider/model` and sets
  `assist.selectedProvider = OpenCode`, and drops any cached OpenCode
  sessions so a new selection never resumes an old session.
- Switching providers never reuses the other provider's credentials,
  model id, or session: the model id is the routing key, OpenCode
  holds no SwiftCode key, and OpenCode sessions are reset on switch.

## Server setup required for OpenCode (user action)

1. Save the agent definition from Settings as
   `.opencode/agent/swiftcode.md` in the project (or
   `~/.config/opencode/agent/swiftcode.md` globally).
2. Run `opencode serve --hostname 127.0.0.1 --port 4096`
   (or enable Managed server in Settings, which starts the same
   command from the `opencode` binary on PATH).
3. Configure at least one model provider inside OpenCode itself;
   SwiftCode never sees those credentials.

If the `swiftcode` agent is missing, prompts fail with a specific
agent-not-found error instead of running under the default agent.
If the server is unreachable, sessions fail in validation with the
exact start command instead of falling back to another provider.

## Verification performed here

- Static review of every edited call site (no Xcode in this
  environment, so no build or test run is claimed).
- New test cases are offline and deterministic by design; they cover
  the routing-critical logic (prefix parsing, specification routing,
  catalog/event parsing, key isolation, fail-closed LLM path).
- The three new files were registered in the `.pbxproj` (Assist
  group + app Sources phase) with fresh ids, verified by grep.

## Known scope limits (by design, not oversights to hide)

- **Dispatcher precedence is unchanged.** `AssistManager.sendMessage`
  still routes first to SwiftCode Cloud models, then to the Meta
  system, then to the Google Cloud/Antigravity runtime when that
  system (or a Google OAuth session) is active. OpenCode/OpenRouter
  selections therefore take effect for **Native Assist**; they do not
  override an active Google Cloud or Meta Assist system. Changing
  that precedence would alter existing providers' behaviour and was
  deliberately not done.
- **OpenCode models do not appear in `AssistModelDiscoveryService`'s
  Available Models list.** That service runs per-provider discovery
  concurrently with its own provider types; the supported OpenCode
  discovery path is the new Settings section (live server catalog +
  manual entry). Adding an OpenCode discovery provider there is a
  follow-up, not a silent omission in the Settings flow.
- **The deprecated `AgentOrchestrator`/`AIProvider` path is untouched.**
  It already defaults to OpenRouter via `OpenRouterAIProvider`, and
  it is deprecated in favour of `AssistAgentSession`. No new provider
  was wired into a deprecated path.

## Not verified — Mac checklist for Dylan

1. Build the app target in Xcode; fix any strict-concurrency or
   SwiftUI diagnostics this environment could not surface (notably
   `OpenCodeClient`'s `AsyncBytes` capture in the SSE task and the
   new Settings view's MainActor accesses).
2. Run the in-app Assist runtime suite and confirm the eight new
   provider cases pass.
3. OpenRouter (with a real key): Test connection, Discover models,
   select a model, run an Assist task that calls a tool, confirm the
   tool executes through SwiftCode and its result returns to the
   model, then cancel mid-stream and confirm the stream stops.
4. OpenCode (with a real server + the `swiftcode` agent installed):
   Check server, Discover models, select one, run the same tool task
   end to end; confirm no OpenCode-side tool execution occurs, and
   that removing the agent produces the agent-not-found error.
5. Confirm the OpenCode `/event` SSE shape against the installed
   server version (event type/property names have varied across
   versions); if the installed version uses `/global/event`, adjust
   `OpenCodeClient.endpointURL` usage for the stream only.
6. Confirm provider switching (OpenRouter ↔ OpenCode ↔ an existing
   provider) restores correctly after relaunch, with no stale model
   or session.
