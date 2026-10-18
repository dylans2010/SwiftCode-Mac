<!-- system-index-depends: CallTool.md -->
# AvailableTools — Registered Tool Catalog & Capability Matrix

Capability-level reference for the tools Assist can actually call. This document describes **what each tool does, what parameters it expects, and its operational risk posture**; the runtime registry (`AssistToolRegistry`) defines active authorization, schemas, and execution rules.

**Authority & Schema Contract:** `AssistToolRegistry` is the sole source of truth. Tool identity is the registered `id` (the `name` you see in schemas). Every ID below is registered in the codebase under `SwiftCode/Backend/Assist/Tools/` (plus `use_workers` in `Subagents/Tools/`). Risk postures reflect tool declarations: `safeRead` / `safeMutation` / `potentiallyDestructive` / `execution` / `externalSideEffect`. See `CallTool.md` for calling procedures and `Safeguards.md` for the authorization model.

**Output contract:** tool results carry `success` (bool — true only when the operation genuinely completed), `output` (concise explanation), `data` (genuine result fields), `error` (structured failure info when applicable), plus `filesChanged` / `diff` / `exitCode` where relevant. `success: true` with empty results means "succeeded and found nothing" — check `data` (e.g. `count: 0`) rather than assuming content. A failure is never reported as success; no-op cases (pattern miss, missing file on delete, unknown template) return `.failure`. Truncation is always marked (e.g. `… [truncated …]`, `stdoutTruncated: true`).

**Paths:** all file paths are workspace-relative unless stated otherwise. `..` is rejected by validators (except `dir_cd`, where it means "parent", clamped at the workspace root). An absolute path with the workspace-root prefix is relativized to the same file; any other absolute path is rejected. The workspace root is the user's active project; when no project is open, filesystem tools fail closed.

---

## Tool-Selection Hierarchy

Priority 1 — Dedicated native tool. When a native tool can complete the operation correctly, use it. Filesystem work (list/read/write/edit/search/metadata) always uses native tools, never shell equivalents (`ls`, `cat`, `grep`, `find`, shell redirection, `sed`).

Priority 2 — `use_terminal` for command-oriented operations. Use it when the task genuinely requires command execution: `xcodebuild` (when no native build tool fits), test suites, package-manager commands, compilers/CLI utilities, build scripts, diagnostics, Git commands with no suitable native Git tool, specialized shell-only operations. Do not force native tools to do work outside their capabilities.

Priority 3 — No tool when no tool is needed. Answer directly when the information is already available: explaining a concept, describing a known API, drafting from conversation context. Never invoke tools merely because they exist, and never repeat a call whose valid result is already in context.

Failure handling: classify the failure first (bad arguments, missing resource, permission, genuine limitation). Fix recoverable argument problems. Try a different tool only when it is authorized and can legitimately complete the operation. Never retry a non-recoverable failure, and never use `use_terminal` to circumvent a native tool's permission failure — a denied operation stays denied.

Native-vs-terminal preference per operation: list directory → `dir_read` (not `ls`); change directory → `dir_cd` (not shell `cd`); read file / lines → `file_read` (not `cat`/`sed`); write file → `file_write`/`file_create` (not redirection); edit file → `code_replace`/`code_insert`/`code_multi_edit` (not `sed`/`perl`); search filenames → `search_text`/`search_regex` (not `find`); search contents → `search_text`/`search_regex`/`search_symbol` (not `grep`); metadata → `dir_read`/`tree_view`; build → `project_build` (approval-exempt native) or `use_terminal` when command execution is required; tests → `project_test` or `use_terminal`; Git → `version_control_operator` or `use_terminal`.

## Terminal Governance

`use_terminal` is the SOLE model-facing terminal tool. No other shell tool is exposed to the model. It executes real commands via `AgentTerminalService` with stdout/stderr/exit code/duration returned; output truncation is marked. It prompts for user approval unless the command is allow-listed or Full Access is enabled. A user rejection is final — never retry or reroute.

Six native tools also run processes directly with fixed argument vectors (never a shell string) and never trigger the terminal prompt: `project_build` (xcodebuild build), `generate_xcodeproj` (xcodegen; fails with install instructions when xcodegen is missing), `project_test` (xcodebuild test), `compiler_diagnostics_engine` (xcodebuild build + diagnostic parse), `dependency_resolution_engine` (xcodebuild -resolvePackageDependencies), `version_control_operator` (git via argv). These are approval-exempt by design with a fixed-argv contract; they are the only sanctioned terminal-adjacent paths besides `use_terminal`. Nothing else in `Tools/` spawns a process.

