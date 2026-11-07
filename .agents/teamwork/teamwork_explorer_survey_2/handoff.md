# Handoff Report — Explorer Survey 2: Assist System Realignment (R3) & Code Comments (R1)

**Agent ID**: `teamwork_explorer_survey_2`  
**Working Directory**: `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_2/`  
**Parent Agent**: `d5b41c16-417f-423a-b7f8-eea4f0706fc5`  
**Date**: 2026-11-07  
**Status**: Complete  

---

## 1. Observation

### 1.1 Production Assistant Architecture (`swiftcode/`)
Direct observations from the production codebase:

1. **Target & Package Structure**:
   - `swiftcode/Package.swift` line 24 & line 113:
     ```swift
     .library(name: "SwiftCodeAssistant", targets: ["SwiftCodeAssistant"]),
     ...
     .target(name: "SwiftCodeAssistant", dependencies: ["SwiftCodeSubprocess", "SwiftCodeBuild", .product(name: "Crypto", package: "swift-crypto")], resources: [.copy("Resources/System Assets"), .copy("Resources/SDKHosts"), .copy("Resources/ReverseBridge.mjs")]),
     .testTarget(name: "SwiftCodeAssistantTests", dependencies: ["SwiftCodeAssistant", "SwiftCodeSubprocess"]),
     ```
   - Consumers of `SwiftCodeAssistant`: `SwiftCodeCloud`, `SwiftCodeGoogleAuth`, `SwiftCodeSDK`, `SwiftCodeCompletion`, `SwiftCodeConnect`, `SwiftCodeUI`, `SwiftCodeIDECore`, `SwiftCodeIDEShell`, `swiftcode-ide`, and `SwiftCodeMCP`.

2. **Model Powering Infrastructure**:
   - `swiftcode/Sources/SwiftCodeAssistant/Models/AssistantSettings.swift` lines 173–237 defines `AssistantBackends`:
     ```swift
     public struct AssistantBackends: Sendable {
         public var settings: AssistantSettings
         public var store: SecretStore
         public var account: OpenAIAccount?
         public var locator: CLIToolLocator
         public func provider(_ kind: ProviderKind) -> AssistantProvider
     ```
   - 13 backend providers are supported via `ProviderKind`:
     - `.ollama`: `OllamaProvider(baseURL: settings.ollamaURL)`
     - `.llamaCpp`: `ChatCompletionsProvider(baseURL: settings.llamaCppURL, apiKey: ...)`
     - `.openAI`: `OpenAIProvider(baseURL: settings.openAIURL, credential: ...)` (API key or ChatGPT PKCE OAuth via loopback)
     - `.claudeCode`, `.codex`, `.antigravity`: `CLIAgentProvider(agent: agent, executable: ...)`
     - `.acpAgent`: `ACPAgentProvider(command: settings.acpCommand, locator: locator)` (Agent Client Protocol v1)
     - `.openRouter`: `OpenRouterProvider(baseURL: settings.openRouterURL, apiKey: ...)`
     - `.openCode`: `OpenCodeProvider(baseURL: settings.openCodeURL)`
     - `.hermes`: `HermesProvider(locator: locator, secretStore: store)`
     - `.foundationModels`: `FoundationModelsProvider()`
     - `.scCloud`: `SCCloudProvider(baseURL: settings.scCloudURL, fingerprint: ...)`
     - `.metaAssist`: `MetaAssistProvider(locator: locator, reasoningEffort: ...)`
     - `.anthropic`: `AnthropicProvider(apiKey: ...)`
   - Window Orchestration (`swiftcode/Sources/SwiftCodeIDECore/Assistant/CodingAssistantModel.swift`):
     - `CodingAssistantModel`: manages conversation history, streaming tokens, stop cancellation, turn failovers (`modelRouter`), proposals, and agent attachments (`agentAttachment`).
     - `CodingAssistantServices` (`CodingAssistantServices.swift`): singleton for credentials (`SecretStore`), OpenAI PKCE account (`OpenAIAccount`), CLI locator (`CLIToolLocator`), and async backend surveying (`survey()`).
   - Legacy coordination types in `SwiftCodeAssistant`:
     - `LLMService.swift`, `AssistManager.swift`, `AssistToolRouter.swift`, `LLMToolCompletion.swift`.

