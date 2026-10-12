<!-- system-index-depends: CallTool.md -->
# AvailableTools — Registered Tool Catalog

Capability-level reference for the tools Assist can actually call. This
document describes **what each tool does**; the runtime registry defines
**what arguments it accepts**.

**Authority:** `AssistToolRegistry` is the source of truth. Tool identity is
the registered `id` (the `name` you see in schemas). Every id below is
registered in the codebase (ids declared under
`SwiftCode/Backend/Assist/Tools/`, plus `execution_plan` and
`use_workers`). Risk postures are read from the tools' own declarations:
`safeRead` / `safeMutation` / `potentiallyDestructive` / `execution` /
`externalSideEffect`. See CallTool.md for the calling procedure and
Safeguards.md for the authorization model.

## File operations

- `file_read` (safeRead) — read the contents of a known file. Not for existence checks.
- `file_write` (safeMutation) — create a new file or replace an entire file's content when you already know the full intended content. Overwrites blindly — read first.
- `file_append` (safeMutation) — append content to the end of an existing file. Requires the file to exist.
- `file_create` (safeMutation) — create a new file; refuses to clobber unless `overwrite: true`.
- `file_delete` (potentiallyDestructive) — delete a file. No undo outside snapshots.
- `file_move` (safeMutation) — relocate a file within the workspace.
- `file_copy` (safeMutation) — duplicate a file (templates, backups before risky edits).
- `file_rename` (safeMutation) — rename a file within its directory (`newName` is a bare file name).
- `dir_create` (safeMutation) — ensure a directory exists; effectively idempotent.
- `dir_delete` (potentiallyDestructive) — recursive directory deletion.
- `dir_read` (safeRead) — list a directory; the discovery tool before reading.
- `tree_view` (safeRead) — directory tree to a bounded depth.
- `code_generate` (safeMutation) — scaffold a new Swift file from a known template (`swift_struct`, `swift_class`, `swiftui_view`, `test`).

## Code mutation

- `code_replace` (safeMutation) — targeted replacement in a file.
- `code_multi_edit` (safeMutation) — multiple coordinated edits in one call.
- `code_insert` (safeMutation) — insert a code block at a line / before / after a position.
- `code_refactor` (safeMutation) — structured refactoring operations.
- `code_format` (safeMutation) — format code.
- `code_mutation_engine` (safeMutation) — minimal scoped mutation: replace a symbol body or exact target text (one of `symbol` / `target` required).
- `patch_application_engine` (safeMutation) — apply a patch block with an integrity check that the original block exists verbatim; replaces all matches.
- `project_mutation_controller` (safeMutation) — register a new Swift file in `SwiftCode.xcodeproj/project.pbxproj` (`add`/`remove`/`repair`). Prefer over hand-editing the pbxproj.

## Search and discovery

- `search_text` (safeRead) — text search across the repository.
- `search_regex` (safeRead) — regex search across the repository.
- `search_symbol` (safeRead) — symbol search (declarations, references).
- `dependency_graph` (safeRead) — dependency relationships between files/modules.
- `code_summary` (safeRead) — summarization of code at a path.
- `code_lint` (safeRead) — lint checks.
- `complexity_analysis` (safeRead) — complexity metrics for code.
- `source_graph_builder` (safeRead) — symbol/import relationship graph over Swift files.
- `semantic_query_engine` (safeRead) — concept-level code search ("find the networking service", "find SwiftUI views").
- `search_skills` (safeRead) — find relevant Skills in the indexed local library. Call once per distinct need; `file_read` the returned `SKILL.md` path to load it. An explicitly `/`-selected Skill is mandatory — follow it, do not substitute.

## Build, test, and diagnostics

- `project_build` (execution) — compile with the real toolchain (xcodebuild/SwiftPM). The authoritative build check; slow — never speculative.
- `project_test` (execution) — run test suites after a green build.
- `compiler_diagnostics_engine` (execution) — structured compiler warnings/errors without a full build flow; a failing build does not fail the tool — parse the payload.
- `automated_repair_engine` (safeMutation) — annotates reported compiler-error lines for review (`// AssistAutoRepair: review required`). Annotation-only, not a real fix; follow with real fixes and `project_build`.
- `dependency_resolution_engine` (execution) — resolve Swift package dependencies (`xcodebuild -resolvePackageDependencies`).
- `env_info` (safeRead) — runtime facts: OS, Swift version, CPU, memory, workspace root. No parameters.
- `env_capture_logs` (safeRead) — recent log lines from the environment snapshot history.
- `runtime_diagnostics_engine` (safeRead) — heuristic scan of a log file for crashes/anomalies; suggestions are leads, not diagnoses.
- `autonomous_review_engine` (safeRead) — heuristic self-review pass (force-unwraps, concurrency smells). Findings are advisory.
- `code_review` (safeRead) — independent-AI-reviewer gate before finishing an implementation task; returns serialized review JSON.
- `task_runner` (execution) — execute a registered internal Swift task by id. Never invent a `task_id`.
- `intel_autofix` (safeMutation) — LLM-driven fix attempt for lint/compilation errors at a path. Output varies between runs — verify by rebuilding.
- `intel_generate_tests` (safeMutation) — generate XCTest stubs for a Swift source file.
- `intel_explain_code` (safeRead) — generate an explanation of a file's architecture and logic.