## `file_read` Line Ranges

`file_read` accepts optional `lines: {start, end}` — 1-based, inclusive. Omit `lines` to read the whole file. `start` defaults to 1, `end` defaults to the last line. `end` beyond EOF is clamped to the last line (reported in `data.end`); `start` beyond EOF is an error; `start > end`, zero/negative, or non-integer values are errors. Returned content is line-number-prefixed (`"242: …"`) and `data` carries `path` (resolved), `start`, `end`, `totalLines`, `fullyAvailable`. Empty file → success with `totalLines: 0`, `start: 1`, `end: 0`. Missing file / permission failure → `.failure`. Request lines 240–280 as `{"path": "…", "lines": {"start": 240, "end": 280}}` — never read the whole file or run `sed` for a targeted range.

## Worked Examples of Correct Tool Selection

Example A — Auditing the Assist codebase. Use native `dir_read` to discover files, `file_read` (with `lines` ranges for large files) to inspect source, `search_text` / `search_regex` to find registrations, native editing tools to fix, `use_terminal` only for a build/test/diagnostic. Wrong: invoking unrelated tools, running `ls`/`cat`/`grep`/`find` through `use_terminal`, claiming a fix without verifying it.

Example B — Writing a Swift source file. Inspect relevant project files as needed, use `file_write` / `file_create` / `code_replace`, verify by re-reading, run `project_build` / `project_test` through native tools when verification needs command execution. Wrong: shell redirection for writes, claiming the write succeeded when it failed.

Example C — Inspecting clipboard contents. No clipboard tool is registered: say so plainly and do not guess contents, read unrelated files, or return fabricated sample data. Never invent a tool that is not in this catalog.

Example D — Building a project. Inspect configuration with native tools if needed, run the build via `project_build` (approval-exempt native) or `use_terminal` for a custom build command, interpret the real output and exit status, report genuine errors, fix when authorized, verify. Wrong: simulating a build result, refusing terminal execution when it is the appropriate mechanism, using unrelated tools.

Example E — Reading lines 240–280. Call `file_read` with `path` and `lines: {start: 240, end: 280}`; use the returned numbered lines for analysis. Wrong: reading the entire file unnecessarily, running `sed` through the terminal, returning invented source, ignoring the requested range.

Example F — Answering a general programming question. Answer directly when the model has sufficient information (e.g. explaining Swift actors). Use tools only if additional research, source inspection, or another operation is genuinely necessary. Wrong: invoking several tools merely because the question concerns programming.

---

## File Operations

