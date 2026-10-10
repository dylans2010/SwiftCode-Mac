# ASSIST TOOLKIT ARCHITECTURE & ROUTING

## 1. The Dual-Toolkit Architecture ("System" vs. "Cloud")
SwiftCode Assist features a flexible dual-toolkit execution model selected by the user via the "Assist Toolkit" picker in the user interface:

### A. "System" Toolkit (Default macOS IDE Toolset)
- **Execution Transport**: Native SwiftCode tools executed over the Unix IPC bridge via `AssistToolRegistry`.
- **Target Environment**: Local macOS developer environment with direct access to Xcode toolchains, SwiftPM, project targets, Git repositories, and local system services.
- **Tools Exposed**:
  - File tools: `file_read`, `file_write`, `file_append`, `file_delete`, `file_move`, `file_copy`, `file_rename`, `file_create`, `dir_create`, `dir_delete`, `dir_read`, `tree_view`, `code_generate`.
  - Search & Discovery: `search_text`, `search_regex`, `search_symbol`, `dependency_graph`, `code_summary`.
  - Code Editing: `code_replace`, `code_multi_edit`, `code_refactor`, `code_format`, `code_insert`, `code_mutation_engine`, `patch_application_engine`.
  - Build & Testing: `project_build`, `project_test`, `compiler_diagnostics_engine`, `automated_repair_engine`, `dependency_resolution_engine`.
  - Git & Recovery: `version_control_operator`, `project_snapshot`, `project_restore`, `project_diff`, `project_changelog`, `safe_undo`.
  - Planning & Workers: `execution_plan`, `plan-AskUser`, `use_workers`, `intel_plan_task`, `intel_breakdown_task`.
  - Integrations: `use_terminal`, `use_mcp`, `use_composio`, `search_skills`.

### B. "Cloud" Toolkit (Google Antigravity Cloud Toolset)
- **Execution Transport**: Direct Google Antigravity SDK built-in cloud runtime tools dispatched via cloud agent execution.
- **Target Environment**: Sandboxed cloud workspace runtime environments.
- **Tools Exposed**:
  - `view_file`: Cloud workspace file inspection.
  - `create_file`: Cloud workspace file creation.
  - `edit_file`: Structured patch block modification.
  - `run_command`: Cloud container/terminal shell execution.
  - `list_directory`: Cloud directory traversal.
  - `search_directory`: Cloud repository text search.
  - `search_web` & `read_url_content`: Online documentation and HTTP content fetching.
  - `start_subagent`: Cloud worker delegation.

---

## 2. Dynamic Routing Discipline
1. **Schema Delivery**: The active session dynamically delivers the tool catalog corresponding strictly to the chosen toolkit.
2. **Catalog Strictness**: The agent must strictly invoke the tools currently presented in its active schema catalog. Never attempt to call a System-only tool in Cloud mode or a Cloud-only tool in System mode.
3. **No Cross-Talk Confusion**: Do not describe the native Unix IPC mechanism when operating in Cloud mode, and do not reference Cloud container limitations when running locally on macOS.
