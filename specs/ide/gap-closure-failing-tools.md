# Gap closure: failing tools (family 2)

Date: 2026-11-06. Slice: gap-closure family 2 (FAILING TOOLS).
Destination: SwiftCode-Mac main @ f9f66c05 (SwiftCode base, SwiftPM).
Legacy (read-only): SwiftCode-Legacy @ d51a8f0d. Legacy source is Dylan's
own code; direct porting was authorised by Dylan under MIT.

This spec covers the tools that Waves 4/5/8 registered but left honestly
failing or partial, plus the verify-and-fix items (image limits, YAML,
plist distinction). The MCP catalogue stays at 433 tools: no tool is
added or removed; registrations change only where noted (two optional
`take_screenshot` parameters).

## 0. Evidence collected live in this slice

- OSV API (`https://api.osv.dev/v1/querybatch`, POST, no key): reachable
  from this VM. `lodash@4.17.20` (npm) returned 4 real advisories
  (`GHSA-29mw-wpgm-hmr9`, `GHSA-35jh-r3h4-6jhm`, `GHSA-r5fr-rjxr-66jc`,
  `GHSA-xxjr-mmjv-4gpg`); `apple/swift-nio@2.0.0`, `vapor/vapor@4.0.0`,
  `krzyzanowskim/CryptoSwift@1.0.0`, `Alamofire@5.0.0` (SwiftURL)
  returned no advisories; `apple/swift-crypto@1.0.0` (SwiftURL) returned
  none. The SwiftURL ecosystem is accepted (HTTP 200, no error), and
  advisories flow for ecosystems that have them. Conclusion: a real,
  keyless vulnerability source exists for `dependency_audit`.