- `file_read` (safeRead) — read file at `path` (required). Optional `lines: {start, end}` 1-based inclusive range; omit for full file. Returns line-numbered `content` + `path`/`start`/`end`/`totalLines`/`fullyAvailable`. Use for known files; use `dir_read`/`tree_view` for discovery, not `file_read` to test existence. Do not use for whole-file reads when a range suffices.
- `file_write` (safeMutation) — create or fully replace file at `path` (required) with `content` (required). Atomic write, disk re-read verification, unified diff, `filesChanged`. Overwrites completely — read first. Do not use for targeted edits (`code_replace` is precise) or appends (`file_append`).
- `file_append` (safeMutation) — append `content` (required) to existing file at `path` (required). Requires the target to exist; missing file fails (no auto-create). Do not use for full rewrites.
- `file_create` (safeMutation) — create file at `path` (required) with `content` (default `""`); refuses to overwrite unless `overwrite: true`. Use when the file must not already exist; use `file_write` to overwrite.
- `file_delete` (potentiallyDestructive) — delete file at `path` (required). Irreversible outside snapshot restore. Missing file fails (not silent success). Do not use speculatively; snapshot first for risky deletes.
- `file_move` (safeMutation) — relocate from `source` to `destination` (both required). Refuses when the destination exists (no silent overwrite). Do not use for renames within one directory (`file_rename`).
- `file_copy` (safeMutation) — duplicate from `source` to `destination` (both required). Refuses when the destination exists. Use for templates/backups before risky edits.
- `file_rename` (safeMutation) — rename within the same directory: `oldPath` + `newName` (both required; `newName` is a single file name, not a path — `/` or `..` rejected). Do not pass a path as `newName`.
- `dir_create` (safeMutation) — ensure directory at `path` (required), including missing parents. Idempotent. Resolved through the filesystem layer (traversal/symlink checked).
- `dir_delete` (potentiallyDestructive) — recursive deletion at `path` (required). Refuses the workspace root; missing directory fails. Destructive and irreversible — verify first, snapshot first.
- `dir_read` (safeRead) — list directory at `path` (required; `.` = session working directory). Sorted entries, directories suffixed `/`, plus `count` and resolved `path`. Non-recursive — use `tree_view` for recursion. The discovery tool before reading files.
- `dir_cd` (safeRead) — change the session working directory: `path` (required), resolved against the current directory (`..` = parent, clamped at root). Persists for the session (in-memory, per-session; new sessions start at the workspace root) and applies to later relative paths and to `use_terminal` when it omits `workingDirectory`. Not a shell `cd`. Do not use to escape the workspace.
- `dir_pwd` (safeRead) — report the session working directory. No parameters.
- `tree_view` (safeRead) — directory tree from `path` (default `.`) to `maxDepth` (integer, clamped 1...10, default 3). Symlinks listed as leaves, never followed; output capped at 2000 entries with a truncation marker. Do not use for flat listings (`dir_read`).
- `code_generate` (safeMutation) — scaffold file at `path` (required) from `template` (required: `swift_struct`, `swift_class`, `swiftui_view`, `test`); `module` (optional, defaults to the user's project name for the test template). Refuses to overwrite. Unknown template fails. The `test` template is a failing `XCTFail` scaffold until a real assertion replaces it — not a passing test.

---

## Code Mutation

- `code_replace` (safeMutation) — targeted replacement in file at `path`: replace exact `target` with `replacement` (all required) with optional `allowMultiple` (boolean, default false). Verified replacement with conflict errors (target-not-found / multiple-matches / stale-state), diff, disk re-read. The preferred precise edit tool. Do not use for whole-file rewrites.
- `code_multi_edit` (safeMutation) — apply `edits` (array, required) across files. Each edit needs non-empty `path` plus either `content` (full-file replacement) or non-empty `search` + `replace`. NOT atomic: earlier edits persist if a later one fails (failure names applied edits). All edits are validated before any are applied; empty `search` is rejected. Do not use when `code_replace` on one file suffices.
- `code_insert` (safeMutation) — insert `code` (required) into file at `path` (required) at integer 1-based `line` (mode `line`, default) or `before`/`after` a `pattern` (required in those modes; `mode` strictly `line`/`before`/`after`). Pattern miss is a failure; unknown mode is a failure. Do not use to replace existing text (`code_replace`).
- `code_refactor` (safeMutation) — LLM full-file rewrite of file at `path` with free-form `action` (both required; `action` is natural language to the model, not an enum). No rebuild verification — caller must verify. Provider is fixed; output varies between runs.
- `code_format` (safeMutation) — basic normalization (trailing whitespace, blank-line collapse, tab expansion, trailing newline) for file or directory at `path` (default `.`; Swift/C/JS/TS/Python). Preserves indentation. Not a real formatter (no swiftformat) — do not present it as one.
- `code_mutation_engine` (safeMutation) — minimal scoped mutation in file at `path`: replace body of named `symbol` or exact `target` block with `replacement` (`path` + `replacement` required, one of `symbol`/`target` required). Substring + brace-count matching (can match comments/strings); output is never syntax-checked. The only tool that also consults `permissions.isPathAllowed`.
- `patch_application_engine` (safeMutation) — replace verbatim `original` block with `updated` in file at `path` (all required); replaces ALL occurrences. The "diff" is a naive positional line comparison, not a Myers diff. Do not use when `code_replace`'s conflict handling is needed.
- `project_mutation_controller` (safeMutation) — register/unregister source file in the USER's project pbxproj: `action` (`add`/`remove`/`repair`, required), `filePath`, `projectFile`. Prefer over hand-editing the pbxproj. `remove` filters by substring (can over-match); `add` reports "already referenced" on any filename match; `lastKnownFileType` is hardcoded to Swift.

---

## Search and Discovery

- `search_text` (safeRead) — literal (case-insensitive) text search for `pattern` (required) across repository files. Sorted; 1 MB file cap; binary files skipped. Do not use for regex (`search_regex`) or symbols (`search_symbol`).
- `search_regex` (safeRead) — regex search for `pattern` (required). Invalid regex fails honestly. Do not use for literal text.
- `search_symbol` (safeRead) — declaration search for `symbol` (required) across 4 declaration patterns. Per-pattern failures are logged, not surfaced — a total failure can look like zero matches.
- `dependency_graph` (safeRead) — `^import` regex scan for file/directory at `path` (optional). Missing directory yields success with 0 nodes — verify the path exists first. Nodes conflate file paths and module names.
- `code_summary` (safeRead) — line / non-empty / `//`-comment counts for file at `path` (required). Does NOT extract interface declarations despite older descriptions. Do not use for real API summaries.
- `code_lint` (safeRead) — line-length (>120) + TODO/FIXME scan for file at `path` (optional). Returns success-with-issues in `data` — callers checking only `success` miss them. Not a style analyzer.
- `complexity_analysis` (safeRead) — substring keyword counting for file at `path` (required). Counts keywords in comments/strings; not real cyclomatic complexity.
- `source_graph_builder` (safeRead) — regex symbol/import graph over the workspace from `path` (optional). Every capitalized word becomes a `type:` edge (noise); relationships truncated at 2000.
- `semantic_query_engine` (safeRead) — substring concept search for `query` (required), optionally scoped to `path`. Substring matching, not semantic search; hits truncated at 1500.
- `search_skills` (safeRead) — query local indexed skills library for `query` (required); `limit` integer (default 8, max 20). Call once per distinct need; inspect the returned `SKILL.md` path using `file_read`.

---

## Build, Test, and Diagnostics

- `project_build` (execution) — builds the USER's Xcode project/workspace (resolved from the workspace root — never this app's own bundle) with `/usr/bin/xcodebuild`, via fixed argv in the background. Approval-exempt by design: never triggers the `use_terminal` prompt. Params: `projectPath`, `scheme`, `configuration` (Debug/Release), `destination`. The authoritative build check; slow — never speculative.
- `generate_xcodeproj` (execution) — generates `.xcodeproj` from an XcodeGen spec: `spec` (workspace-relative `project.yml`, default `project.yml`), `useCache` (`"true"`/`"false"` string). Approval-exempt by design. Fails with install instructions when xcodegen is missing (no silent `brew install`).
- `project_test` (execution) — run test suites for the active workspace: `scheme`, `testPlan` (both optional). Runs real `xcodebuild test`. Run after a green build.
- `compiler_diagnostics_engine` (execution) — runs a FULL `xcodebuild build` (not a lightweight pass) and parses warnings/errors: `project`, `scheme` (both optional). Fixed argv (never a shell string), 300s timeout. Returns success when diagnostics were collected, with explicit `buildFailed`/`exitCode` in data — a failed build is not a tool failure, but it is not hidden either.
- `automated_repair_engine` (safeMutation) — annotation-only: inserts `// AssistAutoRepair: review required` above lines named in `errors` (required). Does NOT fix anything and does NOT rebuild despite older descriptions. Follow with real fixes and `project_build`.
- `dependency_resolution_engine` (execution) — runs `xcodebuild -resolvePackageDependencies` for the workspace project: `packageURL` (required) is a REPORT LABEL ONLY — the tool never adds that package. Fixed argv, 300s timeout, exit code checked.
- `env_info` (safeRead) — runtime facts (macOS version, CPU, memory, workspace root). No required parameters. Does NOT report the Swift toolchain version despite older descriptions.
- `env_capture_logs` (safeRead) — returns snapshot metadata (timestamp/message/id) for `memoryKey` (optional), NOT log contents. Name overstates; do not use to read logs.
- `runtime_diagnostics_engine` (safeRead) — keyword scan (`fatal error`/`crash`/thread-queue) of the crash log file at `logPath` (required). Suggestions are 3 canned strings — leads, not diagnoses.
- `autonomous_review_engine` (safeRead) — heuristic keyword scan (force-unwraps, concurrency smells) for file/directory at `path` (optional). No retain-cycle check. Missing/empty dir yields success with 0 findings.
- `code_review` (safeRead) — independent-AI-reviewer gate before finishing an implementation task. Returns flattened data + summary (not raw serialized JSON). Disabled mode returns success with `status: review_skipped` — that is NOT verification.
- `task_runner` (execution) — execute a registered internal Swift task by `task_id` (required). Task IDs are undiscoverable (no list tool) — never invent one. Note: internal task `project_test` only lists test files, while tool `project_test` runs `xcodebuild test` — same name, different behavior.
- `intel_autofix` (safeMutation) — LLM-driven fix attempt for lint/compilation errors in file at `path` (optional, default `.` — which fails `readFile`; pass a real file). Lints the whole workspace, rewrites only the single `path` file; output varies — verify by rebuilding.
- `intel_generate_tests` (safeMutation) — generate test stubs for source file at `path` (required) into `testPath` (optional). Overwrites an existing test file without warning; counts capped groups inconsistently.
- `intel_explain_code` (safeRead) — LLM explanation for file at `path` (required). On LLM failure returns success with a 1-line fallback — not an explanation. Provider is hardcoded to OpenAI.

