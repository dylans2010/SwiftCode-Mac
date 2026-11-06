# Assist artboards / media / engines tools — behaviour (Wave 5)

Wave 5 of the Legacy -> Mac migration: Artboards (8), Simulator & devices (4),
Image (7), Archive (6), Data (5), Engines (4), Web (1), Reverse (1) — 36 tools.
Merged from the three family specs written by the Wave 5 slice workers; each part
keeps its original internal section numbering (§1, §2, … are part-scoped). The
catalogue entries are `specs/ide/assist-tool-catalogue.md` §126–§165.

Clean-room note: this spec describes behaviour and formats only; no Legacy method
bodies, decompiler text, or Apple code are reproduced in it (this repo's `AGENTS.md`).
## Part A — Artboards / simulator

## Assist artboards / simulator tools — behaviour (Wave 5)

Behaviour for the 12 Legacy Assist tools ported in Wave 5 onto SwiftCode's MCP
host: 8 Artboards tools and 4 Simulator / device tools. See
`assist-tool-catalogue.md` for each tool's ID, schema, capability / risk /
permission, and gate. Legacy source (Dylan's own code, ported under MIT):
`SwiftCode/Backend/Assist/Tools/` in `dylans2010/SwiftCode-Legacy` @
`d51a8f0d`. Registry order below is Legacy's `registerAllTools()` order.

Catalogue count for this wave: **12 IDs served with 10 new registrations +
2 alignments.** `simulator_boot` and `simulator_list` are NOT re-registered:
SwiftCode already registers them in `SwiftCodeTools+Run.swift` (`runTools`) for the
SwiftCode Simulator, and duplicate IDs would break the catalogue's uniqueness
invariant and `MCPServerTests`. They are aligned in place instead (§3).
New registrations: `artboardTools` (8) in
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Artboards.swift` and `simulatorTools` (2:
`device_list`, `simulator_controller`) in
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Simulator.swift`. The coordinator wires
both arrays into `installTools()` in `SwiftCodeTools.swift`
(`server.tools = … + artboardTools + simulatorTools`).

### 1. Conventions shared by this wave

- **Schemas are Legacy's verbatim, plus `workspace`.** Every tool takes
  the `workspace` parameter Wave 1 adds to every tool (optional; opens the
  workspace when it is not the open one). Descriptions below are Legacy's
  verbatim. Structured data keeps Legacy's keys, with typed JSON values
  (integers and booleans) the way SwiftCode's other tools do — Legacy's
  string-only data map is not reproduced. Tools whose Legacy result
  carries no data return a plain text result instead.
- **Risk → annotations** (catalogue §1.3, extended the way Wave 3 extended
  it for `.execution`): `safeRead` → `.read` (`readOnly: true, idempotent:
  true`), `writes: false`; `safeMutation` → `readOnly: false, idempotent:
  true`, `writes: true`; `.execution` → `readOnly: false, idempotent:
  false`, `writes: true`.
- **Approval, no Autopilot.** Every `writes: true` tool is refused in
  `readOnly` server mode by `MCPServer.run` before its handler runs.
  Mutations then go through the approval gate before acting: file writes
  through `commit()` (Wave 2), non-file mutations through
  `approveChangeWithoutFile()` (the Wave 4 `terminalApproveChange` shape
  without requiring an open workspace — the change's path is the workspace
  root when one is open, else the current directory). Legacy's Autopilot
  bypass is deliberately **not** ported.
- **Argument vectors, never a shell.** Every local command runs a fixed
  binary with a fixed argv via Wave 4's `terminalRunFixed` (off the main
  actor), stdin closed, with a timeout (`simctl list` / `devicectl` /
  `xctrace` 60 s; `simctl boot`/`shutdown` 120 s; `simulator_controller`
  300 s). No command string is ever assembled. A timeout is reported,
  never retried silently.
- **Artboards are in-memory, host-scoped.** SwiftCode has no Artboards system
  (the destination audit verified `Artboard` occurs 0 times in destination
  source) and no artboard file format, so the record lives in-memory on
  the host (`SwiftCodeMCPHost.artboards`, `activeArtboardID`), exactly as
  Legacy's lived in-memory in `DocumentCoordinator`'s
  `VisualUIDocument`. Artboards are not persisted to disk, do not survive
  a server restart, and are not scoped per workspace. A fresh server
  starts with no artboards. Legacy's fresh `VisualUIDocument` likewise
  started empty apart from its `Default` canvas root, which SwiftCode does
  **not** seed — but the `Default` deletion guard is kept: an artboard
  named `Default` cannot be deleted.
- **Lookup is Legacy's.** An identifier that parses as a UUID matches by
  id; anything else matches the first artboard whose name contains it
  (case-insensitive). No identifier means the active artboard, else the
  first artboard.

### 2. Seams

- **Artboards → `SwiftCodePreviews`, not a parallel preview system.**
  Compiling an artboard renders its custom SwiftUI source through
  `PreviewRenderRunner` (the `preview_render` engine: writes the source
  to a temporary `<name>.swift`, renders the first `#Preview` — or the
  one `targetView` names — to a PNG headlessly against the open SwiftUI
  port). There is no live preview host in the MCP server, so there is no
  live session, no hosted view, and no build-log stream: success is the
  PNG, failure is the renderer's message + log.
- **No Visual UI Builder component model.** A created artboard's
  component tree is the single root node Legacy's create tool makes (a
  `vStack` named `"<name> Root"` with no children). `artboard_get` prints
  that one line for source-less artboards. There is no drag-and-drop
  canvas, no component insertion, and no code generation beyond the
  custom source the caller supplies.
- **`artboard_run_app` → the existing `run` tool.** It delegates to
  `run(call)`: build the scheme and run it on this computer, or on the
  SwiftCode Simulator when the destination is one. Legacy ran the full app
  on an Apple simulator via `FullAppRunManager`; SwiftCode has no
  Apple-simulator run destination.
- **Simulator tools → `xcrun` as a subprocess, not `SwiftCodeSimFeatures`.**
  `SwiftCodeSimFeatures` is the SwiftCode Simulator's guest-feature channels
  (health, audio, location, settings) — not an Apple `simctl` wrapper —
  and nothing in it is used here. **No new `Package.swift` dependency is
  needed for this wave:** `SwiftCodeMCP` must NOT gain a `SwiftCodeSimFeatures`
  dependency. The simulator tools call `/usr/bin/xcrun` (`simctl`,
  `devicectl`, `xctrace`) as a subprocess; where `xcrun` is absent they
  fail with Legacy's exact message instead of pretending the SwiftCode
  Simulator is a substitute.

### 3. The `simulator_boot` / `simulator_list` collision — alignment

SwiftCode already registers `simulator_boot` and `simulator_list` in
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Run.swift` (`runTools`): they drive the
SwiftCode Simulator on its remote Linux host (`simulator_boot` takes a
`simulator` name/id, default the first, and starts a device without an
app; `simulator_list` lists SwiftCode Simulator devices and whether each is
running, empty when no host is set up). Legacy's tools with the same IDs
target Apple Simulator via `simctl` — same IDs, different backend.
Following the Wave 1 `file_read` / Wave 2 `file_write` alignment
precedent, the existing registrations are aligned in place to cover the
Legacy behaviour where the two can honestly share one tool. The shared
`simctl` helpers (`appleSimulators()`, `parseSimctlDevices(_:)`,
`simctlBootOrShutdown(udid:action:call:)`, `requireXcrun()`,
`runXcrun(_:timeout:)`) live in `SwiftCodeTools+Simulator.swift`.

#### 3.1 `simulator_list` — aligned

| Aspect | SwiftCode (before) | Aligned (now) |
|---|---|---|
| `simulators` | SwiftCode Simulator devices on the remote host | Unchanged |
| `configured` | Whether a SwiftCode Simulator host is set up | Unchanged — still refers to the SwiftCode host only |
| `appleSimulators` | — (did not exist) | **New, always present.** Legacy's `simctl list devices -j` listing: each entry `{name, udid, state, runtime, available}`, runtimes sorted, devices sorted by name within a runtime (Legacy's order). Empty when `xcrun` is absent or the listing fails — never an error. |
| Text | SwiftCode devices, or `No SwiftCode Simulator host is set up.` | Both sections: the SwiftCode lines (or the no-host line), then an Apple section (`Apple simulators (N, M booted): …`, `Apple simulators: none installed.`, or `Apple simulators: unavailable (xcrun not found; install Xcode command line tools).`) |
| Input | None | None (Legacy's `simulator_list` also takes no parameters) |

What cannot be represented: Legacy's result carried only Apple counts
(`device_count`, `runtime_count`, `available_count`, `booted_count`) as
its data; the aligned tool keeps SwiftCode's `simulators`/`configured` as the
primary keys and carries the Apple listing as an array instead — the
counts are the array's length and the `Booted` entries in it. Legacy's
failure modes do not transfer: Legacy failed when `xcrun` was missing or
`simctl list` errored or no simulators existed; the aligned tool reports
an empty Apple section instead, because the SwiftCode half of the tool must
still answer when Apple tooling is absent (e.g. on Linux, where the
existing `SwiftCodeToolsTests` asserts `configured == false`).

#### 3.2 `simulator_boot` — aligned

| Aspect | SwiftCode (before) | Aligned (now) |
|---|---|---|
| No-arg / `simulator` | Boots the SwiftCode Simulator device (default the first) | Unchanged |
| `udid` | — (did not exist) | **New, optional.** An Apple simulator's UDID (UUID) routes to `simctl` instead of the SwiftCode Simulator. Takes precedence when both `simulator` and `udid` are given. |
| `action` | — (did not exist) | **New, optional, Apple path only.** `boot` or `shutdown`, default `boot`. Without a `udid` it is an error: `Invalid action: '<action>'. Pass a udid to boot or shut down an Apple simulator with simctl.` |
| Apple-path validation | — | Legacy's, verbatim: a non-UUID `udid` fails with `Invalid udid: '<udid>' is not a valid UUID.`; an action other than `boot`/`shutdown` fails with `Invalid action: '<action>'. Expected boot or shutdown.` |
| Apple-path execution | — | Legacy's `AssistSimulatorBootTool`: `xcrun simctl <action> <udid>` (60 s… 120 s timeout), then verify by re-listing regardless of the first command's exit code (booting an already-booted device reports an error yet leaves it in the desired state). Success: `Simulator <udid> is now <state> (action: <action>).` with structured `{simulator, state}` (SwiftCode's output keys, not Legacy's `{udid, action, state}`). Wrong state: `Simulator <udid> is <state>, expected <desired>. Detail: <detail>`. UDID absent from the listing: `Simulator with UDID <udid> was not found in simctl list.` Verification itself failing: `Ran simctl <action> (exit <code>) but verification failed: <stderr>`. |
| Apple-path approval | — | The mutation goes through `approveChangeWithoutFile` (the real call, so the server's policy applies) before `simctl` runs. The SwiftCode path keeps its existing behaviour (`writes: true` policy gate only). |
| `xcrun` absent | — | `xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.` (Legacy's message) |

What cannot be represented: Legacy's `simulator_boot` required `udid`
and had no SwiftCode half; the aligned tool keeps `udid` optional so the
existing no-arg SwiftCode call (used by `MCPThorTests`) still boots the
remote device. Legacy's structured data keys (`udid`, `action`,
`state`) are not reproduced — the aligned tool emits SwiftCode's
`{simulator, state}` on both paths.

#### 3.3 Overlapping behaviour (not duplication)

- `simulator_controller`'s `boot`/`shutdown` actions overlap the aligned
  `simulator_boot` (UDID → Apple `simctl`, name → SwiftCode remote) and
  SwiftCode's `simulator_shutdown` (SwiftCode remote only). The controller is the
  `simctl`-native multi-action entry point (boot, shutdown, install,
  launch, openurl) on any device selector `simctl` accepts (`booted`, a
  name, or a UDID); `openurl` and `install` have no SwiftCode equivalent.
- `simulator_controller`'s `launch` overlaps SwiftCode's
  `simulator_launch_app` only in outcome (an app launched on a
  simulator): the SwiftCode tool installs + launches on the remote SwiftCode
  Simulator, this one launches an already-installed bundle id on an
  Apple simulator.
- `device_list` (physical devices via `devicectl`, falling back to
  `xctrace`) has no SwiftCode equivalent: the Device Hub lists physical
  devices in the UI, but no MCP tool does.

### 4. Artboard tools

#### 4.1 `artboard_compile`

- **Legacy description (verbatim):** "Triggers compilation and preview
  generation of a custom artboard or the active SwiftUI file."
- **Legacy schema (verbatim):** object, "Compiles an artboard or active
  SwiftUI document for live preview." Properties: `identifier` (string,
  "Optional artboard UUID or name to compile. If omitted, compiles active
  document/artboard."), `targetView` (string, "Optional name of the SwiftUI
  View or #Preview target to compile."). Required: none.
- **Legacy capability / risk:** compilation / safeMutation.
- **Port behaviour:** resolves the artboard (§1 lookup). With custom
  source, renders it through `SwiftCodePreviews` (§2) and returns the PNG as
  an image block plus the summary `Artboard compiled successfully.\nHosted
  View: Ready`, structured `{status: "success", preview_target}`. On
  render failure it records the log as the artboard's
  `lastCompileError` and returns the error `Artboard preview compilation
  failed.\nLogs:\n<log>` with structured `{status: "failed",
  preview_target}`. `preview_target` is `targetView` when given, else the
  artboard name. `targetView` selects a preview by name; with no
  `targetView` the first `#Preview` renders (Legacy defaulted the target
  to the artboard name, but an unnamed `#Preview` is called `Preview`,
  not the artboard name — see `PreviewDiscovery`).
- **Errors:** no artboards / no match → `No artboards currently configured
  in workspace.` / `Artboard matching '<identifier>' not found. Use
  'artboard_list' to view available artboards.` An artboard with no custom
  source → `Artboard '<name>' has no custom SwiftUI source to compile (the
  MCP host has no active document to fall back to). Give it source with
  artboard_update, or render a file's preview with preview_render.`
  (Legacy fell back to the active document; the MCP host has no active
  document — the delegate only exposes an open file's text by path, not
  which file is open.) Approval is requested before compiling.
