# Extensions v2

A complete, production-oriented extension platform for SwiftCode with
three distinct ecosystems:

1. **VS Code extensions** — real packages from Open VSX, executed by a
   genuine out-of-process Node.js extension host.
2. **SwiftCode-native plugins** — a versioned Swift SDK for extensions
   built directly for SwiftCode.
3. **Xcode source-editor compatibility** — an adapter for reusable
   XcodeKit-shaped command logic (not XcodeKit binaries).

## Repository audit (2026-10-29, main `0b7126e9`)

- Xcode project: `SwiftCode.xcodeproj`, Swift 6.0, app target
  `SwiftCode`, deployment target macOS 15.0 for the app target.
  Source files must be registered in `project.pbxproj` — placing a
  file in a directory does not include it in the build.
- The app already has a legacy `ExtensionManager` /
  `ExtensionManifest` in `SwiftCode/Services` and a second
  `ExtensionManifest` in `SwiftCode/SDK`. All Extensions v2 types
  therefore carry the `ExtV2` prefix; there is no second lifecycle
  manager and no competing registry.
- Sidebar: `MainSidebarItem` in `SwiftCode/Views/Sidebar/
  SidebarMainView.swift` is the only exhaustive sidebar switch. The
  Extensions v2 integration adds one case (`extensions`,
  "puzzlepiece") and one switch arm rendering `ExtensionsHomeView`.
  Nothing else in the sidebar was redesigned.
- Assist: `AssistToolRegistry` (`SwiftCode/Backend/Assist/
  AssistToolRegistry.swift`) is `@MainActor`, keeps the first
  registration on a duplicate id, and tools conform to `AssistTool`
  with `execute(input:context:) -> AssistToolResult`. Extensions v2
  registers into this registry only, via `ExtV2AssistBridge`.
- Editor: no SourceKit-LSP client existed in the app. Extensions v2
  ships its own minimal LSP client (`ExtV2LanguageClient`); it does
  not claim an existing integration.
- Directory names contain a space (`Extensions v2`). The pbxproj
  groups use quoted paths (`path = "Extensions v2";`); the on-disk
  layout and the project layout match.

## Layout (mandatory directories)

- `SwiftCode/Backend/Extensions v2/` — Core, Registry, Packages,
  Manifests, Dependencies, Runtime, IPC, VSCodeCompatibility,
  Workspace, Editor, LanguageServices, NativeSDK, XcodeCompatibility,
  Permissions, Assist, Storage, Diagnostics, Resources, Tests.
- `SwiftCode/Views/Extensions v2/` — `ExtensionsHomeView`,
  `ExtensionRunView`, search, installed, details, permissions,
  settings, diagnostics, updates, row, view models.
- Existing-file changes are limited to the sidebar case above and
  pbxproj registration. No other feature was modified.

## How it works

### Discovery and installation

`ExtV2RegistryClient` talks to Open VSX (`{base}/-/search`,
`{base}/{namespace}/{name}`, download via `files.download` with the
documented `/file/` fallback). Search supports pagination, empty
results, cancellation (a superseded keystroke is not an error), and
registry/network errors surfaced verbatim.

`ExtV2PackageService.install` validates before extracting (size and
entry caps), rejects absolute paths and `..` traversal, extracts
with `ditto` into staging (never in place, never executing package
scripts), rejects symlinks on a post-extraction walk, requires
`extension/package.json` to parse and to match the expected identity,
requires the declared `main` entry to exist, evaluates compatibility,
then commits with a single directory move. The previous version is
kept as a backup until the commit succeeds, so rollback is a move.
Interrupted installs leave only staging behind, which is cleaned at
launch. A broken extension is recorded as `.unavailable` /
`.incompatible` and can never block launch.

### VS Code host

