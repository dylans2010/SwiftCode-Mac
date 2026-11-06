# Assist testing / QA tools — behaviour (Wave 6)

SwiftCode modules: `SwiftCodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 79 Legacy Assist Testing/QA
tools ported in Wave 6: test running & coverage (16, Part A), static
analysis (22, Part B), security/privacy/platform audits (18, Part C),
and docs/review/repo tooling (23, Part D). The catalogue
(`assist-tool-catalogue.md`, §166–§249) is the single source of truth for
each tool's ID, title, description, input schema, output shape,
capability, risk level, permission, and read/write classification; this
spec is the single source of truth for how the tools behave.

## Part A — Test running / coverage

## Assist test-running / coverage tools — behaviour (Wave 6, slice A)

SwiftCode modules: `SwiftCodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 16 Legacy test-running
and coverage tools ported in Wave 6, slice A: running one test,
discovering XCTest cases, parsing test logs, detecting flaky tests,
coverage reporting (two tools), test-data fixtures, snapshot
management, adding a test target, UI-test scaffolding, the SwiftUI
interface/accessibility audit, preflight checks, benchmarking,
compiler diagnostics, crash-log parsing, and runtime diagnostics.
The implementation is `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Testing.swift`
(+ `SwiftCodeTools+TestingSupport.swift`); the tests are
`swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeTestingToolsTests.swift`.

The per-tool sections below are catalogue-ready: each gives the
tool's description and input schema verbatim (Legacy's
`parametersSchema` plus the `workspace` parameter every SwiftCode tool
carries), its output shape, and its error cases, so the coordinator
can merge them into `specs/ide/assist-tool-catalogue.md` without
re-deriving anything.

Scope: what each tool does once called, what it returns, what it
refuses, and which SwiftCode seam it runs through. The approval model
itself (write policy, `commit()` / `approve()`, the rejected
Autopilot bypass) is `specs/ide/assist-approval-model.md` and is
not repeated here beyond the per-tool gate column.

## 1. Conventions shared by the slice

- **IDs, titles, descriptions, schemas are Legacy's verbatim**,
  verified live from each Legacy tool file (see Evidence). The
  only additions are the `workspace` parameter and SwiftCode's
  `additionalProperties: false`. Legacy's parameter-name aliases
  (`filePath`, `file_content`, …) are NOT supported: SwiftCode's
  argument validation rejects unknown arguments before the handler
  runs.
- **Structured data keeps Legacy's keys, with typed JSON values**
  (integers, booleans, doubles) the way SwiftCode's other tools do —
  Legacy's string-only map is not reproduced. Tools whose Legacy
  result carries no data return a plain text result instead.
- **Paths resolve through the session resolvers**
  (`resolveFileReadingPath`, `fileReadingRelativePath`) and never
  escape the workspace. A path the resolver refuses fails with the
  Legacy tool's own message for that tool (e.g. `logPath must be
  inside the workspace and must not contain '..'.`), not the
  resolver's message. A `..` that stays inside the workspace
  resolves (the session resolver's rule) where Legacy's per-tool
  resolvers rejected any `..` as text.
- **Failures are thrown as `MCPToolError`** with Legacy's message
  text, so the caller sees an `isError` result carrying that
  message. Legacy's `.failure(…)` and SwiftCode's throw are the same
  observable outcome.
- **Risk / gate.** `safeRead` tools are `writes: false`,
  `readOnly: true, idempotent: true`. `execution` tools are
  `writes: false`, `readOnly: false, idempotent: false` (they run
  something; they change no file). `safeMutation` tools are
  `writes: true`, `readOnly: false, idempotent: true`, and go
  through `commit()` (text writes) or an explicit `MCPChange` +
  `approve()` per file (snapshot deletions). There is no second
  gate, no Autopilot, no bypass.
- **No result is ever invented.** Test execution runs the real
  runner and reports its actual outcomes; coverage reports the
  coverage the run actually gathered (or says plainly that none
  was gathered); diagnostics report the build's actual issues.
- **No Swift toolchain exists in this environment** (Linux CI):
  the implementation and tests are statically checked only.
  `swift build` / `swift test` and the Mac live runs stay pending
  on Dylan's Mac. Tests that need a toolchain are gated on
  `canBuildPackages`, like the `test` tool's own tests.

## 2. The test-runner seam (read before implementing the runners)

The slice reuses SwiftCode's own test-runner seam and builds no
parallel runner:

- **Discovery:** `WorkspaceSession.discoverTests()` +
  `testsDiscovered()`, then `s.tests` (`[DiscoveredTest]`:
  `suite`, `name`, `file`, `line`, `kind` — `.xctest` or
  `.swiftTesting`; `identifier` is `Suite/name`; `runnerIdentifier`
  is `<Target>/Suite/name` for projects, `Suite/name` for
  packages). `TestDiscovery` finds XCTest methods (`func test…`
  directly in a class naming `XCTestCase` among its supertypes)
  and swift-testing functions (a `func` preceded by `@Test`), in
  Swift sources, plus Objective-C XCTest (`- (void)test…` in an
  `@implementation` whose `@interface` extends `XCTestCase`).
  Implementation: `swiftcode/Sources/SwiftCodeIDECore/Model/TestDiscovery.swift`;
  spec: `specs/ide/testing.md` §Discovery.
- **Running:** `WorkspaceSession.runTests(only: [DiscoveredTest])`
  → `[TestOutcome]` (`suite`, `name`, `status` passed/failed/
  skipped, `failures: [Diagnostic]`, `duration`). It re-discovers
  before each run, runs through the selected test runner
  (swiftcodebuild for projects, SwiftPM's own runner for packages),
  and records the run in `s.reports`. The `test` tool
  (`SwiftCodeTools+Build.swift`) is the reference caller: it applies
  the scheme/destination first (`applyScheme`), saves all files
  (`delegate?.mcpHostSaveAll()`), reports progress
  (`reportingActivity`), and derives `status` as `failed` when any
  outcome failed or the newest report did not succeed.
- **Results parsing:** `SwiftCodeBuild/TestResults.swift`
  (`TestOutcome`, `TestResultParser`) reads runner output: XCTest
  `Test Case '…' passed` lines (Darwin `-[Module.Class test]`
  and Linux `Class.test` forms) and swift-testing `✔` / `✘` /
  `➜` lines.
- **Coverage:** `SwiftCodeXcodebuild/Coverage.swift`
  (`CoverageData`: targets → files → functions/lines, gathered
  with the toolchain's open-source `llvm-cov` from the merged
  profile, in its two result-bundle forms) and
  `WorkspaceSession+Coverage.swift` (`latestCoverage`:
  `[CoverageItem]` — `name`, `coveredLines`,
  `executableLines`, `files`, `fraction` — from the newest report
  that has any). A run gathers coverage only when the scheme's
  Test action enables it (`WorkspaceSession.gathersCoverage`:
  the scheme document's TestAction `codeCoverageEnabled ==
  "YES"`). `CoverageModel.percent` formats a fraction as
  `"NN.N%"`.
- **Result bundles:** `SwiftCodeXcodebuild/XCResultReader.swift`
  reads the result bundles swiftcodebuild writes (`XCResultStore`:
  Zstandard-framed objects); `TestActions.swift` is swiftcodebuild's
  `test` / `test-without-building` implementation (tests run in
  the platform's own `xctest` runner; swift-testing hooks into
  it); `SwiftTestingBridge.swift` bridges swift-testing.
- **What the seam does NOT provide,** and therefore what the
  slice does not fake: a process exit code for a test run (the
  runner reports per-test outcomes, so `test_run_single` has no
  `exitCode` key); an `.xcresult` path for a coverage run
  (SwiftCode's runner writes its own reports, so
  `test_coverage_report` has no `resultBundle` key); an
  `.xccovreport` reader (that format is read by the real `xcrun
  xccov`, §8, not by the llvm-cov seam).

## 3. `test_run_single` — Run Single Test

Legacy: `AssistTestRunSingleTool.swift`. Capability `testing`,
risk `execution`. Gate: none (no file is written).

Description (verbatim): "Runs one test by ID with xcodebuild test
-only-testing and returns pass/fail plus the output tail."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "testId": {"type": "string", "description": "Required. Test identifier, e.g. MyTests/MyTest/testExample."},
  "scheme": {"type": "string", "description": "Scheme to test. Defaults to the first scheme listed by xcodebuild."},
  "destination": {"type": "string", "description": "xcodebuild destination. Default: platform=macOS."}},
 "required": ["testId"], "additionalProperties": false}
```

Behaviour:

1. `testId` is trimmed; missing/blank → `Missing required
   parameter: testId`. It must pass Legacy's validity rule (at
   least two `/`-separated components, no spaces or newlines,
   none of `;|&$`"'<>\!(){}[]*?~#`, no `..`) or the call fails
   with `testId '<id>' is not valid. Expected a form like
   MyTests/MyTest/testExample with no spaces or shell
   characters.`
2. `destination` defaults to `platform=macOS`; `scheme` is
   optional. Either containing a shell character (`;|&$`"'<>\!()`
   or a newline) fails first with Legacy's message
   (`destination contains characters that are not allowed.` /
   `scheme contains characters that are not allowed.`).
3. The scheme/destination are applied with `applyScheme` (the
   `test` tool's path): `destination` is a SwiftCode destination
   name/id/specifier — Legacy's default `platform=macOS` is the
   specifier of the "My Mac" destination and matches as-is. An
   unknown scheme/destination fails with the `test` tool's
   messages (`no scheme "…"`, `no destination "…"`).
4. All files are saved, the tests are discovered, and the test is
   matched the way the `test` tool matches: `identifier`,
   `runnerIdentifier`, bare `name`, `suite`, or
   `Suite/name()`. No match fails with `no test "<id>" was found
   in the sources; tests: <first 40 identifiers>`.
5. The test runs through `runTests(only:)` with progress
   reporting. The summary is Legacy's shape: `Single test <id> —
   Passed|Failed (<container> / <scheme>)`, plus one line per
   failed outcome (`✗ Suite/name` + up to 3 failure
   descriptions), or `No test ran.` + the last 20 log lines when
   nothing ran and the run failed.

Output (structured): `status` ("Passed"/"Failed", Legacy
capitalisation), `testId`, `scheme`, `passed` / `failed` /
`skipped` (ints), `tests` (array of `{suite, name, status,
seconds, failures[]}` in the `test` tool's shape), `logTail`
(last 30 build-log lines).

Deviations from Legacy (deliberate): no `/usr/bin/xcodebuild`
is spawned and no `-only-testing:` argument is built — the run
goes through the session seam (§2), so it works on SwiftPM
packages as well as Xcode projects and never shells out. The
result has no `exitCode` key (the seam reports per-test
outcomes, not a process exit code), and the output tail is the
session build log's tail rather than xcodebuild's stdout tail.
A testId discovery cannot find fails with the `test` tool's
"no test … was found" message instead of xcodebuild failing on
it.

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `testId` | `Missing required parameter: testId` |
| Invalid `testId` form | `testId '…' is not valid. Expected a form like MyTests/MyTest/testExample with no spaces or shell characters.` |
| Unsafe `destination` / `scheme` | `destination contains characters that are not allowed.` / `scheme contains characters that are not allowed.` |
| No workspace open | `no workspace is open: call workspace_open …` |
| Unknown scheme / destination | `no scheme "…"…` / `no destination "…"…` |
| Test not discovered | `no test "…" was found in the sources…` |

## 4. `xctest_discovery` — XCTest Discovery

Legacy: `AssistXctestDiscoveryTool.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Discovers XCTestCase subclasses and
their test methods across the workspace — a test inventory
without running anything."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."}},
 "required": [], "additionalProperties": false}
```

Behaviour: the session's discovery runs (`discoverTests` /
`testsDiscovered`), the results are filtered to XCTest
(`kind == .xctest`) and grouped by suite (class name), each
with its file (first seen) and test-method count, sorted by
class name. Nothing is run.

Output (structured): `classCount`, `testCount` (ints).
Summary: `XCTest inventory: <N> test classes, <M> test
methods:` followed by `- <Class> — <relative file> (<K>
tests)` per class; when none are found, `No XCTestCase
subclasses found in the workspace.` with both counts 0.

Deviations from Legacy: the inventory comes from the session's
discovery rather than Legacy's regex scan of Swift files, so
swift-testing `@Test` functions are not counted (Legacy only
saw XCTestCase subclasses either), a test class with no test
methods does not appear (Legacy's line scan listed it with 0),
and Objective-C XCTest classes are found too, through the same
discovery the `test` tool uses.

Error cases: none beyond "no workspace is open".

## 5. `test_log_parse` — Parse Test Log

Legacy: `AssistTestLogParseTool.swift`. Capability `testing`,
risk `safeRead`. Gate: none.

Description (verbatim): "Parses a test log for passed/failed
test cases, suite summaries, and errors, returning counts plus
the failed test list."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "logPath": {"type": "string", "description": "Required. Workspace-relative path to a test log file."}},
 "required": ["logPath"], "additionalProperties": false}
```

Behaviour (Legacy's line scan, verbatim): a line containing
`Test Case` with ` passed` (and not ` failed`) counts as
passed; with ` failed` (and not ` passed`) counts as failed
and contributes its test name (the quoted `Test Case '…'` name
first, else the `-[…]` form) to the failed list, deduped in
first-seen order. A line containing `Test Suite` and `passed`
or `failed` is a suite summary. A line containing `: error:` or
starting with `error:` is an error line.

Output (structured): `total`, `passed`, `failed`,
`errorCount` (ints), `failedTests` (comma-joined string).
Summary: `Test log '<logPath>': <total> test case(s), <passed>
passed, <failed> failed, <errors> error line(s).`, then
`Failed tests:` + the list, `Suite summaries:` + the first 10,
`Errors:` + the first 10 (each section only when non-empty).

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `logPath` | `Missing required parameter: logPath` |
| Path refused by the resolver | `logPath must be inside the workspace and must not contain '..'.` |
| File does not exist | `Log file not found at '<logPath>'.` |
| File is not UTF-8 text | `Could not read log file at '<logPath>' as UTF-8 text.` |

## 6. `test_flaky_detect` — Flaky Test Detection

Legacy: `AssistTestFlakyDetectTool.swift`. Capability
`testing`, risk `safeRead`. Gate: none.

Description (verbatim): "Parses test logs and reports tests
that show both pass and fail outcomes across runs."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "logPath": {"type": "string", "description": "Workspace-relative path to a test log file."},
  "logsDir": {"type": "string", "description": "Workspace-relative path to a directory of test log files. Used when logPath is empty."}},
 "required": [], "additionalProperties": false}
```

Behaviour: `logPath` wins when non-empty; otherwise
`logsDir` is listed for `.log` / `.txt` files (sorted by
path). One outcome is recorded per `Test Case` line that says
exactly one of passed/failed (lines saying both or neither are
ignored); the test name is extracted as in §5. A test is flaky
when it has at least one pass and at least one fail across the
files read. Unreadable files are skipped (they do not count
toward `filesRead`).

Output (structured): `filesRead`, `flakyCount` (ints),
`flakyTests` (comma-joined string, sorted). Summary: `Flaky
test scan across <N> log file(s): <D> distinct tests observed,
<F> flaky.` plus `No test showed both a pass and a fail.` when
none are flaky, else `- <test>: <P> pass, <F> fail` per flaky
test (sorted).

Error cases:

| Condition | Result |
|---|---|
| Neither `logPath` nor `logsDir` | `Provide logPath or logsDir.` |
| `logPath` refused / missing | `logPath must be inside the workspace and must not contain '..'.` / `Log file not found at '<logPath>'.` |
| `logsDir` refused / not a directory / unreadable | `logsDir must be inside the workspace and must not contain '..'.` / `Logs directory not found at '<logsDir>'.` / `Could not list logs directory at '<logsDir>'.` |
| `logsDir` has no `.log`/`.txt` files | `No .log or .txt files found in '<logsDir>'.` |

## 7. `test_coverage_report` — Test Coverage Report

Legacy: `AssistTestCoverageReportTool.swift`. Capability
`testing`, risk `execution`. Gate: none (no file is written).

Description (verbatim): "Runs xcodebuild test with code
coverage enabled and reports the coverage summary plus
pass/fail."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "scheme": {"type": "string", "description": "Scheme to test. Defaults to the first scheme listed by xcodebuild."},
  "destination": {"type": "string", "description": "xcodebuild destination. Default: platform=macOS."}},
 "required": [], "additionalProperties": false}
```

Behaviour:

1. `destination` defaults to `platform=macOS`; the
   shell-character guards run first with Legacy's messages
   (§3).
2. The scheme/destination are applied with `applyScheme`, all
   files are saved, and the whole suite runs through
   `runTests()` with progress reporting.
3. Coverage comes from the session's latest coverage rows
   (`latestCoverage`, §2) — the run gathers it only when the
   scheme's Test action enables code coverage. The overall
   percent is covered ÷ executable lines over all targets;
   per-target lines give each target's percent and counts.
4. `status` is "Failed" when any test failed or the newest
   report did not succeed, else "Passed" (Legacy capitalisation).

Output (structured): `status`, `scheme`, `coverage` (the
overall percent as a string, `"82.5"` — `""` when nothing was
gathered, as in Legacy), `passed` / `failed` / `skipped`
(ints). Summary: `Test Coverage — <container> / <scheme>:
<status>` + the coverage text + `Executed <N> test(s): <P>
passed, <F> failed, <S> skipped.`

Deviations from Legacy (deliberate): coverage is read from the
session's coverage rows, not parsed out of `xcodebuild` stdout
for `%` lines, and there is no `build/TestResults.xcresult`
result bundle — SwiftCode's runner writes its own reports and no
xcresult path is exposed, so there is no `resultBundle` key.
When the scheme does not gather coverage the tool says so
plainly (`No coverage data was gathered for this run. Enable
code coverage in the scheme's Test action and run again.`)
instead of reporting a coverage number. No `/usr/bin/xcodebuild`
is spawned.

Error cases: unsafe `destination` / `scheme` (Legacy
messages, §3); no workspace open; unknown scheme/destination
(`test` tool messages).

## 8. `test_coverage_reporter` — Test Coverage Reporter

Legacy: `AssistTestCoverageReporterTool.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Extracts line and target test
coverage metrics from build and test artifacts via xccov."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "reportPath": {"type": "string", "description": "Optional explicit path to an .xccovreport file."}},
 "required": [], "additionalProperties": false}
```

Behaviour:

1. With an explicit `reportPath`: an absolute path is used
   as-is (Legacy behaviour); a relative path resolves against
   the workspace root. This is the slice's deliberate,
   read-only exception to workspace confinement — the tool's
   purpose is reading coverage artifacts, which live in
   DerivedData by design — in the same class as
   `preflight_checks`' DerivedData check (§13).
2. Without one: the newest `.xccovreport` / `.xccovarchive`
   under `~/Library/Developer/Xcode/DerivedData`, by
   modification date (Legacy's search, verbatim).
3. Finding nothing is a **success** with Legacy's message
   (`No active .xccovreport or coverage archive found in
   DerivedData. Ensure 'Code Coverage' is enabled in your Xcode
   Scheme test settings.`), not a failure.
4. Otherwise the real `xcrun xccov view --report <path>` runs
   as a fixed argument vector (`terminalRunFixed`, 60 s
   timeout, off the main actor), never a shell. Its combined
   stdout+stderr, trimmed, is reported: empty output →
   `Coverage report found at <name>, but yielded no text
   metrics.`; otherwise `### Test Coverage Report (<name>):`
   followed by the first 40 lines in a code fence (Legacy's
   markdown shape, verbatim).

Output: plain text (Legacy carries no data). The exit code of
`xccov` is ignored, as in Legacy.

Error cases:

| Condition | Result |
|---|---|
| `xcrun` cannot start (e.g. Linux, no Xcode tools) | `Failed to execute xccov: /usr/bin/xcrun is not available on this machine.` |

Honest limitation: on a machine without Xcode command line
tools this tool cannot read anything — it fails with the
message above and never invents coverage. It is not
"honestly failing" in the Wave 2 `code_refactor` sense: on
macOS with a real report it runs the real `xccov` and reports
its real output.

## 9. `test_data_factory` — Test Data Factory

Legacy: `AssistTestDataFactoryTool.swift`. Capability
`testing`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; the fixture is written through `commit()`.

Description (verbatim): "Writes a test fixture file: a JSON
object with sample values per field type, or a Swift struct
with a static sample."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "name": {"type": "string", "description": "Required. Valid Swift identifier used for the fixture type and file name."},
  "kind": {"type": "string", "description": "json or swift. Default: json."},
  "fields": {"type": "string", "description": "Optional comma list, e.g. id:Int,name:String,isActive:Bool. Defaults to id:Int,name:String."},
  "path": {"type": "string", "description": "Optional workspace-relative directory or file path. Default: TestData/."},
  "overwrite": {"type": "string", "description": "Must be 'true' to replace an existing file. Default: 'false'."}},
 "required": ["name"], "additionalProperties": false}
```

Behaviour: `name` must be a valid Swift identifier (letter
or `_` first, then letters/digits/`_`). `kind` is `json` or
`swift` (case-insensitive, default `json`). `fields` is a
comma list of `name:Type` (a bare name defaults to `String`;
every field name must be a valid identifier, every type
non-empty, at least one field must survive). `path` defaults
to `TestData/`; a trailing `/` names a directory for
`<name>.<ext>`, a `.json`/`.swift` suffix names the file
itself, anything else is treated as a directory. An existing
file refuses the write unless `overwrite` is `"true"` (the
schema type is string, kept verbatim; a boolean `true` is also
accepted by the handler).

Sample values (Legacy, verbatim): integers → `1`; doubles /
floats → `3.14`; booleans → `true`; `Date` → JSON
`"2026-01-01T00:00:00Z"` / Swift
`Date(timeIntervalSince1970: 1767225600)`; `URL` →
`https://example.com/<field>`; `UUID` →
`00000000-0000-4000-8000-000000000001`; `[String]` →
`["Sample <field>"]`; `[Int]` → `[1]`; anything else →
`"Sample <field>"` (JSON) / `"Sample <field>"` (Swift).
The JSON body is one object, two-space indent, trailing
newline. The Swift body is `import Foundation` + `struct
<name>` with the fields + `static let sample = <name>(…)`,
trailing newline.

Output (structured): `path` (workspace-relative), `kind`,
`name`. Summary: `Created test fixture at <path>`.

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `name` | `Missing required parameter: name` |
| Invalid `name` | `name '…' is not a valid Swift identifier. Use letters, digits, and underscores, starting with a letter or underscore.` |
| `kind` not `json`/`swift` | `kind must be 'json' or 'swift'.` |
| Bad field | `Field name '…' is not a valid Swift identifier.` / `Field '…' has an empty type.` / `fields produced no usable fields.` |
| Path refused (`..`, or outside the workspace) | `path must be inside the workspace and must not contain '..'.` |
| File exists, no overwrite | `File already exists at '<path>'. Pass overwrite='true' to replace it.` |
| Write refused in review / read-only server | `MCPServer.rejectedMessage` / `readOnlyMessage` (approval model) |

Deviation: an absolute `.json`/`.swift` path outside the
workspace is refused (Legacy used it as-is); the file is
written through `commit()` (parents created, session notified)
rather than Legacy's direct write.

## 10. `test_snapshot_manage` — Manage Test Snapshots

Legacy: `AssistTestSnapshotManageTool.swift`. Capability
`testing`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`. **The flag is static per tool**: the `list`
action writes nothing, but in `readOnly` mode even a list call
is refused in `run()` before the handler, exactly as the
approval model specifies for dry-run tools.

Description (verbatim): "Lists snapshot test reference images
under __Snapshots__ directories, or deletes unreferenced
snapshot files when confirm is true."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "action": {"type": "string", "description": "list or clean. Default: list."},
  "confirm": {"type": "string", "description": "Must be 'true' for clean. Any other value refuses to delete."}},
 "required": [], "additionalProperties": false}
```

Behaviour: snapshot files are image/text/json files
(`png`, `jpg`, `jpeg`, `gif`, `txt`, `json`) under any
`__Snapshots__` directory, skipping `.git`, `build`,
`DerivedData` and `Pods`, sorted by path.

- `list` (default): `Snapshot references: <N> file(s) under
  __Snapshots__ directories.` + one `- <relative path>` line
  per file; `No snapshot files found under any __Snapshots__
  directory in the workspace.` when there are none. Data:
  `count`, `files` (comma-joined relative paths).
