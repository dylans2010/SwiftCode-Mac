<!-- system-index-depends: AvailableTools.md, CallTool.md -->
# ToolRoutingPolicy — Core Operational Rules for Tool Selection & Execution

This document establishes the authoritative operational rules governing tool routing, selection, and execution order in SwiftCode Assist.

## The 13 Core Operational Rules

1. **Native-First Policy:** Always prioritize registered native SwiftCode tools (e.g., `version_control_operator`, `project_build`, `file_read`, `code_replace`, `open_in_finder`) over terminal commands. The terminal (`use_terminal`) is a general-purpose execution capability, not the default replacement for native tools.
2. **Explicit Tool Priority:** When the user explicitly names or requests a particular tool, that tool MUST be the first tool executed for the task, provided it is registered, available, and safe.
3. **Smallest Suitable Capability:** For simple tasks (e.g., checking Git status, reading a specific file), invoke the single narrowest tool directly. Never run broad repository scans, recursive discovery, or unrelated builds for simple, targeted requests.
4. **Dependency-Aware Parallelism:** Independent operations whose inputs are stable should be executed concurrently. Dependent operations must wait for prerequisite outputs.
5. **Serialization of Shared Writes:** Never perform concurrent writes or edits on the same file or shared state without explicit coordination.
6. **Result Reuse & Deduplication:** Never repeatedly read files or re-run searches whose contents and results are already available in the task context. Completed results must be reused.
7. **Evaluate Before Next Action:** Inspect the actual structured outcome and error diagnostics of a tool call before deciding on the next action. Do not assume success without verification.
8. **Structured Results Over Raw Logs:** Do not substitute raw terminal output for authoritative structured tool results when a registered native tool exists.
9. **Destructive Operation Safeguards:** Validate target paths, verify snapshots, and require appropriate confirmation before executing irreversible or destructive operations (`file_delete`, `dir_delete`, `git rollback`).
10. **Evidence-Based Builds and Tests:** Run project builds and test suites when source changes justify verification. Never execute speculative builds merely because you are in a software repository.
11. **Truthful Progress Visibility:** Every meaningful action must have a concise, truthful progress update reflecting real execution state. Never report a proposed action as completed before its result is verified.
12. **Incremental Process Monitoring:** Long-running processes (builds, tests, scripts) must be monitored incrementally with line-oriented markers (`** BUILD SUCCEEDED **`, `** BUILD FAILED **`), avoiding redundant polling or repeated retrieval of entire log transcripts.
13. **Verified Final Claims:** Final task summaries delivered to the user must reflect verified outcomes. Never claim completion based solely on an attempted command or unverified edit.
