<!-- system-index-depends: CallTool.md -->
# AvailableTools — Registered Tool Catalog & Capability Matrix

Capability-level reference for the tools Assist can actually call. This document describes **what each tool does, what parameters it expects, and its operational risk posture**; the runtime registry (`AssistToolRegistry`) defines active authorization, schemas, and execution rules.

**Authority & Schema Contract:** `AssistToolRegistry` is the sole source of truth. Tool identity is the registered `id` (the `name` you see in schemas). Every ID below is registered in the codebase under `SwiftCode/Backend/Assist/Tools/` (plus built-in planning tools `execution_plan` and `use_workers`). Risk postures reflect tool declarations: `safeRead` / `safeMutation` / `potentiallyDestructive` / `execution` / `externalSideEffect`. See `CallTool.md` for calling procedures and `Safeguards.md` for the authorization model.

---

## File Operations

- `file_read` (safeRead) — read the contents of a known file at relative path `path` (optional `lineRange`, `maxBytes`). Not for existence checks. Re-reading verifies edits after mutation.
- `file_write` (safeMutation) — create a new file or replace an entire file's content at relative `path` with `content`. Overwrites existing files completely — inspect with `file_read` first.
- `file_append` (safeMutation) — append `content` to the end of an existing file at relative `path`. Requires the target file to exist.
- `file_create` (safeMutation) — create a new file at relative `path` with `content`; refuses to clobber unless `overwrite: true`.
- `file_delete` (potentiallyDestructive) — delete a file at relative `path`. Irreversible outside snapshot restore.
- `file_move` (safeMutation) — relocate a file from `sourcePath` to `destinationPath` within the workspace.
- `file_copy` (safeMutation) — duplicate a file from `sourcePath` to `destinationPath` (templates, backups before risky edits).
- `file_rename` (safeMutation) — rename a file at relative `path` within its directory (`newName` is a bare file name).
- `dir_create` (safeMutation) — ensure directory structure exists at relative `path`; effectively idempotent.
- `dir_delete` (potentiallyDestructive) — recursive directory deletion at relative `path`. Requires pre-verification.
- `dir_read` (safeRead) — list contents of directory at relative `path` (optional `recursive`, `depth`); the discovery tool before reading files.
- `tree_view` (safeRead) — directory tree from relative `path` to bounded depth `maxDepth`.
- `code_generate` (safeMutation) — scaffold a new Swift file at relative `path` from a known template (`template`: `swift_struct`, `swift_class`, `swiftui_view`, `test`).

---

## Code Mutation

- `code_replace` (safeMutation) — targeted replacement in file at `path`: replace exact target string `target` with `replacement` (optional `allowMultiple`).
- `code_multi_edit` (safeMutation) — perform multiple coordinated edits in file at `path` via `edits` array (`target`, `replacement`).
- `code_insert` (safeMutation) — insert code block `content` into file at `path` at `line` number or relative to `before`/`after` target text (`mode`: `"line"`/`"before"`/`"after"`).
- `code_refactor` (safeMutation) — structured refactoring operations (`action`: `rename_symbol`, `extract_method`, `inline_variable`) across file at `path`.
- `code_format` (safeMutation) — format Swift/source code at relative `path` using standard formatting rules.
- `code_mutation_engine` (safeMutation) — minimal scoped AST/symbol mutation in file at `path`: replace body of named `symbol` or exact `target` block (one of `symbol` / `target` required).
- `patch_application_engine` (safeMutation) — apply a patch block `patch` to file at `path` with an integrity check that the original block exists verbatim; replaces all matches.
- `project_mutation_controller` (safeMutation) — register or unregister source file `path` in `SwiftCode.xcodeproj/project.pbxproj` (`action`: `add`/`remove`/`repair`). Prefer over hand-editing the pbxproj.

---

## Search and Discovery

- `search_text` (safeRead) — plain text search for `query` across repository files (optional `fileTypes`, `maxResults`).
- `search_regex` (safeRead) — regex pattern search for `pattern` across repository files.
- `search_symbol` (safeRead) — symbol search (declarations, references) for `symbolName`.
- `dependency_graph` (safeRead) — module and file import dependency structure for relative `path`.
- `code_summary` (safeRead) — structural summarization and interface declaration extraction for file at `path`.
- `code_lint` (safeRead) — static lint checks and style analysis for file at relative `path`.
- `complexity_analysis` (safeRead) — cyclomatic and structural complexity metrics for source file at `path`.
- `source_graph_builder` (safeRead) — complete symbol, protocol, and import relationship graph over Swift workspace files.
- `semantic_query_engine` (safeRead) — concept-level code search ("find the networking service", "find SwiftUI views").
- `search_skills` (safeRead) — query local indexed skills library for specialized domain playbooks matching `query`. Call once per distinct need; inspect returned `SKILL.md` path using `file_read`. An explicitly `/`-selected Skill is mandatory — follow it, do not substitute.