- `clean`: requires `confirm` to be exactly `"true"`
  (case-insensitive; a boolean `true` does NOT satisfy it —
  Legacy checks the string only). Files are checked against
  the workspace's Swift source text (every `.swift` file
  outside `__Snapshots__`, same skips): a file is referenced
  when its base name appears in the sources, or any
  `.`-separated part of at least 3 characters does, or the
  base name with its digits stripped (at least 3 characters)
  does. Each unreferenced file is deleted only after its own
  `MCPChange` + `approve()` (`Delete unreferenced snapshot
  <path>`); the first refusal stops the clean with
  `rejectedMessage`, and files approved before it stay
  deleted. A delete that fails is reported as kept with its
  error. Summary: `Snapshot clean: deleted <D> unreferenced
  file(s), kept <K>.` + `Deleted:` / `Kept:` lists. Data:
  `deletedCount`, `keptCount`, `deleted` (comma-joined).

Error cases:

| Condition | Result |
|---|---|
| `action` not `list`/`clean` | `action must be 'list' or 'clean'.` |
| `clean` without `confirm='true'` | `clean requires confirm='true'. No files were deleted.` |
| No snapshots (clean) | Success: `No snapshot files found. Nothing to clean.` (`deletedCount` 0) |
| Approval refused (clean) | `The change was rejected in SwiftCode's review; nothing was written.` |

## 11. `test_target_add` — Add Test Target

Legacy: `AssistTestTargetAddTool.swift`. Capability
`compilation`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; the test file and the pbxproj edit each go
through `commit()`, in that order.

Description (verbatim): "Creates a test directory with a real
XCTest file and inserts a PBXNativeTarget block into the
project pbxproj."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "targetName": {"type": "string", "description": "Required. Valid identifier for the new test target."},
  "type": {"type": "string", "description": "unit or ui. Default: unit."}},
 "required": ["targetName"], "additionalProperties": false}
```

Behaviour (in order; every check runs before any write):

1. `targetName` must be a valid Swift identifier; `type` is
   `unit` or `ui` (case-insensitive, default `unit`).
2. The `.xcodeproj` is found (top-level first, then a
   recursive search skipping `.git`, `build`, `DerivedData`,
   `Pods`); its `project.pbxproj` must exist and read as UTF-8.
3. No target with that name may already exist (`name =
   <targetName>;` or `/* <targetName> */` in the pbxproj), and
   no directory with that name may already exist in the
   workspace root.
4. All seven anchors must be present in the pbxproj
   (`/* Begin PBXNativeTarget section */`,
   `/* Begin PBXFileReference section */`,
   `/* Begin PBXSourcesBuildPhase section */`,
   `/* Begin PBXFrameworksBuildPhase section */`,
   `/* Begin XCBuildConfigurationList section */`,
   `/* Begin XCBuildConfiguration section */`, `targets = (`).
5. Twelve 24-character uppercase-hex IDs (UUID with dashes
   removed) are generated, unique and absent from the pbxproj.
6. The whole pbxproj edit is computed in memory first (seven
   section blocks — target, product reference, sources phase,
   frameworks phase, configuration list, Debug and Release
   configurations — plus the `targets` entry, each inserted on
   the line after its anchor). The product type is
   `com.apple.product-type.bundle.unit-test`, or
   `com.apple.product-type.bundle.ui-testing` for `ui`; the
   product is `<targetName>.xctest`; both configurations set
   `IPHONEOS_DEPLOYMENT_TARGET = 17.0`,
   `MACOSX_DEPLOYMENT_TARGET = 14.0`, `PRODUCT_NAME =
   "$(TARGET_NAME)"`, `SWIFT_EMBED_LIBRARIES_WITH_INSTALL =
   YES`.
7. The test file `<targetName>/<targetName>Tests.swift` is
   committed (unit: an `XCTestCase` with `testExample`
   asserting `1 + 1 == 2`; UI: a launch test with
   `XCUIApplication`, `app.launch()`, and a 10 s foreground
   wait), then the modified pbxproj is committed.
8. The pbxproj is re-read from disk and verified to contain
   `name = <targetName>;` and the new target ID.

Output (structured): `targetName`, `type`, `targetID`,
`testFile` (`<targetName>/<targetName>Tests.swift`). Summary:
`Added test target '<targetName>' (<type>) with test file
<targetName>/<targetName>Tests.swift and PBXNativeTarget entry
in project.pbxproj.`

Deviation: because the edit is computed in memory before any
write, a missing anchor writes nothing — including the test
file. (The checked-in Legacy code checks anchors before
creating files too, so the observable outcome matches; the
port additionally cannot leave a test file behind when an
insert fails.) The random-ID generator fails cleanly instead
of indexing out of range if it cannot produce 12 unique IDs.
On a SwiftPM package workspace (no `.xcodeproj`) the tool
fails honestly — it does not invent a project file.

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `targetName` | `Missing required parameter: targetName` |
| Invalid `targetName` | `targetName '…' is not a valid identifier. Use letters, digits, and underscores, starting with a letter or underscore.` |
| `type` not `unit`/`ui` | `type must be 'unit' or 'ui'.` |
| No `.xcodeproj` | `No .xcodeproj found in the workspace root. Open a project first.` |
| No/unreadable `project.pbxproj` | `project.pbxproj not found in '<name>'.` / `Could not read project.pbxproj as UTF-8 text.` |
| Target already exists / directory exists | `A target named '…' already exists in project.pbxproj.` / `Directory '…' already exists in the workspace. Choose a different targetName.` |
| Missing anchor | `project.pbxproj is missing required anchor '<anchor>'. No changes were written.` |
| Insert fails (in-memory) | `Failed to insert the new target blocks into project.pbxproj. No changes were kept.` |
| Post-write verification fails | `Verification failed: target '…' was not found in project.pbxproj after writing.` |

## 12. `ui_test_scaffold` — UI Test Scaffold

Legacy: `AssistUITestScaffoldTool.swift`. Capability
`testing`, risk `safeMutation`. Gate: `writes: true`,
`safeMutation`; the file is written through `commit()`.

Description (verbatim): "Creates a real XCTest UI test file
with setUp, launch, a launch-state assertion, and tearDown."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "testName": {"type": "string", "description": "Required. Valid Swift identifier used for the test class and file name."},
  "targetApp": {"type": "string", "description": "Optional bundle identifier of the app under test. When empty, XCUIApplication() is used."},
  "path": {"type": "string", "description": "Workspace-relative directory for the new test file. Default: UITests/."},
  "overwrite": {"type": "string", "description": "Must be 'true' to replace an existing file. Default: 'false'."}},
 "required": ["testName"], "additionalProperties": false}
```

Behaviour: the file is `<path>/<testName>.swift` (default
directory `UITests/`). Its body is a final `XCTestCase` with
`private var app: XCUIApplication!`,
`setUpWithError` (`continueAfterFailure = false`, then `app =
XCUIApplication()` — or `XCUIApplication(bundleIdentifier:
"<targetApp>")` when one is given), `tearDownWithError`
(`app = nil`), and `testLaunch` (`app.launch()`,
`XCTAssertTrue(app.wait(for: .runningForeground, timeout:
10), "App did not reach the foreground after launch.")`,
`XCTAssertTrue(app.state == .runningForeground)`). An
existing file refuses the write unless `overwrite` is `"true"`
(schema type string, kept verbatim; boolean `true` also
accepted).

Output (structured): `path` (workspace-relative), `testName`.
Summary: `Created UI test file at <path>`.

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `testName` | `Missing required parameter: testName` |
| Invalid `testName` | `testName '…' is not a valid Swift identifier. Use letters, digits, and underscores, starting with a letter or underscore.` |
| Path refused by the resolver | `path must be inside the workspace and must not contain '..'.` |
| File exists, no overwrite | `File already exists at '<path>'. Pass overwrite='true' to replace it.` |

## 13. `interface_simulator` — Interface Simulator & Accessibility Auditor

Legacy: `AssistInterfaceSimulatorTool.swift`. Capability
`testing`, risk `safeRead`. Gate: none.

Description (verbatim): "Inspects SwiftUI View files, audits
accessibility traits, accessibility identifiers, touch
targets, and hierarchy structure."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "viewPath": {"type": "string", "description": "Workspace-relative path to a SwiftUI View file."}},
 "required": ["viewPath"], "additionalProperties": false}
```

Behaviour: the file must exist, read as UTF-8, and contain
`: View` or `some View`. Lines starting with `//` are skipped.
Counting (Legacy's, verbatim — including its quirks, which
define the score): a line containing `Button(` or `Button {`
is a button; **any** line containing
`.accessibilityIdentifier(` or `.accessibilityLabel(` counts
toward the buttons-with-accessibility total (not just the
element it decorates); a line containing `Image(` or
`Image(systemName:` is an image; **any** line containing
`.accessibilityHidden(` counts toward the images-with-
accessibility total; `Text(` lines are text labels; `List {`
or `List(` lines are lists; `.navigationTitle(` marks a
navigation title. The accessibility score is
`Int(buttonsWithA11y / buttonCount * 100)` (100 when there
are no buttons).

Output: plain text (Legacy carries no data):

```
SwiftUI Interface & Accessibility Audit for '<viewPath>':
- Elements Detected:
  * Buttons: <B> (<A> have accessibility tags or labels)
  * Images: <I>
  * Text Labels: <T>
  * Lists/ScrollViews: <L>
  * Navigation Title Configured: Yes|No
- Accessibility Identifier Coverage: <S>%
```

plus, when the score is below 60, `Recommendations:` (add
`.accessibilityIdentifier(...)` to interactive buttons, add
`.accessibilityLabel(...)` to icon-only buttons); otherwise
`Interface compliance check passed with high accessibility
readiness.`

Error cases:

| Condition | Result |
|---|---|
| Missing `viewPath` | `Missing required parameter: viewPath` |
| File does not exist / path refused | `File does not exist: <viewPath>` |
| File unreadable | `Cannot read file: <viewPath>` |
| No SwiftUI View in the file | `File does not appear to contain a SwiftUI View implementation: <viewPath>` |

## 14. `preflight_checks` — Preflight Checks

Legacy: `AssistPreflightChecksTool.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Runs environment preflight checks
before a build/task: workspace writable, Xcode tools present,
DerivedData reachable, free disk space."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."}},
 "required": [], "additionalProperties": false}
```

Behaviour (Legacy's seven checks, verbatim, in order):

1. Workspace writable (`isWritableFile` on the workspace
   root).
2. `xcodebuild` available (executable at
   `/usr/bin/xcodebuild`).
3. `swift` available (executable at `/usr/bin/swift`).
4. `codesign` available (executable at
   `/usr/bin/codesign`).
5. DerivedData reachable (the directory
   `~/Library/Developer/Xcode/DerivedData` exists).
6. Free disk ≥ 5 GB on the workspace volume
   (`attributesOfFileSystem`, `.systemFreeSize`; `unknown`
   when it cannot be read).
7. Artifact storage writable (`.assist_temp` exists as a
   writable directory, or does not exist and the workspace is
   writable — `(will be created on demand)`).

Output (structured): `checkCount` (7), `failureCount`
(ints). Summary: `Preflight checks:` + one `- [PASS|FAIL]
<name> — <detail>` line per check + `Result: all checks
passed` or `Result: <N> check(s) failed`.

Honest behaviour: on a machine without Xcode tools (this
Linux environment) checks 2–4 fail and are reported as
failing — the tool never claims a tool is present when it is
not. The DerivedData read is the same read-only, outside-the-
workspace access as §8.

Error cases: none beyond "no workspace is open". A check that
cannot be performed reports FAIL (disk `unknown`), it does
not throw.

## 15. `performance_benchmark` — Performance Benchmark

Legacy: `AssistPerformanceBenchmarkTool.swift`. Capability
`diagnostics`, risk `execution`. Gate: none (no file is
written).

Description (verbatim): "Runs an allow-listed command N times
via Process and reports average, minimum, and maximum wall
time plus exit codes."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "command": {"type": "string", "description": "Required. Executable path, one of /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du. May include arguments after the executable."},
  "arguments": {"type": "string", "description": "Optional extra arguments, space-separated. Combined with any arguments in command."},
  "iterations": {"type": "string", "description": "Run count. Default: 3. Maximum: 10."}},
 "required": ["command"], "additionalProperties": false}
```

Behaviour: `command` is split on whitespace; its first
token must be exactly one of `/usr/bin/time`,
`/usr/bin/xcodebuild`, `/usr/bin/swift`, `/bin/ls`,
`/usr/bin/du`. The remaining tokens plus `arguments` (a
space-separated string, or an array — Legacy accepts both)
form the argument vector. Any argument containing a shell
character (`;|&$`"'<>\!()` or a newline) fails. The
executable must exist. `iterations` defaults to 3, must be
an integer ≥ 1, and is clamped to 10. Each run executes the
fixed argument vector (`terminalRunFixed`, off the main
actor, working directory = the workspace root) and is timed
with wall-clock time. The output reports average, minimum
and maximum seconds (3 decimals) and the exit codes, plus
the last run's output tail (last 1000 characters).

Output (structured): `executable`, `iterations` (int),
`averageSeconds` / `minSeconds` / `maxSeconds` (doubles),
`exitCodes` (array of ints). Summary: `Benchmark '<exe>
<args>' over <N> run(s): avg <a>s, min <b>s, max <c>s. Exit
codes: <…>.` + `Last run output tail:` + the tail.

Deviations from Legacy: each run is bounded at 300 s
through `terminalRunFixed` and fails on timeout (Legacy
waited unboundedly); `exitCodes` is a JSON array of integers
(Legacy joined them with commas into a string).

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `command` | `Missing required parameter: command` |
| Executable not in the allow-list | `command '<exe>' is not in the allow-list. Allowed: /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du.` |
| Unsafe argument | `Argument '<arg>' contains characters that are not allowed.` |
| Executable missing from disk | `Executable not found at '<exe>'.` |
| `iterations` not an integer ≥ 1 | `iterations must be an integer of at least 1.` |
| Process cannot start | `Benchmark run failed: could not start '<exe>'.` |
| Run exceeds 300 s | `Benchmark run timed out after 300s.` |

Safety: fixed argument vector only, never a shell; no
network, no installs; the allow-list is closed (adding an
executable is a deliberate change, not a caller choice).

## 16. `compiler_diagnostics_engine` — Compiler Diagnostics Engine

Legacy: `AssistCompilerDiagnosticsEngine.swift`. Capability
`diagnostics`, risk `execution`. Gate: none (no file is
written by the tool itself; the build writes its own
products through the session, as the `build` tool does).

Description (verbatim): "Runs xcodebuild and parses
warnings/errors into structured diagnostics."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "project": {"type": "string", "description": "Workspace-relative path to the .xcodeproj/.xcworkspace to diagnose. Defaults to the project found in the workspace root."},
  "scheme": {"type": "string", "description": "Build scheme. Defaults to the project's first listed scheme."}},
 "required": [], "additionalProperties": false}
```

Behaviour:

1. `project`, when given, must name the already-open
   workspace (its project/workspace URL, or the workspace
   folder for a package); anything else fails with
   `project "<project>" is not the open workspace; open it
   with workspace_open first.` When omitted, the open
   workspace is diagnosed.
2. The scheme is applied with `applyScheme`; all files are
   saved; the build runs through the session (`s.build(.build)`,
   the `build` tool's path) with progress reporting.
3. Diagnostics are the build's issues by severity: errors
   (`severity == .error`) and warnings (`.warning`), each
   capped at 200 lines, joined with newlines.
4. **Success means "diagnostics were collected", not "the
   build passed"** (Legacy's rule): the call succeeds even
   when the build fails. The headline is `Compiler diagnostics
   collected (build succeeded).` or `Compiler diagnostics
   collected (build FAILED, exit code <N>).`, and the failure
   is explicit in the data.

Output (structured): `error_count`, `warning_count` (ints),
`errors`, `warnings` (newline-joined issue descriptions),
`exitCode` (0 when the build succeeded, 1 otherwise),
`buildFailed` (bool).

Deviations from Legacy (deliberate): the build runs through
the session (swiftcodebuild / SwiftPM), not a directly spawned
`xcodebuild`, so there is no 300 s timeout and no macOS-only
gate — SwiftCode builds on Linux too, and the `#if os(macOS)`
refusal (`Compiler diagnostics are only available on macOS
runtime`) is not ported. The `project` argument cannot switch
workspaces mid-call; it can only confirm the open one.

Error cases:

| Condition | Result |
|---|---|
| No workspace open | `no workspace is open: call workspace_open …` |
| `project` is not the open workspace | `project "…" is not the open workspace; open it with workspace_open first.` |
| Unknown scheme | `no scheme "…"…` |

## 17. `crash_log_parse` — Crash Log Parse

Legacy: `AssistCrashLogParseTool.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Parses .crash/.ips crash logs:
exception type, termination reason, faulting thread, and top
blamed frames."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "path": {"type": "string", "description": "Workspace-relative path to the .crash or .ips file."}},
 "required": ["path"], "additionalProperties": false}
```

Behaviour (Legacy's scan, verbatim): `Exception Type:` /
`Termination Reason:` / `Triggered by Thread:` (or `Crashed
Thread:`) lines are captured; after a thread line, frame
lines matching `^\d+\s+\S+` are collected, truncated to 160
characters, at most 12, until a blank line, another `Thread
…` line, or the 12-frame cap. When no `Exception Type:` line
was seen, a JSON `.ips` body is tried instead
(`exception.type`, `termination.reason`, `"unknown"` when
absent).

Output (structured): `hasException` (bool), `frameCount`
(int). Summary: `Crash log summary for <path>:` + `- <Exception
Type: …>` / `- <Termination Reason: …>` / `- <Triggered by
Thread: …>` when present + `Top blamed frames:` + the frames
(indented two spaces).

Error cases:

| Condition | Result |
|---|---|
| Missing/blank `path` | `Missing required parameter: path` |
| File cannot be resolved/read | `Cannot read crash log at: <path>` |
| No crash metadata recognised | `No crash metadata recognized in <path>. Expected .crash or .ips format.` |

## 18. `runtime_diagnostics_engine` — Runtime Diagnostics Engine

Legacy: `AssistRuntimeDiagnosticsEngine.swift`. Capability
`diagnostics`, risk `safeRead`. Gate: none.

Description (verbatim): "Analyzes runtime logs for
crashes/anomalies and suggests concrete fixes."

Input schema (verbatim + `workspace`):

```json
{"type": "object", "properties": {
  "workspace": {"type": "string", "description": "Optional: the workspace to use (its path); opened when it is not the open one."},
  "logPath": {"type": "string", "description": "Workspace-relative path of the log file to analyze."}},
 "required": ["logPath"], "additionalProperties": false}
```

Behaviour: the log is read as UTF-8. Crash lines are lines
containing `fatal error` or `crash` (case-insensitive).
Thread-anomaly lines contain both `thread` and `queue`
(case-insensitive). Suggestions: crashes → `Add guards around
nil-sensitive code paths and inspect crashing stack frame
symbols.`; thread anomalies → `Validate actor/queue
confinement for shared mutable state to avoid race
conditions.`; neither → `No critical anomalies detected;
enable verbose logging for deeper tracing.`

Output (structured): `crash_count`,
`thread_anomaly_count` (ints), `suggestions` (newline-joined),
`crashes` (first 100 crash lines, newline-joined). Summary:
`Runtime diagnostics complete.`

Error cases:

| Condition | Result |
|---|---|
| Missing `logPath` | `Missing logPath` |
| File cannot be resolved/read | `Cannot read log at: <logPath>` |

Deviation: Legacy's filesystem read threw its underlying
error; this port reports `Cannot read log at: <logPath>` for
any resolve/read failure.

## 19. Safety rules (non-negotiable)

- **Never a shell.** `performance_benchmark` and
  `test_coverage_reporter` run fixed argument vectors
  (`terminalRunFixed`); `test_run_single`,
  `test_coverage_report` and `compiler_diagnostics_engine`
  run through the session seam (§2). No tool builds a shell
  string, interpolates arguments into one, or runs a caller-
  supplied command. The benchmark allow-list is closed.
- **Never invent a result.** A test run reports the runner's
  actual outcomes; a coverage report with no gathered coverage
  says so; a diagnostics run reports the build's actual
  issues; a coverage reporter without `xcrun` fails instead of
  fabricating a report.
- **Workspace confinement.** No tool writes outside the
  workspace. The two read-only exceptions (§8, §14) read the
  user's own DerivedData / system tool paths and write nothing.
- **Approval is the only gate.** The four writing tools go
  through `commit()` / `approve()`; there is no Autopilot, no
  per-tool bypass, no `confirm` parameter invented for a tool
  that Legacy does not declare one for. `test_snapshot_manage`
  `clean` additionally requires Legacy's own `confirm='true'`
  string — that is tool input, not policy, and it does not
  weaken the gate.
- **Destructive means permanent.** Snapshot `clean` deletes
  files permanently (no trash, no backup). The pbxproj edit in
  `test_target_add` is computed in memory and only written
  after every insert succeeds, so a bad pbxproj writes nothing.
- **Validation before execution.** `testId`, `destination` /
  `scheme` shell characters, benchmark allow-list and
  arguments, fixture/scaffold/target identifiers, and every
  anchor/existence check run before anything is executed or
  written.

## 20. Honestly-failing / BLOCKED notes

**None of the 16 tools is honestly failing and none is
BLOCKED.** All 16 are implemented and registered. The honest
limitations, each named with its prerequisite, are:

- **`test_coverage_report`:** reports coverage only when the
  scheme's Test action gathers it (`codeCoverageEnabled`).
  Prerequisite for a non-empty `coverage` value: enable code
  coverage in the scheme's Test action. Otherwise the tool
  runs the suite, reports pass/fail honestly, and says no
  coverage was gathered.
- **`test_coverage_reporter`:** needs Xcode command line
  tools (`/usr/bin/xcrun` + `xccov`) and a real
  `.xccovreport` / `.xccovarchive` (in DerivedData or named
  explicitly). Prerequisite: macOS with Xcode tools installed.
  Without them it fails with `Failed to execute xccov: …` and
  never invents coverage. Finding no report at all is a
  success with Legacy's message, not a failure.
- **`test_run_single` / `test_coverage_report` /
  `compiler_diagnostics_engine`:** need a Swift toolchain on
  the machine that runs them (the `test` / `build` seam). In
  this Linux environment there is no Swift toolchain, so the
  Mac build/test verification for these three stays pending
  (see §21). They are not stubbed: they call the real seam.
- **`test_target_add`:** needs a real `.xcodeproj` with a
  well-formed `project.pbxproj` (all seven anchors). On a
  SwiftPM package workspace it fails honestly.
- **`preflight_checks`:** honestly reports missing Xcode
  tools as FAIL on machines without them.

## 21. What is still pending (Mac build/test)

- `swift build` / `swift test` in this environment: **not
  possible** — no Swift toolchain exists here. Static checks
  only: 16 tools, IDs unique, delimiters balanced in all three
  new files, no TODO/FIXME, no `testing`-prefixed helper
  collides with an existing SwiftCodeMCP symbol. The full test
  suite (`SwiftCodeTestingToolsTests`, 20 tests — the toolchain-
  gated tests run only when `canBuildPackages` is true) still
  needs a Mac run, as do the live checks: a real single-test
  run, a real coverage run with the scheme gathering coverage,
  a real `xccov` report read, and a real `xcodebuild`-backed
  diagnostics collection through the session build.
- **Wiring (coordinator-owned, NOT done here):** add
  `testingTools` to `installTools()` in
  `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools.swift` (after
  `engineTools`), add the alias `"test_coverage":
  "test_coverage_reporter"` to `MCPServer.toolAliases` in
  `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift` (verified against
  Legacy's `AssistToolRegistry` alias table, line 532 — the
  only alias in this slice), and merge this spec's §3–§18 into
  `specs/ide/assist-tool-catalogue.md`.

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 16 IDs, titles, descriptions, capabilities, risk levels, and input schemas | 1 | Legacy source, read directly: `SwiftCode/Backend/Assist/Tools/AssistTestRunSingleTool.swift`, `AssistXctestDiscoveryTool.swift`, `AssistTestLogParseTool.swift`, `AssistTestFlakyDetectTool.swift`, `AssistTestCoverageReportTool.swift`, `AssistTestCoverageReporterTool.swift`, `AssistTestDataFactoryTool.swift`, `AssistTestSnapshotManageTool.swift`, `AssistTestTargetAddTool.swift`, `AssistUITestScaffoldTool.swift`, `AssistInterfaceSimulatorTool.swift`, `AssistPreflightChecksTool.swift`, `AssistPerformanceBenchmarkTool.swift`, `AssistCompilerDiagnosticsEngine.swift`, `AssistCrashLogParseTool.swift`, `AssistRuntimeDiagnosticsEngine.swift` |
| `test_coverage` → `test_coverage_reporter` is the only alias in this slice | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table (lines 430–556; the `test_coverage` entry at line 532) |
| Test-runner seam: `discoverTests` / `testsDiscovered` / `runTests(only:)` / `runnerIdentifier` / `gathersCoverage` / `latestCoverage`; `test` tool as reference caller | 1 | SwiftCode `swiftcode/Sources/SwiftCodeIDECore/Session/WorkspaceSession.swift` (`discoverTests`, `testsDiscovered`, `runnerIdentifier`, `runTests`, `gathersCoverage`), `swiftcode/Sources/SwiftCodeIDECore/Session/WorkspaceSession+Coverage.swift` (`latestCoverage`), `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Build.swift` (`test`, `build`) |
| Discovery rules (XCTest + swift-testing + ObjC), `TestOutcome` / `TestResultParser`, coverage via llvm-cov, result-bundle reading | 1 | SwiftCode `swiftcode/Sources/SwiftCodeIDECore/Model/TestDiscovery.swift`, `swiftcode/Sources/SwiftCodeBuild/TestResults.swift`, `swiftcode/Sources/SwiftCodeXcodebuild/Coverage.swift`, `swiftcode/Sources/SwiftCodeXcodebuild/XCResultReader.swift`, `swiftcode/Sources/SwiftCodeXcodebuild/TestActions.swift`, `swiftcode/Sources/SwiftCodeXcodebuild/SwiftTestingBridge.swift` |
| `platform=macOS` is the specifier of the "My Mac" destination | 1 | SwiftCode `swiftcode/Sources/SwiftCodeBuild/Destinations.swift` (`Destination.myMac`) |
| Fixed-argv runner, timeout, off-main-actor use; `commit()` / explicit `MCPChange` + `approve()` gate shapes | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+TerminalSupport.swift` (`terminalRunFixed`), `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Content.swift` (`commit`), `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+FileWriting.swift` (`approveFileWritingChange`); approval model `specs/ide/assist-approval-model.md` |
| Argument validation (required, unknown-argument, strict type checks) and alias resolution at `tools/call` time | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift` (`argumentProblem`, `toolAliases`, `run`) |
| SwiftCode port: `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Testing.swift`, `SwiftCodeTools+TestingSupport.swift`; tests `swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeTestingToolsTests.swift` | 1 | Files written in this slice (destination repo only, uncommitted) |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

## Part B — Static analysis

## Assist static-analysis tools — behaviour (Wave 6, slice B)

SwiftCode modules: `SwiftCodeMCP` (the MCP server and its tools; the Wave 6
slice-B port registers the tools below there).

This spec covers the behaviour shared by the 22 Legacy Assist
static-analysis tools ported into SwiftCode in Wave 6 (slice B), plus the
per-tool behaviour that the catalogue
(`assist-tool-catalogue.md`) does not repeat: the workspace scan
rules, the three path resolvers these tools use, the exact scan
semantics, and the full error-case table. The catalogue is the single
source of truth for each tool's ID, title, description, input schema,
output shape, capability, risk level, permission, and read/write
classification; this spec is the single source of truth for how the
tools behave. Each per-tool section below is written catalogue-ready:
its description and schema are Legacy's, verbatim (plus the
`workspace` parameter Wave 1 adds to every tool), so the coordinator
can merge them into the catalogue without re-deriving them.