---

## Git and Recovery

- `version_control_operator` (potentiallyDestructive) — git via fixed argv: `action` (required: `status`, `commit`, `branch`, `rollback`, `diff`; unknown actions rejected), `message` (commit), `name` (branch), `ref` (rollback, default `HEAD~1`, strict allow-list). `status`/`diff` are read-only; `commit` stages everything (`git add -A`); `rollback` (`git reset --hard`) is destructive — snapshot first. Exit codes ARE checked in every branch.
- `project_snapshot` (safeRead) — capture a workspace snapshot; returns a `snapshot_id` for `project_restore`. Copies the whole project (including `.git`/build dirs, no exclusions) to Application Support — size/time unbounded. Snapshot before destructive operations.
- `project_restore` (potentiallyDestructive) — restore workspace to `snapshot_id` (required), wiping the workspace then copying snapshot files. Destructive; relies on runtime approval, none in-tool.
- `project_diff` (safeRead) — real git status + diff against HEAD via `GitService`. `modifiedFiles` uses bare filenames (directory info lost; collisions possible). Not a snapshot comparison.
- `project_changelog` (safeRead) — list snapshot IDs and history; feeds `project_restore` / `safe_undo`. No parameters.
- `safe_undo` (potentiallyDestructive) — restores `snapshots[1]` (second-newest), which is NOT necessarily the pre-last-action state (snapshots are manual/periodic, not per-action). No snapshot is taken before restoring, so undo is not chainable or reversible. Requires ≥2 snapshots. Prefer `project_restore` with an explicit `snapshot_id`.
- `safe_validate_changes` (safeRead) — merge-marker + trailing-newline + readability checks for `path` (optional). False positives: `=======` matches any separator line / markdown / base64-ish content. Returns success-with-issues.

