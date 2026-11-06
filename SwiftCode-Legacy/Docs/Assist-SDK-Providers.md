# Assist SDK Providers: OpenCode SDK + OpenRouter Agent SDK

Status: implemented on main, statically verified only. No Xcode build,
in-app test run, or live provider session has been executed in the
Linux environment used for this work (no Swift/Xcode toolchain there).
See "Not verified — Mac checklist" at the end.

Audit (2026-10-29): an independent audit of both providers (three
parallel workstreams: OpenCode, OpenRouter, Settings/UI) found both
providers PARTIALLY FUNCTIONAL — real SDKs, structurally sound
SwiftCode ownership, but with real defects. The fixes in "Audit
2026-10-29 — defects found and fixed" below were applied and are
covered by new tests where a test exists; the remaining gaps are
listed honestly in the Mac checklist. Do not describe either
provider as fully verified until the Mac checklist is done.

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
  include `stepCountIs`, `maxCost`, `maxTokensUsed`. Audit note: the
  current docs show the method form `client.callModel({...})`, but
  the pinned 0.11.0 `.d.ts` defines BOTH forms and the method
  delegates to the standalone function — the bridge's standalone
  form is verified against `esm/inner-loop/call-model.d.ts`, not an
  invented API. `maxCost` is a stop condition, not a spending
  ceiling: the SDK stops after the step reaching it and then makes
  one final turn (allowFinalResponse), so spend can exceed $2.00.
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
  copied into the runtime `bridge/` directory on first use. The
  runner now refreshes the installed copy when it differs from the
  bundled copy (previously an installed copy was returned forever,
  so bridge updates never propagated). Session bridges resolve
  `node` via `SDKRuntimeManager.detectRuntime()` (PATH + Homebrew
  etc.) instead of PATH-only `/usr/bin/env`, and drain stderr into
  a capped tail surfaced on ready failures instead of /dev/null.
  Ready lines whose `sdkVersion` differs from the pinned version
  are rejected, and the 30 s ready timeout now terminates the
  bridge (the old task-group race never fired for a silent bridge,
  because AsyncStream `next()` is not cancellation-aware).
- Managed OpenCode servers require the `opencode` CLI in addition
  to the SDK package: the SDK ships no binary and its server
  launcher spawns `opencode serve`. The bridge now fails fast with
  a distinct "OpenCode CLI is not installed" error instead of a
  generic unhealthy-server error; Settings copy says the same.
- Known split of responsibilities: `SDKRuntimeManager.launchBridge`
  (manager-owned bridges, used by Settings Stop) and the providers'
  `FoundationProcessBridgeLauncher` (session bridges) are two launch
  paths by design in this version — the providers' path is the one
  exercised by the bridge tests. Unifying them is a follow-up, not a
  silent assumption: Settings Stop does not terminate an active
  session bridge; session cancellation does.

## Providers and settings

Assist Settings (since 2026-10-29) has no shared **SDK Providers**
card: each provider's card carries its own runtime row — per-provider
runtime status (runtime found, SDK installed + version, or missing
with an actionable error), Install / Repair / Refresh-status /
Stop-bridge buttons. The standalone **Tool Source** picker is gone
too: the tool source is now derived from the Assist Toolkit picker
(System → SwiftCode tools; Provider → the toolset of the provider
picked in Assist System). The persisted `assist.toolSource` key is
still read as a fallback for previously saved choices.
Provider identity (`assist.selectedProvider`), model selection
(`selectedAssistModelID`), and credentials keep their existing keys;
changing the toolkit never changes provider, model, system prompt,
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
hardcoded into a bridge file. The runner now invalidates the
baseline-prompt cache on every SDK run (it was previously never
invalidated, so in-session asset updates never reached a later
run) and, like the legacy agent path, retrieves per-task
instructions (`SystemIndexService.retrieve`, 4000 tokens, recorded
in the request ledger) and appends them to the baseline. History
sent to a bridge excludes the current objective (the bridge appends
it as the final turn) and the "I'll inspect…" placeholder assistant
message, so a run's input no longer reads
`user(objective), assistant("I'll inspect…"), user(objective)`.

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
  The "OpenRouter tools" label previously overstated this: these
  are SwiftCode-authored host tools executed through the Agent SDK,
  not OpenRouter's own server tools — Settings copy now says so.
  Host-tool safety fixes in the audit: DNS checks use
  `node:dns/promises` (the callback API threw for every hostname,
  so `fetch_url` failed for all DNS names), every resolved address
  is checked (not just the first), IPv4-mapped IPv6 is recognised
  in both dotted and URL-normalised hex form, and bracketed IPv6
  hostnames are stripped before classification. A residual
  DNS-rebinding TOCTOU (check-time vs fetch-time resolution)
  remains and is documented in the bridge.
