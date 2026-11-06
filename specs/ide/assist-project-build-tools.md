# Assist project / Xcode / build tools — behaviour (Wave 7)

Ycode modules: `YcodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 65 Legacy Assist Project/Xcode/build
tools ported in Wave 7 — the last family of the 291-tool Assist registry: build
& run (13, Part A), project model & pbxproj (19, Part B), SPM / dependencies /
docs (13, Part C), signing / entitlements / plist (11, Part D), and asset catalogs
/ localization (9, Part E). The catalogue (`assist-tool-catalogue.md`, §250–§320)
is the single source of truth for each tool's ID, title, description, input schema,
output shape, capability, risk level, permission, and read/write classification; this
spec is the single source of truth for how the tools behave.

## Part A — Build & run

**Slice:** the 13 Legacy Assist Project/Xcode/build tools — `project_build`,
`project_test`, `project_clean`, `project_archive`, `build_log_analyze`,
`build_system_detect`, `build_configuration_list`, `build_settings_diff`,
`build_phase_scripts_list`, `xcresult_parser`, `derived_data_locate`,
`xcode_toolchain_info`, `xcode_device_destination_finder` — ported onto
Ycode's Assist host (`YcodeMCP`, `ycode/Sources/YcodeMCP/
YcodeTools+ProjectBuild.swift`, array `projectBuildTools`).

**Behaviour sources (read directly):** Legacy
`SwiftCode/Backend/Assist/Tools/AssistBuildProjectTool.swift`
(`project_build` + `generate_xcodeproj`, the latter NOT in this slice),
`AssistTestRunnerTool.swift`, `AssistProjectCleanTool.swift`,
`AssistProjectArchiveTool.swift`, `AssistBuildLogAnalyzeTool.swift`,
`AssistBuildSystemDetectTool.swift`, `AssistBuildConfigurationListTool.swift`,
`AssistBuildSettingsDiffTool.swift`, `AssistBuildPhaseScriptsListTool.swift`,
`AssistXCResultParserTool.swift`, `AssistDerivedDataLocateTool.swift`,
`AssistXcodeToolchainInfoTool.swift`, `AssistXcodeDeviceDestinationTool.swift`
(Dylan's own code, ported under MIT), plus Legacy's
`AssistToolRegistry.swift` alias table (for §1.3) and
`AssistToolSharedHelpers.swift` (`AssistTextFormat.truncated`,
`AssistWorkspaceScan.findPbxproj` / `fileSize`).

**Clean-room note:** implementation in `ycode/` reads this spec, public
docs, and Dylan's own Legacy code (direct porting authorised under MIT).
No reference Xcode copy, Ghidra, simulator IPSW, `research/dirty/`, or
Apple Xcode/Simulator observation was used.

## 1. Conventions shared by the slice

### 1.1 Schemas are Legacy's verbatim, plus `workspace`

Every tool's input schema is Legacy's `parametersSchema` verbatim, plus
the `workspace` parameter every Ycode tool carries. Legacy's
parameter-name aliases are NOT supported: Ycode's argument validation
rejects unknown arguments before the handler runs.

### 1.2 Structured data keeps Legacy's keys, typed

Structured data keeps Legacy's data keys, with typed JSON values
(integers, booleans) the way Ycode's other tools do — Legacy's
string-only map is not reproduced. Tools whose Legacy result carries
no data (`xcresult_parser`, `xcode_device_destination_finder`) return
a plain text result instead. Legacy's `suggestedNextActions`,
`diagnostics`, `duration` and `exitCode` envelope fields are dropped:
`MCPToolResult` has no such fields (same as Waves 1–6).

### 1.3 Registry aliases (coordinator-owned)

Legacy's `AssistToolRegistry.toolAliases` maps these names onto this
slice's IDs. They live in `MCPServer.toolAliases`, which the
coordinator owns — they are not added in the implementation file:

| Alias | Target |
|---|---|
| `build`, `build_project`, `run_build`, `xcodebuild` | `project_build` |
| `test`, `run_tests` | `project_test` |
| `xcresult` | `xcresult_parser` |
| `device_destinations` | `xcode_device_destination_finder` |

**Collision warning for the coordinator:** `build` → `project_build`
and `test` → `project_test` MUST NOT be added as aliases: they would
collide with Ycode's existing native `build` and `test` tools (the
same reason Wave 3 deliberately did not alias `search` →
`search_text`). `build_project`, `run_build`, `xcodebuild`,
`run_tests`, `xcresult` and `device_destinations` have no Ycode
collision and may be added. `project_clean`, `project_archive`,
`build_log_analyze`, `build_system_detect`, `build_configuration_list`,
`build_settings_diff`, `build_phase_scripts_list`, `derived_data_locate`
and `xcode_toolchain_info` have no Legacy aliases.

### 1.4 The build/test seam — no parallel build system, no direct xcodebuild for build/test/clean

`project_build`, `project_test` and the `derivedData` scope of
`project_clean` run through the session — `s.build(.build)`,
`s.runTests()`, `s.build(.clean)` — the same seam Ycode's native
`build` / `test` / `clean` tools and Wave 6's `test_run_single` /
`compiler_diagnostics_engine` use (ycodebuild / SwiftPM for packages,
Ycode's Xcodebuild engine for Xcode projects). No second runner, no
directly spawned `xcodebuild` for these three, never a shell.
Execution always runs the real command and reports its actual output
— no result is ever invented. On a machine with no Swift toolchain
and no Xcode (this Linux environment), these tools fail honestly
with the session's own failure, and the tests gate real-build
assertions on `canBuildPackages` exactly like Wave 6's.

`project_archive` is the one exception: Ycode's build seam has no
archive action (`BuildRequest.Action` is build/clean/test/analyze/
build-for-testing), so it runs the real `/usr/bin/xcodebuild archive`
through the fixed-argv runner (`terminalRunFixed`, off the main
actor), never a shell — the same runner Wave 4's `performance_benchmark`
and Wave 6's `test_coverage_reporter` use. The same runner is used
for `xcode_toolchain_info` (`xcodebuild -version` / `-showsdks`)
and, via `runXcrun`, for `xcresult_parser` (`xcrun xcresulttool`)
and `xcode_device_destination_finder` (`xcrun simctl`).

### 1.5 Paths

Paths resolve through the session resolvers (`resolveFileReadingPath`,
`resolve`, `fileReadingRelativePath`) and never escape the workspace,
with the two deliberate, read-only exceptions documented per tool
below: `xcresult_parser` searches the user's own DerivedData for
`.xcresult` bundles (its Legacy default) and accepts an explicit
absolute bundle path as-is; `derived_data_locate` lists the user's
own DerivedData directory. One resolver tolerance is kept from Wave 6:
a `..` that stays inside the workspace resolves (the session
resolver's rule) where Legacy's per-tool resolvers rejected any `..`
as text (`project_archive`, `build_log_analyze`,
`build_settings_diff`).

### 1.6 Approval gating: one write tool

Exactly one tool in this slice writes: `project_clean`
(`writes: true`, `destructive: true`, Legacy `potentiallyDestructive`).
Its `build/` removal goes through an explicit `MCPChange` +
`approve()` per the approval model (`assist-approval-model.md` §6.2),
using the same `approveFileWritingChange` / `noteFileWritingChanged`
helpers as Wave 2's `dir_delete`, with a plain summary
(`Delete build/ directory and all its contents permanently`). The
`derivedData` scope runs the session clean, which is an execution,
not a file write. In `readOnly` mode the whole call is refused in
`run()` before the handler, exactly as the approval model specifies —
including when the scope would only remove a `build/` that does not
exist. There is no Autopilot bypass.

`project_archive` is `writes: false` with `execution` annotations
(Legacy `riskLevel` `.execution`): it creates the `.xcarchive` as
its build product, the same way the `build` tool creates build
products without being a write tool. Its parent-directory creation
is part of that execution, not a separately approved write.

`project_build` / `project_test` are `writes: false` (`execution`
for `project_test`, `readOnly: false, idempotent: true` for
`project_build`, matching Ycode's native `build` tool). Legacy's
`project_build` is approval-exempt by design in Legacy (it runs
xcodebuild directly so it never triggers the terminal approval
prompt); the Ycode port keeps the exemption in the only form Ycode
has — it is not a write tool, so the write policy never gates it —
and it does not route through `use_terminal`.

### 1.7 Overlap with Ycode-native tools (no duplication)

Ycode already has `build`, `test`, `clean` and `build_log`
(`YcodeTools+Build.swift`) and `simulator_list` (with its Apple
`simctl` section). This slice does NOT duplicate them: `project_build`
/ `project_test` / `project_clean` are the Legacy-named forms of the
same operations, routed through the same session seam with Legacy's
schemas, messages and data keys; `build_log_analyze` parses a log
*file* (the native `build_log` shows the session's in-memory log);
`xcode_device_destination_finder` is Legacy's simctl-only listing
with a platform filter, while `simulator_list` is Ycode's combined
Ycode-Simulator + Apple listing.

### 1.8 No `generate_xcodeproj`

`AssistBuildProjectTool.swift` also contains
`AssistGenerateXcodeprojTool` (`generate_xcodeproj`, XcodeGen
generation with automatic Homebrew install). It is NOT in this
slice's 13 IDs and is not ported here; it belongs to a later slice
if the coordinator assigns it. (It also auto-installs software, which
needs its own approval story.)

## 2. `project_build` — Build Project

- Legacy: `AssistBuildProjectTool`, capability `.compilation`,
  risk `.execution`. Description: "Builds the user's Xcode project
  with xcodebuild, executed directly in the background without
  requiring terminal approval."
- Schema: `projectPath` ("Workspace-relative path to the .xcodeproj
  or .xcworkspace to build. Defaults to the project found in the
  workspace root."), `scheme` ("The scheme to build. Defaults to the
  project's first listed scheme."), `configuration` ("Build
  configuration (Debug or Release). Default is Debug."),
  `destination` ("xcodebuild destination specifier. Default is
  'platform=macOS'."). No required parameters.
- Behaviour: `configuration` defaults to `Debug` (blank → `Debug`);
  `destination` defaults to `platform=macOS` (blank → default).
  `projectPath`, when given, must name the already-open workspace
  (the `compiler_diagnostics_engine` rule: the path must equal the
  session model's URL or its folder, else
  `project "<path>" is not the open workspace; open it with
  workspace_open first.`); when omitted the open workspace is built.
  Scheme/destination go through `applyScheme`, so `destination` is
  a Ycode destination name/id/specifier (Legacy's default
  `platform=macOS` is the specifier of the "My Mac" destination and
  matches as-is) and an unknown scheme/destination fails with
  `applyScheme`'s message. The build runs through the session
  (`s.build(.build)`), with progress reported. Success and failure
  are both returned as a structured result, not a thrown error —
  the Ycode `build` tool's shape: `status` `"Passed"` / `"Failed"`,
  the summary naming project / scheme / configuration / duration,
  the first errors/warnings listed, and the log tail when the build
  fails with no errors.
- Structured data (Legacy keys, typed): `project` (workspace
  display name), `scheme`, `configuration`, `status`, `duration`
  (`"%.2fs"` string, as in Legacy), `error_count` (int),
  `warning_count` (int), `marker` (`"BUILD SUCCEEDED"` /
  `"BUILD FAILED"`, derived from the build status — the session
  build has no xcodebuild stdout marker to read).
- Error cases: no workspace open (session error); `projectPath`
  naming another project; unknown scheme/destination
  (`applyScheme` message).
- Deviations from Legacy, recorded here:
  - No `/usr/bin/xcodebuild` is spawned directly and no
    `-scheme` / `-configuration` / `-destination` argv is built:
    the session build is used, so the scheme's own build
    configuration is honoured and the `configuration` argument is
    accepted but does not override it. (The session's
    `buildRequest` takes its configuration from the scheme; there
    is no per-call configuration override in the Ycode seam.)
  - Legacy found the project by scanning the workspace root for
    `.xcodeproj` / `.xcworkspace`; the port builds the already-open
    workspace, as `compiler_diagnostics_engine` does.
  - Legacy's result is a success/failure `AssistToolResult` with
    `exitCode` and `suggestedNextActions`; the port returns the
    Ycode `build` tool's structured result with `status`, and drops
    the envelope fields (see §1.2).
  - No `BuildOutputAccumulator` (the `** BUILD SUCCEEDED **` /
    `** BUILD FAILED **` line parser) is ported: the session
    build reports issues directly, so there is no xcodebuild
    stdout to accumulate. Error/warning counting is the session's
    issue list, not a `: error:` / `: warning:` line scan.

## 3. `project_test` — Run Tests

- Legacy: `AssistTestRunnerTool`, capability `.testing`,
  risk `.execution`. Description: "Executes test suites and test
  plans using xcodebuild test with proper platform targeting."
- Schema: `scheme` ("The scheme to test. Defaults to the project's
  first listed scheme."), `testPlan` ("Optional name of the test plan
  to execute."). No required parameters.
- Behaviour: scheme goes through `applyScheme` (destination: none —
  Legacy's schema has no destination parameter). `testPlan`, when
  given, must be one of the session's test plans, else
  `the scheme has no test plan "<plan>"` (the `test` tool's message,
  listing the plans when there are any). Tests run through the
  session (`s.runTests()`), with progress reported. The result is a
  structured result with `status` `"Passed"` / `"Failed"`, never a
  thrown error for test failures: the summary is
  `Tests Passed (<duration>):` / `Tests Failed (<duration>):`
  followed by the per-test outcome lines and, on failure, the first
  failures. `diagnostics_count` is the session's displayed-issue
  count after the run.
- Structured data (Legacy keys, typed): `status`, `duration`
  (`"%.2fs"` string), `diagnostics_count` (int).
- Error cases: no workspace open; unknown scheme; unknown test plan.
- Deviations from Legacy, recorded here:
  - Legacy delegates to `AssistVerificationPipeline` (which runs
    `xcodebuild test`); the port runs the session test runner
    (ycodebuild / SwiftPM), the same path the `test` tool and
    `test_run_single` use. No `xcodebuild test` is spawned and no
    `-only-testing:` / test-plan argv is built.
  - Legacy's failure output is the pipeline's diagnostic summary;
    the port's is the session outcomes + displayed issues.
  - Legacy's `suggestedNextActions` / `exitCode` envelope fields
    are dropped (see §1.2).

## 4. `project_clean` — Clean Project

- Legacy: `AssistProjectCleanTool`, capability `.compilation`,
  risk `.potentiallyDestructive`. Description: "Cleans the project:
  removes the workspace build directory and/or runs xcodebuild clean.
  Requires explicit confirmation."
- Schema: `scope` ("build, derivedData, or both. Default: build.
  build removes workspaceRoot/build only; derivedData runs xcodebuild
  clean."), `confirm` ("Must be \"true\" to proceed. Any other value
  fails without doing anything."). Required: `confirm`.
- Behaviour: `confirm` must be `"true"` (case-insensitive; a JSON
  boolean `true` is also accepted) or the call fails with
  `Clean requires confirm="true". No changes were made.` and nothing
  happens. `scope` defaults to `build`; anything other than `build`,
  `derivedData` or `both` fails with
  `Invalid scope '<scope>'. Expected build, derivedData, or both.`
  Scope `build` / `both` removes `<workspace>/build` — after an
  explicit `MCPChange` + `approve()` (summary
  `Delete build/ directory and all its contents permanently`); if
  `build/` does not exist the note `build/ did not exist.` is kept
  instead of a removal. Scope `derivedData` / `both` runs the
  session clean (`s.build(.clean)`); a failed clean fails the call
  with the build's error summary. Build-dir removal happens first,
  then the session clean — so when `both` is requested and the clean
  fails, the removal has already happened (Legacy's wording for the
  missing-project case is kept in spirit: the failure names what
  already completed). The summary is `Cleaned: <removed>. <notes>`
  or `Nothing to clean. <notes>`.
- Structured data (Legacy keys, typed): `removed` (comma-joined
  string — `"build/"` and/or `"xcodebuild clean"` as in Legacy, the
  latter naming the session clean), `scope` (string).
- Error cases: `confirm` not `"true"`; invalid scope; a
  `build/` removal failing (`Failed to remove build directory:
  <detail>`); a failed session clean.
- Deviations from Legacy, recorded here:
  - Legacy's `derivedData` scope ran `xcodebuild clean` against
    the project located at the workspace top level; the port runs
    the session clean, which removes the scheme's build products
    through the Ycode build seam (no `xcodebuild clean` argv is
    built). The `removed` value still says `"xcodebuild clean"`,
    as in Legacy.
  - Legacy's `derivedData` scope failed when no `.xcodeproj` /
    `.xcworkspace` was at the top level; the port fails only when
    the session clean itself fails (the open workspace is the
    project by definition).
  - The `build/` removal is additionally gated by the write policy
    (`writes: true` + `approve()`); Legacy relied on `confirm`
    plus its permissions layer, which Autopilot bypassed. Both
    gates apply here: `confirm="true"` AND the policy approval.
  - Legacy's `runProcess` helper (blocking `Process` + merged
    pipe) is not ported: the session clean and the fixed-argv
    runner replace it.

## 5. `project_archive` — Archive Project

- Legacy: `AssistProjectArchiveTool`, capability `.compilation`,
  risk `.execution`. Description: "Archives the user's Xcode project
  with xcodebuild archive and verifies the .xcarchive exists."
- Schema: `scheme` ("Scheme to archive. Required."),
  `configuration` ("Build configuration, e.g. Release or Debug.
  Default: Release."), `archivePath` ("Workspace-relative destination
  path for the .xcarchive. Required, must stay inside the
  workspace."), `exportOptionsPlist` ("Optional workspace-relative
  path to an ExportOptions.plist (not used by archive; reserved for
  export steps)."). Required: `scheme`, `archivePath`.
- Behaviour: missing/blank `scheme` → `Missing required parameter:
  scheme`; missing/blank `archivePath` →
  `Missing required parameter: archivePath`; blank `configuration`
  → `Missing required parameter: configuration` (default
  `Release`). A non-empty `exportOptionsPlist` must exist inside
  the workspace, else
  `exportOptionsPlist '<path>' not found inside the workspace.`
  (it is validated only — never passed to xcodebuild, as in Legacy).
  `archivePath` must resolve inside the workspace and end in
  `.xcarchive`, else `archivePath must end in .xcarchive.` The open
  workspace must be an Xcode project or workspace
  (`model.kind` `.project` / `.workspace`); a SwiftPM package fails
  with `No .xcodeproj or .xcworkspace found at the top level of the
  workspace.` The archive parent directory is created, then the real
  `xcodebuild` runs with fixed argv —
  `[-project|-workspace, <path>, -scheme, <scheme>, -configuration,
  <configuration>, -archivePath, <archive>, archive]` — in the
  workspace root, bounded at 900 s, never a shell. A non-zero exit
  fails with `xcodebuild archive failed (exit <n>): <output tail>`.
  Afterwards the `.xcarchive` must exist as a directory, else
  `Verification failed: .xcarchive not found at '<archivePath>'
  after a successful xcodebuild run.` Success is
  `Archived scheme '<scheme>' to '<archivePath>' (exit 0).`
- Structured data (Legacy keys, typed): `archivePath`, `scheme`,
  `configuration`, `exitCode` (int).
- Error cases: missing/blank required parameters; `exportOptionsPlist`
  not found; `archivePath` outside the workspace or not ending in
  `.xcarchive`; a SwiftPM workspace; missing `xcodebuild`
  (`xcodebuild not found at /usr/bin/xcodebuild. Install Xcode
  command line tools first.`); a failed or timed-out archive run
  (`Failed to run xcodebuild archive: <detail>` for a launch
  failure, `xcodebuild archive timed out after 900s.` for a timeout);
  a missing archive after a successful run.
- Deviations from Legacy, recorded here:
  - Legacy located the project by scanning the workspace top level
    for `.xcodeproj` / `.xcworkspace`; the port uses the open
    workspace's model (`model.url` is the bundle path).
  - Legacy waited unboundedly and merged stdout+stderr into one
    pipe; the port bounds the run at 900 s and keeps the streams
    separate (the failure tail is stdout + stderr).
  - Legacy's `runProcess` helper is not ported; the fixed-argv
    runner (`terminalRunFixed`) replaces it.

## 6. `build_log_analyze` — Build Log Analyze

- Legacy: `AssistBuildLogAnalyzeTool`, capability `.diagnostics`,
  risk `.safeRead`. Description: "Parses an xcodebuild/swift-build
  log file: extracts errors, warnings, build result, and timing
  summary."
- Schema: `path` ("Workspace-relative path to the build log file.").
  Required: `path`.
- Behaviour: missing/blank `path` →
  `Missing required parameter: path`; an unreadable path →
  `Cannot read build log at: <path>`. Lines are scanned for
  `** BUILD FAILED **` (result `failed`), `** BUILD SUCCEEDED **`
  (result `succeeded`), `: error:` (error line) and `: warning:`
  (warning line); a line carrying both markers counts as an error
  only (Legacy's `else if`). Error/warning lines are trimmed,
  truncated to 300 characters, and de-duplicated preserving first
  order (Legacy's `NSOrderedSet`). The summary is
  `Build log analysis for <path>:` / `- Result: <result>` /
  `- Errors: <n>` / `- Warnings: <n>`, then up to 20 `  ERROR: <line>`
  lines (with `  … [truncated: showing 20 of <n>]` when there are
  more) and up to 10 `  WARNING: <line>` lines (same truncation note
  at 10). No result marker → result `unknown`.
- Structured data (Legacy keys, typed): `result` (string),
  `errorCount` (int), `warningCount` (int).
- Error cases: missing `path`; unreadable log file.
- Deviations: none in behaviour. (The resolver is Ycode's
  `resolveFileReadingPath` rather than Legacy's
  `AssistWorkspacePaths.resolve`; a `..` that stays inside the
  workspace resolves, where Legacy rejected any `..` as text.)

## 7. `build_system_detect` — Build System Detect

- Legacy: `AssistBuildSystemDetectTool`, capability
  `.repositoryDiscovery`, risk `.safeRead`. Description: "Detects the
  build systems in use: .xcworkspace/.xcodeproj, SwiftPM, CocoaPods,
  Carthage, Tuist, xcodegen, Bazel, CMake." No parameters.
- Behaviour: checks the workspace root, in Legacy's order, for:
  `.xcworkspace`, `.xcodeproj`, `Package.swift` (SwiftPM), `Podfile`
  (CocoaPods), `Cartfile` (Carthage), `Project.swift` (Tuist),
  `project.yml` (xcodegen), `BUILD` (Bazel), `CMakeLists.txt`
  (CMake), `Makefile` (Make). Each hit adds a line
  `- <system>: <name>`. Nothing found → success with
  `No recognized build system files found in the workspace root.`
  and count 0.
- Structured data: `count` (int).
- **Deviation — Legacy's Xcode-project check is broken, and the
  port fixes it:** Legacy's check list is
  `[("xcworkspace", ".xcworkspace"), ("xcodeproj", ".xcodeproj"),
  ...]` and it appends the first element to the root — so it looks
  for entries literally named `xcworkspace` / `xcodeproj`, which a
  real `Foo.xcworkspace` / `Foo.xcodeproj` bundle never is. A
  verbatim port would report "no build system" for every real Xcode
  project. The port instead counts any root entry whose extension
  is `xcworkspace` / `xcodeproj` and reports the bundle's name
  (`- .xcworkspace: Foo.xcworkspace`). The eight file markers are
  unchanged (a non-directory entry with that exact name at the
  root; Legacy's directory rule — a directory only counts when the
  marker name starts with `.` — is preserved in effect, since none
  of the markers starts with `.`).

## 8. `build_configuration_list` — Build Configuration List

- Legacy: `AssistBuildConfigurationListTool`, capability
  `.compilation`, risk `.safeRead`. Description: "Lists build
  configurations (Debug/Release/custom) for the project and each
  target from the .pbxproj." No parameters.
- Behaviour: finds the first `.pbxproj` under the workspace root
  (Legacy's `AssistWorkspaceScan.findPbxproj`, same rule as Ycode's
  `reviewDocsFindPbxproj`); none → `No .pbxproj found in the
  workspace.` Each `XCConfigurationList` block is matched by
  Legacy's regex `([0-9A-F]{24}) /\* Build configuration list for
  (PBXProject|PBXNativeTarget) "([^"]+)" \*/ = \{\s*isa =
  XCConfigurationList;.*?buildConfigurations = \((.*?)\);`
  (dot-matches-line-separators), configuration IDs are resolved
  through Legacy's second regex
  `([0-9A-F]{24}) /\* ([^*]+?) \*/ = \{\s*isa =
  XCBuildConfiguration;`, and one line per owner is emitted:
  `- <owner>: <names, sorted, comma-joined>` (or `(none parsed)`).
  No configuration lists parsed →
  `No configuration lists parsed from the pbxproj.`
- Structured data (Legacy keys, typed): `ownerCount` (int),
  `configurations` (string — the distinct configuration names,
  sorted, comma-joined, as in Legacy).
- Error cases: no `.pbxproj`; unreadable `.pbxproj`; no
  configuration lists parsed.
- Deviations: none in behaviour. (The regexes are pbxproj format
  patterns — interop identifiers — reproduced verbatim.)

## 9. `build_settings_diff` — Build Settings Diff

- Legacy: `AssistBuildSettingsDiffTool`, capability `.compilation`,
  risk `.safeRead`. Description: "Diffs two .xcconfig files
  key-by-key, reporting added, removed, and changed build settings."
- Schema: `oldPath` ("Workspace-relative path to the baseline
  .xcconfig."), `newPath` ("Workspace-relative path to the new
  .xcconfig."). Required: `oldPath`, `newPath`.
- Behaviour: both missing/blank →
  `Missing required parameters: oldPath and newPath`. Each file is
  parsed line by line: blank lines and lines starting with `//` or
  `#` are skipped; the rest split on the first `=` into key/value,
  both trimmed; a line with no `=` is ignored. An unreadable file →
  `Cannot parse xcconfig at: <path>` (naming the file that failed).
  Added = keys only in new, removed = keys only in old, changed =
  keys in both with different values; all sorted. No differences →
  success with `Build settings are identical.` Otherwise
  `Build settings diff (<old> -> <new>):` followed by
  `- ADDED: <key> = <value>`, `- REMOVED: <key> (was: <value>)`,
  `- CHANGED: <key>: '<old>' -> '<new>'` lines, added then removed
  then changed.
- Structured data (Legacy keys, typed): `added` (int), `removed`
  (int), `changed` (int).
- Error cases: missing parameters; either file unreadable.
- Deviations: none in behaviour. (Resolver tolerance as §6.)

## 10. `build_phase_scripts_list` — Build Phase Scripts List

- Legacy: `AssistBuildPhaseScriptsListTool`, capability
  `.compilation`, risk `.safeRead`. Description: "Lists Run Script
  build phases from the .pbxproj with their names and script bodies
  (truncated)." No parameters.
- Behaviour: finds the first `.pbxproj` under the workspace root;
  none → `No .pbxproj found in the workspace.` Run Script phases
  are matched by Legacy's regex
  `/\* (.+?) \*/ = \{\s*isa = PBXShellScriptBuildPhase;.*?name =
  (.+?);.*?shellScript = "(.*?)";`
  (dot-matches-line-separators). No matches → success with
  `No Run Script build phases found.` and count 0. Each match
  emits `- <comment> (phase: <name>):` and a fenced block
  ```` ```sh ```` / `<preview>` / ```` ``` ```` with ` [truncated]`
  appended when the script was cut. The name has surrounding
  quotes stripped; the script body has `\\n` sequences replaced
  with real newlines first, then Legacy's
  `AssistTextFormat.truncated(script, limit: 600, label:
  "script truncated")` — first 600 characters plus
  `\n… [script truncated: showing first 600 of <n> characters]`
  when longer.
- Structured data: `count` (int).
- Error cases: no `.pbxproj`; unreadable `.pbxproj`.
- Deviations: none in behaviour.

## 11. `xcresult_parser` — XCResult Bundle Parser

- Legacy: `AssistXCResultParserTool`, capability `.diagnostics`,
  risk `.safeRead`. Description: "Locates and parses .xcresult
  bundles to extract test failures, warnings, and compilation
  diagnostics."
- Schema: `bundlePath` ("Optional specific path to an .xcresult
  bundle. If omitted, the latest result bundle in DerivedData is
  used."). No required parameters.
- Behaviour: an explicit `bundlePath` is used as-is when absolute
  and it exists, or resolved against the workspace root when
  relative and it exists; a non-existent explicit path falls
  through to the DerivedData search (Legacy behaviour). Otherwise
  the newest `.xcresult` bundle under
  `~/Library/Developer/Xcode/DerivedData` by modification date is
  used. No bundle found → success with
  `No .xcresult bundle found. Run a build or test suite first.`
  The bundle is read with the real
  `xcrun xcresulttool get --format json --path <bundle>` (fixed
  argv, 120 s bound). Non-JSON or empty output → success with
  `Parsed .xcresult at <name>, but output is non-JSON or bundle is
  empty.` Otherwise the report is
  `### XCResult Summary (<name>):` followed by
  `#### Errors (<n>):` with up to 10 `- ❌ <message>` lines from
  `issues.errorSummaries._values[].message._value`, and
  `#### Warnings (<n>):` with up to 10 `- ⚠️ <message>` lines from
  `issues.warningSummaries._values[].message._value`; with no
  `issues` key the report ends with
  `No compile errors or test failure summaries recorded in bundle.`
- No structured data (Legacy returns none) — plain text result.
- Error cases: `xcrun` missing or failing to launch
  (`Failed to parse .xcresult via xcresulttool: <detail>`);
  unparseable `simctl`-style JSON is not an error here — a
  non-JSON `xcresulttool` output is the success message above.
- Deviations from Legacy, recorded here:
  - Legacy merged stdout+stderr into one pipe and parsed the
    merge; the port parses stdout only (errors still surface as
    the non-JSON success message when `xcresulttool` fails).
  - Legacy waited unboundedly; the port bounds the run at 120 s.
  - Legacy's `Process` + merged pipe is replaced by the
    fixed-argv runner (`runXcrun`).

## 12. `derived_data_locate` — DerivedData Locate

- Legacy: `AssistDerivedDataLocateTool`, capability `.compilation`,
  risk `.safeRead`. Description: "Locates the project's DerivedData
  directories under ~/Library/Developer/Xcode/DerivedData with
  sizes."
- Schema: `nameFilter` ("Optional substring filter on the
  DerivedData folder name."). No required parameters.
- Behaviour: lists `~/Library/Developer/Xcode/DerivedData`; the
  directory missing → failure
  `DerivedData directory not found at <path>.` Each entry is sized
  by a recursive enumeration summing file sizes (Legacy's
  `AssistWorkspaceScan.fileSize`), stopping early once an entry
  exceeds 20 GB. Entries are filtered by case-insensitive substring
  when `nameFilter` is non-empty, sorted largest first, and up to
  30 are listed as `- <name> — <size> GB` (two decimals). No
  matches → success with `No DerivedData directories matched.`
  and count 0.
- Structured data: `count` (int).
- Error cases: DerivedData directory missing/unreadable.
- Deviations: none in behaviour. (This tool reads outside the
  workspace by design — the user's own DerivedData — as in Legacy;
  see §1.5.)

## 13. `xcode_toolchain_info` — Xcode Toolchain Info

- Legacy: `AssistXcodeToolchainInfoTool`, capability `.compilation`,
  risk `.safeRead`. Description: "Reports the active Xcode version,
  build number, and installed SDKs via xcodebuild." No parameters.
- Behaviour: runs the real `xcodebuild -version` (fixed argv,
  60 s bound); empty output → failure
  `xcodebuild is not available (Xcode command-line tools
  missing?).` Then runs `xcodebuild -showsdks` and collects the
  trimmed lines starting with `-sdk `. The report is
  `Xcode toolchain:` / `<version>` /
  `Installed SDKs (<n>):` / up to 20 `  <sdk line>` lines.
- Structured data: `sdkCount` (int).
- Error cases: `xcodebuild` missing (empty `-version` output).
- Deviations: none in behaviour (Legacy's `AssistArgvRunner`
  60 s timeout is kept; the runner is Ycode's fixed-argv runner).

## 14. `xcode_device_destination_finder` — Xcode Device Destination Finder

- Legacy: `AssistXcodeDeviceDestinationTool`, capability
  `.diagnostics`, risk `.safeRead`. Description: "Lists connected
  physical Apple devices and available simulator runtimes for
  building and testing."
- Schema: `platform` ("Optional platform filter (e.g. 'iOS',
  'watchOS', 'macOS')."). No required parameters.
- Behaviour: runs the real
  `xcrun simctl list devices available -j` (fixed argv, 60 s
  bound). A launch failure → `Failed to query simulator devices
  via simctl: <detail>`. Unparseable JSON →
  `Unable to parse simctl JSON response.` The `devices` object
  maps a runtime identifier to its devices; runtimes are shown
  sorted (Legacy iterated the JSON dictionary, whose order is
  unspecified — the port sorts for deterministic output), filtered
  by case-insensitive substring on the runtime when `platform` is
  given, with the `com.apple.CoreSimulator.SimRuntime.` prefix
  stripped. Up to 6 devices per runtime are listed as
  `- **<name>** (`<state>`) — UDID: `<udid>`` under a
  `#### <runtime>` heading, after the heading
  `### Available Simulator Destinations:`. No devices after
  filtering → success with
  `No available simulators matching the requested filter.`
- No structured data (Legacy returns none) — plain text result.
- Error cases: `xcrun` missing; unparseable JSON.
- Deviations from Legacy, recorded here:
  - Runtime sections are sorted; Legacy's order was the JSON
    dictionary's unspecified order.
  - Legacy's blocking `Process` + merged pipe is replaced by the
    fixed-argv runner (`runXcrun`).
  - Note: despite the description mentioning physical devices,
    Legacy only ever ran `simctl list devices` — the port keeps
    that (simulators only), it does not add a physical-device
    query.

## 15. Safety rules (non-negotiable)

- Never a shell: every subprocess is a fixed argument vector
  (`terminalRunFixed` / `runXcrun`); no string is ever passed to
  `/bin/sh`, and no argument is built by interpolation into a
  command line. Scheme/destination values reach the session seam
  as structured values, never as shell text.
- Workspace confinement: every tool path resolves inside the
  workspace (the two read-only DerivedData exceptions in §1.5
  are the only outside reads, and neither writes).
- One approval gate: `project_clean` is the slice's only write
  tool; its `build/` removal asks `approve()` through an explicit
  `MCPChange` and writes nothing on refusal. `confirm="true"` is
  tool input, not policy — it never bypasses `run()`.
- No Autopilot: no execution mode, no bypass, no stored approval.
- No invented results: a build/test/archive reports the real
  command's real outcome; a missing toolchain is a clean failure
  naming the prerequisite, never a fabricated success.
- No `generate_xcodeproj` in this slice (§1.8).

## 16. Honestly-failing / BLOCKED notes

None of the 13 tools is registered as honestly-failing: all 13 are
implemented. The honest failures are environmental, not
registration-level:

- `project_build`, `project_test`, `project_clean` (derivedData
  scope) need a Swift toolchain or Xcode on the machine running
  the server; on this Linux environment they fail with the
  session's own build failure, not with invented output.
- `project_archive`, `xcode_toolchain_info`, `xcresult_parser`,
  `xcode_device_destination_finder` need macOS with Xcode command
  line tools (`/usr/bin/xcodebuild`, `/usr/bin/xcrun`); without
  them they fail naming the missing tool.
- `derived_data_locate` and the DerivedData search in
  `xcresult_parser` fail / report nothing when
  `~/Library/Developer/Xcode/DerivedData` does not exist.

## 17. What is still pending (Mac build/test)

- `swift build` / `swift test` on Dylan's Mac: no Swift toolchain
  exists in this environment, so the implementation and the tests
  are statically checked only. The real-build tests
  (`project_build` / `project_test` success paths) are gated on
  `canBuildPackages`, like Wave 6's.
- Live `xcodebuild` paths (`project_archive`,
  `xcode_toolchain_info`, `xcresult_parser`,
  `xcode_device_destination_finder`) can only be exercised on a
  Mac with Xcode installed.

## Evidence

| Claim | Level | Source |
|---|---|---|
| The 13 tool IDs, descriptions, schemas, capabilities, risk levels, messages, data keys, and behaviours in §2–§14 | 1 | Legacy `SwiftCode/Backend/Assist/Tools/Assist{BuildProject,TestRunner,ProjectClean,ProjectArchive,BuildLogAnalyze,BuildSystemDetect,BuildConfigurationList,BuildSettingsDiff,BuildPhaseScriptsList,XCResultParser,DerivedDataLocate,XcodeToolchainInfo,XcodeDeviceDestination}Tool.swift`, read directly |
| Legacy aliases for this slice (`build`/`build_project`/`run_build`/`xcodebuild` → `project_build`; `test`/`run_tests` → `project_test`; `xcresult` → `xcresult_parser`; `device_destinations` → `xcode_device_destination_finder`) | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table, read directly |
| `AssistTextFormat.truncated` (first N chars + `\n… [label: showing first N of M characters]`), `AssistWorkspaceScan.findPbxproj` (first `.pbxproj` under root), `fileSize` (`.fileSizeKey`) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistToolSharedHelpers.swift`, read directly |
| `build_system_detect`'s Xcode check looks for entries literally named `xcworkspace` / `xcodeproj` | 1 | Legacy `AssistBuildSystemDetectTool.swift` check list, read directly |
| Session build/test seam (`s.build(.build/.clean)`, `s.runTests()`, `applyScheme`, `testPlanNames`), `BuildRequest.Action` has no archive action | 1 | Ycode `ycode/Sources/YcodeIDECore/Session/WorkspaceSession.swift`, `ycode/Sources/YcodeBuild/BuildEngine.swift`, `ycode/Sources/YcodeMCP/YcodeTools+Build.swift`, read directly |
| Fixed-argv runner (`terminalRunFixed`, `runXcrun`), `approveFileWritingChange` / `noteFileWritingChanged`, `reviewDocsFindPbxproj`, shell-character guards | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+TerminalSupport.swift`, `YcodeTools+Simulator.swift`, `YcodeTools+FileWriting.swift`, `YcodeTools+ReviewDocs.swift`, `YcodeTools+TestingSupport.swift`, read directly |
| Single approval gate, `writes: true` = Legacy `safeMutation` / `potentiallyDestructive`, Autopilot rejection | 1 | `specs/ide/assist-approval-model.md`, read directly |
| `generate_xcodeproj` lives in the same Legacy file but is a different tool ID, not in this slice | 1 | Legacy `AssistBuildProjectTool.swift` (`AssistGenerateXcodeprojTool`), read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol |


## Part B — Project model & pbxproj

Ycode modules: `YcodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 19 Legacy Assist
Project/Xcode/build tools ported in Wave 7, slice B:
`create_new_app`, `generate_xcodeproj`, `pbxproj_lint`,
`project_build_settings`, `project_capabilities`, `project_diff`,
`project_mutation_controller`, `project_restore`,
`project_scheme_list`, `project_snapshot`, `project_structure_map`,
`project_target_add`, `project_target_list`,
`scheme_test_plan_list`, `target_dependencies_list`,
`target_source_list`, `workspace_settings_read`,
`xcode_build_settings_inspector`, `xcode_scheme_manager`. The
implementation is
`ycode/Sources/YcodeMCP/YcodeTools+ProjectModel.swift`; the tests
are `ycode/Tests/YcodeMCPTests/YcodeProjectModelTests.swift`.

The per-tool sections below are catalogue-ready: each gives the
tool's description and input schema verbatim (Legacy's
`parametersSchema` plus the `workspace` parameter every Ycode tool
carries), its output shape, and its error cases, so the coordinator
can merge them into `specs/ide/assist-tool-catalogue.md` without
re-deriving anything.

Scope: what each tool does once called, what it returns, what it
refuses, and which Ycode seam it runs through. The approval model
itself (write policy, `commit()` / `approve()`, the rejected
Autopilot bypass) is `specs/ide/assist-approval-model.md` and is
not repeated here beyond the per-tool gate column.

## 1. Conventions shared by the slice

- **IDs, titles, descriptions, schemas are Legacy's verbatim**,
  verified live from each Legacy tool file (see Evidence). The
  only additions are the `workspace` parameter and Ycode's
  `additionalProperties: false`. Legacy's parameter-name aliases
  are NOT supported: Ycode's argument validation rejects unknown
  arguments before the handler runs. Legacy's tool-name aliases
  for this slice are `xcode_scheme` → `xcode_scheme_manager` and
  `build_settings` → `xcode_build_settings_inspector` (Legacy's
  `AssistToolRegistry` alias table); they live in
  `MCPServer.toolAliases`, which the coordinator owns — they are
  not added here.
- **Structured data keeps Legacy's keys, with typed JSON values**
  (integers, booleans) the way Ycode's other tools do — Legacy's
  string-only map is not reproduced. Tools whose Legacy result
  carries no data return a plain text result instead.
- **Paths resolve through the session resolvers**
  (`resolveFileReadingPath`, `fileReadingRelativePath`) and never
  escape the workspace. A path the resolver refuses fails with
  Legacy's own message for that tool. A `..` that stays inside the
  workspace resolves (the session resolver's rule) where Legacy's
  per-tool resolvers rejected any `..` as text.
- **The project model is Ycode's own, not a parallel one.** All
  pbxproj reads go through `YcodeProject` (`PBXProj` parsing,
  `targets`, `buildConfigurations(listID:)`); all pbxproj edits go
  through `YcodeProject`'s typed mutations (`setBuildSetting`,
  `addFileReference`, `addBuildFile`, `removeFileReference`,
  `addTarget`, `addSourceGroup`) and are serialised with
  `PBXProjWriter` (`serialized(projectName:)`), then written
  through `commit()`. No tool edits pbxproj text by line or regex
  insertion. Consequence: a pbxproj that parses but is missing a
  section anchor cannot occur — the model either parses (and the
  edit is computed in memory first) or fails to parse, so no
  partial write is possible. Legacy's per-tool "missing anchor"
  failures therefore have no equivalent here; a malformed pbxproj
  fails as "Failed to read project.pbxproj." (or "Could not read
  …" for the mutation controller).
- **The first pbxproj wins.** Where Legacy scans for "the"
  pbxproj (`AssistWorkspaceScan.findPbxproj`, first in enumerator
  order), this port takes the first `project.pbxproj` under the
  workspace root in sorted-path order, so the choice is
  deterministic. `project_target_list` scans every
  `project.pbxproj` at depth ≤ 4, as Legacy does.
- **No `xcodebuild` is spawned.** Legacy's scheme/target/settings
  reads run `/usr/bin/xcodebuild -list` / `-showBuildSettings`
  (macOS-only; they fail on Linux and in this environment).
  This port reads the same facts from the parsed pbxproj and from
  the session's own model (`WorkspaceModel.schemeNames`, which
  discovers `.xcscheme` files and autocreates one scheme per
  target when a project has none). Build-setting values are the
  values as written in the pbxproj (project-level merged with
  target-level, target wins); there is no xcconfig inclusion and
  no `$(…)` macro expansion. That is a deliberate deviation,
  recorded per tool below.
- **Failures are thrown as `MCPToolError`** with Legacy's message
  text, so the caller sees an `isError` result carrying that
  message. Legacy's `.failure(…)` and Ycode's throw are the same
  observable outcome.
- **Risk / gate.** `safeRead` tools are `writes: false`,
  `readOnly: true, idempotent: true`. `execution` tools are
  `writes: false`, `readOnly: false, idempotent: false` (they run
  something; they change no file) — except `generate_xcodeproj`,
  which is `writes: true` (see §3.3). `safeMutation` tools are
  `writes: true`, `readOnly: false, idempotent: true`, and go
  through `commit()` (text writes) or an explicit `MCPChange` +
  `approve()` (non-text operations). `project_restore` is
  `writes: true`, `potentiallyDestructive`
  (`readOnly: false, destructive: true`). There is no second gate,
  no Autopilot, no bypass.
- **No result is ever invented.** Lint counts, target lists,
  settings, schemes, diffs and snapshots report what was actually
  read, run, or copied. A missing xcodegen, a missing pbxproj, or
  a missing snapshot fails honestly with the prerequisite named.
- **No Swift toolchain exists in this environment** (Linux CI):
  the implementation and tests are statically checked only.
  `swift build` / `swift test` and the Mac live runs stay pending
  on Dylan's Mac.

## 2. The seams (read before implementing)

- **Project model** (`YcodeProject`): `PBXProj(contentsOf:)`
  / `PBXProj(parsing:)`, `proj.targets` (in the project's
  `targets` list order), `buildConfigurations(listID:)`,
  `setBuildSetting(_:_:configuration:)` /
  `setBuildSetting(_:_:inListOf:)`, `addFileReference(path:to:)`,
  `addBuildFile(fileReference:to:)`,
  `removeFileReference(_:)`, `addTarget(_:)` (`NewTarget`),
  `addSourceGroup(path:)`, `serialized(projectName:)`.
  Specs: `specs/ide/project-editor.md` §Mutations,
  `specs/formats/pbxproj.md`.
- **Schemes** (`YcodeIDECore`): `WorkspaceModel.schemeNames`
  (shared + user `.xcscheme` files discovered per container;
  one scheme per target when a project has none) and
  `WorkspaceModel.projects` (loaded `PBXProj` by `.xcodeproj`
  path). `applyScheme` validates a scheme name against
  `schemeNames`.
- **New projects** (`YcodeIDECore`): `ProjectTemplates.all`
  (descriptors; `platform` + `title` select one),
  `TemplateOptionsForm` (`makeForm(values:)`),
  `ProjectGenerator.generate(_:_:)` (in-memory
  `GeneratedProject`: `files: [(String, String)]` plus an
  optional `project: PBXProj`), serialised with
  `project.serialized(projectName:)`. The tool writes the
  generated files through `commit()`, one per file, in sorted
  path order — it does not call `GeneratedProject.write(in:)`,
  which writes ungated.
- **Git** (`YcodeTools+Git.swift`): `runGit(_:in:)` runs the
  `git` CLI with the Wave 3 environment (no pager, no prompts,
  `GIT_OPTIONAL_LOCKS=0`); a non-zero exit is returned, never
  thrown.
- **Fixed-argv subprocess** (`YcodeTools+TerminalSupport.swift`):
  `terminalRunFixed` (off the main actor), for `xcodegen`.
- **Snapshots**: Ycode keeps no workspace snapshots (the same
  reason Wave 6's `safe_undo` fails honestly). This slice
  nevertheless ports `project_snapshot` / `project_restore`
  honestly, because their prerequisite is self-contained: a
  snapshot is a whole-tree copy plus a `metadata.json`, stored
  under the user's Application Support directory in
  `YcodeSnapshots/<uuid>/` (mirroring Legacy's
  `AssistSnapshots/<uuid>/` layout, renamed for Ycode). No
  session store is needed. See §3.2 and §4.8/§4.9.

## 3. Deliberate deviations from Legacy

### 3.1 No `xcodebuild` anywhere in this slice

Legacy's `project_scheme_list`, `project_target_list`,
`project_build_settings` (read), `xcode_build_settings_inspector`
and `xcode_scheme_manager` (list) spawn `xcodebuild`. The port
reads the pbxproj / session model instead (§1). On macOS the
same facts are returned for well-formed projects; on Linux the
tools work at all, where Legacy failed outright ("Listing Xcode
schemes requires macOS with xcodebuild."). The one fact lost is
xcconfig/macro-resolved setting values (see §3.4).

### 3.2 Snapshots live in `YcodeSnapshots`, and `project_snapshot` is a write

Legacy stores snapshots in Application Support
`AssistSnapshots/<uuid>/` (`files/` + `metadata.json` with `id`,
`timestamp`, `message`, `rootPath`); the port stores them in
`YcodeSnapshots/<uuid>/` with the same layout and the same
metadata keys. Legacy marks `project_snapshot` `safeRead`, but
it writes a whole-tree copy to disk, so the port registers it
`writes: true` (`safeMutation`): a read-only server must not
copy a workspace tree as a side effect. `project_restore`
keeps Legacy's `potentiallyDestructive` and is gated per call
with an explicit `MCPChange` whose summary says the restore
replaces all workspace files. Restore deletes every entry in
the workspace root and copies the snapshot back, exactly as
Legacy does (including its failure mode: a snapshot whose
`files/` directory is missing fails with
"Failed to restore snapshot: Snapshot '<id>' not found.").

### 3.3 `generate_xcodeproj` never installs xcodegen, and is gated

Legacy's approval-exempt design runs `xcodegen` directly and,
when it is missing, installs it via Homebrew — also without a
prompt. The port does neither silent install: it looks for
`xcodegen` at `/opt/homebrew/bin/xcodegen`,
`/usr/local/bin/xcodegen`,
`/opt/homebrew/opt/xcodegen/bin/xcodegen`, then on `PATH`
(`which xcodegen`); when absent it fails with Legacy's own
message ("xcodegen is not installed and Homebrew was not found.
Install Homebrew (https://brew.sh), then run this tool again —
it will install xcodegen automatically." — the last clause is
Legacy's wording for the install it would have done; the port
does not do it, and the spec records that the sentence is kept
verbatim so the error stays recognisable). Legacy marks the
tool `execution`; the port registers it `writes: true`
(`safeMutation`) because `xcodegen generate` writes a
`.xcodeproj` bundle into the workspace, and a read-only server
must refuse that. Before running, the handler presents one
`MCPChange` for the expected output bundle (the project name
is read from the spec's top-level `name:` line; when the spec
has none, the call fails rather than running an unapprovable
write).

### 3.4 Build-setting reads are raw pbxproj values

`project_build_settings` (read) and
`xcode_build_settings_inspector` return the settings as written
in the pbxproj's `XCBuildConfiguration` blocks: project-level
first, target-level overriding, for the named configuration
(`project_build_settings`) or the project's default
configuration (`xcode_build_settings_inspector`, matching
Legacy's bare `-showBuildSettings`). No xcconfig files are
followed and no `$(…)` references are expanded. A setting
whose value only exists via an xcconfig therefore reads as
absent.

### 3.5 `create_new_app` is confined to the workspace

Legacy writes the new project to an absolute `projectLocation`
(default `~/Documents/<appName>`) and opens it into the
session. Ycode tools never write outside the workspace, so the
port resolves `projectLocation` inside the workspace root
(relative, or absolute but contained) and defaults to
`<workspace>/<appName>`; an outside location fails with
"<path> is outside the workspace folder <root>". The port
scaffolds with Ycode's own template (`ProjectGenerator`: the
`<platform> App` template, SwiftUI) instead of Legacy's
`ProjectTemplateManager`, writes no `project.json` (Legacy
metadata, not part of Ycode's project model), and does not
open the new project into the session — the caller opens it
with `workspace_open`. Legacy's `uiPreferences`,
`architecturePreferences` and `additionalRequirements` are
accepted and ignored, as Legacy itself ignores them beyond
storing the description. The bundle identifier default
(`com.swiftcode.<lowercased app name without spaces>`) and the
version/build defaults (`1.0` / `1`) are Legacy's verbatim.

### 3.6 `project_target_add` registers the target properly

Legacy inserts the `PBXNativeTarget` / configuration-list /
configuration blocks as text but never adds the target to the
project's `targets` list, never creates a product reference,
and never creates a build phase — the new target is an orphan
in the file. The port uses `PBXProj.addTarget`, which registers
the target in `targets`, creates its product reference and its
(Debug/Release) configuration list, and additionally registers
the created source folder as a group
(`addSourceGroup`, or a synchronised folder for object version
≥ 77) so the created Swift file is visible in the project.
Legacy's empty `buildPhases` is preserved (no Sources phase is
created). The anchor checks ("missing the Begin … section
anchor") have no model equivalent and are dropped — the edit
is computed in memory first and only committed whole.

### 3.7 `project_mutation_controller` — model edits, not text surgery

- `add`: Legacy resolves the group and Sources phase with
  text regexes (`AssistXcodeProjectResolver`); the port resolves
  them from the parsed graph (group full paths from
  `PBXGroup.path`/`name` up the parent chain, exact match then
  deepest prefix; first Sources phase in project-target order).
  The 4-step registration (build file, file reference, group
  child, phase file) is the same, executed through
  `addFileReference` + `addBuildFile`, and the whole updated
  pbxproj is committed once. The "already referenced" check
  (text contains `filePath` or `fileName`) is kept verbatim.
- `remove`: Legacy deletes every *line* containing the file
  string — which can delete unrelated lines that merely mention
  the name. The port removes the matching `PBXFileReference`
  objects (by `path` or `name`) and their build files and group
  entries through `removeFileReference`, and writes nothing
  when nothing matched (Legacy still rewrote the file and
  reported success; the port reports the same success message
  without a no-op write).
- `repair`: identical text transform (`\n\n\n` → `\n\n`) via
  `commit()`.

### 3.8 `project_capabilities` list keeps Legacy's raw pbxproj lines

Legacy's pbxproj capability scan appends the whole trimmed
line containing `SystemCapabilities` (not a parsed capability
name). The port keeps that verbatim, odd as it is, so list
output matches Legacy's.

### 3.9 `project_diff` counts from porcelain status

Legacy's `GitService` status/diff is not available in Ycode;
the port runs `git status --porcelain`, `git diff HEAD` and
`git branch --show-current` (falling back to
`git rev-parse --abbrev-ref HEAD`, then `(detached)`). Staged
= porcelain lines whose first column is not a space or `?`;
unstaged = lines whose second column is not a space;
untracked (`??`) counts as unstaged. Hunks = `@@` headers in
the diff. Modified files are the status paths'
`lastPathComponent`, as Legacy lists them. Any git failure
(non-repo, missing git) fails as
"Diff inspection failed: <git output>".

## 4. Per-tool behaviour

### 4.1 `create_new_app` — Create New App (writes: true, safeMutation)

- **Description (verbatim):** "Creates a new native application
  project from user specifications or autonomous request
  parameters."
- **Legacy source:** `AssistCreateNewAppTool.swift`.
  Capability `general`, risk `safeMutation`, permission none
  (default: mutating → fileSystem).
- **Input:** `appName` (string, required, "Display name of the
  application (e.g. My Notes)."), `bundleIdentifier` (string,
  "Reverse domain bundle identifier (e.g.
  com.example.mynotes)."), `version` (string, "Marketing
  version number (e.g. 1.0)."), `build` (string, "Build number
  (e.g. 1)."), `platform` (string, "Target platform: macOS,
  iOS, iPadOS, watchOS, or visionOS."),
  `projectLocation` (string, "Absolute file URL path where the
  project directory should be generated."),
  `applicationDescription` (string, required, "Natural language
  description or feature specification of the application."),
  `uiPreferences` (object, "UI and UX preferences (style,
  layout, theme, accessibility, persistence)."),
  `architecturePreferences` (string, "Preferred software
  architecture pattern (e.g. MVVM, TCA, Observable Stores)."),
  `additionalRequirements` (string, "Any extra technical
  requirements or constraints."),
  `overwriteExistingMetadata` (boolean, "Whether to overwrite
  existing project metadata if an active project exists.").
- **Behaviour:** defaults are Legacy's (`platform` macOS,
  `version` "1.0", `build` "1", bundle identifier
  `com.swiftcode.<appName without spaces, lowercased>` when
  empty). The platform selects Ycode's `<platform> App`
  template (iPadOS uses the iOS App template; any other value
  falls back to the macOS App template, as Legacy's
  `selectTemplate` defaults to `swiftui_app`). The form is
  filled with the app name, the organisation prefix derived
  from the bundle identifier, SwiftUI interface/lifecycle,
  Swift language, no tests, no storage, no CloudKit. The
  generated files are committed one per file in sorted path
  order, then the generated `.xcodeproj/project.pbxproj`
  (serialised from the generated `PBXProj`) and its
  `project.xcworkspace/contents.xcworkspacedata` (the
  self-workspace wrapper every Ycode project carries).
  The target directory must not already exist non-empty.
- **Output:** plain text, Legacy's form:
  "Successfully initialized Create New App workflow for
  '<appName>'.\nTarget Directory: <path>\nBundle Identifier:
  <id>\nPlatform: <platform>\nVersion: <version> (<build>)\n
  Scaffolded with Ycode's '<platform> App' template.\nReady
  for autonomous implementation and iteration."
  No data keys (Legacy returns none).
- **Errors:** missing `appName` / `applicationDescription` →
  "Missing required parameter: appName" /
  "Missing required parameter: applicationDescription"; no App
  template for the platform → "No app template for platform
  '<platform>'."; target directory already exists non-empty →
  "Project directory '<path>' already exists."; template
  generation failure → the generator's error text; a
  `projectLocation` outside the workspace → the resolver's
  outside-workspace message.

### 4.2 `generate_xcodeproj` — Generate Xcode Project (writes: true, safeMutation)

- **Description (verbatim):** "Generates .xcodeproj files from
  an XcodeGen project.yml spec. Installs XcodeGen automatically
  if missing. Runs in the background without a terminal approval
  prompt."
- **Legacy source:** `AssistGenerateXcodeprojTool.swift` (in
  `AssistBuildProjectTool.swift`). Capability `compilation`,
  risk `execution`, permission none (default: execution →
  terminalExecution in Legacy; the port gates on the write
  policy instead, §3.3).
- **Input:** `spec` (string, "Workspace-relative path to the
  XcodeGen spec file. Default is 'project.yml'."),
  `useCache` (string, "'true' to pass --use-cache to xcodegen.
  Default is 'false'.").
- **Behaviour:** `spec` defaults to `project.yml` and must
  exist in the workspace. The project name is read from the
  spec's top-level `name:` line; one `MCPChange` is presented
  for the expected `<name>.xcodeproj` bundle (proposed `""`,
  non-text shape) and the run proceeds only on approval.
  `xcodegen` is located, never installed (§3.3), and run as
  `generate --spec <absolute spec path>` plus `--use-cache`
  when `useCache` is `"true"` (case-insensitive), in the
  workspace root, bounded at 300 s, fixed argv, never a shell.
  Produced projects are the top-level `.xcodeproj` bundles
  after the run.
- **Output:** success — "XcodeGen succeeded (<duration>s).
  Generated: <names>\n<stdout tail, 1200 chars>", data
  `spec` (string), `projects` (comma-joined string),
  `duration` (string, `"%.2fs"`).
- **Errors:** spec missing → "XcodeGen spec not found at
  '<spec>' (resolved to <absolute path>). Create a
  project.yml first or pass the spec parameter."; spec has no
  `name:` → "Could not determine the project name from
  '<spec>'; xcodegen output cannot be approved as a change.";
  xcodegen missing → Legacy's Homebrew message (§3.3);
  timeout → "xcodegen timed out after 300s."; non-zero exit or
  no `.xcodeproj` produced → "XcodeGen failed (exit <code>,
  <duration>s):\n<combined output tail, 1500 chars>".

### 4.3 `pbxproj_lint` — pbxproj Lint (read-only)

- **Description (verbatim):** "Lints the .pbxproj: file
  references pointing at missing files, duplicate paths, and
  build files with dangling file references."
- **Legacy source:** `AssistPbxprojLintTool.swift`. Capability
  `diagnostics`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** Legacy's regexes verbatim: file references
  are `([0-9A-F]{24}) /\* (.+?) \*/ = \{isa =
  PBXFileReference;…path = …;` entries with an explicit path
  (quoted or not); a reference is missing when its plain
  relative path does not exist under the project directory
  (the `.xcodeproj`'s parent — absolute SDK paths are skipped);
  duplicate paths are counted per repeated path string;
  dangling build files are `fileRef = <24-hex>` entries whose
  id has no file reference. Caps: missing stops at 200,
  dangling at 100; the report lists at most 30 missing, 20
  duplicates, 20 dangling (sorted).
- **Output:** structured, keys `fileRefCount`, `missingCount`,
  `duplicateCount`, `danglingCount` (integers), `clean`
  (boolean); summary:
  "pbxproj lint for <file>:\n- File references: N\n- Missing
  files on disk: N\n  MISSING: …\n- Duplicate paths: N\n
  DUPLICATE: …\n- Dangling build-file refs: N\n  DANGLING: …"
- **Errors:** no pbxproj in the workspace → "No .pbxproj found
  in the workspace."

### 4.4 `project_build_settings` — Build Settings (writes: true, safeMutation)

- **Description (verbatim):** "Reads Xcode build settings with
  xcodebuild, or sets one build setting key in the project's
  pbxproj."
- **Legacy source:** `AssistProjectBuildSettingsTool.swift`.
  Capability `compilation`, risk `safeMutation`, permission
  none (default: mutating → fileSystem).
- **Input:** `action` (string, "read or set. Default: read."),
  `target` (string, "Optional target name for read or set."),
  `configuration` (string, "Build configuration, e.g. Debug
  or Release. Default: Debug."), `key` (string, "Build setting
  key. Required for set; optional filter for read."),
  `value` (string, "New value for the key. Required for set.").
- **Behaviour — read:** merged raw settings (§3.4) for the
  named configuration; `key` filters to one setting.
- **Behaviour — set:** the key must match
  `[A-Za-z0-9_]+` with no `..`, newline, `;`, `{` or `}`
  (Legacy's `isValidSettingKey`); the setting is set in the
  named configuration of the named target's list, or of the
  project's list when no target is given; the updated pbxproj
  is committed whole and verified by re-parsing and reading
  the setting back.
- **Output:** read-all — "Found N build setting(s) for
  configuration '<c>'.", data `count` (int), `configuration`
  (string), `settings` (string: first 50 settings sorted,
  "K = V" per line). Read-one — "Build setting <key> = <value>",
  data `key`, `value`, `configuration`. Set — "Set build setting
  <key> = <value> for configuration '<c>'.", data `key`,
  `value`, `configuration`, `file` ("project.pbxproj").
- **Errors:** other action → "Invalid action '<action>'.
  Expected read or set."; empty configuration → "Missing
  required parameter: configuration"; set without key/value →
  "Missing required parameter: key for action=set" /
  "Missing required parameter: value for action=set"; bad key
  → "Invalid build setting key '<key>'."; no pbxproj → "No
  project.pbxproj found in the workspace."; target absent →
  "Target '<target>' not found in project.pbxproj."; no block
  for the configuration → "No XCBuildConfiguration block for
  configuration '<c>' found in project.pbxproj."; read-one key
  absent → "Build setting '<key>' not found for configuration
  '<c>'."; write/verify failure → "Failed to write
  project.pbxproj: …" / "Verification failed: '<key> =
  <value>;' not found after writing project.pbxproj."

### 4.5 `project_capabilities` — Capabilities (writes: true, safeMutation)

- **Description (verbatim):** "Lists app capabilities from
  entitlements and pbxproj, or enables/disables one capability
  by editing the entitlements plist."
- **Legacy source:** `AssistProjectCapabilitiesTool.swift`.
  Capability `fileModification`, risk `safeMutation`,
  permission none (default: mutating → fileSystem).
- **Input:** `action` (string, "list, enable, or disable.
  Default: list."), `capability` (string, "Capability name for
  enable/disable: push, icloud, appGroups, appSandbox, keychain,
  network.").
- **Behaviour — list:** capabilities from the first
  `.entitlements` file (key mapping: `aps-environment` →
  `push`, key containing `icloud` → `icloud`,
  `application-groups` → `appGroups`, `app-sandbox` →
  `appSandbox`, `keychain` → `keychain`, `network.client` →
  `network`, anything else → the raw key) union the pbxproj's
  raw `SystemCapabilities` lines (§3.8), sorted, deduplicated.
- **Behaviour — enable/disable:** the capability name maps
  (case-insensitive, with Legacy's aliases: `push`/`aps`/
  `aps-environment` → `aps-environment` = `"development"`;
  `icloud`/`cloudkit` →
  `com.apple.developer.icloud-container-identifiers` = `[]`;
  `appgroups`/`app-groups`/`app_groups` →
  `com.apple.security.application-groups` = `[]`;
  `appsandbox`/`app-sandbox`/`app_sandbox` →
  `com.apple.security.app-sandbox` = `true`;
  `keychain`/`keychain-access-groups` →
  `keychain-access-groups` = `[]`; `network`/`network-client` →
  `com.apple.security.network.client` = `true`). Enable sets
  the key; disable removes it (and fails when it is absent).
  The entitlements plist is re-serialised as XML and committed;
  the result is verified by re-reading.
- **Output:** list — "Capabilities: a, b" or "No capabilities
  found.", data `capabilities` (comma-joined), `count` (int),
  `entitlements` (comma-joined), `pbxproj` (comma-joined).
  Enable — "Enabled capability '<name>' (<key>) in
  <file>.", data `capability`, `entitlementsKey`, `action`
  ("enable"). Disable — the same with "Disabled" / "disable".
- **Errors:** other action → "Invalid action '<action>'.
  Expected list, enable, or disable."; enable/disable without
  capability → "Missing required parameter: capability for
  action=<action>"; unknown capability → "Unknown capability
  '<name>'. Supported: push, icloud, appGroups, appSandbox,
  keychain, network."; no entitlements file → "No .entitlements
  file found in the workspace. Cannot <action> capability
  '<name>'."; invalid plist → "Entitlements file '<file>' is
  not a valid property list dictionary."; disable of an absent
  capability → "Capability '<name>' (<key>) is not enabled in
  entitlements."; write/verify failure → "Failed to write
  entitlements file." / "Verification failed: …".

### 4.6 `project_diff` — Diff Project (read-only)

- **Description (verbatim):** "Compares the working tree with
  Git HEAD, returning real unified diffs and modified files."
- **Legacy source:** `AssistDiffTool.swift`. Capability
  `gitOperations`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** §3.9. Clean tree → "No changes detected.
  Working tree is clean.", data `diff` (`""`).
- **Output:** structured, keys `diff` (string, the unified
  diff), `branch` (string), `staged_count`,
  `unstaged_count` (integers); summary "Git Status on branch
  '<branch>': <staged> staged, <unstaged> unstaged, <hunks>
  diff hunks.\n\n<diff>".
- **Errors:** any git failure → "Diff inspection failed:
  <git output>".

### 4.7 `project_mutation_controller` — Xcode Project Mutation Controller (writes: true, safeMutation)

- **Description (verbatim):** "Adds/removes file references in
  the user's project.pbxproj, resolving groups and build phases
  from the target project."
- **Legacy source:** `AssistProjectMutationController.swift`.
  Capability `fileModification`, risk `safeMutation`,
  permission none (default: mutating → fileSystem). This is a
  controller, not a plain tool: it resolves the target pbxproj
  (explicit `projectFile` wins, else the project in the
  workspace root), resolves the group and Sources phase from
  the target project itself, and performs a multi-step
  registration — the port keeps that shape on the model (§3.7).
- **Input:** `action` (string, required, "One of 'add',
  'remove', or 'repair'.") , `projectFile` (string,
  "Workspace-relative path to project.pbxproj. Defaults to the
  project.pbxproj of the project found in the workspace root."),
  `filePath` (string, "Workspace-relative file path. Required
  for 'add' and 'remove'.").
- **Behaviour:** §3.7. `repair` collapses triple newlines.
  `add` registers the file (build file + file reference +
  group child + phase file) in the first Sources phase in
  project-target order. `remove` unregisters matching file
  references.
- **Output:** plain text, "Project mutation complete:
  <action>" for `repair`/`remove`, "Project mutation complete:
  added <fileName> via 4-step registration protocol" for
  `add`; data `project` (the workspace-relative pbxproj path)
  for all three. The already-referenced case returns
  "File already referenced in project.pbxproj: <filePath>"
  with no data.
- **Errors:** missing action → "Missing action:
  add/remove/repair"; no project → "No Xcode project
  (.xcodeproj) found in the workspace root. Pass projectFile
  explicitly."; unreadable pbxproj → "Could not read
  <pbxPath>: …"; add/remove without filePath → "Missing
  filePath"; no matching group → "No matching group found in
  <pbxPath> for directory '<fileDir>'. Create the group in
  Xcode first or pass a filePath inside an existing group.";
  no Sources phase → "No PBXSourcesBuildPhase ('Sources')
  found in <pbxPath>."; other action → "Unsupported action:
  <action>".

### 4.8 `project_restore` — Restore Snapshot (writes: true, potentiallyDestructive)

- **Description (verbatim):** "Restores the project to a
  previously saved state."
- **Legacy source:** `AssistRestoreSnapshotTool.swift`.
  Capability `general`, risk `potentiallyDestructive`,
  permission none (default: mutating → fileSystem).
- **Input:** `snapshot_id` (string, required, "Snapshot
  identifier from project_snapshot or project_changelog.").
- **Behaviour:** §3.2. The snapshot must exist in the
  `YcodeSnapshots` store; one `MCPChange` is presented for the
  workspace root (summary "Restore project to snapshot
  <id> — replaces all files in the workspace") and the restore
  proceeds only on approval; then every entry in the workspace
  root is deleted and the snapshot's files are copied back.
- **Output:** plain text, "Successfully restored project to
  snapshot: <id>". No data keys (Legacy returns none).
- **Errors:** missing `snapshot_id` → "Missing required
  parameter: snapshot_id"; unknown snapshot → "Failed to
  restore snapshot: Snapshot '<id>' not found."; any other
  failure → "Failed to restore snapshot: <error>".

### 4.9 `project_scheme_list` — List Schemes (read-only)

- **Description (verbatim):** "Lists the Xcode schemes
  available for the user's project or workspace."
- **Legacy source:** `AssistProjectSchemeListTool.swift`.
  Capability `compilation`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** the session model's `schemeNames` (§2) for a
  project/workspace container. A package workspace has no
  `.xcodeproj`/`.xcworkspace` and fails as Legacy does.
- **Output:** structured, keys `schemes` (comma-joined
  string), `count` (int), `project` (the container's last
  path component); summary "Found N scheme(s): a, b".
- **Errors:** no project/workspace at the top level →
  "No .xcodeproj or .xcworkspace found at the top level of the
  workspace."

### 4.10 `project_snapshot` — Snapshot Project (writes: true, safeMutation)

- **Description (verbatim):** "Creates a full snapshot of the
  current project state."
- **Legacy source:** `AssistSnapshotProjectTool.swift`.
  Capability `general`, risk `safeRead` in Legacy — the port
  registers `safeMutation` (§3.2), permission none.
- **Input:** `message` (string, "Label stored on the snapshot.
  Default: \"Manual Snapshot\".").
- **Behaviour:** §3.2. A fresh UUID identifies the snapshot;
  the whole workspace tree is copied to
  `YcodeSnapshots/<uuid>/files/` and `metadata.json` records
  `id`, `timestamp`, `message`, `rootPath`.
- **Output:** structured, key `snapshot_id` (the UUID);
  summary "Successfully created project snapshot: <message>".
- **Errors:** any copy failure → "Failed to create snapshot:
  <error>".

### 4.11 `project_structure_map` — Project Structure Map (read-only)

- **Description (verbatim):** "Builds a machine-readable map
  of the project: top-level directories with file counts and the
  Xcode target layout parsed from the .pbxproj when present."
- **Legacy source:** `AssistProjectStructureMapTool.swift`.
  Capability `repositoryDiscovery`, risk `safeRead`, permission
  none.
- **Input:** `maxDepth` (integer, "Directory depth to map.
  Default 2, max 4.").
- **Behaviour:** `maxDepth` defaults to 2 and clamps to
  1…4. Every file under the root (Legacy's scan semantics:
  hidden files skipped, top-level `.git`, `.build`, `build`,
  `DerivedData`, `.swiftpm`, `Pods`, `Carthage`,
  `node_modules`, `.venv` skipped; 20,000-file cap) counts
  toward each ancestor directory up to `maxDepth`, with byte
  totals from file sizes. Targets come from the first pbxproj
  when one exists (sorted names); a workspace without a pbxproj
  simply has no target line.
- **Output:** structured, keys `directoryCount` (int),
  `targets` (comma-joined string); summary "Project structure
  map (depth N):\n- <dir>/ — <files> files, <bytes>
  bytes\n…\nXcode targets: a, b" (the last line only when
  targets exist).
- **Errors:** none defined (an unreadable root enumerates to
  an empty map).

### 4.12 `project_target_add` — Add Target (writes: true, safeMutation)

- **Description (verbatim):** "Adds a new Xcode target:
  creates a source directory with a real Swift file and inserts
  PBXNativeTarget blocks into project.pbxproj."
- **Legacy source:** `AssistProjectTargetAddTool.swift`.
  Capability `compilation`, risk `safeMutation`, permission
  none (default: mutating → fileSystem).
- **Input:** `targetName` (string, required, "Name of the new
  target. Letters, digits, underscore, hyphen only."),
  `type` (string, "Target type: app, framework, or test.
  Default: app."), `bundleId` (string, "Optional bundle
  identifier for the new target.").
- **Behaviour:** §3.6. The target name must be 1–64 chars of
  `[A-Za-z0-9_-]` with no `..` or `/`; the type must be `app`,
  `framework` or `test`; a bundle id must be non-empty
  `[A-Za-z0-9-.]` with no spaces. The source directory
  `<targetName>/` must not already exist. The Swift file
  content is Legacy's per type (app: `import Foundation` +
  `<Name>App` struct; framework: `import Foundation` +
  `public struct <Name>`; test: `import XCTest` +
  `<Name>Tests: XCTestCase` with `testExample`). Product types:
  app `com.apple.product-type.application` (product
  `<Name>.app`, `wrapper.application`), framework
  `com.apple.product-type.framework` (product
  `<Name>.framework`, `wrapper.framework`), test
  `com.apple.product-type.bundle.unit-test` (product
  `<Name>.xctest`, `wrapper.cfbundle`). The source file is
  committed first, then the updated pbxproj (Legacy's order).
- **Output:** structured, keys `targetName`, `type`,
  `targetId`, `sourceDirectory`; summary "Added target
  '<name>' (<type>) with source directory '<name>/'."
- **Errors:** missing name → "Missing required parameter:
  targetName"; bad type → "Invalid type '<type>'. Expected
  app, framework, or test."; bad name → "Invalid target name
  '<name>'. Use letters, digits, underscore, or hyphen only.";
  bad bundle id → "Invalid bundleId '<id>'."; no pbxproj →
  "No project.pbxproj found in the workspace."; target already
  exists → "Target '<name>' already exists in
  project.pbxproj."; directory exists → "Directory '<name>'
  already exists in the workspace. No changes were made.";
  write/verify failure → "Failed to create target source
  files: …" / "Failed to write project.pbxproj: …" /
  "Verification failed: target '<name>' not found after
  writing project.pbxproj."

### 4.13 `project_target_list` — List Targets (read-only)

- **Description (verbatim):** "Lists the Xcode targets in the
  user's project by scanning project.pbxproj and xcodebuild
  output."
- **Legacy source:** `AssistProjectTargetListTool.swift`.
  Capability `compilation`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** every `project.pbxproj` at depth ≤ 4 is
  parsed and its target names collected (deduplicated,
  sorted). The `xcodebuild -list` second source is not used
  (§3.1); the `sources` data key therefore lists only
  `project.pbxproj` entries (one per pbxproj that yielded
  targets).
- **Output:** structured, keys `targets` (comma-joined),
  `count` (int), `sources` (comma-joined); summary "Found N
  target(s): a, b".
- **Errors:** no targets anywhere → "No Xcode targets found.
  No .xcodeproj with a project.pbxproj was located in the
  workspace."

### 4.14 `scheme_test_plan_list` — Scheme Test Plan List (read-only)

- **Description (verbatim):** "Finds .xctestplan files in the
  workspace and lists the test targets each plan covers."
- **Legacy source:** `AssistSchemeTestPlanListTool.swift`.
  Capability `diagnostics`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** every `.xctestplan` file under the root
  (hidden files skipped) is listed sorted by path; each plan's
  JSON is read for `testTargets[].target.name` and shown as
  " — targets: a, b" (no suffix when the plan has no targets
  or is unreadable JSON).
- **Output:** structured, key `count` (int); summary "No
  .xctestplan files found in the workspace." when empty, else
  "Test plans (N):\n- <rel> — targets: …\n…".
- **Errors:** the workspace cannot be enumerated → "Cannot
  enumerate workspace."

### 4.15 `target_dependencies_list` — Target Dependencies List (read-only)

- **Description (verbatim):** "Lists Xcode target-to-target
  dependencies parsed from the project's .pbxproj."
- **Legacy source:** `AssistTargetDependenciesListTool.swift`.
  Capability `compilation`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** from the first pbxproj: each
  `PBXNativeTarget` (in project-target order) lists the names
  of the targets its `PBXTargetDependency` entries point at
  (sorted per target); a target with none shows "(no target
  dependencies)". Edge count is the total across targets.
- **Output:** structured, keys `targetCount`, `edgeCount`
  (integers); summary "Target dependencies:\n- <name>:
  <deps>\n…".
- **Errors:** no pbxproj → "No .pbxproj found in the
  workspace."; no `PBXNativeTarget` entries → "No
  PBXNativeTarget entries parsed from the pbxproj."

### 4.16 `target_source_list` — Target Source List (read-only)

- **Description (verbatim):** "Lists the source files compiled
  into a given Xcode target (Compile Sources build phase),
  resolved from the .pbxproj."
- **Legacy source:** `AssistTargetSourceListTool.swift`.
  Capability `compilation`, risk `safeRead`, permission none.
- **Input:** `target` (string, "Target name. If omitted, lists
  sources for every target (truncated per target)."),
  `limit` (integer, "Maximum files per target. Default 200.").
- **Behaviour:** `limit` defaults to 200 and clamps to
  1…2000. For each target (project-target order; filtered to
  `target` when given): its `PBXSourcesBuildPhase` files,
  resolved through `PBXBuildFile.fileRef` to the
  `PBXFileReference.path` (references without a `path` are
  skipped), sorted. Each target's list is truncated to `limit`
  with the marker "    … [truncated: showing <limit> of
  <count>]".
- **Output:** structured, key `targetCount` (int); summary
  "Target sources:\n- <name> (<count> files):\n    <path>\n…".
- **Errors:** no pbxproj → "No .pbxproj found in the
  workspace."; named target absent → "Target '<name>' not
  found in the pbxproj."; nothing parsed → "No target source
  phases parsed from the pbxproj."

### 4.17 `workspace_settings_read` — Workspace Settings Read (read-only)

- **Description (verbatim):** "Reads Xcode workspace/shared
  settings (.xcsettings plists): build system, derived-data
  location, and IDE workspace checks."
- **Legacy source:** `AssistWorkspaceSettingsReadTool.swift`.
  Capability `compilation`, risk `safeRead`, permission none.
- **Input:** none (besides `workspace`).
- **Behaviour:** every `.xcsettings` file under the root
  (Legacy's scan semantics) is read as a plist dictionary;
  keys are listed sorted, values truncated to 120 characters;
  an unreadable plist shows "(unreadable plist)".
- **Output:** structured, key `count` (int); summary "No
  .xcsettings files found (default Xcode workspace settings
  apply)." when empty, else "Workspace settings files (N):\n-
  <rel>:\n    <key> = <value>\n…".
- **Errors:** none defined (an unreadable file is reported
  inline, not as a failure).

### 4.18 `xcode_build_settings_inspector` — Xcode Build Settings Inspector (read-only)

- **Description (verbatim):** "Inspects and extracts active
  build configuration settings, flags, and paths via xcodebuild."
- **Legacy source:** `AssistXcodeBuildSettingsTool.swift`.
  Capability `diagnostics`, risk `safeRead`, permission none.
- **Input:** `target` (string, "Optional target name to query
  build settings for."), `settingKey` (string, "Optional
  specific build setting key to extract (e.g.
  PRODUCT_BUNDLE_IDENTIFIER, SWIFT_VERSION).").
- **Behaviour:** merged raw settings (§3.4) for the project's
  default configuration (Legacy's bare `-showBuildSettings`
  shows the default configuration), optionally scoped to
  `target`. The 11 key settings in the summary are Legacy's:
  `TARGET_NAME`, `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`,
  `SWIFT_VERSION`, `IPHONEOS_DEPLOYMENT_TARGET`,
  `MACOSX_DEPLOYMENT_TARGET`, `SDK_NAME`, `ARCHS`,
  `CONFIGURATION`, `INFOPLIST_FILE`, `ENABLE_PREVIEWS`.
- **Output:** no data keys. Full — "### Active Xcode Build
  Settings:\n\n- **<key>**: `<value>`\n…" (only keys present).
  One key — "<key> = <value>". No pbxproj — success with "No
  Xcode build settings returned. Ensure an .xcodeproj exists in
  the workspace." (Legacy's empty-map success).
- **Errors:** `settingKey` absent → "Build setting '<key>'
  was not found in xcodebuild output."; named target absent →
  "Target '<target>' not found in project.pbxproj."
  (Legacy never checked `xcodebuild`'s exit status, so a bad
  target fell through to the empty-map success; the port fails
  plainly instead — §3.1).

### 4.19 `xcode_scheme_manager` — Xcode Scheme & Build Configuration Manager (read-only)

- **Description (verbatim):** "Inspects, lists, and queries
  Xcode schemes, targets, and build configurations in the
  workspace."
- **Legacy source:** `AssistXcodeSchemeTool.swift`. Capability
  `compilation`, risk `safeRead`, permission none.
- **Input:** `action` (string, required, "Action:
  'list_schemes', 'inspect_scheme'."), `schemeName` (string,
  "Scheme name to inspect (for 'inspect_scheme').").
- **Behaviour:** `list_schemes` (or `list`) lists the session
  model's schemes (§2) instead of running
  `xcodebuild -list`. `inspect_scheme` finds
  `<schemeName>.xcscheme` anywhere under the workspace root
  (first in sorted-path order) and returns its first 2000
  characters. Actions are matched case-insensitively, as in
  Legacy.
- **Output:** no data keys. List — "Xcode Schemes &
  Targets:\n<scheme>\n…". Inspect — "Scheme '<name>' found at
  <file>:\n\n<xml prefix>".
- **Errors:** missing `action` → "Missing required parameter:
  action"; other action → "Unsupported action '<action>'.
  Valid: list_schemes, inspect_scheme"; inspect without a
  name → "schemeName parameter is required for
  inspect_scheme"; scheme file absent → "Scheme file
  '<name>.xcscheme' not found in workspace."; package
  workspace for list → "No .xcodeproj or .xcworkspace found at
  the top level of the workspace."

## 5. Wiring

`projectModelTools` is a computed property on `YcodeMCPHost`
in `ycode/Sources/YcodeMCP/YcodeTools+ProjectModel.swift`. It
is NOT wired into `installTools()` by this slice — that file
is owned by the coordinator (19 tools, same IDs/schemas/
behaviour/risk as Legacy; the coordinator adds
`+ projectModelTools` to the `installTools()` chain and the
two Legacy aliases `xcode_scheme` →
`xcode_scheme_manager`, `build_settings` →
`xcode_build_settings_inspector` to `MCPServer.toolAliases`).

## 6. Evidence

| Claim | Level | Source |
|---|---|---|
| All 19 IDs, descriptions, schemas, capabilities, risk levels, and error messages | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistCreateNewAppTool.swift`, `AssistBuildProjectTool.swift` (incl. `AssistGenerateXcodeprojTool`), `AssistPbxprojLintTool.swift`, `AssistProjectBuildSettingsTool.swift`, `AssistProjectCapabilitiesTool.swift`, `AssistDiffTool.swift`, `AssistProjectMutationController.swift`, `AssistRestoreSnapshotTool.swift`, `AssistProjectSchemeListTool.swift`, `AssistSnapshotProjectTool.swift`, `AssistProjectStructureMapTool.swift`, `AssistProjectTargetAddTool.swift`, `AssistProjectTargetListTool.swift`, `AssistSchemeTestPlanListTool.swift`, `AssistTargetDependenciesListTool.swift`, `AssistTargetSourceListTool.swift`, `AssistWorkspaceSettingsReadTool.swift`, `AssistXcodeBuildSettingsTool.swift`, `AssistXcodeSchemeTool.swift`, read directly |
| Snapshot store layout (`AssistSnapshots/<uuid>/files` + `metadata.json` with `id`/`timestamp`/`message`/`rootPath`; restore deletes the workspace then copies back) | 1 | Legacy `SwiftCode/Backend/Assist/Functions/AssistSnapshotFunctions.swift`, read directly |
| Group resolution (exact match, then deepest prefix; parent-chain full paths) and Sources-phase resolution (first `/* Sources */` `PBXSourcesBuildPhase` in file order) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistXcodeProjectResolver.swift` (`groupID`, `sourcesBuildPhaseID`, `parseGroups`), read directly |
| Workspace scan semantics (skipped top-level dirs, 20,000-file cap, first pbxproj in enumerator order) and file-size helper | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistToolSharedHelpers.swift` (`AssistWorkspaceScan`), read directly |
| Aliases `xcode_scheme` → `xcode_scheme_manager`, `build_settings` → `xcode_build_settings_inspector`; no other aliases target this slice's 19 IDs | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` (`toolAliases`), read directly |
| No tool in this slice overrides `requiredPermission`, `prerequisites`, `outputFormat`, `supportedOperations`, or `knownLimitations` | 1 | grep over the 19 Legacy tool files (zero matches) |
| Ycode seams: `PBXProj` parsing/targets/configurations, typed mutations, `PBXProjWriter` serialisation | 1 | Destination `ycode/Sources/YcodeProject/PBXProj.swift`, `Mutations.swift`, `TargetMutations.swift`, `PBXProjWriter.swift`, read directly |
| Scheme model (`WorkspaceModel.schemeNames`, `projects`), new-project templates (`ProjectTemplates.all`, `ProjectGenerator.generate`), git runner (`runGit`), fixed-argv runner (`terminalRunFixed`), `commit()` / `approve()` gate | 1 | Destination `ycode/Sources/YcodeIDECore/Model/WorkspaceModel.swift`, `YcodeIDECore/Model/NewProject/ProjectGenerator.swift`, `ProjectTemplateDescriptors.swift`, `TemplateOptions.swift`, `ycode/Sources/YcodeMCP/YcodeTools+Git.swift`, `YcodeTools+TerminalSupport.swift`, `YcodeTools+Content.swift`, `specs/ide/assist-approval-model.md`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |


## Part C — SPM, dependencies & docs

Ycode modules: `YcodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 13 Legacy Assist
SPM/dependency/docs tools ported in Wave 7, slice C:
`swift_package_manager`, `package_manifest_read`,
`package_manifest_validate`, `package_dependency_add`,
`package_dependency_audit`, `package_dependency_update`,
`spm_dependency_tree`, `carthage_cartfile_inspector`,
`podfile_inspector`, `docc_build`, `docs_generate`,
`docs_index_build`, `project_changelog`. The implementation is
`ycode/Sources/YcodeMCP/YcodeTools+SPMDocs.swift`; the tests are
`ycode/Tests/YcodeMCPTests/YcodeSPMDocsTests.swift`.

The per-tool sections below are catalogue-ready: each gives the
tool's description and input schema verbatim (Legacy's
`parametersSchema` plus the `workspace` parameter every Ycode tool
carries), its output shape, and its error cases, so the coordinator
can merge them into `specs/ide/assist-tool-catalogue.md` without
re-deriving anything.

Scope: what each tool does once called, what it returns, what it
refuses, and which Ycode seam it runs through. The approval model
itself (write policy, `commit()` / `approve()`, the rejected
Autopilot bypass) is `specs/ide/assist-approval-model.md` and is
not repeated here beyond the per-tool gate column.

## 1. Conventions shared by the slice

- **IDs, titles, descriptions, schemas are Legacy's verbatim**,
  verified live from each Legacy tool file (see Evidence). The
  only additions are the `workspace` parameter and Ycode's
  `additionalProperties: false`. Legacy's parameter-name aliases
  are NOT supported: Ycode's argument validation rejects unknown
  arguments before the handler runs.
- **Structured data keeps Legacy's keys, with typed JSON values**
  (integers, booleans) the way Ycode's other tools do — Legacy's
  string-only map is not reproduced. Tools whose Legacy result
  carries no data return a plain text result instead.
- **Paths resolve through the session resolver**
  (`resolveFileReadingPath`) and never escape the workspace, with
  the deviations documented per tool below. Legacy's per-tool
  resolvers rejected any `..` as text; the session resolver
  resolves `..` and then checks containment, so a `..` that stays
  inside the workspace resolves here (the same deviation Wave 6
  recorded for its log tools). A path the resolver refuses fails
  with Legacy's own message for that tool.
- **Subprocess tools run a fixed argument vector, never a shell**,
  through the fixed-argv runner from
  `YcodeTools+TerminalSupport.swift` (`terminalRunFixed`, off the
  main actor), and report the tool's actual output — no result is
  ever invented. Legacy waited unboundedly; this port bounds
  `swift package` runs at 300 s and `xcodebuild docbuild` at
  600 s and fails on timeout. A missing toolchain fails honestly
  with the prerequisite named.
- **Approval gating:** the two writing tools
  (`package_dependency_add`, `docs_generate`) are `writes: true`
  with `safeMutation` annotations. Manifest edits go through
  `commit()`; the generated doc goes through `commit()` too. In
  `readOnly` mode both are refused in `run()` before the handler.
  There is no Autopilot bypass.
- **YcodeProject reuse:** `YcodeProject.PackageDependencies`
  (`SwiftPackageReference`, `SwiftPackageRequirement`,
  `PBXProj.addRemotePackage` / `addPackageProduct`) models
  package references *in a `.pbxproj`* — Xcode-project package
  references, not `Package.swift` text. This slice does not build
  a parallel package model: `Package.swift` is edited as text
  exactly as Legacy edits it, and the audit/tree tools parse the
  same files Legacy parses. Wiring a dependency into an Xcode
  project's `packageReferences` is not Legacy behaviour for these
  tools and is not done here; it belongs with the project/Xcode
  slice that owns `pbxproj` mutation.
- **Legacy aliases for this slice** (from
  `AssistToolRegistry.toolAliases`; wiring them into
  `MCPServer.toolAliases` is the coordinator's job, not this
  slice's): `swift_package` → `swift_package_manager`,
  `spm` → `swift_package_manager`,
  `spm_tree` → `spm_dependency_tree`,
  `podfile` → `podfile_inspector`,
  `cartfile` → `carthage_cartfile_inspector`. No aliases exist
  for `package_manifest_read`, `package_manifest_validate`,
  `package_dependency_add`, `package_dependency_audit`,
  `package_dependency_update`, `docc_build`, `docs_generate`,
  `docs_index_build`, or `project_changelog`.

## 2. `swift_package_manager` — execution, read-only flag

- Legacy: `AssistSwiftPackageTool`, capability `compilation`,
  risk `execution`. Description: "Inspects, resolves, updates,
  and validates Swift Package Manager (SPM) dependencies."
- Input: `action` (required; `resolve`, `update`, `status`,
  `dump_manifest`, `describe`), `packageDir` (workspace-relative
  directory containing `Package.swift`, defaults to the workspace
  root).
- Behaviour: `packageDir` resolves through the session resolver
  (empty means the workspace root); the tool fails with
  `Package.swift not found at <absolute path>` when the directory
  has no `Package.swift`. The action maps to a fixed argv vector
  (`swift package resolve|update|status|dump-package|describe`,
  case-insensitive action match, `dump_manifest` → `dump-package`).
  An unknown action fails with
  `Unsupported action '<action>'. Valid: resolve, update, status, dump_manifest, describe`.
  A missing swift binary fails honestly with
  `Swift not found at /usr/bin/swift.` (the prerequisite is named;
  the run is not faked). Exit 0 returns stdout verbatim, or
  `SPM <action> completed successfully.` when stdout is empty;
  non-zero fails with
  `SPM <action> failed with code <code>:\n<stderr>\n<stdout>`.
  A run that cannot start fails with
  `Failed to execute swift package: <error>`.
- Output: plain text (Legacy carries no data keys).
- Note: `resolve`/`update` can rewrite `Package.resolved` on
  disk as a side effect of the real `swift` invocation — that is
  the subprocess's own behaviour, not a `commit()` write, exactly
  as Legacy runs it; the tool is therefore `writes: false` with
  the `execution` annotation, like the other execution tools.

## 3. `package_manifest_read` — safeRead

- Legacy: `AssistPackageManifestReadTool`, capability
  `compilation`, risk `safeRead`. Description: "Reads Package.swift
  and summarizes the package name, platforms, products, targets,
  and dependencies."
- Input: `path` (workspace-relative path to `Package.swift`,
  default `"Package.swift"`).
- Behaviour: the manifest is read as UTF-8 text and summarised
  with Legacy's extractors, kept verbatim:
  - package name: the first quoted string after the first
    `name:` in the file (`"unknown"` when absent);
  - platforms: each of `iOS`, `macOS`, `watchOS`, `tvOS`,
    `visionOS`, `linux` whose `.<platform>(` occurs, in that
    order;
  - products: quoted `name:` values after the first
    `products:` marker (cap 200);
  - targets: quoted `name:` values after the first `targets:`
    marker (cap 500);
  - dependencies: the quoted `url:` of each `.package(` entry
    (cap 200);
  - `productCount` counts `.library(` + `.executable(`;
    `targetCount` counts `.target(` + `.testTarget(` +
    `.executableTarget(` + `.binaryTarget(` + `.macro(`.
- Errors: `Invalid path '<path>': must be inside the workspace
  and must not contain '..'.` (resolver refusal),
  `Package manifest not found at '<path>'.`,
  `Failed to read Package.swift at '<path>'.`.
- Output data keys (Legacy's, typed): `packageName` (string),
  `platforms` (comma-joined string), `products` (comma-joined),
  `targets` (comma-joined), `dependencies` (comma-joined),
  `productCount` (int), `targetCount` (int),
  `dependencyCount` (int). Summary lines:
  `Package: <name>`, `Manifest: <path>`,
  `Platforms: <list or "none declared">`,
  `Products (<n>): <list or "none">`,
  `Targets (<n>): <list or "none">`,
  `Dependencies (<n>): <list or "none">`.

## 4. `package_manifest_validate` — safeRead, subprocess

- Legacy: `AssistPackageManifestValidateTool`, capability
  `compilation`, risk `safeRead`. Description: "Validates
  Package.swift by running swift package dump-package and
  reporting the package name and target count."
- Input: `path` (workspace-relative path to `Package.swift`,
  default `"Package.swift"`).
- Behaviour: fails honestly with
  `Swift not found at /usr/bin/swift.` when `/usr/bin/swift`
  is absent. The manifest must exist
  (`Package manifest not found at '<path>'.`) and its directory
  must be inside the workspace
  (`Manifest directory is outside the workspace.`). Runs
  `swift package dump-package` in the manifest's directory as a
  fixed argv vector (300 s bound). A non-zero exit fails with
  `Package manifest is invalid: swift package dump-package
  exited with code <code>.\n<stderr tail, last 2000 chars>`.
  On success the stdout JSON supplies `name` and the `targets`
  count (`"unknown"` / 0 when the JSON lacks them).
- Output data keys (typed): `packageName` (string),
  `targetCount` (int), `exitCode` (int). Summary:
  `Package manifest is valid: <name> with <n> target(s).`
- Annotation is `execution` (it runs a subprocess), even though
  Legacy's risk is `safeRead`; the tool writes nothing and is
  `writes: false`.

## 5. `package_dependency_add` — safeMutation, writes: true

- Legacy: `AssistPackageDependencyAddTool`, capability
  `compilation`, risk `safeMutation`. Description: "Inserts a
  `.package(url:from:)` entry into the dependencies array in
  Package.swift."
- Input: `url` (required), `requirement` (default
  `from: "1.0.0"`), `product` (optional), `target` (optional).
- Behaviour (Legacy's text edit, kept verbatim, then written
  through `commit()`):
  - `url` must be non-empty and contain no space, newline, or
    quote: `Invalid url: must not contain spaces, newlines, or quotes.`
  - Requirement normalisation: empty → `from: "1.0.0"`; a bare
    version (quotes stripped) → `from: "<version>"`; a value
    already starting with `from:` / `exact:` / `branch:` /
    `revision:` / `upToNextMajor` / `upToNextMinor` / `range:`
    (case-insensitive prefix) is kept as-is.
  - The workspace-root `Package.swift` must exist
    (`Package.swift not found in the workspace root.`) and be
    readable (`Failed to read Package.swift.`).
  - When the URL is already in the manifest, success with no
    write: `Dependency already present in Package.swift: <url>`,
    data `alreadyPresent: true`.
  - The `dependencies:` array is the first `[` … `]` after the
    first `dependencies:` marker; when there is none the tool
    fails with `Could not find a 'dependencies:' array in
    Package.swift. Add one manually first.` The entry
    `.package(url: "<url>", <requirement>)` is inserted
    (empty array → a one-entry array; otherwise appended after a
    comma when the existing content lacks a trailing comma).
    Insertion failure: `Failed to insert the dependency into the dependencies array.`
  - Target wiring (only when both `product` and `target` are
    non-empty): the product string is inserted into the
    `dependencies:` array following the first
    `name: "<target>"` occurrence; when that array is absent the
    package is still added and the note records
    `package added but target '<target>' dependencies array not found; product '<product>' not wired`.
    When only one of `product`/`target` is given the note is
    `both product and target are required for target wiring; package added without wiring`.
    A product already present in the target's array counts as
    wired. The wiring note is `wired product '<product>' into target '<target>'` on success, `none` otherwise.
  - The whole new manifest text goes through one `commit()` with
    summary `Add dependency <url> to Package.swift`; a review
    refusal throws `rejectedMessage` and writes nothing. After
    the write the file is re-read and verified to contain the
    URL (`Verification failed: url not present in Package.swift after write.`).
- Output data keys (Legacy's): `url` (string), `requirement`
  (string), `targetWiring` (string); the already-present case
  also carries `alreadyPresent` (bool, typed — Legacy's `"true"`
  string is not reproduced).
- Deviation: Legacy edits only the workspace-root
  `Package.swift` (it takes no path argument); this port keeps
  that — there is no `path` parameter to add.

## 6. `package_dependency_audit` — safeRead

- Legacy: `AssistPackageDependencyAuditTool`, capability
  `diagnostics`, risk `safeRead`. Description: "Audits Swift
  package dependencies from Package.swift and Package.resolved,
  flagging missing pins and unpinned requirements."
- Input: none.
- Behaviour: reads the workspace-root `Package.swift`
  (`Package.swift not found in the workspace root.` /
  `Failed to read Package.swift.`). Declared dependencies are
  extracted with Legacy's scanner (each `.package(` entry, 600
  chars of context, cap 200): `url:` quoted string; requirement
  kind from the first of `exact:` / `from:` / `upToNextMajor` /
  `upToNextMinor` / `branch:` / `revision:` / `range:` present
  (`"unknown"` otherwise); only `exact:` counts as exact; the
  dependency name is the URL's last path component without
  `.git`. `Package.resolved` (when present) is parsed in both
  shapes — top-level `pins` (v2/v3) and nested `object.pins`
  (v1) — keyed by lowercase `identity` (falling back to
  `package`), with the version from `state.version` (falling
  back to `state.revision`). Flags: `Missing Package.resolved:
  dependencies are not pinned to exact revisions.` when the
  file is absent, plus one
  `Declared dependency not in Package.resolved: <url>` per
  declared dependency missing from the pins. `swift package
  show-dependencies` output (last 2000 chars) is appended when
  the run succeeds; any failure (no swift, non-zero exit,
  cannot start) contributes nothing — never an error.
- Output data keys (typed): `declaredCount` (int),
  `pinnedCount` (int), `hasResolved` (bool),
  `unpinnedCount` (int), `unpinned` (comma-joined URLs),
  `flags` (semicolon-joined). Summary: the declared/pinned
  counts, whether `Package.resolved` is present, the
  exact/non-exact counts, one `- <url> (requirement: <kind>,
  resolved: <version or "unpinned">)` line per dependency, the
  flags, and the `show-dependencies` output when available.

## 7. `package_dependency_update` — execution, read-only flag

- Legacy: `AssistPackageDependencyUpdateTool`, capability
  `compilation`, risk `execution`. Description: "Runs swift
  package update in the workspace root to update Swift package
  dependencies."
- Input: `package` (optional single dependency name; when
  omitted, all dependencies are updated).
- Behaviour: fails honestly with
  `Swift not found at /usr/bin/swift.` when the binary is
  absent, and `Package.swift not found in the workspace root.`
  when the manifest is absent. A non-empty `package` must be a
  single name without spaces, slashes, or `..`:
  `Invalid package name: must be a single dependency name without spaces, slashes, or '..'.`
  Runs `swift package update [<package>]` in the workspace root
  as a fixed argv vector (300 s bound). Exit 0 succeeds with
  `swift package update succeeded (exit 0).\n<combined output tail, last 2000 chars>`;
  non-zero fails with
  `swift package update failed with exit code <code>.\n<tail>`.
  A run that cannot start fails with
  `Failed to start swift package update: <error>`.
- Output data keys: `exitCode` (int, typed — Legacy's string is
  not reproduced), `outputTail` (string), on success only.
- Note: as with `swift_package_manager`, the update rewrites
  `Package.resolved` as the subprocess's own side effect; the
  tool is `writes: false` with the `execution` annotation.

## 8. `spm_dependency_tree` — safeRead

- Legacy: `AssistSPMDependencyTreeTool`, capability
  `diagnostics`, risk `safeRead`. Description: "Parses
  Package.resolved and Package.swift to construct the complete
  resolved dependency tree."
- Input: `path` (optional explicit path to `Package.resolved`;
  when omitted, the workspace is searched).
- Behaviour: an explicit path resolves through the session
  resolver (absolute inside the workspace as-is; otherwise
  workspace-root-relative). Without one, the candidates are
  checked in order — `Package.resolved`,
  `.swiftpm/xcode/package.resolved`,
  `SwiftCode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  (Legacy's third candidate is kept verbatim even though it
  names the old project) — then a workspace enumeration for a
  file named `package.resolved` (case-insensitive). When no
  file is found, or it cannot be read/parsed as JSON, the tool
  succeeds with `No Package.resolved file found in workspace.`
  (Legacy's success-with-message, not a failure). Pins are read
  in both shapes: top-level `pins` (v2/v3: `identity` falling
  back to `package`; `location` falling back to
  `repositoryURL`; `state.version` default `"unversioned"`;
  `state.revision` truncated to 8 chars) and nested
  `object.pins` (v1: `package`, `repositoryURL`, same state
  rules). The report is Legacy's markdown verbatim:
  `### SPM Dependency Tree (\`<relative path>\`):` then
  `- **Total Resolved Packages**: <n>` then, sorted by
  identity, `- **<identity>** @ \`<version>\` (<revision>)`
  with `  - URL: \`<location>\``.
- Output: plain text (Legacy carries no data keys).

## 9. `carthage_cartfile_inspector` — safeRead

- Legacy: `AssistCarthageCartfileInspectorTool`, capability
  `diagnostics`, risk `safeRead`. Description: "Inspects
  Carthage dependencies and resolved versions in Cartfile and
  Cartfile.resolved."
- Input: none.
- Behaviour: reads `Cartfile` and `Cartfile.resolved` in the
  workspace root only. When neither exists, success with
  `No Carthage Cartfile or Cartfile.resolved found in workspace root.`
  Otherwise the report is Legacy's markdown verbatim:
  `### Carthage Dependencies Report:` then, for `Cartfile`,
  `#### Declared in Cartfile:` with one
  `- \`<line>\`` per non-empty, non-`#` line, and for
  `Cartfile.resolved`, `#### Resolved in Cartfile.resolved:`
  with one `- \`<line>\`` per non-empty line (comments are
  kept in the resolved file, as in Legacy).
- Output: plain text (Legacy carries no data keys).

## 10. `podfile_inspector` — safeRead

- Legacy: `AssistPodfileInspectorTool`, capability
  `diagnostics`, risk `safeRead`. Description: "Inspects
  CocoaPods dependencies, versions, and target configurations
  in Podfile and Podfile.lock."
- Input: `path` (optional directory containing the Podfile;
  defaults to the workspace root).
- Behaviour: reads `Podfile` and `Podfile.lock` in the
  workspace root only. When neither exists, success with
  `No CocoaPods Podfile or Podfile.lock found in workspace root.`
  The report is Legacy's markdown verbatim:
  `### CocoaPods Project Inspection:` then
  `#### Declared Pods in Podfile (<n>):` with one
  `- \`<trimmed pod line>\`` per line whose trimmed form starts
  with `pod `, then `#### Locked Pod Versions (<n>):` with the
  `  - ` entries of the lockfile's `PODS:` section (up to 20),
  stopping at the first line after `PODS:` that is neither a
  `  - `/`    - ` entry nor blank nor indented. (A line that
  starts a new top-level section ends the section; a blank
  line inside it does not — Legacy's exact loop condition.)
- Deliberate quirk preserved: Legacy declares the `path`
  parameter but never reads it — the tool always inspects the
  workspace root. This port keeps that behaviour (and the
  schema) rather than inventing a directory parameter that
  Legacy never honoured.
- Output: plain text (Legacy carries no data keys).

## 11. `docc_build` — execution, read-only flag

- Legacy: `AssistDoccBuildTool`, capability `compilation`,
  risk `execution`. Description: "Builds DocC documentation
  with xcodebuild docbuild and verifies a .doccarchive was
  produced."
- Input: `scheme` (required), `destination` (default
  `platform=macOS`), `outputPath` (workspace-relative
  derived-data directory, default `.docc-derived`).
- Behaviour: `scheme` must be non-empty
  (`Missing required parameter: scheme`) and contain no newline
  (`Invalid scheme: scheme must not contain newlines.`).
  `outputPath`, when given, must resolve inside the workspace
  without `..`:
  `Invalid outputPath: '<outputPath>' must be a workspace-relative path without '..' and must stay inside the workspace.`
  The tool fails honestly with
  `xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.`
  when xcodebuild is absent (on Linux this is the expected
  outcome — the build is not faked). Runs
  `xcodebuild docbuild -scheme <scheme> -destination <destination> -derivedDataPath <derived-data path>`
  as a fixed argv vector (600 s bound) in the workspace root.
  Non-zero exit fails with
  `xcodebuild docbuild failed (exit <code>, scheme: <scheme>): <stderr tail, last 2000 chars>`.
  On exit 0 the derived-data directory is searched for
  `.doccarchive` bundles; when none is found the tool fails
  with `xcodebuild docbuild succeeded but no .doccarchive was found under <path>.`
  The first archive in sorted path order wins.
- Output data keys (Legacy's): `scheme` (string),
  `destination` (string), `archive_path` (string, absolute),
  `archive_relative` (string, workspace-relative). Summary:
  `DocC build succeeded for scheme <scheme>. Archive: <relative path>`.

## 12. `docs_generate` — safeMutation, writes: true

- Legacy: `AssistDocsGenerateTool`, capability
  `fileModification`, risk `safeMutation`. Description:
  "Generates a markdown API document from public Swift
  declarations in the workspace. Refuses to overwrite unless
  overwrite is true."
- Input: `outputPath` (workspace-relative output path, default
  `DOCS_GENERATED.md`), `title` (optional, default
  `Generated API Documentation`), `overwrite` (string; must be
  `"true"` to replace an existing file, default `"false"`).
- Behaviour (Legacy's generator, kept verbatim, written through
  `commit()`): `outputPath` must resolve inside the workspace
  without `..`:
  `Invalid outputPath: '<path>' must be a workspace-relative path without '..' and must stay inside the workspace.`
  An existing output file without `overwrite=true` fails with
  `Refusing to overwrite existing file at '<path>'. Pass overwrite=true to replace it.`
  Swift files are enumerated recursively under the workspace
  root, skipping hidden files and the directories `.git`,
  `DerivedData`, `.build`, `Pods`, `node_modules`, `.swiftpm`,
  `Carthage`, `vendor`, sorted by path. Each file contributes a
  `## <relative path>` section with its leading `//` header
  lines (up to the first 5 lines, stopping at the first
  non-comment, non-blank line) and one
  `- \`<declaration>\`` line per `public ` line containing one
  of `struct `, `class `, `enum `, `protocol `, `actor `,
  `func `, `var `, `let `, `extension `, truncated at the first
  `{` and at 200 chars; a file with none gets
  `_No public declarations found._`. The document header is
  `# <title>` with `- Generated: <ISO 8601 date>`,
  `- Workspace: <absolute workspace path>`,
  `- Swift files: <n>`, `- Public declarations: <n>`; with no
  Swift files the body is `_No Swift files found in the workspace._`.
  The whole document goes through one `commit()`; a review
  refusal throws `rejectedMessage` and writes nothing. A write
  failure reports
  `Failed to write docs to '<path>': <error>`.
- Output data keys (typed): `output_path` (string, absolute),
  `output_relative` (string), `file_count` (int),
  `declaration_count` (int). Summary:
  `Generated docs for <n> Swift file(s), <m> public declaration(s), at <relative path>`.
- Note: `overwrite` stays a string in the schema, as in Legacy;
  only the exact value `"true"` (case-insensitive) overwrites.
  The `Generated:` timestamp means the document always differs
  from any previous run, so `commit()` always performs the
  write after approval.

## 13. `docs_index_build` — safeRead

- Legacy: `AssistDocsIndexBuildTool`, capability `fileReading`,
  risk `safeRead`. Description: "Builds an index of all Markdown
  files in the workspace: path, title (first heading), and size."
- Input: none.
- Behaviour: Markdown files (`.md`, `.markdown`) are enumerated
  recursively under the workspace root, skipping hidden files,
  sorted by path. When there are none, success with
  `No Markdown files found in the workspace.` and `count` 0.
  Each file contributes a table row: workspace-relative path,
  title (the first line starting with `# `, with the prefix
  stripped, truncated to 80 characters; `"(no title)"` when no
  such line or the file is unreadable), and byte size. The table
  is Legacy's markdown table shape:
  `| Path | Title | Bytes |` with a `| --- | --- | --- |`
  separator row and one `| <path> | <title> | <bytes> |` row
  per file.
- Output data keys (typed): `count` (int). Summary:
  `Markdown index (<n> files):\n<table>`.

## 14. `project_changelog` — safeRead

- Legacy: `AssistChangeLogTool`, capability `general`, risk
  `safeRead`. Description: "Displays the history of project
  snapshots and changes."
- Input: none (Legacy declares no `parametersSchema` at all, so
  the protocol default — an empty object — applies).
- Behaviour: Legacy lists snapshots from
  `AssistSnapshotFunctions.listSnapshots()`, whose store is the
  global (not workspace-scoped)
  `<Application Support>/AssistSnapshots/<id>/metadata.json`
  directory. Ycode has no snapshot store — no Ycode tool creates
  snapshots (the same fact Wave 6 records for `safe_undo`) —
  so this port reads that same directory read-only and reports
  what is there, instead of inventing history: each
  `metadata.json` (`id`, `timestamp`, `message`, `rootPath`,
  JSON-encoded with the default `JSONEncoder` date encoding)
  contributes one ` [<timestamp>] <message> (ID: <id>)` line,
  newest first. When the directory is absent or holds no
  readable metadata, the tool succeeds with Legacy's empty
  case: summary `Changelog retrieved successfully.` and `log`
  `No snapshot history found.` The directory is never created
  by this tool (Legacy's `listSnapshots` creates it; this port
  treats a missing directory as empty). This is a deliberate
  read-only exception to workspace confinement, like
  `preflight_checks` reading DerivedData: the snapshot history
  is the user's own global history, not workspace content, and
  Legacy itself is workspace-independent here.
- Output data keys (Legacy's): `log` (string — the joined lines,
  or `No snapshot history found.`).

## 15. Honestly-failing cases (no silent success)

| Tool | Condition | Failure |
|---|---|---|
| `swift_package_manager` | `/usr/bin/swift` absent | `Swift not found at /usr/bin/swift.` |
| `swift_package_manager` | run times out (300 s) | `SPM <action> timed out after 300 seconds.` |
| `package_manifest_validate` | `/usr/bin/swift` absent | `Swift not found at /usr/bin/swift.` |
| `package_manifest_validate` | run times out (300 s) | `swift package dump-package timed out after 300 seconds.` |
| `package_dependency_update` | `/usr/bin/swift` absent | `Swift not found at /usr/bin/swift.` |
| `package_dependency_update` | run times out (300 s) | `swift package update timed out after 300 seconds.` |
| `docc_build` | `/usr/bin/xcodebuild` absent (Linux, or Xcode not installed) | `xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.` |
| `docc_build` | run times out (600 s) | `xcodebuild docbuild timed out after 600 seconds.` |
| `docc_build` | exit 0 but no `.doccarchive` | `xcodebuild docbuild succeeded but no .doccarchive was found under <path>.` |
| `package_dependency_audit` | `swift` absent / `show-dependencies` fails | No failure: the section is omitted (Legacy behaviour). |

No tool in this slice is registered-but-always-failing: every
tool performs its local logic, and the subprocess tools run the
real tooling when it is present and fail honestly when it is not.

## 16. Deliberate deviations from Legacy

- Session-resolver `..` handling (§1): a `..` that stays inside
  the workspace resolves; Legacy's per-tool resolvers rejected
  any `..` as text.
- `spm_dependency_tree` explicit absolute path: Legacy used it
  as-is even outside the workspace; the session resolver falls
  back to a workspace-root-relative reading for an absolute path
  outside the workspace.
- `package_dependency_audit` / `spm_dependency_tree` /
  `docs_index_build`: Legacy's data values are strings
  (`"true"`, `"3"`); Ycode returns typed booleans/integers.
- `package_dependency_add` already-present `alreadyPresent` is
  a typed boolean, not Legacy's `"true"` string.
- `package_manifest_validate` carries the `execution`
  annotation (it spawns `swift`); Legacy's risk is `safeRead`
  and the tool still writes nothing.
- `project_changelog` does not create the snapshots directory
  when it is missing (Legacy's `listSnapshots` does); a missing
  directory reads as empty history.
- `docs_generate` / `package_dependency_add` write through
  `commit()` (atomic temp-file + rename, parent creation,
  session notification) instead of Legacy's direct write; the
  generated doc's timestamp means the write is never skipped as
  a no-op. Legacy's `LiveDiffStreamer` broadcasts and
  `XcodeProjWriter.addFileReference` side effects are not
  ported (approval-model §7.4).
- `swift_package_manager` / `package_dependency_update` /
  `package_manifest_validate` / `package_dependency_audit`
  (show-dependencies) / `docc_build` run through Ycode's
  `terminalRunFixed` with a timeout; Legacy waited unboundedly
  and read its pipes directly.

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 13 IDs, titles, descriptions, schemas, capabilities, risk levels, error messages, output keys, and per-tool algorithms above | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistSwiftPackageTool.swift`, `AssistPackageManifestReadTool.swift`, `AssistPackageManifestValidateTool.swift`, `AssistPackageDependencyAddTool.swift`, `AssistPackageDependencyAuditTool.swift`, `AssistPackageDependencyUpdateTool.swift`, `AssistSPMDependencyTreeTool.swift`, `AssistCarthageCartfileInspectorTool.swift`, `AssistPodfileInspectorTool.swift`, `AssistDoccBuildTool.swift`, `AssistDocsGenerateTool.swift`, `AssistDocsIndexBuildTool.swift`, `AssistChangeLogTool.swift`, read directly |
| Snapshot store shape (`AssistSnapshots` under Application Support, `metadata.json` with `id`/`timestamp`/`message`/`rootPath`, `listSnapshots` sorts newest-first, creates the directory) | 1 | Legacy `SwiftCode/Backend/Assist/Functions/AssistSnapshotFunctions.swift` and `Models/AssistSnapshotModels.swift`, read directly |
| Legacy aliases for this slice | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` `toolAliases` (lines 430–554), read directly |
| Ycode has no snapshot store; `safe_undo` honestly fails for that reason | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+ReviewDocs.swift` header + `safeUndo`, read directly |
| `YcodeProject` models pbxproj package references, not `Package.swift` text | 1 | Ycode `ycode/Sources/YcodeProject/PackageDependencies.swift`, read directly |
| `commit()` / `approve()` / `readOnlyMessage` / `rejectedMessage` / `terminalRunFixed` (fixed argv, timeout) / `resolveFileReadingPath` | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Content.swift`, `YcodeTools+TerminalSupport.swift`, `YcodeTools+FileReadingSupport.swift`, `MCPServer.swift`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |


## Part D — Signing, entitlements & plist

Date: 2026-11-06. Destination: `~/workspace/repos/SwiftCode-Mac`, main @
`2e88bc04` (Ycode base, SwiftPM). Source (read-only): Legacy
`SwiftCode/Backend/Assist/Tools/`, main @ `d51a8f0d`.
Implementation: `ycode/Sources/YcodeMCP/YcodeTools+Signing.swift`
(`signingTools`); tests: `ycode/Tests/YcodeMCPTests/YcodeSigningToolsTests.swift`.

Scope: exactly these 11 Legacy Assist tool IDs, verified live from each
Legacy tool file's `id` (no additions, no drops):

`code_signing_diagnose`, `entitlements_diff`, `entitlements_manager`,
`info_plist_audit`, `plist_editor`, `project_entitlements`,
`project_info_plist`, `project_signing`, `provisioning_check`,
`provisioning_profile_reader`, `signing_certificate_inspector`.

## Conventions shared by the slice

- IDs, titles, descriptions and schemas are Legacy's `parametersSchema`
  verbatim, plus the `workspace` parameter every Ycode tool carries.
  Legacy's parameter-name aliases are NOT supported: Ycode's argument
  validation rejects unknown arguments before the handler runs (same as
  Waves 1–6).
- Structured data keeps Legacy's keys. Typed JSON values (integers,
  booleans) replace Legacy's string-only map, the way Waves 1–6 do it.
  Tools whose Legacy result carries no data return a plain text result.
- Paths resolve through the session resolvers and never escape the
  workspace, with the documented read-only exceptions below
  (`provisioning_profile_reader` accepts an explicit absolute path
  as-is, like Wave 6's `test_coverage_reporter`; `project_signing`
  and `provisioning_check` read the user's own
  `~/Library/MobileDevice/Provisioning Profiles` directory, which is
  outside any workspace by definition).
- Approval gating (the one gate, `specs/ide/assist-approval-model.md`):
  the three writing tools (`entitlements_manager`, `plist_editor`,
  `project_info_plist`) are `writes: true` with `safeMutation`
  annotations. Text writes go through `commit()`; binary-plist writes
  (a `plist_editor` set/delete that preserves a binary source format)
  go through `approveFileWritingChange` + a direct `Data` write, the
  `json_to_plist` shape. `MCPServer.run()` already refuses `writes:
  true` tools when the server is read-only; the approval call is still
  required. There is no Autopilot bypass. Because the `writes` flag is
  static per tool, the read-only actions of the writing tools
  (`entitlements_manager` inspect/list, `plist_editor` read/list_keys,
  `project_info_plist` get) are refused in `readOnly` mode too — the
  same documented consequence as Wave 6's `test_snapshot_manage`
  `list`.
- External processes run through the fixed-argv runner from
  `YcodeTools+TerminalSupport.swift` (`terminalRunFixed`, off the main
  actor, no shell, bounded timeout): `/usr/bin/codesign`,
  `/usr/bin/security`. No process is ever spawned from a shell string.
- Signing/certificate/provisioning inspection reads the local keychain
  and installed profiles and reports real state. Nothing invents
  credentials or identities, and no secret material is ever emitted:
  `signing_certificate_inspector` reports only the names and SHA-1
  hashes `security find-identity` itself prints; the provisioning
  tools report profile metadata and entitlements only — never the
  `DeveloperCertificates` blobs.
- YcodeSigning seam check: `ycode/Sources/YcodeSigning` exists
  (`ProvisioningProfile`, `SigningIdentity`, `CertificateSummary`,
  `EntitlementPolicy`/`EntitlementValue`), but `YcodeMCP` has no target
  dependency on it and `Package.swift` is out of scope for this slice,
  so no parallel signing model was built and those types are not
  imported. The slice instead reuses seams `YcodeMCP` already depends
  on directly: `YcodeProject` + `YcodeSettings`
  (`ProjectSettingsBuilder`, the same seam the `build_settings` tool
  uses) for `project_signing`, and Foundation
  `PropertyListSerialization` + the fixed-argv `security`/`codesign`
  runners for the rest. If a later wave adds `YcodeSigning` to
  `YcodeMCP`'s dependencies, `provisioning_profile_reader` /
  `provisioning_check` are the candidates to move onto
  `ProvisioningProfile`'s pure-Swift CMS decode (which would also make
  them work on Linux); that is recorded here, not done here.

## Legacy aliases for these 11 IDs

From Legacy `AssistToolRegistry.swift` `toolAliases` (only entries whose
target is one of this slice's IDs):

| Alias | Target |
|---|---|
| `plist` | `plist_editor` |
| `entitlements` | `entitlements_manager` |
| `signing_certificate` | `signing_certificate_inspector` |
| `provisioning_profile` | `provisioning_profile_reader` |

No aliases exist for `code_signing_diagnose`, `entitlements_diff`,
`info_plist_audit`, `project_entitlements`, `project_info_plist`,
`project_signing`, `provisioning_check`. Aliases live in
`MCPServer.toolAliases`, which the coordinator owns — they are not
added in this slice.

## Ledger rows (format per `ledgers/MIGRATION_FEATURE_PARITY.md`)

| Legacy path | Disposition | Destination | Status |
|---|---|---|---|
| `SwiftCode/Backend/Assist/Tools/AssistCodeSigningDiagnoseTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (code_signing_diagnose) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistEntitlementsDiffTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (entitlements_diff) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistEntitlementsTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (entitlements_manager) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistInfoPlistAuditTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (info_plist_audit) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistPlistTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (plist_editor) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistProjectEntitlementsTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (project_entitlements) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistProjectInfoPlistTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (project_info_plist) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistProjectSigningTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (project_signing) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistProvisioningCheckTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (provisioning_check) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistProvisioningProfileReaderTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (provisioning_profile_reader) | IMPLEMENTED |
| `SwiftCode/Backend/Assist/Tools/AssistSigningCertificateInspectorTool.swift` | MIGRATE_AND_ADAPT | ycode/Sources/YcodeMCP/YcodeTools+Signing.swift (signing_certificate_inspector) | IMPLEMENTED |

## 1. `code_signing_diagnose` — Code Signing Diagnose

- Description (verbatim): "Diagnoses code-signing state of a built
  .app/.framework: signature validity, authority chain, team identifier,
  and hardened-runtime flags."
- Schema: `path` (string, "Workspace-relative path to the .app,
  .framework, or binary."), required: [`path`].
- Capability: diagnostics. Risk: safeRead. Permission (Legacy-derived):
  none. Read-only; `writes: false`.
- Behaviour: runs `/usr/bin/codesign -dv --verbose=4 <path>` (fixed
  argv, 60 s timeout) and parses the `key=value` lines. `codesign -dv`
  writes its report to stderr, so stdout and stderr are combined
  before parsing (Legacy's runner merged both streams). Findings, in
  Legacy order: "NOT SIGNED: the product has no code signature." when
  the output says so; otherwise, on exit 0, "Signature present and
  verifiable by codesign."; "Ad-hoc signature: distribution and
  notarization will fail; use a Developer ID or App Store identity."
  when the signature is adhoc; "Team identifier: <team>" or "No team
  identifier embedded."; "Hardened runtime flag detected." when
  `flags=0x10000` or `runtime` appears. The message is "Code signing
  diagnosis for <path> (exit <code>):" followed by the findings, plus
  "- Authority: …", "- Identifier: …", "- Format: …" when present.
- Outputs/data keys: `exitCode` (int), `teamIdentifier` (string, `""`
  when absent), `authority` (string, `""` when absent), `signed`
  (bool). Legacy's data values were strings; the keys are unchanged.
- Errors: "Missing required parameter: path" (blank path);
  "No file at path: <path>" (resolver refuses it or the file does not
  exist); "Failed to run codesign: <detail>" (the fixed-argv runner
  could not launch it); "codesign timed out after 60s on <path>."
- Honestly-failing case: on a host without `/usr/bin/codesign`
  (Linux, or a Mac without the tool) the handler fails cleanly with
  "Code signing diagnosis requires macOS with /usr/bin/codesign; it is
  not available on this platform." instead of reporting a fake
  diagnosis. Nothing is invented when the tool is absent.

## 2. `entitlements_diff` — Entitlements Diff

- Description (verbatim): "Compares two .entitlements plist files,
  reporting added, removed, and changed keys."
- Schema: `oldPath` (string, "Workspace-relative path to the baseline
  .entitlements file."), `newPath` (string, "Workspace-relative path to
  the new .entitlements file."), required: [`oldPath`, `newPath`].
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: parses both files as dictionary plists. Added =
  keys only in new, removed = keys only in old, changed = keys in both
  whose `"\(value)"` strings differ (changed entries are rendered
  `"<key>: '<old, first 60 chars>' -> '<new, first 60 chars>'"`,
  Legacy's truncation). Identical files succeed with "Entitlements
  are identical." Otherwise the message is "Entitlements diff
  (<oldPath> -> <newPath>):" followed by "- ADDED: …", "- REMOVED: …",
  "- CHANGED: …" lines, each group sorted.
- Outputs/data keys: `added` (int), `removed` (int), `changed` (int).
- Errors: "Missing required parameters: oldPath and newPath" (either
  blank); "Cannot parse entitlements plist at: <path>" (missing file,
  unreadable, or not a dictionary plist).

## 3. `entitlements_manager` — Entitlements Manager

- Description (verbatim): "Inspects, adds, and removes Apple security
  entitlements (.entitlements) like App Sandbox and Network access."
- Schema: `action` (string, "Action: 'inspect', 'add_entitlement',
  'remove_entitlement', 'list'."), `filePath` (string,
  "Workspace-relative path to the .entitlements file."),
  `entitlementKey` (string, "Entitlement key (e.g.
  'com.apple.security.app-sandbox' or
  'com.apple.security.network.client')."), `value` (string, "Value for
  entitlement (default 'true')."), required: [`action`, `filePath`].
- Capability: fileModification. Risk: safeMutation. Permission
  (Legacy-derived): fileSystem. `writes: true`, `safeMutation`
  annotations. Writes go through `commit()` (XML plist text).
- Behaviour: `inspect`/`list` reads the file and lists
  "Entitlements in '<filePath>' (<n> configured):" plus
  "- <key>: <value>" lines, keys sorted. `add_entitlement` requires
  `entitlementKey`; the value string is coerced to a boolean exactly
  as Legacy does (`"true"` or `"1"`, case-insensitive on `"true"`,
  → true; anything else → false) and stored under the key, creating
  the file (and parent directories) when it does not exist; the file
  is always written as XML. `remove_entitlement` requires
  `entitlementKey` and fails when the key is absent. No key is
  validated against any entitlement policy (YcodeSigning's
  `EntitlementPolicy` is not reachable from this target — see the
  seam note above); any key string is accepted, as in Legacy.
- Outputs: plain text, no data keys (Legacy carries no data).
- Errors: "Missing required parameters: action and filePath";
  "Entitlements file not found at: <filePath>" (inspect/list on a
  missing file); "Invalid property list or cannot parse entitlements
  at: <filePath>"; "entitlementKey is required for add_entitlement" /
  "… for remove_entitlement"; "Entitlements file does not exist at:
  <filePath>" (remove on a missing file); "Entitlement '<key>' not
  found in <filePath>" (remove of an absent key); "Failed to save
  entitlements: <detail>" / "Failed to update entitlements: <detail>";
  "Unsupported action '<action>'. Valid: inspect, list,
  add_entitlement, remove_entitlement".

## 4. `info_plist_audit` — Info.plist Audit

- Description (verbatim): "Audits Info.plist files for required keys,
  version-format sanity, and duplicate bundle identifiers."
- Schema: no properties, required: []. (Legacy's schema is an empty
  object.)
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: scans the whole workspace for files named exactly
  `Info.plist` (hidden files skipped, results sorted by path; no
  build-directory exclusion — Legacy does not exclude any). No files
  found is a success: "No Info.plist files found in the workspace.",
  `count` 0. Required keys: `CFBundleIdentifier`, `CFBundleName`,
  `CFBundleShortVersionString`, `CFBundleVersion`; each missing key is
  one issue. `CFBundleShortVersionString` must match `x.y[.z]`
  (`^\d+\.\d+(\.\d+)?$`); anything else is one issue. A bundle
  identifier appearing in more than one file adds one
  "DUPLICATE bundle id '<id>' in: <files>" line and one issue. Each
  file reports "- <rel>: OK" or "- <rel>: <issues joined with '; '>".
- Outputs/data keys: `fileCount` (int), `issueCount` (int).
- Errors: none beyond an unreadable plist, which is reported inline
  as "- <rel>: UNREADABLE plist" and counts as one issue (Legacy
  behaviour, kept).

## 5. `plist_editor` — Property List Editor

- Description (verbatim): "Inspects, sets, deletes, and validates keys
  in Apple Property List (.plist) files."
- Schema: `action` (string, "Action: 'read', 'set', 'delete',
  'list_keys'."), `filePath` (string, "Workspace-relative path to the
  .plist file."), `key` (string, "Property list key to read, set, or
  delete."), `value` (string, "Value to write (for 'set')."),
  `valueType` (string, "Type of value: 'string', 'boolean', 'integer'
  (defaults to string)."), required: [`action`, `filePath`].
- Capability: fileModification. Risk: safeMutation. Permission
  (Legacy-derived): fileSystem. `writes: true`, `safeMutation`
  annotations.
- Behaviour: the file must exist for every action, including reads
  (Legacy fails before parsing when it does not). `list_keys` lists
  the sorted keys with the count. `read` reports "<key> = <value>".
  `set` stores the value coerced by `valueType`: `"boolean"` →
  `true` iff the string is `"true"` (case-insensitive) or `"1"`;
  `"integer"` → `Int(value) ?? 0`; anything else (including an omitted
  `valueType`) → the string as-is. `delete` removes the key. A write
  preserves the source plist's format: an XML source is rewritten
  through `commit()` (text); a binary source is rewritten through
  `approveFileWritingChange` + a direct `Data` write, the
  `json_to_plist` shape. No verification re-read (Legacy does none
  here — unlike `plist_edit` / `project_info_plist`).
- Outputs: plain text, no data keys (Legacy carries no data).
- Errors: "Missing required parameters: action and filePath";
  "Plist file does not exist at path: <filePath>" (missing file, or a
  path the strict resolver refuses); "File at <filePath> is not a
  dictionary-rooted property list."; "key parameter is required for
  read" / "… for set" / "… for delete"; "Key '<key>' not found in
  <filePath>"; "Error processing plist: <detail>";
  "Unsupported action '<action>'. Valid: read, set, delete,
  list_keys".

## 6. `project_entitlements` — Entitlements

- Description (verbatim): "Finds and parses .entitlements files in
  the workspace and returns their keys and values."
- Schema: `path` (string, "Optional workspace-relative path to a
  specific .entitlements file."), required: [].
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: with an explicit `path`, parses that one file; without
  one, parses every `.entitlements` file in the workspace (hidden
  files skipped, sorted by path). Each file contributes one summary
  line "<basename>: <key> = <value>; …" or "<basename>: (no keys)".
  Values render with Legacy's `stringValue` (booleans as
  true/false, arrays as `[a, b]`, dictionaries as `{k = v, …}` with
  sorted keys, everything else via `"\(value)"`).
- Outputs/data keys: `files` (string, comma-joined basenames), `keys`
  (string, comma-joined unique keys, sorted), `count` (int, unique
  key count).
- Errors: "Path '<path>' is outside the workspace or contains '..'."
  (explicit path the resolver refuses); "Entitlements file not found
  at '<path>'."; "No .entitlements files found in the workspace."
  (scan finds none — a failure in Legacy, kept); "Failed to read
  entitlements file '<basename>'."; "Entitlements file '<basename>'
  is not a valid property list dictionary."

## 7. `project_info_plist` — Info.plist Editor

- Description (verbatim): "Reads and edits Info.plist keys using
  PropertyListSerialization with atomic writes and verification."
- Schema: `action` (string, "get, set, or delete. Default: get."),
  `key` (string, "Plist key. Required for set and delete."), `value`
  (string, "New value for set. Interpreted as Bool for true/false,
  Int for integers, otherwise String."), `path` (string, "Optional
  workspace-relative path to a specific Info.plist. Defaults to the
  first Info.plist found."), required: [].
- Capability: fileModification. Risk: safeMutation. Permission
  (Legacy-derived): fileSystem. `writes: true`, `safeMutation`
  annotations. Writes go through `commit()` (XML plist text) with
  Legacy's verification re-read.
- Behaviour: the target file is the explicit `path` when given, else
  the first `Info.plist` found by a workspace scan (sorted by path,
  skipping paths under `/build/`, `/DerivedData/`, `/.build/` —
  Legacy's exclusion). `get` with a key reports "Info.plist <key> =
  <value>"; `get` without a key lists all keys sorted
  ("Info.plist has <n> key(s):" plus "<key> = <value>" lines). `set`
  interprets the value string as Bool (`true`/`false`,
  case-insensitive), then Int, then Double, then String, writes XML,
  and verifies by re-reading: the written value's rendered form must
  equal the intended value's rendered form. `delete` removes the key
  and verifies it is gone. The success message for `set` is
  "Set Info.plist <key> = <value> (was: <previous or null>).";
  for `delete`, "Deleted Info.plist key '<key>'."
- Outputs/data keys: get-with-key: `key`, `value`, `file` (basename);
  get-all: `keys` (comma-joined), `count` (int), `file`; set: `key`,
  `value`, `file`; delete: `key`, `file`.
- Errors: "Invalid action '<action>'. Expected get, set, or delete.";
  "Path '<path>' is outside the workspace or contains '..'.";
  "No Info.plist found in the workspace."; "Info.plist not found at
  '<basename>'."; "Info.plist at '<basename>' is not a valid property
  list dictionary."; "Key '<key>' not found in Info.plist.";
  "Missing required parameter: key for action=set" /
  "… value for action=set"; "Failed to write Info.plist.";
  "Verification failed: key '<key>' was not written to Info.plist." /
  "… still present in Info.plist."

## 8. `project_signing` — Signing Check

- Description (verbatim): "Checks code-signing build settings and
  lists installed provisioning profile filenames without parsing
  profile contents."
- Schema: `scheme` (string, "Optional scheme name for
  -showBuildSettings."), `configuration` (string, "Build
  configuration, e.g. Debug or Release. Default: Debug."),
  required: [].
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: resolves the five signing settings
  (`CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM`,
  `PRODUCT_BUNDLE_IDENTIFIER`, `CODE_SIGN_IDENTITY`,
  `PROVISIONING_PROFILE_SPECIFIER`) for the requested configuration
  and lists the filenames of installed `.mobileprovision` profiles
  from `~/Library/MobileDevice/Provisioning Profiles` (filenames
  only — profile contents are never parsed here, as in Legacy). The
  summary is Legacy's shape: "Signing for configuration
  '<configuration>':" followed by the five `KEY = <value or (not
  set)>` lines and "Provisioning profiles installed: <n>".
- Deliberate deviation from Legacy: Legacy spawns
  `xcodebuild -showBuildSettings` (macOS-only). This port resolves
  the settings from the workspace's own `.xcodeproj` through
  Ycode's `ProjectSettingsBuilder` — the same seam the
  `build_settings` tool uses — so it works wherever the project
  opens (including Linux) and honours `.xcconfig` base
  configurations. Consequences: (a) a workspace with no
  `.xcodeproj`/`.xcworkspace` fails with Legacy's message
  ("No .xcodeproj or .xcworkspace found at the top level of the
  workspace."); (b) the target resolved is the first target, or the
  target whose name matches `scheme` when one is given (Legacy's
  scheme selected the target implicitly through xcodebuild); (c) a
  `configuration` the project does not define falls back to the
  project's default configuration with a diagnostic, the builder's
  own rule; (d) `scheme` is echoed in the data when given.
- Outputs/data keys: `configuration` (string), `codeSignStyle`,
  `developmentTeam`, `bundleId`, `codeSignIdentity`,
  `provisioningProfileSpecifier` (strings, `""` when unset),
  `provisioningProfileCount` (int),
  `provisioningProfiles` (string, comma-joined filenames),
  `scheme` (string, only when given).
- Errors: "Missing required parameter: configuration" (blank
  configuration); "No .xcodeproj or .xcworkspace found at the top
  level of the workspace."; "cannot resolve the settings of <target>
  (<configuration>): <detail>" (unresolvable settings stack).

## 9. `provisioning_check` — Provisioning Check

- Description (verbatim): "Lists installed provisioning profiles,
  reports expiration, and compares App IDs against an optional
  bundle ID."
- Schema: `bundleId` (string, "Bundle ID to compare against each
  profile App ID (optional)."), required: [].
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: reads every `.mobileprovision` file in
  `~/Library/MobileDevice/Provisioning Profiles`, decodes each with
  `/usr/bin/security cms -D -i <path>` (fixed argv, 60 s per profile),
  and parses the decoded plist. Per profile: name, team name, App ID
  (the `application-identifier` entitlement with its team prefix
  stripped at the first `.`, else `AppIDName`), expiration date, and
  status (`valid`, `EXPIRED`, `expiring soon` — within 30 days).
  With a `bundleId`, each profile is `matches <bundleId>`,
  `wildcard - covers <bundleId>` (App ID bundle part `*`), or
  `MISMATCH (profile App ID bundle: <part>)`. The header is
  "Provisioning profiles: <n>, expired: <n>, expiring within 30
  days: <n>" plus ", bundle <id>: <n> match(es), <n> mismatch(es)"
  when a bundle ID was given; each profile is one line
  "<name> - team: <team> - AppID: <id> - expires: <date or (unknown)>
  - <status> - <comparison>". A profile that fails to decode or
  parse is one "<file> - could not decode: <stderr, last 300 chars>"
  / "<file> - could not parse decoded plist." line and does not abort
  the check (Legacy behaviour).
- Outputs/data keys: `profile_count`, `expired_count`,
  `expiring_count`, `match_count`, `mismatch_count` (ints),
  `bundle_id` (string, `""` when not given).
- Errors: "security tool not found at /usr/bin/security." (the tool
  is absent — the honest failure on Linux, with Legacy's message);
  "No provisioning profiles directory found at
  ~/Library/MobileDevice/Provisioning Profiles. No profiles are
  installed."; "No .mobileprovision files found in
  ~/Library/MobileDevice/Provisioning Profiles." (both are failures
  in Legacy, kept).

## 10. `provisioning_profile_reader` — Provisioning Profile Reader

- Description (verbatim): "Decodes and inspects entitlements, team
  ID, and expiration date of Apple provisioning profiles."
- Schema: `path` (string, "Path to .mobileprovision or
  .provisionprofile file."), required: [`path`].
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: decodes the profile with `/usr/bin/security cms -D -i
  <path>` (fixed argv, 60 s) and parses the decoded plist. The report
  is Legacy's Markdown: "### Provisioning Profile Summary
  (`<basename>`):" with Profile Name, Team (`<teamName>
  (<teamID>)`), App ID Name, Expiration Date (ISO 8601, when
  present), and "#### Entitlements Included (<n>):" with one
  "- **<key>**: `<value>`" line per entitlement. The
  `DeveloperCertificates` blobs are never read or reported.
- Path rule (documented read-only exception, like Wave 6's
  `test_coverage_reporter`): an absolute `path` is used as-is —
  profiles live in `~/Library/MobileDevice/Provisioning Profiles`,
  outside any workspace; a relative path resolves against the
  workspace root and must stay inside it.
- Outputs: plain text, no data keys (Legacy carries no data).
- Errors: "Missing required parameter: path" (blank path);
  "Provisioning profile not found at: <path>"; "Failed to execute
  security cms -D: <detail>" (the tool is absent — the honest
  failure on Linux — or the launch failed); "Failed to decode XML
  property list from provisioning profile." (decode produced
  non-plist output, e.g. a file that is not a CMS envelope).

## 11. `signing_certificate_inspector` — Code Signing Certificate Inspector

- Description (verbatim): "Inspects valid Apple Development and
  Distribution code signing certificates in the keychain."
- Schema: no properties, required: [].
- Capability: diagnostics. Risk: safeRead. Permission: none.
  Read-only; `writes: false`.
- Behaviour: runs `/usr/bin/security find-identity -p codesigning -v`
  (fixed argv, 60 s) and reports each output line as one
  "- `<line>`" entry under "### Available Code Signing
  Certificates:". Empty output succeeds with "No valid code-signing
  identities found in macOS Keychain." Only the names and SHA-1
  hashes `find-identity` itself prints are reported; no private key
  material is touched.
- Outputs: plain text, no data keys (Legacy carries no data).
- Errors: "Failed to execute security find-identity: <detail>" (the
  tool is absent — the honest failure on Linux — or the launch
  failed).
- Honestly-failing case: on a host without `/usr/bin/security` the
  handler fails cleanly instead of reporting an empty certificate
  list (an empty list would be a lie on a machine whose keychain was
  never consulted).

## `plist_editor` vs `plist_edit` — the distinction

These are two distinct Legacy tools; both are ported, and neither
replaces the other:

| | `plist_edit` (Wave 2, `AssistPlistEditTool`, already ported) | `plist_editor` (this slice, `AssistPlistTool`) |
|---|---|---|
| Params | `path`, `action` (default `get`), `key` (required), `value` | `filePath`, `action`, `key`, `value`, `valueType` |
| Actions | `get` / `set` / `delete` | `read` / `set` / `delete` / `list_keys` |
| Read | `get` one key; requires the key | `read` one key, or `list_keys` for all keys |
| Set value | string only | string / boolean / integer via `valueType` |
| Missing file | fails ("Plist file not found at …") | fails ("Plist file does not exist at path: …") |
| Format on write | always XML | preserves the source format (XML or binary) |
| Verification | re-reads and verifies after set/delete | none |
| Data keys | `key` / `value` / `path` | none (plain text) |

Registration, schema and handler are separate; `plist_editor` does not
reuse `plist_edit`'s handler or resolver.

## Evidence

- Legacy tool files read live (all under
  `SwiftCode/Backend/Assist/Tools/`): `AssistCodeSigningDiagnoseTool.swift`,
  `AssistEntitlementsDiffTool.swift`, `AssistEntitlementsTool.swift`,
  `AssistInfoPlistAuditTool.swift`, `AssistPlistTool.swift`,
  `AssistPlistEditTool.swift` (comparison only),
  `AssistProjectEntitlementsTool.swift`,
  `AssistProjectInfoPlistTool.swift`, `AssistProjectSigningTool.swift`,
  `AssistProvisioningCheckTool.swift`,
  `AssistProvisioningProfileReaderTool.swift`,
  `AssistSigningCertificateInspectorTool.swift`; alias table in
  `AssistToolRegistry.swift` (`toolAliases`, lines ~430–560).
- Destination seams read: `ycode/Sources/YcodeMCP/YcodeTools.swift`
  (`tool()`, `installTools()`), `YcodeTools+Testing.swift` (family
  structure), `YcodeTools+FileWriting.swift` (`plist_edit` handler,
  `commit()`/`approveFileWritingChange`, strict resolvers),
  `YcodeTools+TerminalSupport.swift` (`terminalRunFixed`),
  `YcodeTools+Workspace.swift` (`buildSettings` →
  `ProjectSettingsBuilder`), `YcodeTools+Content.swift` (`commit()`),
  `MCPServer.swift` (write policy, `run()`), `specs/ide/assist-approval-model.md`,
  `specs/ide/assist-testing-tools.md`, `ycode/Sources/YcodeSigning/`
  (seam survey — not imported), `ycode/Sources/YcodeProject/` and
  `ycode/Sources/YcodeSettings/` (direct `YcodeMCP` dependencies).
- No Swift toolchain exists in this environment: no `swift build` /
  `swift test` was run and none is claimed. Static checks only
  (delimiter balance, duplicate-ID scan, TODO/FIXME scan, collision
  scan against the existing 251 tools) — see the delivery report.


## Part E — Asset catalogs & localization

Ycode modules: `YcodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 9 Legacy Assist asset
catalog / localization tools ported in Wave 7, slice E:
`asset_catalog_list`, `asset_catalog_manager`, `asset_image_add`,
`localization_audit`, `localization_manager`, `localize_app`,
`string_catalog_migrator`, `strings_file_validate`,
`strings_localization`. The implementation is
`ycode/Sources/YcodeMCP/YcodeTools+AssetsLocalization.swift`; the
tests are `ycode/Tests/YcodeMCPTests/YcodeAssetsLocalizationTests.swift`.

The per-tool sections below are catalogue-ready: each gives the
tool's description and input schema verbatim (Legacy's
`parametersSchema` plus the `workspace` parameter every Ycode tool
carries), its output shape, and its error cases, so the coordinator
can merge them into `specs/ide/assist-tool-catalogue.md` without
re-deriving anything.

Scope: what each tool does once called, what it returns, what it
refuses, and which Ycode seam it runs through. The approval model
itself (write policy, `commit()` / `approve()`, the rejected
Autopilot bypass) is `specs/ide/assist-approval-model.md` and is
not repeated here beyond the per-tool gate column.

## 1. Conventions shared by the slice

- **IDs, titles, descriptions, schemas are Legacy's verbatim**,
  verified live from each Legacy tool file (see Evidence). The
  only additions are the `workspace` parameter and Ycode's
  `additionalProperties: false`. Legacy's parameter-name aliases
  are NOT supported: Ycode's argument validation rejects unknown
  arguments before the handler runs.
- **Structured data keeps Legacy's keys, with typed JSON values**
  (integers, booleans) the way Ycode's other tools do — Legacy's
  string-only map is not reproduced. Tools whose Legacy result
  carries no data, or whose data keys vary by action / file type,
  return a plain text result instead (`asset_catalog_manager`,
  `localization_manager`, `localize_app`, `string_catalog_migrator`,
  `strings_localization`).
- **Paths are confined to the workspace.** Legacy's tools use
  three different path rules: `AssistWorkspacePaths.resolve`
  (rejects any `..` as text, absolute paths must be inside the
  workspace — used by `strings_file_validate`), a per-tool
  `resolvePath` with the same rule (used by `asset_catalog_list`,
  `asset_image_add`, `strings_localization`), and no check at all
  (`asset_catalog_manager`, `localization_manager`,
  `string_catalog_migrator`, `localize_app` append to the
  workspace root unchecked, so `..` escapes). Ycode does not
  reproduce the unchecked rule: every path goes through either
  the slice's strict resolver (same rule as
  `AssistWorkspacePaths.resolve`, preserving Legacy's
  "must be inside the workspace and must not contain '..'"
  messages) or the session resolver `resolveFileReadingPath`
  (used where Legacy had no path error of its own). A `..` that
  stays inside the workspace is refused here, unlike Wave 6's
  session-resolver tools — because these tools' Legacy messages
  say `..` is forbidden, and the message must stay honest.
- **`.xcstrings` goes through Ycode's own `StringCatalog` seam**
  (`YcodeStrings`, re-exported by `YcodeIDECore`): parsing,
  `sourceLanguage`, `keys`, `languages`, `setTranslation`,
  `addKey`, `removeKey`, and `data()` for writing. Where Legacy's
  behaviour needs a shape `StringCatalog` has no setter for (a
  `"new"`-state placeholder unit with an empty value, deleting
  one locale of a key), the handler edits the catalog's public
  `json` (`OrderedJSON`) directly — the seam's own model, not a
  parallel one. `.strings` files are handled with Legacy's
  line-based scan/edit (see §2): `StringsFile.parse` throws on
  the first malformed line, which would change Legacy's
  per-line error behaviour (`strings_file_validate` reports
  every malformed line; `read_key` skips unparseable lines), so
  the line scan is the faithful port.
- **Asset catalogs use plain `FileManager` directory work**, the
  way Legacy does: these tools only enumerate `.xcassets`
  directories and write `Contents.json` text. Ycode's
  `YcodeAssetCatalog` is a CAR compiler; its `CatalogInput`
  directory loader is not visible to `YcodeMCP` (no target
  dependency, and `Package.swift` is out of this slice's scope),
  and nothing here needs a compiled CAR.
- **Failures are thrown as `MCPToolError`** with Legacy's message
  text, so the caller sees an `isError` result carrying that
  message. Legacy's `.failure(…)` and Ycode's throw are the same
  observable outcome.
- **Risk / gate.** `safeRead` tools are `writes: false`,
  `readOnly: true, idempotent: true`. `safeMutation` tools are
  `writes: true`, `readOnly: false, idempotent: true`, and go
  through `commit()` (text writes) or an explicit `MCPChange` +
  `approve()` (the byte copy in `asset_image_add`, §4). The
  `writes` flag is static per tool: `asset_catalog_manager`'s
  `inspect`/`list` actions and `localization_manager`'s
  `list_languages`/`read_key`/`validate` actions write nothing,
  but in `readOnly` mode even those calls are refused in `run()`,
  exactly as the approval model specifies for dry-run tools.
  There is no second gate, no Autopilot, no bypass.
- **No result is ever invented.** The audit reports the keys the
  files actually contain; the migrator converts the entries the
  `.strings` file actually has; `localize_app` discovers only
  the keys the Swift sources actually wrap.
- **No Swift toolchain exists in this environment** (Linux CI):
  the implementation and tests are statically checked only.
  `swift build` / `swift test` and the Mac live runs stay pending
  on Dylan's Mac.

## 2. Shared helpers (slice-private)

- `assetsStrictResolve(_:root:) -> URL?` — Legacy's
  `resolvePath` / `AssistWorkspacePaths.resolve` rule verbatim:
  trim; reject empty, any `..` as text; an absolute path must
  equal the workspace root or sit under it; a relative path is
  appended to the root and must stay under it. Used by
  `asset_catalog_list`, `asset_image_add`, `strings_localization`
  (whose Legacy messages name the rule) and `strings_file_validate`.
- `assetsParseStringsLine(_:) -> (key:value:)?` — Legacy's
  line parser, shared by `localization_manager` and
  `strings_localization`: skip blank / `//` / `/*` lines, split
  on the first `=`, strip a trailing `;`, unquote both sides
  (`\"` → `"`, `\\` → `\`). `assetsEscape(_:)` is Legacy's
  escaper (`\` → `\\`, `"` → `\"`, newline → `\n`).
- `assetsParseStringsKeys(at:) -> Set<String>` — Legacy's
  `localization_audit` key scan: skip blank / `//` / `/*`
  lines, split on the first `=`, strip a trailing `;` from the
  key part, unquote and unescape.
- `assetsXCStringsKeys(at:) -> [String: Set<String>]` —
  Legacy's `localization_audit` xcstrings scan, through
  `StringCatalog`: a key counts for a locale only when that
  key's entry has a `localizations` entry for the locale (the
  source language alone does not count). An unreadable or
  invalid catalog contributes nothing.
- `assetsLocaleFor(url:) -> String?` — the `.lproj` parent
  directory's language code, or nil.
- `assetsFindInfoPlist(in:) -> URL?` / `assetsFindCatalog(named:in:) -> URL?`
  — Legacy's searches: enumerate the workspace skipping
  `.git`, `build`, `DerivedData`, `.build` paths (catalog
  search also skips `DerivedData` only in Legacy's
  `findCatalog`; the plist search skips `build`,
  `DerivedData`, `.build`), sort candidates by path, take the
  first. `findInfoPlist` skips `build`/`DerivedData`/`.build`;
  `findCatalog` skips `build`/`DerivedData`.
- `assetsReadPlist(at:) -> [String: Any]?` /
  `assetsPlistText(_:) -> String?` — `PropertyListSerialization`
  read (any format) and XML serialisation, Legacy's pair.
- `assetsCatalogUnit(_:key:language:) -> (state:value:)?` —
  the `stringUnit` of one key/locale out of a `StringCatalog`'s
  `json`, or nil when there is no such unit.

## 3. `asset_catalog_list` — List Asset Catalog

Legacy: `AssistAssetCatalogListTool.swift`. Capability
`repositoryDiscovery`, risk `safeRead`. Gate: none.

Description (verbatim): "Lists asset catalogs under the workspace
and the image, color, and app-icon sets inside each catalog."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "path": {"type": "string", "description": "Optional workspace-relative path to a single .xcassets catalog or a directory to search. Default: whole workspace."}},
 "required": [], "additionalProperties": false}
```

Behaviour (Legacy's, verbatim):

1. Without `path`, the search root is the workspace root.
   With `path`, the strict resolver (§2) must accept it or the
   call fails with `Invalid path '<path>': must be inside the
   workspace and must not contain '..'.`; the resolved path
   must exist and be a directory or the call fails with
   `Path '<path>' does not exist or is not a directory.`
2. A search root that is itself a `.xcassets` directory is a
   catalog. Otherwise the root is enumerated (skipping hidden
   files); every `.xcassets` directory found is a catalog and
   its descendants are not descended into. Catalogs are sorted
   by path.
3. A catalog's sets are its immediate children ending in
   `.imageset`, `.colorset`, `.appiconset`, `.dataset`, or
   `.symbolset`, sorted by name. (Note: this list is wider than
   `asset_catalog_manager`'s inspect filter, §4 — Legacy's two
   tools genuinely differ here, and the port keeps the
   difference.)
4. No catalogs → success: `No .xcassets catalogs found.`
   with `catalogCount` 0 and `totalSets` 0. Otherwise the
   summary is `Found <C> catalog(s) with <T> set(s) total.`
   followed by one `<relative path>: <N> set(s)` line per
   catalog and one `  - <set name>` line per set.

Output (structured): `catalogCount`, `totalSets` (ints),
`catalogs` (comma-joined workspace-relative catalog paths).

Error cases:

| Condition | Result |
|---|---|
| `path` refused by the strict resolver | `Invalid path '<path>': must be inside the workspace and must not contain '..'.` |
| `path` missing / not a directory | `Path '<path>' does not exist or is not a directory.` |
| No workspace open | `no workspace is open: call workspace_open …` |

## 4. `asset_catalog_manager` — Asset Catalog Manager

Legacy: `AssistAssetCatalogTool.swift`. Capability
`fileModification`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; creations go through `commit()` (the
`Contents.json` text write; creating its parent directories
is `commit()`'s own behaviour). `inspect` / `list` write
nothing but are still `writes: true` (§1).

Description (verbatim): "Inspects, manages, and creates asset
catalogs (.xcassets), image sets, color sets, and dataset assets."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "action": {"type": "string", "description": "Action to perform: 'inspect', 'create_catalog', 'create_colorset', 'create_imageset', 'list'."},
  "catalogPath": {"type": "string", "description": "Workspace-relative path to the .xcassets directory."},
  "assetName": {"type": "string", "description": "Name of the color set or image set to create or inspect."},
  "lightColorHex": {"type": "string", "description": "Hex color for Light mode (e.g. '#FFFFFF' or '#336699')."},
  "darkColorHex": {"type": "string", "description": "Hex color for Dark mode (e.g. '#1E1E1E')."}},
 "required": ["action", "catalogPath"], "additionalProperties": false}
```

Behaviour (Legacy's, in order):

1. Missing `action` or `catalogPath` → `Missing required
   parameters: action and catalogPath`. An unknown action →
   `Unsupported action '<action>'. Valid actions: inspect,
   create_catalog, create_colorset, create_imageset, list`
   (checked before the path is resolved, as in Legacy's
   `switch`).
2. The catalog path is confined with the strict resolver
   (§2): Legacy appended it unchecked, so `..` escaped the
   workspace — Ycode refuses it with `Invalid catalog path
   '<catalogPath>': must be inside the workspace and must not
   contain '..'.` (deliberate deviation, §9).
3. `create_catalog`: writes the catalog's `Contents.json`
   (Legacy's text verbatim: `info` author `xcode`, version 1)
   through `commit()`; the catalog directory is created as the
   file's parent. Success: `Successfully initialized asset
   catalog at <catalogPath>`. An existing catalog is
   re-initialised the same way (Legacy overwrites its
   `Contents.json` unconditionally).
4. `create_colorset`: `assetName` is required
   (`assetName is required for create_colorset`). `lightColorHex`
   defaults to `#007AFF`; `darkColorHex` defaults to the light
   value. The set's `Contents.json` is Legacy's text verbatim
   through `commit()`. Success: `Created Color Set
   '<assetName>' in <catalogPath> with light: <lightHex>, dark:
   <darkHex>`.
5. `create_imageset`: `assetName` is required
   (`assetName is required for create_imageset`). The set's
   `Contents.json` is Legacy's text verbatim (universal 1x/2x/3x
   slots, no filenames) through `commit()`. Success: `Created
   Image Set '<assetName>' in <catalogPath> with universal
   1x/2x/3x slots.`
6. `inspect` / `list`: the catalog must exist
   (`Asset catalog does not exist at path: <catalogPath>`).
   Sets are the directory's children ending in `.colorset`,
   `.imageset`, `.appiconset`, or `.dataset` (no `.symbolset`
   — Legacy's inspect filter, kept verbatim). Success:
   `Asset Catalog '<catalogPath>' contains <N> asset sets:` +
   the set names, one per line.

Output: plain text (Legacy carries no data).

**Known Legacy quirk, preserved verbatim:** `create_colorset`
ignores `lightColorHex` / `darkColorHex` when writing the file:
the `Contents.json` components are hardcoded (light red
0.000 / green 0.500 / blue 1.000; dark red 0.100 / green
0.600 / blue 1.000) and the hex values appear only in the
success message. The port keeps Legacy's exact file text
rather than silently changing what the catalog contains; the
hex arguments are honoured in the message, as in Legacy.
Fixing the file to use the supplied hex values is a behaviour
change for a later wave, not this port.

**Confinement note:** `assetName` is also checked for `/`,
`\`, and `..` (`Invalid assetName: must be a bare name without
slashes or '..'.`) — Legacy did not check it, and a `..`
name would have escaped the catalog. The character set is
otherwise Legacy's (no charset check on this tool, unlike
`asset_image_add`, §5).

Error cases:

| Condition | Result |
|---|---|
| Missing `action` / `catalogPath` | `Missing required parameters: action and catalogPath` |
| Unknown action | `Unsupported action '<action>'. Valid actions: inspect, create_catalog, create_colorset, create_imageset, list` |
| `catalogPath` refused | `Invalid catalog path '<catalogPath>': must be inside the workspace and must not contain '..'.` |
| `create_colorset` / `create_imageset` without `assetName` | `assetName is required for create_colorset` / `assetName is required for create_imageset` |
| `assetName` with `/`, `\`, `..` | `Invalid assetName: must be a bare name without slashes or '..'.` |
| `inspect` / `list` a missing catalog | `Asset catalog does not exist at path: <catalogPath>` |
| Write refused in review / read-only server | `MCPServer.rejectedMessage` / `readOnlyMessage` (approval model) |

## 5. `asset_image_add` — Add Asset Image

Legacy: `AssistAssetImageAddTool.swift`. Capability
`fileModification`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; the `Contents.json` goes through `commit()`,
and the image byte-copy is its own `MCPChange` + `approve()`
before `copyItem` (approval model §6.2), in Legacy's order
(Contents.json first, copy second). A refused copy after an
approved Contents.json leaves the imageset directory behind —
Legacy's non-atomic behaviour (it wrote Contents.json before
copying too).

Description (verbatim): "Adds an image to an asset catalog by
creating an .imageset with Contents.json and copying the source
image."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "catalog": {"type": "string", "description": "Workspace-relative path to the .xcassets catalog (e.g. Assets.xcassets). Created if missing."},
  "imageName": {"type": "string", "description": "Name for the new image set (no slashes or '..')."},
  "sourcePath": {"type": "string", "description": "Workspace-relative path to the source image file inside the workspace."}},
 "required": ["catalog", "imageName", "sourcePath"], "additionalProperties": false}
```

Behaviour (Legacy's, in order):

1. Missing/blank `catalog` / `imageName` / `sourcePath` →
   `Missing required parameter: catalog` (etc., naming the
   first missing one in that order).
2. `catalog` must end in `.xcassets`:
   `Invalid catalog '<catalog>': must end with .xcassets.`
3. `imageName` must be a bare name: no `/`, `\`, `..`, and
   not `.` or `..` (`Invalid imageName: must be a bare name
   without slashes or '..'.`), and only letters, digits,
   spaces, `_`, `-` (`Invalid imageName: use letters, digits,
   spaces, '_' or '-'.`).
4. Both paths go through the strict resolver (§2):
   `Invalid catalog path '<catalog>': must be inside the
   workspace and must not contain '..'.` /
   `Invalid sourcePath '<sourcePath>': must be inside the
   workspace and must not contain '..'.`
5. The source must exist: `Source image not found at
   '<sourcePath>'.`
6. The destination filename is the source's filename, or
   `image.png` when the source has no extension.
7. The imageset must not already exist:
   `Image set '<imageName>.imageset' already exists in
   '<catalog>'.`
8. The catalog directory is created if missing (as the
   Contents.json's parent, via `commit()`). The `Contents.json`
   is Legacy's text verbatim (one universal image with the
   destination filename). The source is then copied into the
   set (an existing destination file is removed first, as in
   Legacy — unreachable in practice, since the set is new).
9. Verification re-reads disk: both files must exist or the
   call fails with `Verification failed: image set files not
   present after write.`

Output (structured): `catalog`, `imageName`, `imageSet`
(workspace-relative), `fileName`. Summary: `Added image
'<imageName>' to '<catalog>' as <imageSet> with file
<fileName>.`

Error cases: as in steps 1–7 and 9 above, plus the approval
refusals (`rejectedMessage` / `readOnlyMessage`).

## 6. `localization_audit` — Localization Audit

Legacy: `AssistLocalizationAuditTool.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Compares localization keys across
locales and reports missing keys and keys never referenced in
Swift code."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."}},
 "required": [], "additionalProperties": false}
```

Behaviour (Legacy's, verbatim):

1. The whole workspace is enumerated (skipping hidden
   files). `Localizable.strings` files contribute their keys
   (§2 line scan) under their `.lproj` parent's locale, or
   `unknown` when they have none. `Localizable.xcstrings`
   files contribute their per-locale keys (§2). `.swift` files
   are collected for the unused-key scan.
2. No localization files at all → success:
   `No Localizable.strings or Localizable.xcstrings files
   found.` with `localeCount` 0 and `totalKeys` 0.
3. Otherwise the summary is, in order: `Locales: <sorted,
   comma-joined>`, `Total distinct keys: <N>`, `Localization
   files: <relative paths, comma-joined>`, one line per locale
   (`<locale>: complete (<K> keys)` or `<locale>: missing <M>
   key(s)`), then `Missing keys:` + one `<locale> missing:
   <key>` line per missing key (sorted, at most 50 per
   locale), then either `Unused keys: none found (all keys
   referenced in Swift files).` or `Unused keys (<U>): keys not
   referenced via NSLocalizedString / String(localized:) /
   quoted literal in Swift files:` + one `- <key>` line per
   unused key (sorted, at most 100).
4. Unused keys (Legacy's scan, verbatim): up to the first 2000
   Swift files, skipping files over 300,000 characters, stop
   once the concatenated text exceeds 5,000,000 characters; a
   key is unused when its quoted form `"<key>"` does not
   appear anywhere in that text.

Output (structured): `localeCount`, `totalKeys`,
`unusedCount` (ints), `unused` (comma-joined sorted keys).

Error cases:

| Condition | Result |
|---|---|
| Workspace cannot be enumerated | `Failed to enumerate workspace.` |
| No workspace open | `no workspace is open: call workspace_open …` |

## 7. `localization_manager` — Localization Manager

Legacy: `AssistLocalizationTool.swift`. Capability
`fileModification`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; `add_translation` writes go through
`commit()` (the whole new file text for `.strings`, the
serialised catalog for `.xcstrings`). `list_languages`,
`read_key`, and `validate` write nothing but are still
`writes: true` (§1).

Description (verbatim): "Inspects, extracts, adds translations,
and validates .strings, .stringsdict, and .xcstrings localization
files."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "action": {"type": "string", "description": "Action: 'list_languages', 'read_key', 'add_translation', 'validate'."},
  "filePath": {"type": "string", "description": "Workspace-relative path to .strings or .xcstrings file."},
  "key": {"type": "string", "description": "Localization key (e.g. 'welcome_message')."},
  "translation": {"type": "string", "description": "Translated string value to insert."}},
 "required": ["action", "filePath"], "additionalProperties": false}
```

Behaviour (Legacy's, in order):

1. Missing `action` or `filePath` → `Missing required
   parameters: action and filePath`. An unknown action →
   `Unsupported action '<action>'. Valid: list_languages,
   read_key, add_translation, validate`. A file whose
   extension is not `strings`, `xcstrings`, or `stringsdict`
   (case-insensitive) → `Unsupported localization file type
   '<ext>'. Expected .strings, .stringsdict, or .xcstrings.`
   The path is confined with the session resolver
   (`resolveFileReadingPath`): Legacy appended it unchecked,
   so `..` escaped the workspace — Ycode refuses it
   (deliberate deviation, §9).
2. `list_languages`: for `.xcstrings`, the languages are the
   union of every entry's `localizations` keys plus the
   catalog's `sourceLanguage`; for other types, the file's own
   `.lproj` locale (when it has one). Sibling locale files
   are then enumerated across the workspace
   (`Localizable.strings`, `Localizable.xcstrings`,
   `InfoPlist.strings` in an `.lproj` directory) and their
   locales added. No languages at all →
   `No languages found. The file '<name>' has no detectable
   locales.` Success: `Languages (<N>): <sorted, comma-joined>`
   with data `languages` (comma-joined) and `count`.
3. `validate`: the file must exist (`File does not exist at:
   <name>`). `.xcstrings`: invalid JSON →
   `Validation failed: <name> is not valid JSON.`; JSON
   without a `strings` dictionary →
   `Validation failed: <name> is JSON but has no 'strings'
   dictionary.`; otherwise `Validation passed for <name>.
   Valid String Catalog with <N> key(s).`
   `.stringsdict`: not a property list →
   `Validation failed: <name> is not a valid property list.`;
   otherwise `Validation passed for <name>. Valid property
   list.` `.strings`: unreadable → `Cannot read <name>`;
   each line is checked — a line starting with `"` that lacks
   a trailing `;` is `Line <N>: missing terminating semicolon
   ';'`, a line starting with `"` that does not parse is
   `Line <N>: malformed key = value entry` (blank, `/*`,
   `//`, and `*` lines are skipped); with no errors,
   `Validation passed for <name>. Contains <N> localized
   entries with no syntax errors.`, otherwise
   `Validation errors in <name>:` + the errors, one per line.
   Validate carries no data.
4. `read_key` / `add_translation` on `.strings`:
   `read_key` requires `key` (`key parameter is required for
   read_key`); the file must exist (`Localization file does
   not exist at: <filePath>`); unreadable →
   `Failed to read localization file: <filePath>`; the first
   line whose key matches wins:
   `Found localization: "<key>" = "<value>";` (Legacy's
   trailing semicolon, verbatim); otherwise
   `Key '<key>' not found in <filePath>`. `add_translation`
   requires `key` and `translation`
   (`key and translation parameters are required for
   add_translation`); the existing key's line is replaced in
   place, otherwise the new `"key" = "value";` line is
   appended; parent directories are created; the write is
   verified to contain the new line
   (`Verification failed: key not present after write.`).
   Success: `Successfully <updated|added> translation for
   '<key>' in <name>.` Neither action carries data.
5. `read_key` / `add_translation` on `.stringsdict`: the file
   must exist and parse as a property-list dictionary
   (`Failed to read <name> as a property list.`). `read_key`
   requires `key`; a missing key →
   `Key '<key>' not found in <name>`; a found key →
   `Found localization entry for '<key>': <entry>` where
   `<entry>` is the plist value's description. `add_translation`
   is honestly refused — Legacy's message, verbatim:
   `add_translation is not supported for .stringsdict files:
   entries are plural/format-rule dictionaries, not plain
   strings. Use the .xcstrings String Catalog (or a .strings
   file) for plain string translations.` Writing a plain
   string into a plural/format-rule dictionary would corrupt
   it, so the refusal is the behaviour, not a gap.
6. `read_key` / `add_translation` on `.xcstrings`: the locale
   is the file's `.lproj` parent, or `en`. `read_key` requires
   `key`; a missing file reads as an empty catalog, so a
   missing key (or missing file) →
   `Key '<key>' not found for locale '<locale>' in <name>.`;
   a found key →
   `Key '<key>' (<locale>) = "<value>" in <name>.` with data
   `key`, `value`, `locale`, `file`. `add_translation`
   requires `key` and `translation`; it sets the locale's
   unit to state `translated` (creating the key and the
   `sourceLanguage`/`version` defaults when the file is new —
   Legacy's new file had neither; the seam's canonical empty
   catalog carries both, §9) and writes through `commit()`.
   Success: `Successfully added translation for '<key>'
   (<locale>) in <name>.` (no data, as in Legacy).

Output: plain text, except `list_languages` (`languages`,
`count`) and `.xcstrings` `read_key` (`key`, `value`,
`locale`, `file`). Because the data keys vary by action and
file type, the tool has no static output schema.

Error cases: as in steps 1–6 above, plus the approval
refusals (`rejectedMessage` / `readOnlyMessage`).

## 8. `localize_app` — App Localizer

Legacy: `AssistLocalizeAppTool.swift`. Capability
`fileModification`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; `localize` commits the String Catalog first
and the Info.plist second (one `commit()` per file, in that
order, stopping at the first refusal — the approval model's
multi-file rule); `set_development_region` commits the
Info.plist, then the catalog's `sourceLanguage` when a catalog
is present (a catalog write failure there is ignored, as in
Legacy — see below). `status` writes nothing but is still
`writes: true` (§1).

Description (verbatim): "Fully localizes an app into up to 3
languages per session: discovers localizable strings in Swift
sources, creates/merges a Localizable.xcstrings String Catalog
with translations, and sets Info.plist CFBundleLocalizations +
CFBundleDevelopmentRegion. Follows the LocalizingApps.md System
Asset."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "action": {"type": "string", "description": "localize (default), status, or set_development_region."},
  "languages": {"type": "array", "items": {"type": "string"}, "description": "Language codes to localize into, 1-3 per Assist session (e.g. [\"es\",\"fr\",\"de\"]). Required for action=localize."},
  "translations": {"type": "object", "description": "Optional map of string-key -> language-code -> translated text. Keys or languages without a supplied translation are written with state \"new\" as untranslated placeholders for the model to translate later."},
  "development_region": {"type": "string", "description": "Development-region language code (default \"en\"). Sets the String Catalog source language on localize; the value to set for action=set_development_region."}},
 "required": [], "additionalProperties": false}
```

Behaviour:

### `localize` (default)

1. `languages` must be a non-empty array of 1–3 language
   codes, each matching `^[A-Za-z]{2,3}(-[A-Za-z]{2,4})?$`
   (duplicates collapse, order kept). Missing/empty →
   `Missing required parameter: languages (1-3 language codes,
   e.g. ["es","fr","de"]).`; an invalid code →
   `Invalid language code '<code>'. Expected 2-3 letters with
   an optional -Region suffix (e.g. en, es, pt-BR, zh-Hans).`;
   more than 3 → `Too many languages (<N>). Maximum 3
   languages per Assist session; run again for more.`
   `development_region` defaults to `en`, must be a valid
   code (`Invalid development_region '<region>'. Expected a
   language code such as en.`). `translations` is a
   key → language → text map; non-string values are ignored.
2. The target directory is the directory holding the first
   `Info.plist` found in the workspace, else the workspace
   root. Localizable keys are discovered in the Swift sources
   under it (§2 discovery): `NSLocalizedString("key" …)` with
   an optional `tableName:` (a non-`Localizable`, non-empty
   table is skipped and counted), and
   `String(localized: "key" …)`. Files under `build`,
   `DerivedData`, `.build`, `Pods`, `.swiftpm` are skipped;
   files ≥ 2,000,000 bytes or not UTF-8 are skipped. No keys
   → `No localizable strings found in Swift sources under
   '<targetDir>'. Wrap user-facing text in
   NSLocalizedString(_:comment:) or String(localized:) first.`
3. The catalog is the first `Localizable.xcstrings` found
   under the target directory, else
   `<targetDir>/Localizable.xcstrings`. It is merged through
   the `StringCatalog` seam: `sourceLanguage` and `version`
   `1.0` are set; every discovered key gets a source-language
   unit (`translated`, value = the key itself) when missing;
   every target language gets the supplied translation
   (`translated`) when one is given, or a `"new"`-state
   placeholder unit with an empty value when it has none.
   Added/updated counts follow Legacy exactly: a new
   localization counts as added; replacing an existing
   localization with a different supplied translation counts
   as updated; an identical supplied translation is a no-op.
   A missing or invalid existing catalog starts from an empty
   one (Legacy's `readCatalog ?? [:]`). The merged catalog is
   committed, then re-read and verified: every discovered key
   must exist with a localization for every requested language
   (`Verification failed: the String Catalog was not written
   correctly.`).
4. When an Info.plist exists, `CFBundleLocalizations` is set
   to the languages and `CFBundleDevelopmentRegion` to the
   region, committed, and re-read to verify both values
   (failure after the catalog was written →
   `Wrote the String Catalog but failed to update Info.plist
   at '<name>'.` — the catalog stays written, Legacy's
   non-atomic behaviour). Without a plist, the note is
   `No Info.plist found; CFBundleLocalizations was not updated.`
5. Summary (Legacy's, verbatim in shape):
   `Localized app into <N> language(s): <langs>.` +
   `- Discovered <K> localizable key(s) in <F> Swift file(s).`
   (+ ` (<S> key(s) use a non-Localizable table and were
   skipped.)` when any were skipped) +
   `- String Catalog: <rel> — <T> key(s), <A> new localization(s)
   added, <U> updated with supplied translations.` +
   `- <plist note>` +
   `- Layout direction: <ltr|rtl>` (+ ` (RTL languages: …)`
   for `ar`, `he`, `fa`, `ur`) +
   `- Note: Info.plist keys <CFBundleName|CFBundleDisplayName>
   are best localized with InfoPlist.strings tables (see
   LocalizingApps.md), not the Localizable catalog.` (only
   when the plist has one of those keys) +
   `Next: call localization_audit to find keys still missing
   per locale.`

   Data: `count` (discovered keys), `path` (catalog, relative),
   `languages` (comma-joined), `layoutDirection`,
   `sourceLanguage`, `keysAdded`.

### `status`

Discovers keys the same way and reports: `Localization
status:` + `- Discovered keys in Swift: <N>` +
`- String Catalog: <absent|present (<K> keys, languages: <…>)>`
+ `- <Info.plist line>`, where the plist line is
`<name>: CFBundleLocalizations=[<…>],
CFBundleDevelopmentRegion=<…>.` or `No Info.plist found.`
Data: `count`, `languages` (the catalog's locales,
comma-joined), `layoutDirection` (`rtl` when any catalog
locale is RTL, else `ltr`), `sourceLanguage` (the catalog's,
or `unknown`).

### `set_development_region`

`development_region` is required
(`Missing required parameter: development_region for
action=set_development_region.`) and must be a valid code
(same `Invalid language code …` message as `localize`).
Without an Info.plist →
`No Info.plist found in the workspace; cannot set the
development region.` An unreadable plist →
`Info.plist at '<name>' is not a valid property list
dictionary.` The plist's `CFBundleDevelopmentRegion` is set
and committed, then verified
(`Failed to set CFBundleDevelopmentRegion in Info.plist.`).
When a `Localizable.xcstrings` sits beside the plist, its
`sourceLanguage` is set too; a failure of that second write
is ignored, exactly as in Legacy (the success message then
simply omits the ` Also set the String Catalog source
language to <region>.` note). Success:
`Set CFBundleDevelopmentRegion to '<region>' (was:
<before>).<note>` Data: `path` (plist, relative),
`sourceLanguage`.

Because the data keys vary by action, the tool has no static
output schema.

Error cases:

| Condition | Result |
|---|---|
| Unknown action | `Invalid action '<action>'. Expected localize, status, or set_development_region.` |
| `localize` without / with bad `languages` | `Missing required parameter: languages (1-3 language codes, e.g. ["es","fr","de"]).` / `Invalid language code '<code>'. …` / `Too many languages (<N>). Maximum 3 languages per Assist session; run again for more.` |
| Bad `development_region` | `Invalid development_region '<region>'. Expected a language code such as en.` (localize) / `Invalid language code '<region>'. …` (set_development_region) |
| `localize` with no discoverable keys | `No localizable strings found in Swift sources under '<dir>'. Wrap user-facing text in NSLocalizedString(_:comment:) or String(localized:) first.` |
| Catalog verification fails | `Verification failed: the String Catalog was not written correctly.` |
| Plist update fails after the catalog | `Wrote the String Catalog but failed to update Info.plist at '<name>'.` |
| `set_development_region` without a plist / bad plist | `No Info.plist found in the workspace; cannot set the development region.` / `Info.plist at '<name>' is not a valid property list dictionary.` / `Failed to set CFBundleDevelopmentRegion in Info.plist.` |
| Write refused in review / read-only server | `MCPServer.rejectedMessage` / `readOnlyMessage` (approval model) |

## 9. `string_catalog_migrator` — String Catalog Migrator

Legacy: `AssistStringCatalogMigratorTool.swift`. Capability
`fileModification`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; the catalog is written through `commit()`
(which creates parent directories — Legacy's raw
`data.write(to:)` did not, so a missing parent directory
failed in Legacy and succeeds here; deliberate deviation).

Description (verbatim): "Converts legacy .strings files into
modern Xcode 15+ String Catalogs (.xcstrings)."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "sourceStringsPath": {"type": "string", "description": "Relative path to the legacy .strings file."},
  "targetXcstringsPath": {"type": "string", "description": "Relative destination path for the .xcstrings file."}},
 "required": ["sourceStringsPath", "targetXcstringsPath"], "additionalProperties": false}
```

Behaviour (Legacy's, in order):

1. Missing `sourceStringsPath` / `targetXcstringsPath` →
   `Missing required parameter: sourceStringsPath` (etc.).
   Both paths are confined with the session resolver
   (`resolveFileReadingPath`): Legacy used absolute paths
   as-is, so an absolute path outside the workspace was
   honoured — Ycode refuses it (deliberate deviation, §1).
2. The source must exist: `Source .strings file not found:
   <srcPath>`. It must read as UTF-8: `Unable to read .strings
   content at <srcPath>`.
3. Entries are parsed with Legacy's regex
   `"key" = "value";` (escaped characters kept raw — no
   unescaping, as in Legacy). Each key becomes a catalog entry
   with `extractionState` `manual` and an `en` localization
   (`translated`, value = the entry's value); duplicate keys
   keep the last value. The catalog's `sourceLanguage` is
   `en` and `version` is `1.0`. The write goes through the
   `StringCatalog` seam (`addKey` + `setTranslation`), which
   preserves Legacy's content and key order (sorted).
4. Success: `Successfully migrated <N> localization keys from
   \`<srcPath>\` to String Catalog \`<dstPath>\`.`, where `<N>`
   is the distinct-key count.

Output: plain text (Legacy carries no data).

Error cases: as in steps 1–2 above, plus the approval
refusals (`rejectedMessage` / `readOnlyMessage`).

## 10. `strings_file_validate` — Strings File Validate

Legacy: `AssistStringsFileValidateTool.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Validates .strings localization files:
syntax errors, duplicate keys, and empty values."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "path": {"type": "string", "description": "Workspace-relative path to the .strings file."}},
 "required": ["path"], "additionalProperties": false}
```

Behaviour (Legacy's, verbatim):

1. Missing/blank `path` → `Missing required parameter: path`.
   The path goes through the strict resolver (§2); an
   unreadable file → `Cannot read file at: <path>`. The file
   is decoded as UTF-8, else UTF-16, else empty; an empty or
   undecodable file → `File is empty or undecodable: <path>`.
2. Every line is checked against Legacy's entry pattern
   `^\s*"key"\s*=\s*"value"\s*;\s*$` (keys/values may contain
   escapes). Blank lines and lines starting with `//` or `/*`
   are skipped — note that a `*` continuation line of a block
   comment is NOT skipped here (unlike
   `localization_manager`'s `validate`, §7) and is reported
   malformed, exactly as in Legacy. A matching line counts as
   valid; a repeated key counts as a duplicate; an empty value
   counts as an empty value. A non-matching, non-skipped line
   counts as malformed (its first 100 characters are kept).
3. Summary:
   `Strings validation for <path>:` +
   `- Valid entries: <V>` + `- Duplicate keys: <D>` +
   `- Malformed lines: <M>` + `- Empty values: <E>` +
   up to 20 `  DUPLICATE: <key>` lines +
   up to 20 `  MALFORMED line <N>: <text>` lines +
   up to 20 `  EMPTY VALUE: <key>` lines.
   The call succeeds even when the file is invalid — the
   verdict is in the data: `passed` is true only when there
   are no duplicates and no malformed lines (empty values do
   not fail the file, as in Legacy).

Output (structured): `valid`, `duplicates`, `malformed`,
`emptyValues` (ints), `passed` (bool).

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `path` | `Missing required parameter: path` |
| Path refused / file unreadable | `Cannot read file at: <path>` |
| File empty or undecodable | `File is empty or undecodable: <path>` |
| No workspace open | `no workspace is open: call workspace_open …` |

## 11. `strings_localization` — Localization Strings

Legacy: `AssistStringsLocalizationTool.swift`. Capability
`fileModification`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; `set` / `delete` write through `commit()`
(the whole new file text for `.strings`, the serialised
catalog for `.xcstrings`). `get` writes nothing but is still
`writes: true` (§1).

Description (verbatim): "Gets, sets, or deletes a localization
string in Localizable.strings or Localizable.xcstrings."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "action": {"type": "string", "description": "get, set, or delete. Default: get."},
  "key": {"type": "string", "description": "Localization key (required)."},
  "value": {"type": "string", "description": "Value for set action."},
  "locale": {"type": "string", "description": "Locale code such as en or fr. Default: en."},
  "path": {"type": "string", "description": "Optional workspace-relative path to a specific .strings or .xcstrings file."}},
 "required": ["key"], "additionalProperties": false}
```

Behaviour (Legacy's, in order):

1. Missing/blank `key` → `Missing required parameter: key`.
   `action` defaults to `get`; anything other than `get` /
   `set` / `delete` → `Invalid action '<action>': must be get,
   set, or delete.` `set` requires a non-empty `value`
   (`Missing required parameter: value for set action.`).
   `locale` defaults to `en`; an empty locale, or one
   containing `/` or `..`, → `Invalid locale.`
2. With `path`, the strict resolver (§2) must accept it
   (`Invalid path '<path>': must be inside the workspace and
   must not contain '..'.`) and the file must exist
   (`Localization file not found at '<path>'.`). Without
   `path`, the file is found in Legacy's order:
   `<locale>.lproj/Localizable.strings`,
   `Localizable.xcstrings` (workspace root),
   `en.lproj/Localizable.strings`,
   `Localizable.strings` (workspace root), then the first
   `Localizable.strings` / `Localizable.xcstrings` found by
   enumerating the workspace. None found →
   `No Localizable.strings or Localizable.xcstrings found for
   locale '<locale>'. Pass path to a specific file.`
3. Any other extension →
   `Unsupported localization file type: <name>. Expected
   .strings or .xcstrings.`
4. `.strings` `get`: the first line whose key matches wins:
   `Key '<key>' = "<value>" in <name>.` with data `key`,
   `value`, `file`; otherwise `Key '<key>' not found in
   <name>.` `.strings` `set`: the matching line is replaced
   in place, otherwise `"key" = "value";` is appended; the
   write is verified to contain the new line
   (`Verification failed: key not present after write.`).
   Success: `Set key '<key>' in <name>.` with data `key`,
   `value`, `file`. `.strings` `delete`: a missing key →
   `Key '<key>' not found in <name>.`; otherwise the line is
   removed. Success: `Deleted key '<key>' from <name>.`
   with data `key`, `file`. An unreadable `.strings` file →
   `Failed to read <name>.`
5. `.xcstrings` `get`: `Key '<key>' (<locale>) = "<value>" in
   <name>.` with data `key`, `value`, `locale`, `file`;
   otherwise `Key '<key>' not found for locale '<locale>' in
   <name>.` `.xcstrings` `set`: the locale's unit is set to
   state `translated` (creating the key when missing).
   Success: `Set key '<key>' (<locale>) in <name>.` with data
   `key`, `value`, `locale`, `file`. `.xcstrings` `delete`:
   the locale is removed; when it was the key's last locale
   the key is removed. A missing key/locale →
   `Key '<key>' not found for locale '<locale>' in <name>.`
   Success: `Deleted key '<key>' (<locale>) from <name>.`
   with data `key`, `locale`, `file`. An unreadable or
   invalid `.xcstrings` file →
   `Failed to read <name> as JSON.`

Because the data keys vary by action and file type, the tool
has no static output schema.

Error cases: as in steps 1–5 above, plus the approval
refusals (`rejectedMessage` / `readOnlyMessage`).

## 12. Deliberate deviations from Legacy (summary)

| # | Deviation | Reason |
|---|---|---|
| 1 | Every path is confined to the workspace. Legacy's `asset_catalog_manager`, `localization_manager`, `string_catalog_migrator`, and `localize_app` appended paths unchecked, so `..` escaped. | Workspace confinement is the Ycode rule (approval model §7); the unchecked append is a sandbox hole, not a feature. |
| 2 | A `..` that stays inside the workspace is still refused by the slice's strict resolver, where the session resolver would allow it. | These tools' Legacy messages say `..` is forbidden; the message must stay honest. |
| 3 | `create_colorset` keeps Legacy's hardcoded colour components and ignores the hex arguments in the file (only the message uses them). | Preserving Legacy's exact file bytes; changing them is a behaviour change for a later wave (§4). |
| 4 | `asset_catalog_manager` rejects an `assetName` containing `/`, `\`, or `..`; Legacy did not check it. | Confinement: the name is appended to the catalog path. |
| 5 | `localization_manager`'s `.xcstrings` `add_translation` on a new file writes the seam's canonical empty catalog (`sourceLanguage` + `version`); Legacy's new file had neither key. | The `StringCatalog` seam's canonical form; the file is a valid catalog either way. |
| 6 | `string_catalog_migrator` writes through `commit()`, which creates parent directories; Legacy's raw write failed when the parent was missing. | `commit()` is the only gate; refusing to create parents would make the tool unusable for nested destinations. |
| 7 | `localize_app` `set_development_region` ignores a catalog-write failure (including a review refusal of the catalog change) after the plist is committed, as Legacy ignores its catalog-write failure. | Legacy's tolerant behaviour; the plist change stands either way. |
| 8 | Structured data uses typed JSON values (ints, bools) where Legacy's map held strings only; `localize_app`'s `count`/`keysAdded`, the audit's counts, and the validator's counts are ints, `passed` is a bool. | The Ycode convention from Waves 1–6; keys are unchanged. |
| 9 | Legacy's `suggestedNextActions: ["localization_audit"]` on `localize_app` is dropped (Ycode's `MCPToolResult` has no such field); the "Next: call localization_audit …" line in the summary keeps the pointer. | Same as Wave 2's dropped envelope fields (approval model §7.4). |
| 10 | Legacy's `LiveDiffStreamer`, `XcodeProjWriter.addFileReference`, and `ProjectSessionStore.recordAssistFileMutation` side channels are not ported. | Approval model §7.4: no unreviewed side writes. New files are not auto-registered in any project file. |

## 13. What is NOT ported (honest gaps)

None of the 9 tools is honestly failing: all 9 are implemented
with their Legacy behaviour. The honest refusals inside the
slice are Legacy's own, preserved verbatim:

- `localization_manager` `add_translation` on a `.stringsdict`
  file is refused (§7 step 5): entries are plural/format-rule
  dictionaries, and writing a plain string would corrupt them.
- `localize_app` `localize` fails when no localizable keys are
  discovered (§8): it does not invent keys.

## 14. Legacy aliases (from `AssistToolRegistry.toolAliases`)

| Alias | Target |
|---|---|
| `asset_catalog` | `asset_catalog_manager` |
| `localization` | `localization_manager` |
| `string_catalog` | `string_catalog_migrator` |

No other alias in the registry points at any of the 9 slice
IDs. Aliases live in `MCPServer.toolAliases`, which the
coordinator owns — they are recorded here, not added by this
slice.

## 15. Evidence

| Claim | Level | Source |
|---|---|---|
| All 9 IDs, titles, descriptions, schemas, capabilities, risk levels, messages, and behaviours | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistAssetCatalogListTool.swift`, `AssistAssetCatalogTool.swift`, `AssistAssetImageAddTool.swift`, `AssistLocalizationAuditTool.swift`, `AssistLocalizationTool.swift`, `AssistLocalizeAppTool.swift`, `AssistStringCatalogMigratorTool.swift`, `AssistStringsFileValidateTool.swift`, `AssistStringsLocalizationTool.swift` (main @ `d51a8f0d`), read directly |
| `AssistToolDataKey.count` / `.path` are `"count"` / `"path"` | 1 | Legacy `SwiftCode/Backend/Assist/AssistModels.swift:356` |
| `AssistWorkspacePaths.resolve` rejects any `..` as text; absolute paths must be inside the workspace | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistToolSharedHelpers.swift:12` |
| Aliases `asset_catalog`, `localization`, `string_catalog` | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift:430` (alias table) |
| `StringCatalog` seam: parse/write, `sourceLanguage`, `keys`, `languages`, `setTranslation`, `addKey`, `removeKey`, `setState`, public `json` with a setting subscript | 1 | Destination `ycode/Sources/YcodeStrings/StringCatalog.swift`, read directly |
| `YcodeStrings` is re-exported by `YcodeIDECore` (`@_exported import YcodeStrings`); `YcodeAssetCatalog` is not visible to `YcodeMCP` (no target dependency in `ycode/Package.swift`) | 1 | Destination `ycode/Sources/YcodeIDECore/Model/StringsExport.swift`, `ycode/Package.swift` |
| `commit()` / `MCPChange` / `approve()` gate, `MCPWritePolicy` modes, `readOnlyMessage`, `rejectedMessage`, `run()` refusal/pre-grant/review wiring | 1 | Destination `ycode/Sources/YcodeMCP/YcodeTools+Content.swift` (`commit`), `ycode/Sources/YcodeMCP/MCPServer.swift` (`run`, `readOnlyMessage`, `rejectedMessage`), `specs/ide/assist-approval-model.md` |
| Session resolver `resolveFileReadingPath`, `fileReadingRelativePath`, `session(for:)`, `text(of:)` | 1 | Destination `ycode/Sources/YcodeMCP/YcodeTools+FileReadingSupport.swift`, `YcodeMCPHost.swift` |
| Test format (`firstText`, never exact `resultText ==` on structured results; `opened` helper; `policy: .allow` for writes; `TempSample` fixtures) | 1 | Destination `ycode/Tests/YcodeMCPTests/TestSupport.swift`, `YcodeTestingToolsTests.swift` |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

