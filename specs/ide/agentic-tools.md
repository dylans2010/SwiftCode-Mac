# Agentic tools — behaviour (Wave 8)

SwiftCode module: `SwiftCodeMCP` (the MCP server and its tools).

This spec is the behaviour contract for the 141 Legacy Agentic tools
ported in Wave 8. The companion spec `agentic-tool-catalogue.md` is
the per-tool catalogue (ID, Legacy class, disposition, verbatim
description, parameter schema, outputs, capability / risk /
permission for all 141 tools, numbered §§1–141). This spec covers
what the catalogue does not repeat per tool: the host conventions
every ported tool follows, the error tables, the deviations from
Legacy behaviour, the collision resolutions, and the param-caveat
register.

Scope: exactly the 141 Agentic tools in the catalogue. The Agentic
registry is a separate registry from the 291-tool Assist registry;
the two registries share names but are different tools with different
schemas, and this wave keeps them distinct.

Implementation: `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+AgenticFiles.swift`
(`agenticFilesTools`, 6 tools), `SwiftCodeTools+AgenticExecution.swift`
(`agenticExecutionTools`, 9 tools),
`SwiftCodeTools+AgenticGit.swift` (`agenticGitTools`, 19 tools),
`SwiftCodeTools+AgenticNetwork.swift` (`agenticNetworkTools`, 19 tools),
`SwiftCodeTools+AgenticCLI.swift` (`agenticCLITools`, 21 tools),
`SwiftCodeTools+AgenticCode.swift` (`agenticCodeTools`, 16 tools),
`SwiftCodeTools+AgenticData.swift` (`agenticDataTools`, 19 tools),
`SwiftCodeTools+AgenticPlanning.swift` (`agenticPlanningTools`, 8 tools).
Tests: `swiftcode/Tests/SwiftCodeMCPTests/SwiftCodeAgentic*Tests.swift` (one file
per slice).

## Host conventions

### Working-directory model

Every ported tool works inside one open workspace. Paths resolve
through the shared resolvers:

- `resolveFileReadingPath` (read paths) and
  `resolveFileWritingPath` (write paths): a leading `/` is
  workspace-root-relative, anything else is relative to the session
  working directory `dir_cd` sets, and `..` past the workspace root
  is an error, never a clamp. Legacy's Agentic tools took raw
  filesystem paths with no confinement at all; the port confines
  every path to the workspace, as every other ported file tool does.
  Results report workspace-relative paths where Legacy reported
  absolute ones.
- The git tools use the same resolver for `repositoryPath`, which is
  **optional** in the SwiftCode schema (Legacy requires it). Omitted, the
  tool operates on the session workspace root; given, it must resolve
  inside the workspace. `git_clone` is the exception: it has no
  `repositoryPath` in Legacy and keeps both of its params required.
- The code-analysis tools resolve through the strict static-analysis
  resolver (`staticAnalysisResolveScanPath`: blank → the workspace
  root; any `..` → the Legacy "Invalid path" failure; a missing path
  fails as "Path not found"). No path ever escapes the workspace.
- The data tools use strict `resolveFileWritingPath` for database
  files and session-aware `resolveFileReadingPath` for crash logs.

### Approval gate (Wave 2)

Legacy's Agentic tools run with no approval (its Autopilot mode
bypasses approval entirely — never ported). The port gates every
mutation before it happens:

- Text/file writes go through `commit()` (the full before/after text
  is shown to the reviewer before the file is written):
  `replace_text`, `run_formatter`, `remove_dependencies` (manifest
  edit), `todo_manager`, `database_migration` (via
  `approveFileWritingChange`).
- Non-file operations gate through an explicit `MCPChange` +
  `approve()` (Wave 2 §6.2 shape): `stop_running_process`,
  `run_formatter`, the git mutating tools (via Wave 3's
  `gitApproveChange`; the change's path is the workspace root,
  relative path `"."`), `rollback_changes`, `checkpoint_creator`
  (via `approveChangeWithoutFile()`, since `commit()` does not apply
  outside the workspace), `update_environment_variables` and
  `manage_secrets` save and `open_browser` (via
  `terminalApproveChange`, the Wave 4 shape for non-file
  operations), the CLI runners (via `terminalApproveChange`), the
  network writers (`download_file`, `upload_file`, mutating
  `http_request` methods, the `swift package` runs).
- In-memory mutations (`ai_context_memory`, `task_planner`,
  `checklist_plan`) and pure reads request no `commit()` /
  `approve()` call — there is no file change to propose — but the
  server-level read-only refusal still applies (the `mem_store` /
  `intel_plan_task` precedent).
- `MCPServer.run` refuses `writes: true` tools when the server is
  read-only, before the handler runs. The read-only actions of a
  writing tool (`git_stash` list/show, `git_worktree` list/prune)
  request no approval but are still refused in `readOnly` mode (the
  Wave 2 dry-run precedent). There is no Autopilot bypass anywhere
  in this wave.

### Subprocesses — argument vectors, never a shell

Every command runs as a fixed argument vector — never a shell:

- `terminalRunFixed` (off the main actor) with stdin closed, the
  never-wait-for-a-person environment (`terminalEnvironment` /
  Wave 3's `gitEnvironment()` for git), bounded at 300 s like
  `use_terminal` (the `sqlite3` tools use a 120 s bound;
  `stop_running_process` uses `/bin/kill` bounded at 30 s).
- Binaries resolve on `PATH` (`terminalResolveProgram`); a missing
  binary fails honestly with `use_terminal`'s message
  `Process execution failed: command '<program>' was not found (no
  executable on PATH or at that path).` Legacy's fixed
  `/usr/bin/...` / `/usr/local/bin/...` paths are not reproduced:
  those paths do not exist for most of these tools on a modern Mac
  (Homebrew installs to `/opt/homebrew/bin`).
- The `action` argument of the CLI tools is passed as a single argv
  element, so shell syntax inside it can never run; it is the CLI's
  own subcommand, not a command line. The same holds for git
  arguments: branch/ref/commit arguments are validated with Wave 3's
  validators (`gitIsValidRefName`, `gitIsValidRef`,
  `gitIsValidCommit`) before they reach git, and a leading `-` can
  never be parsed as a git flag.
- Legacy ran a real shell in exactly one place in this wave:
  `execute_terminal_command` ran `/bin/sh -c`. That is NOT
  reintroduced: the tool is served by the `use_terminal` alias
  (§19 of the catalogue), which tokenizes the command into an argv
  vector and rejects shell metacharacters.

### Result envelope and error style

- Legacy's Agentic tools return plain strings (no structured data
  map). The port returns `MCPToolResult.structured(_:summary:)`,
  which emits two text blocks: the structured data and a
  human-readable summary. Structured keys are the port's own, typed
  JSON values (integers, booleans, numbers) the way SwiftCode's other
  tools do. Tools whose Legacy result carries no data beyond the
  string return a plain text result only where the catalogue says
  so.
- Message assertions must compare `TestSupport.firstText`, never
  `resultText` with exact equality.
- Failure never returns partial data. A failed call returns a failure
  message and no success output. Failures are thrown as
  `MCPToolError` with Legacy's message text where Legacy has one, so
  the caller sees an `isError` result carrying that message.
- No result is ever invented. Where Legacy returned a canned string
  or hardcoded number, the port either computes the real value (see
  Deviations) or fails honestly naming the missing prerequisite (see
  the HONESTLY-FAILING entries in the catalogue).
- A missing required argument fails at the schema gate:
  `<tool>: missing the required argument "<name>"`. A present-but-
  empty string fails in the handler with Legacy's exact `execute()`
  guard message where Legacy has one (`Missing action or path`,
  `Missing path`, `Missing path or tag`, `Missing image`,
  `Missing action or package`, `Missing path or action`,
  `Missing containerID`, `Missing code`, `Missing projectPath`,
  `Missing root_path argument`, `Missing path argument`,
  `Missing repositoryPath or files`).

### Schemas

Schemas are Legacy's verbatim (same property names, same types,
same `required` lists), plus the `workspace` parameter Wave 1 adds
to every tool, and short descriptions on the parameters (Legacy
declares none, except `code_analysis.path` and
`project_indexing.root_path`). SwiftCode's `additionalProperties` is
`false`: aliases pass arguments through unchanged, so an Agentic
argument unknown to the alias target is rejected by validation
before the handler runs. Legacy parameter-name aliases are NOT
supported: SwiftCode's argument validation rejects unknown arguments
before the handler runs.

### Shared state (planning slice)

Slice-local state, all prefixed `agenticPlanning`:

- `AgenticPlanningPlanStore` — process-lifetime, per-workspace plans
  (`[workspace: [planId: plan]]` + current plan ID), NSLock-guarded,
  never persisted. Plans do not survive a server restart (the Wave 4
  `PlanningPlanStore` precedent). Progress weights: `completed` = 1,
  `in_progress` = 0.5, `queued` / `failed` = 0.
- `AgenticPlanningTask` / `AgenticPlanningPlan` — Codable plan model.
- `AgenticPlanningTodo` — Codable todo item, persisted in
  `.assist_temp/memory/todos.json`.
- `SwiftCodeCheckpoints/` — Application Support checkpoint store
  (catalogue §§137–138).
- Reused Wave 4 stores, no second store invented:
  `SwiftCodeMemoryGraphStore` (key `ai_context_memory`) for
  `ai_context_memory`; `PlanningPlanStore` (`"plan:<planId>"`) for
  `task_planner` interop with `intel_breakdown_task`;
  `.assist_temp/memory/` directory for the todo file.

### Network rules (network slice)

- **HTTPS only.** Legacy passed any URL string to `URLSession`. The
  port rejects non-HTTPS URLs (and URLs without a host) for all four
  network tools, the `external_resource_gateway` rule.
- **Response caps.** Legacy buffered responses unboundedly. The port
  caps response bodies (2 MB for text fetches, 10 MB for file
  downloads and uploads) and fails past the cap.
- **Approval.** Every network fetch that writes, every upload, every
  mutating HTTP method, every `swift package` run, and the manifest
  edit go behind the approval gate, like Wave 5's
  `dependency_resolution_engine`. Plain `fetch_url` GETs and
  safe-method `http_request` calls need no approval, like
  `external_resource_gateway`.

### Secrets (data slice)

A secret value never appears in tool output: `manage_secrets` `get`
reports existence only; `read_environment_variables` reports names
only; `update_environment_variables` names the variables set, never
their values; `security_scan` findings report file:line:kind only
and never output matched secret values, as `secrets_scan` does.

## Error tables

### Generic errors (all tools)

