# Assist providers (Wave 9)

The coding assistant's providers on Ycode's `AssistantProvider` host
(`ycode/Sources/YcodeAssistant/`): OpenRouter, OpenCode, Hermes, Apple
Foundation Models, and SwiftCode Cloud. Each provider is a `ProviderKind`
case wired by `AssistantBackends.provider(_:)`; models are discovered
live from the provider — Ycode ships no model list. Credentials live in
the `SecretStore` (Keychain on macOS); no key, token, or secret appears
in source, tests, or specs. Legacy behaviour is ported from Dylan's own
Legacy code (direct porting authorised under MIT); the Ycode
implementation is written from this spec plus the host's public patterns.

The TypeScript SDK provider paths (`OpenRouterSDKProvider` +
`OpenCodeSDKProvider` + `SDKHosts/*-bridge.mjs`) are explicitly **not**
ported in this wave — they belong to the later SDK-platform wave.

## 1. OpenRouter

OpenRouter is the coding assistant's remote-model provider: any model
listed by `https://openrouter.ai/api/v1/models`, reached through
OpenRouter's OpenAI-compatible `POST /chat/completions`, authorized by
an API key the user enters. This spec covers the Ycode port of
Legacy's native (non-SDK) OpenRouter Assist path onto Ycode's
`AssistantProvider` host. The TypeScript SDK path
(`OpenRouterSDKProvider` + `SDKHosts/openrouter-bridge.mjs`) is
explicitly **not** ported; see §6.

## 1. Legacy behaviour

Legacy reaches OpenRouter through three overlapping layers; the slice
ports the Assist-owned behaviour, not all three:

| Legacy file | Role in Legacy | Ported here |
|---|---|---|
| `SwiftCode/Backend/AI/OpenRouterAIProvider.swift` | Thin `AIProvider` wrapper delegating agent turns to `OpenRouterClient` | Yes — the agent-turn entry point becomes `OpenRouterProvider.send(_:)` |
| `SwiftCode/Backend/AI/OpenRouterClient.swift` | Actor: key resolution, `fetchModels` (with an in-memory cache that never expires), direct streaming chat, agent-turn streaming with tool calls, SSE decoding | Yes — key handling, model fetch, streaming, SSE, tool-call decoding (adapted to the host's `ChatEvent`, which has no tool-call event; see §4) |
| `SwiftCode/Backend/AI/OpenRouterRequestBuilder.swift` | Builds the agent request body: model, messages (text / image_url / tool_calls / tool role), `stream: true`, `tools` when non-empty | Yes, in adapted form — the host's `ChatRequest` carries plain-text messages only, so the body is model + messages + `stream: true` (+ generation options); image and tool-call message encoding has no host equivalent and is not ported |
| `SwiftCode/Backend/Assist/OpenRouterAssistProvider.swift` | The Assist entry point: connection test, real-model validation, native tool-calling support detection | Yes — `testConnection()`, `validateModel(_:)`, `OpenRouterToolCallingSupport` |
| `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` (OpenRouter part only, `discoverOpenRouterModels`) | Dynamic discovery: resolves the key, calls `OpenRouterClient.fetchModels()`, maps each model to an `AssistAvailableModel` (display name, context window, `supportsToolCalling: true` for every model, vision guessed from the id) | Yes, in adapted form — dynamic discovery only. The discovery service's **bundled/seed catalog fallback is deliberately not ported**: on discovery failure this provider reports the failure honestly instead of showing models that were never listed |

Adjacent Legacy code **not** in this slice: `SwiftCode/Services/OpenRouterService.swift`
(the older pre-Assist service layer: non-streaming `chat`, streaming
`streamChat`, its own `fetchModels` over the same endpoints) and
`SwiftCode/Core/AI/OpenRouterModel.swift` (the model record it decodes:
`id`, `name`, `description`, `contextLength`, `pricing`).

### 1.1 Endpoints and auth

- Base URL: `https://openrouter.ai/api/v1`.
- `GET /models` — live model list. Legacy sends the request with
  `Authorization: Bearer <key>` when a key is stored, and without it
  when none is (the endpoint answers unauthenticated); the Ycode
  port requires a key first and reports `.signedOut` without one
  (§2), matching the host's provider-availability contract.
- `POST /chat/completions` — chat completions, `stream: true`,
  server-sent events. Legacy reads `data: ` lines until `data:
  [DONE]`, and surfaces a JSON `{"error": {"message": ...}}` payload
  found inside the stream as an error.
- The key is resolved from secure storage (Legacy checks
  `APIKeyManager` for the OpenRouter service, then the Keychain under
  its OpenRouter key, then the hyphenated `openrouter-api-key` key).
  It is never logged or returned; Legacy's audit logging records only
  pass/fail and a masked `first4...last4` form, which the port does
  not reproduce (the port logs nothing about the key at all).

### 1.2 Model discovery

- Dynamic-first: the list always comes from a live `GET /models`.
  The response shape is `{"data": [{id, name, description,
  context_length, pricing, architecture, supported_parameters, ...}]}`.
- Legacy's `OpenRouterModel` decodes `id`, `name`, `description`,
  `contextLength` (`context_length`), and `pricing` (`prompt` /
  `completion`, as strings).
- Legacy's discovery service maps each discovered model with
  `contextWindow = contextLength ?? 128000` — a guessed default when
  the endpoint does not report one. **The port does not guess**: a
  model with no `context_length` has `contextWindow == nil`.
- Legacy's discovery service marks every discovered model
  `supportsToolCalling: true` and guesses vision support from the
  model id (substrings such as `vision`). **The port does neither**:
  tool-calling support comes from the per-model detection in §1.4,
  and vision is not inferred from identifiers.
- Legacy's `OpenRouterClient` caches the fetched list in memory with
  no expiry. The port caches for **1 hour** (`modelCacheTTL`) and
  exposes a manual refresh (`refreshModels()`).
- Legacy's discovery returns an empty list when the key is missing or
  the fetch fails, and the discovery service as a whole falls back to
  bundled/seed catalogs for some providers. The port returns no
  models on failure and reports the failure (`availability()` maps it
  to `.signedOut` / `.notRunning` / `.failed`); there is no seed
  catalog anywhere in the port.

### 1.3 Connection test and model validation

- `testConnection()`: fetches `/models` with the saved key and
  returns `Connected to OpenRouter (N models available).` on HTTP
  200. Failures throw a specific error, never a substituted model:
  401 invalid key, 402 insufficient credits, 429 rate-limited, other
  statuses a generic API error, transport failure a network error.
- `validateModel(_:)`: the identifier must be in provider/model
  form (contain `/`); otherwise it is rejected as not an OpenRouter
  model identifier. The live `/models` list is then consulted: an
  identifier that is not listed throws model-not-found — the selected
  model is never silently replaced by another one. When listed, the
  result is the native tool-calling support from §1.4.

### 1.4 Native tool-calling support detection

Per-model, from the `/models` entry's `supported_parameters` field:

| `supported_parameters` | Result |
|---|---|
| contains `"tools"` | `.supports` |
| present, without `"tools"` | `.doesNotSupport` |
| absent | `.unknown` |

`.unknown` is not a failure: Legacy's Assist session drives tools
through its own JSON tool protocol, so a model without native
function calling still works. Native support is reported, never used
as a silent substitution gate, and never used to switch models.

### 1.5 Streaming and errors

- Request body (agent path): `model`, `messages`, `stream: true`,
  `tools` when non-empty. Messages encode text parts, image parts
  as `image_url` data URLs, tool calls as top-level `tool_calls`,
  and tool results as `role: "tool"` messages with `tool_call_id`.
- Stream decoding: `delta.content` yields text;
  `delta.tool_calls` yields tool calls (`id`, `function.name`,
  `function.arguments` as a string).
- Error mapping (Legacy's `OpenRouterAssistError`, surfaced through
  the client's `AppError.aiError` with the server's `error.message`
  when present): missing key, 401 invalid key, 402 insufficient
  credits, 429 rate-limited, model not found, non-OpenRouter
  identifier, other statuses with the server detail (truncated to
  300 characters), transport failure as a network error.

## 2. What Ycode's host already provides

- `AssistantProvider` (`kind`, `availability()`,
  `contextWindow(model:)`, `send(_:)`), `ProviderKind`,
  `ModelInfo` (`id`, `displayName`, `contextWindow`),
  `ProviderAvailability` (`.ready` / `.notRunning` / `.noModels` /
  `.notInstalled` / `.signedOut` / `.failed`), `AssistantError`
  (`.unreachable` / `.http` / `.modelNotFound` / `.notSignedIn` /
  `.usageLimit` / `.temporarilyUnavailable` / `.unsupported` /
  `.incomplete` / `.failed` / `.malformed`), `ChatRequest`,
  `ChatEvent` (`.text` / `.activity` / `.truncated` / `.finished`),
  and the `eventStream` helper (`ycode/Sources/YcodeAssistant/Core.swift`).
- HTTP one-shot and SSE streaming (`HTTP.send`, `HTTP.streamLines`,
  `HTTP.url`, `HTTP.errorMessage`, `HTTP.isUnreachable`, `SSEDecoder`,
  `JSON`), and the OpenAI chat-completions SSE chunk parser
  (`ChatCompletionsProvider.parseChunk`: text deltas,
  `finish_reason: "length"`, usage chunk, `[DONE]`, in-stream
  `error` objects) — the port reuses that parser unchanged, because
  OpenRouter streams the same format.
- The secret-storage contract (`SecretStore`, `MemorySecretStore`;
  `SecretAccount` keys for the other providers).
- The `provider()` factory in `AssistantSettings.swift`, which the
  coordinator owns.

## 3. What this slice adds

`ycode/Sources/YcodeAssistant/OpenRouterProvider.swift` —
`struct OpenRouterProvider: AssistantProvider`:

- `kind == .openRouter` (the coordinator adds the `ProviderKind`
  case; this file assumes it exists with exactly that name).
- `init(baseURL:apiKey:)`; `defaultBaseURL` is
  `https://openrouter.ai/api/v1`. The key is supplied by the caller
  (the coordinator wires it from the SecretStore account
  `openrouter.api-key`); the provider never reads the store itself.
- `availability()`: no key (nil, empty, or blank) → `.signedOut`
  with a hint to enter a key in Settings ▸ Coding Assistant.
  Otherwise a live `GET /models`: non-empty → `.ready(models)`,
  empty → `.noModels`; unreachable → `.notRunning`; 401 →
  `.signedOut`; other failures → `.failed`.
- `listModels(forceRefresh:)` / `refreshModels()`: dynamic
  discovery with a **1-hour cache** (`modelCacheTTL = 3600`).
  `refreshModels()` bypasses the cache; it is the manual refresh
  path for Settings. Discovery failure throws — no seed catalog.
- `parseModels(_:)`: `data[].id` → `ModelInfo`, `name` → display
  name (id when absent/empty), `context_length` → context window
  (nil when unreported — no guessed default). Server order is
  preserved; entries without an `id` are skipped.
- `contextWindow(model:)`: the discovered context window for the
  model, or nil when unknown.
- `testConnection()`: as §1.3, returning
  `Connected to OpenRouter (N models available).`
- `validateModel(_:)` and `OpenRouterToolCallingSupport`
  (`.supports` / `.doesNotSupport` / `.unknown`): exactly the §1.4
  rule, plus the provider/model-form check and the
  never-substitute-model rule.
- `send(_:)`: `POST {baseURL}/chat/completions` with
  `Authorization: Bearer <key>`, body `messages` (instructions as
  the system message, then the history), `stream: true`,
  `stream_options.include_usage: true`, and the request's generation
  options (`max_tokens`, `temperature`, `top_p`). Streams `ChatEvent`
  text, yields `.truncated` on `finish_reason: "length"`, and ends
  with `.finished(usage)`. Cancelling the consumer closes the
  connection (via `eventStream`).
- Error mapping (`mapError(status:body:model:)`): 401 →
  `.notSignedIn`; 402 → `.failed` (insufficient credits, with the
  server message when present); 429 → `.usageLimit`; 404 →
  `.modelNotFound` **only when the error message itself names the
  requested model** (a 404 from a wrong base URL must not be
  misreported as an unknown model), otherwise `.http`; anything else
  → `.http(status:message)`. Transport failure → `.unreachable`
  naming OpenRouter and the base URL. No key at send time →
  `.notSignedIn`. The stream closing early → `.incomplete`.

`ycode/Tests/YcodeAssistantTests/OpenRouterProviderTests.swift`:
recorded-sample `/models` payload parsing (ids, display-name
fallback, context windows, skipped id-less entry), tool-calling
detection for all three states plus an unlisted model, signed-out
availability with nil/empty/blank keys, bearer-header handling with
an obviously-fake key against the loopback stand-in server, the
1-hour cache plus manual refresh, 401/402/429 availability mapping,
`validateModel` (shape, listed, unlisted, all three support states),
chat-completions streaming with usage, truncation, 404 error
mapping, and pure `mapError` cases. No test makes a live network
call; fixtures use obviously-fake `example/` model ids and a
placeholder key.

## 4. Deliberate differences from Legacy

- **No Foundation Models detour.** Legacy's client routes the
  `AFM 3 Core` model ids to local Apple Foundation Models. That
  belongs to the Foundation Models provider slice, not this one;
  this provider sends every model to OpenRouter.
- **Key required for discovery.** Legacy's `/models` fetch works
  without a key; this provider reports `.signedOut` with no key, per
  the host's availability contract and the slice brief.
- **No guessed context window.** Legacy defaults unreported context
  lengths to 128,000 in discovery; the port reports nil.
- **No per-model capability guessing.** Legacy marks every
  discovered model as tool-calling and guesses vision from id
  substrings; the port reports tool-calling only from
  `supported_parameters` and does not infer vision.
- **No audit logging.** Legacy logs a 7-point auth audit (including
  masked key fragments) on every fetch and stream; the port logs
  nothing about credentials.
- **No tool-call events.** The host's `ChatEvent` has no tool-call
  case, so streamed `delta.tool_calls` are not surfaced by
  `send(_:)` (the shared `parseChunk` parser drops them). Native
  tool-calling *support* is still detected and reported via
  `validateModel(_:)`; the agent tool loop is a later slice's
  concern.
- **No image / tool-call message encoding.** The host's
  `ChatRequest` carries plain-text messages only, so the request
  builder's image and tool-call encodings have no input to encode.

## 5. Error cases

| Situation | Result |
|---|---|
| No API key (nil / empty / blank) | `availability()` → `.signedOut`; `send(_:)` throws `.notSignedIn` |
| Key rejected (401) | `.signedOut` / `.notSignedIn` ("key was not accepted") |
| Insufficient credits (402) | `.failed` with the insufficient-credits message |
| Rate-limited (429) | `.usageLimit` |
| Host unreachable / DNS / timeout | `.notRunning` (availability) / `.unreachable` (send) |
| `/models` returns an empty list | `.noModels` |
| `/models` returns a non-200, non-401/402/429 status | `.failed` with `HTTP <status>: <message>` |
| `/models` body is not the expected shape | Treated as an empty list (`.noModels`) |
| Model id without `/` in `validateModel` | `.failed` (not an OpenRouter identifier) |
| Model id not in the discovered list | `.modelNotFound` (never substituted) |
| Chat 404 whose message names the model | `.modelNotFound` |
| Chat 404 whose message does not name the model | `.http(404, …)` |
| Stream closes before `[DONE]` | `.incomplete` |
| `finish_reason: "length"` | `.truncated` then `.finished` |
| Invalid base URL | `.failed` ("The OpenRouter address is not valid.") |

## 6. Not ported in this slice

- **`OpenRouterSDKProvider.swift` (599 lines) and
  `SDKHosts/openrouter-bridge.mjs`.** Legacy's second OpenRouter
  path runs the `@openrouter/agent` TypeScript SDK out-of-process
  over NDJSON and lets the SDK own the tool-calling loop. The host
  owns its own agent loop (the session asks for a JSON tool request
  and executes it through the registry), so the SDK loop is not
  needed here; porting a Node bridge is out of scope for this slice
  and is a later wave's decision.
- Legacy's `OpenRouterClient` in-memory cache with no expiry is
  replaced by the 1-hour TTL cache (§3), not ported as-is.
- Legacy's diagnostic `DiagnosticEventBus` / `InternalLoggingManager`
  error logging and its 7-point auth audit logging are not ported.

## 7. Wiring the coordinator still owns

- `ProviderKind.openRouter` case (with display name) in `Core.swift`.
- `SecretAccount` entry with the account string
  `openrouter.api-key` in `SecretStore.swift`.
- `openRouterURL` settings field (default
  `https://openrouter.ai/api/v1`) in `AssistantSettings.swift`.
- The `provider()` factory case constructing
  `OpenRouterProvider(baseURL: settings.openRouterURL, apiKey:
  store.readString(<the OpenRouter account>))`.
- `swift build` / `swift test` on a Mac (no Swift toolchain exists
  in this environment; verification here is static checks only).

## Evidence

| Claim | Level | Source |
|---|---|---|
| Endpoints `https://openrouter.ai/api/v1/models` and `/chat/completions`, Bearer auth, key-resolution order (APIKeyManager → Keychain OpenRouter key → `openrouter-api-key`), in-memory model cache, SSE `data:` / `[DONE]` handling, in-stream error payloads | 1 | Legacy `SwiftCode/Backend/AI/OpenRouterClient.swift`, read directly |
| Agent request body shape (model, messages, `stream: true`, `tools` when non-empty), message encoding (text / image_url / tool_calls / tool role) | 1 | Legacy `SwiftCode/Backend/AI/OpenRouterRequestBuilder.swift`, read directly |
| Connection test, model validation (provider/model form, no silent substitution), tool-calling detection via `supported_parameters` containing `tools`, `.unknown` when absent, error cases (401/402/429) | 1 | Legacy `SwiftCode/Backend/Assist/OpenRouterAssistProvider.swift`, read directly |
| Dynamic-first discovery, OpenRouter discovery mapping (display name, context window with 128,000 fallback, every model marked tool-calling, vision guessed from id), empty list on key-missing/fetch failure, service-level bundled/seed catalog fallback for other providers | 1 | Legacy `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` (`discoverOpenRouterModels`, `getProviderName`, `isProviderExplicitlyActive`), read directly |
| Model record fields (`id`, `name`, `description`, `context_length`, `pricing`) | 1 | Legacy `SwiftCode/Core/AI/OpenRouterModel.swift` and `SwiftCode/Services/OpenRouterService.swift` (`OpenRouterModelsResponse`), read directly |
| SDK provider and Node bridge exist and are a separate path (599-line provider, `openrouter-bridge.mjs`) | 1 | Legacy `SwiftCode/Backend/Assist/OpenRouterSDKProvider.swift` (line count verified) and `SwiftCode/Backend/Assist/SDKHosts/` listing, read directly |
| Host contracts: `AssistantProvider`, `ProviderKind` (7 cases, no OpenRouter), `ModelInfo`, `ProviderAvailability`, `AssistantError`, `ChatEvent`, `eventStream`, chat-completions SSE parsing, `SecretStore` accounts, `provider()` factory | 1 | Destination `ycode/Sources/YcodeAssistant/Core.swift`, `ChatCompletionsProvider.swift`, `OpenAIProvider.swift`, `HTTP.swift`, `SecretStore.swift`, `AssistantSettings.swift`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it. Legacy is Dylan's own code; direct porting was authorised by Dylan under MIT | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

## 2. OpenCode

Wave 9 slice — the OpenCode provider on Ycode's `AssistantProvider` host.
Legacy behaviour is ported from Dylan's own Legacy code (direct porting
authorised under MIT); the Ycode implementation is written from this spec
plus the host's public patterns.