Scope: exactly these 22 tools, verified live from the Legacy
registry and each tool's Legacy file at `d51a8f0d`. No other tool is
in scope for this slice, and no tool may be invented, renamed, or
merged with another.

| ID | Title |
|---|---|
| `code_lint` | Lint Code |
| `swift_format_lint` | Swift Format Linter |
| `dead_code_scan` | Dead Code Scan |
| `dead_code_eliminator` | Dead Code Eliminator |
| `duplicate_code_scan` | Duplicate Code Scan |
| `unused_imports_detector` | Unused Imports Detector |
| `import_cleanup` | Import Cleanup |
| `force_unwrap_scan` | Force Unwrap Scan |
| `todo_scan` | TODO Scan |
| `todo_fixme_scanner` | TODO & FIXME Scanner |
| `comment_density_report` | Comment Density Report |
| `code_comment_extract` | Code Comment Extract |
| `complexity_analysis` | Complexity Analysis |
| `function_size_report` | Function Size Report |
| `code_metrics_analyzer` | Code Metrics Analyzer |
| `string_literal_audit` | String Literal Audit |
| `deprecation_usage_scan` | Deprecation Usage Scan |
| `swift_ast_inspector` | Swift AST Inspector |
| `swift_concurrency_analyzer` | Swift Concurrency Analyzer |
| `concurrency_audit` | Concurrency Audit |
| `entry_points_discover` | Discover Entry Points |
| `swift_migration_advisor` | Swift 6 Migration Advisor |

## 1. Conventions shared by the static-analysis tools

### 1.1 The workspace scans

All 22 tools scan the workspace (the folder of the open workspace),
never the whole filesystem. Four scan shapes exist in Legacy, and
the port keeps them distinct:

- **Per-tool enumerator** (`dead_code_scan`,
  `duplicate_code_scan`, `todo_scan`, `import_cleanup`,
  `concurrency_audit`): each Legacy tool carries its own private
  copy. No hidden-file skip; a directory named `.git`,
  `DerivedData`, `.build`, `Pods` or `node_modules` has its
  descendants skipped (`skipDescendants`); Swift files only; files
  over 300,000 bytes dropped; at most 5,000 files; results sorted by
  path. A single-file root is accepted when it is a Swift file of
  300,000 bytes or less, otherwise the scan is empty.
- **`AssistWorkspaceScan.swiftFiles`** (`force_unwrap_scan`,
  `comment_density_report`, `function_size_report`,
  `string_literal_audit`, `deprecation_usage_scan`,
  `entry_points_discover`): hidden files skipped; a file is skipped
  when the *first* path component relative to the root is a skipped
  directory (`.git`, `.build`, `build`, `DerivedData`, `.swiftpm`,
  `Pods`, `Carthage`, `node_modules`, `.venv`) — only the first
  component is checked, so a nested `.build` directory is not
  skipped; Swift files only; at most 8,000 files; enumerator order
  (not sorted). Files that do not decode as UTF-8 are silently
  skipped.
- **Plain directory enumeration** (`code_metrics_analyzer`,
  `swift_migration_advisor`): `FileManager.enumerator` with no
  options, no skipped directories, no size cap, enumerator order; a
  single file is accepted when its extension is `swift` (any other
  single-file target is an error for `code_metrics_analyzer`, and
  an empty file list for `swift_migration_advisor`).
- **Hidden-skipping enumerator** (`todo_fixme_scanner`,
  `swift_concurrency_analyzer` when given a directory):
  `FileManager.enumerator` with `.skipsHiddenFiles` and
  `.skipsPackageDescendants`; `todo_fixme_scanner` accepts `swift`,
  `m` and `h` files, `swift_concurrency_analyzer` accepts `swift`
  only, no size cap. `swift_concurrency_analyzer` given a single
  file scans it whatever its extension (an unreadable file is
  silently skipped).

All scans read files as UTF-8 and silently skip files that do not
decode, except where a tool reads one named file (then a read
failure is a tool error — see §18).

### 1.2 The three path resolvers

- **Strict scan resolver** (`dead_code_scan`,
  `duplicate_code_scan`, `todo_scan`, `import_cleanup`,
  `concurrency_audit`): Legacy's per-tool `resolvePath`. A blank or
  absent path is the workspace root. Any `..` anywhere in the path
  fails with `Invalid path: path must stay inside the workspace and
  must not contain '..'.` A leading-`/` path is used as an absolute
  filesystem path and must be the root or under it; a relative path
  is appended to the workspace root (never the session working
  directory). A root that does not exist scans as zero files (a
  success with empty results, not an error).
- **Session-aware resolver** (`code_lint`, `swift_format_lint`,
  `dead_code_eliminator`, `unused_imports_detector`,
  `complexity_analysis`, `code_metrics_analyzer`,
  `swift_concurrency_analyzer`, `swift_migration_advisor`): Wave
  1's `resolveFileReadingPath`. Plain relative paths resolve
  against the session working directory (`dir_cd` / `dir_pwd`,
  defaulting to the workspace root); a leading `/` is
  workspace-root-relative (an absolute path that really is inside
  the workspace is used as-is); `~` expands to the user's home;
  `..` that escapes the workspace is an error, never a silent
  clamp. This replaces Legacy's bare
  `workspaceRoot.appendingPathComponent(path)` in these tools: the
  Legacy form would happily read outside the workspace, which SwiftCode
  does not allow. The failure messages for missing / unreadable
  files are Legacy's (see §18).
- **Strict file resolver** (`code_comment_extract`,
  `swift_ast_inspector`): SwiftCode's `resolveFileWritingPath`, the
  closest SwiftCode shape to Legacy's `AssistWorkspacePaths.resolve`
  (rejects empty paths, NUL bytes, a leading `~` and any `..`;
  relative paths resolve against the workspace root; a leading-`/`
  path must be under the root). A resolution failure is reported
  with the tool's own Legacy message (`Cannot read file at: <path>`
  / `File not found at path: <path>`).

No tool path is ever allowed to escape the workspace, in any of the
three shapes. Legacy's `/tmp/swiftcode/scripts` carve-out is not
kept (see `assist-approval-model.md` §7.2).

### 1.3 Structured data

Structured data keeps Legacy's keys, with typed JSON values
(integers for counts) the way SwiftCode's other tools do — Legacy's
string-only map is not reproduced. Tools whose Legacy result
carries no data return a plain text result instead. A tool that
returns structured data always returns it, including on its
empty-result path (for example `dead_code_scan` on zero files
returns `scannedFiles: 0, declarationCount: 0, candidateCount: 0,
candidates: ""`).

### 1.4 Parameter-name aliases are NOT supported

Legacy's registry-level `validate()` maps `filePath` /
`file_path` / `targetFile` / `file` onto `path` (and similar
mappings for `content`, `target`, `replacement`, `command`), and
individual tools accept further aliases (`import_cleanup` accepts
`filePath` / `file_path` for `path`; `duplicate_code_scan`
accepts `min_lines` for `minLines`). SwiftCode's argument validation
rejects unknown arguments before the handler runs, so none of
these aliases work in the port — exactly as in Waves 1–3. The one
exception is `dead_code_eliminator`, whose canonical Legacy
parameter really is `filePath`; that name is kept verbatim in its
schema.

### 1.5 Heuristic fidelity — what these tools are not

Every tool in this slice is a **heuristic line / regex scan** in
Legacy, and the port reproduces the heuristics faithfully,
including their known blind spots. None of them is a semantic
analysis, and none of them may be described as one:

- References in strings and comments count as mentions
  (`dead_code_scan`, `duplicate_code_scan`, `import_cleanup`).
- Substring matching is used where Legacy uses it
  (`dead_code_eliminator` counts substring occurrences;
  `complexity_analysis` counts keyword substrings;
  `code_metrics_analyzer` counts lines *containing* a keyword).
- Brace counting ignores strings, comments, and string
  interpolation (`function_size_report`, `concurrency_audit`).
- There is no Swift symbol index, no type checker, and no
  cross-file name resolution beyond whole-word text matching.
- No SwiftCodeSyntax AST is used: SwiftCode's `SwiftCodeSyntax` is a
  tokenizer / block-structure library, not a Swift declaration
  parser, and the `SwiftCodeMCP` target does not depend on it. The
  only tool whose Legacy implementation uses a real parser is
  `swift_ast_inspector`, and its parser path is not ported (see
  §15) — its regex structural fallback is the whole port.

Findings from these tools are leads, not proof. Where Legacy says
so in its description (`dead_code_scan`, `duplicate_code_scan`,
`concurrency_audit`), the port keeps the wording.

### 1.6 Safety rules

- 21 of the 22 tools are read-only (`readOnly: true, idempotent:
  true`, `writes: false`). They never write, never call
  `approve()` / `commit()`, and run in `readOnly` policy mode.
- `import_cleanup` is the only writing tool (`safeMutation`,
  `writes: true`). It gates through `commit()` — one approval per
  changed file, in order, stopping at the first refusal. Files
  approved and written before a refusal stay written; Legacy's
  tool is likewise not atomic (it writes files as it goes). In
  `readOnly` policy mode the call is refused in `MCPServer.run()`
  before the handler runs, including for a scan that would change
  nothing. There is no Autopilot bypass, no second gate, and no
  `dryRun` parameter (Legacy has none).
- `dead_code_eliminator` never writes anything despite its name:
  Legacy's `riskLevel` is `safeRead` and its handler only reports.
  The port keeps it read-only.
- Deleting or editing code on the basis of a scan finding is the
  caller's decision; no tool in this slice deletes code.

### 1.7 Registry aliases (coordinator-owned)

Verified against Legacy's `AssistToolRegistry` alias table; these
belong in `MCPServer.toolAliases`, which this slice does not
touch:

| Alias | Target |
|---|---|
| `metrics` | `code_metrics_analyzer` |
| `dead_code` | `dead_code_eliminator` |
| `migration_advisor` | `swift_migration_advisor` |
| `ast_inspector` | `swift_ast_inspector` |
| `concurrency_analyzer` | `swift_concurrency_analyzer` |
| `swift_format` | `swift_format_lint` |
| `todo_scanner` | `todo_fixme_scanner` |
| `unused_imports` | `unused_imports_detector` |

No other alias in Legacy's table points at a tool in this slice.

## 2. `code_lint` — basic lint of one file

- **Description (verbatim):** `Runs a linter on the specified file or directory.`
- **Schema:** object; `path` (string, `Workspace-relative file path to lint. Default: ".".`), no required parameters. Output: `issues` (string).
- **Behaviour:** reads the single file at `path` (default `"."`).
  For each line: longer than 120 characters →
  `Line <n> is too long (<count> chars)`; containing `TODO` or
  `FIXME` (substring, anywhere in the line) →
  `Line <n> contains a marker: <line trimmed of whitespace>`. A
  line can produce both issues. Despite the description saying
  "file or directory", the tool reads one file; a directory path
  fails to read.
- **Outputs:** no issues → plain text `No basic linting issues
  found in <path>`; otherwise structured `issues` (the issue lines
  joined with `\n`), summary `Basic linting found <n> issues in
  <path>`.
- **Errors:** the file cannot be read → `Failed to lint <path>:
  <system message>`; a path outside the workspace → the
  session-aware resolver's outside-workspace error.

## 3. `swift_format_lint` — Swift style lint of one file

- **Description (verbatim):** `Lints Swift source files for code style, line length, indentation, and formatting violations.`
- **Schema:** object; `path` (string, `Relative path to Swift file in workspace.`), required: `path`. No output schema (plain text).
- **Behaviour:** five checks per line (1-based): longer than 140
  characters → `Line <n>: Line exceeds 140 characters (<count>
  chars).`; ends with a space or tab → `Line <n>: Trailing
  whitespace detected.`; starts with a tab → `Line <n>: Hard tab
  indentation used instead of spaces.`; trimmed line ends with
  `;` and does not contain `/*` → `Line <n>: Redundant trailing
  semicolon.`; more than two consecutive blank lines → `Line <n>:
  More than two consecutive blank lines.` (one issue per excess
  blank line). A line can produce several issues.
- **Outputs:** no issues → `Formatting check passed! No style or
  whitespace issues found in \`<path>\`.`; otherwise `### Swift
  Formatting Violations in \`<path>\` (<n> issues):` followed by
  the first 30 issues as `- <issue>` lines. The count in the
  header is the full count, not the shown 30.
- **Errors:** missing `path` → `Missing required parameter: path`;
  file does not exist → `File not found at path: <path>`; file
  cannot be decoded as UTF-8 → `Unable to read content of
  <path>`.

## 4. `dead_code_scan` — heuristic unreferenced declarations

- **Description (verbatim):** `Heuristic scan for Swift declarations that appear to have no references outside their own declaration line. Excludes public/open API, @main entry points, overrides, and well-known lifecycle names. Findings are heuristic leads, not proof of dead code.`
- **Schema:** object; `path` (string, `Workspace-relative path of a file or directory to scan. Defaults to the workspace root.`), no required parameters. Output: `scannedFiles`, `declarationCount`, `candidateCount` (integers), `candidates` (string).
- **Behaviour:** strict scan resolver (§1.2); per-tool enumerator
  (§1.1). Whole-word occurrence counts are computed across the
  entire scanned corpus (words split on non-alphanumerics).
  Declarations are matched per line with
  `\b(?:func|class|struct|enum|protocol|let|var|typealias|actor)\s+([A-Za-z_][A-Za-z0-9_]*)`.
  The declaration kind is the first whitespace-separated word of
  the matched text. A declaration is skipped when its name is one
  of `main`, `App`, `init`, `deinit`, `body`, `preview`, or when
  its line matches `\b(public|open|override)\b|@main|@IBAction|@objc|PreviewProvider`.
  Otherwise it is a candidate when its corpus word count is at
  most 1 — the declaration line itself contributes the one mention,
  so 1 means nothing else mentions it. Names declared more than
  once (for example overloads) are therefore not flagged, and
  references in strings or comments still count as mentions.
- **Outputs:** `Dead Code Scan (heuristic): scanned <n> Swift
  file(s), found <n> declaration(s), <n> candidate(s) with no
  other whole-word references.` plus the note about overloads and
  string/comment mentions, then up to 200 candidates as
  `- <relative>:<line> <kind> <name> (corpus mentions: <count>)`,
  with `… and <n> more candidate(s) omitted from this listing.`
  when capped; `No dead-code candidates found.` when empty.
  Structured data: `scannedFiles` (files actually read),
  `declarationCount`, `candidateCount` (uncapped),
  `candidates` (the capped list as `<relative>:<line> <kind>
  <name>` lines). Zero files → `Dead Code Scan: no Swift files
  found.` with all-zero data.
- **Errors:** a path failing the strict resolver → `Invalid path:
  path must stay inside the workspace and must not contain '..'.`
  (the regexes cannot fail to build in practice; a build failure
  would report `Dead Code Scan: failed to build declaration
  pattern.`).

## 5. `dead_code_eliminator` — unused private declarations (read-only)

- **Description (verbatim):** `Identifies unreferenced private functions, unused variables, and unreachable code structures in Swift files.`
- **Schema:** object; `filePath` (string, `Workspace-relative path to a Swift file to inspect.`), required: `filePath`. No output schema (plain text). The parameter really is `filePath` in Legacy — this is not an alias.
- **Behaviour:** reads the single file. Lines starting with `//`
  (after trimming) are skipped. A line containing `private func `
  (else, a line containing `fileprivate func `) contributes the
  text up to the first `(` as a private function name. For each,
  substring occurrences of the name in the whole file are counted
  (`components(separatedBy: name).count - 1` — substrings, not
  whole words, so `usedPrivate` also matches inside
  `unusedPrivate`); at most 1 occurrence means declared and never
  called. Only functions are detected — despite the description,
  Legacy detects no variables and no unreachable code.
- **Outputs:** none dead → `Dead Code Scan completed for
  <filePath>: All <n> private declarations have active call
  sites.`; otherwise `Dead Code Scan found <n> unused declarations
  in <filePath>:` followed by `Line <n>: Unused private function
  '<name>()' (0 calls in file).` lines. Note the message says
  "Dead Code Scan", not "Eliminator".
- **Errors:** missing `filePath` → `Missing required parameter:
  filePath`; file does not exist → `File does not exist:
  <filePath>`; file cannot be decoded → `Cannot read file:
  <filePath>`.
- **Safety:** this tool never writes. Its name is Legacy's; the
  port does not make it delete anything.

## 6. `duplicate_code_scan` — heuristic duplicated blocks

- **Description (verbatim):** `Heuristic scan for duplicated blocks of Swift code. Lines are normalized (trimmed, blank lines and full-line comments and brace-only lines skipped) and compared with a sliding window. Findings are heuristic leads — duplicated blocks may be intentional.`
- **Schema:** object; `path` (string, `Workspace-relative path of a file or directory to scan. Defaults to the workspace root.`), `minLines` (string, `Minimum normalized lines per block, as a decimal string. Clamped to at least 3. Default: "6".`), no required parameters. Output: `scannedFiles`, `duplicateGroups` (integers), `groups` (string).
- **Behaviour:** strict scan resolver; per-tool enumerator.
  `minLines` accepts an integer, a whole double, or a numeric
  string (default 6), clamped to at least 3; there is no upper
  clamp. Lines are normalized: trimmed; blank lines, full-line
  `//` comments, and lines made only of punctuation (`{ } ( ) [
  ] , ; : .`) are skipped. A sliding window of `minLines`
  normalized lines is hashed per file; a window seen in at least
  two locations is a group. Groups are sorted earliest-first by
  minimum line number, then by location count descending. A group
  whose every location is the same positive line-offset shift of
  an already-kept group with the same location count is dropped as
  a shifted continuation. At most 100 groups are kept.
- **Outputs:** `Duplicate Code Scan (heuristic): scanned <n> Swift
  file(s) with window size <minLines> normalized line(s), found
  <n> duplicated block group(s).` then per group `Duplicate block
  ×<count>:` with `  - <relative>:<line>` locations and the first
  three normalized lines indented four spaces; `No duplicated
  blocks found.` when empty. Structured data: `scannedFiles`,
  `duplicateGroups` (kept groups), `groups` (the same group text
  without the header line). Zero files → `Duplicate Code Scan: no
  Swift files found.` with all-zero data.
- **Errors:** a path failing the strict resolver → `Invalid path:
  path must stay inside the workspace and must not contain '..'.`

## 7. `unused_imports_detector` — unused framework imports (read-only)