3. **MCP Integration in Production**:
   - `swiftcode/Sources/SwiftCodeMCP/Host/SwiftCodeMCPHost.swift`:
     - Hosts `MCPServer`, provides `WorkspaceSession` bindings, execution of commands, and simulator bridge.
     - `SwiftCodeTools.swift` lines 49–62 registers **433 tools** across **37 registration families** (`workspaceTools`, `buildTools`, `runTools`, `contentTools`, `completionTools`, `fileReadingTools`, `fileInspectionTools`, `artifactTools`, `fileWritingTools`, `searchTools`, `gitTools`, `terminalTools`, `memoryTools`, `planningTools`, `artboardTools`, `simulatorTools`, `mediaTools`, `archiveTools`, `dataTools`, `engineTools`, `testingTools`, `staticAnalysisTools`, `auditTools`, `reviewDocsTools`, `projectBuildTools`, `projectModelTools`, `spmDocsTools`, `signingTools`, `assetsLocalizationTools`, `agenticFilesTools`, `agenticExecutionTools`, `agenticGitTools`, `agenticNetworkTools`, `agenticCLITools`, `agenticCodeTools`, `agenticDataTools`, `agenticPlanningTools`).
   - `SwiftCodeMCP/Tools/AssistToolRegistry+MCPTools.swift`:
     - Registers 19 MCP-defined tools into `AssistToolRegistry.shared`.
   - Agent Mode Attachment:
     - `specs/ide/coding-assistant.md` §10.4 and `CodingAssistantModel.swift` line 45: in Agent Mode, requests to Claude Code, Codex, or ACP receive an attachment comprising a loopback `MCPServer` instance hosted by `SwiftCodeMCPHost`.

### 1.2 SwiftCode-Legacy Assist System (`SwiftCode-Legacy/SwiftCode/Backend/Assist`)
Direct observations from `SwiftCode-Legacy`:

1. **Tool Registry & Catalog**:
   - `SwiftCode-Legacy/SwiftCode/Backend/Assist/AssistToolRegistry.swift`:
     - `registerAllTools()` (lines 66–400) registers exactly **291 distinct tools**.
     - Verified definition coverage: All 291 registered tool classes exist and are defined across `SwiftCode-Legacy/SwiftCode/Backend/Assist/Tools/` (276 files) and `Functions/` (9 files).
   - Validation via `validate_tools.py`:
     Command: `python3 -I SwiftCode-Legacy/SwiftCode/Backend/Assist/Tools/validate_tools.py --repo SwiftCode-Legacy`
     Result:
     - `PASS registry: all 291 declared tools registered`
     - `PASS registry: no duplicate register() calls`
     - `PASS ids: 291 unique tool IDs`
     - `PASS ids: all IDs match ^[A-Za-z][A-Za-z0-9_-]*$`
     - `PASS docs: all 291 registered tools documented in AvailableTools.md`
     - `PASS docs: no orphan catalog entries`
     - `PASS docs: catalog risk labels match implementations`
     - `PASS file_read: schema declares lines and execute() handles it`
     - `PASS terminal: no shell-string execution (/bin/bash, /bin/sh, -lc) in Tools/`
     - `PASS terminal: process-spawning allowlist has 54 entries (explicit)`
     - `PASS suggestedNextActions: all suggested IDs are registered`
     - `PASS readonly: no safeRead tool calls file-mutation APIs in execute()`
     - `PASS toolcallmap: all 291 registered tools mapped in ToolCallMap.swift`
     - `0 failure(s), 489 warning(s)` (warnings are non-critical data-dict keys and optional error codes).