- **OpenCode tools**: the server's built-in tools, executed by the
  server. Permission requests are default-deny: the bridge replies
  `reject` via the verified permission API and emits a failed
  tool event with an explicit permission-denied error. Nothing is
  auto-approved. v1 and v2 permission events use different
  endpoints: v2 (`{id, action, resources}`) replies via
  `client.v2.session.permission.reply({sessionID, requestID: id})`
  — the old v1-only reply never resolved a v2 request. Tool parts
  carry `state` as an object `{status, input, output?, error?,
  time}`; the bridge now maps `state.status` and reads arguments/
  results/timestamps from it (the old string switch mapped every
  tool to Pending forever). SwiftCode-tool turns buffer their text
  and unwrap `{"finalResponse": …}` instead of leaking the JSON
  envelope into the transcript. `promptAsync` now uses
  `throwOnError: true` and checks `result.error`, and a stream
  ending without `session.idle` is an error, not a partial success.
  `tool.ids` failures now fail closed in swiftcode/combined modes
  instead of proceeding ungated.
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
  empty snapshot renders nothing. Rows now carry a per-row source
  badge (SwiftCode / OpenRouter / OpenCode) so combined-mode rows
  are distinguishable, and cancelled rows render under a
  "Cancelled" heading instead of "Error". Cancellation marks all
  non-terminal rows cancelled in the store (previously OpenCode
  rows stayed Running forever and OpenRouter rows reported Failed).
  Tool events are session-only: they are not persisted with saved
  conversations, and Clear Chat now resets the store (previously
  stale rows could render under the next unrelated SDK message).
  Panels are still keyed to the latest SDK run only — earlier runs'
  panels are not retained per message (see Mac checklist).
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
`Views/Settings/AssistSettingsView.swift` (per-provider SDK runtime rows),
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

## Audit 2026-10-29 — defects found and fixed

Verdict before fixes: both providers PARTIALLY FUNCTIONAL. The
integrations genuinely use the real SDKs (not chat-completion
wrappers), and SwiftCode ownership of model, prompt, assets, and
default tools is structurally sound. The defects below were real,
not cosmetic, and are fixed in this commit unless listed under
"still open" in the Mac checklist.

OpenCode (bridge + provider):
- Tool-state mapping: `part.state` is an object, not a string — every
  server tool stayed Pending with no arguments/results. Fixed to
  map `state.status` and read input/output/error/time from it.
- `promptAsync` errors swallowed (SDK default `throwOnError:
  false`, return value discarded) → a rejected prompt hung waiting
  for idle. Fixed with `throwOnError: true` + `result.error` check.
- Event stream ending without idle reported partial text as
  success. Fixed: stream-end-without-idle is now an error.
- Managed server needs the `opencode` CLI, which the SDK install
  does not provide. Since 2026-10-29 this is auto-healed instead:
  `OpenCodeClient.ensureServer()` locates or installs the binary
  automatically (see Assist-OpenCode-OpenRouter-Providers.md).
- v2 permission events answered on the v1 endpoint (and labelled
  "unknown"). Fixed: v2 branch via
  `client.v2.session.permission.reply`, tool name from `action`.
- Catalog model validation never ran: v2 models are an object map,
  not an array. Fixed to check map entries.
- `tool.ids` failure failed open. Fixed: fail closed in
  swiftcode/combined modes.
- `{"finalResponse": …}` was posted verbatim as JSON (and tool-
  request JSON streamed into the transcript). Fixed: SwiftCode-tool
  turns buffer text and unwrap the envelope at turn end.
- Tool-event text was unredacted for OpenCode. Fixed: bridge-side
  redaction (Bearer tokens, sensitive key/value pairs) for
  tool_event display text only — tool_call arguments untouched.
- OpenCode runs sent no `requestId`, so the bridge defaulted to
  "run" and SwiftCode tool call ids repeated across runs, merging
  over earlier rows in the store. Fixed: Swift sends a UUID.
- Cancellation during generation never aborted an external server
  session. Fixed: SIGTERM handler aborts the active session
  (best-effort, 400 ms race) before exit. Note: the event-drain
  itself does not yet race the cancel queue (see checklist).

OpenRouter (bridge + provider):
- `callModel` form: verified NOT a defect. Standalone
  `callModel(client, …)` is in the pinned 0.11.0 `.d.ts`; the
  docs' method form delegates to it.
- Session launcher resolved `node` via inherited PATH only, while
  Settings detection also checks Homebrew etc. Fixed: shared
  launcher now uses `detectRuntime()` for node (shared by both
  providers).