- `npm view rea-agents@6.5.0`: the package EXISTS (MIT, "Reverse
  engineer anything from your terminal or agent with one CLI and MCP
  server", latest 6.8.0, 6.5.0 published). Node v24.22.1 is present in
  this VM. Conclusion: the REVIEW scout's DROP recommendation for
  `ReverseBridge.mjs` rested on "rea-agents was never vendored" — the
  package is obtainable via npm, so the DROP is NOT confirmed. The
  bridge is ported (Dylan's own code) and the tool works when a
  rea-agents@6.5.0 directory + Node 22/24/26 are configured; it fails
  honestly otherwise. Nothing is auto-installed and nothing is vendored
  into the repo.
- Yams (`jpsim/Yams`, MIT, SPM `from: "6.2.2"`): full YAML 1.2 via
  vendored libYAML, works on macOS and Linux (static `CYaml`). This is
  the full-parser path for `parse_yaml` (see §11); it needs a
  Package.swift dependency the coordinator adds, so this slice extends
  the hand-rolled subset parser instead and records the Yams wiring.
- No `magick`/`convert`/`rsvg-convert` binary exists on this Linux VM
  (checked with `which`); `sqlite3` exists at `/usr/bin/sqlite3`.

## 1. `env_capture_logs` — now working

Legacy: `SwiftCode/Backend/Assist/Tools/AssistLogCaptureTool.swift`
(37 lines). `execute` reads the last 10 snapshot-history entries
(`AssistSnapshotFunctions.listSnapshots()` → `timestamp: message [id]`)
and appends a `memoryKey` memory preview (first 500 chars). Empty →
"No logs found in snapshot history."

Wave 4 left it failing ("no snapshot-history store, no Assist memory
store"). Both prerequisites exist now: `project_snapshot` (Wave 7)
stores snapshots in Application Support `SwiftCodeSnapshots/` in Legacy's
`AssistSnapshots/` layout (`projectModelSnapshotsDirectory()`), and the
memory store is `SwiftCodeMemoryGraphStore.shared` (`MemorySupport`).

Port (superset, all real, nothing invented):

- Snapshot history: read `SwiftCodeSnapshots/*/metadata.json` (id,
  timestamp, message), newest first, max 10, formatted exactly like
  Legacy (`<timestamp>: <message> [<id>]`). Missing/empty directory →
  Legacy's exact fallback line.
- Memory: `memoryKey` is read from `SwiftCodeMemoryGraphStore` for the
  open workspace (same workspace key the memory tools use); appended
  as `Memory: <first 500 chars>` when non-empty.
- Environment (new, per the gap-closure brief): the real process
  environment from `ProcessInfo.processInfo.environment`, as
  `NAME=value` lines, plus OS / Swift version / workspace root.
  Values are REDACTED (`<redacted>`) when the name matches the
  sensitive pattern (`KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `AUTH`,
  `CREDENTIAL`, `PRIVATE`, `BEARER`, `SESSION`, `COOKIE`) — the Wave 8
  `read_environment_variables` precedent (names only there) extended:
  non-sensitive values are useful diagnostics and are the user's own
  process environment; secret-looking values never appear in output.
  The environment section is capped at 8,000 characters.
- Recent host output (new): the latest host run's output tail (50
  lines, `runs` keyed by run id) and the simulator log tail (50
  lines), when any exist. These are the host's own real buffers, not
  a per-process log store.

Structured result: `logs` (the joined Legacy-shaped log lines),
`snapshotCount`, `memoryIncluded` (bool), `environmentVariableCount`,
`environment` (the redacted env block), `recentOutput` (the run /
simulator tail). The tool stays read-only.

## 2. `get_process_logs` — now working

Legacy: `SwiftCode/Tools/Agentic/GetProcessLogs.swift` (26 lines).
`run(pid:)` returns the placeholder string `"Log data for process
<pid>"` — no log source exists behind it. Wave 8 correctly refused to
reproduce the placeholder.

Port: real sources, in order, first hit wins:

1. The host's own runs: a `HostRun` whose `process.processIdentifier`
   equals the pid returns its real captured output (tail 100 lines)
   plus its state (running / exited with status N). `run` / simulator
   runs started by this host are covered.
2. macOS unified log: `/usr/bin/log show --style compact --last 15m
   --predicate 'processID == <pid>'` (fixed argv, 45 s timeout, the
   `terminalSystemLog` shape from `use_system`). A denied read fails
   honestly (TCC), never with invented lines.
3. Linux: `journalctl --no-pager -o short --since "15 minutes ago"
   _PID=<pid>` when the binary exists (30 s timeout); plus the live
   process facts from `/proc/<pid>/cmdline` and `/proc/<pid>/status`
   (command line, state, PPid, VmRSS) labelled as process info, not
   logs. A pid with no process and no journal entries fails with
   "no such process / no log entries", never a placeholder.

Validation: pid is required and must be > 0; pid 1 and the host's own
pid are readable (they are just log queries) — no kill path exists
here, so no refusal is needed. Output is capped at 8,000 characters
with a truncation marker. Pure helpers (unified-log argv builder,
journalctl argv builder, `/proc` parsing) are unit-tested; the
`log`/`journalctl` paths are Mac/Linux verification pending.

## 3. `take_screenrecord` — now working on macOS

Legacy: `SwiftCode/Backend/Assist/Tools/AssistTakeScreenrecordTool.swift`
(164 lines) + `AssistScreenRecordingEngine` (actor, SCStream +
AVAssetWriter). Validation: `app_identifier` required; duration
1–60 s (default 10); `capture_mode` window/application_display;
`include_audio` (default false); output `mov`/`mp4` (default mov).
The engine resolves the app (bundle id → name → substring), takes
the first on-screen window over 20×20, records with `SCStream`
(2× window size, even dimensions, 30 fps, cursor shown) into an
`AVAssetWriter` (H.264, `.mov`/`.mp4`), one recording at a time.

Port: `SwiftCodeTools+ScreenRecording.swift` (macOS-only,
`#if canImport(ScreenCaptureKit)` + `#if canImport(AVFoundation)`).
The session class follows Legacy's `StreamRecorderSession` shape
(video input only; `.screen` samples only). Deviations, recorded:

- `capture_mode: "application_display"` is implemented as a display
  filter (the display containing the target window). Legacy accepts
  the value but always uses the window filter; the display filter is
  the behaviour the mode name promises.
- `include_audio: true` sets `capturesAudio` on the stream
  configuration exactly like Legacy, but no audio input is wired to
  the writer (Legacy wires none either) — recordings are video-only.
  The result never claims audio.
- The artifact flow is SwiftCode's (`approveFileWritingChange` +
  `.assist_temp/artifacts/screenrecord_<app>_<ts>.<fmt>`), not
  Legacy's `AssistArtifactStore`. Structured result keeps Legacy's
  keys: `path`, `duration`, `width`, `height`, `app_identifier`,
  `app_name`, `artifact_id`, `format`, `size_bytes`.
- On Linux the handler keeps the exact honest failure (no
  ScreenCaptureKit/AVFoundation), naming the missing capability.

Screen Recording permission is preflighted with
`CGPreflightScreenCaptureAccess` (prompt once), exactly like Legacy.

## 4. `take_screenshot` — window and region capture

Legacy: `SwiftCode/Backend/Assist/Tools/AssistTakeScreenshotTool.swift`
(146 lines) + `AssistScreenCaptureEngine.captureFullScreen` /
`captureUserSelectedRegion`. Fullscreen goes through
`SCScreenshotManager` (2×, best resolution, cursor flag). Region
shows an interactive overlay (`RegionSelectionOverlayWindow`), then
captures the containing display fullscreen and crops to the selected
rect (scale = image width / display width).

Wave 4 ported fullscreen only; `capture_mode: "region"` failed.

Port: two new optional parameters (existing callers unaffected):

- `region`: object `{x, y, width, height}` — screen points, origin at
  the TOP-LEFT of the main display (CoreGraphics coordinates), as the
  rect to crop from the containing display's fullscreen capture.
  Legacy's crop math (scale from the captured image, integral rect)
  is reused. A rect with non-positive width/height fails; a rect
  outside every display fails naming the displays.
- `window_id`: string — a `window_<CGWindowID>` id as listed by
  `use_app` `list_windows` (or a bare number). Captured with
  `SCContentFilter(desktopIndependentWindow:)` on the matching
  `SCWindow`.

`capture_mode` values: `fullscreen` (unchanged), `region` (needs
`region`; without it the call still fails honestly — see below),
`window` (needs `window_id`). Any other value behaves as fullscreen,
as Legacy does. The `display_id`, `include_cursor`, `image_format`
(ignored, PNG always), `purpose`, artifact + `image.png` mirror flow
are unchanged. `capture_mode` in the result reports the mode actually
used (`fullscreen`, `region`, `window`).

NOT ported: the interactive region-selection overlay. It needs a live
AppKit runloop and a user drag while the tool call blocks; the MCP
host also runs headless (`swiftcode mcp`), where no runloop exists. A
modal overlay would block the tool call indefinitely with no timeout.
The rect-based `region` is the working replacement; bare `region`
fails naming the overlay and pointing at `region`.

## 5. `use_mcp` — now working (real external MCP client)

Legacy: `SwiftCode/Backend/Assist/Tools/UseMCP.swift` (244 lines).
`MCPServerManager` holds configured servers (stdio / URL transports)
with a tools list per server; `list` enumerates servers,
`list_tools` lists one server's tools, otherwise the tool is called
via JSON-RPC with approval (unless Autopilot — NOT ported).

SwiftCode had no MCP client at all (it IS an MCP server). Port:
`SwiftCodeTools+MCPClient.swift`, a minimal JSON-RPC 2.0 client:

- Configuration: `~/.config/swiftcode/mcp-servers.json` (or
  `$XDG_CONFIG_HOME/swiftcode/mcp-servers.json`), Claude-Desktop shape:
  `{"mcpServers": {"name": {"command": "...", "args": [...],
  "env": {...}} | {"url": "https://…", "headers": {...}}}}`.
  `transport` is inferred (command → stdio, url → streamable HTTP).
  A missing/empty config file means "no servers configured" (Legacy's
  exact message). No Settings UI writes the file yet; the path is in
  the failure message when empty.
- Transports: stdio (spawn command as a fixed argv vector, NDJSON
  JSON-RPC on stdin/stdout, stderr drained to a bounded tail) and
  streamable HTTP (POST with `Accept: application/json,
  text/event-stream`; handles a bare JSON response and an SSE
  `data:` stream). The legacy SSE transport is NOT implemented; a
  server configured with `"transport": "sse"` fails naming that.
- Protocol: `initialize` (protocol version `2025-03-26`, client
  `SwiftCode` / `swiftcode-mcp`), `notifications/initialized`, `tools/list`,
  `tools/call`. The server's returned protocol version is accepted,
  never enforced. Timeouts: 30 s for initialize/list, 300 s for a
  call. Responses are matched by request id; malformed frames fail.
- Semantics mirror Legacy: `serverName: "list"` (or
  `toolName: "list_servers"`) returns the configured-server list
  without approval and without connecting; `list_tools` connects and
  lists; a call parses `arguments` as a JSON object (invalid JSON
  fails), goes through `terminalApproveChange` (no Autopilot), and
  returns the joined text content (an `isError` result is a failure).
  Output is capped at 8,000 characters with a marker; the structured
  result carries `server`, `tool`, `durationMs`, `isError`.
- Test seams (same pattern as `agenticDataTestSecretStore`):
  `SwiftCodeMCPHost.externalMCPTestConfig` (in-memory server table) and
  the stdio runner is exercised in tests against a stub script via
  real Node — no live network, no real external server.

## 6. `use_composio` — now working (real client, key from SecretStore)

Legacy: `SwiftCode/Backend/Assist/Tools/AssistComposioTool.swift` +
`SwiftCode/Services/ComposioService.swift`. Execution prefers the
Composio CLI (`composio execute <slug> -d <argsJSON>`), falling back
to REST `POST https://backend.composio.dev/api/v3.1/tools/execute/<slug>`
with `x-api-key` (or `x-user-api-key` for `uak_…` keys) and body
`{"arguments": {...}}`. Key resolution order: Keychain
(`composio_api_key`) → `COMPOSIO_API_KEY` env → 
`~/.composio/user_data.json` (`api_key`, `test_user_id`). CLI
candidates: `~/.local/bin/composio`, `/usr/local/bin/composio`,
`/opt/homebrew/bin/composio`.

Port: `SwiftCodeTools+ComposioClient.swift`. Key from
`defaultSecretStore()` under the new account `composio.api-key`
(needs the one-line `SecretAccount.composioKey` addition — delivered
as a patch, not edited here; the client defines the string locally
so it works before the patch lands), then the env var, then
`~/.composio/user_data.json` — Legacy's exact order. No key is ever
written by the tool, and no key value ever appears in output. Slug
validation: non-empty, `[A-Z0-9_]+`, max 128 chars. Arguments must
parse as a JSON object. Approval via `terminalApproveChange` (no
Autopilot). CLI output is parsed for a JSON object (`successful` /
`logId`/`log_id`) exactly like Legacy; a non-zero CLI exit with no
JSON is a failure carrying the stderr tail. REST uses
`SwiftCodeAssistant.HTTP.send` (30 s). With no CLI and no key the tool
fails honestly naming both missing prerequisites and where to put
the key (SecretStore / env / `~/.composio/user_data.json`) — it never
embeds or invents a key.

## 7. `use_workers` — validation + persistence real; execution still blocked

Legacy: `SwiftCode/Backend/Assist/Subagents/Tools/UseWorkersTool.swift`
(204 lines). Resilient input decoding (array / stringified JSON /
single object / `tasks` / `subtasks` synonyms), validation (each
worker needs a non-empty task, truncated to 500 chars; duplicate
names suffixed `-2`, `-3…`; duplicate scopes suffixed with the worker
name; dependencies must name workers in the same batch), then
`WorkerScheduler` executes real subagents, `WorkerPersistenceStore`
persists the tree, and claimed file changes are reconciled against
the filesystem.

Port: the validation is ported exactly (the existing Wave 4 handler
already had name/task/dependency checks; this slice adds the 500-char
truncation, scope dedup, and `targetFiles` collection). Reachability
note: SwiftCode's schema validation runs before the handler, so only the
array form of `workers` can arrive — Legacy's stringified-JSON /
single-object / synonym forms are unreachable through the tool call
and are NOT reproduced (recorded, not silently dropped).

What is real now: validation (exact Legacy rules), topological
ordering by `dependencies` (a cycle fails naming the workers in it),
approval via `terminalApproveChange`, and persistence of the batch
plan as JSON under the workspace `.assist_temp/workers/<batch-id>.json`
(assignments, order, status, timestamps) — a real artifact a later
slice can resume from. Target files are reconciled for real
(existence check per file, reported per worker).

What is still blocked: execution. Workers execute real work through
an LLM subagent loop (`WorkerScheduler` + subagent execution); SwiftCode's
MCP host has no LLM/subagent runtime (the LLM-wiring family owns
that). The handler fails honestly after persisting the plan, naming
the missing subagent runtime. A `FailingToolsWorkerExecutor` protocol
is defined as the seam: a future LLM slice provides an executor and
the runner (topological order, per-worker results, reconciliation)
is already written and unit-tested with a stub executor. No worker
is ever claimed to have run.

## 8. `dependency_audit` — now a real OSV audit

Legacy: `SwiftCode/Tools/Agentic/DependencyAudit.swift` (25 lines).
`run` returns `"No vulnerabilities found in dependencies at
<projectPath>"` without checking anything — an invented clean bill
of health. Wave 8 correctly failed honestly instead.

Port: `SwiftCodeTools+DependencyAudit.swift`, a real audit against the
Open Source Vulnerability database (OSV, `https://api.osv.dev`,
keyless — evidence in §0):

- Input: `projectPath` (workspace-confined directory). Reads
  `Package.resolved` (v1/v2/v3 pin shapes: `package`/`repositoryURL`
  / `state.version` / `state.revision`, and `identity` / `location`
  / `state.version`). Packages without a pinned version (branch /
  revision-only pins, local path deps) are listed as skipped with the
  reason — OSV matching needs a version.
- Query: `POST /v1/querybatch` (max 100 queries per request, 30 s
  timeout), one query per pinned package:
  `{"package": {"name": "<repository URL>", "ecosystem": "SwiftURL"},
  "version": "<pinned version>"}`.
- Detail: for each returned advisory id, `GET /v1/vulns/<id>` (capped
  at 50 detail fetches; beyond that ids are listed without detail).
  Reported per vulnerability: id, summary, severity (CVSS score when
  present), affected versions, fixed version (last `fixed` event in
  the affected ranges), and the first reference URL.
- Result: structured `{packageCount, auditedCount, skippedCount,
  vulnerableCount, vulnerabilities: [...], skipped: [...]}`. Zero
  vulnerabilities is reported as "No advisories reported by OSV for
  N pinned dependencies (checked <date>)" — a real negative from a
  real source, with the OSV coverage caveat stated (matching depends
  on the advisory's affected package URL; advisories keyed under
  other ecosystems do not match). It is never phrased as a guarantee.
- `package_dependency_audit` (Wave 7) is untouched: it audits pins,
  this audits vulnerabilities.
- Test seam: `SwiftCodeMCPHost.dependencyAuditTestFetcher` stubs the OSV
  HTTP layer so tests never touch the network.

## 9. `reverse_analyze` — bridge ported; works when REA is configured

Legacy: `SwiftCode/Backend/Assist/API/Internal API/Reverse/`
(`ReverseToolAdapter.swift` 177, `ReverseBridge.swift` 592,
`ReverseBridge.mjs` 403, `ReverseModels.swift` 658,
`ReverseEvidenceProcessor.swift` 260, `ReverseManager.swift` 253,
`ReverseCommandParser.swift` 246, `ReverseTests.swift` 205).
The tool validates (operation allow-list, REA-disclaimer task screen,
target/scope validation, objdump sub-operation, timeout clamp
10–1800 s default 300), then `ReverseManager` spawns
`node ReverseBridge.mjs --rea-dir <rea-agents@6.5.0 dir>`, writes one
NDJSON request to stdin, reads NDJSON frames (progress / result /
error) to EOF, and formats the Evidence envelope as Markdown.

Port:

- `Resources/ReverseBridge.mjs`: Legacy's bridge, ported verbatim
  except the product name in comments/remediation strings
  (SwiftCode → SwiftCode) and the env fallback
  (`SWIFTCODE_REVERSE_REA_DIR` first, `SWIFTCODE_REVERSE_REA_DIR` as an
  alias). Protocol version 1, pinned `rea-agents@6.5.0`, direct path
  (`dist/composition/directAnalysis.js` → `runDirectAnalysis`) plus
  the pinned-CLI fallback for `inspect_with_objdump` only
  (`scripts/rea.mjs … --format json`). No MCP transport anywhere in
  the bridge. Needs the Package.swift resource wiring (see §14).
- `SwiftCodeTools+ReverseBridge.swift`: the Swift runner, following
  Legacy's `ReverseBridge` (`resolveBridgeURL` → Bundle.module
  resource, `SWIFTCODE_REVERSE_BRIDGE_PATH` / `SWIFTCODE_REVERSE_BRIDGE_PATH`
  env; `resolveREADirectory` → `SWIFTCODE_REVERSE_REA_DIR` /
  `SWIFTCODE_REVERSE_REA_DIR` env, `<bridge>/node_modules/rea-agents`,
  `~/Library/Application Support/SwiftCode/Reverse/node_modules/rea-agents`;
  `resolveNodeURL` → `SWIFTCODE_NODE_PATH` / `SWIFTCODE_NODE_PATH`, the
  three fixed paths, then PATH; node major must be 22/24/26).
  Spawn is argv-only, stdin request + bounded stdout (8 MiB) /
  stderr (64 KiB), timeout kills the child. Frames are validated
  (version 1, matching id, type in progress/result/error) and the
  Evidence envelope must carry `evidence_id` + `operation`.
- Handler (`SwiftCodeTools+Engines.swift`): the existing validation chain
  (steps 1–6) is unchanged; on success the Evidence is rendered as
  Markdown (generic JSON renderer: id, operation, provider,
  confidence, findings/sections when present, else pretty JSON capped
  at 8,000 chars) with structured `{evidence_id, operation,
  provider, confidence, subject_digest}`. A bridge error returns the
  bridge's message + remediation. Without node, without a
  rea-agents@6.5.0 directory, or without the bundled bridge resource,
  the tool fails honestly naming exactly which piece is missing and
  how to supply it (`npm install rea-agents@6.5.0` into a directory +
  `SWIFTCODE_REVERSE_REA_DIR`). Nothing is downloaded or installed by
  the tool.
- The REVIEW scout's DROP for `ReverseBridge.mjs` is reversed with
  evidence (§0): the package is obtainable. The full REA subsystem
  (manager lifecycle, cancellation, EvidenceProcessor's field-specific
  formatter, `ReverseTests`) is NOT ported — the runner + generic
  renderer cover the tool surface; cancellation is the timeout only.

## 10. `use_app` — Accessibility engine ported

Legacy: `SwiftCode/Backend/Assist/Tools/AssistUseAppTool.swift`
(707 lines, dispatch) + `AssistAppInteractionEngine` (~1,460 lines:
AX tree walk, element resolution, semantic actions, menus, CGEvent
input, waits, app screenshot). Wave 4 ported only
`list_applications` (running-only), `launch`, `activate`,
`close_application`, `list_windows` (CGWindowList, on-screen only).

Port: `SwiftCodeTools+AppInteraction.swift` (macOS-only,
`#if canImport(AppKit)` + `#if canImport(ApplicationServices)`),
following the engine's shapes:

- Sessions: per-pid registry (elements `elem_1…`, descriptors,
  selected window, windows list, last screenshot). The session id
  reported to the model is `app-<pid>` (stable across calls; Legacy
  mints a UUID — recorded deviation, strictly more useful).
- `inspect_ui` / `get_accessibility_tree`: AX tree walk of the
  selected (or first) window, max 100 elements, depth 10, Legacy's
  actionable-roles filter; descriptors carry role, subrole, title,
  label, identifier, value, frame, enabled/focused/selected, actions.
- `get_focused_element`: first focused descriptor from a fresh
  inspection (Legacy's shape).
- `inspect_application` (NEW vs Legacy's dispatch, which dropped it
  to the default error): bundle id, pid, name, active/hidden state,
  window count. `inspect_window` (NEW, same reason): title, frame,
  isMain, isMinimized, role for `window_id`/`target`.
- `select_window`: AX raise + set-main, records the selection in the
  session (Legacy's shape; window ids are `window_<index>` in AX
  order — note this differs from the CGWindowList ids the old
  `list_windows` returned; see below).
- `take_screenshot`: fullscreen capture cropped to the target (main
  or `window_id`) window's frame — Legacy's `captureAppScreenshot`
  shape, saved through the artifact flow.
- Input actions via CGEvent, Legacy's exact shapes: `click` /
  `double_click` (clickCount 1/2) / `right_click` (button right),
  `move_pointer` (clickCount 0 move), `drag`, `scroll` (pixel wheel,
  dx/dy), `type_text` (Unicode injection per UTF-16 unit; >100 chars
  via clipboard + Cmd+V with restore), `press_key` (Legacy's
  keycode table), `press_shortcut` (`Cmd+S` splitting),
  `select_all`/`copy`/`paste` (Cmd+A/C/V), `activate_element`
  (semantic press), `set_element_value` (NEW vs Legacy's dispatch,
  which dropped it: AX `kAXValueAttribute` set via the engine's
  semantic action), `set_value` (alias of `type_text`, Legacy's
  dispatch), `select_menu` / `select_menu_item` (menu-bar walk,
  `File > Save` splitting, disabled items refuse).
- `wait_for_element` / `wait_for_window`: 200 ms polling up to the
  timeout (1–60 s, default 5), Legacy's matching rules.
- `verify` / `verify_element_state`: resolve the target; with an
  expected `value`, compare case-insensitively (contains or equal);
  without one, existence is the verification.
- Authorization: `AXIsProcessTrustedWithOptions` (prompt once). When
  untrusted, every AX action fails naming Accessibility in System
  Settings — never a fake tree. Screen capture preflights as in §4.
- Approval: input-delivery actions (click, drag, scroll, typing,
  keys, shortcuts, select_all/copy/paste, activate/set, menus) go
  through `terminalApproveChange` (no Autopilot); reads, waits,
  verify, `select_window`, and `take_screenshot` do not (the
  screenshot's artifact save gates itself). `close_application`
  keeps Legacy's `confirm: true` + the approval gate.
- `list_applications` now also lists INSTALLED apps (Legacy scans
  `/Applications`, `/System/Applications`,
  `/System/Applications/Utilities`, `~/Applications` for `.app`
  bundles) — the Wave 4 "running-only" limit is closed. Running
  apps sort first, as in Legacy.
- Window-id note: the old `list_windows` used CGWindowList numbers
  (`window_<CGWindowID>`); the AX engine numbers windows by AX
  order (`window_1…`). Both spellings are accepted wherever a window
  id is taken (AX order first, then CGWindowID), and `list_windows`
  now reports the AX id, the CGWindowID, title and frame together so
  either can be used downstream.

## 11. `parse_yaml` — subset extended; full parser is Yams

Legacy's `ParseYAMLTool` was a stub ("Parsed … (simulated)"). Wave 8
implemented a real subset parser (block mappings/sequences, plain /
quoted scalars, null/bool/int/double, flow collections; anchors,
aliases, tags, block scalars rejected with the line number).

This slice extends the subset, in `SwiftCodeTools+AgenticData.swift`:

- Block scalars: literal `|` and folded `>` with chomping indicators
  (`-` strip, `+` keep, default clip) and explicit indent indicators
  (`|2`). Folding follows the YAML rule (single newlines fold to
  spaces; blank lines and more-indented lines are kept). Consumed
  from the raw lines at the block's indent.
- Anchors & aliases: `&name` on a scalar or a block value stores the
  parsed value; `*name` resolves it (unknown alias fails with the
  line); merge key `<<: *name` (or a sequence of aliases) merges
  mapping entries without overriding explicit keys.
- Still rejected, with the line and construct: tags (`!foo`, `%TAG`),
  multi-document streams beyond the `---`/`...` separators (skipped
  as before), complex (`? key`) keys, tab indentation, duplicate keys.

A complete YAML 1.2 parser is NOT reimplemented here — that is
libYAML's job. The full path is Yams (MIT, SPM
`.package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")`,
vendored libYAML, Linux-supported — §0). Wiring is a Package.swift
change for the coordinator: add the Yams package, add `Yams` to the
`SwiftCodeMCP` target dependencies, and swap `AgenticDataYAMLParser` for
`Yams.load(yaml:)` behind the same handler (keeping the
duplicate-key rejection and the `AnyJSON` mapping). Until then the
subset parser stays, with its limits stated in the tool description.

## 12. Images — macOS complete; Linux fallback via ImageMagick

Verified live: `image_convert_format`, `image_generate_thumbnail`
and `svg_to_png` on macOS are faithful ports (NSImage decode +
`NSBitmapImageRep`, ImageIO thumbnail, NSImage SVG rasterize with the
512×512 zero-size fallback and width+height-overrides-scale rule).
`image_get_dimensions` / `image_extract_metadata` already work
cross-platform via the header parser (+ ImageIO on macOS).
HEIC is accepted as an INPUT on macOS (NSImage reads it) but is not
an accepted target format — Legacy's exact set (png, jpeg, tiff,
bmp, gif).

Linux extension (new): when ImageMagick is installed (`magick` v7
or `convert` v6, resolved on PATH), the three tools run through it
as a fixed argv vector — `magick <src> [-quality N] <dst>` for
convert, `magick <src> -resize <N>x<N> <dst>` for thumbnails,
`magick -density 144 -background none <src.svg> <dst.png>` for SVG
(density follows the requested scale). Same approval gate, same
output keys, same format allow-list. When no ImageMagick binary is
present the existing honest "only available on macOS" failure
stands, now naming ImageMagick as the Linux prerequisite. No
ImageMagick binary exists on this VM, so the fallback is verified
only at the argv-builder / gate level in tests; a Mac/Linux run with
ImageMagick installed is pending.

## 13. `plist_editor` vs `plist_edit` — verified distinct, no change

Legacy: `AssistPlistTool.swift` (`plist_editor`: actions
read/set/delete/list_keys, `filePath` param, `valueType`
string/boolean/integer, preserves the source plist format on write)
vs `AssistPlistEditTool.swift` (`plist_edit`: actions get/set/delete,
`path`+`key` params, string values only, always writes XML, verifies
by re-read after `set`). Different ids, different schemas, different
semantics. Destination: both are registered (`plist_edit` in
`SwiftCodeTools+FileWriting.swift`, `plist_editor` in
`SwiftCodeTools+Signing.swift`) with those same distinctions. Nothing to
do; no duplication is created.

## 14. Package.swift wiring needed (coordinator applies)

1. `SwiftCodeMCP` target resources: add
   `.copy("Resources/ReverseBridge.mjs")` (or `.process("Resources")`)
   so `Bundle.module` finds the bridge at runtime. Without it,
   `reverse_analyze` fails honestly naming the missing resource.
2. Yams (full YAML, §11): add
   `.package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")`
   and `Yams` to the `SwiftCodeMCP` target dependencies.
3. `SecretAccount.composioKey = "composio.api-key"` in
   `swiftcode/Sources/SwiftCodeAssistant/SecretStore.swift` (one line; the
   Composio client carries the string locally until the patch lands).
4. No new target, no new external dependency besides Yams (optional),
   no changes to any other target's dependencies. System frameworks
   used (`ScreenCaptureKit`, `AVFoundation`, `ApplicationServices`,
   `ImageIO`) need no SPM declaration.

## 15. Tests

`swiftcode/Tests/SwiftCodeMCPTests/FailingToolsGapTests.swift` (Swift Testing,
`@Test`, same `opened`/`TempSample` shape as the existing terminal
tests; `MCPWritePolicy.allow` where a tool writes):

- `env_capture_logs`: returns snapshot lines from a seeded
  `SwiftCodeSnapshots` entry + the memory preview + redacted env vars
  (a `*_TOKEN` var is `<redacted>`, a plain var is shown); empty
  snapshots → Legacy's fallback line.
- `get_process_logs`: own host run by pid returns its real output;
  unknown pid fails (no placeholder text anywhere); unified-log /
  journalctl argv builders produce the exact argv.
- `take_screenrecord` / `take_screenshot` window/region: validation
  errors on Linux (duration range, missing app, missing region rect,
  bad window id) with the honest messages; region crop math
  (scale + integral rect) unit-tested pure.
- `use_mcp`: `list` with no config returns Legacy's exact message;
  a stub stdio server (a small script speaking NDJSON JSON-RPC via
  real Node) lists tools and executes one through the test-seam
  config; bad `arguments` JSON fails before connecting.
- `use_composio`: slug validation; key resolution order with a
  `MemorySecretStore`; CLI argv builder; CLI-output JSON extraction;
  no key + no CLI → honest failure naming both prerequisites.
- `use_workers`: validation (missing task, unknown dependency,
  500-char truncation, duplicate-name suffixing, cycle detection);
  batch plan persisted to `.assist_temp/workers/`; execution fails
  honestly naming the missing subagent runtime; stub-executor run
  completes and reconciles target files.
- `dependency_audit`: `Package.resolved` v1/v2/v3 parsing to OSV
  queries; OSV response mapping (incl. fixed-version extraction);
  missing `Package.resolved` fails honestly; stubbed OSV fetcher
  returns a vulnerability and the tool reports it, and returns none
  and the tool reports the real negative.
- `reverse_analyze`: missing node/REA/bridge → honest failure naming
  the missing piece; stub bridge via real Node + test-seam paths
  returns a canned Evidence envelope end-to-end (spawn + NDJSON +
  validation + Markdown rendering); validation chain unchanged
  (bad operation / out-of-scope target / bad objdump op).
- `use_app`: pure helpers (keycode table incl. Return/Escape/arrows,
  coordinate-space conversion, menu-path splitting, window-id
  parsing); AX actions are NOT executed in tests (they need a Mac
  with Accessibility permission) — validation errors only.
- `parse_yaml`: block scalars (literal/folded, chomping, indent
  indicator), anchors/aliases, merge keys; tags still rejected.
- Images (Linux): no ImageMagick → honest failure; argv builders for
  convert/thumbnail/svg produce the exact argv.

No Swift toolchain exists in this environment: static checks only.
Mac `swift build` / `swift test` and all live runs (ScreenCaptureKit,
AX, OSV live query, REA with a real rea-agents install, ImageMagick
on Linux) are pending on Dylan's Mac.

## 16. Files changed (destination only, uncommitted)

Owned edits: `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Terminal.swift`,
`SwiftCodeTools+AgenticExecution.swift`, `SwiftCodeTools+AgenticNetwork.swift`,
`SwiftCodeTools+AgenticData.swift`, `SwiftCodeTools+Media.swift`,
`SwiftCodeTools+Engines.swift`. New files under
`swiftcode/Sources/SwiftCodeMCP/`: `SwiftCodeTools+FailingToolsSupport.swift`,
`SwiftCodeTools+MCPClient.swift`, `SwiftCodeTools+ComposioClient.swift`,
`SwiftCodeTools+WorkersRuntime.swift`, `SwiftCodeTools+AppInteraction.swift`,
`SwiftCodeTools+ScreenRecording.swift`, `SwiftCodeTools+ReverseBridge.swift`,
`SwiftCodeTools+DependencyAudit.swift`,
`Resources/ReverseBridge.mjs`. New tests:
`swiftcode/Tests/SwiftCodeMCPTests/FailingToolsGapTests.swift`. New spec: this
file. Nothing in Legacy, nothing in SwiftCode-New, no ledger/manifest
edits, no `Package.swift` edits (see §14).

## 17. Evidence

- Legacy sources read: `AssistLogCaptureTool.swift`,
  `GetProcessLogs.swift`, `DependencyAudit.swift`,
  `TakeScreenshot.swift`, `AssistTakeScreenshotTool.swift`,
  `AssistTakeScreenrecordTool.swift`, `AssistScreenCaptureEngine.swift`,
  `AssistScreenRecordingEngine.swift`, `UseMCP.swift`,
  `AssistComposioTool.swift`, `ComposioService.swift`,
  `UseWorkersTool.swift`, `AssistUseAppTool.swift`,
  `AssistAppInteractionEngine.swift`, `AssistImageMutationTools.swift`,
  `AssistPlistTool.swift`, `AssistPlistEditTool.swift`,
  `ReverseToolAdapter.swift`, `ReverseBridge.swift`,
  `ReverseBridge.mjs`, `AssistSnapshotFunctions.swift`,
  `AssistSnapshotModels.swift`, `KeychainService.swift`
  (`composio_api_key`).
- Live checks: OSV `querybatch` (lodash 4 vulns; 4 SwiftURL packages
  none — §0), `npm view rea-agents@6.5.0` (exists, MIT, latest
  6.8.0), `node --version` v24.22.1, `which magick/convert` (absent),
  Yams via web search (MIT, SPM 6.2.2, Linux OK).
- Destination state verified before editing: 433 tools, zero
  duplicate ids; the Wave 4/5/8 headers in the owned files (honest
  failures / partials as quoted in each section above).