## Git and recovery

- `version_control_operator` (potentiallyDestructive) — git `status`/`diff` are read-only and safe anytime; `commit`/`branch` when the task calls for them; `rollback` (`git reset --hard`) only for deliberate recovery. `commit` stages everything (`git add -A`). Exit codes are not checked — read the output text.
- `project_snapshot` (safeRead) — capture a workspace snapshot; returns a `snapshot_id` for `project_restore`.
- `project_restore` (potentiallyDestructive) — restore a snapshot, overwriting workspace state.
- `project_diff` (safeRead) — diff workspace state.
- `project_changelog` (safeRead) — list snapshot ids and history; feeds `project_restore` / `safe_undo`.
- `safe_undo` (potentiallyDestructive) — step back a snapshot.
- `safe_validate_changes` (safeRead) — validate pending changes.

## Terminal and external integrations

- `use_terminal` (execution) — arbitrary shell commands **only after explicit user approval**, and only when no native tool covers the operation. A denial is final — never retry or reroute. Prefer native tools over shelling out.
- `use_mcp` (externalSideEffect) — operate on configured MCP servers (GitHub, databases, developer services). Discover first: `serverName: "list"`, then `toolName: "list_tools"` per server; execute with the real names. `arguments` is a JSON-serialized string. An `@`-selected MCP is mandatory when relevant.
- `use_composio` (externalSideEffect) — third-party integrations via Composio (GitHub, Slack, Gmail, Calendar, …) by `toolSlug`. Requires Composio configured/authenticated.
- `external_resource_gateway` (safeRead) — fetch JSON from an external HTTP(S) API. Only fetch URLs relevant to the task.

## Memory and context

- `mem_store` (safeMutation) — persist a durable fact (`key`/`value`) across turns; overwrites the existing entry.
- `mem_retrieve` (safeRead) — read back a stored fact instead of recomputing or re-asking.
- `mem_clear` (potentiallyDestructive) — irreversibly deletes ALL memory entries. Only on explicit user instruction — never as cleanup or speculatively.
- `mem_context_snapshot` (safeMutation) — capture current environment/open-files context; each call stores a new UUID-keyed payload (not idempotent).
- `context_persistence_store` (safeMutation) — durable key-value context across sessions, persisted at `<workspaceRoot>/.assist_context_store.json`.

## Planning, tasks, and workers

- `intel_plan_task` (safeRead) — draft a high-level plan for a complex task; returns `planId` and steps, persisted as `plan:<planId>`.
- `intel_breakdown_task` (safeRead) — expand a plan into granular steps with acceptance criteria; takes the real `planId` from `intel_plan_task`, persisted as `plan_breakdown:<planId>`.
- `execution_plan` (safeRead) — generate a task-specific execution plan from live repository state; writes `agent_notes.md`. Treat output as a roadmap, not completed work.
- `plan-AskUser` (safeRead) — present a structured question to the user during **Plan mode only** (blocked in Autopilot). Suspends up to 300s; a cancellation or timeout means stop and report, not retry.
- `use_workers` (safeMutation) — decompose genuinely independent workstreams into parallel/sequenced workers. Default to 0 workers; each worker needs a unique name, non-overlapping scope, a task of ≤ 500 characters, and disjoint `targetFiles`. Workers execute real mutations — the highest-risk planning tool. See AgenticLoop.md for the delegation policy.
- `create_new_app` (safeMutation) — scaffold a new native macOS/iOS app project. Switches the active project session; not idempotent.

## Cloud toolkit (Antigravity SDK built-ins — not SwiftCode-registered)

When the **"Cloud"** toolkit is active, the session uses Google Antigravity
SDK's built-in cloud runtime tools instead of the System tools above. These
ids are **not** in `AssistToolRegistry`; they are provided by the Antigravity
cloud runtime and may only be called in Cloud mode:

- `view_file` — cloud workspace file inspection.
- `create_file` — cloud workspace file creation.
- `edit_file` — structured patch-block modification.
- `run_command` — cloud container shell execution.
- `list_directory` — cloud directory traversal.
- `search_directory` — cloud repository text search.
- `search_web` / `read_url_content` — online documentation and HTTP content fetching.
- `start_subagent` — cloud worker delegation.

Never call a System-toolkit id in Cloud mode, or a Cloud id in System mode.