- **Output schema:** `{status, preview_target}`.

#### 4.2 `artboard_create`

- **Legacy description (verbatim):** "Creates a new artboard in the
  Visual UI Builder with custom SwiftUI code or standard component
  layout."
- **Legacy schema (verbatim):** object, "Creates a new artboard in the
  active document." Properties: `name` (string, "Name of the new artboard
  (e.g., 'SettingsView', 'ProfileCanvas')."), `deviceFrame` (string,
  "Target device simulator frame (e.g., 'iPhone 16 Pro', 'iPad Pro').
  Defaults to 'iPhone 16 Pro'."), `sourceCode` (string, "Optional custom
  SwiftUI source code with #Preview to render in this artboard."),
  `appearance` (string, "Color appearance: 'System', 'Light', or 'Dark'.
  Defaults to 'System'."), `isPortrait` (boolean, "Orientation: true for
  portrait, false for landscape. Defaults to true."). Required: `name`.
- **Legacy capability / risk:** fileModification / safeMutation.
- **Port behaviour:** blank `name` fails with Legacy's `Parameter 'name'
  is required.` (a missing `name` is rejected earlier by the schema's
  required list, as with the other ported tools). Creates the record with
  Legacy's defaults (`deviceFrame` `iPhone 16 Pro`, `appearance`
  `System`, `isPortrait` true), root node `vStack` named `"<name> Root"`
  with no children, makes it the active artboard, and returns
  `Successfully created artboard '<name>' (ID: <uuid>) with frame
  '<deviceFrame>'.`, structured `{id, name, deviceFrame}`. Approval is
  requested before creating. Duplicate names are allowed, as in Legacy;
  `appearance` is stored as given (Legacy does not validate it).
- **Output schema:** `{id, name, deviceFrame}`.

#### 4.3 `artboard_delete`

- **Legacy description (verbatim):** "Deletes an artboard from the Visual
  UI Builder canvas by identifier or name."
- **Legacy schema (verbatim):** object, "Deletes an artboard."
  Properties: `identifier` (string, "The UUID or name of the artboard to
  delete."). Required: `identifier`.
- **Legacy capability / risk:** fileModification / safeMutation.
- **Port behaviour:** no artboards → `No artboards currently configured
  in workspace.` No match → `No artboard found matching '<identifier>'.`
  An artboard named `Default` cannot be deleted: `The 'Default' artboard
  cannot be deleted as it is the workspace canvas root.` (Legacy's guard;
  SwiftCode seeds no `Default` artboard, so this only bites when one was
  created by that name.) Otherwise approval is requested, the artboard is
  removed, the active pointer moves to the first remaining artboard, and
  the tool returns `Artboard '<name>' (ID: <uuid>) deleted successfully.`,
  structured `{id, name}`.
- **Output schema:** `{id, name}`.

#### 4.4 `artboard_get`

- **Legacy description (verbatim):** "Retrieves full configuration,
  component tree hierarchy, and custom SwiftUI source code for a
  specified artboard."
- **Legacy schema (verbatim):** object, "Retrieves details of an artboard
  by identifier or name." Properties: `identifier` (string, "The name or
  UUID of the artboard to inspect. If omitted, inspects the active
  artboard."). Required: none.
- **Legacy capability / risk:** diagnostics / safeRead.
- **Port behaviour:** resolves the artboard (§1 lookup) and prints
  Legacy's lines — name, ID, device frame, appearance (`System` when
  unset), orientation, dynamic type size (`Medium` when unset), scale
  (`1.0` when unset), safe areas (`Visible` when unset) — then the last
  compile error when one was recorded by `artboard_compile` (Legacy read
  `DocumentCoordinator.compiledArtboardErrors`; SwiftCode keeps only the last
  compile failure per artboard), then either the custom SwiftUI source
  (under `Custom SwiftUI Source Code:`) or the component hierarchy
  (under `Component Hierarchy:`, the single root line `- [vStack] <root
  name>` — there is no component model to describe further). Structured
  `{id, name, deviceFrame, hasCustomSource}` (Legacy's keys, typed).
- **Errors:** no match → `Artboard matching '<identifier>' not found. Use
  'artboard_list' to view available artboards.` (with `active` when no
  identifier was given).
- **Output schema:** `{id, name, deviceFrame, hasCustomSource}`.

#### 4.5 `artboard_list`

- **Legacy description (verbatim):** "Lists all artboards in the active
  Visual UI Builder workspace, including IDs, device frames, appearance,
  and component counts."
- **Legacy schema (verbatim):** object, "Lists all artboards in the
  current document." No properties. Required: none.
- **Legacy capability / risk:** diagnostics / safeRead.
- **Port behaviour:** empty → `No artboards currently configured in
  workspace.` with structured `{artboard_count: 0, active_artboard_id:
  "", artboards: []}`. Otherwise Legacy's lines (`Found N artboard(s):`,
  then per artboard its number, name, ID, `[ACTIVE]` marker, device
  frame, mode — `custom source` or `component tree` — with root type and
  child count, appearance and orientation), structured
  `{artboard_count, active_artboard_id, artboards}` where each artboard
  entry is `{id, name, deviceFrame, appearance, isPortrait,
  hasCustomSource, active}`.
- **Output schema:** `{artboard_count, active_artboard_id, artboards}`.

#### 4.6 `artboard_run_app`

- **Legacy description (verbatim):** "Builds the active project and runs
  it directly inside an iOS/macOS simulator, reporting logs and execution
  status."
- **Legacy schema (verbatim):** object, "Builds and runs the full app on
  the target simulator." No properties. Required: none.
- **Legacy capability / risk:** compilation / safeMutation.
- **Port behaviour:** delegates to the existing `run` tool (§2): builds
  the scheme and runs it on this computer or on the SwiftCode Simulator
  destination, returning the `run` tool's result (`{runId, state,
  output}`). Legacy refused when a run was already in progress (`An
  application execution run is already in progress.`); the `run` tool's
  own run tracking replaces that guard. Legacy's failure shape (`Full app
  run failed.\nStep: <step>\nLogs:\n…`, `Full application compiled and
  launched successfully.\nDuration: …`) is not reproduced — the `run`
  tool's result is returned as-is. An Apple-simulator run is not
  available (SwiftCode has no Apple-simulator run destination).
- **Output schema:** `{runId, state, output}`.

#### 4.7 `artboard_update`

- **Legacy description (verbatim):** "Updates an existing artboard's
  source code, device frame, appearance, or properties."
- **Legacy schema (verbatim):** object, "Updates an existing artboard."
  Properties: `identifier` (string, "The UUID or name of the artboard to
  update. Defaults to active artboard."), `name` (string, "New name for
  the artboard."), `deviceFrame` (string, "New device simulator frame."),
  `sourceCode` (string, "Updated custom SwiftUI source code."),
  `appearance` (string, "'System', 'Light', or 'Dark'."),
  `isPortrait` (boolean, "Orientation: true for portrait, false for
  landscape."). Required: none.
- **Legacy capability / risk:** fileModification / safeMutation.
- **Port behaviour:** resolves the artboard (§1 lookup); no artboards →
  `No artboards currently configured in workspace.`; no match →
  `Artboard not found matching '<identifier>'.` Approval is requested,
  then the supplied fields are applied (a replaced `sourceCode` clears
  the recorded compile error, as in Legacy) and the tool returns
  `Updated artboard '<name>': <fields>` where `<fields>` is Legacy's
  comma-joined list (`name: '…'`, `deviceFrame: '…'`, `sourceCode
  (length: N)`, `appearance: '…'`, `isPortrait: true/false`),
  structured `{id, name}`. With no fields supplied the message ends
  after the colon, as in Legacy.
- **Output schema:** `{id, name}`.

#### 4.8 `fix_artboards`

- **Legacy description (verbatim):** "Audits the entire Artboards,
  Visual UI Builder, and Preview subsystem, diagnoses simulator,
  destination, code signing, and syntax errors, and applies automated
  repairs until compilation succeeds."
- **Legacy schema (verbatim):** object, "Audits and automatically repairs
  Artboards, SwiftUI Previews, and Full App Run failures." Properties:
  `errorContext` (string, "Optional error message or log excerpt that
  triggered the fix request."), `scope` (string, "Optional repair scope:
  'preview', 'full_app', 'all'. Defaults to 'all'."). Required: none.
- **Legacy capability / risk:** diagnostics / safeMutation.
- **Port behaviour — four passes, Legacy's order:**
  1. **Simulator & destination audit (audit-only).** Counts Apple
     simulators (via `simctl list`) and booted ones, and notes whether a
     SwiftCode Simulator host is configured. Legacy realigned
     `XcodeBuildManager`'s destination to a booted simulator and booted
     one when none was booted; SwiftCode has no `XcodeBuildManager`
     destination to realign and this tool does not boot a simulator on
     its own — use `simulator_boot` for that.
  2. **Clean DerivedData / stale build state (reported, not performed).**
     When `errorContext` contains `already in progress`, `exit code 70`,
     `exit code 65`, or `corrupted` (Legacy's triggers), the action list
     records that no DerivedData clean applies in SwiftCode (use the `clean`
     tool for the workspace build). Nothing is cleaned.
  3. **Active artboard source repair (real).** On the active artboard's
     custom source: injects a missing `import SwiftUI` header, and
     appends a missing `#Preview` macro (`#Preview {\n    <name>()\n}`)
     when neither `#Preview` nor `PreviewProvider` is present. Each
     repair is recorded with Legacy's wording (`Injected missing 'import
     SwiftUI' header into artboard '<name>'`, `Appended missing #Preview
     macro for '<name>'`). A repaired source clears the recorded compile
     error.
  4. **Verification compile pass (real, artboard only).** Re-renders the
     active artboard through `SwiftCodePreviews` when it has custom source
     (Legacy recompiled the active document; the MCP host has no active
     document). Success records `Recompiled artboard '<name>' live preview
     session`; failure records the same line with `(still failing — see
     logs)` and keeps the log as the compile error.
  - **Scope** is validated (`preview`, `full_app`, `all`); anything else
    fails with `Invalid scope: '<scope>'. Expected 'preview', 'full_app',
    or 'all'.` Legacy accepted any value and ignored it. The scope does
    not otherwise change which passes run — Legacy's passes do not branch
    on it either.
  - **Result:** Legacy's summary shape — `Fix with Assist completed audit
    and repairs:` + one `  • <action>` line per action, blank line,
    `Result Status: Healthy / Resolved` (or `Repairs Applied, verifying
    compiler logs` when the verification render failed), `Logs Summary:` +
    the last 1000 characters of the verification log (empty when nothing
    was compiled, which counts as healthy). Legacy judged success from
    the build log's wording; the port uses the render outcome itself,
    because a headless render failure (e.g. no Swift toolchain) may
    produce a log containing neither `failed` nor `error:`. Structured
    `{repaired: true, actions_count}` (Legacy's keys, typed — Legacy's
    values were the strings `"true"` and the count).
- **Output schema:** `{repaired, actions_count}`.

### 5. Simulator / device tools

#### 5.1 `device_list`

- **Legacy description (verbatim):** "Lists connected Apple devices via
  devicectl, falling back to xctrace. Fails clearly when no devices are
  found or the tooling is unavailable."
- **Legacy schema (verbatim):** object, "Lists connected devices. No
  parameters." No properties. Required: none.
- **Legacy capability / risk:** diagnostics / safeRead.
- **Port behaviour:** `xcrun` absent → Legacy's `xcrun not found at
  /usr/bin/xcrun. Install Xcode command line tools first.` Otherwise
  `xcrun devicectl list devices -j`, parsed Legacy's way (`result.devices`
  or top-level `devices`; each device's `identifier`/`udid`,
  `deviceProperties.name`, `hardwareProperties.platform`,
  `connectionProperties.pairingState`; lines `<name> (<id>)` with ` -
  <platform>` and ` - <pairing>` appended when present). Non-empty:
  `Connected devices: N` + the lines, structured `{devices,
  device_count, source: "devicectl"}` where each device entry is `{name,
  identifier, platform, pairing}`. Empty devicectl list → Legacy's `No
  connected devices found (devicectl returned an empty device list).
  Connect a device and trust this Mac, then try again.` Unparseable or
  failing devicectl falls back to `xcrun xctrace list devices`: its
  non-empty text lines (blank lines and `==`/`Devices` headers dropped)
  answer as `Connected devices (via xctrace): N` + the lines, structured
  `{devices, device_count, source: "xctrace"}`; an empty listing fails
  with Legacy's `No connected devices found (xctrace returned an empty
  device list). Connect a device and trust this Mac, then try again.`
  Both failing → `Device listing unavailable. <devicectl detail>.
  xctrace fallback also failed (exit <code>): <stderr>.`
- **Output schema:** `{devices, device_count, source}`.

#### 5.2 `simulator_boot` (aligned — see §3.2)

- **Legacy description (verbatim):** "Boots or shuts down a simulator by
  UDID via simctl, then verifies the resulting state."
- **Legacy schema (verbatim):** object, "Boots or shuts down a simulator
  by UDID." Properties: `udid` (string, "Simulator UDID in UUID format
  (required)."), `action` (string, "boot or shutdown. Default is boot.").
  Required: `udid`.
- **Legacy capability / risk:** systemExecution / execution.
- **Port behaviour:** §3.2. The SwiftCode half keeps its title, description
  stem, `simulator` parameter, annotations (`readOnly: false`) and
  `writes: true`; the Legacy parameters `udid` and `action` are added as
  optional. The aligned input schema is therefore the union of the two
  tools' schemas (Legacy's `udid` required-ness is dropped — the SwiftCode
  path needs no UDID).
- **Output schema:** `{simulator, state}` (SwiftCode's keys, on both paths).

#### 5.3 `simulator_controller`

- **Legacy description (verbatim):** "Controls Apple platform simulators
  (boot, shutdown, install app, open URL) via simctl."
- **Legacy schema (verbatim):** object, "Controls simulator state.
  Actions: 'boot', 'shutdown', 'install', 'launch', 'openurl'."
  Properties: `action` (string, "Action: 'boot', 'shutdown', 'install',
  'launch', or 'openurl'."), `device` (string, "Device name or UDID (e.g.
  'booted', 'iPhone 16 Pro', or UUID)."), `appPath` (string, "Path to
  .app bundle when action is 'install'."), `bundleId` (string, "Bundle
  identifier when action is 'launch'."), `url` (string, "URL string when
  action is 'openurl'."). Required: `action`.
- **Legacy capability / risk:** systemExecution / safeMutation.
- **Port behaviour:** `device` defaults to `booted`, as in Legacy. The
  action dispatches to a fixed `xcrun simctl …` argv (Legacy's mapping,
  verbatim): `boot <device>`, `shutdown <device>`, `install <device>
  <resolved appPath>`, `launch <device> <bundleId>`, `openurl <device>
  <url>`. Missing per-action arguments fail with Legacy's messages
  (`Action 'install' requires 'appPath'.`, `Action 'launch' requires
  'bundleId'.`, `Action 'openurl' requires 'url'.`); an unknown action
  fails with `Unsupported action '<action>'. Supported: boot, shutdown,
  install, launch, openurl.`; a missing `action` is rejected by the
  schema's required list. A relative `appPath` resolves against the
  workspace root when a workspace is open, else the current directory
  (Legacy resolved against its workspace root). `xcrun` absent →
  Legacy's `xcrun not found…` message. The mutation goes through the
  approval gate before `simctl` runs. Exit 0 → `Simulator operation
  '<action>' succeeded on device '<device>'. <output>` with structured
  `{action, device, output}` (combined stdout+stderr, trimmed); non-zero
  → `Simulator command failed (exit code <code>): <output>`. Legacy ran
  the process synchronously with no timeout; the port uses a 300 s
  timeout (a timeout reports as a launch/exit failure, never retried).
- **Output schema:** `{action, device, output}`.

#### 5.4 `simulator_list` (aligned — see §3.1)

- **Legacy description (verbatim):** "Lists available iOS/tvOS/watchOS
  simulators with runtime, state, and UDID via simctl."
- **Legacy schema (verbatim):** object, "Lists available simulators. No
  parameters." No properties. Required: none.
- **Legacy capability / risk:** diagnostics / safeRead.
- **Port behaviour:** §3.1. The SwiftCode half keeps its title, `simulators`
  / `configured` keys and read-only annotations; Legacy's listing is
  carried as the `appleSimulators` array. Legacy's summary line
  (`Simulators: <total> device(s) across <runtimes> runtime(s),
  <available> available, <booted> booted.`) is not reproduced as a
  standalone message — the Apple section's header carries the same
  counts (`Apple simulators (<total>, <booted> booted):`).
- **Output schema:** `{simulators, configured, appleSimulators}`.

### 6. Not ported / honestly-failing

Nothing in this wave is registered as honestly-failing: all 12 IDs have a
real implementation or a real alignment. The following Legacy behaviours
are **not ported** (recorded here, not silently dropped):

- **`artboard_compile`'s live preview session.** Legacy started a live
  `PreviewManager` session (hosted view, streaming build logs). SwiftCode
  renders a single PNG headlessly instead (§4.1). Blocker: no live preview
  host exists in the MCP server.
- **`artboard_compile`'s active-document fallback.** Legacy compiled the
  active document when no artboard matched. The MCP host has no active
  document. Blocker: no open-file tracking in `SwiftCodeMCPHost` (the
  delegate exposes an open file's text by path only).
- **The Visual UI Builder itself.** Drag-and-drop canvas, component
  insertion/editing, and code generation from a component tree do not
  exist in SwiftCode. The artboard tools carry only the record (name, device
  frame, appearance, orientation, custom source) and the single root
  node. Blocker: no Visual UI Builder subsystem (a UI + model port, not
  an MCP-tool port).
- **`artboard_run_app` on an Apple simulator.** Legacy ran on an Apple
  simulator via `FullAppRunManager`. The port runs via the `run` tool
  (host or SwiftCode Simulator destination). Blocker: SwiftCode has no
  Apple-simulator run destination.
- **`fix_artboards` pass 1 (destination realignment + booting) and pass 2
  (DerivedData clean).** Pass 1 is audit-only; pass 2 is reported, not
  performed (§4.8). Blockers: no `XcodeBuildManager` destination model,
  no DerivedData cache in SwiftCode.
- **`simulator_boot` / `simulator_list` as separate Apple-only tools.**
  They share their IDs with SwiftCode's remote-simulator tools and are
  aligned into them (§3) rather than registered twice.
- **Legacy's string-only data map.** Every tool's structured data uses
  typed JSON values (integers, booleans) instead of Legacy's all-string
  dictionary. The keys are kept; the value types are SwiftCode's convention
  (Waves 1–4).

### 7. Safety rules

- **No shell, ever.** All `simctl` / `devicectl` / `xctrace` invocations
  are fixed argv vectors to `/usr/bin/xcrun` (`terminalRunFixed`).
  Device names, UDIDs, bundle ids, URLs and app paths come from tool
  arguments but are passed as single argv elements, never interpolated
  into a command string.
- **Mutations need approval.** `artboard_create`, `artboard_update`,
  `artboard_delete`, `artboard_compile`, `artboard_run_app`,
  `fix_artboards`, `simulator_controller`, and the Apple path of the
  aligned `simulator_boot` all call the approval gate before acting
  (`approveChangeWithoutFile`, or the `run` tool's own gate for
  `artboard_run_app`). The server's read-only policy refuses them all
  before the handler runs. There is no allow-list and no Autopilot.
- **Artboard state is host memory, not files.** The artboard tools never
  read or write workspace files (except `artboard_compile`'s temporary
  render input under the system temp directory, removed afterwards, and
  the `run` tool's normal build through `artboard_run_app`). Nothing an
  artboard tool does can silently modify the user's project.
- **`simctl` never touches a booted device it was not asked to.** The
  aligned `simulator_boot` acts only on the UDID it was given;
  `simulator_controller` acts only on the `device` it was given
  (default `booted`, Legacy's default). `fix_artboards` boots nothing.
- **`xcrun` absence is a clear failure, not a fallback.** On a machine
  without Xcode command line tools, the Apple-simulator tools fail with
  Legacy's `xcrun not found…` message; the aligned `simulator_list`
  reports an empty Apple section alongside the SwiftCode listing.

### Evidence

| Claim | Level | Source |
|---|---|---|
| All 12 IDs, titles, descriptions, capabilities, risk levels, and input schemas | 1 | Legacy source, read directly: `SwiftCode/Backend/Assist/Tools/AssistArtboardCompileTool.swift`, `AssistArtboardCreateTool.swift`, `AssistArtboardDeleteTool.swift`, `AssistArtboardGetTool.swift`, `AssistArtboardListTool.swift`, `AssistArtboardRunAppTool.swift`, `AssistArtboardUpdateTool.swift`, `AssistFixArtboardsTool.swift`, `AssistDeviceListTool.swift`, `AssistSimulatorBootTool.swift`, `AssistSimulatorControllerTool.swift`, `AssistSimulatorListTool.swift` (`dylans2010/SwiftCode-Legacy` @ `d51a8f0d`) |
| SwiftCode already registers `simulator_boot` / `simulator_list` for the remote SwiftCode Simulator; no `Artboard` symbol exists in destination source | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Run.swift` (`runTools`, `simulatorList()`, `simulatorBoot(_:)`); destination audit `~/SwiftCode-Migration-Workspace/audit/destination-architecture.md` §5 (`Artboard` 0 hits) |
| Artboard tools map onto `SwiftCodePreviews`; compile renders via `PreviewRenderRunner` | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Content.swift` (`preview_list`, `preview_render`, `renderPreview(_:)`); `swiftcode/Sources/SwiftCodePreviews/PreviewRenderRunner.swift` (`render(file:name:output:starts:progress:)`), `PreviewDiscovery.swift` (unnamed `#Preview` → `Preview`, `Preview 2`, …) |
| `SwiftCodeSimFeatures` is guest-feature channels, not a `simctl` wrapper; no new `Package.swift` dependency needed | 1 | SwiftCode `swiftcode/Sources/SwiftCodeSimFeatures/` (14 files: health/audio/location/settings channels); `swiftcode/Package.swift` (`SwiftCodeMCP` target dependencies — `SwiftCodeSimFeatures` absent) |
| Approval gate shape for non-file mutations; write-policy gate | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Terminal.swift` (`terminalApproveChange`); `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift` (`MCPServer.run`, `MCPToolAnnotations`, `MCPChange`) |
| `run` tool delegation for `artboard_run_app` | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Run.swift` (`run(_:)`, `launchOnSimulator(app:destination:session:wait:remote:)`) |
| Existing tests pin `simulator_list`'s `configured` key and `simulator_boot`'s no-arg SwiftCode behaviour | 1 | SwiftCode `swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeToolsTests.swift` (`simulatorToolsUseTheRemoteHost`); `swiftcode/Tests/SwiftCodeMCPTests/MCPThorTests.swift` (`bootAndScreenshotOnTheRemoteSimulator`, opt-in) |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |


## Part B — Image / archive / data

## Assist image / archive / data tools — behaviour (Wave 5)

Behaviour for the 18 Legacy Assist tools ported in Wave 5 onto SwiftCode's MCP
host: 7 image tools, 6 archive / compression tools, 5 data / structured-file
tools. See `assist-tool-catalogue.md` for each tool's ID, schema, capability /
risk / permission, and gate. Legacy source (Dylan's own code, ported under
MIT): `SwiftCode/Backend/Assist/Tools/AssistImageInspectionTools.swift`,
`AssistImageMutationTools.swift`, `AssistArchiveTools.swift`,
`AssistBinaryPlistConverterTool.swift`, `AssistJsonValidateTool.swift`,
`AssistJSONValidatorTool.swift`, `AssistYAMLParserTool.swift`,
`AssistYamlValidateTool.swift` in `dylans2010/SwiftCode-Legacy` @ `d51a8f0d`.
Registry order below is Legacy's `registerAllTools()` order (alphabetical
within each family).