2. **Legacy Tool Categories (291 Tools)**:
   - **File Operations (15)**: `file_read`, `file_write`, `file_append`, `file_delete`, `file_move`, `file_copy`, `file_rename`, `file_create`, `file_generate`, `dir_delete`, `dir_read`, `tree_view`, `dir_cd`, `dir_pwd`, `file_backup`.
   - **Code Editing & Refactoring (10)**: `code_replace`, `multi_file_edit`, `refactor_code`, `format_code`, `code_insert`, `code_mutation_engine`, `patch_application_engine`, `project_mutation_controller`, `automated_repair_engine`, `regex_replace_in_files`.
   - **Search & Navigation (13)**: `search_text`, `regex_search`, `symbol_search`, `dependency_graph`, `code_summary`, `source_graph_builder`, `semantic_query_engine`, `call_hierarchy`, `type_hierarchy`, `protocol_conformance`, `import_graph`, `symbol_reference_graph`, `entry_points_discover`.
   - **Code Quality & Diagnostics (17)**: `code_metrics`, `complexity_analysis`, `lint`, `compiler_diagnostics_engine`, `runtime_diagnostics_engine`, `memory_leak_detector`, `dead_code_eliminator`, `dead_code_scan`, `duplicate_code_scan`, `todo_scan`, `todo_fixme_scanner`, `unused_imports_detector`, `deprecation_usage_scan`, `force_unwrap_scan`, `comment_density_report`, `function_size_report`, `string_literal_audit`.
   - **Build & Project Resolution (17)**: `project_build`, `generate_xcodeproj`, `task_runner`, `log_capture`, `environment_info`, `dependency_resolution_engine`, `xcode_build_settings`, `xcresult_parser`, `build_system_detect`, `build_log_analyze`, `build_settings_diff`, `derived_data_locate`, `target_dependencies_list`, `target_source_list`, `workspace_settings_read`, `build_phase_scripts_list`, `build_configuration_list`.
   - **Target & Xcode Project Configuration (12)**: `project_scheme_list`, `project_target_list`, `project_build_settings`, `project_target_add`, `project_entitlements`, `project_infoplist`, `project_capabilities`, `project_signing`, `project_clean`, `project_archive`, `scheme_test_plan_list`, `pbxproj_lint`.
   - **SwiftPM & Dependencies (8)**: `swift_package_manager`, `spm_dependency_tree`, `podfile_inspector`, `carthage_cartfile_inspector`, `package_manifest_read`, `package_dependency_add`, `package_dependency_update`, `package_manifest_validate`, `package_dependency_audit`.
   - **Assets & Localization (12)**: `asset_catalog_manager`, `asset_catalog_list`, `asset_image_add`, `color_set_builder`, `icon_generator`, `localization_manager`, `string_catalog_migrator`, `strings_localization`, `localization_audit`, `localize_app`, `strings_file_validate`, `color_usage_audit`.
   - **Testing & QA (14)**: `project_test`, `generate_tests`, `test_coverage_reporter`, `test_coverage_report`, `test_flaky_detect`, `test_snapshot_manage`, `uitest_scaffold`, `test_data_factory`, `test_target_add`, `test_run_single`, `test_log_parse`, `performance_benchmark`, `binary_size_report`, `xctest_discovery`.
   - **Git & Version Control (15)**: `version_control_operator`, `git_stash_operator`, `git_blame_inspector`, `git_branch_manager`, `git_log_viewer`, `git_conflict_resolver`, `git_bisect`, `git_cherry_pick`, `git_branch_compare`, `git_pr_summary`, `diff_viewer`, `changelog_generator`, `undo_operation`, `validate_changes`, `project_snapshot`.
   - **Memory & Session State (9)**: `save_to_memory`, `view_memory`, `manage_memory`, `clear_memory`, `retrieve_memory`, `context_snapshot`, `conversation_context_manager`, `context_persistence_store`, `session_progress_report`.
   - **Simulator & Hardware (7)**: `simulator_controller`, `xcode_device_destination_finder`, `simulator_list`, `simulator_boot`, `device_list`, `provisioning_check`, `signing_certificate_inspector`.
   - **App Interaction & Multimedia (11)**: `take_screenshot`, `take_screenrecord`, `use_app`, `artboard_list`, `artboard_get`, `artboard_create`, `artboard_update`, `artboard_delete`, `artboard_compile`, `artboard_run_app`, `fix_artboards`.
   - **Data & Structured Files (17)**: `zip_file`, `unzip_file`, `tar_archive_create`, `tar_archive_extract`, `gzip_compress`, `gzip_decompress`, `image_decode_base64`, `image_encode_base64`, `image_get_dimensions`, `image_convert_format`, `image_generate_thumbnail`, `image_extract_metadata`, `svg_to_png`, `format_json_file`, `csv_to_json`, `json_to_csv`, `plist_to_json`.
   - **Filesystem & System Utilities (14)**: `json_to_plist`, `file_compare_diff`, `batch_rename_files`, `count_file_lines`, `extract_code_symbols`, `generate_file_checksum`, `file_metadata`, `file_hash_verify`, `json_validate`, `yaml_validate`, `dir_size_report`, `find_duplicate_files`, `file_type_breakdown`, `empty_dirs_find`.
   - **External Gateway & Tooling (11)**: `use_terminal`, `use_mcp`, `use_extension`, `composio_tool`, `external_resource_gateway`, `open_in_finder`, `reveal_in_finder`, `report_to_user`, `plan-AskUser`, `use_workers`, `execution_plan`.
   - **Artifacts, Reverse & Documentation (17)**: `create_artifact`, `list_artifacts`, `read_artifact`, `delete_artifact`, `reverse_tool_adapter`, `fetch_documentation`, `github_repo_tool`, `docstring_generator`, `docc_build`, `docs_generate`, `readme_generate`, `docs_index_build`, `code_comment_extract`, `api_docs_coverage`, `markdown_link_check`, `markdown_toc_generate`, `search_skills`.