| Case | Message |
|---|---|
| Missing required argument (any tool) | `<tool>: missing the required argument "<name>"` (the server's argument-validation message; the handler's own `Missing required parameter: <name>` fires for a present-but-empty string) |
| Path escapes the workspace (any tool) | `<path> is outside the workspace folder <root>` |
| Approval refused (any gated tool) | The server's rejection message; nothing runs and nothing is written |
| Writes in `readOnly` server mode (any `writes: true` tool) | `<tool> changes files, and this SwiftCode MCP server is read-only. Start it with \`swiftcode mcp --allow-writes\`, or use agent mode in the SwiftCode IDE, where each change is reviewed as a proposal.` |

### Files slice (catalogue §§12–18)

| Case | Message |
|---|---|
| `read_multiple_files` unreadable file | `Failed to read file at <path>: <reason>` |
| `read_multiple_files` bad `paths` entry | `paths[<index>] must be a non-empty string path.` |
| `search_files` / `find_text` / `grep` missing directory | `Directory not found: <directory>` |
| `search_files` / `find_text` / `grep` non-directory | `Not a directory: <directory>` |
| `find_text` no matches | Success: `No matches found.` with empty `results` |
| `replace_text` empty target | `Target must not be empty.` |
| `replace_text` missing file | `Failed to read file at <path>: <reason>` |
| `grep` invalid pattern | `Regex search failed: <error>` |

### Execution slice (catalogue §§22–30)

| Case | Message |
|---|---|
| `run_linter` / `run_formatter` binary absent | Honest failure naming the missing binary and how to install it |
| `run_type_checker` / `run_static_analysis` / `run_benchmark` / `run_application` non-zero exit | Failure with the exit code and tail |
| `run_application` bad `target` (whitespace / leading `-`) | Refused before `swift` runs |
| `stop_running_process` PID ≤ 1 or SwiftCode's own PID | Refused before `kill` runs |
| `stop_running_process` non-zero `kill` exit | Failure carrying the exit code and `kill`'s message |
| `read_build_logs` missing log | Failure telling the caller to run a build first |
| `get_process_logs` any valid `pid` | Honest failure naming the per-process log buffer prerequisite |

### Git slice (catalogue §§33–52)

| Case | Message |
|---|---|
| Workspace not a git repository | Git's own "not a git repository" message |
| `git_add` empty `files` | `Missing repositoryPath or files` (Legacy's message) |
| `git_reset` bad `mode` | Validation failure (modes: `--soft/--mixed/--hard/--merge/--keep`) |
| `git_reset` bad `target` | Validation failure (`gitIsValidRef`) |
| `git_stash` / `git_worktree` bad `action` | Validation failure (stash: `push/pop/list/show/drop/apply/clear`; worktree: `list/add/remove/move/lock/unlock/prune/repair`) |
| `git_worktree` `add` / `remove` / `move` | Git's usage error (extra arguments Legacy's schema does not provide) |
| `git_pull` / `git_push` / `git_clone` any valid call | Honest failure naming the later-wave remote prerequisite |
| `git_merge` / `git_rebase` / `git_cherry_pick` conflict | Error names the conflicted files and the `--abort` escape |

### Network slice (catalogue §§53–71)

| Case | Message |
|---|---|
| Non-HTTPS URL (any of the four network tools) | Rejected (scheme + host checked) |
| Non-2xx response (`fetch_url`, `upload_file`, `http_request`) | Failure |
| `http_request` unknown method | Rejected (allow-list: GET, HEAD, OPTIONS, POST, PUT, PATCH, DELETE) |
| `http_request` non-string header | Rejected |
| Response over the cap | Failure past the cap (2 MB text, 10 MB download/upload) |
| `install_dependencies` / `update_dependencies` directory without `Package.swift` | Validation failure |
| `install_dependencies` / `update_dependencies` Swift absent | `Swift not found at /usr/bin/swift.` |
| `remove_dependencies` unknown package | `Package '…' not found in Package.swift at …` (file untouched) |
| `remove_dependencies` bad `packageName` | Validation failure (single token: no spaces, slashes, or `..`) |
| Honestly-failing tools, valid arguments | Exact prerequisite message (see the catalogue entry) |

### CLI slice (catalogue §§72–92)

| Situation | Result |
|---|---|
| Missing required argument (schema gate) | `<tool>: missing the required argument "<name>"` |
| Empty `action` / `path` / `package` / `tag` / `image` / `containerID` | Legacy's guard message (`Missing action or path`, `Missing path`, `Missing path or tag`, `Missing image`, `Missing action or package`, `Missing path or action`, `Missing containerID`) |
| `path` escapes the workspace | `<path> is outside the workspace folder <root>` |
| Working-directory `path` missing or not a directory | `path does not exist or is not a directory: <path>` |
| File `path` missing or a directory | `path does not exist or is not a file: <path>` |
| Binary not on `PATH` | `Process execution failed: command '<program>' was not found (no executable on PATH or at that path).` (`android_build` additionally names the missing `gradlew` wrapper; `docker_compose` names `docker-compose`; `python_pip` names `pip`) |
| Launch failure | `Process execution failed: could not launch <executable>` |
| Non-zero exit | Error `<display command> failed with exit code <n> (<duration>):\n<stderr or stdout>` with the structured data attached |
| Timeout (300 s) | Error `Command timed out after 300s: <display command>` with the partial data attached |

### Code slice (catalogue §§93–112)

