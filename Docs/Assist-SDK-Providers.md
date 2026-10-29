# Assist SDK Providers: OpenCode SDK + OpenRouter Agent SDK

Status: implemented on main, statically verified only. No Xcode build,
in-app test run, or live provider session has been executed in the
Linux environment used for this work (no Swift/Xcode toolchain there).
See "Not verified — Mac checklist" at the end.

This document supersedes the transport approach in
`Docs/Assist-OpenCode-OpenRouter-Providers.md` (native Swift HTTP
clients). The HTTP clients (`OpenCodeClient`, `OpenRouterClient`) are
left in the tree for their other consumers (connection tests, model
discovery, chat mode); agent-mode sessions for these two providers now
run through the real SDKs. Nothing falls back to HTTP when the SDK
path is selected.

## Packages (verified against the official docs and the installed packages)

- OpenCode: `@opencode-ai/sdk@1.19.5`, `npm install @opencode-ai/sdk`.
  `createOpencode({hostname, port, signal})` starts a server + client;
  `createOpencodeClient({baseUrl})` connects to an existing server;
  the v2 client adds flat parameters and `global.health()`.
- OpenRouter: `@openrouter/agent@0.11.0`, `npm install @openrouter/agent`.
  `callModel(client, {model, input, instructions, tools, stopWhen,
  allowFinalResponse, signal})` owns the multi-turn loop; `tool()` takes
  a Zod v4 `inputSchema` and an `execute` callback; stop conditions
  include `stepCountIs`, `maxCost`, `maxTokensUsed`.
- Do NOT install `@openrouter/sdk` for agent work: the agent toolkit
  moved to `@openrouter/agent` (see the official migration doc). The
  agent package bundles its own OpenRouter client.

## Architecture

SwiftCode remains the host and control plane. Each SDK runs in a
separate Node (preferred) or Bun child process — a JS bridge host —
talking NDJSON over stdin/stdout. There is no JS runtime embedded in
the app and no second settings system, model picker, or tool registry.

```
AssistAgentSession.start (agent mode)
  -> AssistSDKSessionRunner.applicableKind(for: selectedModel)
  -> OpenCodeSDKProvider / OpenRouterSDKProvider (Swift actors)
  -> FoundationProcessBridgeLauncher (Process, argument arrays only)
  -> node SDKHosts/opencode-bridge.mjs | openrouter-bridge.mjs
       opencode: @opencode-ai/sdk session.promptAsync + event.subscribe
       openrouter: @openrouter/agent callModel + tool() execute callbacks
  -> tool_call lines back to Swift for SwiftCode-native tools
  -> SDKToolEventStore -> ORToolsUIView / OCToolsUIView
```

Key files:

- `SwiftCode/Backend/Assist/SDKRuntimeManager.swift` — install,
  verification, Settings status, Process supervision for installs.
- `SwiftCode/Backend/Assist/SDKHosts/opencode-bridge.mjs`,
  `SDKHosts/openrouter-bridge.mjs` — JS bridge hosts (bundle resources,
  not Xcode target sources).
- `SwiftCode/Backend/Assist/OpenCodeSDKProvider.swift`,
  `OpenRouterSDKProvider.swift` — Swift facades. Both share
  `SDKBridgeLaunching` / `FoundationProcessBridgeLauncher` (defined in
  the OpenCode file) and the NDJSON contract.
- `SwiftCode/Backend/Assist/AssistSDKSessionRunner.swift` — the single
  seam into `AssistAgentSession`: routing, bridge install checks,
  request construction, native tool execution, event publishing.
- `SwiftCode/Backend/Assist/SDKToolEvent.swift`,
  `SDKToolEventStore.swift` — shared event contract + store.
- `SwiftCode/Views/Assist/ORToolsUIView.swift`,
  `OCToolsUIView.swift` — provider tool views, rendered by
  `AssistChatBubble` under the SDK run's own transcript message.

## Routing (read this before changing it)

`AssistSDKSessionRunner.applicableKind` decides the SDK path:

1. `opencode:provider/model` ids → OpenCode (checked first).
2. Otherwise, only ids containing `/` are candidates. The discovery
   record for the exact model id is authoritative: providerID
   `openrouter` → OpenRouter SDK; any other provider record vetoes
   the SDK path. Without a discovery record, the persisted provider
   selection (`assist.selectedProvider`) and then the adapter
   specification are consulted.

This order exists because name heuristics alone misroute: a discovered
OpenRouter id such as `anthropic/claude-sonnet-4-5` would otherwise be
read as native Anthropic, and routing on the name alone could silently
move a native model to OpenRouter billing. Bare ids without `/` (native
Anthropic ids carry no slash) never take the SDK path.