Implementation: `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Media.swift`
(`mediaTools`, 7 image tools) and
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ArchiveData.swift` (`archiveTools`,
6 archive tools; `dataTools`, 5 data tools). The coordinator wires
`mediaTools`, `archiveTools` and `dataTools` into `installTools()` in
`SwiftCodeTools.swift` (this slice must not edit that file).

### 1. Conventions shared by all 18 tools

- **Schemas are Legacy's `parametersSchema` verbatim, plus `workspace`.**
  Legacy's parameter-name aliases (`filePath`, `base64`, `data`,
  `destinationPath`, `dest`, `source`, `sourcePath`, `archive`,
  `archivePath`) are NOT supported: SwiftCode's argument validation rejects
  unknown arguments before the handler runs (same as Waves 1–2).
- **Structured data keeps Legacy's keys with typed values.** Legacy's
  tool results carry string-only data maps (`"size": "123"`); the port
  returns integers and booleans (`"size": 123`) the way SwiftCode's other
  tools do. Tools whose Legacy result carries no data return a plain
  text result instead.
- **Workspace-confined paths.** The read tools use the session-aware
  `resolveFileReadingPath` (plain relative paths against the `dir_cd`
  working directory; `..` that stays inside the workspace is allowed;
  `~` expands; a leading `/` is workspace-root-relative unless it is
  really inside the workspace). Every other tool here uses the strict
  `resolveFileWritingPath` (trim; reject empty, NUL, a leading `~` and
  any `..`; plain relative paths against the workspace root, never the
  session directory) — the same shape as Legacy's image-mutation,
  archive, `json_validate` and `yaml_validate` resolvers. No path is
  ever allowed to escape the workspace. Legacy's `json_validator_tool`,
  `yaml_parser_tool` and `binary_plist_converter` had NO confinement
  (absolute paths anywhere were accepted); the port confines them —
  a deliberate security tightening, recorded in §6.
- **Approval, no Autopilot.** Every writing handler gates BEFORE
  touching disk: binary writes and subprocesses through
  `approveFileWritingChange` (the Wave 2 helper), text writes through
  `commit()`. `MCPServer.run` already refuses `writes: true` tools when
  the server is read-only; the approval call is still required.
  Legacy's Autopilot bypass is deliberately NOT ported.
- **Subprocesses are fixed argument vectors, never a shell.** `tar`
  and `gzip` run `/usr/bin/tar` and `/usr/bin/gzip` on both platforms
  with Legacy's argv verbatim. `zip` / `unzip` run `/usr/bin/ditto`
  on macOS and the system `zip` / `unzip` tools on Linux (§4).
  Subprocess runs have a 120-second timeout (Legacy had none); a
  timeout is reported, never retried silently.
- **No new dependency.** Image reading uses a small pure-Foundation
  header parser (§2); plist conversion uses `PropertyListSerialization`
  (§5); YAML uses Legacy's own heuristic, ported verbatim (§5).
  SwiftCode still has no ZIPFoundation, no YAML library, no image
  decoder/encoder and no SVG rasterizer.

### 2. Image tools — `mediaTools`

#### 2.1 The pure-Foundation header parser

`image_get_dimensions` and the Linux half of `image_extract_metadata`
read image headers with `MediaHeaderParser` (PNG, JPEG, GIF, BMP, WebP,
TIFF) and `MediaTIFFParser` (TIFF/EXIF IFDs) — byte-level parsing with
Foundation only, no pixel decoding, no new dependency.

- **PNG:** IHDR gives width, height, bit depth, colour type (0/4 →
  `Gray`, else `RGB`; alpha for types 4 and 6). A `pHYs` chunk with
  unit 1 (pixels per metre) gives DPI (`ppm × 0.0254`); otherwise 72.
- **JPEG:** SOF0–SOF15 (except DHT/JPG/DAC) gives precision, height,
  width, component count (1 → `Gray`, else `RGB`; never alpha).
  JFIF APP0 gives density (unit 1 = DPI, unit 2 = dots per cm × 2.54).
  Scanning stops at SOS/EOI.
- **GIF:** the logical screen descriptor gives the size; the packed
  field's colour-resolution bits give the depth. Transparency lives
  in a graphic-control extension, which the header read does not
  chase — GIFs report no alpha.
- **BMP:** BITMAPINFOHEADER gives size, bit count (32-bit → alpha),
  and pixels per metre (DPI when present).
- **WebP:** VP8X gives width/height minus one plus the alpha flag;
  VP8 (lossy) and VP8L (lossless) give 14-bit sizes; VP8L also gives
  its alpha flag.
- **TIFF:** the first IFD's width (256), height (257), bits per
  sample (258), photometric (262: 0/1 → `Gray`, else `RGB`), samples
  per pixel (277: 2 or 4 → alpha), X/Y resolution (282/283,
  rationals) and resolution unit (296: 2 = inch, 3 = cm × 2.54).
- **`format` is the UTI string Legacy's ImageIO path reports:**
  `public.png`, `public.jpeg`, `com.compuserve.gif`,
  `com.microsoft.bmp`, `org.webmproject.webp`, `public.tiff`.

On macOS, `image_get_dimensions` falls back to ImageIO
(`CGImageSourceCopyPropertiesAtIndex`) for formats the parser does not
know (HEIC, JPEG 2000, …). On Linux there is no fallback: an unknown
format fails with Legacy's "Could not create image source" wording.

#### 2.2 `image_convert_format` — Convert Image Format

- **Legacy description (verbatim):** "Converts an image file between
  formats (png, jpeg, tiff, bmp, gif) with optional compression quality."
- **Schema:** `path` (string, required), `format` (string, required),
  `destination` (string, optional), `quality` (number, optional,
  default 0.9). `quality` is "Compression quality for JPEG/HEIC (0.0
  to 1.0). Default: 0.9." — Legacy's wording, but HEIC is NOT an
  accepted target format (see §6).
- **Capability:** fileModification. **Risk:** safeMutation.
  **Permission:** fileSystem. **Gate:** approval before writing.
- **Behaviour:** decodes with AppKit (`NSImage` → TIFF
  representation → `NSBitmapImageRep`), re-encodes with
  `representation(using:properties:)` (JPEG gets
  `compressionFactor = quality`). Accepted formats, exactly Legacy's:
  `png`, `jpeg`/`jpg` (written as `.jpg`), `tiff`/`tif`, `bmp`,
  `gif`. Anything else fails with `Unsupported target format '<f>'.
  Supported formats: png, jpeg, tiff, bmp, gif.` Default
  destination: the source path with the new extension. Parent
  directories are created. Missing source fails with `Source image
  not found at: <path>`. Undecodable source fails with `Failed to
  read and decode image at: <path>`. A failed encode fails with
  `Failed to convert image to <format> format.`
- **Output:** `destination` (string), `size` (int), `format`
  (string, the lowercased requested format). Message:
  `Successfully converted \`<source>\` to <FORMAT> at \`<dest>\`
  (<n> bytes).`