- **Description (verbatim):** `Scans Swift files to detect redundant or unused framework imports.`
- **Schema:** object; `path` (string, `Relative path to the Swift file.`), required: `path`. No output schema (plain text).
- **Behaviour:** reads the single file. `import <Module>` lines
  (first non-blank token `import`, second token the module name
  with a trailing `;` stripped) are collected. The body is the
  file with import lines removed. An import is "used" when the
  body contains `Module.` or when any known symbol for that module
  appears in the body. Known-symbol map (Legacy's, verbatim):
  Combine → `AnyCancellable`, `PassthroughSubject`,
  `CurrentValueSubject`, `Publisher`, `sink`, `store`,
  `eraseToAnyPublisher`; SwiftUI → `View`, `body`, `some View`,
  `Text`, `VStack`, `HStack`, `State`, `Binding`, `Environment`,
  `Color`; AppKit → `NSView`, `NSViewController`, `NSWindow`,
  `NSApplication`, `NSColor`, `NSImage`, `NSPasteboard`,
  `NSWorkspace`; UIKit → `UIView`, `UIViewController`, `UIWindow`,
  `UIApplication`, `UIColor`, `UIImage`, `UIFont`; os → `Logger`,
  `os_log`, `OSLog`; WebKit → `WKWebView`, `WKNavigationDelegate`;
  AVFoundation → `AVPlayer`, `AVAudioSession`, `AVCaptureSession`;
  CoreData → `NSManagedObject`, `NSManagedObjectContext`,
  `NSPersistentContainer`. Modules absent from the map (including
  `Foundation`) are never flagged, whatever the body contains.
  Symbol matching is substring matching.
- **Outputs:** no imports → `No framework imports found in
  \`<path>\`.`; none unused → `Import analysis clean: All imported
  modules appears to be referenced in \`<path>\`.` (Legacy's
  grammar, kept); otherwise `### Potentially Unused Imports in
  \`<path>\`:` with `- Line <n>: \`import <Module>\` — no known
  <Module> symbols or explicit references found.` lines.
- **Errors:** missing `path` → `Missing required parameter: path`;
  file does not exist → `File not found at path: <path>`; file
  cannot be decoded → `Unable to read content of <path>`.

## 8. `import_cleanup` — remove unused imports (the only writer)

- **Description (verbatim):** `Removes unused import lines from Swift files. An import is removed only when its module name never appears as a whole word anywhere else in the file. Well-known Apple SDK and test modules (Foundation, SwiftUI, XCTest, Testing, and others) are never removed, because their symbols do not mention the module name. Only files that change are rewritten. Heuristic: it does not resolve re-exports or typealiases across modules.`
- **Schema:** object; `path` (string, `Workspace-relative path of a Swift file or directory to clean. Required.`), required: `path`. Output: `filesChanged` (string), `removedImports`, `changedFileCount` (integers), `removed` (string).
- **Behaviour:** strict scan resolver; per-tool enumerator.
  Import lines match `^\s*(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)\b`
  (so `@testable import X` is an import of `X`). The body is the
  file with import lines removed. An import is removed only when
  its module never appears as a whole word (`\bModule\b`) anywhere
  in the body — references in strings and comments count. The
  protected modules are never removed (Legacy's list, verbatim):
  Foundation, Swift, SwiftUI, UIKit, AppKit, Combine, CoreData,
  SwiftData, CoreGraphics, CoreAnimation, QuartzCore, WebKit,
  MapKit, AVFoundation, Photos, UserNotifications, StoreKit,
  Testing, XCTest, Observation, OSLog, UniformTypeIdentifiers,
  CryptoKit, Security, Network, WidgetKit, AppIntents, TipKit,
  CoreLocation, CoreMotion, HealthKit, EventKit, Contacts,
  SafariServices, AuthenticationServices, LocalAuthentication,
  Speech, Vision, NaturalLanguage, PlaygroundSupport. Only files
  with at least one removal are rewritten.
- **Approval:** one `commit()` per changed file, in enumeration
  (sorted-path) order, before that file is written; the change
  summary is `Remove unused imports in <relative>`, with the full
  original and proposed text. The first refusal stops the batch
  with `MCPServer.rejectedMessage`; files already committed stay
  changed (not atomic, as in Legacy). In `readOnly` policy mode
  the call is refused before the handler runs.
- **Outputs:** no files → `Import Cleanup: no Swift files found.`
  with zero data; nothing removed → `Import Cleanup: no unused
  imports found in <n> Swift file(s). Nothing changed.` with zero
  data; otherwise `Import Cleanup: removed <n> unused import(s)
  across <n> file(s):` with `- <relative>: import <Module>`
  lines. Structured data: `filesChanged` (changed relative paths,
  one per line), `removedImports`, `changedFileCount`, `removed`
  (the `- `-less removal lines). SwiftCode's `MCPToolResult` has no
  `filesChanged` field; the changed paths are carried in the data
  only.
- **Errors:** missing or blank `path` → `Missing required
  parameter: path`; a path failing the strict resolver →
  `Invalid path: path must stay inside the workspace and must not
  contain '..'.`

## 9. `force_unwrap_scan` — force-unwrap constructs

- **Description (verbatim):** `Scans Swift sources for force unwraps (!), try!, and as! — crash-prone constructs worth reviewing.`
- **Schema:** object; `limit` (integer, `Maximum findings. Default 100, max 1000.`), no required parameters. Output: `count` (integer).
- **Behaviour:** scans the workspace root with
  `AssistWorkspaceScan.swiftFiles`. Per line (full-line `//`
  comments skipped), in order: a `!` not preceded by `=` or `!`
  and not followed by `=` (regex `(?<![=!])!(?!=)`); `try!`
  (`\btry!\b`); `as! ` (`\as! ` — note the trailing space, so
  `as!` at end of line or before `)` is not matched). The first
  matching pattern wins per line (one finding per line). A force
  unwrap on a line containing `@IBOutlet` is skipped. Stops as
  soon as `limit` findings are reached (clamped to 1…1000,
  default 100). The `!` check is purely textual: `!` inside a
  string literal (for example `"\(name)!"`) is flagged.
- **Outputs:** none → `No force-unwrap constructs found.` with
  `count: 0`; otherwise `Force-unwrap constructs (<n><+ when the
  limit was reached>):` with `- <relative>:<line> [<label>]`
  lines, `count` the number listed.
- **Errors:** none beyond workspace errors. `limit` is clamped,
  never rejected.

## 10. `todo_scan` — TODO/FIXME/XXX/HACK markers

- **Description (verbatim):** `Scans Swift source files for TODO, FIXME, XXX, and HACK markers and returns a file:line:text list with counts per tag.`
- **Schema:** object; `path` (string, `Workspace-relative path of a file or directory to scan. Defaults to the workspace root.`), no required parameters. Output: `scannedFiles`, `totalMarkers`, `todo`, `fixme`, `xxx`, `hack` (integers), `findings` (string).
- **Behaviour:** strict scan resolver; per-tool enumerator. Per
  line, every match of `\b(TODO|FIXME|XXX|HACK)\b[\s:]*([^\n]*)`
  counts (several matches on one line each count, each with the
  text after the tag, whitespace-trimmed). Findings are capped at
  1,000 listed (the counts are uncapped). Markers inside strings
  match too — the tool does not distinguish comments from code.
- **Outputs:** `TODO Scan: scanned <n> Swift file(s), found <n>
  marker(s) — TODO: <n>, FIXME: <n>, XXX: <n>, HACK: <n>.` then
  the findings as `<relative>:<line> <TAG>: <text>`, or `No
  TODO/FIXME/XXX/HACK markers found.`; when the total exceeds the
  listed 1,000, `… and <n> more marker(s) omitted (listing capped
  at 1000).` Structured data carries the same counts plus
  `findings` (the listed lines joined with `\n`). Zero files →
  `TODO Scan: no Swift files found.` with all-zero data.
- **Errors:** a path failing the strict resolver → `Invalid path:
  path must stay inside the workspace and must not contain '..'.`

## 11. `todo_fixme_scanner` — workspace action-item index

- **Description (verbatim):** `Scans workspace files to index all TODO, FIXME, MARK, HACK, and BUG annotations.`
- **Schema:** object; `tag` (string, `Optional specific tag filter: 'TODO', 'FIXME', 'BUG', 'HACK', or 'MARK'.`), `maxResults` (integer, `Maximum number of results to return (default: 50).`), no required parameters. No output schema (plain text).
- **Behaviour:** scans the workspace root with the
  hidden-skipping enumerator (§1.1); `swift`, `m` and `h` files
  only; no skipped-directory list beyond hidden files. With no
  `tag`, the active tags are `TODO:`, `FIXME:`, `BUG:`, `HACK:`,
  `MARK:`; with a `tag`, only `<TAG uppercased>:` is active (an
  unknown tag matches nothing). A line matches when it contains
  the tag text as a substring (the colon is part of the match, so
  a bare `TODO` without a colon does not match); the snippet is
  the line from the tag to its end, whitespace-trimmed. Only the
  first matching tag per line is recorded. Stops at `maxResults`
  (default 50, no clamping).
- **Outputs:** none → `No TODO/FIXME/BUG annotations found in
  workspace.`; otherwise `### Workspace Action Items (<n>
  found):` grouped by tag, tags in sorted order, each group
  `#### <TAG> (<n>):` with `- \`<file>:<line>\` → <snippet>`
  lines. Note the empty message names only TODO/FIXME/BUG although
  the scan also covers MARK and HACK — Legacy's wording, kept.
- **Errors:** none beyond workspace errors.

## 12. `comment_density_report` — comment-to-code ratios

- **Description (verbatim):** `Reports comment-to-code ratios per Swift file, flagging the least-documented files.`
- **Schema:** object; `limit` (integer, `Maximum files to report. Default 30.`), no required parameters. Output: `fileCount` (integer).
- **Behaviour:** scans the workspace root with
  `AssistWorkspaceScan.swiftFiles`. Per file, blank lines are
  ignored; a line inside a `/* … */` block counts as a comment
  line (the line containing `*/` ends the block); a line starting
  with `//` or `/*` counts as a comment line; anything else counts
  as a code line. Trailing `//` comments on a code line do not
  count as comment lines, and `/*` not at the start of a line does
  not start a block. Files with no counted lines are skipped.
  Rows are sorted by ratio ascending (lowest density first); the
  sort is stable for ties.
- **Outputs:** `Comment density (lowest first, <n> files):` with
  the first `limit` rows (clamped to 1…500, default 30) as
  `- <ratio, one decimal>% — <relative> (<comment> comment /
  <code> code lines)`. Structured data: `fileCount` (all files,
  not just the listed ones).
- **Errors:** none beyond workspace errors.

## 13. `code_comment_extract` — documentation comments

- **Description (verbatim):** `Extracts documentation comments (/// and /** */) for a symbol or a whole file, with locations.`
- **Schema:** object; `path` (string, `Workspace-relative Swift file to extract from.`), `symbol` (string, `Optional: only extract comments attached to this symbol name.`), required: `path`. Output: `count` (integer).
- **Behaviour:** strict file resolver (§1.2). A run of `///`
  lines accumulates (the `///` prefix and surrounding whitespace
  stripped per line); a `/**` line accumulates its text up to
  `*/` on the same line (leading `*` and spaces trimmed). When a
  non-doc line follows a pending doc block, the block attaches to
  that line unless the line is blank, a `//` comment, or starts
  with `@` — in those cases the block is dropped. The attached
  name is the full line text (first 100 characters); with a
  `symbol` filter, only lines whose text contains the symbol
  (substring, case-sensitive) are kept. Output is capped at 50
  entries; `count` is the uncapped total.
- **Outputs:** none → `No documentation comments found in <path>`
  (plus ` for '<symbol>'` when a symbol was given), `count: 0`;
  otherwise `Documentation comments in <path> (<n>):` with
  `- <path>:<line>:` followed by the doc text (continuation lines
  indented two spaces) and `→ <name>`.
- **Quirk, preserved:** a multi-line `/** … */` block is not
  collected as one comment. Only its first line enters the pending
  block; the second line is treated as the declaration the block
  attaches to, so its text becomes the "name". Legacy behaves the
  same way; the port does not fix it.
- **Errors:** missing or blank `path` → `Missing required
  parameter: path`; file cannot be resolved or read → `Cannot
  read file at: <path>`.

## 14. `complexity_analysis` — cyclomatic approximation

- **Description (verbatim):** `Analyzes the cyclomatic complexity of code.`
- **Schema:** object; `path` (string, `Workspace-relative path of the file to analyze.`), required: `path`. Output: `score` (integer), `rating` (string).
- **Behaviour:** reads the single file. The score starts at 1 and
  adds, for each of `if `, `for `, `while `, `switch `, `case `,
  `guard `, `catch `, the number of substring occurrences in the
  whole file (including occurrences in strings and comments).
  Rating: score > 20 → `High`; score > 10 → `Medium`; otherwise
  `Low`. This is a keyword-count approximation, not a control-flow
  graph computation.
- **Outputs:** structured `score`, `rating`, summary `Complexity
  analysis for <path>: <rating> (Cyclomatic approximation:
  <score>)`.
- **Errors:** missing `path` → `Missing required parameter: path`;
  file cannot be read → `Failed to analyze complexity for <path>:
  <system message>`.

## 15. `function_size_report` — longest functions

- **Description (verbatim):** `Finds the longest functions by line count, highlighting decomposition candidates.`
- **Schema:** object; `threshold` (integer, `Only report functions at or above this many lines. Default 60.`), `limit` (integer, `Maximum functions to report. Default 30.`), no required parameters. Output: `count` (integer).
- **Behaviour:** scans the workspace root with
  `AssistWorkspaceScan.swiftFiles`. A function starts on a line
  whose declared name is found by Legacy's
  `AssistWorkspaceScan.declaredFuncName` (the line starts with
  `func ` or contains ` func `; the name is the first run of
  letters, digits and `_` after `func `). The body is scanned by
  brace depth: `{` and `}` are counted per line (including braces
  in strings and comments); the function ends at the first line
  after the opening brace where depth returns to 0. Length is
  end − start + 1 lines. Functions at or above `threshold`
  (clamped to at least 5, default 60) are reported, longest first;
  `limit` is clamped to 1…300 (default 30). After a function, the
  scan resumes at its end line, so nested functions are not
  reported separately. A function whose braces never balance runs
  to the end of the file and is counted only if it ever opened a
  brace.
- **Outputs:** none → `No functions with <threshold>+ lines
  found.` with `count: 0`; otherwise `Longest functions
  (≥<threshold> lines, <n> total):` with
  `- <name> — <relative>:<line> (<length> lines)` lines (the first
  `limit`), `count` the uncapped total.
- **Errors:** none beyond workspace errors.

## 16. `code_metrics_analyzer` — file / directory code metrics

- **Description (verbatim):** `Calculates lines of code, comment density, type counts, and complexity metrics for Swift source files.`
- **Schema:** object; `path` (string, `Workspace-relative path to a Swift file or directory.`), required: `path`. No output schema (plain text).
- **Behaviour:** `path` is a file or a directory (plain directory
  enumeration, §1.1 — no skipped directories, no size cap). Lines
  are counted with `components(separatedBy: .newlines)`, so a
  trailing newline counts as one more (empty) line. Each line is
  blank (empty after trimming), a comment line (trimmed line starts
  with `//`, `/*` or `*`), or a code line. Only code lines are
  examined further: containing `func ` counts a function;
  containing `struct `, `class `, `enum ` or `actor ` counts a
  type (one per line, even if several keywords appear); containing
  `if `, `guard `, `for `, `while ` or `case ` counts a decision
  branch. Comment ratio is `comments / codeLines × 100` (0 when
  there are no code lines); average cyclomatic complexity per
  function is `branches / functions + 1` (1.0 when there are no
  functions).
- **Outputs:** the exact Legacy text block:
  `Code Metrics for '<path>' (<n> Swift files):` then
  `- Total Lines: <n>`, `- Code Lines: <n>`, `- Blank Lines: <n>`,
  `- Comment Lines: <n> (<ratio, one decimal>% comment ratio)`,
  `- Declared Types (struct/class/enum/actor): <n>`,
  `- Functions: <n>`,
  `- Decision Branches (if/guard/for/while/case): <n>`,
  `- Avg Cyclomatic Complexity per Function: ~<value, one
  decimal>`.
- **Errors:** missing `path` → `Missing required parameter: path`;
  path does not exist → `File or directory not found at: <path>`;
  a single file that is not Swift → `Target is not a Swift source
  file: <path>`; a directory with no Swift files → `No Swift
  files found to analyze under: <path>`. Files that cannot be
  decoded as UTF-8 are silently skipped (a directory whose Swift
  files are all unreadable reports "No Swift files found" only
  when the enumeration itself found none — an unreadable file
  still counts as found, then contributes nothing).

## 17. `string_literal_audit` — unlocalized user-facing strings

- **Description (verbatim):** `Finds hardcoded user-facing string literals that are not routed through localization (NSLocalizedString / String(localized:)).`
- **Schema:** object; `limit` (integer, `Maximum findings. Default 100, max 1000.`), no required parameters. Output: `count` (integer).
- **Behaviour:** scans the workspace root with
  `AssistWorkspaceScan.swiftFiles`. Per line (full-line `//`
  comments skipped): a line is skipped when its lowercase form
  contains `localizedstring`, `string(localized`, `localized:`,
  `http`, `bundle id` or `identifier`. Otherwise the line must
  contain a string literal of at least 3 characters (regex
  `"([^"\\]|\\.){3,}"`) and a UI hint as a lowercase substring —
  `text(`, `title`, `message`, `placeholder`, `label`, `button(`,
  `alert(`, `navigationtitle` — to be reported, with the first
  literal on the line truncated to 80 characters. Stops at `limit`
  findings (clamped to 1…1000, default 100).
- **Outputs:** none → `No hardcoded user-facing string literals
  detected.` with `count: 0`; otherwise `Possibly unlocalized
  user-facing strings (<n><+ when the limit was reached>):` with
  `- <relative>:<line>: <literal>` lines, `count` the number
  listed.
- **Errors:** none beyond workspace errors. A literal inside a
  string that merely mentions a hint word is flagged; the tool
  cannot tell user-facing text from identifiers or keys.

## 18. `deprecation_usage_scan` — deprecated declarations and uses

- **Description (verbatim):** `Finds declarations marked @available(*, deprecated) in workspace Swift sources and reports where those deprecated symbols are used.`
- **Schema:** object; `limit` (integer, `Maximum usage sites. Default 100, max 500.`), no required parameters. Output: `declarationCount`, `usageCount` (integers).
- **Behaviour:** scans the workspace root with
  `AssistWorkspaceScan.swiftFiles`, in two passes. Pass 1: a line
  matching `@available\([^)]*deprecated[^)]*\)` marks a
  deprecated declaration; the name is taken from the next
  non-empty line with
  `(?:func|class|struct|enum|var|let|typealias)\s+([A-Za-z_][\w]*)`
  (a declaration whose next non-empty line is not a declaration
  contributes no name). The reported location is the `@available`
  line. Pass 2: every line matching `(?<![\w.])<name>\b` for a
  deprecated name is a usage site, except lines matching the
  `@available` pattern — note the declaration's own line (for
  example `func oldThing()`) is therefore reported as a usage site.
  Usage sites are capped at `limit` (clamped to 1…500, default
  100).
- **Outputs:** no declarations → `No @available(*, deprecated)
  declarations found in workspace Swift sources.` with
  `declarationCount: 0, usageCount: 0`; otherwise `Deprecated
  declarations (<n>):` with sorted `- <name> — <relative>:<line>`
  lines, then `Usage sites (<n><+ when the limit was reached>):`
  with `- <relative>:<line>: uses deprecated '<name>'` lines.
- **Deviation, recorded:** Legacy iterates the deprecated names
  from an `NSMutableSet` (unordered), so its usage listing order
  is nondeterministic; the port checks names in sorted order. The
  set of findings is the same.
- **Errors:** none beyond workspace errors.

## 19. `swift_ast_inspector` — structural declaration hierarchy

- **Description (verbatim):** `Inspects the abstract syntax tree (AST) and type declaration hierarchy of a Swift source file.`
- **Schema:** object; `path` (string, `Relative path to the Swift file within the workspace.`), `symbol` (string, `Optional symbol name to filter AST declarations for.`), required: `path`. No output schema (plain text).
- **Behaviour:** strict file resolver (§1.2). The port implements
  only Legacy's regex structural fallback: declarations matching
  `(class|struct|enum|protocol|extension|actor)\s+([A-Za-z0-9_]+)(\s*:\s*([^{]+))?`
  are reported as `- [<kind>] <name>` plus ` : <inheritance>`
  (the inheritance text up to the first `{`, trimmed) when
  present. With a `symbol` filter, only declarations whose name
  contains the filter (case-insensitive) are kept. Matches inside
  strings and comments are reported too — the regex cannot tell
  them apart.
- **Outputs:** none → `No major type declarations found in
  <path>.`; otherwise `Swift Structural AST Declarations in
  <path>:` followed by the declaration lines. The header says
  "Structural AST", not "AST", because no real AST is produced.
- **Not ported — deliberate deviation:** Legacy's primary path
  runs `xcrun swiftc -dump-ast` on the file and returns the first
  250 lines of that dump (optionally filtered to lines containing
  the symbol, case-insensitively), falling back to the regex
  parse only when the dump is empty or contains `error:`. SwiftCode's
  MCP host has no Swift toolchain and does not shell out to
  Apple's toolchain, so the `swiftc -dump-ast` path is not ported.
  The tool is not registered honestly-failing: the regex fallback
  is Legacy's own behaviour when `swiftc` is unavailable, and the
  port returns real structural results through it. What is lost
  is the full compiler AST dump (node kinds, types, source
  ranges); the spec and the tool header say so plainly.
- **Errors:** missing `path` → `Missing required parameter: path`;
  file does not exist or cannot be resolved → `File not found at
  path: <path>`; file cannot be decoded → `Unable to read source
  file at <path>`.

## 20. `swift_concurrency_analyzer` — Swift 6 hazard audit

- **Description (verbatim):** `Audits Swift code for Swift 6 strict concurrency hazards, mutable globals, and actor isolation boundaries.`
- **Schema:** object; `path` (string, `Relative path to file or directory in workspace.`), required: `path`. No output schema (plain text).
- **Behaviour:** `path` is a file or a directory (hidden-skipping
  enumerator for directories, §1.1; a single file is scanned
  whatever its extension, unreadable files silently skipped).
  Three checks per line (trimmed): a line starting with `public
  static var `, `static var ` or `var `, not containing `let `,
  in a file containing neither `@MainActor` nor `actor ` anywhere,
  and not containing `{` (computed properties excluded) →
  `` `<relative>:<line>`: Mutable shared state `<line>` without
  `@MainActor` or `actor` isolation. ``; a line containing
  `DispatchQueue.main.sync` → `` `<relative>:<line>`:
  `DispatchQueue.main.sync` call detected; high deadlock hazard
  on main actor. ``; a line containing `@unchecked Sendable` →
  `` `<relative>:<line>`: `@unchecked Sendable` used; verify
  manual synchronization mechanisms. `` The `@MainActor` /
  `actor` check is file-wide, not per-line, and is re-evaluated
  for every line. A `var ` at the start of a line inside a type
  is flagged the same way as a global — Legacy does not track
  scope.
- **Outputs:** `### Swift 6 Strict Concurrency Analysis (<n> files
  scanned):` then, when clean, `✅ Clean concurrency scan! No
  mutable globals, DispatchQueue.main.sync deadlocks, or unchecked
  Sendables detected.`; otherwise `#### ⚠️ Concurrency
  Diagnostics (<n>):` with the first 25 findings as `- <finding>`
  lines (the count in the header is uncapped).
- **Errors:** missing `path` → `Missing required parameter: path`;
  path does not exist → `Path not found: <path>`.

## 21. `concurrency_audit` — heuristic concurrency hazards

- **Description (verbatim):** `Heuristic scan for Swift concurrency hazards: DispatchQueue.main.sync, nonisolated(unsafe), mutable static vars, Task blocks without await, force unwraps inside async functions, and SwiftUI types without @MainActor. All findings are heuristic leads, not confirmed bugs.`
- **Schema:** object; `path` (string, `Workspace-relative path of a file or directory to audit. Defaults to the workspace root.`), no required parameters. Output: `scannedFiles`, `findingCount` (integers), `findings` (string).
- **Behaviour:** strict scan resolver; per-tool enumerator. Per
  file: when the file imports SwiftUI and contains no `@MainActor`
  anywhere, the first line containing `: View`,
  `: ObservableObject` or `: App` is reported as a SwiftUI type
  without `@MainActor` (one finding per file at most). Per line:
  `DispatchQueue.main.sync` → deadlock hazard;
  `nonisolated(unsafe)` → safety bypass; `static var <name>` →
  mutable static var shared across threads. Async functions are
  tracked by brace depth: a line containing `func` and `async`
  opens an async context that ends when the brace depth returns
  to its entry level; a force unwrap inside it (a `!` preceded by
  a letter, digit, `_`, `)` or `]` and not followed by `=`) is
  reported. A line containing `Task` and `{` opens a look-ahead of
  up to 40 lines: when the block closes without any `await`
  inside, it is reported as a Task block without await. Brace
  counting is textual (strings and comments included). Findings
  are capped at 500.
- **Outputs:** `Concurrency Audit (heuristic): scanned <n> Swift
  file(s), found <n> finding(s).` then up to 500 findings as
  `<relative>:<line>: <issue>`, or `No concurrency hazards
  found.`; when capped, `… and <n> more finding(s) omitted
  (listing capped at 500).` Structured data: `scannedFiles`,
  `findingCount` (uncapped), `findings` (the capped lines). Zero
  files → `Concurrency Audit: no Swift files found.` with
  all-zero data.
- **Errors:** a path failing the strict resolver → `Invalid path:
  path must stay inside the workspace and must not contain '..'.`

## 22. `entry_points_discover` — application entry points

- **Description (verbatim):** `Finds application entry points: @main types, main.swift, and AppDelegate/SceneDelegate classes.`
- **Schema:** object; no parameters besides `workspace`. Output: `count` (integer).
- **Behaviour:** scans the workspace root with
  `AssistWorkspaceScan.swiftFiles`. A file named `main.swift` is
  a hit (`<relative>: main.swift`) and its contents are not
  scanned. Otherwise, a line starting (after trimming) with
  `@main` is a hit with the next non-empty line (trimmed, first
  80 characters) appended (`<relative>:<line>: @main <next>`); a
  line containing `class AppDelegate` or `class SceneDelegate` is
  a hit with the whole line (first 100 characters). Scanning stops
  after a file when more than 200 hits have accumulated. The
  output list is sorted as strings.
- **Outputs:** none → `No application entry points discovered
  (@main, main.swift, AppDelegate).` with `count: 0`; otherwise
  `Entry points:` followed by the sorted hits, `count` the number
  of hits.
- **Errors:** none beyond workspace errors.

## 23. `swift_migration_advisor` — Swift 6 migration audit

- **Description (verbatim):** `Audits Swift code for Swift 6 strict concurrency compliance, mutable globals, actor boundaries, and Sendable conformance.`
- **Schema:** object; `path` (string, `Workspace-relative path to a Swift file or directory.`), required: `path`. No output schema (plain text).
- **Behaviour:** `path` is a file or a directory (plain directory
  enumeration, §1.1; a single non-Swift file yields an empty file
  list and therefore a passing audit). Three checks per line
  (trimmed; full-line `//` comments skipped): a line starting
  with `public static var ` or `static var `, not containing `{`
  → `[Swift 6] Mutable static variable 'static var' without actor
  isolation violates strict concurrency. Protect with actor or
  mark 'nonisolated(unsafe)'.`; a line containing
  `: ObservableObject` → `[Swift 6 / Observation] Uses legacy
  'ObservableObject'. Recommend migrating to Swift modern
  '@Observable'.`; a line containing `@Published ` → `[Swift 6 /
  Observation] Legacy '@Published' property wrapper. In Swift
  Observation framework, properties are observable by default.`
  Each warning is prefixed `<relative>:<line> `. Despite the
  description, the tool does not check Sendable conformance or
  actor boundaries beyond the static-var check — Legacy has no
  such checks, and the port adds none.
- **Outputs:** none → `Swift 6 Migration Audit passed: All
  analyzed code in '<path>' conforms to Swift 6 strict
  concurrency patterns.`; otherwise `Swift 6 Migration Advisor
  found <n> migration opportunities across <n> files in
  '<path>':` with the first 25 warnings and, when there are more,
  `...and <n> more.`
- **Errors:** missing `path` → `Missing required parameter: path`;
  path does not exist → `Path does not exist: <path>`.

## 24. Error cases — summary table

| Tool | Missing / blank required parameter | Nonexistent path | Path failing the strict resolver (`..` / outside) | Unreadable file |
|---|---|---|---|---|
| `code_lint` | — (default `"."`) | `Failed to lint <path>: …` | Resolver error | `Failed to lint <path>: …` |
| `swift_format_lint` | `Missing required parameter: path` | `File not found at path: <path>` | Resolver error | `Unable to read content of <path>` |
| `dead_code_scan` | — (default root) | Success, zero files | `Invalid path: …` | Silently skipped |
| `dead_code_eliminator` | `Missing required parameter: filePath` | `File does not exist: <filePath>` | Resolver error | `Cannot read file: <filePath>` |
| `duplicate_code_scan` | — (default root) | Success, zero files | `Invalid path: …` | Silently skipped |
| `unused_imports_detector` | `Missing required parameter: path` | `File not found at path: <path>` | Resolver error | `Unable to read content of <path>` |
| `import_cleanup` | `Missing required parameter: path` | Success, zero files | `Invalid path: …` | Silently skipped |
| `force_unwrap_scan` | — (no path parameter) | — | — | Silently skipped |
| `todo_scan` | — (default root) | Success, zero files | `Invalid path: …` | Silently skipped |
| `todo_fixme_scanner` | — (no path parameter) | — | — | Silently skipped |
| `comment_density_report` | — (no path parameter) | — | — | Silently skipped |
| `code_comment_extract` | `Missing required parameter: path` | `Cannot read file at: <path>` | `Cannot read file at: <path>` | `Cannot read file at: <path>` |
| `complexity_analysis` | `Missing required parameter: path` | `Failed to analyze complexity for <path>: …` | Resolver error | `Failed to analyze complexity for <path>: …` |
| `function_size_report` | — (no path parameter) | — | — | Silently skipped |
| `code_metrics_analyzer` | `Missing required parameter: path` | `File or directory not found at: <path>` | Resolver error | Silently skipped (see §16) |
| `string_literal_audit` | — (no path parameter) | — | — | Silently skipped |
| `deprecation_usage_scan` | — (no path parameter) | — | — | Silently skipped |
| `swift_ast_inspector` | `Missing required parameter: path` | `File not found at path: <path>` | `File not found at path: <path>` | `Unable to read source file at <path>` |
| `swift_concurrency_analyzer` | `Missing required parameter: path` | `Path not found: <path>` | Resolver error | Silently skipped |
| `concurrency_audit` | — (default root) | Success, zero files | `Invalid path: …` | Silently skipped |
| `entry_points_discover` | — (no parameters) | — | — | Silently skipped |
| `swift_migration_advisor` | `Missing required parameter: path` | `Path does not exist: <path>` | Resolver error | Silently skipped |

"Resolver error" is the session-aware resolver's
outside-workspace error (`<path> is outside the workspace folder
<root>`). All errors are tool errors (`isError: true`), never
protocol errors. Integer parameters are clamped, never rejected:
`limit` 1…1000 (`force_unwrap_scan`, `string_literal_audit`),
1…500 (`deprecation_usage_scan`, `comment_density_report`),
`threshold` at least 5 and `limit` 1…300
(`function_size_report`), `minLines` at least 3
(`duplicate_code_scan`).

## 25. Honestly-failing / BLOCKED — none

All 22 tools are implemented and return real results. No tool is
registered honestly-failing and none is BLOCKED. The two honest
limitations are deviations, not failures, and are recorded where
they belong:

- `swift_ast_inspector` implements only Legacy's regex structural
  fallback; the `xcrun swiftc -dump-ast` primary path is not
  ported (§19). The tool still returns real structural results.
- `deprecation_usage_scan` lists usages in sorted name order
  instead of Legacy's `NSMutableSet` order (§18). The finding set
  is identical.

What remains pending is verification, not implementation: no Swift
toolchain exists in this environment, so `swift build` / `swift
test` and a live run on Dylan's Mac are still pending (see §26).
Nothing in this slice claims a build or test run passed.

## 26. Verification status

- Static checks in this environment (no Swift toolchain):
  22 tools registered in `staticAnalysisTools`, IDs unique and in
  the install order of the scope table; every helper symbol is
  prefixed `staticAnalysis` and occurs in no other file except
  where the support file is its home and the tools file its user;
  delimiter balance verified after stripping string literals and
  comments (the raw-string regex in `string_literal_audit` is the
  one line a naive counter misreads — its parens and brackets are
  balanced in Swift); no TODO/FIXME work markers (the only
  occurrences of those words are the tools' own subject matter:
  descriptions, the `todo_scan` regex, and the `code_lint`
  marker check).
- Tests: `swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeStaticAnalysisTests.swift`
  (registration test plus one behaviour test per tool, 23 tests)
  — not run here: no Swift toolchain in this environment.
- Pending on Dylan's Mac: `swift build`, `swift test`
  (SwiftCodeMCPTests), and a live run of the tools against a real
  workspace, including `import_cleanup` under review policy.

## Evidence

| Claim | Level | Source |
|---|---|---|
| Tool IDs, names, descriptions, risk levels, parameter schemas (names, descriptions, required lists) for all 22 tools | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistLintTool.swift`, `AssistSwiftFormatLintTool.swift`, `AssistDeadCodeScanTool.swift`, `AssistDeadCodeEliminatorTool.swift`, `AssistDuplicateCodeScanTool.swift`, `AssistUnusedImportsDetectorTool.swift`, `AssistImportCleanupTool.swift`, `AssistForceUnwrapScanTool.swift`, `AssistTodoScanTool.swift`, `AssistTodoFixmeScannerTool.swift`, `AssistCommentDensityReportTool.swift`, `AssistCodeCommentExtractTool.swift`, `AssistComplexityAnalysisTool.swift`, `AssistFunctionSizeReportTool.swift`, `AssistCodeMetricsTool.swift`, `AssistStringLiteralAuditTool.swift`, `AssistDeprecationUsageScanTool.swift`, `AssistSwiftASTInspectorTool.swift`, `AssistSwiftConcurrencyAnalyzerTool.swift`, `AssistConcurrencyAuditTool.swift`, `AssistEntryPointsDiscoverTool.swift`, `AssistMigrationTool.swift`, read directly at Legacy `d51a8f0d` |
| Per-tool scan / enumeration shapes, the 300 KB / 5,000-file caps, the skipped-directory lists, the 8,000-file `AssistWorkspaceScan` cap | 1 | The same 22 Legacy tool files (their private `enumerateSwiftFiles` / `resolvePath` helpers) and Legacy `Tools/AssistToolSharedHelpers.swift` (`AssistWorkspaceScan`, `AssistWorkspacePaths`), read directly |
| Registry aliases `metrics`, `dead_code`, `migration_advisor`, `ast_inspector`, `concurrency_analyzer`, `swift_format`, `todo_scanner`, `unused_imports` and the parameter-alias mapping in `validate()` | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` (`toolAliases`, `validate()`), read directly |
| `swift_ast_inspector` runs `xcrun swiftc -dump-ast` first and falls back to the regex structural parse; the fallback pattern and inheritance capture | 1 | Legacy `Tools/AssistSwiftASTInspectorTool.swift`, read directly |
| `import_cleanup` protected-module list, whole-word usage test, `@testable` import pattern, per-file direct writes, `filesChanged` result | 1 | Legacy `Tools/AssistImportCleanupTool.swift`, read directly |
| Approval model: one gate (`MCPWritePolicy` / `run()`), `commit()` per changed file, no Autopilot, no second gate | 1 | `specs/ide/assist-approval-model.md` (§§2, 5, 6), read directly |
| SwiftCodeSyntax is a tokenizer / block-structure library, not a Swift declaration parser, and `SwiftCodeMCP` does not depend on it | 1 | `swiftcode/Sources/SwiftCodeSyntax/SyntaxDocument.swift`, `SyntaxStructure.swift`, and `swiftcode/Package.swift` (`SwiftCodeMCP` target dependencies), read directly |
| Test fixture facts (Greeter has 5 Swift files; `main.swift` is an entry point; no TODO/FIXME/MARK/`@available(*, deprecated)`/`@main` markers) | 1 | `swiftcode/Samples/AgentSamples/Greeter`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

## Part C — Security, privacy & platform audits

## Assist security / privacy / platform audit tools — behaviour (Wave 6, slice C)

Behaviour for the 18 Legacy Assist tools ported in Wave 6 (slice C) onto
SwiftCode's MCP host: security, network, permissions, privacy-manifest,
accessibility (×2), access-level, dependency-license, framework-linker,
memory-leak, Mach-O, Core Data, SwiftData, bundle-resource, binary-size,
image-asset-size, license-header, and secrets-scan audits. See
`assist-tool-catalogue.md` for each tool's ID, schema, capability / risk /
permission, and gate. Legacy source (Dylan's own code, ported under MIT):
`SwiftCode/Backend/Assist/Tools/` in `dylans2010/SwiftCode-Legacy` @
`d51a8f0d`. Registry order below is Legacy's `registerAllTools()` order.

## 1. Conventions shared by the audit tools

- **IDs, names, descriptions, property descriptions: Legacy verbatim.**
  The only description that differs in effect is
  `mach_o_binary_analyzer`'s ("via otool and file"): the words are kept
  verbatim, but the implementation parses with SwiftCodeMachO instead of
  shelling out (§5). The input schema's top-level description is not
  reproduced (SwiftCode's `Schema.object` carries none); every property
  description is Legacy's verbatim.
- **Structured data keeps Legacy's keys, typed.** Legacy returns a
  string-only `[String: String]` data map; the port returns the same keys
  with JSON integers / booleans / strings, as Waves 2–5 do. Tools whose
  Legacy result carries no data return a plain text result. The output
  schema of a structured tool lists exactly the keys its handler returns
  (including the empty-case keys, e.g. `topPublicFiles: ""`).
- **Argument validation happens before the handler.** A missing required
  argument fails in `MCPServer.run()` with `argumentProblem` before the
  handler runs, so the handlers' own "Missing required parameter: …"
  guards are dead code for MCP calls but are kept for fidelity (and for
  the one message that differs from the generic form:
  `privacy_manifest_auditor`'s "Missing required parameter: action
  ('audit' or 'generate')").
- **Parameter-name aliases are NOT supported.** Legacy's registry
  rewrites `filePath` / `file_path` / `targetFile` / `file` to `path`
  (and `required_text` to `requiredText` for `license_header_check`).
  SwiftCode's argument validation rejects unknown arguments before the
  handler runs, so those aliases fail (same as Waves 1–2).
- **Paths: two resolver shapes, both workspace-confined.**
  - *Session-aware* (`resolveFileReadingPath`): tools that in Legacy
    appended the raw path to the workspace root with no validation —
    `security_audit_scanner`, `memory_leak_detector`,
    `accessibility_audit_scanner`, `mach_o_binary_analyzer`, and the
    explicit path of `network_security_auditor` and
    `core_data_model_inspector`. Plain relative paths resolve against
    the `dir_cd` working directory; `..` that stays inside the workspace
    is allowed; a path that would escape is refused with
    `<path> is outside the workspace folder <root>`.
  - *Strict* (`auditResolveStrictPath`): tools with Legacy's strict
    per-tool resolvers — `accessibility_audit`, `secrets_scan`,
    `access_level_audit`, `license_header_check`, `binary_size_report`.
    A missing or blank path is the workspace root; any `..` component
    is rejected; a leading-`/` path is used as an absolute filesystem
    path and must lie under the root; a relative path resolves against
    the workspace root, never the session directory. Each tool reports
    its own Legacy message on rejection (see §2).
  - Legacy's unguarded appends are confined, not reproduced: no audit
    tool can read outside the workspace.
- **Deterministic ordering.** `accessibility_audit`'s findings are
  sorted and `core_data_model_inspector`'s entities are reported in
  name order (Legacy appended in enumeration order / iterated a
  dictionary). Finding text is unchanged.
- **Approval: one writer, one gate.** `privacy_manifest_auditor` is the
  only writing tool in this family (Legacy `riskLevel` `safeMutation`;
  its `generate` action writes `PrivacyInfo.xcprivacy`). Its write goes
  through `commit()`; the `audit` action writes nothing and needs no
  approval. The other 17 tools are Legacy `safeRead`, registered
  `writes: false` with the default read-only annotations. There is no
  Autopilot, no second gate, and no bypass of `MCPWritePolicy`. The
  generate action is refused in `readOnly` server mode by
  `MCPServer.run()` before the handler runs.
- **No subprocesses, no shell.** No tool in this family spawns a
  process. `mach_o_binary_analyzer` parses with SwiftCodeMachO (§5);
  everything else reads files and parses text / plists in-process.

## 2. Per-tool behaviour

### 2.1 `memory_leak_detector` — Memory Leak Detector

- **Description (verbatim):** "Scans Swift source code for retain cycles,
  strong self capture in escaping closures, and unowned reference risks."
- **Schema:** `path` (string, required) — "Workspace-relative path to a
  Swift file or directory."
- **Behaviour:** Resolves `path` session-aware. Missing path fails:
  `Path not found: <path>`. A directory is enumerated (all files, no
  skip rules) and only `.swift` files are scanned; a single file is
  scanned only when it is Swift, otherwise the scan covers 0 files. Each
  non-comment line is checked for: (1) `.sink`, `Task {`, or
  `DispatchQueue.` together with `self.` and no `[weak self]` /
  `[unowned self]` → "Potential retain cycle: escaping closure captures
  strong 'self'. Consider adding '[weak self]'."; (2) `[unowned self]`
  with `async`, `await`, or `URLSession` → "Memory crash hazard:
  '[unowned self]' used in asynchronous or network context. Use '[weak
  self]' instead."; (3) a `var delegate:` / `public var delegate:` /
  `weak var delegate:` line with no `weak ` → "Retain cycle risk:
  Delegate property should be declared 'weak var delegate'." Lines
  starting with `//` are skipped. Findings are
  `<rel>:<line> <message>`, capped at 25 with "...and N more."
- **Outputs:** No findings → "Memory Leak Scan passed: No retain cycles
  or strong self closure hazards detected across N files in '<path>'."
  Otherwise "Memory Leak Scan found N potential issues across M files in
  '<path>':\n\n<findings>".
- **Honesty note:** This is a static source scan in Legacy too — it never
  ran Instruments, `leaks`, or a live process, and the port does not
  either. Findings are heuristics ("Potential", "risk"); a clean scan
  means "no matching patterns", not "no leaks". See §6.

### 2.2 `security_audit_scanner` — Security Audit Scanner

- **Description (verbatim):** "Scans Swift source files for hardcoded
  secrets, API keys, insecure HTTP endpoints, and unsafe storage
  practices."
- **Schema:** `path` (string, required) — "Workspace-relative path to a
  directory or Swift file."
- **Behaviour:** Resolves `path` session-aware. Missing path fails:
  `Path does not exist: <path>`. A directory is enumerated (all files,
  no skip rules) and `.swift` / `.plist` files are scanned; a single
  file is scanned whatever its extension. Each non-comment line is
  checked for: (1) `"http://` without `localhost` / `127.0.0.1` →
  "[ATS] Insecure plaintext HTTP URL detected: '<line>'. Upgrade to
  HTTPS."; (2) a lowercased `api_key = "`, `apikey = "`, `secret = "`,
  or `password = "` with a non-empty value → "[Credential] Potential
  hardcoded credential or secret assignment. Use Keychain or Environment
  variables."; (3) `print("token`, `print("password`, or
  `print("apiKey` → "[Privacy] Sensitive credential leaked into debug
  console print statement." Findings are `<rel>:<line> <message>`,
  capped at 20 with "...and N more."
- **Outputs:** No findings → "Security Audit passed: 0 vulnerabilities or
  hardcoded secrets found across N files in '<path>'." Otherwise
  "Security Audit flagged N items in '<path>':\n\n<findings>".
- **Error cases:** Missing path (above). Unreadable / non-UTF-8 files are
  skipped silently, as in Legacy.

### 2.3 `bundle_resource_auditor` — Bundle Resource Auditor

- **Description (verbatim):** "Audits project resources, asset catalogs,
  and bundle copy phases for missing or orphaned assets."
- **Schema:** `path` (string, optional) — "Optional directory path to
  scan. Defaults to workspace root." **The parameter is declared but
  never read** — the workspace root is always scanned, exactly as in
  Legacy.
- **Behaviour:** Enumerates the workspace root (hidden files and package
  descendants skipped). Counts: directories whose extension is
  `.xcassets`; `.json` files outside `DerivedData` / `Pods` paths;
  `.ttf` / `.otf` files. For every `Contents.json` inside a `.imageset`
  directory, each `images[].filename` is checked on disk; a missing file
  is reported as "Missing image asset: `<rel>` references `<filename>`
  which is not on disk."
- **Outputs:** "### Bundle Resource Audit Report:\n\n- **Asset Catalogs**:
  N found (<first 5>)\n- **Bundled JSON Resources**: N files\n-
  **Custom Font Files**: N files\n\n" followed by either "✅ All asset
  catalog image sets and resource declarations verified on disk." or
  "#### ⚠️ Discrepancies Detected:\n" with up to 15 orphan lines.

### 2.4 `core_data_model_inspector` — Core Data Model Inspector

- **Description (verbatim):** "Locates, inspects, and parses Core Data
  .xcdatamodeld schemas, entities, attributes, and relationships."
- **Schema:** `path` (string, optional) — "Optional path to the
  .xcdatamodeld bundle. If omitted, the workspace is scanned."
- **Behaviour:** An explicit path resolves session-aware; otherwise the
  workspace is searched (hidden files and package descendants skipped)
  for the first `.xcdatamodeld` bundle. No model → "No .xcdatamodeld
  Core Data models found in the workspace." Inside the bundle, the first
  `.xcdatamodel` subdirectory containing a `contents` file is read;
  unreadable contents → "Found model at <name>, but contents XML was
  unreadable." Entities and attributes are parsed per line with the
  regexes `<entity name="([^"]+)"` and `<attribute
  name="([^"]+)"[^>]*attributeType="([^"]+)"` (an attribute is recorded
  only when its `attributeType` is on the same line).
- **Outputs:** "### Core Data Model: `<name>` (N entities):\n\n" then per
  entity (name order) "#### Entity `<name>`:\n" with "  - `<attr>:
  <type>`" lines, or "  _(No attributes defined or managed via
  relationships)_". Relationships are not listed (Legacy parses only
  entities and attributes).

### 2.5 `swift_data_schema_auditor` — SwiftData Schema Auditor

- **Description (verbatim):** "Audits SwiftData models (@Model),
  attributes, relationships, and migration schemas across the
  workspace."
- **Schema:** `path` (string, optional) — "Optional directory path to
  scan. Defaults to workspace root." **The parameter is declared but
  never read** — the workspace root is always scanned, exactly as in
  Legacy.
- **Behaviour:** Enumerates Swift files under the root (hidden files and
  package descendants skipped). A file is examined only when it contains
  `@Model`. After an `@Model` line, the next `class ` / `final class ` /
  `public class ` line names the model (the token after `class`, before
  any `:`); following `var `, `@Attribute`, and `@Relationship` lines
  are collected as properties until a `}` line closes the model. A model
  whose closing `}` is never reached is dropped (Legacy behaviour).
- **Outputs:** No models → "No SwiftData `@Model` classes discovered in
  the workspace." Otherwise "### Discovered SwiftData Models (N
  found):\n\n" then per model "#### `@Model class <name>`
  (`<file>:<line>`):\n" with up to 12 "  - `<property>`" lines, or
  "  _(No explicit stored var properties detected)_". Migration schemas
  are not analysed (Legacy does not analyse them either, despite the
  description).

### 2.6 `privacy_manifest_auditor` — Privacy Manifest Auditor

- **Description (verbatim):** "Audits or scaffolds Apple Privacy
  Manifests (PrivacyInfo.xcprivacy) for Required Reason API compliance."
- **Schema:** `action` (string, required) — "Action: 'audit' (scan
  codebase for API usage) or 'generate' (scaffold a valid
  PrivacyInfo.xcprivacy template)."
- **Risk / gate:** Legacy `safeMutation`; registered `writes: true`,
  annotations `readOnly: false, idempotent: true`. Only the `generate`
  action writes, through `commit()`; `audit` writes nothing.
- **Behaviour — `audit`:** Any action other than `generate` (case-insensitive)
  audits. Counts Swift / `.m` files (hidden files and package descendants
  skipped) containing `UserDefaults`, `contentModificationDate` /
  `fileModificationDate`, `volumeAvailableCapacity` / `systemFreeSize`,
  and `systemUptime` / `mach_absolute_time` (one count per file per
  category, however many occurrences). Reports whether
  `PrivacyInfo.xcprivacy` exists at the workspace root, then the four
  counts with their required-reason categories
  (`NSPrivacyAccessedAPICategoryUserDefaults`,
  `NSPrivacyAccessedAPICategoryFileTimestamp`,
  `NSPrivacyAccessedAPICategoryDiskSpace`,
  `NSPrivacyAccessedAPICategorySystemBootTime`). When the manifest is
  missing and UserDefaults or file-timestamp usage exists, the report
  ends with "⚠️ Required Reason APIs detected without
  PrivacyInfo.xcprivacy. Run with `action: 'generate'` to scaffold the
  required manifest."; otherwise "Compliance check complete."
- **Behaviour — `generate`:** Writes the scaffold template (verbatim
  below) to `<workspace>/PrivacyInfo.xcprivacy` via `commit()` (the
  change is presented as "Generate PrivacyInfo.xcprivacy at workspace
  root"; an existing manifest is overwritten with the same template).
  Success: "Successfully generated compliant PrivacyInfo.xcprivacy at
  workspace root."
- **Template (verbatim):**
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyTracking</key>
      <false/>
      <key>NSPrivacyTrackingDomains</key>
      <array/>
      <key>NSPrivacyCollectedDataTypes</key>
      <array/>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>CA92.1</string>
              </array>
          </dict>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>C617.1</string>
              </array>
          </dict>
      </array>
  </dict>
  </plist>
  ```
  The template declares only the UserDefaults (`CA92.1`) and File
  Timestamp (`C617.1`) categories; a project using the disk-space or
  boot-time APIs must add those categories itself — the tool does not
  infer them from the audit counts.
- **Error cases:** Missing / blank `action` → "Missing required parameter:
  action ('audit' or 'generate')". A refused or failed write surfaces
  `commit()`'s error (`MCPServer.rejectedMessage` on review refusal).

### 2.7 `mach_o_binary_analyzer` — Mach-O Binary Analyzer

- **Description (verbatim):** "Inspects built application binaries,
  architectures (arm64, x86_64), and linked dynamic libraries via otool
  and file."
- **Schema:** `binaryPath` (string, required) — "Relative or absolute path
  to the compiled binary or executable file." (The only tool in this
  family whose Legacy parameter is not called `path`.)
- **Behaviour:** Resolves `binaryPath` session-aware. Missing file fails:
  `Binary file not found at: <absolute path>`. The binary is parsed with
  SwiftCode's own `SwiftCodeMachO` target — see §5 for the seam. The report is:
  "### Mach-O Binary Analysis for `<name>`:\n\n#### Architectures
  (N):\n" with one line per slice — "`<arch>` (<file type>, N
  segment(s), N linked librar(y|ies))" — plus install name, UUID, build
  version (platform, minimum OS, SDK), rpaths, code-signature presence,
  and encryption flag when present; then "\n#### Linked Dynamic Libraries
  (N):\n" with the deduplicated dylib list (first 25), each
  "`<path>` (<kind>, current <version>, compatibility <version>)".
- **Error cases:** Not a Mach-O file, or a 32-bit Mach-O, fails honestly:
  `Not a Mach-O binary: <parser message>` (e.g. "not a 64-bit Mach-O
  (magic 0x…)"). No architecture or dylib is ever invented for an
  unparseable file.

### 2.8 `framework_linker_auditor` — Framework Linker Auditor

- **Description (verbatim):** "Inspects PBXFrameworksBuildPhase in Xcode
  projects to audit linked system and dynamic frameworks."
- **Schema:** `path` (string, optional) — "Optional path to .xcodeproj.
  Defaults to workspace root." **The parameter is declared but never
  read** — the workspace is always searched for `project.pbxproj`,
  exactly as in Legacy.
- **Behaviour:** The first `project.pbxproj` found (hidden files and
  package descendants skipped) is read as text; none → "No
  project.pbxproj file found in workspace." Lines between a
  `/* Frameworks */ = {` or `isa = PBXFrameworksBuildPhase;` line and
  the next line containing `};` are the phase; a line inside it
  containing `/* <name> in Frameworks */` contributes `<name>`.
- **Outputs:** "### Framework Linker Audit (`<xcodeproj name>`):\n\n" then
  either "No frameworks explicitly linked in PBXFrameworksBuildPhase
  (e.g. Pure SPM or auto-linked modules).\n" or "#### Linked Frameworks
  & Dependencies (N):\n" with "- `<framework>`" lines (a framework
  named on two phase lines is listed twice, as in Legacy).

### 2.9 `network_security_auditor` — Network Security & ATS Auditor

- **Description (verbatim):** "Audits NSAppTransportSecurity in
  Info.plist for insecure HTTP and ATS exceptions."
- **Schema:** `path` (string, optional) — "Optional path to Info.plist.
  Defaults to searching workspace."
- **Behaviour:** An explicit path resolves session-aware; otherwise the
  workspace is searched (hidden files and package descendants skipped)
  for the first `Info.plist`. A missing or unparseable plist is a
  success, not a failure: "No valid Info.plist found in workspace." A
  plist with no `NSAppTransportSecurity` key is a success: "✅
  NSAppTransportSecurity is in default secure mode (all plain HTTP
  requests blocked, TLS 1.2+ required)."
- **Outputs:** Otherwise "### App Transport Security (ATS) Audit
  (`<file>`):\n\n- **Allows Arbitrary HTTP Loads**: ⚠️ YES (Potential
  App Store Review Risk) / ✅ NO\n- **Allows Local Networking**: YES /
  NO\n- **Exception Domains**: N configured\n\n" followed, when domains
  exist, by "#### Configured Domain Exceptions:\n" with "- **<domain>**:
  `<config>`" lines (the config is the plist value's description).

### 2.10 `accessibility_audit_scanner` — Accessibility Audit Scanner

- **Description (verbatim):** "Audits SwiftUI views for missing
  accessibility labels, hints, and VoiceOver tap targets."
- **Schema:** `path` (string, required) — "Relative path to Swift file or
  directory."
- **Behaviour:** Resolves `path` session-aware. Missing path fails:
  `Path not found: <path>`. A directory is enumerated (hidden files and
  package descendants skipped) for `.swift` files; a single file is
  scanned whatever its extension. Each line is checked for: (1)
  `Image(systemName:` with no `accessibilityLabel` /
  `accessibilityHidden` on the line and none in the 4-line window
  starting at that line → "`<rel>:<line>`: SF Symbol Image has no
  explicit `.accessibilityLabel` or `.accessibilityHidden(true)`."; (2)
  a line starting with `Button("")` or `Button(" ")` → "`<rel>:<line>`:
  Button with empty label has no VoiceOver text description."
- **Outputs:** "### Accessibility Audit Report (N files scanned):\n\n"
  then either "✅ No obvious accessibility omissions found. All scanned
  interactive elements have labels or standard descriptions." or
  "#### ⚠️ Potential VoiceOver & Accessibility Gaps (N):\n" with up to
  25 warning lines. Findings are heuristics; the 4-line modifier window
  is Legacy's (a label on a later line within the window suppresses the
  warning, even when it belongs to a different view).