## 1. Legacy behaviour

### 1.1 Files (Legacy @ `d51a8f0d`, read live)

| File | Lines | What this slice uses |
|---|---|---|
| `SwiftCode/Backend/Assist/OpenCodeClient.swift` | 709 | The native client — ported |
| `SwiftCode/Backend/Assist/AssistProviderConfiguration.swift` | 220 | `OpenCodeModel` / `OpenCodeModelID`, `OpenCodeConfiguration` (default URL, agent name, deny-all agent definition) — ported as constants and ID parsing |
| `SwiftCode/Backend/Assist/AgentModelAdapter.swift` | — | OpenCode seam: `opencode:` ids route to `OpenCodeClient` before `LLMService`; context is a conservative 128k default |
| `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` | 1,185 | **No OpenCode part.** Verified live: the file contains no OpenCode path at all. OpenCode discovery lives only in `OpenCodeClient.fetchModels()` (§1.3) |
| `SwiftCode/Backend/Assist/OpenCodeSDKProvider.swift` | 628 | **Not ported** — see §5 |
| `SwiftCode/Backend/Assist/SDKHosts/opencode-bridge.mjs` | 1,020 | **Not ported** — see §5 |

Related Legacy notes: `AssistModels.swift` — OpenCode holds no
SwiftCode-managed API key (credentials live in OpenCode's own config)
and never goes through `LLMService`; `AssistAgentSession.swift:456`
calls `OpenCodeClient.ensureServer()` before a run.

### 1.2 Connection

- Default server URL: `http://127.0.0.1:4096`
  (`OpenCodeConfiguration.defaultServerURL`). Loopback only by default;
  Ycode only ever connects out to the configured URL, never exposes it.
- No API key, token, or secret: model-provider credentials live in
  OpenCode's own configuration. Ycode stores none and sends none.
- Agent: every session names the `swiftcode` agent
  (`defaultAgentName = "swiftcode"`), which must be configured
  server-side with every permission denied (Legacy's
  `swiftcodeAgentDefinition`, installed as
  `~/.config/opencode/agent/swiftcode.md` or
  `.opencode/agent/swiftcode.md`). The agent exists so OpenCode acts as
  a pure model behind Ycode's own tool loop instead of executing its
  own tools.
- Model identifiers are `opencode:<providerID>/<modelID>` (for example
  `opencode:anthropic/claude-sonnet-4-5` — Legacy's own example of the
  format). The prefix is deliberate: bare `provider/model` ids already
  route to OpenRouter elsewhere, so an unprefixed OpenCode model would
  be silently sent to the wrong provider.

### 1.3 Local-server protocol (all endpoints relative to the server URL)

| Step | Legacy call | Endpoint |
|---|---|---|
| Health | `checkHealth()` | `GET /global/health` — 200 is healthy; a 401 means the server requires authentication Legacy deliberately does not handle. Body `{"status": "healthy"}` when present |
| Model discovery | `fetchModels()` | `GET /config/providers` — see §1.4 |
| Session | `session(for:)` (cached per workspace directory) | `POST /session`, body `{"title": "SwiftCode Assist"}`; id from `id`, `data.id`, or `session.id` |
| Subscribe | `openEventStream()` | `GET /event`, `Accept: text/event-stream`, 1-hour timeout. Opened **before** the prompt is sent: if the prompt goes first, the server can emit `session.idle` before the subscriber connects and the run waits for an event that already passed |
| Prompt | `promptAsync()` | `POST /session/<id>/prompt_async`, body `{"model": {"providerID", "modelID"}, "agent": "swiftcode", "parts": [{"type": "text", "text": <full turn prompt>}], "system": <system prompt>}`. No generation options (no temperature / max-tokens) are ever sent |
| Abort | `abortRequest()` | `POST /session/<id>/abort` (5 s timeout), fired when the run is cancelled |
| Retry | in `streamPrompt()` | A stale cached session (server restarted) surfaces as a 404 on the prompt; the session is dropped and the run retried exactly once with a fresh session |

`?directory=<workspace path>` is appended to every endpoint when a
workspace directory is known.

### 1.4 Model discovery — `GET /config/providers`

Dynamic only, never a hardcoded catalog: an empty or unparseable
catalog is an error, not a fallback list. The endpoint has returned
both a `providers` array and provider-keyed objects across versions,
and model entries use `id` or `modelID`; `models` may be an array or a
dictionary keyed by model id. Anything unrecognised is skipped rather
than fabricated into a model. Results are deduplicated by stored id
and sorted by provider, then model. The catalog reports **no context
window**; Legacy's `AgentModelAdapter` therefore uses a conservative
128,000-token default for OpenCode models.

### 1.5 Event stream — SSE frames

One `data:` JSON object per frame (`{"type", "properties"}`).
`properties.sessionID` (also spelled `sessionId` / `session_id`)
identifies the session; frames for other sessions are ignored.

| Frame | Meaning |
|---|---|
| `message.part.delta` / `part.delta` with `part.type == "text"` | Text delta (`part.text`); also the bare `properties.delta` string form |
| `message.part.delta` / `part.delta` with `part.type == "tool"` | **Tool part — fail the run closed.** OpenCode must never execute tools on a Ycode session; the run is aborted |
| `part.updated` / `part.added` with text | Ignored — carries the full accumulated part, not a delta; yielding it would duplicate every delta already streamed |
| `part.updated` / `part.added` with `part.type == "tool"` | Tool part — fail closed as above |
| `session.idle` | Run complete |
| `session.error` | Run failed (`properties.error.message`, else `properties.message`) |
| Anything else / `[DONE]` / non-JSON | Ignored — a new event type from a newer server must never be mistaken for model text or a tool result |

The stream carries no token usage, so a finished run reports no
usage counts.

### 1.6 Legacy managed server (auto-heal) — NOT ported to Ycode

Legacy's `ensureServer()` auto-heals both failure modes: a missing
server is started automatically (`opencode serve --hostname 127.0.0.1
--port <port>`, loopback only), and a missing `opencode` binary is
located in well-known install locations or installed via npm/bun
(`npm install -g opencode-ai`, 180 s cap). Only a total auto-heal
failure surfaces as a user-facing error. Ycode does **not** port this
(see §3): the Ycode host has no managed-server lifecycle, and the
other local-server providers (Ollama, llama.cpp) report a stopped
server with a start hint instead. A stopped OpenCode server is
therefore a `.notRunning` availability with a hint telling the user to
run `opencode serve` (installing the CLI first if needed).

## 2. What Ycode's host already provides vs what this slice adds

Host (`ycode/Sources/YcodeAssistant/`):

- `Core.swift` — `AssistantProvider` protocol, `ProviderKind`,
  `ModelInfo`, `ProviderAvailability` (`.ready` / `.notRunning` /
  `.noModels` / `.failed`), `AssistantError`, `ChatRequest`,
  `ChatEvent`, the `eventStream` helper (cancelling the consumer
  cancels the request).
- `HTTP.swift` — `HTTP.send` / `HTTP.stream` / `HTTP.streamLines`,
  `HTTP.url`, `HTTP.jsonRequest`, `HTTP.errorMessage`,
  `HTTP.isUnreachable`, `SSEDecoder`, `LineSplitter`, `JSON`.
- `OllamaProvider.swift` / `ChatCompletionsProvider.swift` — the
  local-server provider patterns this slice follows (reachability
  probe, model listing, SSE/NDJSON streaming, error mapping).
- `AssistantSettings.swift` — the `provider()` factory (coordinator
  owned; this slice does not touch it).

This slice adds (destination repo, uncommitted):

- `ycode/Sources/YcodeAssistant/OpenCodeProvider.swift` —
  `struct OpenCodeProvider: AssistantProvider`:
  - `kind == .openCode` (the `ProviderKind.openCode` case, the
    `openCodeURL` settings field defaulting to
    `http://127.0.0.1:4096`, and the `provider()` wiring are added by
    the coordinator at merge time — this file assumes exactly those
    names and does not compile until the case exists).
  - `init(baseURL:agentName:)`; defaults `http://127.0.0.1:4096` and
    agent `swiftcode`.
  - `availability()` — `GET /config/providers` (5 s timeout); 401 →
    `.failed` (server auth is deliberately unsupported, as in
    Legacy); non-200 → `.failed`; empty catalog → `.noModels`;
    unreachable → `.notRunning` with the start hint. Successful
    lists are cached for 1 hour (`modelCacheTTL = 3600`);
    `refreshModels()` clears the cache for a manual refresh.
  - `parseModels(_:)` — the §1.4 catalog parser, ported from
    Legacy's `OpenCodeProviderCatalog.parseModels` (same shapes,
    same skip-unknown rule, same provider-then-model sort).
  - `contextWindow(model:)` — always 128,000, Legacy's conservative
    default (§1.4). This is a documented default, not a
    server-reported value.
  - `send(_:)` — the §1.3 flow: resolve the `opencode:` model id
    (bare `provider/model` also accepted); reuse the cached session
    for the request's working directory, else `POST /session`;
    subscribe to `GET /event` before `POST prompt_async`; retry
    exactly once on a stale-session 404; stream text deltas as
    `.text`, fail closed on a tool part (aborting the run),
    `.finished(nil)` on `session.idle` (no usage is reported).
    Cancellation aborts the server session (`POST …/abort`).
    Generation options are not sent (§1.3). `?directory=` is sent
    from `ChatRequest.workingDirectory` when set.
  - `parseEvent(_:)` / `handle(eventData:sessionID:directory:out:)`
    — the §1.5 frame parser and dispatcher.
  - `resetSessions()` / `resetSession(directory:)` — drop cached
    session ids (e.g. on provider switch), mirroring Legacy.