| Case | Message |
|---|---|
| `detect_bugs` / `explain_code` missing/blank `code` | `Missing code` (Legacy's message) |
| `code_analysis` missing/blank `path` | `Missing path argument` (Legacy's message) |
| `code_index` / `project_audit` / `security_scan` / `license_scan` missing/blank `projectPath` | `Missing projectPath` (Legacy's message) |
| `project_indexing` missing/blank `root_path` | `Missing root_path argument` (Legacy's message) |
| Any code tool, `..` / escaping path | `Invalid path: path must stay inside the workspace and must not contain '..'.` |
| Any code tool, missing path | `Path not found: <path>` |
| Eight LLM tools (§§97–104), valid arguments | Exact `… is unavailable: … needs an LLM provider …` message (see the catalogue entry) |

### Data slice (catalogue §§113–132)

| Case | Message |
|---|---|
| `parse_json` non-object top level | `JSON is not a dictionary` (Legacy's dictionary-only rule) |
| `parse_json` invalid JSON | The decoder's message |
| `parse_yaml` unsupported construct | Rejected with the line number and the exact construct |
| `parse_xml` malformed XML / no root element | The parser's error / explicit failure |
| `sql_query` non-read-only statement | Fails before running (`SELECT`, `WITH`, `EXPLAIN` only) |
| `sql_query` / `database_schema_inspector` `sqlite3` absent | Honest failure naming `sqlite3` |
| `database_schema_inspector` non-SQLite file | sqlite3's own error ("file is not a database") |
| `database_migration` migration file missing / empty | Validation failure |
| `update_environment_variables` bad entry | Validation failure (non-empty names, no `=` or NUL; string values only) |
| `manage_secrets` `save` without `value` | Failure (Legacy silently reported "Secret saved" without saving anything) |
| `open_browser` non-http(s) URL | Validation failure (scheme + host checked) |
| `open_browser` `xdg-open` absent (Linux) | Honest failure naming it |
| `performance_profiler` / `memory_profiler` missing process / missing `ps` | Honest failure |
| `network_inspector` neither `netstat` nor `ss` installed | Honest failure naming both |
| `crash_analyzer` no recognised crash metadata | `Expected .crash or .ips format` |
| `symbolicate_crash_logs` no Binary Images section / dSYM binary with no image in the log / `atos` absent | Honest failure (on Linux: honest failure naming the missing `atos`) |
| `browser_automation` / `ui_inspector` / `accessibility_inspector` any valid call | Honest failure naming the missing prerequisite |

### Planning slice (catalogue §§133–141)

| Case | Message |
|---|---|
| `ai_context_memory` unknown `action` | Failure with the supported list |
| `progress_tracker` unknown ID | `No task or plan found with ID '…'` |
| `rollback_changes` unknown checkpoint ID | Failure naming `project_restore` for `project_snapshot` snapshots |
| `rollback_changes` checkpoint from another workspace | Failure (`rootPath` mismatch) |
| `checklist_plan` status outside the Legacy enum | Failure |
| `todo_manager` completing/removing a missing todo | Failure |
| `todo_manager` / `questions_handle` unknown action / invalid question | Failure (selection needs non-empty `options`) |

## Deviations from Legacy behaviour

Deviations are deliberate, and each is recorded in the catalogue
entry it applies to. The full list:

### Real deterministic work where Legacy returned hardcoded mock text or canned stubs

- `remove_dependencies` (§64) does real manifest surgery where
  Legacy's message was a stub.
- `progress_tracker` (§136) computes real progress, not Legacy's
  hardcoded `0.75`.
- `code_analysis` (§107) computes real numbers instead of returning
  hardcoded mock text; the `for` parameter label counts as a
  decision point.
- `code_index` / `project_indexing` (§§108–109) build a real
  in-memory index instead of returning canned success strings; the
  index is not persisted and has no embeddings. `project_indexing`
  never returns Legacy's invented "124 symbols found across 42
  files".
- `project_audit` (§112) runs seven real checks instead of returning
  a canned one-liner.
- `security_scan` (§110) scans for real secret / endpoint patterns
  instead of returning "0 issues found".
- `license_scan` (§111) reports found license files / SPDX IDs /
  `Package.resolved` dependencies and explicitly does not determine
  dependency license terms, instead of claiming all dependencies
  are permissive.
- `detect_bugs` (§105) scans the supplied code instead of running
  swiftlint on the working directory (Legacy never passed the
  supplied `code` anywhere).
- `explain_code` (§106) returns the static structural explanation
  instead of an LLM explanation.
- `parse_yaml` / `parse_xml` / `parse_markdown` (§§114–116) are real
  parsers where Legacy returned hardcoded "(simulated)" strings.
- `sql_query` / `database_schema_inspector` /
  `database_migration` (§§117–119) run real SQLite work where Legacy
  returned hardcoded strings.
- `performance_profiler` / `memory_profiler` /
  `network_inspector` / `crash_analyzer` /
  `symbolicate_crash_logs` (§§127–131) take real measurements and
  parse real logs where Legacy returned hardcoded strings.
- The eight LLM-backed code tools (§§97–104), the seven GitHub tools
  (§§65–71), `web_search` / `documentation_search` /
  `api_reference_search` / `package_search` / `dependency_audit`
  (§§57–61), and `browser_automation` / `ui_inspector` /
  `accessibility_inspector` (§§124–126) fail honestly instead of
  returning Legacy's canned strings.
- The planning tools (§§133–141) implement the behaviour the stub
  strings promise, grounded in real SwiftCode state, rather than copying
  stub bodies: `ai_context_memory` stores in the Wave 4 memory
  graph; `task_planner` mints real plans; `todo_manager` keeps a
  real todo file; `progress_tracker` computes real progress;
  `checkpoint_creator` / `rollback_changes` copy and restore real
  trees; `questions_handle` returns a real pending handoff.

### Stores

- `checkpoint_creator` / `rollback_changes` (§§137–138) use their
  own `SwiftCodeCheckpoints/` store, separate from Wave 7's
  `SwiftCodeSnapshots/` — a checkpoint can never be mistaken for a
  project snapshot, and `rollback_changes` refuses snapshot IDs.

### Secrets

- `manage_secrets` `get` (§122) reports existence only; Legacy
  returned the stored value.
- `read_environment_variables` (§120) reports names only; Legacy
  dumped `KEY=value` lines.

### Reads

- `view_container_logs` (§92) is the one pure read among the CLI
  tools (`docker logs`, no approval gate, `writes: false`).

### Search

- `semantic_query_engine` (serving `semantic_code_search`, §95)
  needs no LLM: Legacy's search is a substring scan with three
  keyword expansions.

### Files slice

- `read_multiple_files` (§12) reads in request order and returns in
  request order; Legacy stored the results in a dictionary, so its
  blocks came out in nondeterministic order.
- `search_files` / `find_text` / `grep` (§§14–15, §17): a missing
  directory (or a path that is not a directory) fails explicitly;
  Legacy's enumerator returned `nil` for a missing directory, so
  Legacy silently returned an empty result.
- `replace_text` (§16): an absent target succeeds with
  `replacementCount` 0 and **no** write and no approval round-trip
  (Legacy rewrote the identical file); an empty target is rejected
  with `Target must not be empty.` (Legacy would have inserted the
  replacement between every character).
- `grep` (§17): Legacy spawned `/usr/bin/grep -r -n`; the port
  implements the search natively — no subprocess — and skips hidden
  files, files over 1 MB, binary-extension files, and non-UTF-8
  files. Legacy's grep would also report binary files and descend
  into hidden directories.
- `glob_search` (§18): Legacy ran `/usr/bin/find . -name <pattern>`
  from the process working directory — unscoped and cwd-dependent.
  The port scopes to the workspace root and implements the match
  natively with `fnmatch` (no subprocess); hidden files and the
  top-level skipped directories (`.git`, `.build`, …) are pruned.

### Execution slice

- `run_linter` / `run_formatter` (§§22–23): Legacy passed the raw
  `path` string with the path itself as the working directory (fails
  to launch when the path is a file); the port passes the resolved
  absolute path. Legacy waited unboundedly; the port bounds at 300 s.
- `run_application` (§27): Legacy returned the combined output even
  on failure; the port reports a non-zero exit as a failure.
- `stop_running_process` (§28): Legacy called `kill()` with no guard
  and no approval; the port refuses PID ≤ 1 and SwiftCode's own PID,
  gates through approval, and goes through `/bin/kill` instead of
  the C API.
- `read_build_logs` (§30): over 8000 characters the port returns the
  last 8000 with a truncation marker; Legacy returned the whole file.
- `execute_terminal_command` (§19): Legacy ran a real shell
  (`/bin/sh -c`); the port must NOT reintroduce shell execution.

### Git slice

- `repositoryPath` optional (Legacy: required) — defaults to the
  workspace root; must stay inside the workspace (Legacy accepted
  any absolute path).
- Legacy's read tools return `stdout` unchecked, so a failure
  (unknown file, unknown ref, no repository) silently returns an
  empty string. The port throws git's own message on a non-zero exit
  instead.
- Legacy passes `branch`, `mode`, `target`, `action` and `hash` to
  argv unchecked. The port validates them first (branch names with
  the strict allow-list, refs, hashes, reset modes against
  `--soft/--mixed/--hard/--merge/--keep`, stash actions against
  `push/pop/list/show/drop/apply/clear`, worktree actions against
  `list/add/remove/move/lock/unlock/prune/repair`).
- `git_worktree` (§52) keeps Legacy's single-token `action`: `add`,
  `remove` and `move` need extra arguments Legacy's schema does not
  provide, so git reports its usage error for them — the Legacy
  limitation, preserved honestly rather than papered over with an
  invented schema.
- `git_stash show` (§42) keeps Legacy's plain form (no `-p`); Wave
  3's `git_stash_operator` shows with `-p`.
- `git_reset` (§41) is registered `potentiallyDestructive` (its
  Legacy default is `--hard`, which discards uncommitted changes).

### Network slice

- HTTPS-only URLs (Legacy passed any URL string to `URLSession`).
- Response caps (2 MB text, 10 MB download/upload); Legacy buffered
  unboundedly.
- `http_request` (§56) method allow-list (Legacy passed any method
  string through).
- `install_dependencies` / `update_dependencies` (§§62–63) require a
  `Package.swift` in the directory and fail honestly on Linux with
  "Swift not found at /usr/bin/swift."

### CLI slice

- Binaries resolve on `PATH`, not Legacy's fixed `/usr/bin/...` /
  `/usr/local/bin/...` paths.
- `android_build` (§74) prefers the project's `gradlew` wrapper when
  an executable one exists, falling back to `gradle` on `PATH`.
- `python_pip` (§82) falls back to `pip3` when `pip` is not on
  `PATH`; the missing-binary failure still names `pip`.
- `docker_build` (§88) runs with the build context directory as its
  working directory and passes `.` as the context (equivalent to
  Legacy's `docker build -t <tag> <path>`, keeps the context inside
  the workspace).
- `docker_compose` (§90) falls back to `docker compose -f <path>
  <action>` (the v2 subcommand) when `docker-compose` is not on
  `PATH` but `docker` is.

### Data slice

- `parse_json` (§113) keeps Legacy's dictionary-only rule (a
  non-object top level fails with "JSON is not a dictionary").
- `sql_query` (§117): read-only statements only; writes go through
  `database_migration`, never through this tool.
- `database_migration` (§119): `-bail` stops at the first failing
  statement, but the file's own transaction handling applies — a
  migration file without `BEGIN` can leave a partial apply behind on
  error. The port does not wrap the file in a transaction, since a
  file that already contains `BEGIN` / `COMMIT` would then fail.
- `manage_secrets` (§122): `save` without a `value` fails (Legacy
  silently reported "Secret saved" without saving anything).
- `open_browser` (§123): http(s) URLs only (Legacy passed any string
  to `open`).
- `network_inspector` (§129): a connection-table snapshot, not
  packet capture (capture would need a privileged capture backend).

### Planning slice

- `ai_context_memory` (§133): Legacy accepts any `action` string and
  echoes it without doing anything. The port defines the real
  vocabulary and fails unknown actions instead of echoing a fake
  result.
- `progress_tracker` (§136): an unknown ID fails with `"No task or
  plan found with ID '…'"` — no progress is invented.
- `rollback_changes` (§138) is NOT Wave 6's `safe_undo`, which is
  honestly-failing because it needs a previous-snapshot store the
  host does not keep; `rollback_changes` has its own store (the
  checkpoints `checkpoint_creator` writes), so it can genuinely
  restore.

### Schema additions

- Per-property schema descriptions were added where Legacy declares
  none; types and `required` lists are verbatim.
- The `workspace` parameter was added to every tool.

## Collision resolutions

### Seven git aliases removed in Wave 8

The Agentic tools now own these names, so the alias entries were
removed from `MCPServer.toolAliases` (the operator tools remain
callable by their own names — no capability is lost, only the
shorthand):

| Removed alias | Former target | Now owned by |
|---|---|---|
| `git_status` | `version_control_operator` | `git_status` (catalogue §33, PORTED) |
| `git_diff` | `version_control_operator` | `git_diff` (catalogue §34, PORTED) |
| `git_commit` | `version_control_operator` | `git_commit` (catalogue §36, PORTED) |
| `git_branch` | `version_control_operator` | `git_branch` (catalogue §38, PORTED) |
| `git_stash` | `git_stash_operator` | `git_stash` (catalogue §42, PORTED) |
| `git_blame` | `git_blame_inspector` | `git_blame` (catalogue §46, PORTED) |
| `git_log` | `git_log_viewer` | `git_log` (catalogue §47, PORTED) |

Any slice material proposing those seven as aliases is stale and was
corrected in the merge: the Agentic tool owns the name.

### Five Agentic aliases added in Wave 8

| Added alias | Target | Agentic tool |
|---|---|---|
| `list_directory` | `dir_read` | catalogue §13, ALREADY-SERVED |
| `execute_terminal_command` | `use_terminal` | catalogue §19, ALREADY-SERVED |
| `xcode_build` | `project_build` | catalogue §31, ALREADY-SERVED |
| `semantic_code_search` | `semantic_query_engine` | catalogue §95, ALREADY-SERVED |
| `cross_reference_search` | `symbol_reference_graph` | catalogue §96, ALREADY-SERVED |

Each was verified param-compatible live before being added (the
Agentic tool's required parameters are a subset of the target's
parameters with the same names and types; aliases pass arguments
through unchanged and `Schema.object` rejects unknown keys).

### Six exact-ID duplicates — no second registration

| ID | Already-registered tool | Catalogue |
|---|---|---|
| `tree_view` | Assist `tree_view` (Wave 1) | §11 |
| `git_cherry_pick` | Assist `git_cherry_pick` (Wave 3), aligned in place (below) | §50 |
| `swift_package_manager` | Assist `swift_package_manager` (Wave 7) | §32 |
| `take_screenshot` | Assist `take_screenshot` (Wave 4) | §132 |
| `call_hierarchy` | Assist `call_hierarchy` (Wave 3) | §93 |
| `dependency_graph` | Assist `dependency_graph` (Wave 3) | §94 |

### `git_cherry_pick` aligned in place

`git_cherry_pick` is NOT in `SwiftCodeTools+AgenticGit.swift`: it is the
Wave 3 Assist tool in `SwiftCodeTools+Git.swift`, aligned in place to
accept Agentic spellings. Optional `hash` + `repositoryPath`
properties were added, `required` changed from `["commit"]` to `[]`,
and the handler uses `commit ?? hash`, with the repo resolved from
`repositoryPath` or the workspace root. `noCommit` keeps Legacy's
**string** schema. One registration serves both shapes instead of a
second registration.

### Near-duplicates considered and rejected

An alias is only valid when the Agentic tool's required parameters
are a subset of the target's parameters with the same names and
types. The following were checked and rejected as aliases (each is
ported as distinct, or honestly failing as distinct, per the
catalogue entry):

- `read_multiple_files` vs `file_read` (single-file only).
- `search_files` vs `file_list` (`glob` + `limit` over the
  workspace, not `directory` + `pattern`).
- `find_text` vs `search_text` (workspace-wide, case-insensitive,
  single `pattern`).
- `replace_text` vs `code_replace` (params compatible but behaviour
  differs — `code_replace` fails on a missing or multi-occurring
  target unless `allowMultiple` is set, and an alias cannot inject
  `allowMultiple: true`).
- `grep` vs `search_regex` (workspace-wide, no `directory`).
- `glob_search` vs `file_list` (`glob`, not `pattern`).
- `run_linter` vs `code_lint` (built-in heuristics, never SwiftLint).
- `run_formatter` vs `code_format` (built-in formatter, never
  SwiftFormat).
- `run_type_checker` vs `project_build` (no build-tests action).
- `run_static_analysis` vs `compiler_diagnostics_engine` (runs the
  session build, does not pass `-analyze`).
- `run_benchmark` vs `performance_benchmark` (no `projectPath`).
- `run_application` vs `run` (no `projectPath` or `target`).
- `stop_running_process` vs `stop` (stops a host-managed run by
  `runId`, no `pid`).
- `read_build_logs` vs `build_log_analyze` / `build_log` (no
  `projectPath`).
- `git_checkout` vs `git_branch_manager` `switch` (`action` +
  `branchName` vs `branch`).
- `git_reset` vs `version_control_operator` `rollback` (`ref` vs
  `mode`/`target`).
- `install_dependencies` / `update_dependencies` vs
  `swift_package_manager` (`projectPath` vs `packageDir` + required
  `action`) and vs `package_dependency_update` (workspace root only,
  no `projectPath`).
- `dependency_audit` vs `package_dependency_audit` (pins, not
  vulnerabilities).
- `fetch_url` / `http_request` vs `external_resource_gateway`
  (JSON-only / GET-only; the Agentic tools return raw text and allow
  any method, headers, and body).
- `explain_code` vs `intel_explain_code` (required `path` vs inline
  `code`).
- `security_scan` vs `security_audit_scanner` / `secrets_scan`
  (`path` vs `projectPath`).
- `license_scan` vs `dependency_licenses` (no parameters vs required
  `projectPath`).
- `code_analysis` vs `code_metrics_analyzer` /
  `complexity_analysis` / `code_summary` (narrower tools; the
  Agentic tool is an aggregate report with its own output shape).
- `code_index` / `project_indexing` vs `source_graph_builder` /
  `extract_code_symbols` (graph / one file's symbols vs a
  project-wide declaration index).
- `generate_code` vs `code_generate` (`path` + `template` vs
  free-form `prompt`).
- `refactor_code` vs `code_refactor` (`path` + `action` vs inline
  `code` + `instructions`).
- `review_code` vs `code_review` (no parameters vs inline `code`).
- `fix_bugs` vs `intel_autofix` (`path` vs inline `code` + `issue`).
- `generate_unit_tests` / `generate_integration_tests` vs
  `intel_generate_tests` (`path`, writes through `commit()`, vs
  inline `code`, returns text).
- `generate_documentation` vs `docstring_generator` (`declaration`
  header vs arbitrary `code`).
- `parse_json` vs `json_validate` / `json_validator_tool` (inline
  string vs file `path`).
- `parse_yaml` vs `yaml_parser_tool` / `yaml_validate` (inline
  string vs file `path`).
- `crash_analyzer` vs `crash_log_parse` (`logPath` vs `path`).
- `read_environment_variables` /
  `update_environment_variables` vs `environment_variable_manager`
  (host process environment vs workspace `.env` files; `variables`
  map is not a target parameter).
- `performance_profiler` / `memory_profiler` vs
  `process_monitor_tool` (required `pid` vs optional `filter`).
- `ui_inspector` / `accessibility_inspector` vs `use_app`
  (`app_identifier` + `action` vs no arguments and no target
  application).
- `network_inspector` vs `use_system` (`operation` required, vs no
  arguments and a traffic-inspection purpose).
- `task_planner` vs `intel_plan_task` (`goal` vs `task`).
- `todo_manager` vs `todo_scan` / `todo_fixme_scanner` (a
  free-standing todo list vs scanning source for task comments).
- `progress_tracker` vs `session_progress_report` (one plan/task by
  ID vs engineering phases).
- `checkpoint_creator` vs `project_snapshot` (`description`,
  required, vs `message`, optional; separate stores by design).
- `rollback_changes` vs `project_restore` (`checkpointID` vs
  `snapshot_id`; separate stores by design).
- `questions_handle` vs `plan-AskUser` (array of questions with
  per-question `input_type` vs one question with `choices` /
  `allowsMultipleAnswers`).

## Param-caveat register

These pre-existing aliases serve the Assist alias contract. They are
NOT silently "fixed" — the alias targets serve the Assist shape, and
an Agentic-schema call fails argument validation as described. The
register records each caveat exactly as found.

| Agentic ID | Alias target | Caveat |
|---|---|---|
| `edit_file` | `code_replace` | Agentic takes `path` + `edits[]` of `{search, replace}` pairs, replacing **all** occurrences of each. The target takes a single `target` / `replacement` pair and fails on a missing or multi-occurring target unless `allowMultiple` is set. An Agentic-schema call fails validation (unknown `edits` key). The nearest ported behaviour for a multi-edit is `code_multi_edit`, whose `edits` array carries a per-edit `path` plus `content` or `search` + `replace` — a different shape again. |
| `rename_file` | `file_rename` | Agentic renames a file **or directory** to an arbitrary `newPath` (a `moveItem`, i.e. it can also move across directories). The target takes `newName`, a single path component within the same directory, and rejects anything else. An Agentic-schema call fails validation (unknown `newPath` key). |
| `copy_file` | `file_copy` | Agentic takes `sourcePath` / `destinationPath`; the target takes `source` / `destination`. An Agentic-schema call fails validation (unknown keys). |
| `move_file` | `file_move` | Agentic takes `sourcePath` / `destinationPath`; the target takes `source` / `destination`. An Agentic-schema call fails validation (unknown keys). |
| `create_file` | `file_create` | Params are compatible, but the behaviour differs on an existing file: Agentic `create_file` overwrites unconditionally, while `file_create` refuses an existing file unless `overwrite=true`. An Agentic caller that relied on silent overwrite gets a refusal instead. |
| `tree_view` | `tree_view` (registered, same ID) | Agentic takes a required `directory` plus `depth` (default 2) and renders via `/usr/bin/tree` with a manual fallback. The registered tool takes `path?` + `maxDepth?` (default depth 3, emoji rendering). An Agentic-schema call fails validation (unknown `directory` key). |
| `run_tests` | `project_test` | Agentic requires `projectPath`; `project_test` has NO `projectPath` parameter (its params are `scheme` and `testPlan`). A `run_tests` call carrying `projectPath` is rejected as an unknown argument; the alias only works when the caller omits `projectPath` (and then the project is the open workspace). |
| `swift_package_manager` | `swift_package_manager` (registered, same ID) | Widening caveat: the ported tool is narrower than the Agentic one — it allowlists actions (`resolve`, `update`, `status`, `dump_manifest`, `describe`) and takes an optional `packageDir` instead of a required `path`, so arbitrary `swift package <action>` invocations (e.g. `clean`, `reset`, `generate-xcodeproj`) are not served by the existing registration. That narrower surface is the Assist tool's design; serving the arbitrary-action surface is a widening of the existing tool, not a second registration. |
| `call_hierarchy` | `call_hierarchy` (registered, same ID) | Param name mismatch: the ported tool requires `function`; the Agentic schema requires `symbol`. An Agentic caller passing `symbol` fails required-argument validation against the ported schema. |
| `dependency_graph` | `dependency_graph` (registered, same ID) | Param name mismatch: the ported tool takes an optional `path` (defaults to the workspace root); the Agentic schema requires `projectPath`. An Agentic caller passing `projectPath` is rejected as an unknown argument. |
| `take_screenshot` | `take_screenshot` (registered, same ID) | Param delta: the Agentic tool takes `path` (required); the served tool takes no `path` and chooses the artifact path itself (`capture_mode` / `display_id` / `include_cursor` / `image_format` / `purpose`, all optional). A caller that needs a screenshot at a specific path cannot express that through the served tool. |
| `ask_user` | `plan-AskUser` | Param mismatch: the Agentic caller passes `question`, `input_type`, `options`; `plan-AskUser` requires `question`, `allowsMultipleAnswers`, `choices`. An Agentic-style call fails validation (`allowsMultipleAnswers` / `choices` missing; `input_type` / `options` rejected as unknown keys). The alias is Legacy's own registry alias, kept as-is. |

## Evidence

| Claim | Level | Source |
|---|---|---|
| Host conventions (cwd model, resolvers, approval gate, subprocess shape, result envelope, error style) | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift` (`MCPWritePolicy`, `run`, `readOnlyMessage`, `toolAliases`), `SwiftCodeTools+Content.swift` (`commit`), `SwiftCodeTools+TerminalSupport.swift` (`terminalRunFixed`, `terminalResolveProgram`, `terminalEnvironment`, `terminalApproveChange`), `SwiftCodeTools+FileReading.swift` (`resolveFileReadingPath`), and the eight `SwiftCodeTools+Agentic*.swift` implementation files, read directly |
| Approval gate shapes (`commit()`, explicit `MCPChange` + `approve()`, `approveChangeWithoutFile()`, `approveFileWritingChange`, `gitApproveChange`, `terminalApproveChange`) | 1 | The implementation files above and `specs/ide/assist-approval-model.md` §6 |
| Per-slice conventions, error tables, and deviations | 1 | The eight Wave 8 slice specifications (merged into the catalogue and this spec) and the Wave 8 implementation files, read directly |
| 7 git aliases removed and 5 Agentic aliases added in Wave 8; 6 exact-ID duplicates; `git_cherry_pick` aligned in place | 1 | `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift` (`toolAliases` and its Wave 8 comment) and `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Git.swift` (`git_cherry_pick` registration), read directly; live `tool("…")` counts in the eight `SwiftCodeTools+Agentic*.swift` files |
| Param-caveat register entries | 1 | `MCPServer.toolAliases` and the target tools' schemas in `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+*.swift`, read directly; the slice specifications' per-tool param tables |
| Near-duplicate rejections | 1 | Target tools' schemas in `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+*.swift`, read directly; the slice specifications' alias-compatibility checks |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