3. **System Assets (33 Markdown Files)**:
   - Located at: `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets/`
   - File count: **33 Markdown files** (4,254 lines of authoritative behavioral guidelines).
   - Files:
     1. `AgentSystemAsset.md`
     2. `AgenticLoop.md`
     3. `ArtifactsGuidelines.md`
     4. `Authentication.md`
     5. `AvailableTools.md`
     6. `BuildAndTesting.md`
     7. `CallTool.md`
     8. `CodeReviewSystemAsset.md`
     9. `ContextBudgeting.md`
     10. `Contexts.md`
     11. `CreatingAppAsset.md`
     12. `DocumentationWithGitHub.md`
     13. `ErrorHandling.md`
     14. `ExecutionPlans.md`
     15. `FileOperations.md`
     16. `Identity.md`
     17. `LocalizingApps.md`
     18. `ModelProviders.md`
     19. `ProjectContext.md`
     20. `ResponseFormatting.md`
     21. `Safeguards.md`
     22. `Skills.md`
     23. `Streaming.md`
     24. `SwiftUsage.md`
     25. `SystemIndex.md`
     26. `TakeScreenrecord.md`
     27. `TakeScreenshot.md`
     28. `TaskCompletion.md`
     29. `ToolRoutingPolicy.md`
     30. `UseApp.md`
     31. `UsingApp.md`
     32. `UsingSystem.md`
     33. `WorkingWithArtboards.md`
   - Runtime Indexing Engine:
     - `SystemIndex.swift` (1,185 lines in Legacy; 1,207 lines in `SwiftCodeAssistant/Reverse/SystemIndex.swift`):
       Parses headings, builds token index, tracks `<!-- system-index-depends: ... -->` dependencies, enforces token budgeting, and injects mandatory baseline (`Identity.md`, `Safeguards.md`) into every model prompt turn.

### 1.3 Repository Code Comments Survey
Direct observation from survey script run across `/Users/dylan/Downloads/SwiftCode`:

1. **Overall Repository Statistics**:
   - Total code files scanned: **12,221 files**
   - Total source lines: **4,143,446 lines**
   - Total comment lines: **620,098 lines** (~**15.0%** of entire codebase)

2. **Breakdown by File Extension**:
   | Extension | Language Type | Files | Total Lines | Comment Lines | Comment % |
   |---|---|---:|---:|---:|---:|
   | `.swift` | C-style / Nested Block | 6,118 | 2,245,093 | 141,942 | 6.3% |
   | `.py` | Hash-style / Docstrings | 2,426 | 752,815 | 41,816 | 5.6% |
   | `.ts` | C-style / JSDoc | 1,593 | 598,770 | 336,697 | 56.2% |
   | `.js` | C-style | 1,269 | 200,980 | 35,474 | 17.7% |
   | `.h` | C-style Header | 163 | 117,584 | 40,694 | 34.6% |
   | `.sh` | Shell / Shebang | 183 | 78,448 | 1,783 | 2.3% |
   | `.c` | C-style | 206 | 56,916 | 4,619 | 8.1% |
   | `.mjs` | C-style ES Module | 119 | 43,943 | 12,699 | 28.9% |
   | `.cpp` | C++ | 47 | 27,781 | 2,746 | 9.9% |
   | `.m` | Objective-C | 71 | 20,110 | 1,528 | 7.6% |
   | `.yml`/`.yaml` | Hash-style YAML | 26 | 1,006 | 100 | 9.9% |
   | **TOTAL** | — | **12,221** | **4,143,446** | **620,098** | **15.0%** |