- **macOS-only.** There is no image decoder/encoder on Linux, so
  the handler fails there with `image_convert_format is only
  available on macOS.` — registered, honestly failing, never faked
  (§6). Its real macOS behaviour stays pending verification on
  Dylan's Mac.

#### 2.3 `image_decode_base64` — Decode Base64 to Image

- **Legacy description (verbatim):** "Decodes a Base64-encoded string
  into an image file (PNG, JPEG, TIFF, GIF) and saves it to disk."
- **Schema:** `base64String` (string, required), `destination`
  (string, required). `base64String` "accepts raw base64 or
  data:image/...;base64,... URI".
- **Capability:** fileModification. **Risk:** safeMutation.
  **Permission:** fileSystem. **Gate:** approval before writing.
- **Behaviour:** a `data:…;base64,` prefix (text before the first
  comma containing `;base64`) is stripped; whitespace is removed;
  the remainder decodes with `.ignoreUnknownCharacters`. Empty or
  undecodable input fails with `Failed to decode base64 string into
  valid binary data.` The raw bytes are written as-is (no re-encode),
  atomically, with parent directories created. The destination
  resolves with the strict writer resolver; an escaping destination
  fails with `Destination path is outside the workspace: <path>`.
  The base64 payload is validated before the destination is
  resolved (Legacy's order); the approval gate runs before any
  directory is created or byte written.
- **Output:** `destination` (string), `size` (int). Message:
  `Successfully decoded base64 string and saved image to \`<dest>\`
  (<n> bytes).`

#### 2.4 `image_encode_base64` — Encode Image to Base64

- **Legacy description (verbatim):** "Reads an image file from the
  workspace and encodes it into a Base64 string or Data URI."
- **Schema:** `path` (string, required), `includeDataUri` (boolean,
  optional, default false).
- **Capability:** fileReading. **Risk:** safeRead. **Read-only.**
- **Behaviour:** reads the file bytes (any file — the extension only
  decides the MIME type, exactly like Legacy; there is no image
  validation). MIME by extension: png → `image/png`, jpg/jpeg →
  `image/jpeg`, gif → `image/gif`, webp → `image/webp`, svg →
  `image/svg+xml`, tif/tiff → `image/tiff`, anything else →
  `application/octet-stream`. With `includeDataUri`, the result is
  `data:<mime>;base64,<base64>`. Missing file fails with `Image file
  not found at: <path>`. Unreadable file fails with `Failed to read
  image file \`<path>\`: <reason>`.
- **Output:** `path` (string), `mimeType` (string), `byteCount`
  (int), `charCount` (int, length of the returned string including
  the data-URI prefix when present), `base64` (string, the returned
  string). Message: `Successfully encoded \`<path>\` into Base64
  (<raw> bytes raw, <b64> chars base64).\nPreview: <first 100 chars
  of the returned string>...`

#### 2.5 `image_extract_metadata` — Extract Image Metadata

- **Legacy description (verbatim):** "Extracts all embedded EXIF,
  TIFF, GPS, and camera metadata from an image as structured JSON."
- **Schema:** `path` (string, required).
- **Capability:** fileReading. **Risk:** safeRead. **Read-only.**
- **Behaviour (macOS):** ImageIO's full property dictionary
  (`CGImageSourceCopyPropertiesAtIndex`), sanitized exactly like
  Legacy (values that are not valid JSON objects become
  `String(describing:)`), serialized pretty-printed with sorted
  keys. A file ImageIO cannot open fails with `Could not read image
  source at: <path>`.
- **Behaviour (Linux):** only what the byte parser can read
  honestly, one group per embedded source:
  - **PNG:** `tEXt` keyword/value pairs and uncompressed `iTXt`
    pairs. `zTXt` (compressed text) is skipped — Foundation on
    Linux has no zlib inflate.
  - **JPEG:** the JFIF APP0 version/density, and the EXIF APP1
    payload: IFD0 plus the Exif (tag 34665) and GPS (tag 34853)
    sub-IFDs, with common tag numbers named (`Make`, `Model`,
    `Orientation`, `DateTimeOriginal`, `FocalLength`,
    `GPSLatitude`, …; unknown tags report as `Tag <number>`).
    Rationals report as doubles; ASCII values as strings;
    MakerNote reports as `(binary data, <n> bytes)`, never decoded;
    UserComment has its 8-byte encoding prefix stripped.
  - **GIF:** comment extensions (`0x21 0xFE`), walked block by
    block so image data is never mistaken for a comment.
  - **TIFF:** the first IFD's tags, named where known.
  - A file with no parseable embedded metadata returns zero groups
    (`{}`) rather than an error.
- **Output:** `path` (string), `metadataCount` (int, number of
  property groups — the ImageIO dictionary's key count on macOS,
  the embedded-group count on Linux), `metadataJSON` (string, the
  pretty-printed sorted-keys JSON). Message: `Extracted metadata
  from \`<path>\` (<n> property groups):\n<json>`.
- **The two platforms return different `metadataJSON` shapes for
  the same file.** That is the honest consequence of having ImageIO
  on one platform and only byte parsing on the other; callers must
  not assume the macOS shape on Linux or vice versa.

#### 2.6 `image_generate_thumbnail` — Generate Image Thumbnail

- **Legacy description (verbatim):** "Generates a scaled thumbnail
  image maintaining aspect ratio and writes it to disk."
- **Schema:** `path` (string, required), `maxPixelSize` (integer,
  optional, default 256), `destination` (string, optional).
- **Capability:** fileModification. **Risk:** safeMutation.
  **Permission:** fileSystem. **Gate:** approval before writing.
- **Behaviour:** ImageIO thumbnail creation
  (`kCGImageSourceCreateThumbnailFromImageAlways` +
  `kCGImageSourceCreateThumbnailWithTransform` +
  `kCGImageSourceThumbnailMaxPixelSize`), encoded as PNG. Default
  destination: `<name>_thumb.png` (the source path minus its
  extension, plus `_thumb.png`). A non-positive `maxPixelSize`
  fails with `Invalid maxPixelSize '<n>': must be a positive
  integer.` (Legacy did not validate it; an invalid size failed
  later inside ImageIO.) Missing source fails with `Source image
  not found at: <path>`; an unreadable source with `Could not read
  image source at: <path>`; a failed thumbnail with `Failed to
  create thumbnail from image: <path>`; a failed PNG encode with
  `Failed to encode thumbnail into PNG data.`
- **Output:** `destination` (string), `width` (int), `height`
  (int), `size` (int). Message: `Successfully generated <w>x<h>
  thumbnail for \`<source>\` at \`<dest>\` (<n> bytes).`
- **macOS-only,** same as `image_convert_format` (§2.2): on Linux
  the handler fails with `image_generate_thumbnail is only
  available on macOS.` (§6). Real macOS behaviour pending
  verification on Dylan's Mac.

#### 2.7 `svg_to_png` — Convert SVG to PNG

- **Legacy description (verbatim):** "Renders an SVG vector graphic
  into a raster PNG image file at a specified scale or dimensions."
- **Schema:** `path` (string, required), `destination` (string,
  optional), `scale` (number, optional, default 2.0), `width`
  (integer, optional), `height` (integer, optional).
- **Capability:** fileModification. **Risk:** safeMutation.
  **Permission:** fileSystem. **Gate:** approval before writing.
- **Behaviour:** AppKit rasterization exactly like Legacy:
  `NSImage(contentsOf:)` (AppKit parses the SVG), drawn into an
  `NSBitmapImageRep` through an `NSGraphicsContext`, encoded as PNG.
  An explicit width AND height together (both > 0) override the
  scale; otherwise the intrinsic size is multiplied by `scale`
  (default 2.0); a zero-sized intrinsic image renders at 512×512.
  Default destination: the source path with a `.png` extension.
  Missing file fails with `SVG file not found at: <path>`; an
  unparseable SVG with `Failed to parse and render SVG at: <path>`;
  a failed bitmap allocation with `Failed to allocate bitmap
  representation for SVG rendering.`; a failed graphics context
  with `Failed to create graphics context for bitmap.`; a failed
  PNG encode with `Failed to encode rendered SVG into PNG format.`
- **Output:** `destination` (string), `width` (int), `height`
  (int), `size` (int). Message: `Successfully rendered SVG
  \`<source>\` to PNG \`<dest>\` (<w>x<h>, <n> bytes).`
- **macOS-only,** same as `image_convert_format` (§2.2): on Linux
  the handler fails with `svg_to_png is only available on macOS.`
  (§6). Real macOS behaviour pending verification on Dylan's Mac.
  (Legacy's renderer is AppKit's SVG support, not a dedicated SVG
  engine; fidelity limits of that renderer are inherited, not fixed
  here.)

### 3. Archive tools — `archiveTools`

All six are fileModification / safeMutation / fileSystem, approval-gated
before any write, and report Legacy's messages verbatim.

#### 3.1 `zip_file` — Zip File or Directory

- **Legacy description (verbatim):** "Compresses a file or directory
  into a .zip archive using the macOS system archive tool."
- **Schema:** `path` (string, required), `destination` (string,
  required).
- **Behaviour:** macOS runs `/usr/bin/ditto -c -k --sequesterRsrc
  <source> <dest>` (Legacy's argv verbatim). Linux runs
  `/usr/bin/zip -r -q <dest> <name>` with the source's parent as
  the working directory, so the archive holds the item's own name
  the way ditto's does; `ditto` does not exist on Linux and
  `--sequesterRsrc` has no Linux equivalent. When `zip` is not
  installed, the tool fails with `zip_file needs the \`zip\`
  command-line tool, which is not installed on this system.`
  Missing source fails with `Source item not found at: <path>`.
  A failed run fails with `ditto zip failed with code <n>: <output>`
  on macOS, `zip failed with code <n>: <output>` on Linux.
- **Output:** `destination` (string), `size` (int). Message:
  `Successfully compressed \`<source>\` into \`<dest>\` (<n> bytes).`

#### 3.2 `unzip_file` — Unzip Archive

- **Legacy description (verbatim):** "Extracts a .zip archive into a
  destination directory using the macOS system archive tool."
- **Schema:** `path` (string, required), `destination` (string,
  required).
- **Behaviour:** macOS runs `/usr/bin/ditto -x -k <archive> <dir>`
  (Legacy's argv verbatim). Linux runs `/usr/bin/unzip -q -o
  <archive> -d <dir>`; when `unzip` is not installed, the tool fails
  with `unzip_file needs the \`unzip\` command-line tool, which is
  not installed on this system.` The destination directory is created
  when missing (after approval). Missing archive fails with `Archive
  file not found at: <path>`. A failed run fails with `ditto unzip
  failed with code <n>: <output>` on macOS, `unzip failed with code
  <n>: <output>` on Linux.
- **Output:** `destination` (string), `extractedCount` (int, the
  top-level item count of the destination directory after
  extraction). Message: `Successfully extracted \`<source>\` into
  \`<dest>\` (<n> extracted items).`

#### 3.3 `tar_archive_create` — Create Tar Archive

- **Legacy description (verbatim):** "Creates a .tar or .tar.gz
  archive from a directory or files using system tar."
- **Schema:** `path` (string, required), `destination` (string,
  required), `gzip` (boolean, optional).
- **Behaviour:** `/usr/bin/tar -czf|-cf <dest> -C <parent> <name>`
  (Legacy's argv verbatim, both platforms). `gzip` defaults to true
  for `.tar.gz` / `.tgz` destinations, false otherwise. The
  destination's parent directories are created (after approval).
  Missing source fails with `Source file/folder not found at:
  <path>`. A failed run fails with `tar failed with code <n>:
  <output>`.
- **Output:** `destination` (string), `size` (int). Message:
  `Successfully created tar archive \`<dest>\` (<n> bytes).`

#### 3.4 `tar_archive_extract` — Extract Tar Archive

- **Legacy description (verbatim):** "Extracts a .tar or .tar.gz
  archive into a destination directory using system tar."
- **Schema:** `path` (string, required), `destination` (string,
  required).
- **Behaviour:** `/usr/bin/tar -xf <archive> -C <dir>` (Legacy's
  argv verbatim, both platforms). The destination directory is
  created when missing (after approval). Missing archive fails with
  `Archive not found at: <path>`. A failed run fails with `tar
  extraction failed with code <n>: <output>`.
- **Output:** `destination` (string), `extractedCount` (int, the
  top-level item count of the destination directory after
  extraction). Message: `Successfully extracted archive \`<source>\`
  into \`<dest>\` (<n> extracted items).`

#### 3.5 `gzip_compress_file` — Gzip Compress File

- **Legacy description (verbatim):** "Compresses a file into a .gz
  file using system gzip."
- **Schema:** `path` (string, required), `destination` (string,
  optional, default `<path>.gz`).
- **Behaviour:** `/usr/bin/gzip -c -k -f <source>` (Legacy's argv
  verbatim, both platforms); the compressed bytes are captured from
  stdout as raw `Data` (never decoded as text) and written to the
  destination atomically after approval, with parent directories
  created. The source file is never modified (`-k`). Missing source
  fails with `File not found at: <path>`. A failed run fails with
  `gzip compression failed: <stderr>`.
- **Output:** `destination` (string), `size` (int). Message:
  `Successfully compressed \`<source>\` to \`<dest>\` (<n> bytes).`

#### 3.6 `gzip_decompress_file` — Gzip Decompress File

- **Legacy description (verbatim):** "Decompresses a .gz file into a
  destination file using system gzip."
- **Schema:** `path` (string, required), `destination` (string,
  optional, default: the `.gz` suffix removed, or
  `<path>.decompressed` when there is no `.gz` suffix).
- **Behaviour:** `/usr/bin/gzip -d -c -k -f <source>` (Legacy's argv
  verbatim, both platforms); the decompressed bytes are captured
  from stdout as raw `Data` and written to the destination
  atomically after approval, with parent directories created.
  Missing source fails with `Archive file not found at: <path>`.
  A failed run fails with `gzip decompression failed: <stderr>`.
- **Output:** `destination` (string), `size` (int). Message:
  `Successfully decompressed \`<source>\` to \`<dest>\` (<n> bytes).`

### 4. Data tools — `dataTools`

#### 4.1 `binary_plist_converter` — Binary Plist Converter

- **Legacy description (verbatim):** "Converts property list files
  between XML and Binary formats using plutil." (The schema's own
  description says "Converts .plist files to human-readable XML or
  compact binary format via plutil." — the port does not use plutil;
  see below.)
- **Schema:** `path` (string, required), `format` (string, optional,
  default `xml1`).
- **Capability:** fileModification. **Risk:** safeMutation.
  **Permission:** fileSystem. **Gate:** approval before writing.
- **Behaviour:** the file is read with
  `PropertyListSerialization` (which accepts XML and binary) and
  rewritten in the target format (`.xml` for `xml1`, `.binary` for
  `binary1`), atomically, in place. `format` is matched
  case-insensitively and validated explicitly — anything else fails
  with `Unsupported plist format '<f>'. Supported formats: xml1,
  binary1.` (Legacy passed the value straight to `plutil`, whose
  error wording this replaces.) Missing file fails with `File not
  found at: <path>`; an unreadable or invalid plist fails with
  `Failed to read plist at \`<path>\`: <reason>`. The path is
  confined to the workspace (Legacy accepted absolute paths
  anywhere — see §6).
- **Output:** none (plain text result). Message: `Successfully
  converted \`<path>\` to <format> format.`

#### 4.2 `json_validate` vs `json_validator_tool` — the near-duplicate pair

Legacy carries two JSON validation tools. Both are ported as separate
tools with their distinct Legacy behaviour; they are NOT merged.

| | `json_validate` | `json_validator_tool` |
|---|---|---|
| Legacy class | `AssistJsonValidateTool` | `AssistJSONValidatorTool` |
| Capability | fileModification | diagnostics |
| Risk | safeMutation | safeMutation |
| Parameters | `path`, `action` (`validate`/`format`, default `validate`), `write` (**string** `"true"`, default false) | `path`, `formatInPlace` (boolean, default false) |
| Top-level fragments | Allowed (`.allowFragments`) | Not allowed (no options) |
| Validate result | `Valid JSON in <rel>.` + data (`path`, `valid`, `written`) | `✅ JSON syntax valid for \`<path>\` (<n> bytes). Top-level type: <type>.` (no data) |
| Format result | Pretty-printed + sorted-keys preview in data as `formatted`; writes back only when `write` is true | Pretty-printed + sorted-keys rewrite in place when `formatInPlace` is true; message `JSON is valid! Successfully reformatted and saved \`<path>\` with standard 2-space pretty-printing.` |
| Invalid JSON | `Invalid JSON in <rel>: <reason>` | `JSON Validation Error in \`<path>\`: <reason>` |
| Missing file | `JSON validation requires an existing file: <path>` (directories also rejected) | `File not found at: <path>` |
| Unknown action | `Invalid action '<a>'. Allowed: validate, format.` | (no action parameter) |

Both use the strict writer resolver; an escaping path fails with
`Refusing to access path outside the workspace: <path>`. Both write
through `commit()` (approval-gated). `json_validate`'s `write`
accepts a JSON boolean as well as the string `"true"`/`"1"`/`"yes"`
(Legacy's `boolValue`); its schema still declares the string type,
verbatim from Legacy.

#### 4.3 `yaml_parser_tool` — YAML Parser & Validator

- **Legacy description (verbatim):** "Validates structure and syntax
  of YAML files (workflows, project.yml, fastlane) in the workspace."
  (The schema's own description: "Audits YAML indentation, keys, and
  syntax integrity for workflows or project specs.")
- **Schema:** `path` (string, required).
- **Capability:** diagnostics. **Risk:** safeRead. **Read-only.**
- **Behaviour:** reads the file as UTF-8 and reports, as Markdown:
  one error line per line starting with a tab (`Line <n>: Hard tab
  indentation detected. YAML strictly requires spaces.`), otherwise
  `✅ Indentation check passed (no invalid tabs detected).`, then
  `#### Root & Key Declarations (<n>):` listing the first 20 keys
  found (the text before the first `:` on each non-blank,
  non-comment line, skipping list-item keys and empty keys) as
  `- Line <n>: \`<key>\``. This is a heuristic listing, not a parse:
  no values are extracted and no structure is validated beyond the
  tab check. Missing file fails with `File not found at: <path>`;
  unreadable content with `Unable to read content of: <path>`.
- **Output:** none (plain text result, the Markdown report).

#### 4.4 `yaml_validate` — Validate YAML

- **Legacy description (verbatim):** "Heuristic YAML validation (no
  full YAML parser): rejects tab indentation, unbalanced
  brackets/quotes, duplicate top-level keys, and mapping lines
  without a colon. Format normalizes indentation to 2 spaces per
  level and only writes back when write is true and validation passes."
- **Schema:** `path` (string, required), `action` (`validate`/
  `format`, default `validate`), `write` (string `"true"`, default
  false).
- **Capability:** fileModification. **Risk:** safeMutation.
  **Permission:** fileSystem. **Gate:** approval before writing
  (through `commit()`).
- **Behaviour:** Legacy's heuristic, ported verbatim
  (`dataValidateYAML` / `dataFormatYAML`): tab indentation,
  unbalanced single/double quotes (quote-aware, comment-aware,
  escape-aware, block-scalar-aware), unbalanced `[`/`{` brackets,
  duplicate top-level keys, and mapping lines without a colon are
  errors; `---` resets the top-level key set; block scalars
  (`|` / `>`) suspend validation of their bodies. The formatter
  re-indents to 2 spaces per level (the step is the file's smallest
  positive indent when it is at least 2, else 2); block scalar
  bodies keep their original indentation; blank lines stay blank.
  It does not reflow or re-quote values. A non-UTF-8 file fails with
  `File <rel> is not valid UTF-8 text.` Validation failure fails
  with `YAML validation failed (heuristic — no full YAML parser) in
  <rel>:\n<errors>`. Unknown action fails with `Invalid action
  '<a>'. Allowed: validate, format.`
- **Output:** `path` (string), `valid` (bool), `heuristic` (bool,
  always true), `written` (bool); on `format`, `formatted` (string)
  is additionally returned (preview, or the written text). Messages:
  validate pass — `YAML validation passed (heuristic — no full YAML
  parser) in <rel>.`; format with write — the same plus `Formatted
  YAML written back to the file.`; format preview — the same plus
  `Formatted preview returned without writing.`

#### 4.5 YAML: what is NOT a parser

Neither YAML tool parses YAML into values. `yaml_parser_tool` lists
keys; `yaml_validate` checks heuristics and re-indents. SwiftCode has no
YAML library and none is added by this slice. A caller needing real
YAML values (nested maps, anchors, multi-document streams, typed
scalars) does not get them from these tools, and the tools say so in
their messages (`heuristic — no full YAML parser`). Adding a YAML
library (or a fuller hand-written parser) is a coordinator decision,
not something this slice smuggles in.

### 5. Per-tool Legacy description / schema verbatim

The tool titles, descriptions and parameter descriptions in
`mediaTools`, `archiveTools` and `dataTools` are Legacy's
`parametersSchema` text verbatim (plus the `workspace` parameter),
except where §6 notes a correction. Legacy source for each tool:

| Tool | Legacy class | Legacy file |
|---|---|---|
| `image_convert_format` | `AssistImageConvertFormatTool` | `AssistImageMutationTools.swift` |
| `image_decode_base64` | `AssistImageDecodeBase64Tool` | `AssistImageMutationTools.swift` |
| `image_encode_base64` | `AssistImageEncodeBase64Tool` | `AssistImageInspectionTools.swift` |
| `image_extract_metadata` | `AssistImageExtractMetadataTool` | `AssistImageInspectionTools.swift` |
| `image_generate_thumbnail` | `AssistImageGenerateThumbnailTool` | `AssistImageMutationTools.swift` |
| `image_get_dimensions` | `AssistImageGetDimensionsTool` | `AssistImageInspectionTools.swift` |
| `svg_to_png` | `AssistSvgToPngTool` | `AssistImageMutationTools.swift` |
| `gzip_compress_file` | `AssistGzipCompressTool` | `AssistArchiveTools.swift` |
| `gzip_decompress_file` | `AssistGzipDecompressTool` | `AssistArchiveTools.swift` |
| `tar_archive_create` | `AssistTarArchiveCreateTool` | `AssistArchiveTools.swift` |
| `tar_archive_extract` | `AssistTarArchiveExtractTool` | `AssistArchiveTools.swift` |
| `unzip_file` | `AssistUnzipFileTool` | `AssistArchiveTools.swift` |
| `zip_file` | `AssistZipFileTool` | `AssistArchiveTools.swift` |
| `binary_plist_converter` | `AssistBinaryPlistConverterTool` | `AssistBinaryPlistConverterTool.swift` |
| `json_validate` | `AssistJsonValidateTool` | `AssistJsonValidateTool.swift` |
| `json_validator_tool` | `AssistJSONValidatorTool` | `AssistJSONValidatorTool.swift` |
| `yaml_parser_tool` | `AssistYAMLParserTool` | `AssistYAMLParserTool.swift` |
| `yaml_validate` | `AssistYamlValidateTool` | `AssistYamlValidateTool.swift` |

Capability / risk / permission per tool (Legacy's `capability`,
`riskLevel`, and the default permission derivation — mutating tools
require `fileSystem`, read tools require none):

| Tool | Capability | Risk | Writes |
|---|---|---|---|
| `image_convert_format` | fileModification | safeMutation | yes |
| `image_decode_base64` | fileModification | safeMutation | yes |
| `image_encode_base64` | fileReading | safeRead | no |
| `image_extract_metadata` | fileReading | safeRead | no |
| `image_generate_thumbnail` | fileModification | safeMutation | yes |
| `image_get_dimensions` | fileReading | safeRead | no |
| `svg_to_png` | fileModification | safeMutation | yes |
| `gzip_compress_file` | fileModification | safeMutation | yes |
| `gzip_decompress_file` | fileModification | safeMutation | yes |
| `tar_archive_create` | fileModification | safeMutation | yes |
| `tar_archive_extract` | fileModification | safeMutation | yes |
| `unzip_file` | fileModification | safeMutation | yes |
| `zip_file` | fileModification | safeMutation | yes |
| `binary_plist_converter` | fileModification | safeMutation | yes |
| `json_validate` | fileModification | safeMutation | yes |
| `json_validator_tool` | diagnostics | safeMutation | yes |
| `yaml_parser_tool` | diagnostics | safeRead | no |
| `yaml_validate` | fileModification | safeMutation | yes |

### 6. Deliberate deviations and honest failures

- **macOS-only raster tools (§2.2, §2.6, §2.7).**
  `image_convert_format`, `image_generate_thumbnail` and `svg_to_png`
  are registered on every platform but fail on Linux with an exact
  `"<id> is only available on macOS."` message. No new dependency is
  added to fake them, and no Linux code path pretends to rasterize.
  Their real macOS behaviour (AppKit decode/encode, ImageIO
  thumbnails, AppKit SVG rendering) is implemented from Legacy but
  stays **pending verification on Dylan's Mac** — there is no Swift
  toolchain in this environment and no macOS to run them on.
- **`image_convert_format`'s `quality` description still says
  "JPEG/HEIC".** That is Legacy's wording, kept verbatim; HEIC is not
  an accepted target format.
- **`image_get_dimensions` values come from the header parser**
  (or ImageIO on macOS for unknown formats), not ImageIO alone.
  Same message shape and data keys as Legacy.
- **`image_extract_metadata` returns different shapes per platform**
  (full ImageIO dictionary on macOS; embedded-chunk subset on Linux).
  Compressed PNG text (`zTXt`) is skipped on Linux (no zlib inflate
  in Foundation there).
- **`zip_file` / `unzip_file` use `zip` / `unzip` on Linux**
  instead of macOS-only `ditto`; failure messages name the tool
  actually run. `ditto`'s `--sequesterRsrc` handling is not
  reproduced on Linux. The macOS `ditto` path is implemented from
  Legacy but stays pending verification on Dylan's Mac.
- **`binary_plist_converter` uses `PropertyListSerialization`,
  not `plutil`.** Same observable result for valid plists; explicit
  `xml1`/`binary1` validation; approval-gated; workspace-confined
  (Legacy accepted absolute paths anywhere).
- **Path confinement tightened** for `json_validator_tool`,
  `yaml_parser_tool` and `binary_plist_converter` (Legacy accepted
  absolute paths outside the workspace for these three).
- **`json_validate`, `json_validator_tool` and `yaml_validate` are
  `writes: true`** (Wave 2 precedent for conditional writers): a
  read-only server refuses even a validate-only call. The write
  itself is additionally approval-gated.
- **`json_validate` / `yaml_validate`'s `write` is string-typed in
  the schema (verbatim from Legacy), and SwiftCode's argument
  validation rejects a JSON boolean for it before the handler runs**
  (`the argument "write" must be of type string`). Legacy's
  `boolValue` accepts booleans too, and the port's handler still
  tolerates one — but through MCP only the string `"true"` /
  `"1"` / `"yes"` reaches it.
- **Structured data uses typed values** (integers/booleans) where
  Legacy used strings, per the Wave 2 convention. The `formatted`
  key of `json_validate` / `yaml_validate` is present only on the
  `format` action (the declared output schema lists the always-
  present keys).
- **No full YAML parser.** Both YAML tools are heuristic-only, as
  Legacy's are (§4.5).
- **Archive subprocess timeout (120 s).** Legacy had no timeout;
  the port reports a timeout instead of hanging forever.
- **`image_generate_thumbnail` validates `maxPixelSize > 0`.**
  Legacy did not; an invalid size failed later inside ImageIO.

### 7. Not ported / honestly failing

- `image_convert_format`, `image_generate_thumbnail`, `svg_to_png`
  on Linux: registered, honestly failing (§6). No other tool in this
  slice honestly fails: all 6 archive tools and all 5 data tools are
  fully implemented on both platforms, and the 3 image read tools
  plus `image_decode_base64` are fully implemented on both platforms.
- Nothing in this slice was silently dropped or merged. The
  `json_validate` / `json_validator_tool` pair and the
  `yaml_parser_tool` / `yaml_validate` pair are kept as separate
  tools with their distinct Legacy behaviour (§4.2).

### Evidence

- Legacy tool IDs, schemas, messages and behaviour: the eight Legacy
  source files listed in §5, read directly (Dylan's own code; direct
  porting authorised under MIT). Evidence level: Legacy source (the
  migration's authorised input), not Apple behaviour.
- SwiftCode host conventions (approval gate, `writes` flag, path
  resolvers, `.structured(_:summary:)` two-block results, `zip` /
  `unzip` / `tar` / `gzip` availability in this environment):
  `swiftcode/Sources/SwiftCodeMCP/` (Waves 1–4) and the tools present in the
  Linux VM (`/usr/bin/tar`, `/usr/bin/gzip`, `/usr/bin/zip`,
  `/usr/bin/unzip` present; `/usr/bin/ditto`, `/usr/bin/plutil`
  absent).
- PNG/JPEG/GIF/BMP/WebP/TIFF/EXIF header layouts: public file-format
  specifications (W3C PNG, ITU T.81 JPEG, GIF89a, Microsoft BMP,
  WebP container, TIFF 6.0 / EXIF 2.32) — public documentation, not
  Apple code. No reference Xcode copy, Ghidra, simulator IPSW,
  `research/dirty/`, or Apple binary was opened for this slice.


## Part C — Engines / web / reverse

## Assist engines / web / reverse tools — behaviour (Wave 5)

Behaviour for the 6 Legacy Assist tools ported in Wave 5 onto SwiftCode's MCP
host: 4 engines, 1 web / documentation tool, 1 reverse / binary-analysis
tool. See `assist-tool-catalogue.md` for each tool's ID, schema,
capability / risk / permission, and gate. Legacy source (Dylan's own code,
ported under MIT): `SwiftCode/Backend/Assist/Tools/
AssistCodeMutationEngine.swift`,
`AssistDependencyResolutionEngine.swift`,
`AssistExternalResourceGateway.swift`,
`AssistPatchApplicationEngine.swift`,
`AssistFetchDocumentationTool.swift`, and
`SwiftCode/Backend/Assist/API/Internal API/Reverse/
ReverseToolAdapter.swift` (+ `ReverseModels.swift`,
`ReverseCommandParser.swift`, `ReverseManager.swift`,
`ReverseBridge.swift`, `ReverseBridge.mjs`) in
`dylans2010/SwiftCode-Legacy` @ `d51a8f0d`. Registry order below is
Legacy's `registerAllTools()` order within each family.

### 1. Conventions shared by the engines / web / reverse tools

- **Workspace-confined file access.** `code_mutation_engine` and
  `patch_application_engine` resolve `path` with
  `resolveFileWritingPath` (relative to the workspace root, never the
  session working directory; a leading `/` is a filesystem path that
  must stay inside the workspace; `..` and `~` are rejected). A path
  that fails resolution fails with `Path not allowed: <path>`.
  `reverse_analyze` does NOT use the workspace relativizer at all:
  its `targetPath` must be absolute, and it is validated by its own
  scope rule (§7).
- **Approval, no Autopilot.** The two file-mutating engines write
  through `commit()`, so they go through SwiftCode's approval gate like
  every other write tool; `dependency_resolution_engine` gates its
  `xcodebuild` run through `terminalApproveChange` before executing.
  Legacy's `AssistPermissionsManager` Autopilot mode — under which
  SwiftCode-level restrictions are bypassed almost entirely — is
  deliberately **not** ported.
- **Risk → annotations** (catalogue §1.3, extended the way Wave 3
  extended it): `safeRead` → `.read` (`readOnly: true, idempotent:
  true`), `writes: false`; `safeMutation` → `readOnly: false,
  idempotent: true`, `writes: true`; `execution` → `readOnly: false,
  idempotent: false`, `writes: true`; `externalSideEffect` →
  `readOnly: false, idempotent: false, openWorld: true`, `writes:
  true`. One more annotation exists in this wave: `externalRead`
  (`readOnly: true, idempotent: true, openWorld: true`, `writes:
  false`) for `fetch_documentation` — a read that observes the
  outside world (the `system_notification_tool` precedent from Wave
  4). Tools registered `writes: true` are refused in `readOnly`
  server mode by `MCPServer.run` before the handler runs.
- **Honestly-failing tools.** A tool whose prerequisite does not exist
  in SwiftCode is still registered (same ID, same schema) and validates
  its inputs first with Legacy-exact messages, then fails naming the
  exact prerequisite — never a fake success. This wave:
  `reverse_analyze` (fully — see §7).
- **Permissions (Legacy derivation, catalogue §1.2).** `isMutating`
  in Legacy is `riskLevel == .safeMutation ||
  .potentiallyDestructive`; a mutating tool requires `fileSystem`,
  `use_terminal` requires `terminalExecution`, screenshot /
  screenrecord require `screenRecording`, `use_app` requires
  `accessibility`, everything else requires `none`. So in this wave
  only `code_mutation_engine` and `patch_application_engine`
  require `fileSystem`; the other four require `none`. A SwiftCode
  permission requirement is documentation here: the MCP host has no
  permission store, and macOS TCC prompts are the OS's, surfaced as
  errors when denied — never silently bypassed.
- **The `workspace` parameter.** Every tool in this wave accepts the
  Wave 1 `workspace` parameter. `fetch_documentation` and
  `external_resource_gateway` do not touch a workspace, so they accept
  it and ignore it (the Wave 4 precedent for clipboard, notifications,
  `use_app`, and the honestly-failing bridges).
- **Structured data keeps Legacy's keys, with typed JSON values.**
  Legacy's tool results carry a string-only `[String: String]` data
  map; the port returns the same keys with typed values (integers for
  counts / codes / exit codes, booleans for flags), the way SwiftCode's
  other tools do.

### 2. `code_mutation_engine` — Controlled Mutation Engine

- Legacy description (verbatim): "Applies safe, minimal source
  mutations scoped to a symbol or an exact range."
- Capability: `fileModification`. Risk: `safeMutation`. Permission:
  `fileSystem`. Gate: `commit()` (approval) — `writes: true`.
- Input (Legacy `parametersSchema` verbatim, plus `workspace`):
  `path` (string, required) — "Workspace-relative path of the file to
  mutate."; `replacement` (string, required) — "Replacement source
  text."; `symbol` (string) — "Symbol name whose body will be
  replaced. Provide either symbol or target."; `target` (string) —
  "Exact text to replace (all occurrences). Provide either symbol or
  target." Schema description: "Applies safe, minimal source mutations
  scoped to a symbol or an exact text range."
- Behaviour (Legacy's `execute`, ported exactly):
  - Reads the file. With `symbol`: finds the first occurrence of the
    symbol name, then the first `{` after it, then brace-counts to the
    matching `}`; the replaced range starts at the symbol name itself,
    so the declaration line is replaced too. With `target`: replaces
    **every** occurrence of the exact text. `symbol` wins when both are
    given (Legacy checks `symbol` first).
  - The mutation must change the file; an unchanged result is a
    failure, not a success.
  - Writes the whole file back through `commit()`.
- Output: structured `{bytes_before: int, bytes_after: int}` (Legacy's
  data keys, typed), summary `Applied minimal mutation to <path>`.
- Error cases (Legacy messages, verbatim):
  - `Missing path` — no (or empty) `path`.
  - `Missing replacement` — no `replacement` (an empty string is a
    valid replacement: it deletes the symbol body / target text).
  - `Path not allowed: <path>` — the path escapes the workspace.
  - `Cannot read <path>: <reason>` — the file does not exist or is
    not readable (Legacy's `readFile` throw, surfaced).
  - `Unable to locate symbol body for: <symbol>` — the symbol name is
    not found, or there is no `{` after it, or the braces never
    balance.
  - `Target text not found` — `target` does not occur in the file.
  - `Provide either symbol or target` — neither `symbol` nor `target`
    was given (or both were empty).
  - `No mutation produced` — the replacement equals the text it
    replaces.
- Safety rules: workspace-confined path only; approval before the
  write; no shell, no subprocess; the brace counter is deliberately
  naive (it does not understand strings, comments, or character
  literals containing braces) — exactly as in Legacy.

### 3. `dependency_resolution_engine` — Dependency Resolution Engine

- Legacy description (verbatim): "Resolves the workspace project's
  existing Swift Package dependencies via xcodebuild."
- Capability: `compilation`. Risk: `execution`. Permission: `none`.
  Gate: approval (`terminalApproveChange`) before running xcodebuild
  — `writes: true`.
- Input (Legacy `parametersSchema` verbatim, plus `workspace`):
  `packageURL` (string, required) — "Package URL label for the
  resolution report. The tool resolves the project's existing
  dependencies; it does not add this package." Schema description:
  "Runs xcodebuild -resolvePackageDependencies for the workspace
  project. NOTE: packageURL is a report label only — this tool does
  not add a new package dependency. Runs via an argument vector
  (never a shell string), bounded by a 300s timeout."
- Behaviour (Legacy's `execute`, ported):
  - Locates the user's `.xcworkspace` or `.xcodeproj` at the top level
    of the workspace root (`AssistXcodeProjectResolver.locate`:
    workspace preferred over project; alphabetically-first within one
    kind). No project bundle → failure.
  - Runs `/usr/bin/xcodebuild -project <path> | -workspace <path>
    -resolvePackageDependencies` as a fixed argument vector via
    `terminalRunFixed` (never a shell), working directory = workspace
    root, 300 s timeout. `packageURL` is a report label only: the tool
    resolves the project's **existing** dependencies and never adds a
    package.
  - On macOS only. Legacy's `#else` branch fails on any other OS, and
    so does the port.
- Output: structured `{output: string, package: string, exitCode:
  int}` (Legacy's data keys, typed), summary `Resolved dependencies
  for <packageURL>`. `output` is xcodebuild's stdout followed by its
  stderr.
- Error cases (Legacy messages, verbatim):
  - `Missing packageURL` — no (or empty) `packageURL`.
  - `Dependency resolution requires macOS runtime` — any non-macOS
    platform (Legacy's `#else` branch).
  - `No Xcode project (.xcodeproj/.xcworkspace) found in the workspace
    root; cannot resolve package dependencies.` — no project bundle at
    the workspace root (a bare Swift package folder has no
    `.xcodeproj`, so it fails here too — `swift package resolve` is a
    different tool and is not substituted).
  - `Failed to run xcodebuild: /usr/bin/xcodebuild was not found.` —
    xcodebuild is absent (the port's own check; Legacy would surface
    the runner's launch error instead).
  - `Failed to run xcodebuild: could not launch /usr/bin/xcodebuild.`
    — the process could not start at all.
  - `xcodebuild -resolvePackageDependencies timed out after 300s
    (killed).`
  - `Dependency resolution failed (exit code <n>): <last 1500 chars of
    output>` — non-zero exit.
- Safety rules: fixed argv, never a shell; approval before the run
  (resolving fetches packages over the network and writes into
  DerivedData and the package cache); 300 s timeout, killed on expiry.

### 4. `external_resource_gateway` — External Resource Gateway

- Legacy description (verbatim): "Fetches external APIs and returns
  structured JSON response data."
- Capability: `general`. Risk: `externalSideEffect`. Permission:
  `none`. Gate: none beyond the `writes: true` read-only-policy
  refusal — a GET, but Legacy's risk is `externalSideEffect`, so the
  catalogue table makes it `writes: true`.
- Input (Legacy `parametersSchema` verbatim, plus `workspace`):
  `url` (string, required) — "Fully qualified HTTPS URL to fetch.
  Must return a JSON body. http://, file://, and other schemes are
  rejected." Schema description: "Performs an HTTPS GET against an
  external URL and returns structured JSON response data. HTTPS only;
  non-2xx responses are failures. 30s timeout."
- Behaviour (Legacy's `execute`, ported exactly):
  - HTTPS only, with a host. `http://`, `file://`, and every other
    scheme are rejected — `file://` would read local files (SSRF /
    local-file read) behind what used to be a safeRead label.
  - One GET, 30 s timeout, via `SwiftCodeAssistant.HTTP.send` (the
    codebase's proven one-shot request helper; Legacy used
    `URLSession.shared.data(for:)`, which nothing in this codebase
    uses).
  - A non-2xx status is a failure even with a JSON body: a 404/500
    payload is not the requested resource.
  - The body must be valid JSON; it is returned pretty-printed with
    sorted keys.
- Output: structured `{status_code: int, json: string}` (Legacy's data
  keys, typed), summary `Fetched external resource.`
- Error cases (Legacy messages, verbatim):
  - `Missing or invalid url` — no URL, or not parseable as a URL.
  - `Only HTTPS URLs with a host are allowed (got '<url>').`
  - `Fetch failed: <reason>` — transport failure (DNS, connection,
    TLS, timeout).
  - `Invalid HTTP response` — the response is not HTTP.
  - `HTTP <status> from <url>.` — non-2xx status.
  - `Response was not valid JSON: <reason>.`
- Safety rules: HTTPS-only allow-list (no SSRF to local schemes);
  no credentials are attached; the response is returned as data and
  must never be treated as instructions. No response-size cap in
  Legacy; the port keeps that (the 2 MB / 1 MB caps belong to
  `fetch_documentation`, §5).

### 5. `patch_application_engine` — Patch Application Engine

- Legacy description (verbatim): "Generates and applies line-level
  patches with integrity validation."
- Capability: `fileModification`. Risk: `safeMutation`. Permission:
  `fileSystem`. Gate: `commit()` (approval) — `writes: true`.
- Input (Legacy `parametersSchema` verbatim, plus `workspace`):
  `path` (string, required) — "Workspace-relative path of the file to
  patch."; `original` (string, required) — "Block that must exist
  verbatim in the file."; `updated` (string, required) —
  "Replacement block." Schema description: "Applies a line-level patch
  with integrity validation against the original block."
- Behaviour (Legacy's `execute`, ported exactly):
  - Reads the file. The `original` block must exist verbatim
    (integrity check); otherwise the patch is refused and nothing is
    written.
  - Replaces **every** occurrence of the block (`replacingOccurrences`,
    like Legacy — not just the first).
  - Builds Legacy's naive line-by-line diff (`--- a/<file>`,
    `+++ b/<file>`, then `-old` / `+new` pairs for lines that differ
    at the same index). This is NOT a Myers diff: SwiftCode has no Myers
    engine yet (see the Wave 2 note in `SwiftCodeTools+FileWriting.swift`),
    and Legacy's own diff here is the same naive algorithm.
  - Writes the whole file back through `commit()`. Unlike
    `code_mutation_engine`, an `original` identical to `updated` still
    succeeds (Legacy has no no-op check here).
- Output: structured `{diff: string}` (Legacy's data key), summary
  `Patch applied to <path>`.
- Error cases (Legacy messages, verbatim):
  - `Missing path` — no (or empty) `path`.
  - `Missing patch blocks: original/updated` — either block absent.
  - `Path not allowed: <path>` — the path escapes the workspace.
  - `Cannot read <path>: <reason>` — the file does not exist or is
    not readable.
  - `Patch integrity check failed: original block not found` — the
    `original` block does not occur verbatim.
- Safety rules: workspace-confined path only; approval before the
  write; the integrity check runs before any write, so a failed patch
  never touches the file.

### 6. `fetch_documentation` — Fetch Apple Documentation

- Legacy description (verbatim): "Retrieves real Apple Developer
  documentation: API references (Swift/ObjC), framework guides,
  declarations, availability, and code examples from official Apple
  sources."
- Capability: `general`. Risk: `safeRead`. Permission: `none`. Gate:
  none (`writes: false`, `externalRead` annotations). No workspace is
  needed: documentation comes from developer.apple.com, not from the
  open project.
- Legacy known limitations (verbatim):
  - "Only official Apple Developer documentation
    (developer.apple.com) is reachable."
  - "Symbol resolution probes likely documentation paths; an unusual
    symbol may need its exact documentation URL."
  - "Content reflects Apple's published documentation at fetch time,
    cached up to 24 hours."
- Input (Legacy `parametersSchema` verbatim, plus `workspace`):
  `query` (string) — "Natural-language topic, framework, API symbol,
  or question. Examples: 'SwiftUI View', 'URLSession', 'AppStorage
  property wrapper', 'how to request camera permission'."; `url`
  (string) — "Direct Apple Developer documentation URL, e.g.
  https://developer.apple.com/documentation/swiftui/view.";
  `framework` (string) — "Framework or technology to scope the
  lookup, e.g. 'SwiftUI', 'Foundation', 'AppKit'."; `platform`
  (string) — "Target platform for availability filtering, e.g. 'iOS',
  'macOS', 'watchOS'. Informational: full availability is still
  reported."; `language` (string) — "Preferred declaration language:
  'swift' or 'objc'. Defaults to Swift when both exist.";
  `includeExamples` (boolean) — "Include code examples from the
  documentation. Defaults to true."; `maxResults` (integer) —
  "Maximum documentation pages to return (1-5). Defaults to 3."
  Schema description: "Fetches official Apple Developer
  documentation. Provide query or url (at least one)." No required
  arguments in the schema (at least one of `query` / `url` is required
  by the handler).
- Behaviour — the retrieval pipeline (Legacy's, validated by Legacy
  against live Apple endpoints):
  1. Resolve the request to one or more documentation paths: an
     explicit `developer.apple.com/documentation/...` URL resolves to
     exactly one candidate (locale prefixes like `/de/documentation/`
     are stripped — DocC JSON is locale-independent; anchors are
     stripped); otherwise a natural-language query (+ optional
     framework) probes likely paths. Candidate rules, verbatim from
     Legacy: with a framework, the query being the framework name
     alone fetches the framework root page; a dotted symbol
     (`SwiftUI.View`) maps to its path segments; a symbol within the
     framework maps to `documentation/<framework>/<symbol>`; the
     framework root is always the last candidate. Without a framework,
     dotted queries map to path segments (dropping the last segment as
     a second candidate when there are more than two), and multi-word
     queries map to `documentation/<words>`. A single-token query
     without a framework cannot be resolved to a path reliably and
     fails instead of guessing. At most 4 candidates are probed.
  2. Fetch the structured DocC JSON
     (`https://developer.apple.com/tutorials/data/documentation/<path>.json`)
     — the same payload Apple's own documentation viewer renders.
  3. Fall back to fetching and parsing the HTML page when a DocC
     payload is unavailable (404 on the JSON endpoint, or an
     unparseable payload).
  4. Parse declarations, availability, discussion, examples and
     related links; preserve canonical URLs; mark the retrieval
     method (`docc-json` | `html-fallback`). The canonical URL follows
     JSON redirects (the `/tutorials/data/` prefix and `.json`
     suffix are stripped back to the documentation page).
  5. Return clear, structured results. Unavailable fields are
     reported honestly — signatures, availability and content are
     never fabricated.
- DocC JSON parsing rules (Legacy's `parseDocCJSON`):
  - The payload must have `metadata` or `abstract`, or it is not
    documentation (schema drift guard → HTML fallback).
  - Title: `metadata.navigatorTitle`, else `metadata.fragments`,
    else the first 60 characters of the abstract; an empty title falls
    back to the URL's last path component.
  - Declarations: from `primaryContentSections` entries of kind
    `declarations`; a declaration is kept when its `languages` list is
    empty or contains the requested language or `swift`; the text is
    its `tokens` joined; at most 4. Platforms named by declarations
    are collected as an availability fallback.
  - Discussion: `content` sections' `paragraph` / `heading` / `aside`
    blocks (rich text of `inlineContent`), plus `unorderedList` /
    `orderedList` items as `- <text>` lines; `codeListing` blocks
    become fenced examples (only when `includeExamples`, at most 4).
  - Availability: `metadata.platforms[]` entries as
    `<name> <introducedAt>+` (or just `<name>`); when empty, the
    deduplicated, sorted platforms from the declarations.
  - Related links: `seeAlsoSections` + `relationshipsSections`
    identifiers resolved through the `references` dictionary; only
    `developer.apple.com/documentation` URLs are kept; at most 12.
- HTML fallback rules (Legacy's `fetchHTMLFallback`): title from
  `<title>` (minus ` | Apple Developer Documentation`), description
  from `<meta name="description">` (or `<meta content="...">`), body
  text with `script` / `style` / `head` / `nav` / `header` / `footer`
  dropped, tags stripped, a few entities decoded, whitespace
  collapsed. The discussion is description + body text, capped at
  6,000 characters. A page with an empty title or empty discussion is
  not a page (returns nil → next candidate).
- Rendering (Legacy's `renderResults`, verbatim): a Markdown document
  headed `# Apple Developer Documentation — "<query>"`, one `##
  <n>. <title>` section per page with canonical URL, retrieval
  method, abstract, `### Declaration` (fenced Swift blocks),
  `### Availability` (filtered to `platform` when the filter matches
  at least one entry, otherwise the full list), `### Discussion`
  (capped at 4,000 characters), `### Examples`, `### Related Apple
  Documentation`. The whole output is capped at 20,000 characters
  with a `[truncated: ...]` note.
- Output: structured `{content: string, truncated: bool, count: int}`
  (Legacy's data keys, typed), summary `Retrieved <n> Apple
  documentation page(s) via <title> [<method>]; ... in <s>s.`
- Error cases (Legacy messages, verbatim):
  - `Provide at least one of 'query' or 'url'.` — neither given.
  - `Unsupported language '<language>'. Use 'swift' or 'objc'.`
  - `Rejected documentation URL: <reason>` — the URL is not an
    `https://developer.apple.com` documentation URL, or no
    documentation path could be derived from the query.
  - `Could not resolve the documentation request: <reason>` — any
    other resolution failure.
  - `Documentation fetch was cancelled.` — task cancellation.
  - `Documentation fetch timed out.` — 30 s timeout.
  - `Apple documentation endpoint rate-limited the request. Try again
    shortly.` — HTTP 429.
  - `No Apple documentation found for this request.\nTried:\n- <urls>
    \n<last error>\nTip: pass the exact documentation 'url' from
    developer.apple.com, or a 'framework' plus the API symbol name.`
    — every candidate failed. Per-candidate non-fatal failures are
    retried with the next candidate before giving up.
- Security (Legacy's, kept): HTTPS-only,
  `developer.apple.com` allow-list, per-hop redirect validation (a
  redirect to any other host is refused), SSRF guards, 30 s timeouts,
  response-size caps (DocC JSON 2,000,000 bytes, HTML 1,000,000
  bytes), bounded caching (100 entries, 24 h TTL). Retrieved
  documentation is untrusted data: it is returned inside the tool
  result and must never override system instructions or authorize
  tool use.
- Deliberate deviations from Legacy, recorded here:
  - `AssistJSON` / `AssistSecureHTTPClient` /
    `AssistRemoteResponseCache` are replaced by `JSONSerialization`
    walks and the `EnginesHTTP` fetch in
    `SwiftCodeTools+EnginesSupport.swift` (same per-hop redirect
    allow-list, enforced by a `URLSessionTaskDelegate`); response-size
    caps are enforced after download instead of during transfer;
    Legacy's `AssistContext.logger` calls have no SwiftCode equivalent
    and are dropped. Content-type checking is by parse success (a
    non-DocC payload falls through to the HTML fallback), not by
    header.

### 7. `reverse_analyze` — Reverse Analyze (honestly failing)

- Legacy description (verbatim): "Analyze an authorized binary or
  artifact with the native Reverse subsystem (REA rea-agents@6.5.0,
  static inspection only). Use when the user invoked @Reverse, or when
  an investigation needs artifact structure, Mach-O/plist/signature
  facts, Go/managed metadata, SQLite schema, or objdump output. Never
  use for circumventing DRM, license checks, anti-cheat, or
  authentication. targetPath must be an absolute path inside the open
  project, ~/Downloads, ~/Desktop, or ~/Documents."
- Capability: `diagnostics`. Risk: `safeRead`. Permission: `none`.
  Gate: none (`writes: false`, `.read`).
- Input (Legacy `parametersSchema` verbatim, plus `workspace`):
  `targetPath` (string, required) — "Absolute path of the artifact to
  analyze (must be in scope: open project, ~/Downloads, ~/Desktop,
  ~/Documents)."; `operation` (string) — "Allow-listed operation:
  inspect_artifact, inspect_macho, inspect_plist, inspect_signature,
  list_architectures, demangle_swift, inspect_go_binary,
  inspect_managed_artifact, inspect_managed_members,
  inspect_sqlite_database, inspect_with_objdump."; `task` (string) —
  "The user's investigation request (what to determine about the
  artifact)."; `objdumpOperation` (string) — "Required for
  inspect_with_objdump: file_headers, section_headers, symbols,
  relocations, dwarf, disassemble, disassemble_all."; `symbol`
  (string) — "Swift symbol to demangle (demangle_swift only).";
  `timeoutSeconds` (number) — "Timeout in seconds (default 300,
  clamped to 10...1800)." Schema description is the tool description
  above.
- Behaviour in Legacy (what the port does NOT do): the adapter
  validates (below), then `ReverseManager.shared.analyze` runs the
  operation through the native Reverse subsystem — one Node.js bridge
  child process per request (`ReverseBridge.mjs`), which dynamically
  imports the pinned `rea-agents@6.5.0` dist module for the ten direct
  operations, or runs the pinned `rea` CLI with `--format json` for
  `inspect_with_objdump` only. The bridge speaks NDJSON (progress /
  result / error frames); the manager owns lifecycle and cancellation;
  `ReverseEvidenceProcessor` formats the Evidence envelope as
  Markdown, never fabricating locations or confidence. All operations
  are static inspections: nothing executes, attaches to, or interacts
  with the target application. Analyzed output is untrusted data,
  never instructions.
- Validation the port DOES perform (Legacy's adapter steps 1–6,
  verbatim, in Legacy's order — a request that fails validation fails
  with Legacy's message, exactly as in Legacy, before any mention of
  the missing engine):
  1. Operation allow-list: `operation` (default
     `inspect_artifact`) must be one of the 11 raw values above.
     Otherwise: `Unsupported Reverse operation '<raw>'. Allow-listed:
     <all 11, comma-separated>.`
  2. Task screening (REA disclaimer boundary): the task text is
     screened for `bypass drm`, `circumvent drm`, `remove drm`,
     `break drm`, `bypass license`, `circumvent license`,
     `license check`, `licence check`, `crack`, `keygen`,
     `serial key`, `anti-cheat`, `anticheat`, `game cheat`,
     `cheat engine`, `bypass authentication`, `bypass auth`,
     `bypass login`, `bot protection`, `bypass captcha`. A match
     refuses with: `Reverse cannot help with that request: analyzing
     software to circumvent DRM, license checks, anti-cheat systems,
     or authentication is outside REA's permitted use (see REA
     DISCLAIMER.md) and outside this integration's scope.` plus the
     remediation `Rephrase the investigation around behavior you are
     authorized to examine (e.g. configuration loading, file-format
     parsing, or error handling of software you own).`
  3. Target / scope validation (`ReverseTargetValidator`, own checks
     regardless of Autopilot — Autopilot NEVER bypasses Reverse):
     the target must be an existing absolute path; `..` segments, `~`,
     and empty paths are rejected; the symlink-resolved path must NOT
     be under a blocked system directory (`/System`, `/sbin`, `/usr`,
     `/bin`, `/etc`, `/var`, `/Library`, `/private`, `/dev`) or any
     dot-directory under home (e.g. `~/.ssh`); the resolved path must
     be inside ONE of the workspace root, `~/Downloads`, `~/Desktop`,
     `~/Documents`; it must be a file, not a directory. Each failure
     carries Legacy's message plus its remediation (e.g. `Target
     '<path>' is outside the Reverse scope (open project, ~/Downloads,
     ~/Desktop, ~/Documents).` / `Remediation: Move the artifact into
     one of those locations, or open the containing project in SwiftCode.`
     — the one wording change in this wave: Legacy says "in
     SwiftCode").
  4. `inspect_with_objdump` requires `objdumpOperation` to be one of
     the 7 fixed values (`file_headers`, `section_headers`, `symbols`,
     `relocations`, `dwarf`, `disassemble`, `disassemble_all`;
     default `file_headers`). Otherwise: `Invalid objdumpOperation
     '<raw>'. Fixed choices: <all 7, comma-separated>.`
  5. `symbol` is read only for `demangle_swift`.
  6. `timeoutSeconds` is clamped to 10...1800 (default 300).
- Honest failure (the port, after validation passes): `reverse_analyze
  needs the native Reverse subsystem (Node.js 22, 24, or 26 + the
  pinned rea-agents@6.5.0 package + ReverseBridge.mjs), which SwiftCode's
  MCP host does not have yet; no binary was analyzed.`
- Why it cannot run in SwiftCode yet: the REA subsystem is a Node.js
  bridge process plus a pinned npm package (`rea-agents@6.5.0`) that
  Legacy locates via a settings override, the
  `SWIFTCODE_REVERSE_REA_DIR` environment variable, `node_modules`
  next to the bridge script, or an Application Support copy — none of
  which exists in SwiftCode, and the runtime requirements are explicitly
  never auto-installed (Legacy's README: "Runtime requirements (never
  auto-installed)"). Node.js itself is resolved like the SDK node
  launcher's order (`SWIFTCODE_NODE_PATH`, well-known paths, `PATH`)
  and is likewise absent here.
- Future seam (not implemented): SwiftCode already has a Mach-O parser
  (`SwiftCodeMachO`: `ByteReader`, `MachOImage`, `SymbolTable`). A later
  wave could implement the read-only, host-local operations
  (`list_architectures`, `inspect_macho`) directly on `SwiftCodeMachO`
  without the REA bridge — but that would be a different tool
  contract (no REA Evidence envelope, no `provider`/`confidence`
  fields), so it is recorded here as a possibility, not ported as a
  partial implementation that would silently change the output shape.

### 8. Not ported / honestly-failing — summary

| Tool | Status | Exact prerequisite |
|---|---|---|
| `code_mutation_engine` | Implemented | — (local file op; approval gate) |
| `dependency_resolution_engine` | Implemented (macOS only) | macOS runtime + `/usr/bin/xcodebuild` + a `.xcodeproj` / `.xcworkspace` at the workspace root; fails with Legacy's `Dependency resolution requires macOS runtime` elsewhere |
| `external_resource_gateway` | Implemented | Network access to the HTTPS URL; the URL must return JSON |
| `patch_application_engine` | Implemented | — (local file op; approval gate) |
| `fetch_documentation` | Implemented | Network access to `developer.apple.com` (DocC JSON, HTML fallback) |
| `reverse_analyze` | Honestly failing | The native Reverse subsystem: Node.js 22, 24, or 26 + the pinned `rea-agents@6.5.0` package + `ReverseBridge.mjs` |

No behaviour, credential, or network call is invented for
`reverse_analyze`. Its handler validates every input with Legacy's
messages first, then fails naming the prerequisite above.

### 9. Error cases — summary table

| Tool | Error | Message |
|---|---|---|
| `code_mutation_engine` | missing `path` | `Missing path` |
| `code_mutation_engine` | missing `replacement` | `Missing replacement` |
| `code_mutation_engine` | escaping path | `Path not allowed: <path>` |
| `code_mutation_engine` | unreadable file | `Cannot read <path>: <reason>` |
| `code_mutation_engine` | symbol not found / unbalanced | `Unable to locate symbol body for: <symbol>` |
| `code_mutation_engine` | target absent | `Target text not found` |
| `code_mutation_engine` | neither `symbol` nor `target` | `Provide either symbol or target` |
| `code_mutation_engine` | no change | `No mutation produced` |
| `dependency_resolution_engine` | missing `packageURL` | `Missing packageURL` |
| `dependency_resolution_engine` | non-macOS | `Dependency resolution requires macOS runtime` |
| `dependency_resolution_engine` | no project bundle | `No Xcode project (.xcodeproj/.xcworkspace) found in the workspace root; cannot resolve package dependencies.` |
| `dependency_resolution_engine` | no xcodebuild | `Failed to run xcodebuild: /usr/bin/xcodebuild was not found.` |
| `dependency_resolution_engine` | launch failure | `Failed to run xcodebuild: could not launch /usr/bin/xcodebuild.` |
| `dependency_resolution_engine` | timeout | `xcodebuild -resolvePackageDependencies timed out after 300s (killed).` |
| `dependency_resolution_engine` | non-zero exit | `Dependency resolution failed (exit code <n>): <tail>` |
| `external_resource_gateway` | missing/invalid URL | `Missing or invalid url` |
| `external_resource_gateway` | non-HTTPS scheme | `Only HTTPS URLs with a host are allowed (got '<url>').` |
| `external_resource_gateway` | transport failure | `Fetch failed: <reason>` |
| `external_resource_gateway` | non-HTTP response | `Invalid HTTP response` |
| `external_resource_gateway` | non-2xx status | `HTTP <status> from <url>.` |
| `external_resource_gateway` | non-JSON body | `Response was not valid JSON: <reason>.` |
| `patch_application_engine` | missing `path` | `Missing path` |
| `patch_application_engine` | missing blocks | `Missing patch blocks: original/updated` |
| `patch_application_engine` | escaping path | `Path not allowed: <path>` |
| `patch_application_engine` | unreadable file | `Cannot read <path>: <reason>` |
| `patch_application_engine` | integrity check | `Patch integrity check failed: original block not found` |
| `fetch_documentation` | neither query nor URL | `Provide at least one of 'query' or 'url'.` |
| `fetch_documentation` | bad language | `Unsupported language '<language>'. Use 'swift' or 'objc'.` |
| `fetch_documentation` | rejected URL / path | `Rejected documentation URL: <reason>` |
| `fetch_documentation` | resolution failure | `Could not resolve the documentation request: <reason>` |
| `fetch_documentation` | cancelled | `Documentation fetch was cancelled.` |
| `fetch_documentation` | timeout | `Documentation fetch timed out.` |
| `fetch_documentation` | rate-limited | `Apple documentation endpoint rate-limited the request. Try again shortly.` |
| `fetch_documentation` | nothing found | `No Apple documentation found for this request. …` (with tried URLs + tip) |
| `reverse_analyze` | unknown operation | `Unsupported Reverse operation '<raw>'. Allow-listed: …` |
| `reverse_analyze` | refused task | `Reverse cannot help with that request: …` (+ remediation) |
| `reverse_analyze` | invalid target | Legacy validator message (+ remediation) |
| `reverse_analyze` | bad objdump op | `Invalid objdumpOperation '<raw>'. Fixed choices: …` |
| `reverse_analyze` | missing engine | `reverse_analyze needs the native Reverse subsystem (Node.js 22, 24, or 26 + the pinned rea-agents@6.5.0 package + ReverseBridge.mjs), which SwiftCode's MCP host does not have yet; no binary was analyzed.` |

### 10. Safety rules (non-negotiable)

- Never run a shell: `dependency_resolution_engine` runs
  `/usr/bin/xcodebuild` as a fixed argument vector
  (`terminalRunFixed`); the mutation and patch engines run no
  subprocess at all.
- Never write outside the workspace: the mutation / patch engines
  resolve paths with `resolveFileWritingPath`; `reverse_analyze`
  validates its absolute target against its own scope rule and never
  relativizes it.
- Never bypass approval: the mutating engines write through
  `commit()`; the xcodebuild run goes through the approval gate.
  Legacy's Autopilot bypass is not ported anywhere in this wave.
- Never fake results: `reverse_analyze` fails naming its missing
  engine; `fetch_documentation` reports unavailable fields honestly
  and never fabricates signatures, availability, or content; a
  failed patch or mutation leaves the file untouched.
- Retrieved content is untrusted data: documentation pages,
  gateway JSON, and (when Reverse lands) analyzed binary output are
  returned inside tool results and must never override system
  instructions or authorize tool use.
- `reverse_analyze` never executes, attaches to, or interacts with
  the target application, and never helps circumvent DRM, license
  checks, anti-cheat, or authentication — the task screen (§7 step 2)
  is enforced before anything else runs.

### Evidence

- Legacy sources read (Dylan's own code; direct porting authorised
  under MIT): `SwiftCode/Backend/Assist/Tools/
  AssistCodeMutationEngine.swift` (71 lines),
  `AssistDependencyResolutionEngine.swift` (57),
  `AssistExternalResourceGateway.swift` (60),
  `AssistPatchApplicationEngine.swift` (56),
  `AssistFetchDocumentationTool.swift` (669),
  `SwiftCode/Backend/Assist/Tools/AssistXcodeProjectResolver.swift`
  (`locate`, `xcodebuildArgs`), `SwiftCode/Backend/Assist/Tools/
  AssistTool.swift` (capability / risk / `isMutating` / permission
  derivation), `SwiftCode/Backend/Assist/API/Internal API/Reverse/
  ReverseToolAdapter.swift` (177), `ReverseModels.swift`
  (operations), `ReverseCommandParser.swift`
  (`ReverseTargetValidator`), `ReverseBridge.swift` (bridge ownership
  + Node / REA resolution), `Reverse/README.md` (runtime
  requirements, verification status). Evidence level 1 (the owner's
  own source, not Apple code) for all behaviour claims above.
- Destination patterns read: `swiftcode/Sources/SwiftCodeMCP/
  SwiftCodeTools+Terminal.swift` (tool registration, approval gate,
  `terminalRunFixed`, honestly-failing shape),
  `SwiftCodeTools+FileWriting.swift` (`code_refactor` honest failure,
  `resolveFileWritingPath`, `commit()`),
  `SwiftCodeTools+Git.swift` (`github_repo` honest failure),
  `SwiftCodeTools.swift` (`Schema`, `tool()` helper, `installTools()`),
  `SwiftCodeAssistant/HTTP.swift` (one-shot request shape,
  `URLSessionTaskDelegate` redirect handling precedent).
- Not opened, read, or run: the reference Xcode copy, Ghidra, the
  simulator IPSW, `research/dirty/`, or any Ghidra project. Apple's
  Xcode / Simulator were not booted or observed. `fetch_documentation`
  behaviour comes from Legacy's own documented pipeline (validated by
  Legacy against live Apple endpoints); no live fetch was performed
  from this environment to write this spec.