- `ycode/Tests/YcodeAssistantTests/OpenCodeProviderTests.swift` —
  parser tests against recorded sample payloads (no live network),
  availability / cache / not-running tests against the test
  `LoopbackServer` (unreachable-port case needs no live server),
  end-to-end `send` tests (session → event → prompt order, prompt
  body, other-session filtering, tool-part failure, stale-session
  retry, missing model, unreachable server). Fixture ids are invented
  (`acme/alpha`); no real provider or model is named in code or
  tests.

## 3. Divergences from Legacy (deliberate)

1. **No managed server / auto-install.** Legacy starts and installs
   the server (§1.6); Ycode reports `.notRunning` with a start hint.
   Reason: the Ycode host has no managed-server lifecycle, and the
   sibling local providers behave the same way. A later wave could
   add managed startup; it would need a host-level lifecycle, not a
   provider-local `Process` launch.
2. **No `GET /global/health` probe.** Availability proves liveness
   with the same request that lists models (`GET /config/providers`),
   like Ollama's `/api/tags` probe. A 401 is still reported as in
   Legacy.
3. **Session title kept as `SwiftCode Assist`** (Legacy's literal
   title) rather than renamed, so server-side session lists match
   Legacy behaviour.
4. **Errors map to `AssistantError`.** Legacy's `OpenCodeError`
   cases map as: server unavailable → `.unreachable` (with the start
   hint); prompt/session failures → `.failed` (message preserved,
   including the 300-character body cap); tool part →
   `.failed` with Legacy's tool-execution-blocked wording; stream
   interruption → `.failed`; closed stream without idle →
   `.incomplete`. There is no `.notRunning` error case; unreachability
   is reported through availability and `.unreachable` on send.
5. **One event subscription survives the stale-session retry.**
   Legacy re-opens the event stream after the retry; Ycode reuses the
   single subscription because `/event` is a global feed filtered by
   session id. If the prompt fails outright, the opened subscription
   is cancelled via a throwaway iterating task so no connection is
   left dangling.

## 4. Error cases

| Situation | Result |
|---|---|
| Server not running / unreachable | `availability()` → `.notRunning` ("OpenCode is not running at \<url\>. Start it with `opencode serve` …"); `send()` → `AssistantError.unreachable` with the same hint |
| Invalid base URL | `.failed` / `AssistantError.failed` |
| Server requires auth (401 on discovery) | `.failed` — run the server on loopback without server auth |
| Server lists no models (200, empty catalog) | `.noModels` — configure a model provider in OpenCode first |
| Non-200 discovery / prompt / session | `.failed` with status and the first 300 characters of the body |
| Session creation returns no id | `.failed` ("OpenCode session creation returned no session id.") |
| Server does not recognise the `swiftcode` agent (404 mentioning "agent") | `.failed` naming the agent and where to define it |
| Stale session (prompt 404, not agent-related) | Session dropped, retried exactly once with a fresh session |
| Tool part on the event stream | `.failed` (tool-execution-blocked wording); the run is aborted server-side |
| `session.error` frame | `.failed` with the server's message |
| Stream closes before `session.idle` | `.incomplete` ("the server closed the stream") |
| Event stream non-2xx | `.failed` ("OpenCode event stream returned status \<n\>. …") and an abort is fired, since the prompt may still be running |
| No model selected / unparsable model id | `.modelNotFound` with a hint to choose an OpenCode model in Settings |
| Consumer cancels | `CancellationError`; an abort is fired best-effort |

## 5. Not ported: OpenCodeSDKProvider + opencode-bridge.mjs

`OpenCodeSDKProvider.swift` (628 lines) is a Swift facade over
`SDKHosts/opencode-bridge.mjs` (1,020 lines): it launches Node, and
the bridge owns the SDK session, system prompt, and event stream over
a shared NDJSON run protocol on stdin/stdout, using
`@opencode-ai/sdk@1.19.5` (v2 client), installed by the
SDKRuntimeManager under Application Support. It is **not ported in
this slice**, by task scope: the native HTTP client above is the
provider Ycode needs, and the bridge needs a Node runtime, an SDK
runtime manager, and the SDK tool-source/event contract
(`SDKToolEvent`, `OpenCodeSDKToolSource`, `SDKBridgeLaunching`) that
do not exist in the Ycode host. Consequences, stated plainly:

- Runs that need the SDK transport (the bridge's session ownership,
  SDK-managed tools, and the `swiftcode` / `opencode` / `combined`
  tool-source selection) are honestly unavailable through this
  provider; nothing here reimplements the bridge.
- The native client covers the pure-model path: prompt in, text
  deltas out, with Ycode's own tool loop on top. Any operation that
  in Legacy depended on the Node SDK bridge is unavailable, with the
  prerequisite (Node + `@opencode-ai/sdk` bridge + SDK runtime
  manager) named here rather than silently emulated.

## 6. Evidence

- Legacy `OpenCodeClient.swift` (709 lines), `AssistProviderConfiguration.swift`
  (220 lines), `AgentModelAdapter.swift` (OpenCode seam, 128k default),
  `AssistModelDiscoveryService.swift` (1,185 lines — verified to contain
  no OpenCode path), `OpenCodeSDKProvider.swift` (628 lines),
  `SDKHosts/opencode-bridge.mjs` (1,020 lines) — read live from
  `~/workspace/repos/SwiftCode-Legacy` @ `d51a8f0d` (read-only). Legacy is
  Dylan's own code; direct porting authorised under MIT (spec-first
  where it costs nothing).
- Ycode host: `ycode/Sources/YcodeAssistant/Core.swift`,
  `OllamaProvider.swift`, `ChatCompletionsProvider.swift`, `HTTP.swift`,
  `AssistantSettings.swift` — read live from the destination repo @
  `aca43f3f`.
- Audit: `~/SwiftCode-Migration-Workspace/audit/legacy-subsystem-map.md`
  §2.3 (providers).
