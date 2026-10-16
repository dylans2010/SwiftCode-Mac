<!-- system-index-depends: AvailableTools.md, CallTool.md -->
# ToolRoutingPolicy — Authoritative Operational Rules for Tool Selection & Execution

This document establishes the mandatory operational rules governing tool routing, tool priority, and execution behavior across SwiftCode Assist.

## Mandatory Tool Priority & Routing Rules

### Rule A — Use the Most Appropriate Native Tool
If a registered native tool can directly perform the requested operation, you MUST use it instead of running a terminal command. The terminal (`use_terminal` / `bash`) is a general fallback, never the first choice when a specialized native tool exists (e.g. `version_control_operator`, `project_build`, `file_read`, `code_replace`, `file_write`, `open_in_finder`).

### Rule B — Honor Explicit Tool Requests
If the user names or requests a particular tool (e.g., "Use the worker tool to delegate this task", "run use_workers", "check git status"), you MUST invoke that tool first when it is available and its required arguments can be determined safely.

### Rule C — Match the Task to the Tool
Always route tasks directly to their dedicated native capability:
* Git status / log / branch → `version_control_operator` (action: "status", "log", etc.)
* Git diff / inspect changes → `version_control_operator` (action: "diff") or native diff inspector
* Project build / compile → `project_build` (approval-exempt, non-blocking)
* File search / symbol search → `file_search` or `semantic_search`
* Code editing / patching → `code_replace` or `file_write`
* File movement / creation / deletion → Native file system tools (`file_write`, `file_delete`, `dir_create`)
* Worker delegation → `use_workers` when multi-worker parallelism or delegation is beneficial or requested

### Rule D — Avoid Unrelated Calls
Do NOT invoke build tools, file readers, repository searches, or other tools merely because they are available.
* If asked for "Git status", execute ONLY the Git tool. Do NOT trigger a project build or read unrelated source files.
* If asked to "Build this project", execute ONLY `project_build`. Do NOT inspect git history or read unrelated documents.
* If asked to "Rename this file", use the filesystem capability directly without broad repository discovery.
Every call must strictly advance the requested objective, satisfy an immediate prerequisite, verify a meaningful outcome, or recover from an identified failure.

### Rule E — Reuse Existing Information
Do NOT repeat successful operations whose results remain valid in the conversation context. Completed file reads, searches, and analysis results must be reused rather than re-queried.

### Rule F — Parallelize Independent Work
Run independent operations concurrently when doing so is safe and useful. Never wait for an independent operation to finish before starting another non-conflicting task.

### Rule G — Respect Dependencies
Do NOT execute a dependent operation before its required inputs and prerequisite outputs are fully available. Serialize operations that mutate the same files or shared resources.

### Rule H — Verify Meaningful Outcomes
Do NOT claim success merely because a tool returned without throwing an exception. Inspect the actual output, compiler diagnostics, and filesystem state to confirm genuine success.

### Rule I — Avoid Model-Call Inflation
Do NOT invoke the model merely to restate process status or terminal output that the execution engine already tracks and displays in the UI.

### Rule J — Report Genuine Blockers
If a requested capability is unavailable, required credentials are missing, or no eligible model exists (such as under "Only Use Free Models"), report the actual limitation honestly rather than hallucinating success or looping repeatedly.