### 2.11 `license_header_check` — License Header Check

- **Description (verbatim):** "Checks the first 15 lines of each Swift
  file for required header text (default: "Copyright") and reports files
  missing it."
- **Schema:** `path` (string, optional) — "Workspace-relative path of a
  file or directory to check. Defaults to the workspace root.";
  `requiredText` (string, optional) — "Header text that must appear in
  the first 15 lines. Case-insensitive. Default: "Copyright"."
- **Structured data:** `scannedFiles`, `withHeader`, `missingHeader`
  (integers), `missingFiles` (newline-joined relative paths, `""` when
  none).
- **Behaviour:** Resolves `path` with the strict resolver; a rejected
  path fails: "Invalid path: path must stay inside the workspace and
  must not contain '..'." Swift files are enumerated (at most 300 KB
  each, at most 5000 files; `.git`, `DerivedData`, `.build`, `Pods`,
  `node_modules` skipped; hidden files NOT skipped — Legacy passes no
  enumerator options here). A file passes when the first 15 lines
  contain `requiredText` case-insensitively. Legacy also accepts the
  `required_text` alias; SwiftCode does not (§1).
- **Outputs:** No Swift files → "License Header Check: no Swift files
  found." Otherwise "License Header Check: scanned N Swift file(s) for
  header text "<text>" in the first 15 lines — M with header, K
  missing.\n" followed by either "All scanned files contain the required
  header text." or "Files missing the header text:\n- <file>…".