---

## Terminal and External Integrations

- `use_terminal` (execution) — arbitrary shell commands. Only `command` is required; `workingDirectory` (defaults to session working directory), `explanation`, `estimatedImpact`, `modifiesRepo` (string `"true"`/`"false"` or boolean) all default. Approval prompt unless allow-listed / Full Access. User rejection is final — never retry or reroute. Only when no native tool covers the operation. Prefer native tools over shelling out. Note: `project_build`, `generate_xcodeproj`, `project_test`, `compiler_diagnostics_engine`, `dependency_resolution_engine`, `version_control_operator` never route through this tool and never prompt.
- `use_mcp` (externalSideEffect) — operate on configured MCP servers. Discover first: `serverName: "list"`, then `toolName: "list_tools"` per server; execute with real names (`serverName`, `toolName`, `arguments` — all required; `arguments` is a JSON-serialized string). Approval requested. `list_tools` requires approval + auto-connect; top-level `list` does not. An `@`-selected MCP server is mandatory when relevant.
- `use_composio` (externalSideEffect) — third-party integrations via Composio by `toolSlug` (required) + `arguments` (required, dict or JSON string). Approval requested first. `modifiesRepo: false` is hardcoded in the approval request even when the slug mutates external state.
- `external_resource_gateway` (externalSideEffect) — HTTPS-only GET of a JSON API at `url` (required). `http://`, `file://`, and other schemes are rejected; non-2xx responses fail; 30s timeout. Only fetch URLs relevant to the task.

---

## Memory and Context

- `mem_store` (safeMutation) — persist a durable fact: `key` + `value` (both required); overwrites existing entry.
- `mem_retrieve` (safeRead) — read back a stored fact by `key` (required). Missing key fails (unlike `context_persistence_store` get-missing, which succeeds with `""`).
- `mem_clear` (potentiallyDestructive) — irreversibly deletes ALL memory entries. Only on explicit user instruction — never as cleanup or speculatively. No parameters.
- `mem_context_snapshot` (safeMutation) — capture a marker payload (session + workspace + latest snapshot id). Does NOT capture "environment and open files" despite older descriptions. Each call mints a new UUID key (not idempotent).
- `context_persistence_store` (safeMutation) — durable key-value context across sessions, persisted at `<workspaceRoot>/.assist_context_store.json` (repo pollution; gets snapshotted). `key` (required), `action` (`get`/`set`/`delete`), `value`. Get/delete of a missing key succeeds (with `value: ""` for get) — indistinguishable from a stored empty value. Invalid `action` falls through to `get`.