---

## Build, Test, and Diagnostics

- `project_build` (execution) — builds the USER's Xcode project/workspace (resolved from the workspace root — never this app's own bundle) with `/usr/bin/xcodebuild`, run directly via Process in the background. Approval-exempt by design: this is the one terminal operation that never triggers the `use_terminal` approval prompt. The authoritative build check; slow — never speculative.
- `generate_xcodeproj` (execution) — generates `.xcodeproj` files from an XcodeGen `project.yml` spec via `xcodegen`, run directly via Process in the background. Installs XcodeGen with Homebrew automatically when missing. Approval-exempt by design, like `project_build`.
- `project_test` (execution) — run test suites for active workspace (optional `testTarget`, `testFilter`) after a green build.
- `compiler_diagnostics_engine` (execution) — structured compiler warnings/errors without a full xcodebuild flow; a failing build does not fail the tool — parse the diagnostic payload.
- `automated_repair_engine` (safeMutation) — annotates reported compiler-error lines in file `path` for review (`// AssistAutoRepair: review required`). Annotation-only, not a real fix; follow with real fixes and `project_build`.
- `dependency_resolution_engine` (execution) — resolve Swift package dependencies (`xcodebuild -resolvePackageDependencies`).
- `env_info` (safeRead) — runtime facts: macOS version, Swift toolchain version, CPU, memory, workspace root. No required parameters.
- `env_capture_logs` (safeRead) — recent log lines from environment snapshot history.
- `runtime_diagnostics_engine` (safeRead) — heuristic scan of crash log file at `path` for crashes/anomalies; suggestions are leads, not diagnoses.
- `autonomous_review_engine` (safeRead) — heuristic self-review pass (force-unwraps, concurrency smells, retain cycles) for file `path`. Findings are advisory.
- `code_review` (safeRead) — independent-AI-reviewer gate before finishing an implementation task; returns serialized review JSON scorecard.
- `task_runner` (execution) — execute a registered internal Swift task by `task_id`. Never invent a `task_id`.
- `intel_autofix` (safeMutation) — LLM-driven fix attempt for lint/compilation errors in file at `path`. Output varies between runs — verify by rebuilding.
- `intel_generate_tests` (safeMutation) — generate XCTest or Swift Testing stubs for source file at `path`.
- `intel_explain_code` (safeRead) — generate high-level architectural overview and logic explanation for file `path`.

---

## Git and Recovery

- `version_control_operator` (potentiallyDestructive) — git operations (`action`: `status`, `diff`, `commit`, `branch`, `rollback`). `status`/`diff` are read-only and safe anytime; `commit`/`branch` when task calls for them; `rollback` (`git reset --hard`) only for deliberate recovery. `commit` stages everything (`git add -A`). Exit codes are not checked — read the output text.
- `project_snapshot` (safeRead) — capture a workspace snapshot; returns a `snapshot_id` for `project_restore`.
- `project_restore` (potentiallyDestructive) — restore workspace to `snapshot_id`, overwriting uncommitted edits.
- `project_diff` (safeRead) — compare current workspace state against last snapshot or commit.
- `project_changelog` (safeRead) — list snapshot IDs and history; feeds `project_restore` / `safe_undo`.
- `safe_undo` (potentiallyDestructive) — step back a snapshot.
- `safe_validate_changes` (safeRead) — validate pending workspace modifications for syntax and structural integrity.

---

## Terminal and External Integrations

- `use_terminal` (execution) — arbitrary shell commands. Requires explicit user approval UNLESS the command is on the user's allow-list or Full Access is enabled (Assist Settings > Terminal Command Approvals) — those run immediately with no prompt. Only when no native tool covers the operation. Requires `command`, `workingDirectory` (optional), `explanation`, `estimatedImpact`, `modifiesRepo`. User rejection is final — never retry or reroute. Prefer native tools over shelling out. Note: `project_build` and `generate_xcodeproj` never route through this tool and never prompt.
- `use_mcp` (externalSideEffect) — operate on configured MCP servers (GitHub, databases, developer services). Discover first: `serverName: "list"`, then `toolName: "list_tools"` per server; execute with real names. `arguments` is a JSON-serialized string. An `@`-selected MCP server is mandatory when relevant.
- `use_composio` (externalSideEffect) — third-party integrations via Composio (GitHub, Slack, Gmail, Calendar, …) by `toolSlug`. Requires Composio configured/authenticated.
- `external_resource_gateway` (safeRead) — fetch JSON from an external HTTP(S) API `url` (optional `headers`, `method`). Only fetch URLs relevant to the task.

---