### 2.12 `access_level_audit` — Access Level Audit

- **Description (verbatim):** "Counts Swift declarations by access level
  (public, open, internal, private, fileprivate; default internal when
  unspecified) and lists the files with the most public API. Heuristic:
  access is inferred from keywords on the declaration line, with
  public/open taking precedence over private(set)."
- **Schema:** `path` (string, optional) — "Workspace-relative path of a
  file or directory to audit. Defaults to the workspace root."
- **Structured data:** `scannedFiles`, `public`, `open`, `internal`,
  `private`, `fileprivate`, `total` (integers), `topPublicFiles`
  (newline-joined "<file>: <count>", `""` when none).
- **Behaviour:** Resolves `path` with the strict resolver (same failure
  message as §2.11). Swift files are enumerated exactly as in §2.11. A
  line counts as a declaration when it matches
  `\b(func|class|struct|enum|protocol|actor|var|let|typealias|extension)\b`.
  The level is the first whole-word match in the order public, open,
  fileprivate, private — otherwise internal. (A `private(set)` line
  with no higher keyword counts as private; a line with both `public`
  and `private` counts as public.)
- **Outputs:** No Swift files → "Access Level Audit: no Swift files
  found." Otherwise "Access Level Audit: scanned N Swift file(s), T
  declaration(s) — public: P, open: O, internal: I, private: R,
  fileprivate: F.\n" followed by either "No public/open declarations
  found." or "Files with the most public/open API:\n" with the top 10
  "- <file>: N public/open declaration(s)" lines.

### 2.13 `binary_size_report` — Binary Size Report

- **Description (verbatim):** "Reports total size and the 10 largest
  files for each .app bundle under the workspace build directory or an
  explicit in-workspace path. DerivedData is never scanned."
- **Schema:** `path` (string, optional) — "Optional workspace-relative
  path to a .app bundle or a directory to search for .app bundles.
  Default: build/."
- **Structured data:** `appCount`, `totalBytes` (integers), `apps`
  (comma-joined "<bundle>=<bytes>", `""` when none).
- **Behaviour:** Defaults to `build/` when `path` is missing or blank.
  Resolves with the strict resolver; a rejected path fails: "path must
  be inside the workspace and must not contain '..'." A missing path
  fails: "Path not found at '<path>'. Build the project first or pass a
  path to an existing .app bundle." A path that is neither a `.app`
  bundle nor a directory fails: "path '<path>' is neither a .app bundle
  nor a directory." `.app` bundles are found by enumeration (`.git` and
  `DerivedData` never descended into; a found bundle is not descended
  into). Each bundle is sized by summing its regular files; the 10
  largest files per bundle are listed. Sizes format as "%.2f MB" (≥ 1
  MiB), "%.1f KB" (≥ 1 KiB), else "N bytes".
- **Outputs:** No bundles → "No .app bundles found under '<path>'.
  DerivedData is intentionally never scanned." Otherwise "Binary size
  report: N .app bundle(s)." then per bundle (path order) "\n\n<rel> —
  total <size> (<bytes> bytes), M file(s)" with "  - <rel>: <size>
  (<bytes> bytes)" lines, then "\n\nGrand total: <size> (<bytes>
  bytes)".

### 2.14 `secrets_scan` — Secrets Scan

- **Description (verbatim):** "Scans source and config files for secret
  patterns. Reports file:line:pattern only and never outputs matched
  secret values."
- **Schema:** `path` (string, optional) — "Workspace-relative directory
  or file to scan (optional)."
- **Structured data:** `finding_count`, `files_scanned`,
  `files_with_findings` (integers).
- **Behaviour:** Resolves `path` with the strict resolver; a rejected
  path fails: "Invalid path: '<path>' must be a workspace-relative path
  without '..' and must stay inside the workspace." Scannable files are
  every file under the root except binary-extension files (`png`, `jpg`,
  `jpeg`, `gif`, `pdf`, `zip`, `a`, `o`, `dylib`, `car`, `icns`, `mp3`,
  `mp4`, `mov`, `sqlite`, `db`, `xcarchive`, `framework`, `app`, `ipa`),
  skipping the `.git`, `DerivedData`, `.build`, `Pods`, `node_modules`,
  `.swiftpm`, `Carthage`, `vendor`, `.doccarchive` directories; hidden
  files are NOT skipped (Legacy passes no enumerator options here). A
  single-file root is scanned whatever its extension. The six patterns,
  matched per line:
  | Label | Pattern |
  |---|---|
  | AWS Access Key ID | `AKIA[0-9A-Z]{16}` |
  | GitHub token | `ghp_[A-Za-z0-9]{20,}\|gho_[A-Za-z0-9]{20,}\|github_pat_[A-Za-z0-9_]{20,}` |
  | OpenAI-style API key | `sk-[A-Za-z0-9]{20,}` |
  | api_key assignment | `api[_-]?key\s*=\s*['"][^'"]+['"]` (case-insensitive) |
  | password assignment | `password\s*=\s*['"][^'"]+['"]` (case-insensitive) |
  | Private key block | `-----BEGIN [^-]* PRIVATE KEY-----` |
- **Safety rule (hard):** A finding is `<rel>:<line>:<label>` only — the
  matched value and the source line are never included in any output,
  log, or structured data. Findings are deduplicated and sorted.
- **Outputs:** "Secrets scan: N finding(s) in M file(s), K file(s)
  scanned." followed by either " No secret patterns found." or the
  findings, one per line.

### 2.15 `permissions_audit` — Permissions Audit

- **Description (verbatim):** "Audits Info.plist usage descriptions,
  entitlements, and PrivacyInfo.xcprivacy entries, and flags API usage
  missing a usage description."
- **Schema:** No parameters.
- **Structured data:** `usage_description_count`, `entitlement_count`
  (distinct keys), `privacy_api_count`, `missing_count` (integers),
  `privacy_tracking` (string: `"true"`, `"false"`, or `"not declared"`).