- Ready timeout never fired for a silent bridge (AsyncStream
  `next()` is not cancellation-aware). Fixed: timeout terminates
  the bridge, whose termination handler unblocks the consumer.
  Applied to both providers, plus ready `sdkVersion` checks.
- Current objective duplicated in model input (history + userText,
  with the placeholder assistant message between). Fixed in the
  runner (history excludes the objective and the placeholder).
- SDK runs got the baseline prompt only, and the baseline cache was
  never invalidated. Fixed: per-task retrieval (4000 tokens,
  ledger-recorded) + cache invalidation per SDK run.
- `fetch_url` SSRF gaps: callback-API DNS (threw for every
  hostname), single-address check, unrecognised mapped IPv6,
  bracketed IPv6 hostnames bypassing classification. All fixed;
  residual DNS-rebinding TOCTOU documented in the bridge.
- `maxCost` copy overstated as a ceiling; host-tool label
  overstated as OpenRouter's own tools. Both reworded.
- Combined-mode rename could still collide with a native tool
  literally named `openrouter_<name>`. Fixed: fail loudly.
- Tool-event correlation keyed on name+args collapsed identical
  calls and could orphan stream/execute rows. Fixed: SDK call id
  is the primary correlation key, name+args only a fallback.
- Cancelled tools reported as Failed. Fixed: bridge emits
  `cancelled` for cancel rejections; views render Cancelled
  distinctly from Error.
- Zod-internals check (`_zod.def.type`) replaced with input-schema
  shape checks.
- Fatal handler printed a raw stack to stderr. Fixed: message only.

Settings / UI (shared):
- Tool events accumulated across runs/conversations and stale
  rows leaked after Clear Chat. Partially fixed: per-run UUID
  request ids (OpenCode), Clear Chat resets the store, runner
  cancel marks non-terminal rows cancelled, store merge key now
  includes source. Per-message panel retention is still open.
- Settings status proved install only, not bridge-ready, and its
  timeout text pointed at a log UI that does not exist. Fixed:
  text corrected; a real "Validate runtime" button is still open.
- No Settings-time warning for incompatible tool source + model.
  Fixed: inline warning in the SDK section (run still fails
  explicitly if missed).
- Legacy OpenCode section copy contradicted the SDK path. Fixed.
- Install notice claimed a fresh install on a no-op. Fixed:
  "Already installed and verified" when it was already installed.
- Tool-source picker state was initialised once and never
  reloaded; picker had no accessibility label. Fixed.
- SDK tool panels are session-only (not persisted). Documented in
  Settings and here, not silently implied otherwise.

Tests added:
- `SDKHosts/sdk-bridge-tests.mjs` (committed; run from a directory
  with the pinned packages installed — see its header): OpenCode
  tool-state/timestamp/redaction/model-id/finalResponse cases,
  OpenRouter schema/host-tool/IP-gate cases. Run 2026-10-29 in
  /tmp with `@opencode-ai/sdk@1.19.5` + `@openrouter/agent@0.11.0`:
  all assertions passed. Process contracts run the same day:
  OpenRouter bridge prints `ready` with sdkVersion 0.11.0;
  OpenCode bridge against an unreachable server exits 1 with no
  ready; managed mode without the CLI exits 1 with the distinct
  CLI-missing error.
- `SDKProviderTests`: positive OpenRouter persisted-provider
  routing, merge edge cases (terminal→different terminal,
  same-state nil-result refresh, source-isolated merge), and
  cancelNonTerminal behaviour.
- Swift tests were NOT run here (no Xcode toolchain in this
  environment) — they are item 2 of the Mac checklist, as before.

## Not verified — Mac checklist for Dylan (updated)

Items 1–7 from the previous checklist still stand, plus:
8. Per-message tool panels: earlier SDK runs' OR/OC panels are
   still not retained (single-slot sdkMessageId). Decide whether
   to attach event snapshots to messages or accept latest-only.
9. OpenCode event-drain vs cancel queue: cancellation during
   generation now aborts via SIGTERM, but the drain loop does not
   itself race cancel lines — verify cancel-mid-generation against
   a real external server.
10. Combined-mode live behaviour: deny-all `swiftcode` agent +
    tools-map interaction, and whether non-colliding built-ins
    actually run under it.
11. Settings "Validate runtime" (bridge ready + key check) and a
    rendered bridge/install log, if those are wanted — the current
    status is install status, and the timeout text no longer
    pretends otherwise.
12. OpenCode turn timeout: a prompt that neither idles nor errors
    still has no turn-level timeout (prompt rejection and
    stream-end are now errors, but a hung server turn is not).
13. App termination with an active session bridge (manager
    `shutdown` wiring at app termination is still to be called
    from the app lifecycle; session cancellation already
    terminates session bridges).
