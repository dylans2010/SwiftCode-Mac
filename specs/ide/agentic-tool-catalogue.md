# Agentic tool catalogue — Wave 8

Ycode module: `YcodeMCP` (the MCP server and its tools).

This spec is the catalogue for the 141 Legacy Agentic tools ported in
Wave 8 from SwiftCode Legacy into Ycode. It is the single source of
truth for each tool's ID, Legacy class, disposition, description,
input schema, output shape, capability, risk level, permission, and
read/write classification. The companion spec `agentic-tools.md`
covers the behaviour shared by these tools: host conventions, the
approval gate, the error tables, the deviations from Legacy, the
collision resolutions, and the param-caveat register.

Scope: exactly these 141 tools, verified live from the Legacy Agentic
registry (`SwiftCode/Tools/Agentic/ListTools.swift`, 141 entries).
No tool may be invented, renamed, or merged with another.

Implementation: `ycode/Sources/YcodeMCP/YcodeTools+AgenticFiles.swift`
(`agenticFilesTools`, 6 tools), `YcodeTools+AgenticExecution.swift`
(`agenticExecutionTools`, 9 tools),
`YcodeTools+AgenticGit.swift` (`agenticGitTools`, 19 tools),
`YcodeTools+AgenticNetwork.swift` (`agenticNetworkTools`, 19 tools),
`YcodeTools+AgenticCLI.swift` (`agenticCLITools`, 21 tools),
`YcodeTools+AgenticCode.swift` (`agenticCodeTools`, 16 tools),
`YcodeTools+AgenticData.swift` (`agenticDataTools`, 19 tools),
`YcodeTools+AgenticPlanning.swift` (`agenticPlanningTools`, 8 tools).
117 tools are registered across those eight files. The other 24 are
not registered: 6 are exact-ID duplicates of already-registered
tools and 18 are already served through `MCPServer.toolAliases`.

## What the Agentic registry is (and is not)

The Agentic tools are a second, independent registry from the 291
Assist tools: `SwiftCode/Tools/Agentic/ListTools.swift` (141 entries,
`AgentTool` protocol, `static let identifier`) exposed via
`SwiftCode/Core/AI/Agent/AgentToolRegistry.swift`
(`schema()` / `execute(name:arguments:)`). The two registries share
names (`read_file`, `tree_view`, `git_cherry_pick`,
`swift_package_manager`, `take_screenshot`, `call_hierarchy`,
`dependency_graph`, …) but are different tools with different
schemas — migration scoping keeps them distinct, and this catalogue
classifies each Agentic tool against the already-ported MCP tools on
its own merits. The counts must never be conflated: 141 Agentic
tools here, 291 Assist tools in `assist-tool-catalogue.md`.

Three facts about the Agentic registry shape every disposition below:

- The `AgentTool` protocol declares only `name`, `description`,
  `schema`, and `execute(arguments:)`. It has **no capability, risk
  level, or permission** field. Capability / risk / permission in
  this catalogue are therefore the Ycode port's own derivation,
  following the Assist catalogue §1.2 rule (read-only → `safeRead` /
  `none`; file-writing → `safeMutation` / `fileSystem`; deleting →
  `potentiallyDestructive` in the target's annotations), not a
  Legacy declaration.
- The Agentic registry has **no aliases**: `AgentToolRegistry.execute`
  is an exact-name dictionary lookup. The Ycode aliases that serve
  Agentic IDs come from the *Assist* registry's alias table
  (`MCPServer.toolAliases`), not from anything Agentic. An Agentic
  caller using Agentic parameter names therefore does not
  automatically get the Assist-shaped tool — see the param-caveat
  register in `agentic-tools.md`.
- Agentic tools return plain strings in Legacy (no structured data
  map). Where the port returns structured data, the keys are the
  port's own; Legacy defines no data keys to keep verbatim.

## Conventions

### Result envelope

Every registered tool returns `MCPToolResult.structured(_:summary:)`,
which emits two text blocks: the structured data and a human-readable
summary. Message assertions must compare `TestSupport.firstText`,
never `resultText` with exact equality. Failure never returns partial
data. See `agentic-tools.md` for the full envelope and error style.

### How capability, risk, and permission are derived

Legacy Agentic tools declare none of these, so the port derives them
from behaviour, using the Assist catalogue §1.3 risk → annotation
table:

| Risk | Ycode `MCPToolAnnotations` | `writes` |
|---|---|---|
| `safeRead` | `readOnly: true, idempotent: true` | `false` |
| `safeMutation` | `readOnly: false, idempotent: true` | `true` |
| `potentiallyDestructive` | `readOnly: false, destructive: true` | `true` |
| `execution` | `readOnly: false, idempotent: false` | `false`, unless the run writes (`run_formatter`, `stop_running_process`, and the CLI runners are `writes: true`) |
| `externalSideEffect` | `readOnly: false, idempotent: false, openWorld: true` | `true` |

### Input schemas

Each tool section below transcribes its Legacy schema verbatim as a
JSON Schema code block: every property, its type, and the `required`
list, exactly as declared, plus the `workspace` parameter Wave 1 adds
to every Ycode tool. Where Legacy declares no per-property
description, none is transcribed; the short descriptions on Ycode
schema properties are Ycode additions. `additionalProperties` is
`false` on Ycode schemas: aliases pass arguments through unchanged,
so an Agentic argument unknown to the alias target is rejected by
validation before the handler runs.

### Dispositions

Exactly one disposition per tool:

- **PORTED** — registered as a new MCP tool in the Wave 8
  implementation (90 tools; 100 after Wave 10).
- **HONESTLY-FAILING** — registered, but the handler honestly fails
  with a named prerequisite; the prerequisite is given in the section
  (27 tools; 17 after Wave 10).
- **DUPLICATE-OF** — exact-ID duplicate of an already-registered
  tool; no second registration. The target ID is given in the
  section (6 tools).
- **ALREADY-SERVED** — a different ID already covers it via a
  `toolAliases` entry in `MCPServer.swift`. The alias target is
  given in the section, with whether the alias pre-existed or was
  added in Wave 8 (18 tools).

Counts: PORTED 100 + HONESTLY-FAILING 17 + DUPLICATE-OF 6 +
ALREADY-SERVED 18 = 141. (Wave 10: the 7 GitHub tools §§65–71 plus
git_pull/git_push/git_clone §§43–45 moved from HONESTLY-FAILING to
PORTED; see the Wave 10 notes in those sections.) Registered (PORTED + HONESTLY-FAILING) =
117, verified live by counting `tool("…")` calls in the eight
`YcodeTools+Agentic*.swift` files (Files 6, Execution 9, Git 19,
Network 19, CLI 21, Code 16, Data 19, Planning 8).

## Disposition summary

| # | ID | Legacy class | Disposition | Target / prerequisite |
|---|---|---|---|---|
| 1 | `read_file` | `ReadFileTool` | ALREADY-SERVED | `file_read` (alias, pre-existing) |
| 2 | `write_file` | `WriteFileTool` | ALREADY-SERVED | `file_write` (alias, pre-existing) |
| 3 | `edit_file` | `EditFileTool` | ALREADY-SERVED | `code_replace` (alias, pre-existing; param-incompatible — see §3) |
| 4 | `create_file` | `CreateFileTool` | ALREADY-SERVED | `file_create` (alias, pre-existing; overwrite behaviour delta — see §4) |
| 5 | `delete_file` | `DeleteFileTool` | ALREADY-SERVED | `file_delete` (alias, pre-existing) |
| 6 | `rename_file` | `RenameFileTool` | ALREADY-SERVED | `file_rename` (alias, pre-existing; param-incompatible — see §6) |
| 7 | `copy_file` | `CopyFileTool` | ALREADY-SERVED | `file_copy` (alias, pre-existing; param-incompatible — see §7) |
| 8 | `move_file` | `MoveFileTool` | ALREADY-SERVED | `file_move` (alias, pre-existing; param-incompatible — see §8) |
| 9 | `create_directory` | `CreateDirectoryTool` | ALREADY-SERVED | `dir_create` (alias, pre-existing) |
| 10 | `delete_directory` | `DeleteDirectoryTool` | ALREADY-SERVED | `dir_delete` (alias, pre-existing) |
| 11 | `tree_view` | `TreeViewTool` | DUPLICATE-OF | `tree_view` (registered Assist tool, same ID; param mismatch — see §11) |
| 12 | `read_multiple_files` | `ReadMultipleFilesTool` | PORTED | — |
| 13 | `list_directory` | `ListDirectoryTool` | ALREADY-SERVED | `dir_read` (alias, added in Wave 8) |
| 14 | `search_files` | `SearchFilesTool` | PORTED | — |
| 15 | `find_text` | `FindTextTool` | PORTED | — |
| 16 | `replace_text` | `ReplaceTextTool` | PORTED | — |
| 17 | `grep` | `GrepTool` | PORTED | — |
| 18 | `glob_search` | `GlobSearchTool` | PORTED | — |
| 19 | `execute_terminal_command` | `ExecuteTerminalCommandTool` | ALREADY-SERVED | `use_terminal` (alias, added in Wave 8) |
| 20 | `run_build` | `RunBuildTool` | ALREADY-SERVED | `project_build` (alias, pre-existing, Wave 7) |
| 21 | `run_tests` | `RunTestsTool` | ALREADY-SERVED | `project_test` (alias, pre-existing, Wave 7; param caveat — see §21) |
| 22 | `run_linter` | `RunLinterTool` | PORTED | — |
| 23 | `run_formatter` | `RunFormatterTool` | PORTED | — |
| 24 | `run_type_checker` | `RunTypeCheckerTool` | PORTED | — |
| 25 | `run_static_analysis` | `RunStaticAnalysisTool` | PORTED | — |
| 26 | `run_benchmark` | `RunBenchmarkTool` | PORTED | — |
| 27 | `run_application` | `RunApplicationTool` | PORTED | — |
| 28 | `stop_running_process` | `StopRunningProcessTool` | PORTED | — |
| 29 | `get_process_logs` | `GetProcessLogsTool` | HONESTLY-FAILING | Per-process log buffer (none exists) |
| 30 | `read_build_logs` | `ReadBuildLogsTool` | PORTED | — |
| 31 | `xcode_build` | `XcodeBuildTool` | ALREADY-SERVED | `project_build` (alias, added in Wave 8) |
| 32 | `swift_package_manager` | `SwiftPackageManagerTool` | DUPLICATE-OF | `swift_package_manager` (registered Wave 7 Assist tool, same ID; narrower surface — see §32) |
| 33 | `git_status` | `GitStatusTool` | PORTED | — |
| 34 | `git_diff` | `GitDiffTool` | PORTED | — |
| 35 | `git_add` | `GitAddTool` | PORTED | — |
| 36 | `git_commit` | `GitCommitTool` | PORTED | — |
| 37 | `git_checkout` | `GitCheckoutTool` | PORTED | — |
| 38 | `git_branch` | `GitBranchTool` | PORTED | — |
| 39 | `git_merge` | `GitMergeTool` | PORTED | — |
| 40 | `git_rebase` | `GitRebaseTool` | PORTED | — |
| 41 | `git_reset` | `GitResetTool` | PORTED | — |
| 42 | `git_stash` | `GitStashTool` | PORTED | — |
| 43 | `git_pull` | `GitPullTool` | PORTED | Wave 10: real `git pull`, approval-gated (see §43) |
| 44 | `git_push` | `GitPushTool` | PORTED | Wave 10: real `git push`, approval-gated (see §44) |
| 45 | `git_clone` | `GitCloneTool` | PORTED | Wave 10: real `git clone`, URL policy, approval-gated (see §45) |
| 46 | `git_blame` | `GitBlameTool` | PORTED | — |
| 47 | `git_log` | `GitLogTool` | PORTED | — |
| 48 | `git_show` | `GitShowTool` | PORTED | — |
| 49 | `git_tag` | `GitTagTool` | PORTED | — |
| 50 | `git_cherry_pick` | `GitCherryPickTool` | DUPLICATE-OF | `git_cherry_pick` (Wave 3 Assist tool, aligned in place to accept Agentic spellings — see §50) |
| 51 | `git_revert` | `GitRevertTool` | PORTED | — |
| 52 | `git_worktree` | `GitWorktreeTool` | PORTED | — |
| 53 | `fetch_url` | `FetchURLTool` | PORTED | — |
| 54 | `download_file` | `DownloadFileTool` | PORTED | — |
| 55 | `upload_file` | `UploadFileTool` | PORTED | — |
| 56 | `http_request` | `HTTPRequestTool` | PORTED | — |
| 57 | `web_search` | `WebSearchTool` | HONESTLY-FAILING | Web search provider (Legacy endpoint was a dead DuckDuckGo proxy) |
| 58 | `documentation_search` | `DocumentationSearchTool` | HONESTLY-FAILING | Documentation search backend (Legacy was a canned stub) |
| 59 | `api_reference_search` | `APIReferenceSearchTool` | HONESTLY-FAILING | Documentation search backend (Legacy was a canned stub) |
| 60 | `package_search` | `PackageSearchTool` | HONESTLY-FAILING | Package-index search backend (Legacy was a canned stub) |
| 61 | `dependency_audit` | `DependencyAuditTool` | HONESTLY-FAILING | Vulnerability/advisory data source (Legacy invented "No vulnerabilities found") |
| 62 | `install_dependencies` | `InstallDependenciesTool` | PORTED | — |
| 63 | `update_dependencies` | `UpdateDependenciesTool` | PORTED | — |
| 64 | `remove_dependencies` | `RemoveDependenciesTool` | PORTED | — |
| 65 | `create_pull_request` | `CreatePullRequestTool` | PORTED | Wave 10: real `POST /pulls` via YcodeGitHub (see §65) |
| 66 | `review_pull_request` | `ReviewPullRequestTool` | PORTED | Wave 10: real PR + reviews read via YcodeGitHub (see §66) |
| 67 | `read_pull_request` | `ReadPullRequestTool` | PORTED | Wave 10: real PR + files read via YcodeGitHub (see §67) |
| 68 | `read_issues` | `ReadIssuesTool` | PORTED | Wave 10: real `GET /issues` via YcodeGitHub (see §68) |
| 69 | `create_issue` | `CreateIssueTool` | PORTED | Wave 10: real `POST /issues` via YcodeGitHub (see §69) |
| 70 | `update_issue` | `UpdateIssueTool` | PORTED | Wave 10: real `PATCH /issues` via YcodeGitHub (see §70) |
| 71 | `search_issues` | `SearchIssuesTool` | PORTED | Wave 10: real `GET /search/issues` via YcodeGitHub (see §71) |
| 72 | `cocoapods` | `CocoaPodsTool` | PORTED | — |
| 73 | `carthage` | `CarthageTool` | PORTED | — |
| 74 | `android_build` | `AndroidBuildTool` | PORTED | — |
| 75 | `gradle` | `GradleTool` | PORTED | — |
| 76 | `npm` | `NpmTool` | PORTED | — |
| 77 | `pnpm` | `PnpmTool` | PORTED | — |
| 78 | `yarn` | `YarnTool` | PORTED | — |
| 79 | `bun` | `BunTool` | PORTED | — |
| 80 | `cargo` | `CargoTool` | PORTED | — |
| 81 | `go_build` | `GoBuildTool` | PORTED | — |
| 82 | `python_pip` | `PythonPipTool` | PORTED | — |
| 83 | `java_maven` | `JavaMavenTool` | PORTED | — |
| 84 | `dotnet_cli` | `DotNetCLITool` | PORTED | — |
| 85 | `flutter` | `FlutterTool` | PORTED | — |
| 86 | `react_native` | `ReactNativeTool` | PORTED | — |
| 87 | `expo` | `ExpoTool` | PORTED | — |
| 88 | `docker_build` | `DockerBuildTool` | PORTED | — |
| 89 | `docker_run` | `DockerRunTool` | PORTED | — |
| 90 | `docker_compose` | `DockerComposeTool` | PORTED | — |
| 91 | `kubernetes_apply` | `KubernetesApplyTool` | PORTED | — |
| 92 | `view_container_logs` | `ViewContainerLogsTool` | PORTED | — |
| 93 | `call_hierarchy` | `CallHierarchyTool` | DUPLICATE-OF | `call_hierarchy` (registered Wave 3 tool, same ID; param caveat — see §93) |
| 94 | `dependency_graph` | `DependencyGraphTool` | DUPLICATE-OF | `dependency_graph` (registered Wave 3 tool, same ID; param caveat — see §94) |
| 95 | `semantic_code_search` | `SemanticCodeSearchTool` | ALREADY-SERVED | `semantic_query_engine` (alias, added in Wave 8) |
| 96 | `cross_reference_search` | `CrossReferenceSearchTool` | ALREADY-SERVED | `symbol_reference_graph` (alias, added in Wave 8) |
| 97 | `generate_code` | `GenerateCodeTool` | HONESTLY-FAILING | LLM provider (Legacy returned a canned stub) |
| 98 | `refactor_code` | `RefactorCodeTool` | HONESTLY-FAILING | LLM provider (Legacy returned the input unchanged with a comment) |
| 99 | `review_code` | `ReviewCodeTool` | HONESTLY-FAILING | LLM provider (Legacy returned canned "Review comments: LGTM!") |
| 100 | `fix_bugs` | `FixBugsTool` | HONESTLY-FAILING | LLM provider (Legacy returned the input unchanged with a comment) |
| 101 | `generate_unit_tests` | `GenerateUnitTestsTool` | HONESTLY-FAILING | LLM provider (Legacy returned a canned empty XCTestCase stub) |
| 102 | `generate_integration_tests` | `GenerateIntegrationTestsTool` | HONESTLY-FAILING | LLM provider (Legacy returned a canned empty XCTestCase stub) |
| 103 | `generate_documentation` | `GenerateDocumentationTool` | HONESTLY-FAILING | LLM provider (Legacy returned a canned doc line) |
| 104 | `generate_comments` | `GenerateCommentsTool` | HONESTLY-FAILING | LLM provider (Legacy returned a canned comment line) |
| 105 | `detect_bugs` | `DetectBugsTool` | PORTED | — |
| 106 | `explain_code` | `ExplainCodeTool` | PORTED | — |
| 107 | `code_analysis` | `CodeAnalysisTool` | PORTED | — |
| 108 | `code_index` | `CodeIndexTool` | PORTED | — |
| 109 | `project_indexing` | `ProjectIndexingTool` | PORTED | — |
| 110 | `security_scan` | `SecurityScanTool` | PORTED | — |
| 111 | `license_scan` | `LicenseScanTool` | PORTED | — |
| 112 | `project_audit` | `ProjectAuditTool` | PORTED | — |
| 113 | `parse_json` | `ParseJSONTool` | PORTED | — |
| 114 | `parse_yaml` | `ParseYAMLTool` | PORTED | — |
| 115 | `parse_xml` | `ParseXMLTool` | PORTED | — |
| 116 | `parse_markdown` | `ParseMarkdownTool` | PORTED | — |
| 117 | `sql_query` | `SQLQueryTool` | PORTED | — |
| 118 | `database_schema_inspector` | `DatabaseSchemaInspectorTool` | PORTED | — |
| 119 | `database_migration` | `DatabaseMigrationTool` | PORTED | — |
| 120 | `read_environment_variables` | `ReadEnvironmentVariablesTool` | PORTED | — |
| 121 | `update_environment_variables` | `UpdateEnvironmentVariablesTool` | PORTED | — |
| 122 | `manage_secrets` | `ManageSecretsTool` | PORTED | — |
| 123 | `open_browser` | `OpenBrowserTool` | PORTED | — |
| 124 | `browser_automation` | `BrowserAutomationTool` | HONESTLY-FAILING | Browser automation driver (WebDriver / Playwright session) |
| 125 | `ui_inspector` | `UIInspectorTool` | HONESTLY-FAILING | Live target application with accessibility access |
| 126 | `accessibility_inspector` | `AccessibilityInspectorTool` | HONESTLY-FAILING | Live target application + accessibility permission |
| 127 | `performance_profiler` | `PerformanceProfilerTool` | PORTED | — |
| 128 | `memory_profiler` | `MemoryProfilerTool` | PORTED | — |
| 129 | `network_inspector` | `NetworkInspectorTool` | PORTED | — |
| 130 | `crash_analyzer` | `CrashAnalyzerTool` | PORTED | — |
| 131 | `symbolicate_crash_logs` | `SymbolicateCrashLogsTool` | PORTED | — |
| 132 | `take_screenshot` | `TakeScreenshotTool` | DUPLICATE-OF | `take_screenshot` (registered Wave 4 tool, same ID; param delta — see §132) |
| 133 | `ai_context_memory` | `AIContextMemoryTool` | PORTED | — |
| 134 | `task_planner` | `TaskPlannerTool` | PORTED | — |
| 135 | `todo_manager` | `TodoManagerTool` | PORTED | — |
| 136 | `progress_tracker` | `ProgressTrackerTool` | PORTED | — |
| 137 | `checkpoint_creator` | `CheckpointCreatorTool` | PORTED | — |
| 138 | `rollback_changes` | `RollbackChangesTool` | PORTED | — |
| 139 | `ask_user` | (class name not recorded in the source material; source file `AskUser.swift`) | ALREADY-SERVED | `plan-AskUser` (alias, pre-existing; param-incompatible — see §139) |
| 140 | `questions_handle` | `QuestionHandlerTool` | PORTED | — |
| 141 | `checklist_plan` | `ChecklistPlanTool` | PORTED | — |

## 1. `read_file` — Read File

- **Legacy class:** `ReadFileTool`.
- **Disposition:** ALREADY-SERVED → `file_read` (alias, pre-existing in `MCPServer.toolAliases`, carried over from the Assist registry in Waves 1–2). No code was written for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice (the slice table records class, disposition, and parameters only).
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** as the target (`readOnly: true, idempotent: true`). **`writes`:** `false`.
- **Parameters (Agentic, from the slice table):** `path` (string, required). Target `file_read` params: `path`, `startLine`, `lineCount`, `lines`. Param-compatible: yes — `path` is the target's `path`.

**Output (success).** As the target `file_read` returns it.

## 2. `write_file` — Write File

- **Legacy class:** `WriteFileTool`.
- **Disposition:** ALREADY-SERVED → `file_write` (alias, pre-existing). No code was written for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `path` (string, required), `content` (string, required). Target `file_write` params: `path`, `content`. Param-compatible: yes.

**Output (success).** As the target `file_write` returns it.

## 3. `edit_file` — Edit File

- **Legacy class:** `EditFileTool`.
- **Disposition:** ALREADY-SERVED → `code_replace` (alias, pre-existing). No code was written for this ID in Wave 8. The alias is left exactly as Waves 1–2 registered it; see the caveat below and the param-caveat register in `agentic-tools.md`.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `path` (string, required), `edits[]` (array of `{search, replace}` pairs, required). Target `code_replace` params: `path`, `target`, `replacement`, `allowMultiple`. Param-compatible: **no**.

**Caveat.** The Agentic tool takes one `path` plus an `edits` array and replaces **all** occurrences of each pair. The alias target `code_replace` takes a single `target` / `replacement` pair and fails on a missing or multi-occurring target unless `allowMultiple` is set. An Agentic-schema `edit_file` call fails argument validation (unknown `edits` key). The nearest ported behaviour for a multi-edit is `code_multi_edit`, whose `edits` array carries a per-edit `path` plus `content` or `search` + `replace` — a different shape again, so it is not an alias target either.

## 4. `create_file` — Create File

- **Legacy class:** `CreateFileTool`.
- **Disposition:** ALREADY-SERVED → `file_create` (alias, pre-existing). No code was written for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `path` (string, required), `content` (string, optional). Target `file_create` params: `path`, `content`, `overwrite`. Param-compatible: yes, with a behaviour delta (below).

**Behaviour delta.** Params are compatible, but the behaviour differs on an existing file: Agentic `create_file` overwrites unconditionally (`content.write(to:atomically:)`), while `file_create` refuses an existing file unless `overwrite=true`. An Agentic caller that relied on silent overwrite gets a refusal instead.

## 5. `delete_file` — Delete File

- **Legacy class:** `DeleteFileTool`.
- **Disposition:** ALREADY-SERVED → `file_delete` (alias, pre-existing). No code was written for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `potentiallyDestructive`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `path` (string, required). Target `file_delete` params: `path`. Param-compatible: yes.

**Output (success).** As the target `file_delete` returns it.

## 6. `rename_file` — Rename File

- **Legacy class:** `RenameFileTool`.
- **Disposition:** ALREADY-SERVED → `file_rename` (alias, pre-existing). No code was written for this ID in Wave 8. See the caveat below and the param-caveat register in `agentic-tools.md`.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `oldPath` (string, required), `newPath` (string, required). Target `file_rename` params: `oldPath`, `newName`. Param-compatible: **no**.

**Caveat.** Agentic renames a file **or directory** to an arbitrary `newPath` (a `moveItem`, i.e. it can also move across directories). The alias target `file_rename` takes `newName`, a single path component within the same directory, and rejects anything else. An Agentic-schema call fails validation (unknown `newPath` key).

## 7. `copy_file` — Copy File

- **Legacy class:** `CopyFileTool`.
- **Disposition:** ALREADY-SERVED → `file_copy` (alias, pre-existing). No code was written for this ID in Wave 8. See the caveat below and the param-caveat register in `agentic-tools.md`.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `sourcePath` (string, required), `destinationPath` (string, required). Target `file_copy` params: `source`, `destination`. Param-compatible: **no**.

**Caveat.** Agentic takes `sourcePath` / `destinationPath`; the alias target takes `source` / `destination`. An Agentic-schema call fails validation (unknown keys). The same name denotes two different schemas in the two Legacy registries, and one Ycode alias can only point one way — it currently points at the Assist shape.

## 8. `move_file` — Move File

- **Legacy class:** `MoveFileTool`.
- **Disposition:** ALREADY-SERVED → `file_move` (alias, pre-existing). No code was written for this ID in Wave 8. See the caveat below and the param-caveat register in `agentic-tools.md`.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `sourcePath` (string, required), `destinationPath` (string, required). Target `file_move` params: `source`, `destination`. Param-compatible: **no**.

**Caveat.** As §7: Agentic takes `sourcePath` / `destinationPath`; the alias target takes `source` / `destination`. An Agentic-schema call fails validation (unknown keys).

## 9. `create_directory` — Create Directory

- **Legacy class:** `CreateDirectoryTool`.
- **Disposition:** ALREADY-SERVED → `dir_create` (alias, pre-existing). No code was written for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `path` (string, required). Target `dir_create` params: `path`. Param-compatible: yes.

**Output (success).** As the target `dir_create` returns it.

## 10. `delete_directory` — Delete Directory

- **Legacy class:** `DeleteDirectoryTool`.
- **Disposition:** ALREADY-SERVED → `dir_delete` (alias, pre-existing). No code was written for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `fileModification`. **Risk:** `potentiallyDestructive`. **Required permission:** `fileSystem`. **MCP annotations:** as the target. **`writes`:** `true`.
- **Parameters (Agentic, from the slice table):** `path` (string, required). Target `dir_delete` params: `path`. Param-compatible: yes.

**Output (success).** As the target `dir_delete` returns it.

## 11. `tree_view` — Tree View

- **Legacy class:** `TreeViewTool`.
- **Disposition:** DUPLICATE-OF `tree_view` — the ID is already a registered MCP tool (the Assist `tree_view` port), so no second registration exists. The Agentic tool is served by that one registration, with the param mismatch below.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** as the registered tool (`readOnly: true, idempotent: true`). **`writes`:** `false`.
- **Parameters (Agentic, from the slice table):** `directory` (string, required), `depth` (optional, default 2). Registered `tree_view` params: `path?`, `maxDepth?` (default depth 3, emoji rendering). Param-compatible: **no**.

**Caveat.** The Agentic tool takes a required `directory` plus `depth` (default 2) and renders via `/usr/bin/tree` with a manual fallback. An Agentic-schema call fails validation (unknown `directory` key). Recorded in the param-caveat register in `agentic-tools.md`.

## 12. `read_multiple_files` — Read Multiple Files

- **Legacy class:** `ReadMultipleFilesTool`.
- **Disposition:** PORTED as `read_multiple_files` in `YcodeTools+AgenticFiles.swift` (`agenticFilesTools`).
- **Description (verbatim):** "Reads the content of multiple files."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{ "type": "object",
  "properties": { "paths": { "type": "array", "items": { "type": "string" } } },
  "required": ["paths"] }
```

**Output (success).** Reads each path as UTF-8, in request order. Structured data key `files` is an array of `{path, content}` objects in request order; the summary is Legacy's exact per-file block shape, `--- FILE: <path> ---\n<content>\n\n`, concatenated.

**Notes.** Deliberate deviation: Legacy stored the results in a dictionary, so its blocks came out in nondeterministic order; the port is deterministic instead. No caller could depend on Legacy's order. A file that cannot be read fails the whole call (`Failed to read file at <path>: <reason>`), as in Legacy (its `run` throws on the first unreadable path). Paths resolve with `resolveFileReadingPath` (leading `/` is workspace-root-relative, anything else is relative to the session working directory `dir_cd` sets, `..` past the workspace root is an error, never a clamp); Legacy took raw filesystem paths with no confinement. Results report workspace-relative paths where Legacy reported absolute ones.

**Error cases.** A missing `paths` fails with the server's `missing the required argument "paths"`; a non-string or empty entry fails with `paths[<index>] must be a non-empty string path.`; an unreadable file fails with `Failed to read file at <path>: <reason>`; a path outside the workspace fails with the resolver's `<path> is outside the workspace folder <root>`.

## 13. `list_directory` — List Directory

- **Legacy class:** `ListDirectoryTool`.
- **Disposition:** ALREADY-SERVED → `dir_read` (alias, **added in Wave 8** to `MCPServer.toolAliases`). No tool was registered for this ID in Wave 8.
- **Description (verbatim):** not recorded in the source material for this slice.
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** as the target (`readOnly: true, idempotent: true`). **`writes`:** `false`.
- **Parameters (Agentic):** `path` (string, required). Target `dir_read` required params: `{path}`, same name and type (string). Param-compatible: yes.

**Output delta (recorded).** `dir_read` returns sorted entries with a trailing `/` on directories plus structured `contents` / `count` / `path`, while Agentic `list_directory` returns FileManager order, raw names joined with `\n`, no markers.

## 14. `search_files` — Search Files

- **Legacy class:** `SearchFilesTool`.
- **Disposition:** PORTED as `search_files` in `YcodeTools+AgenticFiles.swift`.
- **Description (verbatim):** "Searches for files matching a pattern in a directory."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{ "type": "object",
  "properties": { "directory": { "type": "string" }, "pattern": { "type": "string" } },
  "required": ["directory", "pattern"] }
```

**Output (success).** Recursive enumeration under `directory` (hidden files skipped, regular files only), keeping files whose last path component contains `pattern` — a case-sensitive substring match, exactly as Legacy implements it (`lastPathComponent.contains(pattern)`). Results are workspace-relative paths, sorted. Data keys: `files` (the sorted paths), `count`. No matches is a success with an empty list. Summary: `Found <n> file(s) matching '<pattern>' in <directory>.` or `No files matching '<pattern>' found in <directory>.`

**Notes.** Why not an alias of `file_list`: `file_list` takes `glob` + `limit` over the workspace, not `directory` + `pattern`; params incompatible, so no alias is possible. Deliberate deviation: a missing directory (or a path that is not a directory) fails with `Directory not found: <directory>` / `Not a directory: <directory>`. Legacy's enumerator returns `nil` for a missing directory, so Legacy silently returned an empty result; the port fails explicitly, matching the Wave 3 convention for directory-scoped tools.

## 15. `find_text` — Find Text

- **Legacy class:** `FindTextTool`.
- **Disposition:** PORTED as `find_text` in `YcodeTools+AgenticFiles.swift`.
- **Description (verbatim):** "Searches for text in a directory."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{ "type": "object",
  "properties": { "directory": { "type": "string" }, "text": { "type": "string" } },
  "required": ["directory", "text"] }
```

**Output (success).** Recursive enumeration under `directory` (hidden files skipped, regular files only); every file that decodes as UTF-8 is scanned line by line (1-based). A line matches when it contains `text` (`line.contains(text)`), **case-sensitive** — unlike `search_text`, which is case-insensitive. A file's matching line numbers are reported as `<rel>: 1, 2, 3`, one line per file, sorted by path. Data key: `results` (the joined lines, empty string when nothing matches). Summary: `Text search results for '<text>' in <directory>:` or `No matches found.` when empty (Legacy's exact no-match message).

**Notes.** Why not an alias of `search_text`: `search_text` takes a single `pattern`, is workspace-wide and case-insensitive; params incompatible, so no alias is possible. There is no file-size cap, as in Legacy; files that do not decode as UTF-8 are silently skipped, as in Legacy (`try? String(contentsOf:)`). An empty `text` matches every line, as in Legacy (`line.contains("")` is true) — Legacy behaviour, preserved, not a bug fixed silently. A missing directory fails with `Directory not found: <directory>` (see §14).

## 16. `replace_text` — Replace Text

- **Legacy class:** `ReplaceTextTool`.
- **Disposition:** PORTED as `replace_text` in `YcodeTools+AgenticFiles.swift`.
- **Description (verbatim):** "Replaces text in a file."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `commit()` (full before/after text shown to the reviewer) **before** the file is written; `MCPServer.run` already refuses `writes: true` tools when the server is read-only. There is no Autopilot bypass.

```json
{ "type": "object",
  "properties": { "path": { "type": "string" }, "target": { "type": "string" },
                  "replacement": { "type": "string" } },
  "required": ["path", "target", "replacement"] }
```

**Output (success).** Reads the file as UTF-8, replaces **every** occurrence of `target` with `replacement` (literal, not a regular expression: `replacingOccurrences`), and writes the result through `commit()`. Data keys: `path` (as supplied), `replacementCount` (the non-overlapping literal occurrence count). Summary (Legacy's exact message): `Successfully replaced text in <path>`.

**Notes.** Why not an alias of `code_replace`: `code_replace` fails on a missing or multi-occurring target unless `allowMultiple` is set; params are compatible but behaviour is not the same, and an alias cannot inject `allowMultiple: true`. Ported as distinct. Deliberate deviations, both recorded in the implementation header: an absent target succeeds with `replacementCount` 0 and **no** write and no approval round-trip (Legacy rewrote the identical file and reported success; the port reports the same success without a pointless write); an empty target is rejected with `Target must not be empty.` (Legacy would have inserted the replacement between every character — a safety rejection, not Legacy behaviour).

**Error cases.** A missing file fails with `Failed to read file at <path>: <reason>`; a path outside the workspace fails with the resolver's outside-workspace error; an approval refusal fails with the server's rejection message and the file is left unchanged; a read-only server refuses before the handler runs.

## 17. `grep` — Grep

- **Legacy class:** `GrepTool`.
- **Disposition:** PORTED as `grep` in `YcodeTools+AgenticFiles.swift`.
- **Description (verbatim):** "Searches for a pattern in a directory using grep."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{ "type": "object",
  "properties": { "pattern": { "type": "string" }, "directory": { "type": "string" } },
  "required": ["pattern", "directory"] }
```

**Output (success).** Directory-scoped regular-expression search. The pattern is compiled once as a **case-sensitive** `NSRegularExpression` (the `/usr/bin/grep` default) and matched per line (`firstMatch` per line; a line with several matches is reported once). Each matching line is reported as `<rel>:<line>: <text>`, sorted by path. Data key: `results` (the matching lines joined with `\n`, empty string when nothing matches). Summary: `Grep search completed for '<pattern>'` (mirroring `search_regex`'s message shape).

**Notes.** Why not an alias of `search_regex`: `search_regex` takes a single `pattern` over the workspace; params incompatible (`directory` is unknown to it), so no alias is possible. Deliberate deviation: Legacy spawned `/usr/bin/grep -r -n`. The port implements the search natively — no subprocess — and its scan mirrors the Wave 3 `search_regex` scan: hidden files skipped, files over 1 MB skipped, binary-extension files skipped, files that do not decode as UTF-8 skipped. Legacy's grep would also report binary files ("Binary file … matches") and descend into hidden directories; the port does neither.

**Error cases.** A missing `pattern` / `directory` fails with the server's missing-argument error; an invalid pattern fails with `Regex search failed: <error>` (mirroring `search_regex`) — the compilation error is reported, never a partial result; a missing directory fails with `Directory not found: <directory>` (see §14).

## 18. `glob_search` — Glob Search

- **Legacy class:** `GlobSearchTool`.
- **Disposition:** PORTED as `glob_search` in `YcodeTools+AgenticFiles.swift`.
- **Description (verbatim):** "Searches for files matching a glob pattern."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{ "type": "object",
  "properties": { "pattern": { "type": "string" } },
  "required": ["pattern"] }
```

**Output (success).** Glob file search over the workspace. The pattern is matched with `fnmatch` against the **file name only** — Legacy's `find -name` semantics — so a pattern containing `/` (e.g. `Sources/*.swift`) matches nothing. Results are workspace-relative paths, sorted. Data keys: `files` (the sorted paths), `count`. No matches is a success with an empty list. Summary: `Found <n> file(s) matching '<pattern>'.` or `No files matching '<pattern>' found.`

**Notes.** Why not an alias of `file_list`: `file_list` takes `glob`, not `pattern`, and globs the relative path (or basename when the pattern has no `/`); params incompatible, so no alias is possible. Deliberate deviations: Legacy ran `/usr/bin/find . -name <pattern>` from the process working directory — unscoped and cwd-dependent. The port scopes to the workspace root and implements the match natively with `fnmatch` (no subprocess). Hidden files and the top-level skipped directories (`.git`, `.build`, …) are pruned, as in the other ported search tools; `find` would have walked them.

## 19. `execute_terminal_command` — Execute Terminal Command

- **Legacy class:** `ExecuteTerminalCommandTool`.
- **Disposition:** ALREADY-SERVED → `use_terminal` (alias, **added in Wave 8** to `MCPServer.toolAliases`). No tool was registered for this ID in Wave 8.
- **Description (verbatim):** "Executes a terminal command in a given working directory."
- **Capability:** `systemExecution`. **Risk:** `execution`. **Required permission:** terminal execution (approval gate on every run; no Autopilot bypass). **MCP annotations:** as the target. **`writes`:** as the target.

```json
{"type": "object",
 "properties": {"command": {"type": "string"},
                "workingDirectory": {"type": "string"}},
 "required": ["command"]}
```

**Notes.** Legacy behaviour: runs `/bin/sh -c <command>` via `ProcessRunnerTool` in the given working directory; returns stdout on exit 0, otherwise `"Command failed with exit code <code>\n\nSTDOUT: …\n\nSTDERR: …"`. Param-compatibility: required `{command}` is a subset of `use_terminal`'s params (`command`, `workingDirectory`, `explanation`, `estimatedImpact`, `modifiesRepo`); `workingDirectory` exists in both with the same name and type. Alias-valid. Deliberate deviation: Legacy ran a real shell (`/bin/sh -c`). The port must NOT reintroduce shell execution: `use_terminal` tokenizes the command into an argv vector and rejects shell metacharacters, so commands needing pipes, redirects, variables or globbing must be split into separate tool calls. This matches Wave 4's documented deviation for `use_terminal` itself.

## 20. `run_build` — Run Build

- **Legacy class:** `RunBuildTool`.
- **Disposition:** ALREADY-SERVED → `project_build` (alias, pre-existing, added Wave 7). No code was written for this ID in Wave 8.
- **Description (verbatim):** "Runs the build command for a Swift project."
- **Capability:** `compilation`. **Risk:** `execution`. **MCP annotations:** as the target.

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"}},
 "required": ["projectPath"]}
```

**Notes.** Legacy behaviour: runs `/usr/bin/swift build` in `projectPath`; returns stdout + stderr. Param-compatibility: required `{projectPath}` is a param of `project_build` (same name and type). Alias-valid. Behaviour note: the port runs the session build (`s.build(.build)`), not `swift build` directly, and `projectPath` must name the open workspace (the Wave 7 `project_build` rule). For a nested SwiftPM package, use the ported `run_type_checker` (§24) instead.

## 21. `run_tests` — Run Tests

- **Legacy class:** `RunTestsTool`.
- **Disposition:** ALREADY-SERVED → `project_test` (alias, pre-existing, added Wave 7). No code was written for this ID in Wave 8. See the param caveat below and the param-caveat register in `agentic-tools.md`.
- **Description (verbatim):** "Runs the test command for a Swift project."
- **Capability:** `testing`. **Risk:** `execution`. **MCP annotations:** as the target.

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"}},
 "required": ["projectPath"]}
```

**Notes.** Legacy behaviour: runs `/usr/bin/swift test` in `projectPath`; returns stdout + stderr. **Param-compatibility caveat:** the Agentic tool requires `projectPath`, but `project_test` has NO `projectPath` parameter (its params are `scheme` and `testPlan`). Because aliases pass arguments through unchanged and `MCPServer.run` validates against the target's schema, a `run_tests` call carrying `projectPath` is rejected as an unknown argument; the alias only works when the caller omits `projectPath` (and then the project is the open workspace). The port runs the session test runner (`s.runTests()`), not `swift test` directly.

## 22. `run_linter` — Run Linter

- **Legacy class:** `RunLinterTool`.
- **Disposition:** PORTED as `run_linter` in `YcodeTools+AgenticExecution.swift` (`agenticExecutionTools`).
- **Description (verbatim):** "Runs a linter (SwiftLint) on a given path."
- **Capability:** `diagnostics`. **Risk:** `execution` (`readOnly: false, idempotent: false`, `writes: false` — a lint run modifies nothing).

```json
{"type": "object",
 "properties": {"path": {"type": "string"}},
 "required": ["path"]}
```

**Output (success).** Exit 0 → structured `exitCode` + `outputTail`; non-zero → failure with the exit code and tail.

**Notes.** Legacy behaviour: runs `/usr/bin/swiftlint lint <path>` with the path itself as the working directory; returns stdout + stderr. Why not an alias of `code_lint`: `code_lint` is a built-in heuristic lint (line length over 120 chars, task-marker comments) that never invokes SwiftLint. Same parameter shape (`path`), different behaviour — so it is ported as distinct, not aliased. Port behaviour: resolves `swiftlint` on `PATH` (Legacy's fixed `/usr/bin/swiftlint` is on `PATH`, so a Homebrew install works too) and runs `swiftlint lint <resolved-absolute-path>` as a fixed argv vector via `terminalRunFixed`, bounded at 300 s, in the path itself (directory) or its parent (file). SwiftLint absent → honest failure naming the missing binary and how to install it. Deviations: Legacy passed the raw `path` string with the path itself as the working directory (fails to launch when the path is a file); the port passes the resolved absolute path. Legacy waited unboundedly; the port bounds at 300 s.

## 23. `run_formatter` — Run Formatter

- **Legacy class:** `RunFormatterTool`.
- **Disposition:** PORTED as `run_formatter` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Runs a formatter (SwiftFormat) on a given path."
- **Capability:** `fileModification`. **Risk:** `safeMutation` (`readOnly: false, idempotent: true`, `writes: true`). **Gate:** explicit `MCPChange` + `approve()` before running (in read-only mode the server refuses before the handler runs).

```json
{"type": "object",
 "properties": {"path": {"type": "string"}},
 "required": ["path"]}
```

**Output (success).** Exit 0 → structured `exitCode` + `outputTail`; non-zero → failure with the exit code and tail.

**Notes.** Legacy behaviour: runs `/usr/bin/swiftformat <path>` with the path itself as the working directory; returns stdout + stderr. Why not an alias of `code_format`: `code_format` applies Ycode's built-in `fileWritingSimpleFormat` and never invokes SwiftFormat. Same parameter shape (`path`), different behaviour — ported as distinct. Port behaviour: resolves `swiftformat` on `PATH` and runs `swiftformat <resolved-absolute-path>` as a fixed argv vector via `terminalRunFixed`, bounded at 300 s. This is a file mutation, so the tool is `writes: true` with `safeMutation` annotations. SwiftFormat absent → honest failure naming the missing binary. Deviations: same path-resolution and 300 s bound as `run_linter` (§22).

## 24. `run_type_checker` — Run Type Checker

- **Legacy class:** `RunTypeCheckerTool`.
- **Disposition:** PORTED as `run_type_checker` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Runs the Swift type checker on a project."
- **Capability:** `compilation`. **Risk:** `execution` (`readOnly: false, idempotent: false`, `writes: false`).

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"}},
 "required": ["projectPath"]}
```

**Output (success).** Exit 0 → structured `exitCode` + `outputTail`; non-zero → failure with the exit code and tail.

**Notes.** Legacy behaviour: runs `/usr/bin/swift build --build-tests` in `projectPath`; returns stdout + stderr. Why not an alias of `project_build`: `project_build` runs the session build for the scheme's build configuration; it has no build-tests action, so it cannot express "build including the test targets" (the type-check). Param shape matches (`projectPath`), behaviour does not. Port behaviour: resolves `projectPath` with `resolveFileReadingPath` (must be an existing directory inside the workspace; unlike `project_build` it need not be the open workspace itself, so a nested package works) and runs `swift build --build-tests` as a fixed argv vector via `terminalRunFixed`, bounded at 300 s. The session build seam was not used because it exposes no build-tests action — the only `--build-tests` use in `YcodeBuild` is inside the test runner, which also executes the tests. Swift toolchain absent → honest failure.

## 25. `run_static_analysis` — Run Static Analysis

- **Legacy class:** `RunStaticAnalysisTool`.
- **Disposition:** PORTED as `run_static_analysis` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Runs static analysis on a Swift project."
- **Capability:** `compilation`. **Risk:** `execution` (`readOnly: false, idempotent: false`, `writes: false`).

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"}},
 "required": ["projectPath"]}
```

**Output (success).** Exit 0 → structured `exitCode` + `outputTail`; non-zero → failure with the exit code and tail.

**Notes.** Legacy behaviour: runs `/usr/bin/swift build --build-tests -Xswiftc -analyze` in `projectPath`; returns stdout + stderr. Why not an alias: no ported tool runs the Swift compiler analyzer. The ported static-analysis tools are scanners/parsers over source or build output (`dead_code_scan`, `security_audit_scanner`, `compiler_diagnostics_engine` runs the session build and reports issues — it does not pass `-analyze`). Port behaviour: same seam as `run_type_checker` (§24), with argv `["build", "--build-tests", "-Xswiftc", "-analyze"]`, bounded at 300 s.

## 26. `run_benchmark` — Run Benchmark

- **Legacy class:** `RunBenchmarkTool`.
- **Disposition:** PORTED as `run_benchmark` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Runs benchmarks on a Swift project."
- **Capability:** `testing`. **Risk:** `execution` (`readOnly: false, idempotent: false`, `writes: false`).

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"}},
 "required": ["projectPath"]}
```

**Output (success).** Exit 0 → structured `exitCode` + `outputTail`; non-zero (e.g. no `benchmark` target) → failure with the exit code and tail.

**Notes.** Legacy behaviour: runs `/usr/bin/swift run -c release benchmark` in `projectPath`; returns stdout + stderr. Why not an alias of `performance_benchmark`: `performance_benchmark` runs an allow-listed command N times and reports timings; it has no `projectPath` parameter, so the Agentic tool's required `projectPath` is not a subset of its params and the alias would be rejected by argument validation. Different behaviour (runs the project's own `benchmark` executable target once, reports its output) and incompatible params — ported as distinct. Port behaviour: resolves `projectPath` as for `run_type_checker` (§24) and runs `swift run -c release benchmark` as a fixed argv vector via `terminalRunFixed`, bounded at 300 s.

## 27. `run_application` — Run Application

- **Legacy class:** `RunApplicationTool`.
- **Disposition:** PORTED as `run_application` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Runs a Swift application target."
- **Capability:** `systemExecution`. **Risk:** `execution` (`readOnly: false, idempotent: false`, `writes: false`).

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"},
                "target": {"type": "string"}},
 "required": ["projectPath", "target"]}
```

**Output (success).** Exit 0 → structured `exitCode` + `outputTail`; non-zero → failure with the exit code and tail (Legacy returned the combined output even on failure; the port reports it as a failure, like the other run tools).

**Notes.** Legacy behaviour: runs `/usr/bin/swift run <target>` in `projectPath`; returns stdout + stderr. Why not an alias of `run`: the `run` tool builds the scheme and runs its built product; it has neither a `projectPath` nor a `target` parameter, so the Agentic tool's required params are not a subset of its params and the alias would be rejected. Different behaviour (runs a named SwiftPM executable target via `swift run`) — ported as distinct. Port behaviour: validates `target` is a single bare name (no whitespace, no leading `-`, so it can never be reinterpreted as a `swift run` flag), resolves `projectPath` as for `run_type_checker` (§24), and runs `swift run <target>` as a fixed argv vector via `terminalRunFixed`, bounded at 300 s.

## 28. `stop_running_process` — Stop Running Process

- **Legacy class:** `StopRunningProcessTool`.
- **Disposition:** PORTED as `stop_running_process` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Stops a running process using its PID."
- **Capability:** `systemExecution`. **Risk:** `potentiallyDestructive` (`readOnly: false, destructive: true`, `writes: true`). **Gate:** explicit `MCPChange` + `approve()` (read-only mode refuses before the handler runs).

```json
{"type": "object",
 "properties": {"pid": {"type": "integer"}},
 "required": ["pid"]}
```

**Output (success).** Legacy's exact message: `"Process <pid> terminated."`

**Notes.** Legacy behaviour: calls `kill(pid, SIGTERM)` directly; returns `"Process <pid> terminated."`. Why not an alias of `stop`: the `stop` tool stops a host-managed run by `runId`; it has no `pid` parameter, so the Agentic tool's required `pid` is not a subset of its params and the alias would be rejected. Different behaviour (terminates an arbitrary OS process) — ported as distinct. Port behaviour: refuses PID ≤ 1 and Ycode's own PID, then gates through approval, then runs `/bin/kill -TERM <pid>` as a fixed argv vector (bounded at 30 s). A non-zero `kill` exit (e.g. no such process) is a failure carrying the exit code and `kill`'s message. Deviations: Legacy called `kill()` with no guard and no approval; the port adds both guards and the approval gate, and goes through `/bin/kill` instead of the C API so no Darwin/Glibc import is needed.

## 29. `get_process_logs` — Get Process Logs

- **Legacy class:** `GetProcessLogsTool`.
- **Disposition:** HONESTLY-FAILING — registered as `get_process_logs` with Legacy's full schema in `YcodeTools+AgenticExecution.swift`; the handler validates `pid`, then always fails. The placeholder is NOT reproduced: inventing log text would be fake behaviour.
- **Description (verbatim):** "Retrieves logs for a running process."
- **Capability:** `diagnostics`. **Risk:** `safeRead` (it would be a pure read if the store existed).

```json
{"type": "object",
 "properties": {"pid": {"type": "integer"}},
 "required": ["pid"]}
```

**Missing prerequisite (exact).** A per-process log buffer (stdout/stderr stored keyed by PID for processes the host started). Ycode's MCP host keeps run output keyed by run ID (`run_output`), never by PID, and tracks no child-process log store. The failure message names this.

**Notes.** Legacy behaviour: `run()` returns the placeholder string `"Log data for process <pid>"` — there is no real log source behind it (the file's own comment: "Implementation would normally retrieve from a log buffer").

## 30. `read_build_logs` — Read Build Logs

- **Legacy class:** `ReadBuildLogsTool`.
- **Disposition:** PORTED as `read_build_logs` in `YcodeTools+AgenticExecution.swift`.
- **Description (verbatim):** "Reads build logs from a project directory."
- **Capability:** `diagnostics`. **Risk:** `safeRead` (`.read` annotations, pure read).

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"}},
 "required": ["projectPath"]}
```

**Output (success).** Returns the file as plain text; over 8000 characters it returns the last 8000 with a truncation marker (Legacy returned the whole file).

**Notes.** Legacy behaviour: reads `<projectPath>/.build/build.log` as UTF-8 and returns it. Why not an alias: `build_log_analyze` needs a log-file `path`, not a `projectPath`; `build_log` reads the session's in-memory build log and likewise has no `projectPath`. The Agentic tool's required `projectPath` is not a param of either, so no alias is valid. Different behaviour (reads the SwiftPM `.build/build.log` file) — ported as distinct. Port behaviour: resolves `projectPath` as for `run_type_checker` (§24) and reads `.build/build.log` as UTF-8. Missing log → failure telling the caller to run a build first.

## 31. `xcode_build` — Xcode Build

- **Legacy class:** `XcodeBuildTool`.
- **Disposition:** ALREADY-SERVED → `project_build` (alias, **added in Wave 8** to `MCPServer.toolAliases`). No tool was registered for this ID in Wave 8. Note the existing alias `xcodebuild` → `project_build` (Wave 7) covers the hyphen-less Assist spelling; this adds the Agentic underscore spelling.
- **Description (verbatim):** "Executes xcodebuild to build a project."
- **Capability:** `compilation`. **Risk:** `execution`. **MCP annotations:** as the target.

```json
{"type": "object",
 "properties": {"projectPath": {"type": "string"},
                "scheme": {"type": "string"}},
 "required": ["projectPath", "scheme"]}
```

**Notes.** Legacy behaviour: runs `/usr/bin/xcodebuild -project <projectPath> -scheme <scheme> build`; returns stdout + stderr. Param-compatibility: required `{projectPath, scheme}` is a subset of `project_build`'s params (`projectPath`, `scheme`, `configuration`, `destination`); same names and types. Alias-valid. Behaviour note: the port runs the session build, not `/usr/bin/xcodebuild` directly, and `projectPath` must name the open workspace (the Wave 7 `project_build` rule).

## 32. `swift_package_manager` — Swift Package Manager

- **Legacy class:** `SwiftPackageManagerTool`.
- **Disposition:** DUPLICATE-OF `swift_package_manager` — the ID is already a registered MCP tool (`YcodeTools+SPMDocs.swift`, Wave 7 slice C, the Assist tool of the same ID). No code was written for this ID in Wave 8.
- **Description (verbatim):** "Runs Swift Package Manager commands."
- **Capability:** `compilation`. **Risk:** `execution`. **MCP annotations:** as the registered tool.

```json
{"type": "object",
 "properties": {"action": {"type": "string"},
                "path": {"type": "string"}},
 "required": ["action", "path"]}
```

**Notes.** Legacy behaviour: runs `/usr/bin/swift package <action>` in `path`; returns stdout + stderr. Any action string is passed through. **Coverage caveat:** the ported tool is narrower than the Agentic one — it allowlists actions (`resolve`, `update`, `status`, `dump_manifest`, `describe`) and takes an optional `packageDir` instead of a required `path`, so arbitrary `swift package <action>` invocations (e.g. `clean`, `reset`, `generate-xcodeproj`) are not served by the existing registration. That narrower surface is the Assist tool's design, not a gap introduced here; if the coordinator wants the arbitrary-action surface, it is a widening of the existing tool, not a second registration. Recorded in the param-caveat register in `agentic-tools.md`.

## 33. `git_status` — Git Status

- **Legacy class:** `GitStatusTool`.
- **Disposition:** PORTED as `git_status` in `YcodeTools+AgenticGit.swift` (`agenticGitTools`). The Agentic tool owns this name in Wave 8: the former alias `git_status` → `version_control_operator` was **removed** in Wave 8 (the operator tool remains callable by its own name).
- **Description (verbatim):** "Returns the status of the git repository."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** `git status --porcelain` in `repositoryPath`; returns stdout. Empty output → "Working tree clean."

**Notes.** Legacy behaviour: `git status --porcelain` in `repositoryPath`; returns stdout (unchecked). Port notes: non-zero exit throws git's message (Legacy would return an empty string on failure — see the deviations in `agentic-tools.md`). Why the operator tool does not cover it: `version_control_operator`'s `status` is `git status --short` with no file scope, it requires `action`, and it has no `repositoryPath` — parameter-incompatible. Ycode schema shape: Legacy's schema verbatim, plus the `workspace` parameter, with `repositoryPath` **optional** in the Ycode schema (Legacy requires it); omitted, the tool operates on the session workspace root.

## 34. `git_diff` — Git Diff

- **Legacy class:** `GitDiffTool`.
- **Disposition:** PORTED as `git_diff` in `YcodeTools+AgenticGit.swift`. The former alias `git_diff` → `version_control_operator` was **removed** in Wave 8; the Agentic tool owns this name.
- **Description (verbatim):** "Returns the diff of changes in the repository."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "file": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** `git diff` plus `file` when given, in `repositoryPath`; returns stdout. Empty output → "No changes."

**Notes.** Legacy behaviour: `git diff` plus `file` when given, in `repositoryPath`; returns stdout (unchecked). Port notes: `file` is validated as a repository-relative path (leading `-` rejected); non-zero exit throws git's message. Why the operator tool does not cover it: the target's `diff` is whole-workspace `git diff -- .` with no `file` param and requires `action` — parameter-incompatible. `repositoryPath` optional in the Ycode schema (see §33).

## 35. `git_add` — Git Add

- **Legacy class:** `GitAddTool`.
- **Disposition:** PORTED as `git_add` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Adds files to the git staging area."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "files": {"type": "array", "items": {"type": "string"}}}, "required": ["repositoryPath", "files"]}
```

**Output (success).** "Files added successfully" (git's output when non-empty, else Legacy's success string).

**Notes.** Legacy behaviour: `git add <files...>` in `repositoryPath`; non-zero exit throws stderr; success returns "Files added successfully". Port notes: each file validated as repository-relative; empty `files` keeps Legacy's "Missing repositoryPath or files" error. No alias existed; `version_control_operator` commit stages everything internally (`git add -A`) but exposes no standalone add. `repositoryPath` optional in the Ycode schema (see §33).

## 36. `git_commit` — Git Commit

- **Legacy class:** `GitCommitTool`.
- **Disposition:** PORTED as `git_commit` in `YcodeTools+AgenticGit.swift`. The former alias `git_commit` → `version_control_operator` was **removed** in Wave 8; the Agentic tool owns this name.
- **Description (verbatim):** "Commits staged changes to the git repository."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "message": {"type": "string"}}, "required": ["repositoryPath", "message"]}
```

**Output (success).** Git's output when non-empty, else Legacy's "Changes committed successfully".

**Notes.** Legacy behaviour: `git commit -m <message>` in `repositoryPath`; non-zero exit throws stderr; success returns "Changes committed successfully". Stages nothing — commits what is already staged. Why the operator tool does not cover it: the target runs `git add -A` first and commits with a default message, and requires `action` — behaviour and params differ. `repositoryPath` optional in the Ycode schema (see §33).

## 37. `git_checkout` — Git Checkout

- **Legacy class:** `GitCheckoutTool`.
- **Disposition:** PORTED as `git_checkout` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Checks out a Git branch."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "branch": {"type": "string"}}, "required": ["repositoryPath", "branch"]}
```

**Output (success).** "Successfully checked out branch \(branch)".

**Notes.** Legacy behaviour: `git checkout <branch>` in `repositoryPath`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully checked out branch \(branch)". Port notes: `branch` validated with Wave 3's strict allow-list. Nearest ported tool is `git_branch_manager` `switch` (same git command), but its params (`action` + `branchName`) are incompatible with `branch` — an alias cannot remap them. `repositoryPath` optional in the Ycode schema (see §33).

## 38. `git_branch` — Git Branch

- **Legacy class:** `GitBranchTool`.
- **Disposition:** PORTED as `git_branch` in `YcodeTools+AgenticGit.swift`. The former alias `git_branch` → `version_control_operator` was **removed** in Wave 8; the Agentic tool owns this name.
- **Description (verbatim):** "Lists Git branches."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** `git branch --format=%(refname:short)` in `repositoryPath`; returns the lines joined by `\n`. Empty output → "No branches in the repository."

**Notes.** Legacy behaviour: as above, returns the lines joined by `\n`. Why the operator tool does not cover it: the target's `branch` action creates/checks out a branch; it does not list — behaviour not covered. `repositoryPath` optional in the Ycode schema (see §33).

## 39. `git_merge` — Git Merge

- **Legacy class:** `GitMergeTool`.
- **Disposition:** PORTED as `git_merge` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Merges a Git branch."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "branch": {"type": "string"}}, "required": ["repositoryPath", "branch"]}
```

**Output (success).** "Successfully merged branch \(branch)".

**Notes.** Legacy behaviour: `git merge <branch>` in `repositoryPath`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully merged branch \(branch)". Port notes: `branch` validated with the strict allow-list. On failure with conflicted files, the error names them and the `git merge --abort` escape (Wave 3 cherry-pick shape). No alias, no target. `repositoryPath` optional in the Ycode schema (see §33).

## 40. `git_rebase` — Git Rebase

- **Legacy class:** `GitRebaseTool`.
- **Disposition:** PORTED as `git_rebase` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Rebases the current branch onto another branch."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "branch": {"type": "string"}}, "required": ["repositoryPath", "branch"]}
```

**Output (success).** "Successfully rebased onto \(branch)".

**Notes.** Legacy behaviour: `git rebase <branch>` in `repositoryPath`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully rebased onto \(branch)". Port notes: `branch` validated with the strict allow-list. On failure with conflicted files, the error names them and the `git rebase --abort` escape. No alias, no target. `repositoryPath` optional in the Ycode schema (see §33).

## 41. `git_reset` — Git Reset

- **Legacy class:** `GitResetTool`.
- **Disposition:** PORTED as `git_reset` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Resets the current HEAD to a specified state."
- **Capability:** `gitOperations`. **Risk:** `potentiallyDestructive` (the Legacy default `--hard` discards uncommitted changes and moves HEAD). **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, destructive: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "mode": {"type": "string"}, "target": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** "Successfully reset to \(target) with mode \(mode)".

**Notes.** Legacy behaviour: `git reset <mode> <target>` in `repositoryPath`, with Legacy defaults `mode` = `"--hard"`, `target` = `"HEAD"`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully reset to \(target) with mode \(mode)". Port notes: `mode` validated against `--soft/--mixed/--hard/--merge/--keep`; `target` validated with `gitIsValidRef`. Nearest ported tool is `version_control_operator` `rollback` (`git reset --hard` only), but its params (`ref`) are incompatible with `mode`/`target`. `repositoryPath` optional in the Ycode schema (see §33).

## 42. `git_stash` — Git Stash

- **Legacy class:** `GitStashTool`.
- **Disposition:** PORTED as `git_stash` in `YcodeTools+AgenticGit.swift`. The former alias `git_stash` → `git_stash_operator` was **removed** in Wave 8; the Agentic tool owns this name.
- **Description (verbatim):** "Stashes changes in the working directory."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git for every action except `list` and `show` (which only report, but are still refused in `readOnly` mode because the tool is `writes: true`).

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "action": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** "Successfully executed git stash \(action)".

**Notes.** Legacy behaviour: `git stash <action>` in `repositoryPath`, with Legacy default `action` = `"push"`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully executed git stash \(action)". Port notes: `action` validated against `push/pop/list/show/drop/apply/clear` (Legacy passed it through unchecked). `show` keeps Legacy's plain form (no `-p`); Wave 3's `git_stash_operator` shows with `-p`. Why the operator tool does not cover it: params are incompatible (`repositoryPath` required in Agentic, absent in the target; Agentic passes `action` through raw, the target maps actions and adds `stashIndex`/`message`). `repositoryPath` optional in the Ycode schema (see §33).

## 43. `git_pull` — Git Pull

- **Legacy class:** `GitPullTool`.
- **Disposition:** HONESTLY-FAILING — registered as `git_pull` with full Legacy schema in `YcodeTools+AgenticGit.swift`; the handler always fails naming the missing prerequisite: remote access is out of scope for this wave; remote operations (push/pull/fetch/clone) are a later wave. No remote data is fetched and none is faked.
- **Description (verbatim):** "Pulls changes from a remote repository."
- **Capability:** `gitOperations`. **Risk:** not applicable — the handler always fails (a real pull would be a remote mutation). **Required permission:** `none` (never runs). **Read-only:** yes as registered (github_repo precedent). **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Notes.** Legacy behaviour: `git pull` in `repositoryPath`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully pulled changes".

**Wave 10 note.** Now real: `git pull` in `repositoryPath` (default `.`), approval-gated, registered `writes: true` with `annotations: safeMutation`. Success keeps Legacy's message, `Successfully pulled changes`; failure is `git_pull: git pull failed: <stderr>`. Authentication is the configured credential helper plus best-effort stdin-only PAT seeding for github.com HTTPS remotes (see `github-service.md` §3).

## 44. `git_push` — Git Push

- **Legacy class:** `GitPushTool`.
- **Disposition:** HONESTLY-FAILING — registered as `git_push` with full Legacy schema in `YcodeTools+AgenticGit.swift`; the handler always fails naming the later-wave remote prerequisite (as §43).
- **Description (verbatim):** "Pushes committed changes to the remote repository."
- **Capability:** `gitOperations`. **Risk:** not applicable — the handler always fails (a real push would be a remote mutation). **Required permission:** `none` (never runs). **Read-only:** yes as registered (github_repo precedent). **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Notes.** Legacy behaviour: `git push` in `repositoryPath`; non-zero exit throws stderr; success returns "Push successful".

**Wave 10 note.** Now real: `git push` in `repositoryPath` (default `.`), approval-gated, registered `writes: true` with `annotations: safeMutation`. Success keeps Legacy's message, `Push successful`; failure is `git_push: git push failed: <stderr>`. Same credential seeding as `git_pull` (`github-service.md` §3).

## 45. `git_clone` — Git Clone

- **Legacy class:** `GitCloneTool`.
- **Disposition:** HONESTLY-FAILING — registered as `git_clone` with full Legacy schema in `YcodeTools+AgenticGit.swift`; the handler always fails naming the later-wave remote prerequisite (as §43). This also covers local-path clones: the tool never runs git in this wave.
- **Description (verbatim):** "Clones a Git repository."
- **Capability:** `gitOperations`. **Risk:** not applicable — the handler always fails (a real clone would be a remote fetch). **Required permission:** `none` (never runs). **Read-only:** yes as registered (github_repo precedent). **`writes`:** `false`.

```json
{"type": "object", "properties": {"remoteURL": {"type": "string"}, "destinationPath": {"type": "string"}}, "required": ["remoteURL", "destinationPath"]}
```

**Notes.** Legacy behaviour: `git clone <remoteURL> <destinationPath>` (no working directory); non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully cloned \(remoteURL) to \(destinationPath)". `git_clone` has no `repositoryPath` in Legacy and keeps both of its params required (unlike the other git tools, whose `repositoryPath` is optional in the Ycode schema).

**Wave 10 note.** Now real: `git clone <remoteURL> <destinationPath>` (no working directory), URL-checked by the §3.3 policy (https://, SCP-like SSH, or a local path inside the workspace; other schemes, embedded credentials, and leading `-` rejected), approval-gated, registered `writes: true` with `annotations: safeMutation`. Success keeps Legacy's message; failure is `git_clone: git clone failed: <stderr>`. Same credential seeding as `git_pull` (`github-service.md` §3).

## 46. `git_blame` — Git Blame

- **Legacy class:** `GitBlameTool`.
- **Disposition:** PORTED as `git_blame` in `YcodeTools+AgenticGit.swift`. The former alias `git_blame` → `git_blame_inspector` was **removed** in Wave 8; the Agentic tool owns this name.
- **Description (verbatim):** "Shows Git blame for a file."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "file": {"type": "string"}}, "required": ["repositoryPath", "file"]}
```

**Output (success).** `git blame <file>` in `repositoryPath`; returns stdout.

**Notes.** Legacy behaviour: `git blame <file>` in `repositoryPath`; returns stdout (unchecked). Port notes: `file` validated as repository-relative; non-zero exit throws git's message (Legacy would return an empty string). Why the inspector does not cover it: params are incompatible (`file` vs `path`, `repositoryPath` extra) and output differs (plain `git blame` vs porcelain + `blame -s`). `repositoryPath` optional in the Ycode schema (see §33).

## 47. `git_log` — Git Log

- **Legacy class:** `GitLogTool`.
- **Disposition:** PORTED as `git_log` in `YcodeTools+AgenticGit.swift`. The former alias `git_log` → `git_log_viewer` was **removed** in Wave 8; the Agentic tool owns this name.
- **Description (verbatim):** "Shows Git log for a repository."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** `git log --oneline -n 20` in `repositoryPath`; returns stdout. Empty output → "No commits found in the repository history."

**Notes.** Legacy behaviour: `git log --oneline -n 20` in `repositoryPath`; returns stdout (unchecked). Port notes: fixed `-n 20` kept verbatim. Why the viewer does not cover it: params are incompatible (`repositoryPath` extra) and behaviour differs (fixed `-n 20` vs `maxCount` default 15 + optional `path`). `repositoryPath` optional in the Ycode schema (see §33).

## 48. `git_show` — Git Show

- **Legacy class:** `GitShowTool`.
- **Disposition:** PORTED as `git_show` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Shows details of a Git commit."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "hash": {"type": "string"}}, "required": ["repositoryPath", "hash"]}
```

**Output (success).** `git show <hash>` in `repositoryPath`; returns stdout.

**Notes.** Legacy behaviour: `git show <hash>` in `repositoryPath`; returns stdout (unchecked). Port notes: `hash` validated with `gitIsValidCommit`; non-zero exit throws git's message. No alias, no target. `repositoryPath` optional in the Ycode schema (see §33).

## 49. `git_tag` — Git Tag

- **Legacy class:** `GitTagTool`.
- **Disposition:** PORTED as `git_tag` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Lists Git tags."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}}, "required": ["repositoryPath"]}
```

**Output (success).** `git tag` in `repositoryPath`; returns the lines joined by `\n`. Empty output → "No tags in the repository."

**Notes.** Legacy behaviour: `git tag` in `repositoryPath`; returns the lines joined by `\n`. List only — Legacy has no create/delete form. No alias, no target. `repositoryPath` optional in the Ycode schema (see §33).

## 50. `git_cherry_pick` — Git Cherry-Pick

- **Legacy class:** `GitCherryPickTool`.
- **Disposition:** DUPLICATE-OF `git_cherry_pick` — the ID is already a registered MCP tool (the Wave 3 Assist tool in `YcodeTools+Git.swift`), so no second registration exists in `YcodeTools+AgenticGit.swift`. The one registration was **aligned in place** in Wave 8 to accept Agentic spellings: optional `hash` + `repositoryPath` properties were added, `required` changed from `["commit"]` to `[]`, and the handler uses `commit ?? hash`, with the repo resolved from `repositoryPath` or the workspace root. `noCommit` keeps Legacy's **string** schema.
- **Description (verbatim):** "Cherry-picks a Git commit."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "hash": {"type": "string"}}, "required": ["repositoryPath", "hash"]}
```

**Notes.** Legacy Agentic behaviour: `git cherry-pick <hash>` in `repositoryPath`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully cherry-picked \(hash)". The aligned Assist registration additionally accepts the Assist spelling (`commit`, `noCommit`) and cherry-picks one commit onto the current branch; on conflict it reports the conflicted files and leaves the state for manual resolution. `hash` validated with `gitIsValidCommit`. On failure with conflicted files, the error names them and the `git cherry-pick --abort` escape (Wave 3 shape).

## 51. `git_revert` — Git Revert

- **Legacy class:** `GitRevertTool`.
- **Disposition:** PORTED as `git_revert` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Reverts a Git commit."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git.

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "hash": {"type": "string"}}, "required": ["repositoryPath", "hash"]}
```

**Output (success).** "Successfully reverted \(hash)".

**Notes.** Legacy behaviour: `git revert --no-edit <hash>` in `repositoryPath`; non-zero exit throws `AppError.gitError(stderr)`; success returns "Successfully reverted \(hash)". Port notes: `hash` validated with `gitIsValidCommit`; `--no-edit` kept verbatim (never waits for an editor). No alias, no target. `repositoryPath` optional in the Ycode schema (see §33).

## 52. `git_worktree` — Git Worktree

- **Legacy class:** `GitWorktreeTool`.
- **Disposition:** PORTED as `git_worktree` in `YcodeTools+AgenticGit.swift`.
- **Description (verbatim):** "Manages Git worktrees."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `gitApproveChange` before running git for every action except `list` and `prune` (which only report, but are still refused in `readOnly` mode because the tool is `writes: true`).

```json
{"type": "object", "properties": {"repositoryPath": {"type": "string"}, "action": {"type": "string"}}, "required": ["repositoryPath", "action"]}
```

**Output (success).** `git worktree <action>` in `repositoryPath` (the action passed through as a single argv token); returns stdout.

**Notes.** Legacy behaviour: as above, returns stdout (unchecked). Port notes: `action` validated against `list/add/remove/move/lock/unlock/prune/repair`. `add`, `remove` and `move` need extra arguments Legacy's schema does not provide, so git reports its usage error for them — the Legacy limitation, preserved honestly rather than papered over with an invented schema. No alias, no target. `repositoryPath` optional in the Ycode schema (see §33).

## 53. `fetch_url` — Fetch URL

- **Legacy class:** `FetchURLTool` (`FetchURL.swift`).
- **Disposition:** PORTED as `fetch_url` in `YcodeTools+AgenticNetwork.swift` (`agenticNetworkTools`).
- **Description (verbatim):** "Fetches the content of a URL."
- **Capability:** external read. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `readOnly: true, idempotent: true, openWorld: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}
```

**Output (success).** Structured `{status_code, content}`.

**Notes.** Legacy behaviour: `URLSession.shared.data(from:)` on any URL string; returns the body as UTF-8 text (empty string when undecodable). Missing `url` → `AgentError.toolError("Missing url")`; unparseable URL → `AppError.commonError("Invalid URL")`. Port behaviour: HTTPS-only URL (scheme + host checked); `YcodeAssistant.HTTP.send` (the codebase's proven one-shot request helper, 30 s timeout); non-2xx is a failure; body capped at 2,000,000 bytes; returns structured `{status_code, content}`. Why not `external_resource_gateway`: that tool requires the body to be valid JSON and returns it pretty-printed; `fetch_url` returns raw text for any content type.

## 54. `download_file` — Download File

- **Legacy class:** `DownloadFileTool` (`DownloadFile.swift`).
- **Disposition:** PORTED as `download_file` in `YcodeTools+AgenticNetwork.swift`.
- **Description (verbatim):** "Downloads a file from a URL."
- **Capability:** external write. **Risk:** `externalSideEffect`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`. **Gate:** approval gate (`approveFileWritingChange`) before the fetch and the write.

```json
{"type": "object", "properties": {"url": {"type": "string"}, "destinationPath": {"type": "string"}}, "required": ["url", "destinationPath"]}
```

**Output (success).** Structured `{url, destinationPath, bytes}`. Summary: `"Successfully downloaded \(url) to \(destinationPath)"` (Legacy's message).

**Notes.** Legacy behaviour: `URLSession.shared.download(from:)`, then `removeItem` + `moveItem` to the destination (any absolute path). Returns `"Successfully downloaded \(url) to \(destinationPath)"`. Port behaviour: HTTPS-only URL; destination resolved with `resolveFileWritingPath` (workspace-confined); body capped at 10,000,000 bytes; written atomically (binary-safe — `commit()` is text-only and is not used).

## 55. `upload_file` — Upload File

- **Legacy class:** `UploadFileTool` (`UploadFile.swift`).
- **Disposition:** PORTED as `upload_file` in `YcodeTools+AgenticNetwork.swift`.
- **Description (verbatim):** "Uploads a file to a URL."
- **Capability:** external write. **Risk:** `externalSideEffect`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`. **Gate:** approval gate before the file leaves the workspace (an upload is an external side effect carrying workspace data).

```json
{"type": "object", "properties": {"path": {"type": "string"}, "url": {"type": "string"}}, "required": ["path", "url"]}
```

**Output (success).** Structured `{status_code, content}`.

**Notes.** Legacy behaviour: `URLSession.shared.upload(for:fromFile:)` with an HTTP POST; returns the response body as UTF-8 text. Port behaviour: HTTPS-only URL; source resolved with `resolveFileReadingPath` (workspace-confined, must exist); file capped at 10,000,000 bytes; POST via `YcodeAssistant.HTTP.send`; non-2xx is a failure; response body capped at 2,000,000 bytes.

## 56. `http_request` — HTTP Request

- **Legacy class:** `HTTPRequestTool` (`HTTPRequest.swift`).
- **Disposition:** PORTED as `http_request` in `YcodeTools+AgenticNetwork.swift`.
- **Description (verbatim):** "Performs an HTTP request."
- **Capability:** external write (the method may mutate). **Risk:** `externalSideEffect`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`. **Gate:** mutating methods (POST/PUT/PATCH/DELETE) go through the approval gate and therefore need an open workspace; safe methods (GET/HEAD/OPTIONS) do not.

```json
{"type": "object", "properties": {"url": {"type": "string"}, "method": {"type": "string"}, "headers": {"type": "object", "additionalProperties": {"type": "string"}}, "body": {"type": "string"}}, "required": ["url", "method"]}
```

**Output (success).** Structured `{status_code, content}`.

**Notes.** Legacy behaviour: `URLRequest` with any method string, caller headers, optional UTF-8 body; `URLSession.shared.data(for:)`; returns the body as UTF-8 text. Missing `url`/`method` → `"Missing url or method"`. Port behaviour: HTTPS-only URL; method allow-list — GET, HEAD, OPTIONS, POST, PUT, PATCH, DELETE (Legacy passed any method string through); headers must be strings; non-2xx is a failure; body capped at 2,000,000 bytes. Why not `external_resource_gateway`: that tool is GET-only and JSON-only; `http_request` allows any method, headers, and body and returns raw text.

## 57. `web_search` — Web Search

- **Legacy class:** `WebSearchTool` (`WebSearch.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `web_search` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `query`, then fails naming the missing prerequisite. No search was performed and no results were invented.
- **Description (verbatim):** "Performs a web search."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** default (read-only); no network call is made.

```json
{"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
```

**Missing prerequisite (exact).** A web search provider/backend in Ycode MCP.

**Notes.** Legacy behaviour: GETs `https://ddg-api.herokuapp.com/search?q=<percent-encoded query>` and returns the body, or `"No results"` when undecodable. Missing `query` → `"Missing query"`. Why honestly failing: Legacy's endpoint is an unofficial DuckDuckGo proxy, not a supported search backend. Ycode's MCP host has no web search provider at all. Wiring the tool to that proxy would depend on a defunct third-party endpoint; inventing results would be fake behaviour. Failure message: "web_search needs a web search provider, which Ycode's MCP host does not have yet: no search was performed. Legacy called an unofficial DuckDuckGo proxy (ddg-api.herokuapp.com) that is not a supported search backend; no request was sent to it and no results were invented."

## 58. `documentation_search` — Documentation Search

- **Legacy class:** `DocumentationSearchTool` (`DocumentationSearch.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `documentation_search` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `query`, then fails naming the missing backend and pointing at `fetch_documentation`.
- **Description (verbatim):** "Searches for documentation."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
```

**Missing prerequisite (exact).** A documentation search index/backend in Ycode MCP.

**Notes.** Legacy behaviour: a stub. `run(query:)` returns the canned string `"Documentation for: \(query)"` without searching anything. Why honestly failing: returning that string would be fake behaviour. Ycode has no documentation search backend: `fetch_documentation` fetches a known Apple documentation page, it does not search.

## 59. `api_reference_search` — API Reference Search

- **Legacy class:** `APIReferenceSearchTool` (`APIReferenceSearch.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `api_reference_search` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `query`, then fails naming the missing backend.
- **Description (verbatim):** "Searches for API references."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
```

**Missing prerequisite (exact).** A documentation search index/backend in Ycode MCP.

**Notes.** Legacy behaviour: a stub. `run(query:)` returns the canned string `"API Reference for: \(query)"` without searching anything. Why honestly failing: same as `documentation_search` (§58) — the canned string is fake behaviour, and Ycode has no API-reference search backend (`fetch_documentation` fetches known pages only).

## 60. `package_search` — Package Search

- **Legacy class:** `PackageSearchTool` (`PackageSearch.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `package_search` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `query`, then fails naming the missing backend.
- **Description (verbatim):** "Searches for packages."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
```

**Missing prerequisite (exact).** A package-index search backend in Ycode MCP (for example the Swift Package Index API).

**Notes.** Legacy behaviour: a stub. `run(query:)` returns the canned string `"Package search results for: \(query)"` without searching anything. Why honestly failing: the canned string is fake behaviour, and Ycode has no package-index search backend.

## 61. `dependency_audit` — Dependency Audit

- **Legacy class:** `DependencyAuditTool` (`DependencyAudit.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `dependency_audit` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `projectPath`, then fails naming the missing prerequisite.
- **Description (verbatim):** "Audits project dependencies for vulnerabilities."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call, no filesystem read.

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Missing prerequisite (exact).** A vulnerability/advisory data source in Ycode MCP.

**Notes.** Legacy behaviour: a stub. `run(projectPath:)` returns the canned string `"No vulnerabilities found in dependencies at \(projectPath)"` without checking anything — a clean bill of health invented out of nothing. Why honestly failing: no vulnerability check is possible without a vulnerability/advisory data source, and Ycode MCP has none. Returning Legacy's string would assert a security claim nobody verified. Not a duplicate of `package_dependency_audit`: that ported tool audits pins (declared vs. `Package.resolved`), not vulnerabilities. Different behaviour; no alias.

## 62. `install_dependencies` — Install Dependencies

- **Legacy class:** `InstallDependenciesTool` (`InstallDependencies.swift`).
- **Disposition:** PORTED as `install_dependencies` in `YcodeTools+AgenticNetwork.swift`.
- **Description (verbatim):** "Installs project dependencies."
- **Capability:** `execution`. **Risk:** `execution`. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true` (resolving fetches packages and writes into the package cache / `.build`). **Gate:** approval gate (`terminalApproveChange`).

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Output (success).** Exit 0 returns structured `{exitCode, output}`; non-zero throws with the output.

**Notes.** Legacy behaviour: runs `/usr/bin/swift package resolve` with `projectPath` as the working directory (via Legacy's `ProcessRunnerTool`) and returns stdout + stderr. Port behaviour: `projectPath` resolved inside the workspace (`resolveFileReadingPath`); `Package.swift` must exist in that directory; `/usr/bin/swift` must exist; `/usr/bin/swift package resolve` via `terminalRunFixed`, 300 s timeout. On Linux (no `/usr/bin/swift`) the tool fails with "Swift not found at /usr/bin/swift.", the `spmDocsSwiftPackage` message. Not an alias of `swift_package_manager`: an alias passes arguments unchanged and `Schema.object` rejects unknown keys, but the Agentic tool requires `projectPath` (which `swift_package_manager` does not have — it has `packageDir`) while `swift_package_manager` requires `action` (which the Agentic tool does not send). Param-incompatible → ported as distinct.

## 63. `update_dependencies` — Update Dependencies

- **Legacy class:** `UpdateDependenciesTool` (`UpdateDependencies.swift`).
- **Disposition:** PORTED as `update_dependencies` in `YcodeTools+AgenticNetwork.swift`.
- **Description (verbatim):** "Updates project dependencies."
- **Capability:** `execution`. **Risk:** `execution`. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** approval gate (`terminalApproveChange`).

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Output (success).** Same shape as §62, with subcommand `update`.

**Notes.** Legacy behaviour: runs `/usr/bin/swift package update` with `projectPath` as the working directory and returns stdout + stderr. Port behaviour: same shape as `install_dependencies` (§62), with subcommand `update`. Not an alias of `package_dependency_update`: that tool runs `swift package update` only in the workspace root and has no `projectPath` parameter; the Agentic tool requires `projectPath`. Param-incompatible → ported as distinct. (Same argument against `swift_package_manager` action `update` as in §62.)

## 64. `remove_dependencies` — Remove Dependencies

- **Legacy class:** `RemoveDependenciesTool` (`RemoveDependencies.swift`).
- **Disposition:** PORTED as `remove_dependencies` in `YcodeTools+AgenticNetwork.swift`.
- **Description (verbatim):** "Removes a package dependency from the project."
- **Capability:** `safeMutation`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** the edited manifest goes through `commit()` (approval gate).

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}, "packageName": {"type": "string"}}, "required": ["projectPath", "packageName"]}
```

**Output (success).** The manifest with the package removed; the tool fails honestly ("Package '…' not found in Package.swift at …") when no `.package` entry matches, and leaves the file untouched.

**Notes.** Legacy behaviour: a stub. `run(projectPath:packageName:)` returns `"Package \(packageName) removed from Package.swift at \(projectPath)"` without editing anything. **Port behaviour — real removal, not Legacy's stub:** the handler resolves `projectPath` inside the workspace, reads `Package.swift`, and performs manifest surgery (`agenticNetworkRemovePackage`): (1) finds every `dependencies: [...]` array in the manifest (package-level first, then each target's), with bracket matching that skips string contents; (2) in the package-level array, removes the `.package(...)` element matching `packageName` — by an explicit `name:`, by the last path component of its `url:` (without a trailing `.git`), or by the URL itself; (3) in every target array, removes `.product(name: "<packageName>", …)` elements and bare `"<packageName>"` string elements (SwiftPM lets a target list a dependency product as a plain string); (4) element removal takes one adjacent comma with it (trailing comma, else the preceding one) and swallows the removed line's indentation/newline, so the manifest stays valid with no dangling `,,`. `packageName` must be a single token (no spaces, slashes, or `..`). **Known limitation (recorded):** a bare string in a target's dependencies is treated as a product reference; the pathological case of a same-package target sharing the package's name would also be removed. Multiline strings and string interpolation inside dependency arrays are not special-cased by the bracket matcher; manifests do not use them there.

## 65. `create_pull_request` — Create Pull Request

- **Legacy class:** `CreatePullRequestTool` (`CreatePullRequest.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `create_pull_request` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates all four arguments, then fails naming the missing prerequisite.
- **Description (verbatim):** "Creates a pull request."
- **Capability:** read-only (registered, never executes). **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"title": {"type": "string"}, "body": {"type": "string"}, "head": {"type": "string"}, "base": {"type": "string"}}, "required": ["title", "body", "head", "base"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"PR created: \(title)"` with no API call behind it. Note: Legacy's schema carries no owner/repo — the tool could not have addressed a repository even if it had called an API. Why honestly failing: the Wave 3 `github_repo` precedent — Ycode's MCP host has no GitHub API client and no GitHub credential flow. This cannot be implemented purely on local git data: creating a PR is a GitHub-side write. Failure message: "<tool> needs a GitHub API client with authentication, which Ycode's MCP host does not have yet: no GitHub data was read or written. Remote and GitHub access is a later wave; use the workspace's local git tools (git_log_viewer, git_branch_compare, git_pr_summary) for local repository information."for local repository information."

**Wave 10 note.** Now real: `POST /repos/{owner}/{repo}/pulls` via `YcodeGitHub`, with the repository from the new optional `repository` argument or the workspace remote (Legacy had no repo parameter at all). Requires a token; registered `writes: true` with `annotations: external`; approval-gated before the API call. Success: `PR #<number> created: <title> (<html_url>)`. See `github-service.md` §2.1.

## 66. `review_pull_request` — Review Pull Request

- **Legacy class:** `ReviewPullRequestTool` (`ReviewPullRequest.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `review_pull_request` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `prNumber`, then fails naming the missing prerequisite (as §65).
- **Description (verbatim):** "Reviews a pull request."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"prNumber": {"type": "integer"}}, "required": ["prNumber"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"Reviewing PR #\(prNumber)"` with no API call behind it. Why honestly failing: same prerequisite as §65. Reviewing a PR needs the PR's diff and review API, which live on GitHub, not in the local checkout. (The local `git_pr_summary` tool only summarises already-fetched local refs.)(The local `git_pr_summary` tool only summarises already-fetched local refs.)

**Wave 10 note.** Now real as a read-only summary: the PR plus its reviews, via `YcodeGitHub`; no token required for a public repo. Legacy has no `body`/`event` parameter, so there is no submit-a-review path — no parameter was invented. See `github-service.md` §2.2.

## 67. `read_pull_request` — Read Pull Request

- **Legacy class:** `ReadPullRequestTool` (`ReadPullRequest.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `read_pull_request` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `prNumber`, then fails naming the missing prerequisite (as §65).
- **Description (verbatim):** "Reads content of a pull request."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"prNumber": {"type": "integer"}}, "required": ["prNumber"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"Content of PR #\(prNumber)"` with no API call behind it. Why honestly failing: same prerequisite as §65. PR content lives on GitHub; it is not in local git data (unless the `refs/pull/…` ref was explicitly fetched, which the tool cannot assume and which Legacy never did).which Legacy never did).

**Wave 10 note.** Now real: the PR plus its changed files, via `YcodeGitHub`; no token required for a public repo. The file list is capped at 30 entries. See `github-service.md` §2.3.

## 68. `read_issues` — Read Issues

- **Legacy class:** `ReadIssuesTool` (`ReadIssues.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `read_issues` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `repository`, then fails naming the missing prerequisite (as §65).
- **Description (verbatim):** "Reads issues for a repository."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"repository": {"type": "string"}}, "required": ["repository"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"List of issues for \(repository)"` with no API call behind it. Why honestly failing: same prerequisite as §65. Issues live on GitHub, not in the local checkout.Issues live on GitHub, not in the local checkout.

**Wave 10 note.** Now real: `GET /repos/{owner}/{repo}/issues?state=open`, PRs excluded, via `YcodeGitHub`; no token required for a public repo. See `github-service.md` §2.4.

## 69. `create_issue` — Create Issue

- **Legacy class:** `CreateIssueTool` (`CreateIssue.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `create_issue` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `title` and `body`, then fails naming the missing prerequisite (as §65).
- **Description (verbatim):** "Creates an issue."
- **Capability:** read-only (registered, never executes). **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"title": {"type": "string"}, "body": {"type": "string"}}, "required": ["title", "body"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"Issue created: \(title)"` with no API call behind it. Why honestly failing: same prerequisite as §65. Creating an issue is a GitHub-side write.Creating an issue is a GitHub-side write.

**Wave 10 note.** Now real: `POST /repos/{owner}/{repo}/issues` via `YcodeGitHub`, with the repository from the new optional `repository` argument or the workspace remote. Requires a token; registered `writes: true` with `annotations: external`; approval-gated before the API call. Success: `Issue #<number> created: <title> (<html_url>)`. See `github-service.md` §2.5.

## 70. `update_issue` — Update Issue

- **Legacy class:** `UpdateIssueTool` (`UpdateIssue.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `update_issue` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `issueNumber`, then fails naming the missing prerequisite (as §65).
- **Description (verbatim):** "Updates an issue."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"issueNumber": {"type": "integer"}, "title": {"type": "string"}, "body": {"type": "string"}}, "required": ["issueNumber"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"Issue #\(issueNumber) updated"` with no API call behind it. `title`/`body` are optional (only `issueNumber` is required). Why honestly failing: same prerequisite as §65.

**Wave 10 note.** Now real: `PATCH /repos/{owner}/{repo}/issues/{number}` via `YcodeGitHub`, with the repository from the new optional `repository` argument or the workspace remote. Requires a token; registered `writes: true` with `annotations: external`; approval-gated before the API call. Fails when neither `title` nor `body` is supplied instead of sending an empty PATCH. See `github-service.md` §2.6.

## 71. `search_issues` — Search Issues

- **Legacy class:** `SearchIssuesTool` (`SearchIssues.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `search_issues` with Legacy's full schema in `YcodeTools+AgenticNetwork.swift`; the handler validates `query`, then fails naming the missing prerequisite (as §65).
- **Description (verbatim):** "Searches for issues."
- **Capability:** read-only. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** read-only; no network call.

```json
{"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
```

**Missing prerequisite (exact).** GitHub API client + credential flow in Ycode MCP.

**Notes.** Legacy behaviour: a stub. Returns `"Search results for issues: \(query)"` with no API call behind it. Why honestly failing: same prerequisite as §65. GitHub issue search is a GitHub API operation, not local data.

**Wave 10 note.** Now real: `GET /search/issues` via `YcodeGitHub`; no token required for a public search. The new optional `repository` argument appends `repo:<owner>/<repo>` to the query (Legacy's schema has no `repository` argument). See `github-service.md` §2.7.

## 72. `cocoapods` — CocoaPods

- **Legacy class:** `CocoaPodsTool`.
- **Disposition:** PORTED as `cocoapods` in `YcodeTools+AgenticCLI.swift` (`agenticCLITools`).
- **Description (verbatim):** "Runs CocoaPods commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** Structured data in the `use_terminal` output keys (`command`, `workingDirectory`, `stdout`, `stderr`, `stdoutTruncated`, `stderrTruncated`, `exitCode`, `duration`). Success summary: `<display command> completed successfully (exit code 0 in <duration>):\n<stdout or "(No stdout output)">` with stdout capped at the last 3000 chars (stderr at the last 2000) in the structured data. Non-zero exit: error `<display command> failed with exit code <n> (<duration>):\n<stderr or stdout, last 1500 chars>` with the same data attached.

**Notes.** Behaviour: `pod <action>` in the `path` directory (Legacy: `/usr/local/bin/pod`). Binary resolves on `PATH` (`pod`), not Legacy's fixed `/usr/local/bin/pod`. Every command in this slice runs through `terminalRunFixed` with a fixed argv, stdin closed, the never-wait-for-a-person environment (`terminalEnvironment`), bounded at 300 s like `use_terminal`. The `action` argument is passed as a single argv element, so shell syntax inside it can never run. A `path` naming a working directory resolves with `resolveFileReadingPath` and must exist and be a directory (`path does not exist or is not a directory: <path>`); Legacy accepted any absolute path. Missing/empty arguments fail with Legacy's exact `execute()` guard messages (`Missing action or path` here).

## 73. `carthage` — Carthage

- **Legacy class:** `CarthageTool`.
- **Disposition:** PORTED as `carthage` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs Carthage commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72 (`use_terminal` output keys; success / failure / timeout shapes).

**Notes.** Behaviour: `carthage <action>` in the `path` directory (Legacy: `/usr/local/bin/carthage`). Binary resolves on `PATH` (`carthage`). Shared slice conventions as §72.

## 74. `android_build` — Build Android Project

- **Legacy class:** `AndroidBuildTool`.
- **Disposition:** PORTED as `android_build` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Builds an Android project."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "path": { "type": "string" }
  },
  "required": ["path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `gradle assembleDebug` in the `path` directory (Legacy: `/usr/bin/gradle`). Deliberate deviation: the port prefers the project's `gradlew` wrapper when an executable one exists in the project directory (the standard Android build entry point), falling back to `gradle` on `PATH`. When neither exists the failure names both: `Process execution failed: command 'gradle' was not found (no executable on PATH or at that path) and no gradlew wrapper exists in '<path>'.` Shared slice conventions as §72; empty `path` fails with Legacy's `Missing path`.

## 75. `gradle` — Gradle

- **Legacy class:** `GradleTool`.
- **Disposition:** PORTED as `gradle` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs Gradle commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `gradle <action>` in the `path` directory (Legacy: `/usr/bin/gradle`). Binary resolves on `PATH` (`gradle`). Shared slice conventions as §72.

## 76. `npm` — npm

- **Legacy class:** `NpmTool`.
- **Disposition:** PORTED as `npm` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs npm commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `npm <action>` in the `path` directory (Legacy: `/usr/bin/npm`). Binary resolves on `PATH` (`npm`). Shared slice conventions as §72.

## 77. `pnpm` — pnpm

- **Legacy class:** `PnpmTool`.
- **Disposition:** PORTED as `pnpm` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs pnpm commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `pnpm <action>` in the `path` directory (Legacy: `/usr/bin/pnpm`). Binary resolves on `PATH` (`pnpm`). Shared slice conventions as §72.

## 78. `yarn` — Yarn

- **Legacy class:** `YarnTool`.
- **Disposition:** PORTED as `yarn` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs yarn commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `yarn <action>` in the `path` directory (Legacy: `/usr/bin/yarn`). Binary resolves on `PATH` (`yarn`). Shared slice conventions as §72.

## 79. `bun` — Bun

- **Legacy class:** `BunTool`.
- **Disposition:** PORTED as `bun` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs bun commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `bun <action>` in the `path` directory (Legacy: `/usr/bin/bun`). Binary resolves on `PATH` (`bun`). Shared slice conventions as §72.

## 80. `cargo` — Cargo

- **Legacy class:** `CargoTool`.
- **Disposition:** PORTED as `cargo` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs cargo commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `cargo <action>` in the `path` directory (Legacy: `/usr/bin/cargo`). Binary resolves on `PATH` (`cargo`). Shared slice conventions as §72.

## 81. `go_build` — Build Go Project

- **Legacy class:** `GoBuildTool`.
- **Disposition:** PORTED as `go_build` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Builds a Go project."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "path": { "type": "string" }
  },
  "required": ["path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `go build` in the `path` directory (Legacy: `/usr/bin/go`, no package argument — builds the package in the working directory). Binary resolves on `PATH` (`go`). Shared slice conventions as §72; empty `path` fails with Legacy's `Missing path`.

## 82. `python_pip` — Python pip

- **Legacy class:** `PythonPipTool`.
- **Disposition:** PORTED as `python_pip` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs pip commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "package": { "type": "string" }
  },
  "required": ["action", "package"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `pip <action> <package>` in the workspace root (Legacy ran with no working directory, `/usr/bin/pip`). Deliberate deviation: the port falls back to `pip3` when `pip` is not on `PATH`; the missing-binary failure still names `pip`. Shared slice conventions as §72; empty arguments fail with Legacy's `Missing action or package`.

## 83. `java_maven` — Maven

- **Legacy class:** `JavaMavenTool`.
- **Disposition:** PORTED as `java_maven` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs Maven commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `mvn <action>` in the `path` directory (Legacy: `/usr/bin/mvn`). Binary resolves on `PATH` (`mvn`). Shared slice conventions as §72.

## 84. `dotnet_cli` — .NET CLI

- **Legacy class:** `DotNetCLITool`.
- **Disposition:** PORTED as `dotnet_cli` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs .NET CLI commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `dotnet <action>` in the `path` directory (Legacy: `/usr/bin/dotnet`). Binary resolves on `PATH` (`dotnet`). Shared slice conventions as §72.

## 85. `flutter` — Flutter

- **Legacy class:** `FlutterTool`.
- **Disposition:** PORTED as `flutter` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs Flutter commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `flutter <action>` in the `path` directory (Legacy: `/usr/bin/flutter`). Binary resolves on `PATH` (`flutter`). Shared slice conventions as §72.

## 86. `react_native` — React Native

- **Legacy class:** `ReactNativeTool`.
- **Disposition:** PORTED as `react_native` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs React Native commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `npx react-native <action>` in the `path` directory (Legacy: `/usr/bin/npx`). Binary resolves on `PATH` (`npx`); `react-native` is the fixed first argument, not a resolvable binary. Shared slice conventions as §72.

## 87. `expo` — Expo

- **Legacy class:** `ExpoTool`.
- **Disposition:** PORTED as `expo` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs Expo commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["action", "path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `npx expo <action>` in the `path` directory (Legacy: `/usr/bin/npx`). Binary resolves on `PATH` (`npx`); `expo` is the fixed first argument. Shared slice conventions as §72.

## 88. `docker_build` — Build Docker Image

- **Legacy class:** `DockerBuildTool`.
- **Disposition:** PORTED as `docker_build` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Builds a Docker image."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "path": { "type": "string" },
    "tag": { "type": "string" }
  },
  "required": ["path", "tag"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `docker build -t <tag> <path>` (Legacy: `/usr/bin/docker`, no working directory). Deliberate deviation: the port runs with the build context directory as its working directory and passes `.` as the context, which is equivalent to Legacy's `docker build -t <tag> <path>` and keeps the context inside the workspace. Binary resolves on `PATH` (`docker`). Shared slice conventions as §72; empty arguments fail with Legacy's `Missing path or tag`.

## 89. `docker_run` — Run Docker Container

- **Legacy class:** `DockerRunTool`.
- **Disposition:** PORTED as `docker_run` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs a Docker container."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "image": { "type": "string" }
  },
  "required": ["image"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `docker run <image>` in the workspace root (Legacy ran with no working directory, `/usr/bin/docker`). Note Legacy passes no container arguments, ports, or detach flag: the run is foreground and bounded by the 300 s timeout. Binary resolves on `PATH` (`docker`). Shared slice conventions as §72; empty `image` fails with Legacy's `Missing image`.

## 90. `docker_compose` — Docker Compose

- **Legacy class:** `DockerComposeTool`.
- **Disposition:** PORTED as `docker_compose` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Runs docker-compose commands."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "path": { "type": "string" },
    "action": { "type": "string" }
  },
  "required": ["path", "action"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `docker-compose -f <path> <action>` in the workspace root (Legacy: `/usr/bin/docker-compose`, no working directory). The `path` is the compose file; it must exist (a `path` naming a file must exist and not be a directory: `path does not exist or is not a file: <path>`). Deliberate deviation: the port falls back to `docker compose -f <path> <action>` (the v2 subcommand) when `docker-compose` is not on `PATH` but `docker` is. When neither exists the failure names `docker-compose`. Shared slice conventions as §72; empty arguments fail with Legacy's `Missing path or action`.

## 91. `kubernetes_apply` — Apply Kubernetes Configuration

- **Legacy class:** `KubernetesApplyTool`.
- **Disposition:** PORTED as `kubernetes_apply` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Applies a Kubernetes configuration."
- **Capability:** `execution`. **Risk:** `execution`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`. **Gate:** `terminalApproveChange` before running.

```json
{
  "type": "object",
  "properties": {
    "path": { "type": "string" }
  },
  "required": ["path"]
}
```

**Output (success).** As §72.

**Notes.** Behaviour: `kubectl apply -f <path>` in the workspace root (Legacy ran with no working directory, `/usr/bin/kubectl`). The `path` is the manifest file; it must exist. Binary resolves on `PATH` (`kubectl`). Shared slice conventions as §72; empty `path` fails with Legacy's `Missing path`.

## 92. `view_container_logs` — View Container Logs

- **Legacy class:** `ViewContainerLogsTool`.
- **Disposition:** PORTED as `view_container_logs` in `YcodeTools+AgenticCLI.swift`.
- **Description (verbatim):** "Views logs for a Docker container."
- **Capability:** read. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read` (`readOnly: true, idempotent: true`). **`writes`:** `false`. **Gate:** none — no approval gate. The one pure read in this slice.

```json
{
  "type": "object",
  "properties": {
    "containerID": { "type": "string" }
  },
  "required": ["containerID"]
}
```

**Output (success).** As §72 (the `use_terminal` output keys carry the `docker logs` output).

**Notes.** Behaviour: `docker logs <containerID>` in the workspace root (Legacy ran with no working directory, `/usr/bin/docker`). Binary resolves on `PATH` (`docker`). Shared slice conventions as §72; empty `containerID` fails with Legacy's `Missing containerID`.

## 93. `call_hierarchy` — Call Hierarchy

- **Legacy class:** `CallHierarchyTool` (`CallHierarchy.swift`).
- **Disposition:** DUPLICATE-OF `call_hierarchy` — the ID is already registered by the Wave 3 port of Assist's `AssistCallHierarchyTool` (`YcodeTools+Search.swift`), so no second registration exists. The registered tool is real behaviour serving the Agentic tool's purpose, and strictly more than the Agentic stub.
- **Description (verbatim, Agentic):** "Displays the call hierarchy of a symbol."
- **Capability:** as the ported tool (`safeRead`). **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"symbol": {"type": "string"}}, "required": ["symbol"]}
```

**Notes.** Legacy Agentic behaviour: a stub — `run` returns the string `"Call hierarchy for <symbol>"` and does nothing else. Served tool: "For a function name, finds its definition site, its callers across the workspace, and the functions it calls." It scans Swift files for the function name, reports definitions (at most 20), callers (at most 50), and callees (distinct, sorted), with data keys `function`, `definitionCount`, `callerCount`, `calleeCount`. **Parameter caveat:** the ported tool requires `function`; the Agentic schema requires `symbol`. An Agentic caller passing `symbol` would fail required-argument validation against the ported schema. There is no alias that can remap the name (aliases pass arguments through unchanged), so Agentic callers must be told to use `function`. No code was written for this tool. Recorded in the param-caveat register in `agentic-tools.md`.

## 94. `dependency_graph` — Dependency Graph

- **Legacy class:** `DependencyGraphTool` (`DependencyGraph.swift`).
- **Disposition:** DUPLICATE-OF `dependency_graph` — the ID is already registered by the Wave 3 port of Assist's `AssistDependencyGraphTool` (`YcodeTools+Search.swift`), so no second registration exists. The registered tool is real behaviour serving the Agentic tool's purpose, and strictly more than the Agentic stub.
- **Description (verbatim, Agentic):** "Generates a dependency graph for a project."
- **Capability:** as the ported tool (`safeRead`). **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Notes.** Legacy Agentic behaviour: a stub — `run` returns the string `"Visual representation of dependencies"` and does nothing else. Served tool: "Generates a graph of project dependencies." It scans `.swift` files under the scope directory, extracts imports with `^\s*import\s+([A-Za-z0-9_\.]+)`, and reports nodes (files + modules) and edges (`<source> -> <module>`) with data keys `node_count`, `edge_count`, `nodes`, `edges`. **Parameter caveat:** the ported tool takes an optional `path` (defaults to the workspace root); the Agentic schema requires `projectPath`. An Agentic caller passing `projectPath` would be rejected as an unknown argument. Agentic callers must be told to use `path`. No code was written for this tool. Recorded in the param-caveat register in `agentic-tools.md`.

## 95. `semantic_code_search` — Semantic Code Search

- **Legacy class:** `SemanticCodeSearchTool` (`SemanticCodeSearch.swift`).
- **Disposition:** ALREADY-SERVED → `semantic_query_engine` (alias, **added in Wave 8** to `MCPServer.toolAliases`). No tool was registered for this ID in Wave 8.
- **Description (verbatim):** "Performs semantic search on code."
- **Capability:** as the target (`safeRead`). **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
```

**Notes.** Legacy Agentic behaviour: a stub — `run` returns `["Results for semantic search: <query>"]`. Served tool: `semantic_query_engine` — "Performs semantic search for symbols, SwiftUI views, models, and services with usage context." Its own port is explicit that it is a literal substring scan with three keyword expansions (`view` / `model` / `service`), exactly as Legacy's Assist implementation does it — despite the name it performs no embedding or LLM semantic search, and the port does not pretend otherwise. That is the project's accepted realisation of "semantic search over code", and the Agentic tool's intended behaviour is exactly that. Param-compatibility (alias-valid): the Agentic tool's required parameters are `{query: string}`; the target accepts `{query: string, path?: string}`. Required set is a subset with the same name and type, so an alias passing arguments through unchanged is valid. `semantic_query_engine` needs no LLM (Legacy's search is a substring scan).

## 96. `cross_reference_search` — Cross Reference Search

- **Legacy class:** `CrossReferenceSearchTool` (`CrossReferenceSearch.swift`).
- **Disposition:** ALREADY-SERVED → `symbol_reference_graph` (alias, **added in Wave 8** to `MCPServer.toolAliases`). No tool was registered for this ID in Wave 8.
- **Description (verbatim):** "Searches for cross-references of a symbol."
- **Capability:** as the target (`safeRead`). **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"symbol": {"type": "string"}}, "required": ["symbol"]}
```

**Notes.** Legacy Agentic behaviour: a stub — `run` returns `["References to <symbol>"]`. Served tool: `symbol_reference_graph` — "Traverses workspace files to identify declarations, references, and call sites for a given Swift symbol." It enumerates workspace Swift files, reports every line containing the symbol (declarations vs usages, `maxResults` default 50). Param-compatibility (alias-valid): the Agentic tool's required parameters are `{symbol: string}`; the target accepts `{symbol: string, maxResults?: integer}`. Required set is a subset with the same name and type, so an alias passing arguments through unchanged is valid. (Note the existing alias `symbol_graph` → `symbol_reference_graph` is the same target.)

## 97. `generate_code` — Generate Code

- **Legacy class:** `GenerateCodeTool` (`GenerateCode.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `generate_code` with the full Legacy schema in `YcodeTools+AgenticCode.swift` (`agenticCodeTools`); the handler always fails, naming the missing LLM provider (Wave 2 `code_refactor` / Wave 6 `code_review` precedent). Legacy itself returns a canned string — a fake in Legacy, not ported as real behaviour.
- **Description (verbatim):** "Generates code based on a prompt."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema (as with `code_refactor` / `code_review`).

```json
{"type": "object", "properties": {"prompt": {"type": "string"}}, "required": ["prompt"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"// Generated code based on: <prompt>\nfunc generated() {}"`. Failure message (verbatim): `generate_code is unavailable: generating code from a prompt needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns a canned stub ("// Generated code based on: <prompt>"), so nothing is generated here.` Template / stub generation labelled as such was explicitly ruled out as a stand-in: the tool's real value is LLM generation. Each handler throws `MCPToolError` with its message; no workspace session is needed and nothing is written. Not a duplicate of `code_generate`: the ported tool renders one of four fixed file templates from a required `path` + `template`; the Agentic tool takes a free-form `prompt`. Different parameters and different behaviour.

## 98. `refactor_code` — Refactor Code

- **Legacy class:** `RefactorCodeTool` (`RefactorCode.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `refactor_code` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Refactors code based on instructions."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}, "instructions": {"type": "string"}}, "required": ["code", "instructions"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"// Refactored code\n\(code)"` — the input code unchanged with a comment. Failure message (verbatim): `refactor_code is unavailable: refactoring code from instructions needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns the input code unchanged with a comment, so nothing was changed.` Not a duplicate of `code_refactor`: the ported tool is itself honestly failing and takes `path` + `action`; the Agentic tool takes inline `code` + `instructions`. Not alias-compatible.

## 99. `review_code` — Review Code

- **Legacy class:** `ReviewCodeTool` (`ReviewCode.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `review_code` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Reviews code using AI."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"Review comments: LGTM!"`. Failure message (verbatim): `review_code is unavailable: reviewing code needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns a canned "Review comments: LGTM!", so no review is performed and nothing was verified.` Not a duplicate of `code_review`: the ported tool is itself honestly failing and takes no parameters; the Agentic tool takes inline `code`. Not alias-compatible.

## 100. `fix_bugs` — Fix Bugs

- **Legacy class:** `FixBugsTool` (`FixBugs.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `fix_bugs` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Fixes bugs in Swift code."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}, "issue": {"type": "string"}}, "required": ["code", "issue"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"// Fixed code\n\(code)"` — the input code unchanged with a comment. Failure message (verbatim): `fix_bugs is unavailable: fixing a described bug needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns the input code unchanged with a comment, so nothing was changed.` Not a duplicate of `intel_autofix`: the ported tool is itself honestly failing and takes `path`; the Agentic tool takes inline `code` + `issue`. Not alias-compatible.

## 101. `generate_unit_tests` — Generate Unit Tests

- **Legacy class:** `GenerateUnitTestsTool` (`GenerateUnitTests.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `generate_unit_tests` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Generates unit tests for the provided code."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"import XCTest\nclass GeneratedTests: XCTestCase {}"` — a canned empty XCTestCase stub. Failure message (verbatim): `generate_unit_tests is unavailable: generating unit tests with meaningful assertions needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns a canned empty XCTestCase stub, so nothing is generated.` Not a duplicate of `intel_generate_tests`: the ported tool generates test stubs from a file `path` and writes them through `commit()`; the Agentic tool takes inline `code` and returns text. Not alias-compatible, and stub generation labelled as such is not an acceptable stand-in for LLM test generation.

## 102. `generate_integration_tests` — Generate Integration Tests

- **Legacy class:** `GenerateIntegrationTestsTool` (`GenerateIntegrationTests.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `generate_integration_tests` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Generates integration tests for the provided code."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"import XCTest\nclass GeneratedIntegrationTests: XCTestCase {}"` — a canned empty XCTestCase stub. Failure message (verbatim): `generate_integration_tests is unavailable: generating integration tests with meaningful assertions needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns a canned empty XCTestCase stub, so nothing is generated.` Not a duplicate of `intel_generate_tests` (as §101).

## 103. `generate_documentation` — Generate Documentation

- **Legacy class:** `GenerateDocumentationTool` (`GenerateDocumentation.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `generate_documentation` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Generates documentation for the provided code."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"/// Documentation for the provided code"`. Failure message (verbatim): `generate_documentation is unavailable: generating documentation for code needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns a canned "/// Documentation for the provided code" line, so nothing is generated.` Not a duplicate of `docstring_generator`: the ported tool takes a `declaration` header (+ `summary`) and renders a DocC comment; the Agentic tool takes arbitrary `code`. Not alias-compatible.

## 104. `generate_comments` — Generate Comments

- **Legacy class:** `GenerateCommentsTool` (`GenerateComments.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `generate_comments` with the full Legacy schema in `YcodeTools+AgenticCode.swift`; the handler always fails, naming the missing LLM provider (as §97).
- **Description (verbatim):** "Generates comments for the provided code."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`. No output schema.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Missing prerequisite (exact).** An LLM provider (OpenRouter / the configured Assist provider) wired for this tool in Ycode's MCP host.

**Notes.** Legacy behaviour: returns `"// Comments for the provided code"`. Failure message (verbatim): `generate_comments is unavailable: generating comments for code needs an LLM provider (OpenRouter / the configured Assist provider), and Ycode's MCP host has no LLM provider wired for this tool. Legacy's implementation only returns a canned "// Comments for the provided code" line, so nothing is generated.`

## 105. `detect_bugs` — Detect Bugs

- **Legacy class:** `DetectBugsTool` (`DetectBugs.swift`).
- **Disposition:** PORTED as `detect_bugs` in `YcodeTools+AgenticCode.swift` (deterministic subset).
- **Description (verbatim):** "Detects bugs in Swift code."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Output (structured).** `findingCount` (int), `findings` (string, `line <n> [<kind>] — <trimmed line>` per finding). Summary: `Bug scan (heuristic) of the supplied code: <n> finding(s).` + the listing, or `Bug scan (heuristic) of the supplied code: no bug patterns found.` Findings are heuristic leads, not confirmed bugs.

**Notes.** Legacy behaviour: `run` executes `/usr/bin/swiftlint lint --quiet` and returns swiftlint's stdout lines as "bugs" — but it never passes the supplied `code` anywhere (it lints the process working directory), so the tool ignores its own input. The swiftlint path is not a real implementation of "detect bugs in this code". Ported behaviour: a heuristic scan of the supplied code string itself. Per line (full-line `//` comments skipped; matches in strings otherwise still count): postfix force unwrap (`!` following an identifier, `)`, `]` or `}`, not part of `!=`, and not followed by `"` — punctuation inside a string literal, e.g. `"Hello, \(name)!"`, is not a force unwrap; boolean negation (`!flag`) is not flagged); `try!` → "force try (try!)", `as!` → "force cast (as!)" (checked before the force-unwrap pattern, whose `!` would otherwise also match the `y!` in `try!`); `fatalError(` / `preconditionFailure(`; empty `catch` block: `catch { … }` on one line, or a `catch`-opening line (`catch {`, `} catch {`, `} catch FooError {`) whose next non-blank line is a lone `}`. At most one finding per line for the force family (`try!` / `as!` / force unwrap); `fatalError` and empty `catch` are reported independently. Listing capped at 200 findings. Error cases: missing/blank `code` → `Missing code` (Legacy's message).

## 106. `explain_code` — Explain Code

- **Legacy class:** `ExplainCodeTool` (`ExplainCode.swift`).
- **Disposition:** PORTED as `explain_code` in `YcodeTools+AgenticCode.swift` (deterministic subset).
- **Description (verbatim):** "Explains code using AI."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}
```

**Output (structured).** `explanation` (string). The summary is the explanation itself.

**Notes.** Legacy behaviour: the one tool in this slice that is genuinely LLM-backed — it streams a chat completion from OpenRouter (`openai/gpt-4o-mini`, "Explain this code:\n…") and returns the explanation. No LLM provider is wired in Ycode's MCP host, so the LLM path cannot be ported. Ported behaviour: the deterministic subset the project already accepted for `intel_explain_code` (`YcodeTools+Planning.swift`, `explainCode`): the static structural explanation from `PlanningSupport.staticExplanation(of:at:)` applied to the supplied code — line count, imports, declared types, function names — with the explicit header "Static analysis of supplied code (no LLM explanation is available in Ycode's MCP host)." It names the code's structure; it does not understand what the code does. Not a duplicate of `intel_explain_code`: same purpose, but the ported tool takes a required `path` and the Agentic tool takes a required inline `code` — different parameter names, so no alias is valid. Error cases: missing/blank `code` → `Missing code` (Legacy's message).

## 107. `code_analysis` — Code Analysis

- **Legacy class:** `CodeAnalysisTool` (`CodeAnalysisTool.swift`).
- **Disposition:** PORTED as `code_analysis` in `YcodeTools+AgenticCode.swift` (real aggregate analysis).
- **Description (verbatim):** "Analyzes Swift code for potential issues, complexity, and architectural patterns."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"path": {"type": "string", "description": "The path to the file or directory to analyze."}}, "required": ["path"]}
```

**Output (structured).** `fileCount`, `totalLines`, `codeLines`, `commentLines`, `blankLines`, `functionCount`, `typeCount`, `decisionPoints`, `complexity` (string rating), `patterns` (comma-joined or "none detected"), `issueCount` (force-unwrap + fatalError + marker counts), `forceUnwrapCount`, `todoCount`, `issues` (newline-joined), `suggestions` (newline-joined). Summary mirrors Legacy's four-line shape with real values: `Analysis for <path>:` + files/lines, complexity, patterns, potential issues, suggestions. No Swift files → success with all counts 0 and complexity "Low".

**Notes.** Legacy behaviour: returns hardcoded mock text ("Complexity: Low", "Patterns: Observable, MVVM", "Potential Issues: None found.", "Suggestions: Consider adding documentation comments to public methods.") for any path — a fake, not ported. Ported behaviour: every number is computed from the scanned Swift files (the static-analysis per-tool enumerator: Swift files only, 300 KB cap, at most 5000, sorted by path; unreadable files skipped). Line classes per `count_file_lines`: blank; comment (trimmed line starts with `//`, `/*`, `*`, or `#`); otherwise code. Decision points: regex matches of `\b(if|for|while|guard|case|catch)\b|&&|\|\|`. Known heuristic quirk: the parameter label `for` counts as a branch (`greeting(for:)` contributes one point), as do the words in comments. Declarations: the `agenticCodeScanDeclarations` regex scan (see §108). Force-unwrap / `fatalError` / marker counts: the shared `agenticCodeBugFindings` / `agenticCodeTodoCount` scans (§105). Longest function: brace-depth spans from each `func` line (heuristic: braces in strings/comments shift spans, as in Legacy's `call_hierarchy` callee scan). Patterns detected from the text: SwiftUI (`import SwiftUI` or `: View`), Observable (`@Observable` / `ObservableObject`), MVVM (a declared type whose name ends in `ViewModel`), Actor (an `actor` declaration), Async/Await (`async` / `await`), Combine (`import Combine`), Testing (`import XCTest` / `import Testing`), SwiftData (`import SwiftData` / `@Model`). Complexity rating from the average decision points per function: < 3 Low, < 8 Moderate, else High (0 functions → Low). Suggestions derived from the numbers: replace force unwraps; resolve task markers; "Consider adding documentation comments to public methods." (Legacy's own suggestion, kept verbatim as a conditional) when comment lines are under 10% of all lines; decompose the longest function when it is ≥ 60 lines; otherwise "No major suggestions." Not a duplicate of `code_metrics_analyzer` / `complexity_analysis` / `code_summary`: the ported tools are narrower (metrics, complexity, or a one-line summary); `code_analysis` is an aggregate report with its own output shape. Error cases: missing/blank `path` → `Missing path argument` (Legacy's message); any `..` / escaping path → `Invalid path: path must stay inside the workspace and must not contain '..'.`; missing path → `Path not found: <path>`.

## 108. `code_index` — Code Index

- **Legacy class:** `CodeIndexTool` (`CodeIndex.swift`).
- **Disposition:** PORTED as `code_index` in `YcodeTools+AgenticCode.swift` (real in-memory index).
- **Description (verbatim):** "Indexes the code in a project."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Output (structured).** `fileCount`, `symbolCount`, `classCount`, `structCount`, `enumCount`, `protocolCount`, `actorCount`, `functionCount`, `symbols` (string, `Kind Name — rel:line` per entry). Summary keeps Legacy's message shape with real numbers: `Project code indexed successfully at <projectPath>: <S> symbols across <F> files.` + the per-kind breakdown + the listing.

**Notes.** Legacy behaviour: returns the canned string `"Project code indexed successfully at <projectPath>"` and builds no index — a fake, not ported. Ported behaviour: builds a real in-memory declaration index per call and reports the real counts. Enumeration is the static-analysis per-tool enumerator (Swift files only, 300 KB cap, at most 5000, sorted by path). Declarations are found by `agenticCodeScanDeclarations`: the type regex `^(?:public |private |internal |fileprivate |open )?(?:final )?(class|struct|enum|actor|protocol)\s+([A-Za-z0-9_]+)` anchored at the trimmed line start (mirroring Legacy's `extractDeclaredTypes`, plus `protocol`), and the function regex `\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)` (Legacy's `AssistGenerateTestsTool` pattern). Full-line comments are skipped; matches in strings still count. The index is not persisted and has no embeddings; it is rebuilt on every call. The symbol listing is capped at 200 entries, scan order. Not a duplicate of `source_graph_builder` / `extract_code_symbols`: the ported tools build a graph or extract one file's symbols; the Agentic tools build a project-wide declaration index with per-kind counts and a symbol listing. Error cases: missing/blank `projectPath` → `Missing projectPath` (Legacy's message); any `..` / escaping path → `Invalid path: path must stay inside the workspace and must not contain '..'.`; missing path → `Path not found: <projectPath>`.

## 109. `project_indexing` — Project Indexing

- **Legacy class:** `ProjectIndexingTool` (`ProjectIndexingTool.swift`).
- **Disposition:** PORTED as `project_indexing` in `YcodeTools+AgenticCode.swift` (real in-memory index).
- **Description (verbatim):** "Indexes the project to allow for fast semantic searches and relationship mapping."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"root_path": {"type": "string", "description": "The root path of the project to index."}}, "required": ["root_path"]}
```

**Output (structured).** Same keys as `code_index` (§108). Summary keeps Legacy's message shape with real numbers: `Project at <rootPath> has been indexed. <S> symbols found across <F> files.` + the per-kind breakdown + the listing. It does not enable semantic search by itself — there is no persisted index and no embedding store; see `semantic_code_search` (§95) for the search side.

**Notes.** Legacy behaviour: returns the hardcoded mock `"Project at <rootPath> has been indexed. 124 symbols found across 42 files."` — invented numbers, a fake, not ported. Ported behaviour: the same real in-memory index builder as `code_index` (§108), shared helper `agenticCodeBuildIndex`. The two tools are distinct Legacy tools with distinct parameter names (`projectPath` vs `root_path`) and distinct summary wording, so both are registered; they report identical counts for the same scope. Error cases: missing/blank `root_path` → `Missing root_path argument` (Legacy's message); any `..` / escaping path → `Invalid path: path must stay inside the workspace and must not contain '..'.`; missing path → `Path not found: <root_path>`.

## 110. `security_scan` — Security Scan

- **Legacy class:** `SecurityScanTool` (`SecurityScan.swift`).
- **Disposition:** PORTED as `security_scan` in `YcodeTools+AgenticCode.swift` (real secrets + endpoint scan).
- **Description (verbatim):** "Performs a security scan on the project."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Output (structured).** `findingCount`, `filesScanned`, `filesWithFindings`, `findings` (string, `rel:line [kind]` per finding). Summary: `Security scan of <projectPath>: <n> finding(s) in <m> file(s) (of <k> scanned).` + the listing, or `Security scan of <projectPath>: no hardcoded secrets or insecure endpoints found in <k> file(s).`

**Notes.** Legacy behaviour: returns the canned string `"Security scan report: 0 issues found"` without scanning anything — a fake, not ported. Ported behaviour: scans every file under the scope it can read as UTF-8 (all extensions; hidden files included — `.env` files are a common secret store; `.git` / `DerivedData` / `.build` / `build` / `Pods` / `node_modules` / `.swiftpm` / `.venv` skipped; files over 300 KB skipped; at most 5000 files, sorted by path) for two finding classes: hardcoded-secret assignments (case-insensitive `password` / `passwd` / `api key` / `secret` / `access token` / `private key` followed by `:` or `=` and a quoted value of at least 4 characters — findings report file:line:kind only and never output matched secret values, as `secrets_scan` does) and insecure `http://` endpoints (`http://localhost` and `http://127.0.0.1` excluded). Full-line comments are skipped for URLs (a commented URL is harmless) but not for secrets (a commented-out credential is still a leak). Listing capped at 200 findings. Not a duplicate of `security_audit_scanner` / `secrets_scan`: overlapping substance (secret / insecure-endpoint scanning), but the ported tools take `path` while the Agentic tool requires `projectPath` — different parameter names, so no alias is valid. Ported as distinct with its own scope and output shape. Error cases: missing/blank `projectPath` → `Missing projectPath` (Legacy's message); any `..` / escaping path → `Invalid path: path must stay inside the workspace and must not contain '..'.`; missing path → `Path not found: <projectPath>`.

## 111. `license_scan` — License Scan

- **Legacy class:** `LicenseScanTool` (`LicenseScan.swift`).
- **Disposition:** PORTED as `license_scan` in `YcodeTools+AgenticCode.swift` (real license-file + SPDX scan).
- **Description (verbatim):** "Scans the project for dependency licenses."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Output (structured).** `licenseFileCount`, `licenseFiles` (newline-joined relative paths), `spdxCount` (distinct identifiers), `spdxIdentifiers` (`ID ×count`, comma-joined), `dependencyCount`, `dependencies` (`name version` per line), `filesScanned` (source files whose headers were checked for SPDX identifiers).

**Notes.** Legacy behaviour: returns the canned string `"License report: All dependencies use permissive licenses"` without checking anything — a fake verdict, not ported. Ported behaviour: reports what it actually finds. License files: any file whose stem (case-insensitive) is `license`, `licence`, `copying`, `notice`, or `unlicense`. Each file's terms are classified from well-known phrases (Apache License, MIT License, GNU General/Lesser General Public License, Mozilla Public License, BSD License, The Unlicense) or reported as "unrecognised terms". SPDX identifiers: `SPDX-License-Identifier:` in the first 15 lines of Swift / C-family source files, counted per identifier. Dependencies: names and versions parsed from the first `Package.resolved` found under the scope (v1 pins `package` + `state.version` and v2/v3 pins `identity` + `version` both handled); absent when no `Package.resolved` exists. **Dependency license terms are not determined by this scan**: no SPDX database or network lookup is performed, and the tool never claims a dependency's license is permissive. The summary says so plainly. Not a duplicate of `dependency_licenses`: overlapping substance (dependency inventory for license review), but the ported tool takes no parameters while the Agentic tool requires `projectPath`, so no alias is valid. Error cases: missing/blank `projectPath` → `Missing projectPath` (Legacy's message); any `..` / escaping path → `Invalid path: path must stay inside the workspace and must not contain '..'.`; missing path → `Path not found: <projectPath>`.

## 112. `project_audit` — Project Audit

- **Legacy class:** `ProjectAuditTool` (`ProjectAudit.swift`).
- **Disposition:** PORTED as `project_audit` in `YcodeTools+AgenticCode.swift` (real aggregate audit).
- **Description (verbatim):** "Performs a full audit of the project."
- **Capability:** safeRead-equivalent. **Risk:** `safeRead`. **Required permission:** `none`. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{"type": "object", "properties": {"projectPath": {"type": "string"}}, "required": ["projectPath"]}
```

**Output (structured).** `swiftFileCount`, `totalLines`, `testFileCount`, `todoCount`, `forceUnwrapCount`, `secretFindingCount`, `hasReadme` (bool), `hasLicense` (bool), `checkCount` (7), `failureCount`, `findings` (string, one `PASS` / `FAIL` line per check). Summary: `Project audit for <projectPath>:` + counts + pass/fail totals + the check lines.

**Notes.** Legacy behaviour: returns the canned string `"Full project audit report for <projectPath>"` and audits nothing — a fake, not ported. Ported behaviour: seven real checks over the real file counts (Swift enumeration as in §107; counts from the shared `agenticCodeBugFindings` / `agenticCodeTodoCount` / `agenticCodeSecretFindings` scans): (1) README present (a `README*` entry at the project root); (2) license file present (a `LICENSE*` / `LICENCE*` / `COPYING*` entry at the project root); (3) tests present (at least one `*Tests.swift` file or a file under a `Tests/` directory); (4) no task markers (marker count 0); (5) no force unwraps (force-unwrap / `try!` / `as!` count 0); (6) no hardcoded secrets (secret / insecure-endpoint count 0); (7) build system present (`Package.swift` or an `.xcodeproj` at the project root). Each check reports `PASS` / `FAIL` with a one-line detail. The audit is the checks listed here — it does not build, run tests, or review code. Error cases: missing/blank `projectPath` → `Missing projectPath` (Legacy's message); any `..` / escaping path → `Invalid path: path must stay inside the workspace and must not contain '..'.`; missing path → `Path not found: <projectPath>`.

## 113. `parse_json` — Parse JSON

- **Legacy class:** `ParseJSONTool` (`ParseJSON.swift`).
- **Disposition:** PORTED as `parse_json` in `YcodeTools+AgenticData.swift` (`agenticDataTools`).
- **Description (verbatim):** "Parses a JSON string."
- **Capability:** general. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"json": {"type": "string"}}, "required": ["json"]}
```

**Output (success).** Returns the parsed object as structured data (`result`) instead of Legacy's `"\(result)"` string.

**Notes.** Legacy parsed with `JSONSerialization` and required the top level to be a dictionary, returning it as a stringified map. Port: `agenticDataParseJSON`. Parses the `json` argument for real with `AnyJSON.parse`; keeps Legacy's dictionary-only rule (a non-object top level fails with "JSON is not a dictionary"). Invalid JSON fails with the decoder's message. Not a duplicate of `json_validate` / `json_validator_tool`: the ported tools validate a JSON *file* (`path`); `parse_json` parses an inline JSON *string* (`json`). Different input, different behaviour.

## 114. `parse_yaml` — Parse YAML

- **Legacy class:** `ParseYAMLTool` (`ParseYAML.swift`).
- **Disposition:** PORTED as `parse_yaml` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Parses a YAML string."
- **Capability:** general. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"yaml": {"type": "string"}}, "required": ["yaml"]}
```

**Output (success).** Returns the parsed value as structured data (`parsed`, plus `topLevelKeys`).

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Parsed YAML (simulated)". Port: `agenticDataParseYAML`, backed by `AgenticDataYAMLParser`. A real YAML subset parser: block mappings and sequences by indentation, plain / single- / double-quoted scalars, `null` / booleans / integers / doubles, and flow collections (`[a, b]`, `{k: v}`). **Limits (honest, not silent):** anchors, aliases, tags, block scalars (`|`, `>`), tab indentation, and duplicate mapping keys are rejected with the line number and the exact construct. `yes` / `no` / `on` / `off` are strings (YAML 1.2 core schema), not booleans. Multi-document streams are not supported beyond skipping `---` / `...` separators. There is no full YAML parser in Ycode (Wave 5's `yaml_parser_tool` / `yaml_validate` are the same heuristic family, file-based). Not a duplicate of `yaml_parser_tool` / `yaml_validate`: the ported tools validate a YAML *file* (`path`); `parse_yaml` parses an inline YAML *string* (`yaml`).

## 115. `parse_xml` — Parse XML

- **Legacy class:** `ParseXMLTool` (`ParseXML.swift`).
- **Disposition:** PORTED as `parse_xml` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Parses an XML string."
- **Capability:** general. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"xml": {"type": "string"}}, "required": ["xml"]}
```

**Output (success).** Returns the root element as structured data: `tag`, `attributes`, `children` (recursive), and `text` (only when non-blank).

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Parsed XML (simulated)". Port: `agenticDataParseXML`, backed by `AgenticDataXMLTreeBuilder` (Foundation `XMLParser`). Malformed XML fails with the parser's error; a document with no root element fails explicitly.

## 116. `parse_markdown` — Parse Markdown

- **Legacy class:** `ParseMarkdownTool` (`ParseMarkdown.swift`).
- **Disposition:** PORTED as `parse_markdown` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Parses a Markdown string."
- **Capability:** general. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"markdown": {"type": "string"}}, "required": ["markdown"]}
```

**Output (success).** Returns `blocks` (headings with level, fenced code blocks with language, flat lists with `ordered`, blockquotes, rules, paragraphs), `headings`, and `links` (links and images with `kind`, `text`, `url`).

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Parsed Markdown (simulated)". Port: `agenticDataParseMarkdown`, backed by `agenticDataParseMarkdown` (structural block parser). Soft line breaks join with a space, as Markdown renders them. **Limits:** tables, reference-style links, HTML blocks, and nested emphasis are not parsed — their lines become paragraphs. Nested list items are flattened into the list's `items`.

## 117. `sql_query` — SQL Query

- **Legacy class:** `SQLQueryTool` (`SQLQuery.swift`).
- **Disposition:** PORTED as `sql_query` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Executes an SQL query."
- **Capability:** general. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"query": {"type": "string"}, "databasePath": {"type": "string"}}, "required": ["query", "databasePath"]}
```

**Output (success).** Returns `rows` (parsed JSON array) and `rowCount`; an empty result is zero rows (that is what `sqlite3 -json` prints).

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Result of query: …". Port: `agenticDataSQLQuery`. Runs the query for real against SQLite via the `sqlite3` CLI (`-json -readonly`, fixed argument vector, 120-second timeout). The database path is workspace-confined (`resolveFileWritingPath`) and must exist. **Deliberate deviation:** read-only statements only (`SELECT`, `WITH`, `EXPLAIN`, after stripping leading SQL comments). Anything else fails before running, and the `-readonly` open is a backstop. Writes go through `database_migration` (§119), never through this tool. When the `sqlite3` CLI is not installed, the tool fails honestly naming it.

## 118. `database_schema_inspector` — Database Schema Inspector

- **Legacy class:** `DatabaseSchemaInspectorTool` (`DatabaseSchemaInspector.swift`).
- **Disposition:** PORTED as `database_schema_inspector` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Inspects the schema of a database."
- **Capability:** general. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"databasePath": {"type": "string"}}, "required": ["databasePath"]}
```

**Output (success).** Returns `tables` (with columns and foreign keys), `views`, `indexes`, and `tableCount`.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Schema for …". Port: `agenticDataDatabaseSchemaInspector`. Reads the schema for real via the `sqlite3` CLI (`-json -readonly`): `sqlite_master` rows (excluding `sqlite_%` internals), then per-table `PRAGMA table_info` (columns: name, type, notNull, primaryKey, defaultValue) and `PRAGMA foreign_key_list` (table, from, to, onUpdate, onDelete). A file that is not a SQLite database fails with sqlite3's own error ("file is not a database").

## 119. `database_migration` — Database Migration

- **Legacy class:** `DatabaseMigrationTool` (`DatabaseMigrationTool.swift`).
- **Disposition:** PORTED as `database_migration` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Applies a database migration."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** approval-gated through `approveFileWritingChange` before anything runs; the changed database is reported with `noteFileWritingChanged`.

```json
{"type": "object", "properties": {"databasePath": {"type": "string"}, "migrationPath": {"type": "string"}}, "required": ["databasePath", "migrationPath"]}
```

**Output (success).** Returns `database` and `migration` (workspace-relative).

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Migration applied to …". Port: `agenticDataDatabaseMigration`. Applies the migration file for real via `sqlite3 -bail <db> ".read <path>"` (fixed argument vector; the path is quoted for the dot-command, spaces survive). The database file is created when it does not exist; the migration file must exist and be non-empty. **Caveat:** `-bail` stops at the first failing statement, but the file's own transaction handling applies — a migration file without `BEGIN` can leave a partial apply behind on error. The port does not wrap the file in a transaction, since a file that already contains `BEGIN` / `COMMIT` would then fail.

## 120. `read_environment_variables` — Read Environment Variables

- **Legacy class:** `ReadEnvironmentVariablesTool` (`ReadEnvironmentVariables.swift`).
- **Disposition:** PORTED as `read_environment_variables` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Reads environment variables."
- **Capability:** `systemExecution`. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {}}
```

**Output (success).** Returns the sorted variable **names** (`names`) and the `count`.

**Notes.** Legacy returned `ProcessInfo.processInfo.environment` as `KEY=value` lines. Port: `agenticDataReadEnvironmentVariables`. **Deliberate deviation (secrets):** values are never reported. Environment values routinely contain secrets (API keys, tokens), so the port follows the Wave 6 `secrets_scan` precedent — report the label (here, the name) only. Legacy's `KEY=value` dump is not reproduced. Not a duplicate of `environment_variable_manager`: the ported tool manages workspace `.env` *files* and requires `action`; the Agentic tool reads the host process environment and takes no arguments. Calling the target with no arguments fails its required `action`.

## 121. `update_environment_variables` — Update Environment Variables

- **Legacy class:** `UpdateEnvironmentVariablesTool` (`UpdateEnvironmentVariables.swift`).
- **Disposition:** PORTED as `update_environment_variables` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Updates environment variables."
- **Capability:** `systemExecution`. **Risk:** `safeMutation`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `terminalApproveChange` (the Wave 4 shape for non-file operations).

```json
{"type": "object", "properties": {"variables": {"type": "object", "additionalProperties": {"type": "string"}}}, "required": ["variables"]}
```

**Output (success).** The result names the variables set, never their values.

**Notes.** Legacy called `setenv` for each entry with no gate. Port: `agenticDataUpdateEnvironmentVariables`. Validates every entry first (non-empty names, no `=` or NUL; string values only), gates through approval, then calls `setenv` in the host process — children spawned afterwards inherit the new values. Unlike `environment_variable_manager` (Assist, Wave 4), this edits the live process environment, not a `.env` file. Not a duplicate of `environment_variable_manager`: the Agentic tool requires `variables` (an object map), which is not a parameter of the target at all.

## 122. `manage_secrets` — Manage Secrets

- **Legacy class:** `ManageSecretsTool` (`ManageSecrets.swift`).
- **Disposition:** PORTED as `manage_secrets` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Manages secrets in the keychain."
- **Capability:** general. **Risk:** `safeMutation`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`. **Gate:** `save` is approval-gated.

```json
{"type": "object", "properties": {"action": {"type": "string", "enum": ["save", "get"]}, "key": {"type": "string"}, "value": {"type": "string"}}, "required": ["action", "key"]}
```

**Output (success).** `save` reports "Secret saved"; `get` reports only whether a secret exists for the key.

**Notes.** Legacy saved through `KeychainService.shared` and `get` returned the stored value. Port: `agenticDataManageSecrets`, backed by Ycode's `SecretStore` (`defaultSecretStore()`: login keychain on macOS, a 0600 file under `~/.config/ycode/secrets` on Linux). **Deliberate deviation (secrets):** `get` never returns the value — a secret value must never appear in tool output. `save` without a `value` fails in the port (Legacy silently reported "Secret saved" without saving anything). An unknown action keeps Legacy's "No result" answer. **Test seam:** `YcodeMCPHost.agenticDataTestSecretStore` (a `SecretStore?`, unset in production) lets tests use a `MemorySecretStore` so no real keychain or config file is touched.

## 123. `open_browser` — Open Browser

- **Legacy class:** `OpenBrowserTool` (`OpenBrowser.swift`).
- **Disposition:** PORTED as `open_browser` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Opens a URL in the default browser."
- **Capability:** `systemExecution`. **Risk:** `externalSideEffect`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`. **Gate:** approval-gated through `terminalApproveChange`.

```json
{"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}
```

**Output (success).** Returns Legacy's "Opened …" message.

**Notes.** Legacy ran `/usr/bin/open [url]` via a process runner and returned "Opened …". Port: `agenticDataOpenBrowser`. Approval-gated, then `/usr/bin/open [url]` on macOS or `/usr/bin/xdg-open [url]` on Linux (fixed argument vector). **Deliberate deviation:** http(s) URLs only. Legacy passed any string to `open`; the port validates the scheme and a non-empty host first. When `xdg-open` is not installed on Linux, the tool fails honestly naming it.

## 124. `browser_automation` — Browser Automation

- **Legacy class:** `BrowserAutomationTool` (`BrowserAutomation.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `browser_automation` with the full Legacy schema in `YcodeTools+AgenticData.swift`; the handler validates `script` and then always fails naming the missing prerequisite.
- **Description (verbatim):** "Executes a browser automation script."
- **Capability:** `systemExecution`. **Risk:** `externalSideEffect`. **Required permission:** none. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`.

```json
{"type": "object", "properties": {"script": {"type": "string"}}, "required": ["script"]}
```

**Missing prerequisite (exact).** A browser automation driver (a WebDriver or Playwright session driving a real browser) in Ycode's MCP host.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Browser automation script executed". Failure message: "browser_automation needs a browser automation driver (a WebDriver or Playwright session driving a real browser), which Ycode's MCP host does not have; no script was executed." There is no automation driver to wire it to, and the Legacy stub never executed anything either, so nothing real was lost.

## 125. `ui_inspector` — UI Inspector

- **Legacy class:** `UIInspectorTool` (`UIInspector.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `ui_inspector` with the full Legacy schema in `YcodeTools+AgenticData.swift`; the handler always fails naming the missing prerequisite.
- **Description (verbatim):** "Inspects the UI hierarchy."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** accessibility (would be required). **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {}}
```

**Missing prerequisite (exact).** A live target application with accessibility access to inspect its UI hierarchy, in Ycode's MCP host.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "UI Inspector data hierarchy". Failure message: "ui_inspector needs a live target application with accessibility access to inspect its UI hierarchy, which Ycode's MCP host does not have; no UI was inspected." The headless MCP host has no target application and no UI session; the Assist `accessibility_audit` / `accessibility_audit_scanner` tools (Wave 6) audit project source statically and are a different behaviour, not a substitute. Not servable by alias of `use_app`: the ported tool requires `app_identifier` + `action`; the Agentic tool takes no arguments and names no target application.

## 126. `accessibility_inspector` — Accessibility Inspector

- **Legacy class:** `AccessibilityInspectorTool` (`AccessibilityInspector.swift`).
- **Disposition:** HONESTLY-FAILING — registered as `accessibility_inspector` with the full Legacy schema in `YcodeTools+AgenticData.swift`; the handler always fails naming the missing prerequisite.
- **Description (verbatim):** "Inspects accessibility properties."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** accessibility (would be required). **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {}}
```

**Missing prerequisite (exact).** A live target application and accessibility permission to read its accessibility properties, in Ycode's MCP host.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Accessibility properties for active window". Failure message: "accessibility_inspector needs a live target application and accessibility permission to read its accessibility properties, which Ycode's MCP host does not have; no accessibility properties were read." Same reasoning as `ui_inspector` (§125).

## 127. `performance_profiler` — Performance Profiler

- **Legacy class:** `PerformanceProfilerTool` (`PerformanceProfiler.swift`).
- **Disposition:** PORTED as `performance_profiler` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Profiles the performance of a process."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"pid": {"type": "integer"}}, "required": ["pid"]}
```

**Output (success).** Returns `pid`, `cpuPercent`, `rssBytes`, `vszBytes`, `command` — a single snapshot, not a time series.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Performance metrics for process …". Port: `agenticDataPerformanceProfiler`. Takes a single live snapshot with `/bin/ps -o pid=,%cpu=,rss=,vsz=,%mem=,comm= -p <pid>` (same columns on macOS and Linux; `rss` / `vsz` are KiB). A missing process, an invisible pid, or a missing `ps` fails honestly; the summary says it is a single snapshot, not a time series. This is real measurement, not Legacy's hardcoded string — but it is not a sampling profiler (no call tree, no time series); Ycode's `YcodeProfiler` / Gauge stack is a separate, deeper system and is not wired to this tool. Not a duplicate of `process_monitor_tool`: the ported tool takes an optional `filter` (process-name substring) and lists processes; the Agentic tool requires `pid` (integer), which the target does not accept.

## 128. `memory_profiler` — Memory Profiler

- **Legacy class:** `MemoryProfilerTool` (`MemoryProfiler.swift`).
- **Disposition:** PORTED as `memory_profiler` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Profiles the memory usage of a process."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"pid": {"type": "integer"}}, "required": ["pid"]}
```

**Output (success).** Returns `pid`, `rssBytes`, `vszBytes`, `memPercent`, `command` — a single live snapshot (as §127).

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Memory usage data for process …". Port: `agenticDataMemoryProfiler`. Same live `ps` snapshot as §127 (shared `agenticDataSampleProcess`). Same honest-failure behaviour for missing processes and missing `ps`. Not a duplicate of `process_monitor_tool` (as §127).

## 129. `network_inspector` — Network Inspector

- **Legacy class:** `NetworkInspectorTool` (`NetworkInspector.swift`).
- **Disposition:** PORTED as `network_inspector` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Inspects network traffic."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {}}
```

**Output (success).** Returns a snapshot of the active connection table as `connections` (`protocol`, `local`, `foreign`, `state`), `connectionCount`, and `source`, capped at 200 rows.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Network traffic analysis". Port: `agenticDataNetworkInspector`. Returns a snapshot of the active connection table — `netstat -an` when present, else `ss -tan` (fixed argument vectors). The summary states plainly that this is a connection-table snapshot, not packet capture: live traffic content is not available in Ycode's MCP host (capture would need a privileged capture backend). When neither `netstat` nor `ss` is installed, the tool fails honestly naming both. Not a duplicate of `use_system` (`network_interfaces`, `listening_sockets`): `use_system` requires `operation` and reports interface/socket listings; `network_inspector` takes no arguments and its Legacy purpose is traffic inspection. Different parameters and different behaviour.

## 130. `crash_analyzer` — Crash Analyzer

- **Legacy class:** `CrashAnalyzerTool` (`CrashAnalyzer.swift`).
- **Disposition:** PORTED as `crash_analyzer` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Analyzes crash logs."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"logPath": {"type": "string"}}, "required": ["logPath"]}
```

**Output (success).** Returns `hasException` and `frameCount`, with a summary of exception type, termination reason, crashed thread, and top blamed frames.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Analysis of crash log at …". Port: `agenticDataCrashAnalyzer`. Parses the crash log for real by reusing Wave 6's `testingParseCrashLog` (same parser as `crash_log_parse`, which takes `path`; this tool takes `logPath`, so it is a distinct registration, not an alias). A log with no recognised crash metadata fails ("Expected .crash or .ips format").

## 131. `symbolicate_crash_logs` — Symbolicate Crash Logs

- **Legacy class:** `SymbolicateCrashLogsTool` (`SymbolicateCrashLogs.swift`).
- **Disposition:** PORTED as `symbolicate_crash_logs` in `YcodeTools+AgenticData.swift`.
- **Description (verbatim):** "Symbolicates crash logs."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** none. **MCP annotations:** `.read`.

```json
{"type": "object", "properties": {"logPath": {"type": "string"}, "dsymPath": {"type": "string"}}, "required": ["logPath", "dsymPath"]}
```

**Output (success).** Returns `symbolicatedFrames` (`address`, `symbol`) and `frameCount`. No file is written: the symbolicated frames are returned as data.

**Notes.** Legacy's `run` was a stub returning the hardcoded string "Symbolicated crash log". Port: `agenticDataSymbolicateCrashLogs`. On macOS it symbolicates for real via `atos`: the dSYM's DWARF binary is resolved (`Contents/Resources/DWARF/<name>` inside a `.dSYM` bundle, or the file itself when a plain file is passed; when several DWARF binaries are present, the one matching an image name in the log wins, else the tool fails listing them); image load addresses and architectures come from the log's Binary Images section; frames belonging to the dSYM's binary are collected from the log's frame lines and passed to one `atos -o <binary> -arch <arch> -l <loadAddress> <addr…>` call. A log with no Binary Images section, a dSYM whose binary has no image in the log, or a missing `atos` fails honestly; a log with no frames for the dSYM's binary reports that nothing was symbolicated. On Linux the handler fails honestly naming the missing `atos` (Xcode command line tools).

## 132. `take_screenshot` — Take Screenshot

- **Legacy class:** `TakeScreenshotTool` (`TakeScreenshot.swift`).
- **Disposition:** DUPLICATE-OF `take_screenshot` — the ID is already a registered MCP tool (the Wave 4 port of Assist's `AssistTakeScreenshotTool` in `YcodeTools+Terminal.swift`), so no second registration exists. No code was written for the Agentic ID in this slice.
- **Description (verbatim, Agentic):** "Takes a screenshot and saves it to a path."
- **Capability:** as the served tool. **Risk:** as the served tool (`writes: true`). **Required permission:** none. **MCP annotations:** as the served tool.

```json
{"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}
```

**Notes.** Legacy Agentic behaviour: ran `/usr/sbin/screencapture [path]`. Served tool: `take_screenshot`, description "Captures the user's entire screen or a user-selected screen region, produces a valid PNG image, and makes the resulting image available to the active AI model for visual analysis.", parameters `capture_mode` / `display_id` / `include_cursor` / `image_format` / `purpose` (all optional), fullscreen only (region honestly unavailable), capture via ScreenCaptureKit, saved as a workspace artifact under `.assist_temp/artifacts/`, `writes: true`. **Parameter delta:** the Agentic tool takes `path` (required); the served tool takes no `path` and chooses the artifact path itself. A caller that needs a screenshot at a specific path cannot express that through the served tool; that gap is recorded here, not papered over. Recorded in the param-caveat register in `agentic-tools.md`.

## 133. `ai_context_memory` — AI Context Memory

- **Legacy class:** `AIContextMemoryTool` (`AIContextMemory.swift`).
- **Disposition:** PORTED as `ai_context_memory` in `YcodeTools+AgenticPlanning.swift` (`agenticPlanningTools`).
- **Description (verbatim):** "Manages AI context memory."
- **Capability:** memory. **Risk:** `safeMutation` (in-memory graph mutation; `writes: true`, not idempotent — `store` appends). **Required permission:** none (no filesystem access; the graph is host memory). **Gate:** server-level read-only refusal only; no file change to propose, so no `commit()` / `approve()` call (the `mem_store` / `mem_context_snapshot` precedent).

```json
{ "type": "object",
  "properties": { "action": { "type": "string" }, "data": { "type": "string" } },
  "required": ["action"] }
```

**Output (structured).** `{action, entries: [string], count}`.

**Notes.** Legacy behaviour: `run(action:data:)` returns `"Memory \(action)ed"`; nothing is stored, retrieved, or cleared. Port: real behaviour backed by Wave 4's `YcodeMemoryGraphStore` (per-workspace, process-lifetime, never persisted), under the key `ai_context_memory`, holding a JSON array of entries. Actions: `store` (requires `data`; appends), `retrieve` / `list` (return the entries), `clear` (empties the list). Unknown actions fail with the supported list. Summaries keep Legacy's `"Memory \(action)ed"` shape: `"Memory stored"`, `"Memory retrieved"`, `"Memory listed"`, `"Memory cleared"`. Deviation: Legacy accepts any `action` string and echoes it without doing anything. The port defines the real vocabulary and fails unknown actions instead of echoing a fake result.

## 134. `task_planner` — Task Planner

- **Legacy class:** `TaskPlannerTool` (`TaskPlanner.swift`).
- **Disposition:** PORTED as `task_planner` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Plans tasks to achieve a goal."
- **Capability:** planning. **Risk:** `safeMutation` (`writes: true`, not idempotent — mints a fresh plan on every call). **Required permission:** none. **Gate:** server-level read-only refusal only; no file change to propose (the `intel_plan_task` precedent).

```json
{ "type": "object",
  "properties": { "goal": { "type": "string" } },
  "required": ["goal"] }
```

**Output (structured).** `{planId, steps, taskCount, tasks: [{id, title, status}]}`. The `tasks` array is additive — Legacy defines no output schema — and is what makes the plan addressable by `checklist_plan` (§141) / `progress_tracker` (§136).

**Notes.** Legacy behaviour: `run(goal:)` returns `["Step 1 for \(goal)"]`. Port: splits the goal the way Wave 4's `intel_plan_task` does (clauses separated by `, . ;` or newlines, numbered; a generic four-step plan — Analyse / Implement / Validate / Summarise — when the goal has no clauses), mints a `planId` (UUID), and stores the plan in the slice's `AgenticPlanningPlanStore` (per-workspace, process-lifetime) with one queued task per step, so `checklist_plan` / `progress_tracker` can work on it. The steps are additionally recorded in Wave 4's `PlanningPlanStore` under `"plan:<planId>"`, so `intel_breakdown_task` can break a `task_planner` plan down. Why not a duplicate of `intel_plan_task`: same behaviour family (natural language → plan steps), but the required parameter differs (`goal` vs `task`), so an alias would fail validation — aliases pass arguments through unchanged and `Schema.object` rejects unknown keys. Ported as distinct.

## 135. `todo_manager` — Todo Manager

- **Legacy class:** `TodoManagerTool` (`TodoManager.swift`).
- **Disposition:** PORTED as `todo_manager` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Manages a todo list."
- **Capability:** planning. **Risk:** `safeMutation` (`writes: true`, not idempotent — `add` appends). **Required permission:** `fileSystem` (workspace file write). **Gate:** `commit()` before every write.

```json
{ "type": "object",
  "properties": { "action": { "type": "string" }, "todo": { "type": "string" } },
  "required": ["action"] }
```

**Output (structured).** `{action, todos: [{text, completed, createdAt}], count}`.

**Notes.** Legacy behaviour: `run(action:todo:)` returns `["Todo list updated"]`; nothing is stored. Port: a real per-workspace todo list in `<workspace>/.assist_temp/memory/todos.json` (the Wave 4 memory-directory pattern; pretty-printed, sorted-key JSON of `{text, completed, createdAt}`), written through `commit()`. Actions: `add` (requires `todo`), `list`, `complete` (requires `todo`; exact match, else case-insensitive), `remove` (same matching), `clear`. Completing or removing a missing todo fails. Unknown actions fail. Mutations keep Legacy's `"Todo list updated"` wording as their summary prefix. Why not a duplicate of `todo_scan` / `todo_fixme_scanner`: those scan source files for outstanding-task comments; this manages a free-standing todo list. Different behaviour entirely.

## 136. `progress_tracker` — Progress Tracker

- **Legacy class:** `ProgressTrackerTool` (`ProgressTracker.swift`).
- **Disposition:** PORTED as `progress_tracker` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Tracks the progress of a task."
- **Capability:** planning. **Risk:** `safeRead` (read-only, idempotent). **Required permission:** none.

```json
{ "type": "object",
  "properties": { "taskID": { "type": "string" } },
  "required": ["taskID"] }
```

**Output (structured).** `{taskID, progress: number 0.0–1.0, status}`.

**Notes.** Legacy behaviour: `run(taskID:)` returns the hardcoded `0.75`; the handler formats `"Progress for \(taskID): \(progress * 100)%"`. Port: computes real progress from the slice plan store. A plan ID reports the fraction of its tasks complete (`completed` = 1, `in_progress` = 0.5, `queued` / `failed` = 0); a task ID reports that task's own progress and status. An unknown ID fails with `"No task or plan found with ID '…'"` — no progress is invented. The summary keeps Legacy's format: `"Progress for <taskID>: <progress * 100>%"`. Why not a duplicate of `session_progress_report`: that tool summarises engineering phases and the agent-notes save time; this tracks one plan/task by ID. Different behaviour.

## 137. `checkpoint_creator` — Checkpoint Creator

- **Legacy class:** `CheckpointCreatorTool` (`CheckpointCreator.swift`).
- **Disposition:** PORTED as `checkpoint_creator` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Creates a checkpoint of the current state."
- **Capability:** planning. **Risk:** `safeMutation` (`writes: true`, not idempotent — mints a fresh checkpoint on every call). **Required permission:** `fileSystem` (writes outside the workspace, into Application Support). **Gate:** `approveChangeWithoutFile()` before copying (the Wave 7 snapshot precedent — `commit()` does not apply outside the workspace); the server-level read-only refusal applies first.

```json
{ "type": "object",
  "properties": { "description": { "type": "string" } },
  "required": ["description"] }
```

**Output (structured).** `{checkpoint_id, description}`.

**Notes.** Legacy behaviour: `run(description:)` returns `"Checkpoint '\(description)' created"`; nothing is captured. Port: a real checkpoint — a full-tree copy of the workspace into Application Support `YcodeCheckpoints/<uuid>/files` plus `metadata.json` (`id`, `timestamp`, `description`, `rootPath`), the Wave 7 `project_snapshot` layout in a directory of its own. A partial checkpoint is removed on failure. The summary is Legacy's verbatim: `"Checkpoint '<description>' created"`. Why not a duplicate of / alias to `project_snapshot`: the parameter names differ (`description`, required, vs `message`, optional), so an alias would fail validation — `description` is not a `project_snapshot` parameter and `Schema.object` rejects unknown keys. The stores are also separate by design, so a checkpoint can never be mistaken for a project snapshot (and `rollback_changes` refuses snapshot IDs). The behaviour is the same mechanism (full-tree copy) under a distinct, task-scoped identity: a checkpoint is a named restore point created during a task; a snapshot is a general project snapshot.

## 138. `rollback_changes` — Rollback Changes

- **Legacy class:** `RollbackChangesTool` (`RollbackChanges.swift`).
- **Disposition:** PORTED as `rollback_changes` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Rolls back changes to a specified checkpoint."
- **Capability:** planning. **Risk:** `potentiallyDestructive` (`writes: true`, destructive — replaces all workspace files). **Required permission:** `fileSystem`. **Gate:** explicit `MCPChange` + `approve()` before any deletion; the server-level read-only refusal applies first.

```json
{ "type": "object",
  "properties": { "checkpointID": { "type": "string" } },
  "required": ["checkpointID"] }
```

**Output (structured).** `{checkpoint_id}`.

**Notes.** Legacy behaviour: `run(checkpointID:)` returns `"Changes rolled back to \(checkpointID)"`; nothing is restored. Port: restores a checkpoint from the slice's own `YcodeCheckpoints/` store: verifies the checkpoint exists and that its recorded `rootPath` matches the current workspace (a checkpoint from another workspace fails), then — after an explicit `MCPChange` + `approve()` (the Wave 7 `project_restore` shape) — replaces every file in the workspace with the checkpoint's copy. An unknown ID fails and names `project_restore` for `project_snapshot` snapshots. The summary is Legacy's verbatim: `"Changes rolled back to <checkpointID>"`. Why not a duplicate of / alias to `project_restore`: the parameter name differs (`checkpointID` vs `snapshot_id`), so an alias would fail validation. The stores are separate by design (see §137). This is also NOT Wave 6's `safe_undo`, which is honestly-failing because it needs a previous-snapshot store the host does not keep; `rollback_changes` has its own store (the checkpoints `checkpoint_creator` writes), so it can genuinely restore.

## 139. `ask_user` — Ask User

- **Legacy class:** not named in the source material (source file `AskUser.swift`).
- **Disposition:** ALREADY-SERVED → `plan-AskUser` (alias, pre-existing in `MCPServer.toolAliases`, verified live). No code was written for this ID in Wave 8. See the param caveat below and the param-caveat register in `agentic-tools.md`.
- **Description (verbatim):** "Asks the user a clarifying question."
- **Capability:** planning. **Risk:** `safeRead` (the target never blocks and writes nothing). **Required permission:** none.

```json
{ "type": "object",
  "properties": {
    "question": { "type": "string" },
    "input_type": { "type": "string", "enum": ["text", "selection"] },
    "options": { "type": "array", "items": { "type": "string" } } },
  "required": ["question", "input_type"] }
```

**Notes.** Legacy behaviour: `execute` returns `"Awaiting user response..."`; it blocks in Legacy (native macOS question UI, up to 300 s). Served tool: the Wave 4 `plan-AskUser` tool never blocks and returns a pending handoff payload. **Caveat — parameter mismatch:** the Agentic schema is NOT a subset of `plan-AskUser`'s schema. The Agentic caller passes `question`, `input_type`, `options`; `plan-AskUser` requires `question`, `allowsMultipleAnswers`, `choices`. An Agentic-style call therefore fails validation (`allowsMultipleAnswers` / `choices` missing; `input_type` / `options` rejected as unknown keys). The alias is Legacy's own registry alias, kept as-is; if Agentic-shaped calls are wanted to work, that needs a schema-level decision (e.g. a distinct `ask_user` port or an alias-time argument mapping), not a silent rename.

## 140. `questions_handle` — Questions Handle

- **Legacy class:** `QuestionHandlerTool` (`QuestionHandler.swift`).
- **Disposition:** PORTED as `questions_handle` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Asks multiple clarifying questions before starting work."
- **Capability:** planning. **Risk:** `safeRead` (read-only, idempotent). **Required permission:** none.

```json
{ "type": "object",
  "properties": {
    "questions": { "type": "array",
      "items": { "type": "object",
        "properties": {
          "id": { "type": "string" },
          "prompt": { "type": "string" },
          "input_type": { "type": "string", "enum": ["text", "selection"] },
          "options": { "type": "array", "items": { "type": "string" } } },
        "required": ["id", "prompt", "input_type"] } } },
  "required": ["questions"] }
```

**Output (structured).** `{questionSetId, questions: [{id, prompt, input_type, options}], status: "pending"}`.

**Notes.** Legacy behaviour: `execute` returns `"Awaiting user response to question set..."`; it blocks in Legacy. Port: the Wave 4 `plan-AskUser` precedent applied to a batch: validates every question (`id`, `prompt`, `input_type` required; `input_type` must be `text` or `selection`; a `selection` needs non-empty `options`), then returns the question set as a structured pending handoff (`questionSetId`, the questions as given, `status: "pending"`) and returns immediately. The caller presents the questions to the user and feeds the answers back; the tool never waits and never hangs. Why not a duplicate of `plan-AskUser`: that tool asks one question with `choices` / `allowsMultipleAnswers`; this one takes an array of questions with per-question `input_type`. The parameters are incompatible (`questions` vs `question` / `allowsMultipleAnswers` / `choices`), so no alias is valid.

## 141. `checklist_plan` — Checklist Plan

- **Legacy class:** `ChecklistPlanTool` (`ChecklistPlan.swift`).
- **Disposition:** PORTED as `checklist_plan` in `YcodeTools+AgenticPlanning.swift`.
- **Description (verbatim):** "Updates the execution plan checklist."
- **Capability:** planning. **Risk:** `safeMutation` (`writes: true`, idempotent — upserting the same tasks twice is a no-op). **Required permission:** none (in-memory plan store). **Gate:** server-level read-only refusal only; no file change to propose (the `intel_plan_task` precedent).

```json
{ "type": "object",
  "properties": {
    "tasks": { "type": "array",
      "items": { "type": "object",
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "status": { "type": "string", "enum": ["queued", "in_progress", "completed", "failed"] },
          "detail": { "type": "string" } },
        "required": ["id", "title", "status"] } } },
  "required": ["tasks"] }
```

**Output (structured).** `{planId, taskCount, completedCount, progress: number 0.0–1.0}`.

**Notes.** Legacy behaviour: `execute` returns `"Checklist updated"`; nothing is stored. Port: updates the workspace's current plan in the slice's `AgenticPlanningPlanStore` (creating a plan titled `"Checklist"` from the given tasks when no plan exists yet). Each incoming task is matched by `id`, then by title (case-insensitive); a match updates status/title/detail in place, a miss appends. Statuses outside the Legacy enum fail. Returns the plan's completed count and progress fraction. The summary keeps Legacy's wording as its prefix: `"Checklist updated: <completed> of <total> tasks completed."`

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 141 IDs, Legacy class names, descriptions, and schemas | 1 | Legacy source, read directly (Dylan's own code, direct porting authorised under MIT): `SwiftCode/Tools/Agentic/` — the per-slice files named in each section above; registry membership in `SwiftCode/Tools/Agentic/ListTools.swift` (141 entries) |
| Agentic registry is 141 tools, independent of the 291 Assist tools; `AgentTool` declares no capability/risk/permission; registry lookup is exact-name only, no aliases | 1 | Legacy `SwiftCode/Tools/Agentic/ListTools.swift` and `SwiftCode/Core/AI/Agent/AgentTool.swift` (`AgentTool` protocol) and `AgentToolRegistry.swift`, read directly |
| Registered Agentic tools = 117 (Files 6, Execution 9, Git 19, Network 19, CLI 21, Code 16, Data 19, Planning 8) | 1 | Live count of `tool("…")` calls in `ycode/Sources/YcodeMCP/YcodeTools+Agentic*.swift`, verified 2026-11-06 |
| 5 aliases added in Wave 8 (`list_directory` → `dir_read`, `execute_terminal_command` → `use_terminal`, `xcode_build` → `project_build`, `semantic_code_search` → `semantic_query_engine`, `cross_reference_search` → `symbol_reference_graph`); 7 git aliases removed in Wave 8 (`git_status`, `git_diff`, `git_commit`, `git_branch` → `version_control_operator`; `git_stash` → `git_stash_operator`; `git_blame` → `git_blame_inspector`; `git_log` → `git_log_viewer`) | 1 | `ycode/Sources/YcodeMCP/MCPServer.swift` (`toolAliases` and its Wave 8 comment), read directly |
| 13 pre-existing Agentic alias keys in `toolAliases` besides the 5 added in Wave 8 (18 Agentic IDs served by alias in total) | 1 | `ycode/Sources/YcodeMCP/MCPServer.swift` (`toolAliases`), enumerated live: `read_file`, `write_file`, `create_file`, `delete_file`, `move_file`, `copy_file`, `rename_file`, `create_directory`, `delete_directory`, `edit_file`, `run_build`, `run_tests`, `ask_user` |
| Exact-ID duplicates (6): `tree_view`, `git_cherry_pick`, `swift_package_manager`, `take_screenshot`, `call_hierarchy`, `dependency_graph` | 1 | `tool("…")` registrations in `ycode/Sources/YcodeMCP/YcodeTools+*.swift` (the Assist/Wave 3–7 registrations of those IDs), read directly |
| `git_cherry_pick` aligned in place (optional `hash` + `repositoryPath`, `required` `["commit"]` → `[]`, handler uses `commit ?? hash`) | 1 | `ycode/Sources/YcodeMCP/YcodeTools+Git.swift` (`git_cherry_pick` registration), read directly; `git_cherry_pick` is absent from `YcodeTools+AgenticGit.swift` (19 tools) |
| Per-slice behaviour, port notes, deviations, and error cases | 1 | The eight Wave 8 slice specifications (merged here) and the Wave 8 implementation files `ycode/Sources/YcodeMCP/YcodeTools+Agentic*.swift`, read directly |
| Ported targets' params and behaviour for alias/duplicate comparisons (`file_read`, `file_write`, `file_create`, `file_delete`, `file_move`, `file_copy`, `file_rename`, `dir_create`, `dir_delete`, `code_replace`, `code_multi_edit`, `tree_view`, `dir_read`, `use_terminal`, `project_build`, `project_test`, `semantic_query_engine`, `symbol_reference_graph`, `plan-AskUser`, `swift_package_manager`, `call_hierarchy`, `dependency_graph`, `take_screenshot`, `version_control_operator`, `git_stash_operator`, `git_blame_inspector`, `git_log_viewer`) | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+*.swift` and `MCPServer.swift`, read directly; `specs/ide/assist-tool-catalogue.md` and the Assist behaviour specs |
| Gate shape (`commit()` per text write, approval before disk, read-only refusal in `run()`) | 1 | Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`MCPWritePolicy`, `run`, `readOnlyMessage`); `YcodeTools+Content.swift` (`commit`); `specs/ide/assist-approval-model.md` §6 |
| Gaps recorded, not filled: the files slice records no verbatim Agentic description for its 12 non-ported tools (§§1–11, §13); the planning slice records no Legacy class name for `ask_user` (§139) | — | Absence in the source material for those slices; nothing was invented to fill them |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