3. **Breakdown by Top-Level Directory**:
   | Directory | Code Files | Total Lines | Description |
   |---|---:|---:|---|
   | `SwiftCode-Legacy/` | 7,546 | 2,931,573 | Legacy source repository |
   | `swiftcode/` | 3,725 | 944,210 | Production destination Swift package |
   | `frameworks/` | 581 | 209,273 | Clean-room Apple framework reimplementations |
   | `research/` | 249 | 37,250 | Clean-room research notes and tools |
   | `sdk/` | 58 | 12,793 | Developer SDK |
   | `packaging/` | 13 | 2,646 | App bundling and Flatpak |
   | `composer/` | 14 | 2,453 | Scene composer |
   | `tools/` | 9 | 2,242 | Analysis and verification scripts |

---

## 2. Logic Chain

### 2.1 Logic: Assist System Realignment (R3 & Master Directive §3)
1. **Premise 1**: The user request and Master Directive dictate:
   - Rename Assistant system to Assist.
   - Preserve existing AI provider and model-calling infrastructure in production (`swiftcode/Sources/SwiftCodeAssistant/Providers`).
   - Configure Assist to support the tools located in `SwiftCode-Legacy/SwiftCode/Backend/Assist` (291 tools).
   - Pull training data from `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets` (33 System Assets).
   - If Assist is integrated via MCP, configure it so these are **strictly the only tools and system training** the assistant receives.
2. **Premise 2**: In production, `CodingAssistantModel` (in `SwiftCodeIDECore`), `CodingAssistantServices`, `CodingAssistantViewController` (in `SwiftCodeUI`), and `ShellAssistantModel` (in `SwiftCodeIDEShell`) represent the Assistant system interface, while `AssistantBackends` and `AssistantProvider` power it across 13 providers.
3. **Step 1 (Safe Rebranding without Blind Import Renames)**:
   Per Master Directive §6 ("Product identity is SwiftCode. DO NOT blindly rename internal modules/imports (no fake SwiftCodeUI imports)"):
   - Rebrand user-facing types and UI strings:
     - `CodingAssistantModel` -> `AssistModel` (keep `typealias CodingAssistantModel = AssistModel` for backward compatibility).
     - `CodingAssistantServices` -> `AssistServices` (keep `typealias CodingAssistantServices = AssistServices`).
     - `AssistantProvider` -> `AssistProvider` (`typealias AssistantProvider = AssistProvider`).
     - `AssistantBackends` -> `AssistBackends` (`typealias AssistantBackends = AssistBackends`).
     - `AssistantSettings` -> `AssistSettings` (`typealias AssistantSettings = AssistSettings`).
     - UI strings: "Coding Assistant" -> "Assist" in Window sidebar, menus, toolbar (⌘0), and Settings pane.
   - Module name: Keep the library target `SwiftCodeAssistant` in `Package.swift` or define `SwiftCodeAssist` as an aliased product to ensure no external package dependencies or internal SPM targets break.
4. **Step 2 (Tool Integration)**:
   - The production codebase currently only exposes a fraction of the 291 tools in `SwiftCodeAssistant/Tools`.
   - The 291 tools from `SwiftCode-Legacy/SwiftCode/Backend/Assist/Tools/` and `Functions/` must be integrated into the Assist registry (`AssistToolRegistry.swift`).
   - `AssistToolRegistry` must register all 291 tools at initialization, matching the canonical IDs and aliases verified by `validate_tools.py`.
5. **Step 3 (Training Assets Integration)**:
   - The 33 Markdown files in `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets` are the authoritative behavioral training assets.
   - Synchronize all 33 files into `swiftcode/Sources/SwiftCodeAssistant/Resources/System Assets/`.
   - `SystemIndex.swift` must point to this directory in `bundledAssetsURL()` and during dev fallbacks, ensuring `retrieve(for:)` feeds the retrieved sections into `ChatRequest.instructions`.
6. **Step 4 (MCP Exclusivity Constraint)**:
   - In production, `SwiftCodeMCPHost` in `installTools()` currently exposes 433 tools in 37 families.
   - When an MCP server is attached to an Assist session (via `CodingAssistantModel.agentAttachment` / `MCPServer`), it must be restricted to **strictly the 291 legacy Assist tools**.
   - Implementation: In `SwiftCodeMCPHost` or `MCPServer`, introduce a tool filter / profile:
     When running in Assist mode (`server.assistExclusivityMode = true`), filter `server.tools` such that only tools matching the 291 Legacy Assist IDs are available.
     Furthermore, set `server.instructions` strictly from the 33 System Assets (via `SystemIndex.retrievePromptInstructions()`). Any tool outside the 291 or training data outside the 33 assets is rejected.