## Memory and Context

- `mem_store` (safeMutation) — persist a durable fact (`key`/`value`) across turns; overwrites existing entry.
- `mem_retrieve` (safeRead) — read back a stored fact by `key` instead of recomputing or re-asking.
- `mem_clear` (potentiallyDestructive) — irreversibly deletes ALL memory entries. Only on explicit user instruction — never as cleanup or speculatively.
- `mem_context_snapshot` (safeMutation) — capture current environment/open-files context; each call stores a new UUID-keyed payload (not idempotent).
- `context_persistence_store` (safeMutation) — durable key-value context across sessions, persisted at `<workspaceRoot>/.assist_context_store.json`.

---

## Planning, Tasks, and Workers

- `intel_plan_task` (safeRead) — draft a high-level plan for a complex task; returns `planId` and steps, persisted as `plan:<planId>`.
- `intel_breakdown_task` (safeRead) — expand a plan into granular steps with acceptance criteria; takes real `planId` from `intel_plan_task`, persisted as `plan_breakdown:<planId>`.
- `execution_plan` (safeRead) — generate a task-specific execution plan from live repository state; writes `agent_notes.md`. Treat output as a roadmap, not completed work.
- `plan-AskUser` (safeRead) — present a structured question to the user during **Plan mode only** (blocked in Autopilot). Suspends up to 300s; a cancellation or timeout means stop and report, not retry.
- `use_workers` (safeMutation) — decompose genuinely independent workstreams into parallel/sequenced workers. Default to 0 workers; each worker needs a unique name, non-overlapping scope, a task of ≤ 500 characters, and disjoint `targetFiles`. Workers execute real mutations — the highest-risk planning tool. See AgenticLoop.md for the delegation policy.
- `create_new_app` (safeMutation) — scaffold a new native macOS/iOS app project. Switches the active project session; not idempotent.

---

## Xcode Project & Build (60-tool expansion)

- `project_scheme_list` (safeRead) — list schemes via `xcodebuild -list -json` for the workspace project.
- `project_target_list` (safeRead) — list targets from pbxproj + `xcodebuild -list -json`.
- `project_build_settings` (safeMutation) — read (`action: read`) or set (`action: set`, `key`/`value`) build settings for a target/configuration.
- `project_target_add` (safeMutation) — add an app/framework/test target: creates source file + inserts PBXNativeTarget blocks, verified on re-read.
- `project_entitlements` (safeRead) — parse `*.entitlements` files, return keys/values.
- `project_info_plist` (safeMutation) — get/set/delete Info.plist keys via plist serialization.
- `project_capabilities` (safeMutation) — list/enable/disable capabilities via entitlements + SystemCapabilities.
- `project_signing` (safeRead) — CODE_SIGN_STYLE / DEVELOPMENT_TEAM / bundle ID + provisioning profile filenames (never profile contents).
- `project_clean` (potentiallyDestructive) — requires `confirm: "true"`; removes workspace `build/` and/or runs `xcodebuild clean`.
- `project_archive` (execution) — `xcodebuild archive` for `scheme` to in-workspace `archivePath`; verifies `.xcarchive`.

## SwiftPM, Assets & Resources

- `package_manifest_read` (safeRead) — parse Package.swift: name, platforms, products, targets, dependencies.
- `package_dependency_add` (safeMutation) — insert `.package(url:from:)` + optional product/target wiring; verifies on re-read.
- `package_dependency_update` (execution) — `swift package update [package]` in workspace root.
- `package_manifest_validate` (safeRead) — `swift package dump-package`, exit 0 + name/target count.
- `package_dependency_audit` (safeRead) — Package.swift vs Package.resolved: missing resolved, non-exact requirements, deps missing from resolved + `show-dependencies`.
- `asset_catalog_list` (safeRead) — enumerate `*.xcassets`, list image/color/icon/dataset/symbol sets + counts.
- `asset_image_add` (safeMutation) — create `imageName.imageset/` + valid Contents.json + copy workspace image, verified.
- `strings_localization` (safeMutation) — get/set/delete one key in `.strings` or `.xcstrings` (per-locale).
- `localization_audit` (safeRead) — missing keys per locale + keys never referenced in Swift.
- `plist_edit` (safeMutation) — get/set/delete plist keys via plist serialization, atomic write + verify.

## Code Quality & Analysis