- **Behaviour:** Enumerates every file under the workspace root (hidden
  files skipped; `.git`, `DerivedData`, `.build`, `Pods`, `node_modules`,
  `.swiftpm`, `Carthage`, `vendor` skipped — Legacy's exact skip set).
  Every `Info.plist` contributes its `*UsageDescription` keys; every
  `.entitlements` file contributes all its keys; every
  `PrivacyInfo.xcprivacy` contributes `NSPrivacyTracking` and its
  `NSPrivacyAccessedAPITypes[].NSPrivacyAccessedAPIType` values. Then a
  heuristic: for each of `AVCaptureDevice` →
  `NSCameraUsageDescription`, `CLLocationManager` →
  `NSLocationWhenInUseUsageDescription`, `PHPhotoLibrary` →
  `NSPhotoLibraryUsageDescription`, `CNContactStore` →
  `NSContactsUsageDescription`, `AVAudioRecorder` →
  `NSMicrophoneUsageDescription`, `EKEventStore` →
  `NSCalendarsUsageDescription`, `HKHealthStore` →
  `NSHealthShareUsageDescription`, `SFSpeechRecognizer` →
  `NSSpeechRecognitionUsageDescription`, when the marker appears in any
  Swift file but the key is absent from every `Info.plist`, a missing
  entry is reported ("<marker> used in <first 3 files> but <key> is
  missing"). `NSLocationAlwaysUsageDescription` is accepted as an
  alternative to the WhenInUse key.
- **Outputs:** "Permissions audit complete.\n" then the seven summary
  lines (usage descriptions with count and sorted keys; usage description
  files; entitlement keys with distinct count and sorted keys;
  entitlement files; PrivacyInfo files; `NSPrivacyTracking`;
  `NSPrivacyAccessedAPITypes` with count and sorted values) and either
  "Missing usage descriptions: none detected by heuristic." or
  "Missing usage descriptions (N):\n  - <entry>…".

### 2.16 `accessibility_audit` — Accessibility Audit

- **Description (verbatim):** "Heuristic SwiftUI accessibility audit:
  flags Button/Image without accessibility labels, TextField with empty
  labels, and color-only state."
- **Schema:** `path` (string, optional) — "Workspace-relative directory
  or file to audit (optional)."
- **Structured data:** `finding_count`, `files_scanned` (integers).
- **Behaviour:** Resolves `path` with the strict resolver; a rejected
  path fails: "Invalid path: '<path>' must be a workspace-relative path
  without '..' and must stay inside the workspace." Swift files are
  enumerated (hidden files skipped; `.git`, `DerivedData`, `.build`,
  `Pods`, `node_modules`, `.swiftpm`, `Carthage`, `vendor` skipped; a
  single-file root yields itself when Swift). Per file: a `Button(` line
  with no `accessibilityLabel` / `accessibilityHidden` /
  `accessibilityElement` on the line opens a 10-line window — a finding
  ("<rel>:<line>:Button without .accessibilityLabel (heuristic)") is
  emitted unless an accessibility modifier appears within the window
  (a second `Button(` forces the pending one out first); an `Image(`
  line works the same with a 5-line window ("Image without
  .accessibilityLabel / .accessibilityHidden (heuristic)"); a
  `TextField(` line containing `""` is an immediate finding ("TextField
  with empty label (heuristic)"); a `foregroundColor` line with `.red` /
  `.green` / `.orange` and no accessibility modifier is an immediate
  finding ("Color-only state via foregroundColor (heuristic) - pair with
  a label or icon"). Findings are sorted; the header says "Findings are
  heuristics; verify each one."
- **Outputs:** "Accessibility audit: N finding(s) in M Swift file(s).
  Findings are heuristics; verify each one." followed by either " No
  issues detected." or the findings, one per line.

### 2.17 `dependency_licenses` — Dependency Licenses

- **Description (verbatim):** "Inventories third-party dependencies from
  Package.resolved and Podfile.lock, reporting versions for license
  review."
- **Schema:** No parameters.
- **Structured data:** `count` (integer).
- **Behaviour:** Reads only `<workspace>/Package.resolved` and
  `<workspace>/Podfile.lock` (top-level files; nested lockfiles are not
  read, as in Legacy). `Package.resolved` pins are read from the v1
  `pins` array or the v2 `object.pins` array; each row is
  `<identity|package|unknown>`, `SwiftPM`, `<state.version|unknown>`,
  `see package repository`. `Podfile.lock` rows come from the `PODS:`
  section: each indented line's first token, until the first blank or
  non-indented line; each row is `<name>`, `CocoaPods`, `""`, `see
  podspec`.
- **Outputs:** No rows → "No resolvable dependency lockfiles found
  (checked Package.resolved, Podfile.lock)." Otherwise "Dependency
  license inventory:\n<table>\n\nNote: license text lives in each
  package's repository; verify before distribution." where the table is
  a Markdown table with headers Dependency | Manager | Version |
  License. The tool reports versions only — it does not fetch, read, or
  verify any license text. Legacy capability is `repositoryDiscovery`
  (the only non-`diagnostics` tool in this family); SwiftCode's `MCPTool`
  has no capability field, so the distinction is recorded here only.

### 2.18 `image_asset_size_report` — Image Asset Size Report

- **Description (verbatim):** "Reports oversized image files inside
  .xcassets catalogs — candidates for compression or vectorization."
- **Schema:** `thresholdKB` (integer, optional) — "Size threshold in KB.
  Default 500."
- **Structured data:** `imageCount`, `oversizedCount` (integers),
  `totalBytes` (integer).
- **Behaviour:** The threshold is `max(1, thresholdKB ?? 500)` KiB. Image
  files (`.png`, `.jpg`, `.jpeg`, `.heic`, `.webp`, `.tiff`, `.pdf`)
  under the workspace are enumerated with SwiftCode's shared
  `SearchWorkspace` scan (hidden files and top-level skipped
  directories excluded, as Legacy's `AssistWorkspaceScan` does) and
  only files whose path contains `.xcassets/` are counted. Files at or
  above the threshold are listed largest-first (up to 50), each as
  "- <rel> — <size> KB" (one decimal).
- **Outputs:** No catalog images → "No image files found inside .xcassets
  catalogs." Otherwise "Asset catalog images: N files, B bytes total.\n
  Oversized (≥T KB): M" followed by the oversized lines, or "All images
  are under the threshold."

## 3. Safety rules

- **Secrets are never echoed.** `secrets_scan` reports
  `file:line:pattern` only (§2.14). `security_audit_scanner` does
  include the offending source line in its ATS finding (Legacy
  behaviour — the line is a URL, not a credential) but never a matched
  secret value; its credential finding names the pattern, not the value.
- **Workspace confinement (§1).** Every path a caller supplies resolves
  inside the workspace; Legacy's unguarded appends are confined, not
  reproduced.
- **One write, one gate.** The only file this family writes is
  `PrivacyInfo.xcprivacy` via `privacy_manifest_auditor`'s `generate`
  action, through `commit()` (§2.6). No other tool asks for approval, and
  no tool consults the write policy itself.
- **No execution.** No audit tool runs a subprocess, a shell, Instruments,
  `leaks`, `otool`, or `file`. The Mach-O tool parses bytes (§5).
- **No Autopilot.** Legacy's `AssistPermissionsManager` Autopilot bypass
  is not ported, as in every other wave (see
  `assist-approval-model.md` §5.2).

## 4. Catalogue-ready sections

The sections above are written so the coordinator can merge them into
`assist-tool-catalogue.md` verbatim: each §2 subsection carries the
tool's verbatim description, its schema (properties with verbatim
descriptions, required list), its outputs, and its error cases.
Risk table for the catalogue (§1.3): 17 tools are Legacy `safeRead`
(`diagnostics`, except `dependency_licenses` which is
`repositoryDiscovery`) → registered `writes: false`, annotations
`readOnly: true, idempotent: true`. `privacy_manifest_auditor` is Legacy
`safeMutation` (`diagnostics`) → registered `writes: true`, annotations
`readOnly: false, idempotent: true`. Legacy aliases verified against
`AssistToolRegistry.toolAliases` (Legacy @ `d51a8f0d`):
`security_audit` → `security_audit_scanner`,
`memory_leak` → `memory_leak_detector`,
`bundle_auditor` → `bundle_resource_auditor`,
`core_data_inspector` → `core_data_model_inspector`,
`swift_data_schema` → `swift_data_schema_auditor`,
`privacy_manifest` → `privacy_manifest_auditor`,
`macho_analyzer` → `mach_o_binary_analyzer`,
`framework_linker` → `framework_linker_auditor`,
`network_security` → `network_security_auditor`,
`a11y_scanner` → `accessibility_audit_scanner`. No aliases exist for
`permissions_audit`, `accessibility_audit`, `access_level_audit`,
`dependency_licenses`, `binary_size_report`, `image_asset_size_report`,
`license_header_check`, or `secrets_scan`. (SwiftCode resolves no aliases
in this wave; the table is recorded here so the catalogue can carry it.)

## 5. Mach-O seam notes

- Legacy's `mach_o_binary_analyzer` ran two subprocesses:
  `/usr/bin/file <path>` for the architecture line and `xcrun otool -L
  <path>` for linked libraries. Both are macOS-only (`xcrun` does not
  exist on Linux) and both shell out with a raw path argument.
- The port does not build a parallel Mach-O parser. It reuses SwiftCode's
  existing `SwiftCodeMachO` target (`MachOFile` / `MachOImage` /
  `ByteReader`, specified in `specs/formats/macho-and-dyld-cache.md`
  §2), which the `SwiftCodeMCP` target now depends on (one-line
  `Package.swift` change: `"SwiftCodeMachO"` added to `SwiftCodeMCP`'s
  dependencies). `MachOFile` handles fat (universal) containers and
  thin images; `MachOImage` exposes CPU type / subtype, file type,
  segments, dylib references (path, kind, current / compatibility
  versions), install name, dylinker, UUID, build version, entry offset,
  rpaths, code signature, chained fixups, exports trie, symtab, function
  starts, and the encryption flag.
- The report therefore differs from Legacy's in form, not in substance:
  architectures come from the parsed slices (names via
  `MachO.architectureName`), dylibs from the parsed load commands
  (deduplicated across slices, first 25 listed, as Legacy capped its
  `otool` lines at 25). There is no `file`-style free-text line to
  reproduce — the port reports the parsed facts instead of quoting a
  CLI.
- Limits inherited from `SwiftCodeMachO`, reported honestly rather than
  worked around: only 64-bit images parse (`MachOImage` requires magic
  `0xFEEDFACF`); a 32-bit Mach-O, a non-Mach-O file, or a truncated
  header fails with `Not a Mach-O binary: <parser message>`. The tool
  never claims an architecture it did not parse.

## 6. Honestly-failing / BLOCKED notes

- **BLOCKED: none.** All 18 tools are implemented and registered.
- **Honestly-failing: none registered as failing.** Two tools fail
  honestly on inputs they cannot handle, which is the designed
  behaviour, not a port gap:
  - `mach_o_binary_analyzer` fails on non-Mach-O files and 32-bit
    Mach-O binaries (§5) — prerequisite for success is a 64-bit
    Mach-O (thin or fat).
  - `binary_size_report` fails when the path does not exist — the
    prerequisite is a built `.app` bundle (or a directory containing
    one); the error says so ("Build the project first or pass a path
    to an existing .app bundle.").
- **Static-only by design (not a gap):** `memory_leak_detector`,
  `security_audit_scanner`, `accessibility_audit`, and
  `accessibility_audit_scanner` are heuristic source scans in Legacy;
  none of them executes code, runs Instruments, or observes a live
  process, and the port does not add that. A clean result means "no
  matching patterns found", never "proven leak-free / secure /
  accessible". `swift_data_schema_auditor` does not analyse migration
  schemas and `core_data_model_inspector` does not list relationships,
  despite their descriptions — both limits are Legacy's, preserved.
- **Pending (not done here):** `swift build` / `swift test` on a Mac
  (no Swift toolchain exists in this environment — static checks only);
  the coordinator's wiring of `auditTools` into `installTools()` and
  the catalogue merge.

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 18 Legacy tool IDs, names, descriptions, schemas, risk levels, capabilities, and `execute()` behaviour | 1 | Legacy `SwiftCode/Backend/Assist/Tools/Assist{SecurityAudit,NetworkSecurityAuditor,PermissionsAudit,PrivacyManifestAuditor,AccessibilityAudit,AccessibilityAuditScanner,AccessLevelAudit,DependencyLicenses,FrameworkLinkerAuditor,MemoryLeakDetector,MachOBinaryAnalyzer,CoreDataModelInspector,SwiftDataSchemaAuditor,BundleResourceAuditor,BinarySizeReport,ImageAssetSizeReport,LicenseHeaderCheck,SecretsScan}Tool.swift`, read directly @ `d51a8f0d` |
| Legacy `registerAllTools()` order; alias table (`security_audit`, `memory_leak`, `bundle_auditor`, `core_data_inspector`, `swift_data_schema`, `privacy_manifest`, `macho_analyzer`, `framework_linker`, `network_security`, `a11y_scanner`); common parameter aliases (`filePath`, `required_text`, …) | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift`, read directly |
| `SwiftCodeMachO` API (`MachOFile`, `MachOImage`, `ByteReader`, `MachO.architectureName`, 64-bit-only parsing, fat containers) | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMachO/MachOImage.swift`, `ByteReader.swift`, read directly; `specs/formats/macho-and-dyld-cache.md` §2 |
| Session-aware vs strict path resolvers; `commit()` / `approve()` gate; `MCPWritePolicy` modes; no Autopilot | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+FileReadingSupport.swift`, `SwiftCodeTools+Content.swift` (`commit`), `specs/ide/assist-approval-model.md`, read directly |
| `SearchWorkspace.files` skip set (Legacy `AssistWorkspaceScan` port) | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+SearchSupport.swift`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |

## Part D — Docs, review & repo tooling

## Assist testing / review / docs tools — behaviour spec (Wave 6, slice D)

SwiftCode module: `SwiftCodeMCP` (the MCP server and its tools). Implementation:
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ReviewDocs.swift` (`reviewDocsTools`),
tests: `swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeReviewDocsTests.swift`.

This spec is the behaviour contract for the 23 Legacy Assist tools that
audit, document, review and report on a workspace: API-surface and
docs-coverage analysis, README / Markdown tooling, repository overview,
static review engines, doc comments and snippets, asset-catalog colour
and icon tooling, staleness and change-impact reporting, change
validation, session export / progress, undo, and registry lookup.

Behaviour source (all read directly, Dylan's own code, ported under
MIT): Legacy `SwiftCode/Backend/Assist/Tools/` —
`AssistApiDocsCoverageTool.swift`, `AssistApiEndpointAuditTool.swift`,
`AssistApiSurfaceExtractTool.swift`, `AssistReadmeGenerateTool.swift`,
`AssistReadmeLocateTool.swift`, `AssistRepoOverviewTool.swift`,
`AssistMarkdownLinkCheckTool.swift`, `AssistMarkdownTocGenerateTool.swift`,
`CodeReview.swift` (registering class `CodeReviewTool`, confirmed by
reading the file — the `code_review` ID string appears in several
files, but only this file registers it),
`AssistAutomatedRepairEngine.swift`,
`AssistAutonomousReviewEngine.swift`,
`AssistDocStringGeneratorTool.swift`, `AssistCodeSnippetTool.swift`,
`AssistIconGeneratorTool.swift`, `AssistColorUsageAuditTool.swift`,
`AssistColorSetBuilderTool.swift`, `AssistStaleFilesReportTool.swift`,
`AssistChangeImpactEstimateTool.swift`, `AssistUndoTool.swift`,
`AssistValidateChangesTool.swift`, `AssistSessionExportTool.swift`,
`AssistSessionProgressReportTool.swift`,
`AssistToolCapabilityLookupTool.swift`; the alias table in
`AssistToolRegistry.swift` (`toolAliases`); `AssistToolSharedHelpers.swift`
(`AssistWorkspaceScan`, `AssistWorkspacePaths.iso8601`); and
`AssistToolingSupport` (the clamping `resolvePath` and
`enumeratedFiles`) as used by the tools above. Legacy versions are at
`d51a8f0d`.

Conventions (same as Waves 1–3): schemas are Legacy's
`parametersSchema` verbatim, plus the `workspace` parameter Wave 1 adds
to every tool; structured data keeps Legacy's keys with typed JSON
values (integers and booleans) instead of Legacy's string-only map;
Legacy's parameter-name aliases are NOT supported (SwiftCode's argument
validation rejects unknown arguments before the handler runs); paths
resolve as §3 describes; every writing handler gates through
`commit()` / `approve()` before touching disk (§3); there is no
Autopilot bypass.

## 1. The 23 tools

| ID | Title | Legacy risk | Writes | Status |
|---|---|---|---|---|
| `api_docs_coverage` | API Docs Coverage | safeRead | No | Implemented |
| `api_endpoint_audit` | API Endpoint Audit | safeRead | No | Implemented |
| `api_surface_extract` | API Surface | safeRead | No | Implemented |
| `automated_repair_engine` | Automated Repair Engine | safeMutation | Yes | Implemented (deterministic part only; §4.3) |
| `autonomous_review_engine` | Autonomous Review Engine | safeRead | No | Implemented |
| `change_impact_estimate` | Change Impact Estimate | safeRead | No | Implemented |
| `code_review` | Code Review Validation | safeRead | No | Honestly-failing — LLM prerequisite (§4.1) |
| `code_snippet_manager` | Code Snippet & Architecture Template Manager | safeRead | No | Implemented |
| `color_usage_audit` | Color Usage Audit | safeRead | No | Implemented |
| `colorset_builder` | Color Set Builder | safeMutation | Yes | Implemented |
| `docstring_generator` | DocC Documentation Generator | safeRead | No | Implemented |
| `icon_generator_tool` | App Icon Generator & Validator | safeMutation | Yes | Implemented |
| `markdown_link_check` | Markdown Link Check | safeRead | No | Implemented |
| `markdown_toc_generate` | Markdown TOC Generate | safeMutation | Yes | Implemented |
| `readme_generate` | README Generate | safeMutation | Yes | Implemented |
| `readme_locate` | Locate README | safeRead | No | Implemented |
| `repo_overview` | Repository Overview | safeRead | No | Implemented |
| `safe_undo` | Undo Last Action | potentiallyDestructive | Yes | Honestly-failing — snapshot store (§4.2) |
| `safe_validate_changes` | Validate Changes | safeRead | No | Implemented |
| `session_export` | Export Session | safeMutation | Yes | Implemented |
| `session_progress_report` | Session Progress Report | safeRead | No | Implemented, degraded — no phases (§4.4) |
| `stale_files_report` | Stale Files Report | safeRead | No | Implemented |
| `tool_capability_lookup` | Tool Capability Lookup | safeRead | No | Implemented, adapted — no capability/cost (§4.5) |

Install order is the table order (alphabetical by ID). Nothing in this
slice is BLOCKED: the two tools that cannot run here are registered
honestly-failing (§4), not omitted.

## 2. Per-tool behaviour (catalogue-ready)

Each entry gives the verbatim Legacy description, the verbatim input
schema (plus `workspace`), the output schema, the behaviour, and the
error cases. `workspace` is `Schema.workspace` on every tool
("Optional: the workspace to use (its path); opened when it is not the
open one.") and is omitted from the per-tool property lists below.

### 2.1 `api_docs_coverage`

- Description (verbatim): "Measures the share of public/open Swift
  declarations that carry documentation comments."
- Input: `limit` (integer) — "Maximum undocumented symbols to list.
  Default 50." No required parameters.
- Output: `total` (integer), `documented` (integer), `coverage`
  (string, `"%.1f"` percent).
- Behaviour: scans every Swift file in the workspace (hidden files and
  `.git` / `.build` / `DerivedData` / `.swiftpm` / `Pods` / `Carthage` /
  `node_modules` / `.venv` skipped). A declaration is a line matching
  `^\s*(public|open)\s+(?:final\s+|static\s+)*(class|struct|enum|protocol|func|var|let|typealias|init)\b`
  (matched per line, so `^` is the line start). It counts as documented
  when any of the up-to-3 lines above it starts (after trimming) with
  `///` or `/**`. `limit` is clamped to 1…500 (default 50) and caps only
  the undocumented list, never the counts.
- Output text: `API docs coverage: %.1f%% (%d of %d public declarations
  documented)`; when undocumented symbols exist, `Undocumented
  (showing N):` followed by `- <rel>:<line>: <trimmed line, first 90
  characters>` per symbol.
- Errors: none — an empty workspace reports `0.0% (0 of 0 …)` with an
  empty undocumented list.

### 2.2 `api_endpoint_audit`

- Description (verbatim): "Inventories hardcoded http(s) URL literals
  in Swift sources, grouped by host — surfacing endpoints that should
  be configurable."
- Input: `limit` (integer) — "Maximum URL sites. Default 100, max 500."
  No required parameters.
- Output: `count` (integer, 0 when no endpoints) or `hostCount`
  (integer), `siteCount` (integer).
- Behaviour: scans Swift files line by line. Lines whose trimmed form
  starts with `//` are skipped. URL literals match
  `"(https?://[^"\s\\]+)"` (group 1 is the URL). The host is
  `URL(string:)?.host`, or `(unparseable)`. A site is skipped when the
  host contains `example.`, or when the host contains `apple.com` AND
  the URL contains `developer`. `byHost` counts every match (not
  capped); the site list is capped at `limit` (clamped 1…500, default
  100).
- Output text: no endpoints →
  `No hardcoded http(s) endpoints found in Swift sources.` Otherwise
  `Hardcoded endpoints by host:` then `- <host>: <count>` per host
  (count descending), then `Sites (N[+]):` with `- <rel>:<line>:
  <url, first 100 characters>` per site. The `+` appears when the site
  list reached the limit.
- Errors: none.

### 2.3 `api_surface_extract`

- Description (verbatim): "Extracts public/open declarations (func,
  class, struct, enum, protocol, actor, var, let, typealias, extension)
  from Swift files, grouped by file, with file:line locations and a
  total count."
- Input: `path` (string) — "Workspace-relative path of a file or
  directory to scan. Defaults to the workspace root." No required
  parameters.
- Output: `scannedFiles` (integer), `declarationCount` (integer),
  `declarations` (string, flat list joined with `\n`).
- Behaviour: the path uses Legacy's private resolver (§3.3): empty or
  absent means the workspace root; any `..` is refused; a leading-`/`
  path must be the root or under it; anything else appends to the root.
  A single Swift file (at most 300 KB) scans on its own; a directory
  enumerates `.swift` files up to 300 KB each, skipping `.git` /
  `DerivedData` / `.build` / `Pods` / `node_modules`, at most 5000
  files, sorted by path. Declarations match
  `\b(public|open)\s+(?:\w+\s+)*?(func|class|struct|enum|protocol|actor|var|let|typealias|extension)\b\s*([A-Za-z_][A-Za-z0-9_]*)?`
  — note the kind list has no `init`, so `public init(...)` is NOT
  counted (unlike `api_docs_coverage`, which does count it). Each
  entry is `<rel>:<line> <access> <kind>[ <name>]`, grouped by file
  (files sorted, entries in file order). The listing caps at 1000
  declarations.
- Output text: `API Surface: scanned N Swift file(s), found M
  public/open declaration(s) across K file(s).` then per file
  `<rel>:` with `  - <entry>` lines; `Listing capped at 1000
  declarations.` when capped. No Swift files →
  `API Surface: no Swift files found.` with all-zero data.
- Errors: an unresolvable path fails with `Invalid path: path must
  stay inside the workspace and must not contain '..'.` A regex that
  fails to compile fails with `API Surface: failed to build declaration
  pattern.`

### 2.4 `readme_generate`

- Description (verbatim): "Generates a README.md skeleton from real
  repository inspection: project name, build systems, targets,
  structure, and entry points."
- Input: `path` (string) — "Workspace-relative output path. Default:
  README.generated.md."; `overwrite` (boolean) — "Overwrite if the
  file exists. Default false." No required parameters. Writes: yes
  (`safeMutation`, approval-gated through `commit()`).
- Output: `path` (string, the path as given).
- Behaviour: the output path resolves session-aware
  (`resolveFileReadingPath`); an outside-workspace path fails with
  `Refusing to write outside the workspace: <path>`. An existing file
  without `overwrite: true` fails with `File already exists at <path>.
  Pass overwrite: true to replace it.` The skeleton is built from real
  inspection: project name is the workspace folder name; build systems
  are `SwiftPM` (a `Package.swift` at the root), `Xcode workspace` (a
  `.xcworkspace` at the root) else `Xcode project` (a `.xcodeproj` at
  the root), `CocoaPods` (a `Podfile` at the root); targets come from
  the first `.pbxproj` under the root, matching `/\* (\w[\w ]*) \*/ =
  \{\s*isa = PBXNativeTarget;`, sorted; Swift source files are counted.
  The Markdown is Legacy's verbatim skeleton (`# <project>`, the
  "Generated README skeleton — fill in …" line, Overview with
  workspace / Swift-file count / build systems, Targets when any,
  Building with `swift build` and/or the `xcodebuild` stanza, Project
  Structure, License).
- Output text: `README skeleton written to <path>.`

### 2.5 `readme_locate`

- Description (verbatim): "Finds README files in the workspace (any
  case/extension), reporting each path and its title line."
- Input: no properties. Output: `count` (integer).
- Behaviour: every workspace file whose name (lowercased) starts with
  `readme`, sorted by path. Each line is `- <rel>: <first non-empty
  line, trimmed, first 120 characters>`, or `(unreadable)` when the
  file cannot be read as UTF-8.
- Output text: `README files found:` followed by one line per file.
- Errors: no README fails with `No README file found in the
  workspace.` (a failure, not an empty success).

### 2.6 `repo_overview`

- Description (verbatim): "Summarizes the workspace repository: file
  counts by language, directory breadth, README/license presence, and
  largest files."
- Input: `topLanguages` (integer) — "How many top languages to report.
  Default 8." No required parameters.
- Output: `fileCount` (integer), `totalBytes` (integer), `readme`
  (string, `""` when absent), `license` (string, `""` when absent).
- Behaviour: enumerates all workspace files (hidden files and
  `.git` / `.build` / `DerivedData` / `.swiftpm` / `Pods` / `Carthage` /
  `node_modules` / `.venv` skipped). Extensions are lowercased; files
  without an extension count under `(no extension)` (which the text
  renders as `.(no extension)` — Legacy's quirk, preserved).
  `topLanguages` is clamped to 1…20 (default 8). README is the first
  existing of `README.md`, `README.markdown`, `README.txt`,
  `Readme.md`, `readme.md` at the root; license is the first existing
  of `LICENSE`, `LICENSE.md`, `LICENSE.txt`, `LICENCE`, `COPYING`.
  Largest files are the top 5 by size.
- Output text (verbatim shape):
  `Repository overview for <folder>:` /
  `- Total files: N` / `- Total size: B bytes` /
  `- README: <name or "not found">` /
  `- License: <name or "not found">` /
  `- Top languages/extensions:` with `  - .<ext>: <count> files` /
  `- Largest files:` with `  - <path> (<size> bytes)`.
- Errors: none.

### 2.7 `markdown_link_check`

- Description (verbatim): "Validates links in Markdown files:
  internal file links must resolve; reports broken ones."
- Input: `path` (string) — "Optional workspace-relative Markdown
  file. Omit to check all Markdown files." No required parameters.
- Output: `checked` (integer), `broken` (integer).
- Behaviour: with `path`, checks that one file (outside-workspace
  fails with `Refusing to access path outside the workspace: <path>`);
  otherwise checks every `.md` / `.markdown` file in the workspace. A
  file that cannot be read as UTF-8 is skipped silently (so a missing
  single file reports `All 0 internal links resolve.` rather than
  failing). Links match
  `\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)` (group 2 is the
  destination). Skipped without counting: destinations starting with
  `#`, containing `://`, or starting with `mailto:`; after stripping a
  `#anchor` suffix, an empty destination is skipped. Every other
  destination counts as `checked`; it is broken when it resolves
  outside the workspace root or the target does not exist (resolution
  is relative to the linking file's directory). Broken entries cap at
  200.
- Output text: no broken links → `All <checked> internal links
  resolve.` Otherwise `Broken internal links (<broken> of <checked>
  checked):` with `- <rel>: [<dest>]` per broken link. Broken links
  are a successful result, not a tool error.
- Errors: only the outside-workspace single path (§ above).

### 2.8 `markdown_toc_generate`

- Description (verbatim): "Generates a table of contents from a
  Markdown file's headings and inserts or updates it between TOC
  markers."
- Input: `path` (string) — "Workspace-relative Markdown file."
  (required); `maxDepth` (integer) — "Heading depth to include.
  Default 3, max 6." Writes: yes (`safeMutation`, approval-gated
  through `commit()`).
- Output: `path` (string, as given), `entryCount` (integer).
- Behaviour: `maxDepth` is clamped to 1…6 (default 3). Headings are
  lines starting with `#`; level is the count of leading `#`
  (1…`maxDepth`); the title is the remainder trimmed, and empty titles
  are skipped. Anchors are built by lowercasing, keeping only
  alphanumerics, spaces and hyphens, and replacing spaces with
  hyphens. TOC lines are `(level-1)×2 spaces + "- [<title>](#<anchor>)"`,
  wrapped as `<!-- TOC -->\n<lines>\n<!-- /TOC -->`. When both markers
  are present (in order), the block between them — markers included —
  is replaced. Otherwise the block is inserted after the first `# `
  heading (a blank line, then the block), or prepended (`<toc>\n\n<text>`)
  when there is no `# ` heading.
- Output text: `Table of contents (<n> entries) written to <path>.`
- Errors: a missing/blank `path` fails with `Missing required
  parameter: path`; an unreadable file fails with `Cannot read Markdown
  file at: <path>`; a file with no headings in range fails with `No
  headings found in <path>.`

### 2.9 `code_review`

- Description (verbatim): "Validates the completed implementation
  using an independent AI reviewer stage before finishing the task."
- Input: no properties. No output schema (it never succeeds).
- Behaviour: honestly-failing (§4.1). Legacy gathers the session
  objective, completed actions, plan, tool-call history, repository
  changes (snapshot diff), and build/diagnostic events, sends them to
  an LLM with the `CodeReviewSystemAsset.md` system prompt, and
  requires a JSON verdict whose `status` is `task_ready` or
  `task_failed`. SwiftCode's MCP host has no LLM provider wired for this
  tool, so the handler always throws naming that prerequisite and
  verifies nothing. The tool is `safeRead` / `writes: false`, so it
  runs (and fails) even on a read-only server.
- Errors: always — see §4.1 for the exact message.

### 2.10 `automated_repair_engine`

- Description (verbatim): "Consumes compiler diagnostics, applies
  targeted fixes, and validates by rebuilding."
- Input: `errors` (string, required) — "Compiler diagnostic lines in
  'path:line:...' format. Only lines containing '.swift:' are
  processed." Writes: yes (`safeMutation`, one `commit()` per
  annotated file, in diagnostic order, stopping at the first refusal).
- Output: `fix_count` (integer).
- Behaviour: only lines containing `.swift:` are processed. A line is
  parsed by splitting on `:` — the path is the first field, the line
  number the second (0 when it is not a number); lines with three or
  fewer fields are skipped. For each parsed diagnostic, the file is
  re-read from disk (so a second diagnostic for the same file
  annotates the already-annotated text, as Legacy does), and when the
  line number is in range the line becomes
  `// AssistAutoRepair: review required` followed by the original line.
  Out-of-range line numbers are skipped silently. Paths resolve
  session-aware (`resolveFileReadingPath`); an unresolvable path or an
  unreadable file fails the whole call.
- Output text: `Applied <n> automated repair annotations.`
- Errors: a missing or empty `errors` payload fails with `Missing
  compiler errors payload` (a missing argument is caught earlier by
  argument validation as `missing the required argument "errors"`).
- Note: despite the description, Legacy's `execute()` never rebuilds,
  and neither does the port — the annotation is the whole repair
  (§4.3). No rebuild validation is performed or claimed.

### 2.11 `autonomous_review_engine`

- Description (verbatim): "Performs static self-review, detects
  inefficient patterns, and proposes refactors."
- Input: `path` (string) — "Workspace-relative directory to review.
  Defaults to the workspace root." No required parameters.
- Output: `finding_count` (integer), `findings` (string, findings
  joined with `\n`, at most 1000).
- Behaviour: the path uses the clamping resolver (§3.3) — an escaping
  path silently becomes the workspace root. Swift files up to 800 KB
  are scanned (hidden files skipped, no skipped-directory rule). Three
  literal checks, one finding per file per check:
  1. `text.contains("!\n") || text.contains(" as!")` →
     `<rel>: force-unwrap/type-cast usage detected; prefer safe
     optional binding.`
  2. `text.contains("DispatchQueue.main.async") &&
     text.contains("Task {")` → `<rel>: mixed concurrency primitives
     found; consider consolidating around Swift Concurrency.`
  3. `text.components(separatedBy: "for ").count > 6 &&
     !text.contains(".filter")` → `<rel>: loop-heavy section;
     evaluate higher-order transformations or index precomputation.`
  Findings are advisory text only; nothing is changed or proposed as
  an edit. Despite the name, this is a literal substring scan, not an
  LLM or semantic review.
- Output text: `Autonomous review complete.`
- Errors: none.

### 2.12 `docstring_generator`

- Description (verbatim): "Generates Apple DocC compliant
  documentation comments (///) with Parameters, Returns, and Throws
  tags for Swift declarations."
- Input: `declaration` (string, required) — "The Swift function,
  type, or protocol declaration header."; `summary` (string) — "Brief
  single-line summary of what the declaration does." No output schema
  (plain text result).
- Behaviour: Legacy risk is `safeRead` despite its `fileModification`
  capability — the tool writes nothing and only returns the generated
  comment, so it is registered `writes: false`. The summary defaults
  to `Performs operations associated with this declaration.` The
  comment is `/// <summary>`, `///`, then one `/// - Parameter <name>:
  The <type> value supplied for processing.` per `name: Type` pair
  found between the first `(` and the last `)` (split on `,`; the name
  is the last space-separated word of the part before `:`; `_` and
  empty names are skipped; only the part up to the first `:` after the
  name is used as the type), then `/// - Throws: An error if processing
  or I/O fails during execution.` when the declaration contains
  `throws`, then `/// - Returns: A \`<type>\` instance representing the
  computed outcome.` when it contains `->` (the type is the text after
  the last `->`, trimmed). The result is the comment, a blank line in
  the sense of the joined lines, then the declaration itself.
- Output text: `Generated DocC Documentation:\n\n```swift\n<comment>\n<declaration>\n``` `.
- Errors: a missing `declaration` is caught by argument validation
  (`missing the required argument "declaration"`); the handler's
  `Missing required parameter: declaration` is a backstop.

### 2.13 `code_snippet_manager`

- Description (verbatim): "Retrieves and injects battle-tested Swift
  architecture templates (SwiftUI MVVM, AsyncStream, Actor isolation,
  Keychain wrapper)."
- Input: `templateId` (string, required) — "Template identifier:
  'observable_viewmodel', 'async_stream', 'keychain_helper',
  'swiftui_glass_card', 'actor_service'."; `targetName` (string) —
  "Name of the type or feature to substitute in the template." No
  output schema (plain text result).
- Behaviour: the template id matches case-insensitively;
  `targetName` defaults to `Feature`. Templates (verbatim from Legacy,
  with `<name>` substituted):
  - `observable_viewmodel` — "Swift 6 @Observable ViewModel
    Template:": `@Observable @MainActor public final class
    <name>ViewModel` with `items`, `isLoading`, `errorMessage` and an
    async `loadData()`.
  - `async_stream` — "AsyncStream Template:": `public func
    make<name>Stream() -> AsyncStream<String>`.
  - `actor_service` — "Thread-Safe Actor Service Template:": `public
    actor <name>Service` with a `[String: Data]` cache and
    `store` / `retrieve` / `clear`.
  - `swiftui_glass_card` — "SwiftUI Glassmorphic Card Template:":
    `public struct <name>CardView: View` with a glassmorphic card
    layout.
  The tool only returns the template text; it injects nothing into any
  file (despite the description's "injects").
- Errors: an unknown id fails with `Unknown templateId '<id>'.
  Available: observable_viewmodel, async_stream, actor_service,
  swiftui_glass_card`. `keychain_helper` is listed in the schema
  description but has no case in Legacy's `switch`, so it fails with
  exactly that message — preserved, not fixed (§5).

### 2.14 `color_usage_audit`

- Description (verbatim): "Finds hardcoded colors in SwiftUI/UIKit
  code (Color(red:), UIColor literals, hex strings) that should live
  in the asset catalog."
- Input: `limit` (integer) — "Maximum findings. Default 100, max 500."
  No required parameters.
- Output: `count` (integer).
- Behaviour: scans Swift files line by line; a line whose trimmed form
  starts with `//` is skipped. Six patterns, in order; the first match
  per line wins:
  `Color\s*\(\s*red\s*:` → `Color(red:...)`,
  `UIColor\s*\(\s*red\s*:` → `UIColor(red:...)`,
  `NSColor\s*\(\s*red\s*:` → `NSColor(red:...)`,
  `"#[0-9A-Fa-f]{6}"|"#[0-9a-f]{3}"` → `hex literal`,
  `Color\s*\(\s*hex\s*:` → `Color(hex:)`,
  `UIColor\s*\(\s*hex\s*:` → `UIColor(hex:)`.
  `limit` is clamped to 1…500 (default 100) and caps the findings.
- Output text: no findings → `No hardcoded colors found — colors
  appear to use named assets.` Otherwise `Hardcoded colors (<n>[+]) —
  consider asset-catalog named colors:` with `- <rel>:<line> [<label>]`
  per finding. The `+` appears when the list reached the limit.
- Errors: none.

### 2.15 `colorset_builder`

- Description (verbatim): "Creates or updates adaptive Light/Dark
  mode colorsets in Xcode asset catalogs."
- Input: `catalogPath` (string, required) — "Relative path to the
  .xcassets directory."; `colorName` (string, required) — "Name of the
  color set (e.g. BrandPrimary, SurfaceElevated)."; `lightHex` (string,
  required) — "Hex color for Any/Light mode (e.g. #007AFF, #FFFFFF).";
  `darkHex` (string) — "Hex color for Dark mode (e.g. #0A84FF,
  #1C1C1E)." Writes: yes (`safeMutation`, approval-gated through
  `commit()` on `<catalog>/<colorName>.colorset/Contents.json`). No
  output schema (plain text result).
- Behaviour: `darkHex` defaults to `lightHex`. A hex colour is parsed
  by trimming whitespace, uppercasing, stripping a leading `#`, and —
  only when exactly 6 characters remain — scanning hex digits into
  `%.3f` sRGB components with alpha `1.000`; anything else (including
  3-digit hex) falls back to Legacy's `#007AFF` components (`0.000`,
  `0.478`, `1.000`, `1.000`). The written `Contents.json` is Legacy's
  verbatim template: a universal (Any/Light) colour plus a dark
  `luminosity` appearance, `srgb` colour-space, `info.author =
  xcode, version = 1`.
- Output text: `Successfully built adaptive ColorSet \`<colorName>\`
  at: <absolute colorset path>\n- Light: <lightHex>\n- Dark:
  <darkHex>`.
- Errors: a missing required parameter is caught by argument
  validation; a catalog path outside the workspace fails with `Path is
  outside the workspace: <catalogPath>`; a `colorName` containing `/`,
  `\`, `..` or a NUL byte fails with `Invalid colorName '<name>': must
  be a single color set name, not a path.` (Legacy would silently
  create nested directories for such a name; §5).

### 2.16 `icon_generator_tool`

- Description (verbatim): "Validates, configures, or scaffolds
  complete AppIcon.appiconset specifications in asset catalogs."
- Input: `catalogPath` (string, required) — "Relative path to the
  .xcassets directory."; `action` (string, required) — "Action:
  'validate' or 'scaffold'." Writes: yes (`safeMutation`) — the flag
  is static for the whole tool, so even the read-only `validate`
  action is refused on a read-only server (approval model §6.4
  reasoning: the server cannot know from the registration whether a
  particular call will write). No output schema (plain text result).
- Behaviour: the catalog path resolves inside the workspace
  (`resolveFileWritingPath`); outside fails with `Path is outside the
  workspace: <catalogPath>`. The icon set is
  `<catalog>/AppIcon.appiconset`.
  - `scaffold` (case-insensitive): writes Legacy's verbatim
    `Contents.json` template — one `universal`/`ios` 1024×1024 slot
    plus the ten `mac` slots (16/32/128/256/512 at 1× and 2×), `info`
    `author = xcode, version = 1` — through `commit()` (parents are
    created; an existing `Contents.json` is replaced silently, as
    Legacy does). Output text: `Successfully created universal
    AppIcon.appiconset at: <absolute icon-set path>`.
  - Any other `action` value validates, as in Legacy: `Contents.json`
    must exist and parse as JSON with an `images` array, else the call
    fails with `Contents.json not found or invalid in <absolute
    icon-set path>`. A slot counts as filled when it has a non-empty
    `filename` whose file exists; otherwise it counts as empty. Output
    text: `AppIcon.appiconset audit for \`<catalogPath>\`:\n- Total
    slots configured: <n>\n- Rendered assets present: <filled>\n-
    Empty/unassigned slots: <empty>`.
- Errors: missing required parameters are caught by argument
  validation; the validate failure above.

### 2.17 `stale_files_report`

- Description (verbatim): "Reports source files not modified in a long
  time, surfacing potentially abandoned or legacy code."
- Input: `days` (integer) — "Staleness threshold in days. Default
  180."; `limit` (integer) — "Maximum files to return. Default 50, max
  500." No required parameters.
- Output: `count` (integer, the TOTAL stale count, not the shown
  count); `days` (integer, present only when stale files exist).
- Behaviour: `days` is clamped to a minimum of 1 (default 180, no
  maximum); `limit` is clamped to 1…500 (default 50). Source
  extensions: `swift`, `m`, `mm`, `h`, `c`, `cpp`, `hpp`, `ts`, `js`,
  `py`, `rs`. A file is stale when its modification date is before
  `now − days × 86400s`. Stale files sort oldest-first; only the first
  `limit` are listed, but `count` is the total. Dates render with
  Legacy's `AssistWorkspacePaths.iso8601` (ISO 8601 with fractional
  seconds).