One Node.js process per extension (`ExtV2HostManager`), speaking
NDJSON JSON-RPC v1 (`ExtV2RPC`) over stdio. The embedded host script
(`ExtV2HostScript.source`) intercepts `require('vscode')` and
replaces it with a shim implementing the supported surface; the
extension's own `node_modules` resolve normally. Host-initiated
requests (file reads/writes, diagnostics, provider registration,
permission requests) are served by `ExtV2Manager` through the
workspace bridge and permission manager. A host that crashes is
marked `.crashed`; after 3 consecutive crashes it stays stopped
until the user retries it manually — no restart loops. Node.js is
discovered from settings or `/opt/homebrew/bin/node`,
`/usr/local/bin/node`, `/usr/bin/node`; without Node, activation
fails with an actionable message instead of a silent no-op.

### API matrix (versioned, in `ExtV2VSCodeAPI.matrix`)

Supported: commands, window messages, output channels, quick pick /
input box (headless fallback: no selection, logged), workspace fs,
open/apply edits, configuration, document-change events, completion,
hover, definition, references, rename, formatting, code actions,
diagnostic collections, status bar, tree data, snippets.
Partial: progress UI, tasks, terminal (no full PTY), source control,
themes, grammars, webviews (restricted bridge, see below).
Unsupported (the shim throws a descriptive error, never fake
success): debug, notebooks, testing, authentication, secrets,
custom editors, filesystem providers, full PTY terminals.

### Editor and workspace bridges

`ExtV2WorkspaceBridge` enforces workspace containment after symlink
resolution and checks capabilities on every call; git access is
read-only `git status` via the real binary. `ExtV2EditorBridge`
applies edits in reverse order against current on-disk content,
validates ranges, rejects overlaps, and counts columns in Swift
Characters (emoji-safe). **Limitation, stated plainly:** v1 edits
are file writes plus an `ExtV2DocumentDidChange` notification; they
do not reach into an NSTextView's undo stack. Extension edits are
therefore not undoable from the editor's Undo menu in v1. Direct
NSTextView integration is the documented next wiring step.

### Language servers

`ExtV2LanguageClient` is a real LSP client over stdio
(Content-Length framing): initialize with capability negotiation,
initialized, didOpen/didChange/didClose, completion, hover,
shutdown/exit, restart, plus 30s request timeouts. It does not
assume any server binary exists; a missing executable is a clear
error. SourceKit-LSP can be used as the Swift server by pointing
the client at the `sourcekit-lsp` executable for a workspace.

### Native SDK (v1)

Conform to `ExtV2NativePlugin`, declare an
`ExtV2NativePluginManifest` (id, commands, capabilities), register
with `ExtV2NativePluginRegistry`. The sample plugin
(`ExtV2SamplePlugin`, command `extv2.sample.listWorkspace`) compiles
and runs, and is registrable from Extensions > Native Extensions
and Settings. **Trust boundary:** plugins compiled into the app run
in-process and are trusted as much as the app. Third-party native
code is NOT dynamically loaded in-process by this SDK — there is no
bundle loader, deliberately, because in-process loading would bypass
every permission check. Untrusted code should ship as a VS Code
extension through the out-of-process host.

### Xcode compatibility

`ExtV2XcodeCompatibility` models `XCSourceTextBuffer`,
`XCSourceTextRange`, `XCSourceTextPosition`,
`XCSourceEditorCommand`, and invocations as SwiftCode-native types
(0-based positions, Character-counted columns). Commands register
in `ExtV2XcodeCommandRegistry` and run against a caller-supplied
buffer with validated, atomic edit batches. The included
`ExtV2SortLinesCommand` is a working example and the UI demo in
Extensions > Xcode Compatibility. Categories, kept distinct
everywhere in UI and docs:

1. SwiftCode-native extensions (SDK / VS Code host).
2. Reusable Xcode source-editor command logic (this adapter).
3. XcodeKit extension binaries — run under Xcode only, never here.
4. External developer tools via documented interfaces (e.g. LSP).

### Assist