- Evidence levels (per the repo's clean-room protocol): Legacy source
  and Ycode host source are first-hand reads of Dylan's own / Ycode's
  own code (level 1 for this migration's purposes — no Apple binaries,
  no Ghidra, no Xcode/Simulator observation were involved). The
  OpenCode server API shapes are taken from Legacy's implementation
  and its comments citing `https://opencode.ai/docs/sdk/`; the public
  docs were not re-fetched in this slice, so endpoint behaviour beyond
  what Legacy implements is unverified here.
- Not verified in this environment: no Swift toolchain exists here,
  so `swift build` / `swift test` were not run (static checks only —
  see the slice report). The Mac build/test, a live OpenCode server
  run, and the coordinator's `ProviderKind.openCode` /
  `openCodeURL` / `provider()` additions are still pending.

## 3. Hermes

Hermes Agent (Nous Research) as a coding-assistant back end in
YcodeAssistant: one-shot runs of the real `hermes` CLI, observed
through its stream-json event stream. No Ycode tools are sent to
Hermes; Hermes runs its own tools and Ycode only observes them.

## 1. Legacy behaviour (verified live, Legacy @ d51a8f0d)

Sources:

- `SwiftCode/Backend/Assist/HermesProvider.swift` (actor, ~950 lines)
- `SwiftCode/Backend/Assist/HermesSessionRunner.swift` (121 lines)
- `SwiftCode/Backend/Assist/HermesProviderTests.swift` (in-app runtime tests)
- `Docs/Assist-Hermes-Provider.md`
- `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` — contains
  **no** Hermes code (verified by grep: zero matches in 1,185 lines).
  Hermes model discovery lives entirely in `HermesProvider.swift`
  itself (`fetchModels` / `readConfiguredModelSpecs` /
  `parseModelOutput`).

### 1.1 Protocol: stream-json CLI, NOT ACP

The brief for this slice described Hermes as "ACP via `hermes acp`".
That is wrong, and Legacy says so explicitly in its header: Hermes
is a Python CLI agent, not a Swift library and not a JS SDK, and
SwiftCode launches the real `hermes` executable as a child process
and talks to it through its documented programmatic interface:

```
hermes --in <workspace> chat --oneshot --query-file <file>
       --format stream-json --source tool
       [--provider <provider>] [--model <model>]
       [--toolsets <csv>] [--max-turns <n>]
```

Verified against the Hermes Agent repository and its CLI reference.
Legacy deliberately did **not** use:

- `hermes -z` (scripted one-shot): prints final text only (no tool
  events) and sets `HERMES_YOLO_MODE=1` internally, which would
  silently auto-approve.
- `hermes acp` (the ACP server): a real editor protocol, but
  implementing a full ACP JSON-RPC host (permission callbacks,
  session lifecycle, gateway viewer semantics) would be a larger,
  riskier surface for no capability gain over stream-json, and ACP
  likewise cannot inject SwiftCode's system prompt.
- `@hermes/plugin-sdk`: extends Hermes Desktop's UI; not an
  agent-execution interface.

`--format stream-json` emits one JSON object per stdout line:

| `type` | Fields | Meaning |
|---|---|---|
| `system` | `model`, `session_id` | Init record |
| `text` | `text` | Assistant text delta |
| `tool_use` | `name`, `input` | Hermes started one of its own tools |
| `tool_result` | `name`, `output` (capped at 5000 chars by Hermes), `duration_ms`, `is_error` | That tool finished |
| `result` | `session_id`, `exit_code`, `text` (the whole reply), `tokens`, `duration_ms`, `error` | Terminal record; authoritative for final text and exit code |

Diagnostics stay on stderr. Exit codes for finite runs: 0
completed, 1 failed / partial / iteration budget / never ran, 130
interrupted, 75 transient provider failure (dispatcher requeue
code; surfaced as a failure, never retried silently).

Tool events carry **no call id** on the wire, so Legacy synthesises
stable per-run ids (`hermes-<run>-<name>-<n>`) to pair `tool_use`
with `tool_result` and to keep runs in one session from merging.

### 1.2 One-shot semantics

One SwiftCode task maps to one bounded Hermes run. A fresh run is
used for every task: SwiftCode never passes `--resume`, so Hermes
session state is never silently carried across tasks. The SwiftCode
transcript remains the conversation record. No conversation history
is replayed into Hermes.

The runner (`HermesSessionRunner.run`) builds the system prompt
(base instructions + retrieved System Asset instructions), takes
the selected model id, runs one provider run, and returns the final
text — preferring the terminal `result.text` (authoritative; text
deltas can stop early on a replay gap), falling back to the streamed
deltas, and failing rather than posting a partial or empty reply as
if it were complete.

### 1.3 No SwiftCode tools inside a Hermes run

The stream-json interface is observational for tools: Hermes
reports the tools **it** executes; there is no documented callback
by which SwiftCode could execute its own registry tools inside a
Hermes run. Legacy therefore sends **no** SwiftCode tool schemas to
Hermes and never claims SwiftCode tools ran. Tool events are
published with source `.hermes` so the Hermes tool panel renders
exactly what Hermes did. Selecting Hermes is an explicit choice of
Hermes' tool system.

### 1.4 Prompt delivery

Hermes' chat parser has no `--system-prompt` flag. Legacy delivers
its assembled prompt (system instructions first, then the task,
separated by `\n\n---\n\n`) as the contents of the query file —
user-turn delivery, not a system prompt. Hermes' own profile
(`SOUL.md`) / workspace rules still apply on top; if they contradict
SwiftCode's instructions, Hermes resolves the conflict. Legacy
never writes to `~/.hermes/SOUL.md`, `config.yaml`, or `.env` to
force its prompt in. The prompt travels in a temp file outside the
workspace (deleted on every exit path), never in argv, so it cannot
leak into a process listing; `--query-file` passes the body verbatim
(no shell interpretation of quotes, `$()`, or backticks). The child
is launched directly (no shell), with no shell interpolation
anywhere.

### 1.5 Approvals

A single-query Hermes run has no user at a terminal to answer an
approval prompt, so Hermes' own `approvals.single_query_mode`
applies — its default is `deny`, i.e. a dangerous command is
blocked and the agent must find another way. Legacy never passes
`--yolo` and never sets `HERMES_YOLO_MODE` /
`HERMES_ACCEPT_HOOKS`, and launches Hermes with a controlled
environment (PATH/HOME/TMPDIR only) so a stray `HERMES_*` variable
in the parent environment can never change that. Hermes tools
therefore always run under Hermes' own approval policy, never under
SwiftCode's tool permissions. If the user's Hermes config sets
`single_query_mode` to `approve`, that is their Hermes
configuration choice, not something SwiftCode enables.

### 1.6 Model identity and discovery

Models are stored as `hermes:<spec>` where `<spec>` is Hermes' own
syntax: `provider:model` (for example
`hermes:openrouter:anthropic/claude-sonnet-4-6`) or a bare model
name Hermes resolves against its configured default provider (for
example `hermes:gpt-5.5`). The `hermes:` prefix is deliberate: a
bare `provider/model` id already routes to OpenRouter in
`LLMService`, so an unprefixed Hermes model would be silently sent
to the wrong provider. Nothing strips the prefix and re-routes the
model elsewhere. (The example model names above are Legacy's own
recorded samples, not a catalogue Ycode ships.)

Discovery is dynamic-first and throws rather than fabricating.
There is no non-interactive Hermes model-list command, so Legacy
uses the two real sources that exist:

1. The model Hermes is configured to use, read from its
   `config.yaml` (`model.provider` and `model.default`, under
   `HERMES_HOME` or `~/.hermes`). `hermes model` with no arguments
   is an interactive picker that refuses to run without a terminal,
   so it is never launched; its output format is still parsed by
   the pure `parseModelOutput` helper for the Settings flow.
2. When that provider is OpenRouter, OpenRouter's live `/models`
   catalog (via the saved OpenRouter key), because Hermes then
   routes through OpenRouter and those are exactly the models
   Hermes can be pointed at. When there is no OpenRouter key, only
   the current model is returned — never a fabricated catalog.

When nothing parses, discovery throws an honest error instead of
showing a fabricated catalog. Legacy's own doc also records, in its
"Known limitations", that "Hermes model discovery is not
implemented: SwiftCode cannot list Hermes' configured models …
so the user types the model spec in Settings" — the doc and the
code disagree on the date the `fetchModels` path landed; the code
(and its tests) are the authority for what was implemented, and
this spec follows the code.

### 1.7 Credentials (Legacy)

Hermes credentials live in Hermes' own `~/.hermes/.env` and
`config.yaml`. Legacy stores no Hermes API key, never passes
`--api-key` / `--base-url` (which would put a key in argv and in
Hermes' launch-only memory), and redacts tool arguments/results
and stderr tails before they reach the UI or an error string.
Hermes authenticates itself; SwiftCode never downloads or executes
a remote install script and never manages Hermes' credentials.

### 1.8 Cancellation (Legacy, honestly limited)

Cancellation terminates only the child process Legacy started
(SIGTERM, a 2-second grace wait, then SIGKILL), marks the run's
non-terminal tool rows cancelled, and does not re-report the
cancellation as a failure. Caveat, stated in Legacy's doc: modern
`hermes chat` is a gateway client, and its own interrupt path says
"Detached; accepted work continues at the gateway." No CLI command
exists to cancel a gateway turn from outside (that would need ACP
`session/cancel`). So Legacy's cancel guarantees the local CLI
process dies and SwiftCode stops observing/reporting the run — it
cannot guarantee a gateway turn that was already accepted stops
executing. Treat a cancelled Hermes run as "SwiftCode stopped
watching", not "Hermes stopped working".

### 1.9 Executable discovery (Legacy)

Configured path wins when it is executable; otherwise PATH plus
`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`. `hermes
--version` (first stdout line, 15 s timeout) is used by the
Settings status check, never to gate a run.

## 2. What Ycode's host already provides vs what this slice adds

Host (read first, followed exactly):

- `ycode/Sources/YcodeAssistant/Core.swift` — `ProviderKind` (7
  cases; the coordinator adds `.hermes`), `AssistantProvider`
  protocol, `ModelInfo`, `ProviderAvailability`, `AssistantError`,
  `eventStream` helper.
- `ycode/Sources/YcodeAssistant/CLIAgents.swift` — the CLI-agent
  pattern this provider follows: one subprocess per request,
  `CLIToolLocator` for discovery, `CLIEventParser` for turning a
  tool's JSON event stream into `ChatEvent`s, `CLIAgentProvider`
  as the structural model.
- `ycode/Sources/YcodeSubprocess/StreamingSubprocess.swift` —
  `lines(executable:arguments:environment:currentDirectory:)`,
  which streams stdout line by line and escalates SIGINT →
  SIGTERM → SIGKILL on cancellation; non-zero exit surfaces as
  `ExitError` with a capped stderr tail.
- `ycode/Sources/YcodeAssistant/SecretStore.swift` —
  `SecretStore` protocol (`KeychainSecretStore` on macOS,
  0600-file store on Linux, `MemorySecretStore` for tests).

What this slice adds (new files only; no host file is edited):

- `ycode/Sources/YcodeAssistant/HermesProvider.swift` —
  `HermesProvider: AssistantProvider` plus the ported value types
  (`HermesModelID`, `HermesConfiguration`, `HermesStreamResult`,
  `HermesParsedEvent`, `HermesStreamParser`,
  `HermesPromptBuilder`, `HermesStreamEventParser`).
- `ycode/Tests/YcodeAssistantTests/HermesProviderTests.swift` —
  offline tests (see §5).
- This spec.

### 2.1 Why the host ACP client is NOT used

The task brief asked for the provider to be built on the host's
ACP client (`ACPConnection` / `ACPClient.swift`). That is not
possible for Hermes as Legacy drives it, and the reason is a
protocol mismatch, not a missing feature:

- `ACPConnection` speaks ACP version 1: newline-delimited
  JSON-RPC over stdin/stdout, `initialize` / `session/new` /
  `session/prompt` / `session/cancel`, with client-side handlers
  for `fs/read_text_file`, `fs/write_text_file`, and
  `session/request_permission`.
- Legacy drives Hermes with a one-shot CLI invocation whose stdout
  is a stream of flat JSON objects (`system` / `text` /
  `tool_use` / `tool_result` / `result`) and whose stdin is never
  written to. There is no JSON-RPC request/response, no session
  creation, no permission callback, and no way to inject Ycode
  tools or a system prompt through it.

Forcing Hermes onto `ACPConnection` would mean speaking ACP to a
process that was not started in ACP mode, which cannot work; and
starting `hermes acp` instead would be a different provider design
that Legacy explicitly rejected (§1.1) and that the migration
brief did not authorise. So this provider follows the host's
other, equally established CLI-agent pattern
(`CLIAgentProvider` + `StreamingSubprocess` + `CLIEventParser`)
and builds **no** ACP code at all — no parallel ACP stack, no
second JSON-RPC implementation. The one gap this leaves, versus a
hypothetical future ACP-based Hermes provider, is the one Legacy
already documents: no gateway-side cancel (`session/cancel`) and
no way to expose Ycode tools to Hermes via `session/new`
`mcpServers`. Both are documented Hermes capabilities, neither is
claimed by this CLI implementation.

## 3. Ycode behaviour

### 3.1 Provider shape

`HermesProvider` is a struct conforming to `AssistantProvider`
with `kind == .hermes` (the case is added by the coordinator at
merge time; this file assumes exactly that name). It holds the
located executable, a `HermesConfiguration`, an optional
`SecretStore`, and a home directory used only for model discovery.
Construction mirrors `CLIAgentProvider`: either an explicit
executable URL or a `CLIToolLocator` that finds `hermes` (PATH,
then the usual install folders), honouring an explicit path in the
configuration.

### 3.2 Availability and models

- Executable absent → `.notInstalled` with the setup hint
  ("run `hermes setup` and `hermes model` in Terminal").
- Executable present → `.ready` with the models Hermes itself
  reports: its configured model, read from `config.yaml`
  (`model.provider` / `model.default`, under `HERMES_HOME` or
  `~/.hermes`), as `hermes:<spec>` ids. No hardcoded model list.
- When no model is configured → `.ready` with a single `Default`
  entry (`ModelInfo(id: "", displayName: "Default")`): the agent
  runs with whatever model Hermes itself defaults to. This is a
  deliberate deviation from Legacy's `fetchModels`, which throws
  when nothing parses; throwing from `availability()` would hide
  a working agent whose config lives in a non-default location,
  and the run itself still fails with a clear error if Hermes has
  no usable model. The host's CLI agents use the same `Default`
  entry (`CLIAgentProvider.availability`, `ACPAgentProvider`).
- `contextWindow(model:)` returns `nil`: Hermes reports no
  context window for its models.
- The OpenRouter-catalog expansion Legacy performs when Hermes is
  OpenRouter-backed is **not** ported: it needs the OpenRouter
  provider's live catalog and saved key, which belong to the
  OpenRouter slice, not this one. Availability therefore reports
  only the configured model (or `Default`). If the OpenRouter
  slice later exposes a catalog, this provider can expand to it
  the way Legacy does; until then it reports one real model rather
  than a fabricated list.

### 3.3 One run

`send(_:)` runs one request through `eventStream`, exactly one
child process per request:

1. Resolve the model id (§3.4). An invalid `hermes:` id throws
   `AssistantError.modelNotFound` **before** anything is launched.
2. Write the prompt to a temp query file
   (`ycode-hermes-query-<uuid>.txt` in the temporary directory),
   built by `HermesPromptBuilder` from the request's instructions
   plus the conversation (earlier turns as `<role>` blocks, then
   the new message), separated by `\n\n---\n\n`. Deleted in
   `defer` on every exit path.
3. Build the controlled environment (§3.5) and the exact argv
   (§3.6), then stream stdout lines through
   `StreamingSubprocess.lines` with the request's working
   directory (or the user's home) as the child's cwd.
4. Map each line through `HermesStreamEventParser` (§3.7).
5. On completion: if a terminal `result` arrived, `.finished`
   carries its token usage; otherwise, if any text arrived,
   `.finished(nil)`; if no text and no result arrived, the run
   throws instead of posting an empty reply. A non-zero process
   exit after a successful terminal result is honoured as a
   success (the result record is authoritative); any other
   non-zero exit throws with the redacted stderr tail.
6. Cancellation (consumer stops / task cancelled) interrupts the
   child via `StreamingSubprocess` (SIGINT → SIGTERM → SIGKILL);
   the gateway caveat from §1.8 still applies.

No Ycode tool schemas are sent. No MCP server is attached.
Hermes runs its own tools; Ycode observes.

### 3.4 Model ids

`HermesModelID` is ported from Legacy unchanged in semantics:
`spec`, `storedID` (`hermes:<spec>`), `provider` (nil for a bare
model — Ycode must not invent one), `model` (the part after the
provider prefix), strict `parse` (nil for anything without the
`hermes:` prefix, an empty spec, or an empty model part).

One deliberate leniency in `resolvedModelID`: a non-empty model
value that does **not** carry the `hermes:` prefix is taken as
Hermes' own spec. In Ycode the provider is already selected
(`ProviderKind.hermes`), so the prefix carries no routing meaning;
Legacy needed it only to keep a bare `provider/model` id from
routing to OpenRouter. An empty model part still fails before
launch.

### 3.5 Credentials — the Ycode deviation (explicit)

Legacy behaviour: Hermes authenticates itself from its own
`~/.hermes/.env`; SwiftCode stores no Hermes key and passes none.

Ycode behaviour: Ycode **never reads or writes `~/.hermes/.env`**
and never reads `~/.hermes/config.yaml` for secrets (it reads
only the non-secret `model.provider` / `model.default` fields for
discovery, §3.2). Instead, when the selected model's provider has
a documented key variable, the key is read from Ycode's
`SecretStore` (Keychain on macOS) and placed in the child
process's environment at spawn time:

| Hermes provider | Env variable (Hermes' public reference) | SecretStore account |
|---|---|---|
| `openrouter` | `OPENROUTER_API_KEY` | `hermes.openrouter-api-key` |
| `openai-api` | `OPENAI_API_KEY` | `hermes.openai-api-key` |
| anything else | — (unmapped) | — |

Why this shape:

- Hermes has no single "Hermes API key". Its public
  environment-variable reference names one key variable per LLM
  provider (`OPENROUTER_API_KEY`, `OPENAI_API_KEY`,
  `FIREWORKS_API_KEY`, …), and its config reference states that
  secrets go in `.env` while everything else goes in
  `config.yaml`. A single `hermes.api-key` account would have no
  defined meaning to Hermes.
- Only providers whose variable is documented in that reference
  are mapped. Anything else returns nil and Hermes authenticates
  itself from its own `.env` via HOME — Legacy behaviour, not a
  failure. A variable name must never be invented for an unmapped
  provider; more mappings can be added once their names are
  verified against Hermes' reference.
- The SecretStore account strings live in this file
  (`HermesProvider.apiKeyAccount(forProvider:)`), not in
  `SecretAccount`, because `SecretStore.swift` is coordinator-owned
  and this slice must not edit it. The coordinator may move them
  into `SecretAccount` at merge time.
- The key is placed **only** in the child environment. It is never
  put in argv (Legacy's rule, kept), never logged, and every stderr
  tail is passed through `HermesProvider.redacted(_:secrets:)`
  before it reaches an error string, so a key can never leak into
  logs or UI.

The child environment is otherwise exactly Legacy's controlled
environment — PATH (executable's dir first), HOME, TMPDIR only —
so no `HERMES_*` variable is inherited and a stray
`HERMES_YOLO_MODE` in the parent can never auto-approve a run.
This provider never passes `--yolo` and never sets
`HERMES_YOLO_MODE` / `HERMES_ACCEPT_HOOKS`.

### 3.6 Arguments

`HermesProvider.buildArguments` (pure, tested) builds the exact
Legacy argv, in order:

```
--in <directory> chat --oneshot --query-file <path>
--format stream-json --source tool
[--provider <provider>] [--model <model>]
[--toolsets <csv>] [--max-turns <n>]
```

`--in` is a global option and must precede the subcommand.
`--provider` only when the model spec carries one; `--model`
only when a model is selected (absent means Hermes' configured
default); `--toolsets` only when the configuration's normalised
toolsets are non-empty (whitespace-only counts as empty);
`--max-turns` only when `maxTurns > 0`. Never `--yolo`,
`--api-key`, `--base-url`, and never the prompt itself.

### 3.7 Stream-json → chat events

`HermesStreamParser.parseLine` (ported from Legacy) maps one
stdout line to `HermesParsedEvent`; blank lines, malformed JSON,
and unknown types map to `.ignored` and never abort a run.
`HermesStreamEventParser` (conforming to the host's
`CLIEventParser`) turns those into `ChatEvent`s:

- `text` → `.text(delta)`.
- `tool_use` → `.activity("<name>: <path|command|query>")`
  (tool name plus the most useful argument when the input
  carries one; just the name otherwise).
- `tool_result` → `.activity("<name> ✓")` or `"<name> ✗"`.
- `result` with exit code 0 → its text is emitted only if no
  text delta arrived (the result text is authoritative); its
  `tokens` (`input` / `output`) ride on the `.finished` emitted
  by `finish()`. A non-zero exit code throws
  `AssistantError.tool` at the result line, carrying the
  result's `error` when present.
- `system` and `.ignored` → no events.

The terminal result's token usage is carried in
`HermesStreamResult.tokens`; Legacy's struct did not model the
wire `tokens` object (its own test sample contains one), so this
is a small additive extension, not a behaviour change.

### 3.8 Configuration

`HermesConfiguration` (executable path, toolsets, max-turns) is
ported as a plain value with `normalisedToolsets`. It does **not**
read or write UserDefaults: in Ycode, settings live in
`AssistantSettings` (coordinator-owned) and the coordinator maps
them into this value when constructing the provider. Model
selection lives in the selected model id, never duplicated in the
configuration.

## 4. Error cases

| Situation | Ycode result |
|---|---|
| `hermes` binary not found | `availability()` → `.notInstalled` (setup hint); `send` throws `AssistantError.tool` with the setup hint |
| Invalid `hermes:` model id (empty spec, empty model part) | `AssistantError.modelNotFound` before launch; no other model substituted |
| No model configured and no model selected | Run proceeds with no `--model` flag; Hermes uses its configured default; if Hermes itself has none, its own error surfaces |
| Query file cannot be written | `AssistantError.tool` ("Could not write the Hermes query file…") |
| Child exits non-zero without a successful terminal result | `AssistantError.tool` with the redacted stderr tail (or "exit status N"); login/auth wording gets the sign-in hint |
| Terminal `result` has non-zero `exit_code` | `AssistantError.tool` with the result's `error` (or "Hermes run failed (exit N)") |
| Run completes with no text and no result record | `AssistantError.tool` ("completed without a final response") — never an empty reply |
| Malformed / unknown stream-json line | Ignored; the run continues |
| Cancellation | `CancellationError`; local child is interrupted (SIGINT → SIGTERM → SIGKILL). Gateway caveat (§1.8) applies |
| No SecretStore key for a mapped provider | No credential variable is set; Hermes authenticates itself from its own `.env` (Legacy behaviour) |
| Unmapped provider (e.g. Anthropic direct) | No credential variable is set; same as above. No variable name is invented |

## 5. Tests

`ycode/Tests/YcodeAssistantTests/HermesProviderTests.swift`
(Swift Testing, `@testable import YcodeAssistant`). All offline and
deterministic — no real `hermes` binary, no real key, no network:

- Model-id parsing and provider/model split (Legacy's recorded
  samples, including the rejection cases).
- Exact argument construction, bare-model arguments, and the
  default-model case (no `--provider` / `--model` flags); the
  forbidden flags (`--yolo`, `--api-key`, `--base-url`) and prompt
  text never appear in argv.
- Stream-json parsing for every documented event type against
  recorded sample payloads, including token usage on the terminal
  result; malformed lines ignored.
- Prompt builder (separator, empty-side handling).
- `HermesStreamEventParser` mapping: text deltas, tool-use /
  tool-result activity lines, result-text-only-when-no-delta,
  tokens on `.finished`, non-zero result throws.
- Availability: `.notInstalled` when the binary is absent
  (locator with an `isExecutable` stub that always returns false);
  `.ready` with the configured model read from a fixture
  `config.yaml`; `.ready` with `Default` when nothing is
  configured; `contextWindow` is nil.
- Config discovery: `readConfiguredModelSpecs` and
  `parseModelOutput` against fixture text.
- Credentials with a fake key in a `MemorySecretStore`:
  credential mapping only for documented providers; the
  controlled environment never inherits `HERMES_*` variables;
  `redacted(_:secrets:)` removes the fake key from error text.
- End-to-end against a stand-in `hermes` shell script (not a live
  agent): it records argv, reports whether
  `OPENROUTER_API_KEY` reached it without printing the value, and
  emits recorded stream-json lines. Asserts the streamed text and
  activity lines, token usage on `.finished`, the exact argv, the
  fake key appearing nowhere in events or argv, the temp query
  file being deleted, the no-key case reporting `key-absent`, an
  invalid model failing before launch (no argv recorded), and a
  failing run surfacing its stderr.

Not covered here (needs Dylan's Mac): the Swift build and test
run (no Swift toolchain in this environment), the Settings
installation check against a real `hermes` binary, and a real
end-to-end Hermes task (select a `hermes:openrouter:<model>` id,
ask it to inspect a test workspace, confirm a `read_file` tool
event is observed).

## 6. What is NOT in this slice (honest gaps)

- `ProviderKind.hermes` and the `provider()` wiring in
  `AssistantSettings.swift` are coordinator-owned and do not exist
  yet: this file references `.hermes` and will not compile until
  the coordinator adds the case. Nothing else in this slice can be
  built or tested until then.
- No ACP support (§2.1): by design, following Legacy. Gateway-side
  cancel and exposing Ycode tools to Hermes remain unavailable.
- No OpenRouter-catalog expansion in availability (§3.2): needs
  the OpenRouter slice's live catalog.
- No `hermes --version` check: Legacy used it only for the
  Settings status card, which is coordinator/UI work; availability
  here is binary presence plus configured-model read.
- No Hermes settings UI: `HermesConfiguration` is a value; the
  coordinator wires it from `AssistantSettings`.
- Credential mappings exist only for `openrouter` and `openai-api`
  (§3.5). Other providers fall back to Hermes' own `.env`.

## Evidence

| Claim | Level | Source |
|---|---|---|
| Stream-json CLI invocation, event types, exit codes, `--in` before subcommand, no `--resume` | 1 | Legacy `SwiftCode/Backend/Assist/HermesProvider.swift` header + `buildArguments` + `execute`, read directly |
| `hermes acp` and `hermes -z` deliberately not used, with reasons | 1 | Same file, header "Deliberately NOT used" |
| One-shot semantics, no tool schemas sent, Hermes tools observed only | 1 | Legacy `HermesSessionRunner.swift` header + `run`; `HermesProvider.swift` header "SwiftCode-native tools" |
| Terminal `result.text` authoritative; empty run fails, never posts empty reply | 1 | Legacy `HermesSessionRunner.swift` (`run`, final-text selection) |
| Prompt delivery as user-turn text via query file; no `--system-prompt`; temp file deleted on every exit path | 1 | Legacy `HermesProvider.swift` (`HermesPromptBuilder`, `execute` query-file handling) |
| Approvals: `single_query_mode` default `deny`; never `--yolo` / `HERMES_YOLO_MODE` / `HERMES_ACCEPT_HOOKS`; controlled PATH/HOME/TMPDIR environment | 1 | Legacy `HermesProvider.swift` header "Approvals"; `Docs/Assist-Hermes-Provider.md` § Approvals and security |
| Model id syntax `hermes:<provider>:<model>` / `hermes:<model>`, prefix rationale, strict parse | 1 | Legacy `HermesProvider.swift` (`HermesModelID`); `HermesProviderTests.swift` cases 1–2 |
| Discovery from `config.yaml` `model.provider`/`model.default`; `hermes model` never launched; OpenRouter catalog expansion when OpenRouter-backed | 1 | Legacy `HermesProvider.swift` (`fetchModels`, `readConfiguredModelSpecs`, `parseModelOutput`) |
| Credentials live in `~/.hermes/.env`; Legacy stores/passes no key; redaction of tool args/results/stderr | 1 | Legacy `HermesProvider.swift` header "Secrets"; `Docs/Assist-Hermes-Provider.md` § Secrets |
| Cancellation is local-only; gateway turn may continue after detach | 1 | Legacy `HermesProvider.swift` (`cancel`); `Docs/Assist-Hermes-Provider.md` § Cancellation |
| Executable discovery order; `hermes --version` for Settings checks only | 1 | Legacy `HermesProvider.swift` (`defaultSearchDirectories`, `resolveExecutable`, `detectVersion`) |
| `AssistModelDiscoveryService.swift` contains no Hermes code | 1 | Grep over the file (1,185 lines, zero `hermes` matches), verified live |
| Host ACP client speaks ACP v1 JSON-RPC (`initialize`/`session/new`/`session/prompt`/`session/cancel`); host CLI-agent pattern is one subprocess + `StreamingSubprocess.lines` + `CLIEventParser` | 1 | Destination `ycode/Sources/YcodeAssistant/ACPClient.swift`, `CLIAgents.swift`; `ycode/Sources/YcodeSubprocess/StreamingSubprocess.swift`, read directly |
| Provider key variables are per-provider env vars (`OPENROUTER_API_KEY`, `OPENAI_API_KEY`); secrets belong in `.env`, other settings in `config.yaml` | 2 | Hermes Agent public docs: Configuration (`hermes config set OPENROUTER_API_KEY …`, `.env` for secrets) and Environment Variables (LLM Providers table), retrieved 2026-11-06 |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

## 4. Apple Foundation Models

Ycode modules: `YcodeAssistant` (the provider), `YcodeAssistantTests`
(its tests). Wave 9 slice: Apple Foundation Models only.

This spec is the behaviour contract for `FoundationModelsProvider`, the
`AssistantProvider` for Apple's on-device Foundation Models framework.
It is Apple Foundation Models **only**: on-device, no network, no account,
no sign-in, no provider picker inside it, and no credential of any kind.
There is no `/models` endpoint — Apple's on-device model is a single
model, and availability reports it as ready with the model Apple reports.
The coordinator adds the `ProviderKind.foundationModels` case and the
`provider()` wiring in `AssistantSettings.swift` at merge time; this
slice assumes that case exists with exactly that name and does not edit
`Core.swift`, `AssistantSettings.swift`, `SecretStore.swift`,
`Package.swift`, `MCPServer.swift`, `MCPServerTests.swift`, or the
ledger.

## 1. Legacy behaviour

### 1.1 The service: `SwiftCode/Services/FoundationModels.swift`

- `FoundationModels` (`@Observable @MainActor`, `shared` singleton) is
  the only Legacy type that touches the framework. It is guarded with
  `#if canImport(FoundationModels)` around the real call; the `#else`
  branch is a simulation (see §1.3, not ported).
- `AppleFoundationModel` enum, two cases: `afm3Core = "AFM 3 Core"` and
  `afm3CoreAdvanced = "AFM 3 Core Advanced"`. The descriptions call
  them an on-device 3-billion-parameter dense model and an on-device
  20-billion-parameter sparse model. The default selection (no
  `UserDefaults` value stored) is `.afm3Core`; the toggle
  `apple_foundation_models_enabled` defaults to on. `statusDescription`
  is `"Ready (On-Device)"` whenever enabled — Legacy never checks the
  system model's real availability.
- `generatePrivateResponse(prompt:systemPrompt:)` (the only real
  generation entry): builds `Instructions` from the system prompt and
  calls `LanguageModelSession(model: SystemLanguageModel(),
  instructions: instructions)`, then `session.respond(to: prompt)` and
  returns `response.content`. **The selected model is never passed to
  the framework** — the session is always built from the system model
  whatever `selectedModel` says. The selection only ever surfaced in
  simulated replies (a `[On-Device <model>]` prefix) and in diagnostics
  strings. The two enum cases are therefore labels Legacy kept, not
  models the framework lets the caller choose.
- `streamPrivateResponse(prompt:onToken:)` does not stream from the
  framework at all: it awaits the whole `generatePrivateResponse`
  result and then re-emits it word by word with a 30 ms sleep. It also
  throws when Foundation Models is disabled.
- `generateConciseTitle(from:)` is a pure string helper (strip code
  fences / mentions / quotes, drop leading request prefixes, keep at
  most 4 words / 24 characters). It uses no model and is not part of
  this slice.

### 1.2 Discovery: `AssistModelDiscoveryService.generateAppleFoundationModels()`

- `generateBaselineModels()` always appends
  `generateAppleFoundationModels()` first, so the models show
  immediately; `discoverAppleFoundationModels()` just returns the same
  list again. Discovery never asks the system whether the model is
  actually present.
- The function returns **two** entries, one per `AppleFoundationModel`
  case (`AppleFoundationModel.allCases.map`):

  | id / `modelIdentifier` | display name | context window | notes |
  |---|---|---|---|
  | `AFM 3 Core` | `Apple AFM 3 Core (On-Device)` | 8,192 | priority 90, `supportsVision` false |
  | `AFM 3 Core Advanced` | `Apple AFM 3 Core Advanced (On-Device)` | 32,000 | priority 91, `supportsVision` true |

  Both: `providerID` `"apple"`, `providerName`
  `"Apple Foundation Models"`, `source` `.appleFoundation`,
  `isConfigured` true, `isAvailable` true, `status` `.available`,
  `statusDescription` `"On-Device Available"`,
  `supportsStreaming` true, `supportsToolCalling` false,
  `supportsStructuredOutput` true, `supportsAgenticUse` true,
  `supportsSubagents` false. Both are undeletable:
  `isFoundationModel(id:source:providerName:)` matches on the source,
  the provider name, `"afm"`/`"apple"` in the id, or either enum raw
  value, and `removeModel` / `removeProvider` refuse Foundation Models.
- The audit (`audit/legacy-subsystem-map.md` §2.3) records this
  accurately: Foundation Models is "surfaced in Assist only via
  `AssistModelDiscoveryService.generateAppleFoundationModels()` — no
  separate Assist provider client."

### 1.3 The simulation branch (NOT ported)

- Where the framework is absent, Legacy's `#else` branch in
  `generatePrivateResponse` returns canned text after a 200 ms sleep:
  a title for prompts containing "title", a JSON
  `{"updatedPrompt": …}` blob for prompts containing "updatedPrompt",
  otherwise `"[On-Device <model>]\nProcessed query with complete
  on-device local privacy guarantees. …"`. A `#if !canImport
  (FoundationModels)` block at the bottom of the file also declares
  stub `SystemLanguageModel` / `LanguageModelSession` types whose
  `respond` returns `"Simulated response"`.
- Ycode does **not** port any of this. A provider that answers from
  canned text while presenting itself as a model would violate the
  host's contract; where the framework is absent this provider reports
  honestly unavailable and `send(_:)` fails (§3, §5).

### 1.4 Legacy callers in Assist (for context, not ported here)

- `AgentModelAdapter` — offline fallback: when a remote call fails it
  forces Foundation Models on and calls `generatePrivateResponse` with
  a rehydrated prompt. `selectBestLocalFallback()` prefers the
  selected Foundation Models entry.
- `AssistConversationHistory` — conversation titles and title
  suggestions via `generatePrivateResponse`, falling back to
  `generateConciseTitle` on failure.
- `PromptEnhancer` — temporarily forces `.afm3Core` and calls
  `generatePrivateResponse`, then restores the selection.
- `CodingToolsService`, `CodeReview`, `WorkerTaskDecomposer`,
  `AssistAgentSession`, `AssistManager` — call
  `generatePrivateResponse` (or gate on `isEnabled`) for code review,
  tool responses, task decomposition, and session fallbacks.
- `AssistFeedbackService` — reports `isEnabled` and `selectedModel`
  in diagnostics. None of these callers pass a model identifier to
  the framework; all of them go through the shared service above.

## 2. What the host already provides vs what this slice adds

| | Host (`YcodeAssistant`) | This slice |
|---|---|---|
| Provider contract | `AssistantProvider`: `kind`, `availability()`, `contextWindow(model:)`, `send(_:)`; `ProviderAvailability` (`.ready` / `.notRunning` / `.noModels` / `.notInstalled` / `.signedOut` / `.failed`); `AssistantError`; `eventStream` helper; `ChatRequest` / `ChatEvent` | `FoundationModelsProvider: AssistantProvider` |
| Existing provider to model on | `OllamaProvider` (HTTP discovery, streaming NDJSON, error mapping, cancellation via `eventStream`) | Same shape, no HTTP: the framework is the transport |
| Model listing | Host has no model-list endpoint concept for this provider | `availability()` returns the single model (see §3) |
| Settings / wiring | `AssistantSettings.provider(_:)` factory (coordinator-owned; this slice does not edit it) | Nothing — the coordinator wires `.foundationModels` at merge time |
| Streaming | `ChatEvent.text` deltas + `.finished(TokenUsage?)` | Deltas derived from cumulative snapshots (§4) |
| Credentials | `SecretStore` (other providers) | None — there is no credential concept in this slice at all |

## 3. The model: one entry, the Legacy default

- `availability()` returns `.ready` with exactly one `ModelInfo`:
  `id` `"AFM 3 Core"`, display name
  `"Apple AFM 3 Core (On-Device)"` — Legacy's default
  `generateAppleFoundationModels()` entry, verbatim. This is one
  model, not a list: the framework exposes a single system model and
  there is no endpoint that could discover more.
- Legacy's second entry, `AFM 3 Core Advanced` (32,000 tokens,
  vision), is **not** exposed. There is no framework API to select
  it, Legacy never passed it to the framework either (§1.1), and
  listing it would present a choice the user cannot make. If a later
  OS exposes a selectable variant, that is a new slice, not a silent
  addition here.
- The context window is **not** Legacy's hardcoded 8,192. On a
  framework platform it is read live from
  `SystemLanguageModel.default.contextSize` (an async `Int`) in both
  `availability()` and `contextWindow(model:)`, because the installed
  model reports its own budget and that is what prompt budgeting
  should use. (Third-party references put the on-device window around
  4,096 tokens; Legacy claimed 8,192 for this entry. The live value
  wins over both — verify the reported number on a Mac, §6.)
  `contextWindow(model:)` returns `nil` for any id other than the
  single model id, and `nil` when the model is not available.
- No model identifier is ever invented beyond the Legacy default
  entry above, and no list of models is constructed anywhere.

## 4. Availability and sending

### 4.1 Availability conditions

The framework ships with macOS 26 / iOS 26 (Apple's public
documentation; the framework and `SystemLanguageModel` are iOS 26+ /
macOS 26+). The model additionally needs Apple
Intelligence-capable hardware and Apple Intelligence turned on, and
the model weights downloaded. The provider checks the real state
instead of Legacy's unconditional `"Ready (On-Device)"`:

| System state | `availability()` |
|---|---|
| Framework absent (this Linux environment; any platform without it) | `.notInstalled`, hint: "Apple Foundation Models is not available on this device. It needs macOS 26 or later on an Apple Intelligence-capable Mac, with Apple Intelligence turned on." |
| Framework present but OS older than macOS 26 / iOS 26 | `.notInstalled`, same hint |
| `SystemLanguageModel.default.availability == .available` | `.ready([ModelInfo])` (§3) |
| `.unavailable(.deviceNotEligible)` | `.notInstalled`, hint: "This device cannot run Apple Foundation Models. It needs an Apple Intelligence-capable Mac." (permanent for the device) |
| `.unavailable(.appleIntelligenceNotEnabled)` | `.failed`, "Apple Intelligence is turned off. Turn it on in System Settings to use Apple Foundation Models." |
| `.unavailable(.modelNotReady)` | `.failed`, "The Apple Foundation Models on-device model is still downloading. Try again later." (transient; there is no download API to trigger) |
| Any other / future reason | `.failed`, "Apple Foundation Models is unavailable on this device." |

Reason cases are matched one by one rather than with an exhaustive
`switch`, so an unfamiliar reason still yields an honest message
instead of breaking the build on a future OS.

### 4.2 Sending

- One session per request: a fresh `LanguageModelSession(model:
  SystemLanguageModel.default, instructions:)` per `send(_:)`, mirroring
  Legacy's one session per `generatePrivateResponse` call. A session
  holds a transcript, so a fresh session keeps requests independent;
  the host owns conversation history and passes it in the request.
- `request.instructions` becomes the session's `Instructions`
  (omitted when empty). The prompt is built from `request.messages`
  only — earlier turns as `<role>\ncontent\n</role>` blocks, then the
  new user message — so the instructions are not duplicated into the
  prompt. An empty request (no messages) fails with
  `AssistantError.failed("There is no message to send.")`.
- Streaming uses `session.streamResponse(to: prompt)`, which yields
  `ResponseStream<String>` snapshots. Each snapshot's `.content` is
  the **whole reply so far**, not a delta, so the provider diffs
  against the previous snapshot and yields only the new suffix as
  `.text`. A snapshot that is not a prefix of the previous text (the
  model revised earlier text) is yielded whole rather than dropped.
  The stream ends with `.finished(nil)`: the framework reports no
  token usage for a stream, so none is claimed.
- No tools are attached to the session. Legacy never gave Foundation
  Models tools, and this provider does not add tool calling.
- Generation options (`maxOutputTokens`, temperature, `topP`) are
  **not** mapped onto the framework's `GenerationOptions` in this
  slice: the exact `streamResponse(to:options:)` shape is unverified
  here, so the model runs on its defaults rather than on a guessed
  call. The context window still bounds a reply.
- Cancelling the consuming task stops the request: the stream loop
  checks cancellation per snapshot and `eventStream` cancels the
  underlying task when the consumer stops (same mechanism as
  `OllamaProvider`).

## 5. Error cases

| Situation | Result |
|---|---|
| Framework absent / OS too old | `send(_:)` throws `AssistantError.failed` with the §4.1 hint; `availability()` is `.notInstalled` |
| Model unavailable at send time | `AssistantError.failed` with the §4.1 reason message |
| `GenerationError.exceededContextWindowSize` | `AssistantError.failed`: "The conversation is too long for the Apple Foundation Models on-device model. Start a new conversation or shorten the request." |
| `GenerationError.rateLimited` | `AssistantError.temporarilyUnavailable`: "Apple Foundation Models is busy right now. Try again shortly." |
| `GenerationError.guardrailViolation` | `AssistantError.failed`: "Apple Foundation Models declined this request." |
| Any other framework error | `AssistantError.failed` with the framework error's description |
| Consumer cancels | `CancellationError` propagates; the stream ends (no partial reply is presented as complete) |

Generation-error cases are matched one by one (§4.1 rationale). The
`GenerationError` case names are taken from public references, not
from a Mac build — see §6.

## 6. What is NOT in this slice / still needs a Mac

- `ProviderKind.foundationModels` and the `provider()` factory case,
  the settings UI, and any model picker: coordinator-owned, added at
  merge time. Until the case exists, this provider's `kind` reference
  does not compile — that is expected and recorded, not a defect in
  this slice.
- **No Mac build or test run exists for this slice.** There is no
  Swift toolchain in this environment, so verification here is static
  checks only (delimiter balance, greps, `git status` scope — see the
  slice report). `swift build` / `swift test` on Dylan's Mac must
  confirm: the `FoundationModels` import and `#available` gating
  compile under the macOS 26 SDK; `LanguageModelSession(model:
  instructions:)` and `streamResponse(to:)` accept the call shapes
  used here; `SystemLanguageModel.default.contextSize` returns the
  expected window; the gated `availabilityOnFrameworkPlatformsIsReadyOrHonest`
  test passes on a Mac with and without Apple Intelligence enabled.
- The real-framework path can only be verified on a Mac with
  Foundation Models (macOS 26+, Apple Intelligence-capable hardware,
  Apple Intelligence on, model downloaded). In particular the exact
  `GenerationError` associated values, the `streamResponse` snapshot
  shape, and the live context-window number are all unverified until
  then. If any call shape is wrong, fix the call — do not fall back to
  canned text.
- Legacy's `generateConciseTitle(from:)` (pure string helper) and the
  Assist callers in §1.4 (offline fallback, titles, prompt
  enhancement, code review) are not ported in this slice; they are
  separate work that consumes this provider.

## Evidence

| Claim | Level | Source |
|---|---|---|
| `FoundationModels.shared`, `AppleFoundationModel` cases/default, `generatePrivateResponse` always using `SystemLanguageModel()`, `streamPrivateResponse` re-emitting whole replies word by word, simulation `#else` branch and stub types, `generateConciseTitle` | 1 | Legacy `SwiftCode/Services/FoundationModels.swift`, read directly |
| `generateAppleFoundationModels()` two entries with ids, display names, context windows 8,192 / 32,000, capabilities, priorities, undeletable; `discoverAppleFoundationModels()` returns the same list; `generateBaselineModels()` appends it first | 1 | Legacy `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` (`generateAppleFoundationModels`, `discoverAppleFoundationModels`, `generateBaselineModels`, `isFoundationModel`, `removeModel`, `removeProvider`), read directly |
| No separate Assist provider client for Foundation Models; surfaced only via discovery | 1 | Legacy subsystem map `audit/legacy-subsystem-map.md` §2.3, verified against the two files above |
| Assist callers (`AgentModelAdapter` fallback, `AssistConversationHistory` titles, `PromptEnhancer`, `CodingToolsService`, `CodeReview`, `WorkerTaskDecomposer`, `AssistManager`, `AssistAgentSession`, `AssistFeedbackService`) | 1 | Legacy `SwiftCode/Backend/Assist/` grep for `FoundationModels`, read directly |
| Host contract: `AssistantProvider`, `ProviderAvailability`, `AssistantError`, `eventStream`, `ChatRequest`/`ChatEvent`; `OllamaProvider` streaming/error/cancellation shape | 1 | Ycode `ycode/Sources/YcodeAssistant/Core.swift`, `OllamaProvider.swift`, read directly |
| Framework is macOS 26 / iOS 26+; `SystemLanguageModel.default` is the entry point; `.availability` is `.available` / `.unavailable(.deviceNotEligible \| .appleIntelligenceNotEnabled \| .modelNotReady)`; `isAvailable` shorthand; `contextSize` is an async `Int` on the default model; `LanguageModelSession(model:instructions:)` and `streamResponse(to:)` yielding cumulative `ResponseStream<String>` snapshots with `.content`; `GenerationError` cases `exceededContextWindowSize` / `rateLimited` / `guardrailViolation` | 1 | Public documentation and references: conor.fyi "iOS 26 FoundationModels: Comprehensive Swift/SwiftUI Reference" (availability, session init, streaming, `contextSize`, generation errors); emrldlabs "Foundation Models Framework: On-Device LLMs in Swift" (framework scope, `SystemLanguageModel.default`, streaming). Apple's own developer documentation page for `SystemLanguageModel` returned no extractable content when fetched in this environment, so the Apple-direct check is still open — the call shapes above are **unverified until a Mac build** (see §6) |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

## 5. SwiftCode Cloud (SCCloud)

SwiftCode's own hosted models, as an `AssistantProvider` on the Ycode
assistant host (`ycode/Sources/YcodeAssistant/SCCloudProvider.swift`).

## 1. Legacy behaviour

Source (read directly, Legacy repo main @ `d51a8f0d`, read-only):

- `SwiftCode/Backend/Assist/SCCloudModel.swift` (~1000 lines):
  `SCCloudConfiguration`, `SCCloudModelInfo`, `SCCloudModelDiscovery`,
  `SCCloudDeviceFingerprint`, `SCCloudRateLimiter`, `SCCloudModelClient`,
  `SCCloudError`.
- `SCCloudModelsEndpoint.js` (repo root, 232 bytes): a Node module
  exporting a single `endpoint` string. Legacy reads it dynamically at
  runtime (bundle resources, working directory, home directory, and
  walking up from the app executable) so the URL can change without
  recompiling.
- `SwiftCode/SDK/Contracts/Protocol/SDKCloudModelContracts.swift` and
  `SwiftCode/SDK/Host/ServiceAdapters/CloudModel/SDKCloudModelAdapter.swift`:
  the SDK-side contract for the `use.SwiftCodeModel` capability's
  `cloudModel.complete` method. The adapter passes only
  extension-supplied content (prompt, history, system prompt, optional
  model identifier) to the host's `SCCloudModelClient` and receives only
  the assistant's text; the endpoint URL, fingerprint, and quota
  internals never cross the SDK boundary. Input bounds there: prompt
  ≤ 64 KiB, ≤ 100 history entries, ≤ 16 KiB per history entry, system
  prompt ≤ 16 KiB, model identifier ≤ 256 chars. The adapter is out of
  scope for this slice (no SDK platform exists in the destination yet);
  it is recorded here so a later SDK slice knows the contract it must
  honour.
- `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift`: no
  SCCloud parts — SCCloud discovery lives entirely in
  `SCCloudModelDiscovery` inside `SCCloudModel.swift`, not in the shared
  discovery service.

### 1.1 Endpoint handling (including the dead tunnel)

- Legacy resolves the base URL in this order: the
  `swiftcode_cloud_endpoint_url` UserDefaults override, then the URL
  parsed out of `SCCloudModelsEndpoint.js`, then a hardcoded fallback
  (`SCCloudConfiguration.defaultBaseURLString`,
  `SCCloudModel.swift:45`).
- The JS file and the hardcoded fallback both name the same endpoint:
  an ephemeral Cloudflare tunnel. The migration audit (§4.4, item 2)
  records it as almost certainly dead/rotated, and this slice does not
  reproduce the URL anywhere — not in source, tests, fixtures, or this
  spec.
- `isConfigured` in Legacy is true only for a non-empty `https` URL
  with a host.
- The port drops the JS-file mechanism and the hardcoded fallback
  entirely. The base URL comes from one place only: the host settings
  field `scCloudURL` (coordinator-owned, default empty string). There
  is no default URL anywhere in the port.

### 1.2 Auth flow — a device fingerprint, NOT an API key

Legacy has no API key, token, or sign-in for SCCloud. Authentication
is a per-device fingerprint:

- Header: `X-SwiftCode-Device-Fingerprint` on every request, including
  model discovery (discovery is explicitly not counted against the
  daily chat quota).
- Value: `ssc_` + hex(SHA-256(stable hardware material)). Material is
  the host UUID, hardware model, CPU brand/count, and non-loopback IP
  addresses. The raw values are hashed in memory and never persisted;
  only the final `ssc_…` identifier is stored, in the Keychain, and it
  is never exposed to the UI.
- The fingerprint is generated on first use, when the user enables the
  "Use SwiftCode's Cloud Model" toggle, and the backend enforces the
  same fair-use policy server-side from the header alone.

Consequence for the host: **no `sccloud.api-key` SecretAccount entry
is needed or created.** The coordinator must instead provision and
persist the fingerprint (the provider exposes
`SCCloudProvider.provisionFingerprint()` for that) and pass it into
`SCCloudProvider(baseURL:fingerprint:)`. If a future SCCloud server
gains API-key auth, that is a new credential, not something Legacy
had.

### 1.3 Model discovery

- Wire format is OpenAI-compatible (Legacy's configured format):
  discovery is `GET /v1/models`, chat is `POST /v1/chat/completions`.
  Legacy also defines an Ollama-native alternative (`GET /api/tags`,
  `POST /api/chat`); it is not the configured format and the port does
  not implement it.
- Discovery parses the OpenAI shape `{ "data": [ { "id": "…",
  "owned_by": "…" } ] }`, canonicalizes each ID by stripping a
  trailing `:latest` tag, deduplicates, and sorts by name.
- Results are cached in memory and persisted to Application Support
  (`sccloud-models.json`) with a **1-hour TTL**. A failed refresh never
  wipes the previous list. When the endpoint URL changes, stale models
  from the old URL are evicted immediately.
- Legacy's internal ID scheme is `swiftcode-cloud:<endpoint-name>`
  (plus the bare legacy `swiftcode-cloud` single-model ID, which names
  no server-side model). Callers resolve through
  `endpointName(forInternalID:)`; the picker shows the endpoint name
  verbatim.
- Legacy keeps a curated `modelBlurbs` table keyed by canonical model
  name (descriptions for the picker). The port does **not** carry it:
  it is a frozen list of model names, which contradicts dynamic
  discovery, and its entries describe models a future endpoint may not
  serve.

### 1.4 Request / response shapes

- Chat request (both wire formats): `POST` with JSON body
  `{ "model": "<endpoint name>", "messages": [{ "role", "content" }…],
  "stream": false }`, `Content-Type: application/json`, the
  fingerprint header, 180 s request timeout / 300 s resource timeout.
  The system prompt, when present, is inserted as the first history
  entry. The model sent is the exact server-side name of the selected
  discovered model — never a hardcoded single model; when no
  discovery result exists yet and no fallback name is configured,
  the client fails with `noModelAvailable` (Legacy's
  `defaultModelIdentifier` is the empty string).
- Response parsing, in order: OpenAI-style
  `choices[0].message.content`; Ollama-style `message.content`;
  single-string shapes under `response`, `output`, `text`,
  `content`, `result`, `answer`; finally a bare non-empty string body.
  Anything else is `invalidResponse`.
- Errors: `notConfigured`, `fingerprintUnavailable`,
  `rateLimited(retryAfter:)`, `network`, `server(statusCode:message)`,
  `invalidResponse`, `noModelAvailable`. HTTP 429 is treated as rate
  limited. Server errors keep the full body (capped at 8000 chars)
  for a Server Error dialog; the chat line shows a 300-char preview.
  A 530 / tunnel-error signature (or an HTML body) gets the specific
  "server is currently offline or unreachable (Cloudflare Tunnel
  Error 530/1033)" message.
- Fair use: **10 requests per rolling 24-hour window**, enforced by
  `SCCloudRateLimiter` with timestamps persisted in Application
  Support (`sccloud-usage.json`). The gate is checked before sending;
  any completed HTTP round-trip counts against the quota, success or
  failure. Quota frees up gradually as old requests age out of the
  window.

## 2. What Ycode's host already provides vs what this slice adds

Host already provides (unchanged by this slice):

- `AssistantProvider` (`kind`, `availability()`,
  `contextWindow(model:)`, `send(_:)` streaming `ChatEvent`s),
  `ModelInfo`, `ProviderAvailability` (`.ready` / `.notRunning` /
  `.noModels` / `.notInstalled` / `.signedOut` / `.failed`),
  `AssistantError`, the `eventStream` helper, and the `HTTP` /
  `SSEDecoder` / `JSON` helpers (`HTTP.send`, `HTTP.url`,
  `HTTP.errorMessage`, `HTTP.isUnreachable`).
- A pure-Swift SHA-256 and secure random bytes (`Crypto.swift`),
  reused for fingerprint provisioning so the module still builds on
  Linux without CryptoKit.
- `SecretStore` (Keychain on macOS, 0600 files on Linux) for the
  coordinator to persist the provisioned fingerprint in.

This slice adds (`ycode/Sources/YcodeAssistant/SCCloudProvider.swift`):

- `SCCloudProvider: AssistantProvider` with `kind == .scCloud`
  (case added by the coordinator), `init(baseURL:fingerprint:cache:limiter:)`.
  `baseURL` defaults to `""` — unconfigured — and there is no default
  URL constant anywhere.
- `availability()`: `.signedOut` with `unconfiguredHint` when no
  endpoint is configured; otherwise live discovery against
  `GET /v1/models`, returning `.ready(models)` / `.noModels` /
  `.notRunning` (unreachable) / `.failed` (other errors). The hint
  names exactly what must be supplied: a real SCCloud endpoint URL
  in Settings ▸ Coding Assistant.
- `listModels()`: dynamic discovery only — parses the endpoint's
  `/v1/models` into `[ModelInfo]` (canonicalized, deduplicated,
  sorted). No frozen model list anywhere.
- `SCCloudModelCache`: in-memory discovery cache, **TTL 1 hour**,
  endpoint-keyed (a URL change evicts immediately). A failed refresh
  serves the previous list when one exists.
- `send(_:)`: non-streaming `POST /v1/chat/completions` with
  `stream: false` (as in Legacy — the whole reply arrives as one
  `.text` event followed by `.finished(nil)`), the fingerprint
  header, the 10/day gate checked first, and the completed round-trip
  recorded against the quota. Model resolution: explicit model
  first (a Legacy-style `swiftcode-cloud:<name>` ID is unwrapped),
  otherwise the first discovered model.
- `contextWindow(model:)`: the context window reported by discovery
  for that model, when the endpoint reports one (the OpenAI-compatible
  list normally does not; Legacy captured it only from Ollama tags).
- `SCCloudRateLimiter`: 10 requests per rolling 24 hours, in-memory
  in this port (see §3).
- `provisionFingerprint()`: `ssc_` + hex(SHA-256(random 32 bytes))
  for the coordinator to call once and store.
- Static, testable parsers: `parseModels(_:)`,
  `parseResponse(_:)`, `canonicalModelName(_:)`,
  `endpointName(forInternalID:)`, `mapHTTPError(status:body:)`.

The coordinator still owns (not in this slice): the `.scCloud`
`ProviderKind` case, the `scCloudURL` settings field (default `""`),
the `provider()` wiring in `AssistantSettings.swift`, and the
fingerprint provisioning/storage call. Until those land, this file
references `.scCloud` and does not compile on its own — that is
expected and recorded in the slice report.

## 3. Deliberate deviations from Legacy (all documented in code)

1. **No default endpoint, no JS-file endpoint.** Legacy's fallback
   and `SCCloudModelsEndpoint.js` are dropped, not ported. The URL
   comes only from `scCloudURL`.
2. **Fingerprint material is random, not hardware-derived.** Legacy
   hashes stable hardware identifiers (host UUID, `hw.model`, CPU
   brand, IP addresses) via CryptoKit/`gethostuuid`/`sysctl`. The
   portable assistant target has no hardware-identity API, so the
   port generates `ssc_` + SHA-256 of 32 random bytes once and relies
   on the host storing it. The `ssc_` shape, the header name, and the
   Keychain/secret-store confinement are preserved; the derivation
   is not. A stored random identity is stable across restarts exactly
   like Legacy's, as long as the coordinator stores it.
3. **Discovery cache and rate-limiter timestamps are in-memory
   only.** Legacy persisted both to Application Support
   (`sccloud-models.json`, `sccloud-usage.json`). A host restart here
   re-discovers and resets the local quota window. The backend still
   enforces the same 10/day limit independently via the fingerprint
   header, so the cap itself is not bypassed — only the local
   pre-check restarts fresh.
4. **`modelBlurbs` not ported** (frozen model-name list; see §1.3).
5. **Ollama-native wire format not ported** (not Legacy's configured
   format; see §1.3).
6. **Loopback HTTP allowed.** Legacy's `isConfigured` requires
   `https`. The port also accepts `http` for loopback hosts only
   (`127.0.0.1`, `localhost`, `::1`), so tests and local development
   servers work; every other host still requires `https`.
7. **SDK adapter not ported.** `SDKCloudModelAdapter` /
   `SDKCloudModelContracts` belong to the SDK platform slice, not to
   the assistant provider. Their contract (§1, first bullet) is
   recorded here for that later slice.

## 4. Dead-endpoint status and what Dylan must supply

**Status: SCCloud is honestly unavailable until Dylan supplies a real
endpoint.** The Legacy endpoint was an ephemeral tunnel; it is dead,
and the port ships no replacement and no default. With no endpoint
configured, `availability()` returns `.signedOut` with the hint
quoted in §2, and `send(_:)` throws
`.notSignedIn` with the same hint. Nothing is faked: no canned model
list, no canned responses.

To enable SCCloud, Dylan must supply:

1. **A real SCCloud endpoint URL** — a stable HTTPS base URL serving
   the OpenAI-compatible API (`GET /v1/models`,
   `POST /v1/chat/completions`), entered in Settings ▸ Coding
   Assistant (`scCloudURL`). A tunnel URL that can rotate is not
   acceptable as a shipped default; if a tunnel is used for testing,
   it must be re-entered each time it rotates.
2. Nothing else. There is no API key, account, or sign-in to supply:
   the device fingerprint is generated automatically on first enable
   and stored in the secret store, and the 10/day fair-use limit is
   enforced by the endpoint from that fingerprint.

When an endpoint IS configured, discovery and chat are real network
calls against it — never canned responses.

## 5. Error cases

| Situation | Result |
|---|---|
| No endpoint configured (`scCloudURL` empty, malformed, or non-HTTPS non-loopback) | `availability()` → `.signedOut` with the unconfigured hint; `send(_:)` throws `.notSignedIn` with the same hint |
| Endpoint unreachable (DNS / refused / lost) | `.notRunning` ("Check the network connection and that the SCCloud endpoint is running."); `send` throws `.unreachable` |
| Endpoint answers non-2xx on discovery | `.failed` (or the previous cached list is served when one exists) |
| Endpoint lists no models | `.noModels` ("SwiftCode Cloud lists no models at …") |
| Endpoint rejects the device identity (401) | `.signedOut` ("The SCCloud endpoint rejected this device's identity. Toggle the cloud model off and on again…") |
| No fingerprint provisioned yet | `send` throws `.failed` (toggle the cloud model off and on again) |
| No model selected and discovery is empty | `send` throws `.failed` ("SwiftCode Cloud lists no models. … refresh the model list…") |
| Daily quota exhausted (local gate or HTTP 429) | `.usageLimit` with the retry-after duration when known |
| Tunnel down (HTTP 530, tunnel-error text, or HTML body) | `.temporarilyUnavailable` (tunnel-error message, as in Legacy) |
| Other HTTP error | `.http(status:message)` with a 300-char preview |
| Unparseable response body | `.malformed` ("…returned a response that could not be understood.") |
| Server closes the stream / times out | `.unreachable` / the underlying network error (180 s timeout) |

## 6. Tests

`ycode/Tests/YcodeAssistantTests/SCCloudProviderTests.swift`
(uses the shared `LoopbackServer`, `Recorder`, and `collect`
helpers from `ProviderTests.swift`; no live network):

- Unconfigured provider reports `.signedOut` with a hint naming the
  endpoint URL; malformed / non-HTTPS URLs are unconfigured; a
  well-formed but unreachable HTTPS URL reports `.notRunning`.
- `send` without an endpoint throws `.notSignedIn`.
- `parseModels` canonicalizes (`:latest` stripped), deduplicates,
  sorts, and ignores malformed entries; non-JSON / empty bodies
  yield no models.
- Internal-ID unwrapping (`swiftcode-cloud:<name>` → `<name>`,
  bare `swiftcode-cloud` → nil, non-cloud IDs untouched).
- `parseResponse` accepts all four Legacy shapes and rejects empty
  / unparseable bodies.
- `provisionFingerprint()` yields `ssc_` + 64 hex chars, distinct
  per call.
- `SCCloudRateLimiter` gates after its limit and formats durations
  (`7h 12m`, `5m`).
- Discovery + chat against a fake loopback endpoint: models listed,
  context window read, chat returns the reply text, the fingerprint
  header is present on both requests, and no `Authorization` header
  is ever sent; the chat body carries `stream: false` and the
  system instruction as the first message.
- Legacy internal IDs are unwrapped on send; with no model selected
  the first discovered model is used.
- HTTP 429 → `.usageLimit`; HTTP 530 + HTML body →
  `.temporarilyUnavailable`.
- An exhausted local quota blocks before any network use.

No Swift toolchain exists in this environment, so `swift build` /
`swift test` were not run — static checks only. The Mac build/test
remains pending, including the fact that the test file references
`ProviderKind.scCloud`, which the coordinator adds at merge time.

## Evidence

| Claim | Level | Source |
|---|---|---|
| Endpoint resolution order (UserDefaults override → JS file → hardcoded fallback), JS-file search paths, regex URL parsing | 1 | Legacy `SwiftCode/Backend/Assist/SCCloudModel.swift` (`SCCloudConfiguration`), read directly |
| Hardcoded fallback is a dead ephemeral tunnel; audit verdict | 1 | Legacy `SCCloudModelsEndpoint.js` (232 bytes), read directly; migration audit `legacy-subsystem-map.md` §4.4 item 2 |
| OpenAI-compatible wire format is the configured one; Ollama-native is the unused alternative; paths `/v1/chat/completions`, `/v1/models`, `/api/chat`, `/api/tags` | 1 | Legacy `SCCloudModel.swift` (`wireFormat`, path constants) |
| Fingerprint header name, `ssc_` + SHA-256 shape, hardware material sources, Keychain storage, never exposed to UI | 1 | Legacy `SCCloudModel.swift` (`SCCloudDeviceFingerprint`) |
| 10/day rolling 24 h limit, gate-then-record, round-trip counts even on failure, persisted timestamps | 1 | Legacy `SCCloudModel.swift` (`SCCloudRateLimiter`, `SCCloudModelClient.complete`) |
| Discovery parsing (OpenAI `data[].id`, Ollama `models[].name` + `details.context_length`), `:latest` canonicalization, 1-hour TTL, endpoint-change eviction, failed refresh keeps cache | 1 | Legacy `SCCloudModel.swift` (`SCCloudModelDiscovery`) |
| Internal ID scheme `swiftcode-cloud:<name>`, bare legacy ID, endpoint-name resolution | 1 | Legacy `SCCloudModel.swift` (`modelIDPrefix`, `endpointName(forInternalID:)`, `internalID(forEndpointName:)`) |
| Non-streaming chat (`stream: false`), request/response shapes and parse order, 180 s / 300 s timeouts, system prompt first | 1 | Legacy `SCCloudModel.swift` (`makeRequest`, `parseResponse`, `complete`) |
| Error taxonomy and user-facing messages, 429 → rate limited, 530/tunnel-error handling, 8000-char body cap, 300-char preview | 1 | Legacy `SCCloudModel.swift` (`SCCloudError`) |
| SDK contract: adapter passes only extension content, host owns endpoint/fingerprint/quota, input bounds | 1 | Legacy `SwiftCode/SDK/Contracts/Protocol/SDKCloudModelContracts.swift`, `SwiftCode/SDK/Host/ServiceAdapters/CloudModel/SDKCloudModelAdapter.swift` |
| `AssistModelDiscoveryService.swift` has no SCCloud parts | 1 | Grep over Legacy `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` for `SCCloud` — no hits |
| No API key / token / sign-in exists for SCCloud in Legacy | 1 | Full read of `SCCloudModel.swift` — the only credential is the device fingerprint; no `Authorization` header is set anywhere in the file |
| Host protocol, availability cases, error types, HTTP/SSE/JSON helpers, SHA-256 + SecureRandom in-module | 1 | Destination `ycode/Sources/YcodeAssistant/Core.swift`, `HTTP.swift`, `Crypto.swift`, `SecretStore.swift`, `AssistantSettings.swift` |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