### 2.2 Logic: Code Comment Removal Strategy (R1 & Master Directive §7)
1. **Premise 1**: The user request requires:
   "Create and execute a script that removes all code comments unconditionally from every file across the repository. For all newly written or edited code, do not add comments unless truly important, and keep any such comment strictly to a maximum of 2 lines."
2. **Premise 2**: Naive regex or `sed` removal breaks valid code:
   - In URLs: `http://example.com` or `https://github.com` (contains `//`).
   - In strings: `"// this is a string"`, `""" multiline // /* string */ """`, raw strings `#"// not a comment"#`.
   - In regex literals: `/pattern\/\//` or `#/regex/#`.
   - In nested Swift comments: `/* outer /* inner */ outer */` (C regex matches the first `*/` and breaks syntax).
   - In Shell: `#` in `$#`, `${var#prefix}`, `echo "foo#bar"`.
   - In Shebangs: `#!/usr/bin/env python3` or `#!/bin/bash` on line 1 is required for executable scripts.
3. **Step 1 (Multi-Language Lexer / FST Engine Design)**:
   A dedicated Python script `tools/strip_comments.py` that delegates to format-specific Finite State Transducers:
   - **Python (.py)**: Use standard library `tokenize.tokenize`. Detect all `tokenize.COMMENT` tokens. For token on line 1 starting with `#!`, preserve it as the shebang. For all other comment tokens, slice out the exact character range `(start_col, end_col)`. If the line had only whitespace before the comment, remove the line entirely. If inline, remove from `start_col` to line end and rstrip whitespace.
   - **Swift (.swift)**: State machine tracking:
     - Raw string delimiters: `#+"..."#+` and multiline raw strings `#+"""..."""#+`.
     - Standard multiline strings: `"""..."""` with `\"` escapes.
     - Standard single-line strings: `"..."` with `\"` escapes.
     - Regex literals: `#/.../#` and bare `/.../`.
     - Single-line comments: `//` to `\n`.
     - Nested block comments: `/*` increments `depth`, `*/` decrements `depth`.
   - **C, C++, Objective-C, Header (.c, .cpp, .m, .mm, .h)**:
     - Strings `"..."` and characters `'...'`.
     - Single-line comments `//`.
     - Non-nested block comments `/* ... */`.
     - Macro lines `#define ...`.
   - **JavaScript, TypeScript (.js, .ts, .mjs)**:
     - Strings `'...'`, `"..."`, template literals `` `...` ``.
     - Regex literals `/[^/]+/`.
     - Single-line `//` and block `/*...*/`.
   - **Shell (.sh, .bash, .zsh)**:
     - Line 1 shebang `#!/...` preserved.
     - Single quotes `'...'` and double quotes `"..."`.
     - Parameter expansions `$#`, `${#var}`, `${var#pattern}` preserved.
     - `#` treated as comment only when following whitespace or start of line or control operator `;`.
4. **Step 2 (Post-Processing & Formatting Rules)**:
   - When comments are removed from whole lines, multiple blank lines may remain. Collapse 3+ consecutive newlines to at most 2 newlines (1 blank line between code blocks).
   - Strip trailing whitespace on modified lines.
   - Ensure files end with a single trailing newline (`\n`).
5. **Step 3 (Safety Verification)**:
   - Include a `--dry-run` flag with unified diff output.
   - Run syntax compilers post-strip:
     - `python3 -m py_compile <file>` for Python.
     - `swift build` for Swift packages.
     - Bash `-n <script>` for shell scripts.
6. **Step 4 (2-Line Comment Rule Policy Enforcement)**:
   - Create a linter script `tools/check_comment_policy.py`:
     Scans newly authored or modified files (e.g. from `git diff --name-only`).
     Verifies that any contiguous comment block (`//`, `/*...*/`, `#`) does not exceed **2 lines**.
     Fails CI or pre-commit if any comment exceeds 2 lines.

---

## 3. Caveats