The SDK branch runs in `AssistAgentSession.start` after the agent-mode
guard and BEFORE legacy validation (a managed OpenCode server is not
running yet at validation time, so the old reachability check would
fail it). Chat-mode OpenRouter traffic via `LLMService` is unchanged;
only agent-mode sessions use the SDKs. A failure on the SDK path is
terminal for the turn — it never falls back to HTTP or another
provider.

## Runtime installation and Process lifecycle

- Location: `~/Library/Application Support/SwiftCode/SDKRuntime/
  {opencode,openrouter}/`, with `node_modules/` and `bridge/` beneath
  it. Never the app bundle (bundles are read-only after install) and
  never the workspace. Uninstall is deleting that directory.
- Install: per-provider `package.json` pinning the exact versions
  above plus the generated lockfile, via `npm install --no-audit
  --no-fund` (or `bun install`). Single-flight per provider, 300 s
  timeout, cancellation, drained stdout/stderr (no pipe deadlock),
  minimal env, nonzero-exit surfacing, partial-install cleanup.
- Verification: every status call re-reads
  `node_modules/<pkg>/package.json`; a missing file or version
  mismatch is a corrupt install that triggers Repair, never reuse.
- Runtime prerequisite: Node (preferred) then Bun, resolved from PATH
  plus well-known locations by executable bit. Neither found is an
  actionable `runtimeMissing` error, never a silent success. SwiftCode
  does not bundle Node/Bun and does not download a runtime.
- Bridges: launched with argument arrays only, controlled cwd
  (the runtime directory, so ESM imports resolve from `node_modules`),
  minimal env (PATH/HOME/TMPDIR). Readiness is the bridge's first
  `{"type":"ready"}` line after SDK imports resolve (30 s timeout);
  a running process alone is never treated as ready. OpenCode
  readiness additionally requires `global.health()` healthy.
  Termination is SIGTERM → grace → SIGKILL, targeting only PIDs
  SwiftCode started; external OpenCode servers are never closed or
  killed. Cancellation aborts the server/SDK session first, then
  terminates the bridge after a grace period.
- Bridge scripts ship as bundle resources (`.mjs` in the Resources
  build phase, following the `ReverseBridge.mjs` precedent) and are
  copied into the runtime `bridge/` directory on first use.
- Known split of responsibilities: `SDKRuntimeManager.launchBridge`
  (manager-owned bridges, used by Settings Stop) and the providers'
  `FoundationProcessBridgeLauncher` (session bridges) are two launch
  paths by design in this version — the providers' path is the one
  exercised by the bridge tests. Unifying them is a follow-up, not a
  silent assumption: Settings Stop does not terminate an active
  session bridge; session cancellation does.

## Providers and settings

Assist Settings → **SDK Providers** (after the OpenRouter & OpenCode
section): per-provider runtime status (runtime found, SDK installed +
version, or missing with an actionable error), Install / Repair /
Refresh-status / Stop-bridge buttons, and the **Tool Source** picker
bound to `assist.toolSource` (default `swiftcode`). Provider identity
(`assist.selectedProvider`), model selection
(`selectedAssistModelID`), and credentials keep their existing keys;
changing the tool source never changes provider, model, system prompt,
or credentials.

The previous OpenRouter & OpenCode section (key status, connection
test via `/models`, model discovery, OpenCode server URL / agent /
managed-server toggle) is unchanged and remains the connection-test
path — note `@openrouter/agent` has no cost-free key check, so the
bridge's `ready` proves only that SDK imports resolve; authentication
is proven by the Settings `/models` check and by the first run's 401
surfacing as an actionable invalid-key error.

## System Assets

The runner passes `AssistManager.getSystemPrompt()` verbatim:

- OpenCode: the prompt's `system` field on every `promptAsync` turn
  (initial and each tool-result follow-up), so multi-turn runs cannot
  drift to server defaults. History is folded into the prompt text
  because `promptAsync` has no history parameter.
- OpenRouter: the SDK's `instructions` field, which the SDK re-sends
  with the full accumulated input on every turn (verified in the
  installed `async-params.d.ts` + README). History + user text become
  `input` items; unknown roles map to `user`.

No provider default prompt is ever substituted, and no prompt is
hardcoded into a bridge file. Updated assets reach the next run
through the established loading mechanism.

## Tool ecosystems and tool-source selection

`assist.toolSource` values: `swiftcode`, `openrouter`, `opencode`,
`combined` (default `swiftcode`). The picker text states plainly that
provider tools run under the provider runtime's permissions.