`ExtV2AssistBridge` builds validated descriptors (stable tool ids
`extv2.<extension>.<command>`, typed parameter schemas, required
parameters, required capabilities, read-only flag) and registers
`ExtV2ExtensionAssistTool` into the existing registry only when
`.assistTools` is granted. Execution re-validates input, re-checks
capabilities, routes by command ownership (a tool can never run
another extension's command), and enforces the host timeout.
Failures return `.failure`, never silent success.

### Assist: `use_extension`

Assist interacts with installed extensions through the `use_extension`
tool (`SwiftCode/Backend/Assist/Tools/UseExtensionTool.swift`,
registered in `AssistToolRegistry`, catalogued in `AvailableTools.md`,
mapped in `ToolCallMap`). Actions: `list`, `details`,
`list_commands`, `list_xcode_commands`, `activate`, `deactivate`,
`execute`, `run_xcode_command`, `enable`, `disable`, `diagnostics`.
VS Code extensions run via activation + command execution through
the real host (with confirm: true, `execute` activates first when
stopped, so one call works end to end); native plugin commands route
through the native registry; Xcode commands run against real
workspace files via a source buffer, writing back only on change.
Mutating actions require `confirm: true`. The tool itself launches
nothing — all execution goes through `ExtV2Manager`, so permission
checks, the IPC allowlist, and crash handling apply exactly as from
the UI. Test coverage lives in `ExtV2TestSuite` (validation, Xcode
file round-trip, unknown-command and path-escape failures).

### Permissions and security

Capabilities are declared per extension, granted explicitly,
persisted in `grants.json`, and revocable from Extensions >
Permissions (revocation applies on the next call). Defaults are
deny; with no prompt handler, a request is denied. IPC methods are
allowlisted on both sides; oversize messages are dropped and the
host faulted. Secrets are never passed to extension hosts and never
logged. A permission prompt is not a sandbox: the actual boundaries
are process isolation for VS Code extensions, the IPC allowlist,
capability checks in the bridges, archive validation, and resource
limits (`ExtV2ResourceLimits`).

### Persistence and recovery

`~/Library/Application Support/SwiftCode/ExtensionsV2/` holds
`installed.json`, `grants.json`, `settings.json`,
`diagnostics.jsonl`, `staging/`, `extensions/<id>/`, and
`backups/`. All JSON writes are atomic (temp file + replace).
Restart, interrupted downloads/installs, failed updates, host
crashes, disablement, revocation, dependency removal, and offline
startup are all handled by re-reading authoritative records, never
by assuming prior UI state.

## Verification status (honest)

- Static checks done in this environment (no Swift toolchain here):
  file inventory, pbxproj registration, brace balance, cross-file
  symbol review, and a Node syntax check of the embedded host
  script (extracted and parsed with `node --check`).
- In-app self-tests: Extensions > Diagnostics > "Run self-tests"
  (`ExtV2TestSuite`) covers versions, engine requirements, manifest
  validation, compatibility, dependency resolution (missing and
  cycles), editor/Xcode edits (including emoji columns, overlaps,
  failed-batch atomicity), RPC validation (round-trip, disallowed
  methods, oversize), permissions (deny-by-default, grant, revoke,
  handler-less request), identity parsing, and Assist descriptor
  validation.
- Still pending on Dylan's Mac (never claimed as passed):
  `xcodebuild` build of the full app target, running
  `ExtV2TestSuite` in-app, a real Open VSX search + VSIX install,
  a real VS Code extension activation through the Node host
  (requires Node.js on the Mac), the sample native plugin run,
  the Xcode sort-lines demo, and an Assist tool call from an
  extension command.

## Mac checklist (for Dylan)

1. Open `SwiftCode.xcodeproj`, build the SwiftCode target.
2. Extensions sidebar item → Discover → search → install a small
   Open VSX extension; confirm state, details, and diagnostics.
3. Run view → activate → run a contributed command.
4. Extensions > Diagnostics > Run self-tests → all pass.
5. Extensions > Xcode Compatibility → Sort all lines on the demo
   buffer.
6. Extensions > Settings → register the sample native plugin, then
   run `extv2.sample.listWorkspace` from its Run view.