- `dead_code_scan` (safeRead) — heuristic: declarations with zero references (overloads excluded).
- `duplicate_code_scan` (safeRead) — normalized sliding-window duplicate blocks, file:line pairs.
- `todo_scan` (safeRead) — TODO/FIXME/XXX/HACK inventory, file:line:text + counts.
- `license_header_check` (safeRead) — files missing `requiredText` (default Copyright) in first 15 lines.
- `api_surface_extract` (safeRead) — public/open declarations grouped by file + count.
- `symbol_rename_project` (safeMutation) — whole-word project-wide rename across Swift files.
- `symbol_move_file` (safeMutation) — move brace-balanced symbol block from source to destination file, verified + restore on failure.
- `import_cleanup` (safeMutation) — remove unused `import X` lines (protected modules never removed).
- `access_level_audit` (safeRead) — declaration counts by public/open/internal/private/fileprivate.
- `concurrency_audit` (safeRead) — heuristic: DispatchQueue.main.sync, nonisolated(unsafe), Task without await, shared mutable statics, force-unwraps in async contexts.

## Testing & QA (expansion)

- `test_coverage_report` (execution) — `xcodebuild test -enableCodeCoverage YES`, parses coverage % + TEST SUCCEEDED/FAILED, result bundle path.
- `test_flaky_detect` (safeRead) — parse test logs for tests with both pass and fail outcomes.
- `test_snapshot_manage` (safeMutation) — list `__Snapshots__` refs; `clean` only with `confirm: "true"`, deletes only unreferenced snapshots (heuristic).
- `ui_test_scaffold` (safeMutation) — write real XCTest UI test file; refuses overwrite unless `overwrite: "true"`.
- `test_data_factory` (safeMutation) — write real JSON/Swift fixture from `fields` (e.g. `id:Int,name:String`); refuses overwrite unless `overwrite: "true"`.
- `test_target_add` (safeMutation) — add unit/UI test target: test file + pbxproj blocks, all anchors verified before writing.
- `test_run_single` (execution) — `xcodebuild test -only-testing:<testId>`, pass/fail + output tail.
- `test_log_parse` (safeRead) — parse test log: Test Case pass/fail, suite summaries, `: error:` lines, failed list.
- `performance_benchmark` (execution) — run allow-listed command 1–10 times, avg/min/max wall time + exit codes.
- `binary_size_report` (safeRead) — `.app` bundles under workspace `build/` only (never DerivedData): total + 10 largest files.

## Git Advanced & Structured Files

- `git_stash` (safeMutation) — `git stash` list/push/pop/apply/drop with validation.
- `git_blame` (safeRead) — `git blame --line-porcelain`, optional line range, max 2000 lines.
- `git_bisect` (execution) — `git bisect` start/good/bad/skip/reset/log with ref validation.
- `git_cherry_pick` (safeMutation) — `git cherry-pick [--no-commit] <commit>` (SHA/ref validated); on conflict reports conflicted files, never auto-aborts.
- `git_branch_compare` (safeRead) — `git diff --stat base...head` + `git log base..head`.
- `git_pr_summary` (safeRead) — local-only markdown PR summary: commits + diff stat, no GitHub API.
- `file_metadata` (safeRead) — size, dates, permissions, type via FileManager.
- `file_hash_verify` (safeRead) — `shasum`/`md5`, compare to `expectedHash`; mismatch is `match: "false"`, not a tool error.
- `json_validate` (safeMutation) — validate / format (pretty + sorted keys); writes back only when `write: "true"`.
- `yaml_validate` (safeMutation) — heuristic validator (tabs, unbalanced brackets/quotes, duplicate top-level keys); format normalizes to 2-space indent, writes only when `write: "true"` + validation passes.

## Environment, Devices, Docs & Security

- `simulator_list` (safeRead) — `xcrun simctl list devices -j`, grouped by runtime with state + UDID.
- `simulator_boot` (execution) — `simctl boot/shutdown <udid>` (UUID validated), verified via `simctl list`.
- `device_list` (safeRead) — `devicectl list devices -j` with `xctrace` fallback; fails clearly when unavailable.
- `provisioning_check` (safeRead) — decode provisioning profiles via `security cms -D` + plist, flags expired/expiring (30d), compares App ID to `bundleId` (wildcard `*` matches).
- `docc_build` (execution) — `xcodebuild docbuild` for `scheme`, verifies `.doccarchive`.
- `docs_generate` (safeMutation) — generate real markdown API docs from public declarations; refuses overwrite unless `overwrite: "true"`.
- `secrets_scan` (safeRead) — scan for AWS/GitHub/sk- keys, api_key/password assignments, private-key blocks. Reports ONLY file:line:pattern — never matched values or line contents.
- `permissions_audit` (safeRead) — Info.plist usage descriptions, entitlements, PrivacyInfo.xcprivacy + heuristic missing-description checks.
- `accessibility_audit` (safeRead) — heuristic: Button/Image without accessibility label, unlabeled TextField, color-only state.
- `session_export` (safeMutation) — write markdown export with title, timestamp, sessionId, workspace, notes. Never reads conversation history. Refuses overwrite unless `overwrite: "true"`.

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