---

## Planning, Tasks, and Workers

- `intel_plan_task` (safeRead) — draft a high-level plan for a complex task: `task` (required). Returns `planId` and steps, persisted as `plan:<planId>`. Mechanical clause-numbering, not real planning — treat as scaffolding.
- `intel_breakdown_task` (safeRead) — expand a plan into granular steps: `planId` (required, must come from `intel_plan_task`). Mechanical tripling of stored-plan lines (including blanks) — review the output, do not trust it blindly.
- `execution_plan` (safeMutation) — generate a task-specific execution plan from live repository state: `objective` + `mode` (both required). Writes `agent_notes.md` into the workspace (it is a mutation despite older safeRead labeling). The plan is a fixed 4-step template; treat output as a roadmap, not completed work. "Files inspected" counts relevant files, not inspected files.
- `plan-AskUser` (safeRead) — present a structured question to the user during **Plan mode only** (blocked in Autopilot). `question`, `allowsMultipleAnswers`, `choices` (array of `{choice, assistRecommended}`) all required; `userSpecification` boolean. Suspends up to 300s; cancellation/timeout means stop and report, not retry.
- `use_workers` (safeMutation) — decompose genuinely independent workstreams into parallel/sequenced workers: `workers` (required). Default to 0 workers; each worker needs a unique name, non-overlapping scope, a task of ≤ 500 characters, and disjoint `targetFiles`. Workers execute real mutations — the highest-risk planning tool. See AgenticLoop.md for the delegation policy.
- `create_new_app` (safeMutation) — scaffold a new native macOS/iOS app project: `appName` + `applicationDescription` (required); `bundleIdentifier` defaults to `com.swiftcode.<name>`. Writes OUTSIDE the workspace (default `~/Documents/<appName>`, `/tmp` fallback) and switches the active project session; not idempotent.

---

## Known Limitations (honest)

- The six approval-exempt process tools (`project_build`, `generate_xcodeproj`, `project_test`, `compiler_diagnostics_engine`, `dependency_resolution_engine`, `version_control_operator`) bypass the `use_terminal` approval prompt by design; their safety rests on the fixed-argv contract, not on a prompt.
- Several "intelligence" tools are keyword/substring heuristics, not the analysis their names promise (`complexity_analysis`, `autonomous_review_engine`, `semantic_query_engine`, `code_summary`, `code_lint`, `runtime_diagnostics_engine`).
- `safe_undo` is not per-action undo; `execution_plan` is a template; `intel_plan_task` / `intel_breakdown_task` are mechanical; `automated_repair_engine` annotates instead of repairing; `env_capture_logs` returns snapshot metadata, not logs; `dependency_resolution_engine` never adds a package.
- Throws propagate instead of `.failure` in a few tools (`automated_repair_engine`, `patch_application_engine`, `runtime_diagnostics_engine`, `source_graph_builder`, `context_persistence_store`); callers should treat a throw as a tool failure.
- `AssistPermissionsManager` is consulted by almost no tool (`code_mutation_engine` only, for `isPathAllowed`); the real gates are filesystem containment, validators, the phase gate, and the terminal approval dialog.

---

## Cloud Toolkit (Antigravity SDK Built-ins — Cloud Mode ONLY)

When the **"Cloud"** toolkit is active, the session uses Google Antigravity SDK's built-in cloud runtime tools instead of the System tools above. These IDs are **not** in `AssistToolRegistry`; they are provided by the Antigravity cloud runtime and may only be called in Cloud mode:

- `view_file` — cloud workspace file inspection.
- `create_file` — cloud workspace file creation.
- `edit_file` — structured patch-block modification.
- `run_command` — cloud container shell execution.
- `list_directory` — cloud directory traversal.
- `search_directory` — cloud repository text search.
- `search_web` / `read_url_content` — online documentation and HTTP content fetching.
- `start_subagent` — cloud worker delegation.

Never call a System-toolkit ID in Cloud mode, or a Cloud ID in System mode.