- **SwiftCode tools** (both providers): the bridge receives the
  registered tool schemas (all non-disabled tools from
  `AssistToolRegistry`). Tool calls come back as `tool_call` lines and
  execute in Swift through `AssistSDKSessionRunner.executeNativeTool`:
  registry validation (registration, disabled/unavailable, required
  args, types, path traversal) with the validated corrected input,
  then `tool.execute(input:context:)` with the session's
  `AssistContext`, then `AssistToolResultFormatter.modelFacingPayload`.
  A failed validation, unknown tool, or unsuccessful result throws
  and is reported to the model as a tool error — never as success.
  Name collisions in combined mode resolve deterministically: the
  SwiftCode tool wins (OpenRouter renames its host tool to
  `openrouter_<name>`; OpenCode disables the colliding built-in via
  the prompt tools map — it does not rename server tools).
- **OpenRouter tools**: exactly two real host-side tools implemented
  in the bridge — `fetch_url` (GET only, http/https, loopback/private
  IP blocking including DNS-resolution checks, 15 s timeout, 200 KB
  cap, no credentials forwarded, binary content not returned) and
  `current_datetime`. Neither touches the filesystem or shell.
- **OpenCode tools**: the server's built-in tools, executed by the
  server. Permission requests are default-deny: the bridge replies
  `reject` via the verified permission API and emits a failed
  tool event with an explicit permission-denied error. Nothing is
  auto-approved.
- **Unsupported combinations are explicit errors, not fallbacks**:
  `openrouter` tools for OpenCode, `opencode` tools for OpenRouter.
- **Isolation**: every event carries `source` (swiftcode/openrouter/
  opencode) and `provider` (the serving runtime). Execution routing
  keys on `source`, never on display name. The combined-mode
  `opencode_` prefix idea from early UI notes was NOT implemented:
  server tools keep their real names and collisions are resolved by
  disabling, which is enforceable server-side.

Safety scope, stated honestly: SDK runs do NOT apply the plan-based
phase allowlist (that control belongs to the plan execution path).
They rely on registry validation plus the tool-level permission
checks in `AssistContext` — the same checks plan tools go through at
execution time, including the Autopilot semantics of the existing
permissions manager. Provider-managed tools (OpenCode built-ins,
OpenRouter host tools) run under the provider runtime's permissions,
not SwiftCode's; that is why the picker warns about combined mode.

## Native tool-call interfaces

- `ORToolsUIView(events:)` renders events whose serving provider is
  `openrouter`; `OCToolsUIView(events:)` renders `opencode` events.
  (Integration correction to the original source-only filter: a
  SwiftCode-source call bridged through an SDK run still belongs to
  that run's view, because the native plan UI does not render SDK
  runs. Each event still renders in exactly one provider view.)
- Rows are keyed by `toolCallId`, so streaming merges update rows in
  place without duplication or lost expansion state. States:
  requested (Pending) → running → completed/failed/cancelled, with
  terminal states never regressing and a nil result never overwriting
  an existing one. Arguments render as parsed key/value rows with a
  disclosure for full redacted text; results show only for completed
  calls, errors only for failed/cancelled. Arguments/results are
  redacted (keys containing password/token/key/secret/authorization)
  in the bridges and again in the views' safe accessors.
- Wiring: `AssistChatBubble` renders the appropriate view under
  exactly the SDK run's transcript message (keyed by
  `AssistAgentSession.sdkMessageId` + `sdkSessionId`/`sdkSessionKind`,
  reading a snapshot from `SDKToolEventStore`). No sample data: an
  empty snapshot renders nothing.
- `SDKToolEvent` decoding note: timestamps are ISO 8601 on the wire;
  bridge-side Swift decoding must use `.iso8601` (the struct itself
  sets no strategy).

## Subagent work (workstreams, §19)

Four parallel workstreams with explicit file ownership and a shared
NDJSON contract, all integrated and reviewed by the parent:

- **D — Runtime infrastructure + Settings**: `SDKRuntimeManager`,
  Settings SDK Providers section, tool-source persistence.
- **A — OpenCode SDK**: `opencode-bridge.mjs`,
  `OpenCodeSDKProvider.swift`; verified SDK APIs against the installed
  package (v2 client, `tool.ids()`, permission reply API).
- **B — OpenRouter Agent SDK**: `openrouter-bridge.mjs`,
  `OpenRouterSDKProvider.swift`; verified `callModel`/`tool`/stop
  conditions against the installed package; found and fixed two real
  bugs via tests (a `maxCost` name shadow, structured SDK error
  objects needing extraction).
- **C — Native tool UI**: `SDKToolEvent`, `SDKToolEventStore`,
  `ORToolsUIView`, `OCToolsUIView`, following the Muse Tool view's
  visual language.

Conflicts resolved by the parent at integration:

- **Duplicate `SDKToolSource` type** (C's event source vs D's setting,
  the latter with `.combined`): D's renamed to `SDKToolSourceSetting`.
- **Two launch paths** (D's `launchBridge` takes no argv; OpenCode
  needs `--server-url`/`--managed`): providers keep the shared
  `FoundationProcessBridgeLauncher` they were tested with;
  `SDKRuntimeManager` remains the install/verify/status authority.
  Documented above as a known split, not hidden.
- **Combined-mode collision semantics**: disable, not rename, for
  OpenCode (see above).
- **View filter**: provider-based, not source-only (see above).
- **OpenRouter routing**: discovery-record-first, not name
  heuristics (see Routing).

## Changed files

New: `Backend/Assist/SDKRuntimeManager.swift`,
`Backend/Assist/SDKHosts/opencode-bridge.mjs`,
`Backend/Assist/SDKHosts/openrouter-bridge.mjs`,
`Backend/Assist/OpenCodeSDKProvider.swift`,
`Backend/Assist/OpenRouterSDKProvider.swift`,
`Backend/Assist/AssistSDKSessionRunner.swift`,
`Backend/Assist/SDKToolEvent.swift`,
`Backend/Assist/SDKToolEventStore.swift`,
`Backend/Assist/SDKProviderTests.swift`,
`Views/Assist/ORToolsUIView.swift`, `Views/Assist/OCToolsUIView.swift`,
`Docs/Assist-SDK-Providers.md`. (`agent_notes.md` at the repo root
holds the same findings in short form but is gitignored by repo
convention — `.gitignore:50` — so it stays local-only and is not
part of this commit.)

Edited: `Backend/Assist/AssistAgentSession.swift` (SDK branch +
cancellation + transcript keys), `Views/Assist/AssistMainView.swift`
(SDK panel in `AssistChatBubble`),
`Views/Settings/AssistSettingsView.swift` (SDK Providers section),
`Backend/Assist/AssistRuntimeTestSuite.swift` (SDK tests),
`SwiftCode.xcodeproj/project.pbxproj` (all new Swift files as target
sources; both `.mjs` bridges as bundle resources).

## Verification actually performed

- Official docs read + installed packages inspected
  (`@opencode-ai/sdk@1.19.5`, `@openrouter/agent@0.11.0`, including
  `.d.ts` and README): SDK APIs above are verified, not recalled.
- `node --check` passes on both bridges. Bridge error paths
  exercised under Node: missing SDK (exit 1, actionable error, no
  `ready`), unreachable OpenCode server (exit 1, no `ready`),
  OpenRouter dummy-key run (401 surfaced as actionable invalid-key
  error, exit 1), unsupported tool source (explicit error, exit 1),
  empty model (actionable error, exit 1), ready handshake + SIGTERM
  clean exit, OpenRouter tool-schema conversion + host-tool safety
  checks (localhost/private/invalid/ftp rejected without network).
- Static review of all Swift: brace/paren balance, no TODOs, every
  referenced type grep-verified to exist, pbxproj registrations
  verified programmatically (fileRef + buildFile + group + phase for
  every new file; resources phase for both bridges).
- New offline, deterministic in-app tests in `SDKProviderTests`
  (routing, tool-source mapping, setting persistence round-trip,
  event-store merge, provider view routing), wired into
  `AssistRuntimeTestSuite` alongside the existing provider tests.

## Not verified — Mac checklist for Dylan

1. Xcode build of the full target (highest-risk points: the
   `@Observable` + `@MainActor` store, `AsyncStream` continuation
   handling in both providers, the `AsyncThrowingStream` consumption
   in the runner, `SDKToolEventStore` observation in
   `AssistChatBubble`, and the `@Sendable` closures crossing the
   provider actors).
2. In-app test run (both provider suites).
3. Settings: Install both SDKs (needs Node or Bun on the Mac), then
   Repair after deleting a `node_modules` entry to prove corrupt
   detection.
4. OpenCode live run: managed server start + `global.health()`,
   swiftcode JSON tool loop with a real model, opencode built-in tool
   run with a permission request (must deny and surface the error),
   combined-mode collision, cancellation mid-run, provider switch
   (no orphaned bridge/server).
5. OpenRouter live run with a real key: swiftcode bridged tool
   round-trip through a real multi-turn run, host-tool execution,
   stop conditions (25 steps / $2.00), cancellation mid-stream.
6. Transcript: OR/OC panels appear under the correct message only,
   update live during streaming, and survive scrolling back.
7. App termination with an active session bridge (manager `shutdown`
   wiring at app termination is still to be called from the app
   lifecycle; session cancellation already terminates session bridges).