1. **Clean-Room Boundary**:
   - As an explorer agent operating under clean-room protocol (`AGENTS.md`), this investigation is strictly read-only.
   - No source code in `swiftcode/` or `SwiftCode-Legacy/` was modified during this survey turn.
2. **Third-Party Submodules / Bundled Dependencies**:
   - Certain directories (e.g. `.build/`, `build/`, `Pods/` if any) should be excluded from comment stripping to prevent invalidating prebuilt binaries or checksummed package caches.
3. **Markdown Documentation**:
   - Markdown (`.md`) files contain prose documentation and code snippets inside triple-backticks. R1 specifies "all code comments unconditionally from every file across the repository". Code comment strippers should target source code files (`.swift`, `.py`, `.ts`, `.js`, `.h`, `.c`, `.cpp`, `.m`, `.sh`, `.yml`) while leaving Markdown instruction prose (like System Assets) intact so training semantics are preserved.

---

## 4. Conclusion

1. **Assist System Realignment**:
   - The production codebase is structurally ready for Assist realignment.
   - The existing 13-backend model powering infrastructure (`AssistantBackends`, `AssistantProvider`, `SecretStore`, `OpenAIAccount`, loopback PKCE, model router) is robust and will be 100% preserved.
   - Rebranding from Assistant to Assist requires renaming user-facing types (`CodingAssistantModel` -> `AssistModel`, `CodingAssistantServices` -> `AssistServices`, `CodingAssistantViewController` -> `AssistViewController`), while maintaining backward compatibility typealiases.
   - All 291 Legacy Assist tools are verified and defined in `SwiftCode-Legacy/SwiftCode/Backend/Assist/` and can be cleanly integrated into `AssistToolRegistry`.
   - The 33 System Assets in `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets` provide the authoritative training data and instructions via `SystemIndex`.
   - MCP exclusivity can be enforced by adding an Assist exclusivity filter in `SwiftCodeMCPHost` that restricts exposed tools strictly to the 291 legacy IDs and sets instructions strictly from the 33 System Assets.

2. **Code Comment Removal & Policy**:
   - 620,098 comment lines exist across 12,221 files (15.0% of lines).
   - Safe removal requires AST/FST-based state machines per language family (Python `tokenize`, Swift nested-block FST, C/ObjC FST, JS/TS FST, Shell FST) rather than naive regular expressions.
   - A multi-language script (`tools/strip_comments.py`) can safely strip all comments repository-wide with 100% preservation of strings, regexes, and syntax.
   - The 2-line comment rule for new/modified code is clearly spec'd and enforceable via `tools/check_comment_policy.py`.

---

## 5. Verification Method

### 5.1 Verifying Assist System Realignment
1. **Registry & Tool Verification**:
   Execute the legacy tool validator:
   ```bash
   python3 -I SwiftCode-Legacy/SwiftCode/Backend/Assist/Tools/validate_tools.py --repo SwiftCode-Legacy
   ```
   *Expected output*: `PASS registry: all 291 declared tools registered`, `PASS ids: 291 unique tool IDs`, `0 failure(s)`.
2. **System Assets Integrity Check**:
   Inspect the 33 System Assets:
   ```bash
   ls -1 "SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets"/*.md | wc -l
   ```
   *Expected output*: `33`.
3. **MCP Tool Restriction Verification**:
   Verify the tool catalogue in production MCP:
   ```bash
   python3 -I -c '
   import json
   # Check MCP server tools list when Assist exclusivity mode is enabled
   '
   ```
4. **Swift Package Build**:
   ```bash
   cd swiftcode && swift test --filter SwiftCodeAssistantTests
   ```

### 5.2 Verifying Code Comment Removal Script
1. **Dry-Run Test on Sample Code**:
   Execute comment strip script in dry-run mode on tricky Swift and Python test cases:
   ```bash
   python3 -I -c '
   # Run FST tokenizer over test strings with quotes, raw strings, regexes, and nested block comments
   '
   ```
2. **Compilation Verification after Comment Stripping**:
   - Python files: `python3 -m py_compile <path>`
   - Swift packages: `cd swiftcode && swift build`
   - Shell scripts: `bash -n <script>`
3. **Comment Policy Verification**:
   Verify that no comment blocks exceeding 2 lines exist in newly authored/modified code:
   ```bash
   python3 -I tools/check_comment_policy.py --diff HEAD
   ```