- Output text: no stale files → `No source files older than <days>
  days.` Otherwise `Stale source files (not modified in <days>+ days,
  <total> total):` with `- <path> — modified <iso8601>, <size> bytes`
  per shown file.
- Errors: none.

### 2.18 `change_impact_estimate`

- Description (verbatim): "Estimates the blast radius of changing a
  file: finds Swift files that reference its base symbol name."
- Input: `path` (string, required) — "Workspace-relative path of the
  file to change."; `limit` (integer) — "Maximum referencing files.
  Default 50."
- Output: `symbol` (string), `referencingFileCount` (integer),
  `blastRadius` (string, `LOW` / `MEDIUM` / `HIGH`).
- Behaviour: the symbol is the file's base name without its extension;
  an empty symbol fails with `Could not derive a symbol name from:
  <path>`. Referencing files are Swift files (other than the file
  itself, compared by standardized path) containing a line matching
  `(?<![\w.])<escaped symbol>\b` — a whole-word reference not preceded
  by a word character or a dot (so `GreeterTests` does not count as a
  reference to `Greeter`, and `foo.Greeter` does not either). The list
  caps at `limit` (clamped 1…500, default 50) and is sorted in the
  output. Blast radius: 0 files → `LOW`, 1–10 → `MEDIUM`, 11+ →
  `HIGH`. This is a textual heuristic, not a semantic reference search:
  it also matches the symbol in comments and strings.
- Output text: `Change impact estimate for <path> (symbol '<symbol>'):` /
  `- Blast radius: <level> — referenced by <n> file(s)` / `- <path>`
  per referencing file.
- Errors: a missing/blank `path` is caught by argument validation (or
  the handler's `Missing required parameter: path` backstop); a path
  outside the workspace fails with `Refusing to access path outside the
  workspace: <path>`.

### 2.19 `safe_undo`

- Description (verbatim): "Reverts the last modification made by the
  agent."
- Input: no properties. No output schema (it never succeeds).
  `potentiallyDestructive`, `writes: true`.
- Behaviour: honestly-failing (§4.2). Legacy lists workspace snapshots
  (`AssistSnapshotFunctions.listSnapshots`), requires at least two
  (current baseline + previous state), and restores `snapshots[1]`,
  failing with `At least two snapshots are required to undo (current
  baseline + previous state).` when there are fewer. SwiftCode's MCP host
  keeps no snapshots and `commit()` records no previous file content,
  so there is nothing to restore. The handler always throws naming
  that prerequisite. It must only ever undo changes the host itself
  made — and since the host records none, it undoes nothing.
- Errors: always — see §4.2 for the exact message.

### 2.20 `safe_validate_changes`

- Description (verbatim): "Verifies that the applied changes are
  correct and don't break functionality."
- Input: `path` (string) — "Workspace-relative file or directory to
  validate. Default: \".\"." No required parameters.
- Output: `issue_count` (integer, always present); `issues` (string,
  joined with `\n`, present only when there are issues).
- Behaviour: the path uses the clamping resolver (§3.3). A directory
  enumerates files up to 500 KB each (hidden files skipped, no
  extension filter, no skipped-directory rule); a single file
  validates on its own; a nonexistent path validates as one
  unreadable file. Per file, in order: unreadable as UTF-8 text →
  `<rel>: unreadable text file`; contains `<<<<<<<`, `>>>>>>>` or
  `=======` anywhere → `<rel>: merge conflict markers detected`
  (note: any `=======` line flags the file, including a Markdown
  divider — Legacy's check is that broad); does not end with `\n` →
  `<rel>: missing trailing newline` (an empty file therefore flags a
  missing trailing newline). A file can produce two issues.
- Output text: no issues → `Changes validated successfully`.
  Otherwise `Validation completed with <n> issue(s)`. Issues are a
  successful result, not a tool error.
- Errors: none.

### 2.21 `session_export`

- Description (verbatim): "Writes a markdown export with session
  metadata (title, timestamp, session ID, workspace, notes). Does not
  read conversation history. Refuses to overwrite unless overwrite is
  true."
- Input: `title` (string) — "Export title (optional)."; `notes`
  (string) — "Free-form notes to include (optional)."; `outputPath`
  (string) — "Workspace-relative output path. Default is
  .assist_session_export.md."; `overwrite` (string) — "Set to true to
  overwrite an existing output file. Default is false." No required
  parameters. Writes: yes (`safeMutation`, approval-gated through
  `commit()`).
- Output: `output_path` (string, absolute path), `output_relative`
  (string, as given / defaulted), `session_id` (string),
  `timestamp` (string).
- Behaviour: the output path defaults to `.assist_session_export.md`
  and uses Legacy's private `resolveInsideWorkspace`: trim, reject
  empty and any `..` component; a leading-`/` path must be the
  workspace root or under it; anything else appends to the root.
  `overwrite` is a STRING: only the (case-insensitive) value `"true"`
  overwrites — a JSON boolean is rejected by argument validation,
  exactly as Legacy's `as? String` cast would ignore it. An existing
  file without overwrite fails with `Refusing to overwrite existing
  file at '<outputRelative>'. Pass overwrite=true to replace it.` The
  title defaults to `Assist Session Export`; notes default to empty
  (rendered as `_No notes provided._`). The timestamp is a plain
  `ISO8601DateFormatter` (no fractional seconds — Legacy's form here,
  unlike `AssistWorkspacePaths.iso8601`). The session ID is a
  deterministic UUID derived from the workspace root path (SHA-256 of
  the path, first 16 bytes formatted as a UUID) — SwiftCode has no
  agent-session UUID (§5). The Markdown body is Legacy's verbatim
  shape: `# <title>`, `- Exported: <timestamp>`, `- Session ID:
  <uuid>`, `- Workspace: <absolute root path>`, a `## Tool Registry`
  section stating tool definitions live in `AssistToolRegistry` and
  the export contains session metadata only, and a `## Notes` section.
  The tool deliberately never reads conversation history.
- Output text: `Session export written to <outputRelative> (session
  <sessionId>).`
- Errors: an invalid output path fails with `Invalid outputPath:
  '<outputRelative>' must be a workspace-relative path without '..'
  and must stay inside the workspace.`; the overwrite refusal above.

### 2.22 `session_progress_report`

- Description (verbatim): "Summarizes the active agent session:
  engineering phases by status, failures, and the last agent-notes save
  time."
- Input: no properties.
- Output: `phaseCount`, `completed`, `inProgress`, `failed`,
  `pending` (all integers).
- Behaviour: degraded (§4.4). Legacy reads `AgentPhaseCoordinator`
  (phases with `completed` / `inProgress` / `failed` / `pending` /
  `skipped` statuses and per-phase failure lists) and
  `AgentNotesManager.lastSavedTimestamp`. SwiftCode has no phase
  coordinator, so all five counts are always 0 and the message always
  starts `No engineering phases are registered for this session.` The
  agent-notes line is real: it reports the modification time of the
  workspace's `agent_notes.md` (`Agent notes last saved: <iso8601 with
  fractional seconds>`) or `Agent notes: never saved this session.`
  when the file does not exist.
- Errors: none.

### 2.23 `tool_capability_lookup`

- Description (verbatim): "Looks up a registered tool's capability,
  risk level, description, and parameter schema from the live
  registry."
- Input: `toolId` (string, required) — "Registered tool id, e.g.
  repo_overview."
- Output: `toolId` (string, the resolved canonical id), `riskLevel`
  (string), `required` (string, required parameter names joined with
  `", "`, `""` when none).
- Behaviour: adapted (§4.5). The id is trimmed; a blank id fails with
  `Missing required parameter: toolId`. Aliases resolve first through
  `MCPServer.toolAliases`, as Legacy's `getTool` does. The tool is
  looked up in the live `server.tools` list — the SwiftCode registry — so
  it reports what is actually installed, including tools from other
  slices once the coordinator wires them in. The risk level is derived
  from the tool's annotations: `destructive` →
  `potentiallyDestructive`, `writes` → `safeMutation`, otherwise
  `safeRead`. SwiftCode tools carry no capability taxonomy and no cost
  model, so the capability and estimated-cost lines Legacy reports are
  omitted, not invented.
- Output text:
  `Tool: <id> — <title>` / `Risk level: <risk>` /
  `Read-only: <true|false>, Mutating: <true|false>` /
  `Description: <description>` /
  `Parameters: <sorted property names, or "(none)">` /
  `Required: <required names, or "(none)">`.
- Errors: an unknown id fails with `No registered tool with id
  '<toolId>'.` (the message uses the id as given, before alias
  resolution).

## 3. Shared rules

### 3.1 Approval gating

The seven writing tools (`automated_repair_engine`,
`colorset_builder`, `icon_generator_tool`, `markdown_toc_generate`,
`readme_generate`, `safe_undo`, `session_export`) are registered
`writes: true`. `MCPServer.run` refuses them on a read-only server
with `readOnlyMessage` before the handler runs. In `allow` mode the
approval is pre-granted; in `review` mode each change is presented as
an `MCPChange` and written only on acceptance, returning
`rejectedMessage` on refusal. Every writing handler goes through
`commit()` (one approval per changed file, in order, stopping at the
first refusal — the multi-file shape from the approval model §6.3 —
for `automated_repair_engine`, which can touch several files).
`safe_undo` is `potentiallyDestructive` (`destructive: true`); the
other six are `safeMutation` (`readOnly: false, idempotent: true`).
There is no Autopilot bypass, no second gate, and no per-tool flag
that can bypass `run()` (approval model §5). `icon_generator_tool`
is `writes: true` even for its read-only `validate` action: the flag
is static per tool, and the server cannot know from the registration
whether a particular call will write.

### 3.2 Workspace scans

`SearchWorkspace.files` / `swiftFiles` match Legacy's
`AssistWorkspaceScan` (hidden files skipped; top-level `.git`,
`.build`, `build`, `DerivedData`, `.swiftpm`, `Pods`, `Carthage`,
`node_modules`, `.venv` skipped). `SearchWorkspace.enumeratedFiles`
matches Legacy's `AssistToolingSupport.enumeratedFiles` (hidden files
skipped, no skipped-directory rule, files over the size cap dropped).
Scan results are in enumerator order unless the tool sorts them
(`api_surface_extract` sorts by path; `stale_files_report` sorts
oldest-first; `change_impact_estimate` sorts its output list).

### 3.3 Path resolution, per tool

| Tool | Resolver | Rule |
|---|---|---|
| `readme_generate`, `markdown_link_check`, `change_impact_estimate`, `automated_repair_engine`, `markdown_toc_generate` | Session-aware `resolveFileReadingPath` | Plain relative paths resolve against the session working directory; a leading `/` is workspace-root-relative unless it is really inside the workspace; `..` escaping the workspace is refused. The tool reports its own Legacy message on refusal (see §2). |
| `autonomous_review_engine`, `safe_validate_changes` | Clamping `resolveFileWritingClampedPath` | An escaping path silently becomes the workspace root, never an error; empty / `.` is the root. |
| `api_surface_extract` | Private `reviewDocsApiSurfaceScope` | Empty means the root; any `..` is refused; a leading-`/` path must be the root or under it. |
| `icon_generator_tool`, `colorset_builder` | Strict `resolveFileWritingPath` | Rejects empty paths, NUL bytes, a leading `~` and any `..`; relative paths resolve against the workspace root. |
| `session_export` | Private `reviewDocsSessionExportURL` | Legacy's `resolveInsideWorkspace` verbatim. |
| Read-only scans (`api_docs_coverage`, `api_endpoint_audit`, `color_usage_audit`, `readme_locate`, `repo_overview`, `stale_files_report`) | Workspace root | No path parameter; the whole workspace is scanned. |

No path is ever allowed to escape the workspace. Legacy's
`/tmp/swiftcode/scripts` carve-out is not kept (approval model §7.2),
and the blocked-path list is replaced by confinement (§7.3).

### 3.4 Text results vs structured results

Tools whose Legacy result carries no data (`docstring_generator`,
`code_snippet_manager`, `colorset_builder`, `icon_generator_tool`)
return a plain text result. All others return `.structured` with the
output schema of §2 (the summary is the first text block; the JSON
mirror is the second — tests must assert on `firstText`, never on
exact `resultText ==`).

## 4. Honestly-failing, degraded and adapted tools

### 4.1 `code_review` — honestly-failing (missing LLM prerequisite)

Legacy's `CodeReviewTool.execute` (in `CodeReview.swift`) loads the
`CodeReviewSystemAsset.md` system prompt, gathers the session
objective, completed actions, plan, tool-call history, repository
changes (snapshot diff) and build/diagnostic events, sends them to an
LLM — Apple Foundation Models when enabled, else the configured
provider via `LLMService` — and requires a JSON verdict whose `status`
is `task_ready` or `task_failed` (anything else is a contract error).
SwiftCode's MCP host has no LLM provider wired for this tool, so the
handler always throws:

> `code_review is unavailable: Legacy performs the review by sending
> the task history, repository changes and build state to an LLM
> (Apple Foundation Models or the configured provider) and requiring a
> JSON verdict with status task_ready or task_failed. SwiftCode's MCP host
> has no LLM provider wired for this tool, so no review is performed
> and nothing was verified.`

No review is faked. Wiring a provider is the prerequisite for a real
port; the session-history and snapshot-diff gathering Legacy does
would also need SwiftCode equivalents (there is no agent session loop and
no snapshot store in the host).

### 4.2 `safe_undo` — honestly-failing (missing snapshot store)

Legacy's `AssistUndoTool.execute` lists workspace snapshots via
`AssistSnapshotFunctions.listSnapshots()`, requires at least two, and
restores `snapshots[1]` (the state before the last modification).
SwiftCode's MCP host keeps no snapshots — `commit()` records no previous
file content, and `WorkspaceSession.noteFileEdited` records only a
path, not content — so there is nothing to restore. The handler always
throws:

> `safe_undo is unavailable: Legacy reverts the last modification by
> restoring the previous workspace snapshot (AssistSnapshotFunctions:
> at least two snapshots, restore snapshot[1]). SwiftCode's MCP host keeps
> no snapshots and commit() records no previous file content, so there
> is nothing to restore. Nothing was changed.`

The tool stays registered `potentiallyDestructive` / `writes: true`,
so a read-only server refuses it before the handler. A real port
needs a snapshot store (or per-change originals recorded at `commit()`
time) and a decision about scope: Legacy restores the whole workspace
to the previous snapshot, while the task's rule is that `safe_undo`
must only undo changes the host itself made via the approval gate.
Until that store exists, failing honestly is the correct behaviour.

### 4.3 `automated_repair_engine` — deterministic part only

Legacy's description promises validation "by rebuilding", but its
`execute()` never rebuilds: it only inserts the
`// AssistAutoRepair: review required` annotation above each reported
line. The port implements exactly what `execute()` does (annotation
only, approval-gated per file). No rebuild is performed or claimed.
A future enhancement could run a real build after annotating and
report the result, but that would be new behaviour, not a port.

### 4.4 `session_progress_report` — degraded (no phase coordinator)

SwiftCode has no equivalent of Legacy's `AgentPhaseCoordinator` or
`AgentNotesManager`. Phase counts are therefore always zero and the
message always starts `No engineering phases are registered for this
session.` The agent-notes line is real (modification time of the
workspace's `agent_notes.md`, or "never saved"). If a later wave adds
a phase model to the host, this tool should read it and the spec's
§2.22 must be updated; until then the tool must not invent phases.

### 4.5 `tool_capability_lookup` — adapted (no capability taxonomy)

SwiftCode tools have no `ToolCapability` and no `estimatedCost`. The
lookup reports what the live registry actually carries (id, title,
description, input parameters, required list, and the
annotations-derived risk level) and omits the capability and cost
lines. The structured `capability` key is likewise omitted rather
than filled with a placeholder value.

## 5. Deliberate deviations from Legacy

| Deviation | Reason |
|---|---|
| `code_review` / `safe_undo` honestly fail instead of running | Missing LLM provider / snapshot store (§4.1–4.2). Wave 2 `code_refactor` precedent. |
| `session_progress_report` always reports zero phases | No phase coordinator in SwiftCode (§4.4). |
| `tool_capability_lookup` omits capability and estimated cost | SwiftCode tools carry neither (§4.5). |
| `session_export` session ID is a deterministic UUID derived from the workspace root path | SwiftCode has no agent-session UUID. Stable per workspace. |
| `session_export` timestamp is a plain `ISO8601DateFormatter` (no fractional seconds) | That is Legacy's form in this tool; `stale_files_report` / `session_progress_report` use `AssistWorkspacePaths.iso8601` (with fractional seconds), as Legacy does. |
| `automated_repair_engine` performs no rebuild | Legacy's `execute()` never rebuilds either (§4.3). |
| `code_snippet_manager` has no `keychain_helper` template | Legacy's `switch` has no such case; only its schema description lists it. Preserved, not fixed. |
| `colorset_builder` rejects path-like `colorName` values | Legacy would silently create nested directories. Hardening; the error names the problem. |
| `icon_generator_tool` / `colorset_builder` resolve catalog paths inside the workspace | Legacy appended the path to the workspace root without a containment check, honouring absolute outside paths. SwiftCode confinement wins. |
| `session_export` `overwrite` keeps Legacy's string type (`"true"`) | A JSON boolean is rejected by argument validation, as Legacy's `as? String` cast would ignore it. |
| `docstring_generator` is `writes: false` | Legacy risk is `safeRead`; it returns text and writes nothing. |
| `api_endpoint_audit` empty case returns only `count` | Legacy's data shape is preserved exactly (the output schema lists all three keys as optional). |
| `safe_validate_changes` / `stale_files_report` omit the second data key when empty | Legacy's data shapes are preserved exactly (`issues` / `days` only when non-empty). |

## 6. Wiring (for the coordinator)

- Array: `reviewDocsTools` on `SwiftCodeMCPHost`
  (`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ReviewDocs.swift`), 23 tools in
  the §1 table order. Add `+ reviewDocsTools` to `installTools()` in
  `SwiftCodeTools.swift`.
- Writes: `automated_repair_engine`, `colorset_builder`,
  `icon_generator_tool`, `markdown_toc_generate`, `readme_generate`,
  `safe_undo`, `session_export` (`writes: true`; `safe_undo` is the
  only `destructive: true` one).
- Aliases to add to `MCPServer.toolAliases` (verified in Legacy's
  `AssistToolRegistry.toolAliases`): `docstring` →
  `docstring_generator`, `snippet` → `code_snippet_manager`,
  `icon_generator` → `icon_generator_tool`, `colorset` →
  `colorset_builder`. No other slice-D tool has a Legacy alias (the
  full alias table was checked). Note `search` → `search_text` is
  deliberately NOT an alias in SwiftCode (it would collide with SwiftCode's
  `search`); `tool_capability_lookup` resolves the aliases that do
  exist in `MCPServer.toolAliases`.
- Tests: `swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeReviewDocsTests.swift`
  (26 tests). No Swift toolchain exists in this environment, so `swift
  build` / `swift test` and live runs on Dylan's Mac are still
  pending; the implementation and tests were statically checked only
  (tool count, ID uniqueness, delimiter balance, no outstanding task
  markers, helper names prefixed `reviewDocs` with no collisions in
  `SwiftCodeMCP`).

## Evidence

| Claim | Level | Source |
|---|---|---|
| Tool IDs, titles, descriptions, schemas, risk levels, and the `code_review` registering class (`CodeReviewTool` in `CodeReview.swift`) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/` files listed above, read directly at `d51a8f0d` |
| `code_review` gathers session state and requires an LLM JSON verdict with status `task_ready` / `task_failed` | 1 | Legacy `Tools/CodeReview.swift` (`execute`, system-prompt load, LLM call, status check), read directly |
| `safe_undo` restores `snapshots[1]` and needs ≥ 2 snapshots | 1 | Legacy `Tools/AssistUndoTool.swift`, read directly |
| `automated_repair_engine` annotates lines, never rebuilds | 1 | Legacy `Tools/AssistAutomatedRepairEngine.swift` (`execute`, `parseDiagnostic`), read directly |
| `session_progress_report` reads `AgentPhaseCoordinator` + `AgentNotesManager.lastSavedTimestamp` | 1 | Legacy `Tools/AssistSessionProgressReportTool.swift`, read directly |
| `tool_capability_lookup` reports capability, risk, estimated cost from the live registry | 1 | Legacy `Tools/AssistToolCapabilityLookupTool.swift`, read directly |
| Aliases `docstring`, `snippet`, `icon_generator`, `colorset` | 1 | Legacy `AssistToolRegistry.swift` (`toolAliases`, lines 500, 502, 529, 530), read directly |
| Scan skip rules, `iso8601` with fractional seconds, `findPbxproj` | 1 | Legacy `Tools/AssistToolSharedHelpers.swift` (`AssistWorkspaceScan`, `AssistWorkspacePaths`), read directly |
| `commit()` / `approve()` gate, `MCPWritePolicy` modes, `readOnlyMessage`, `rejectedMessage`, unknown-argument rejection | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift`, `SwiftCodeTools+Content.swift` (`commit`), read directly |
| `resolveFileReadingPath` / `resolveFileWritingPath` / `resolveFileWritingClampedPath` semantics; `SearchWorkspace` scan rules | 1 | SwiftCode `SwiftCodeTools+FileReadingSupport.swift`, `SwiftCodeTools+FileWriting.swift`, `SwiftCodeTools+SearchSupport.swift`, read directly |
| No snapshot store, no phase coordinator, no LLM provider in SwiftCode's MCP host | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/` and `SwiftCodeIDECore/Session/WorkspaceSession.swift` (`noteFileEdited` records paths only), read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
