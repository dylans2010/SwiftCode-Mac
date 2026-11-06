# Wave 19 — System Assets Re-derivation

**Status:** staged, ready for parent integration. Nothing in this spec has been
written to the destination repo, committed, or pushed.

## 1. Problem

Legacy's `SwiftCode/Backend/Assist/Functions/System Assets/` holds 33 Markdown
files (4,254 lines) that are Dylan's own behavioral training layer for Assist:
identity, safeguards, routing policy, the agentic loop, streaming, artboards
guidance, and — most importantly — `AvailableTools.md`, an enumeration of
Legacy's 291-tool Assist registry. That enumeration is stale against the
destination's 433-tool MCP catalogue, so copying the files would enshrine
wrong tool IDs, wrong risk levels, wrong parameter lists, and Legacy-only
concepts (Autopilot bypass, allow-list/Full Access approvals, pbxproj
auto-registration, absolute model secrecy) that the destination does not have.

The REVIEW-REQUIRED scout (`audit/review-required-decisions.md` §3) therefore
ruled all 33 files **rewrite-from-spec**: keep Dylan's behavioral prose, but
re-derive every tool fact from the live catalogue.

## 2. Derivation method

### 2.1 Live catalogue (`derive-catalogue.py` → `catalogue.json`)

`derive-catalogue.py` tokenizes the Swift sources under
`swiftcode/Sources/SwiftCodeMCP/` (handles `"""` multiline strings,
`#"..."#` raw strings, `\(` interpolations, line-continuation `\` + newline,
`//` and `/* */` comments) and extracts every
`tool("id", "Title", "description", input:, output:, annotations:, writes:)`
registration, resolving `annotations` (`.read` default, named local lets,
inline `MCPToolAnnotations(...)`) and `required:` parameters.

Risk derivation (the reverse of `specs/ide/assist-tool-catalogue.md` §1.3,
extended per the `SwiftCodeTools+Terminal.swift` header), in precedence order:

1. `destructive` → `potentiallyDestructive`
2. `openWorld` → `externalSideEffect` (even for reads — a tool whose effects
   leave the workspace must not be presented as a pure read; this is the
   §1.3 Finder-tool exception)
3. `readOnly` → `safeRead`
4. `!idempotent` → `execution`
5. `idempotent` → `safeMutation`

**Result: 433 tools, 433 unique IDs, 0 duplicates** (the script exits 1
otherwise). 37 registration families (the earlier working note said 36; the
37th is `contentTools`, 7 tools — the full list is in `catalogue.json`).
Risks: execution 54, safeRead 229, safeMutation 114, externalSideEffect 23,
potentiallyDestructive 13. `writes: true` on 170 tools. No null families, no
empty descriptions, no missing titles. `installTools` family order is the
order in `SwiftCodeTools.swift` (`workspaceTools + buildTools + … +
agenticPlanningTools`).

The catalogue was re-derived a second time during verification and produced
identical counts (433/433/0 dups, same risk distribution).

### 2.2 Prose files (`adapt-system-assets.py`)

32 of the 33 files are Legacy's own prose, adapted by asserted exact-match
replacements. Every replacement is checked: the old string must occur exactly
the expected number of times, or the script aborts — a stale correction is
never silently skipped. Each file gets a re-derivation header naming the live
catalogue (433 tools, 0 duplicate IDs), the Legacy source path, and this spec.
Each file's `<!-- system-index-depends: … -->` comment is preserved verbatim
(32 of 33 files declare one; `WorkingWithArtboards.md` declares none, exactly
as in Legacy).

Adaptation rules:

- Keep Dylan's behavioral prose verbatim **except** where the live tree
  contradicts it. Every contradiction below was verified by grep against the
  destination at local HEAD `305696b` before the replacement was written.
- Tool IDs verified against the live 433; stale IDs replaced per the mapping
  in §4, or marked absent with a reason.
- Autopilot passages rewritten to the destination reality (no Autopilot mode;
  Plan mode exists as a plan-document label only — `PlanningExecutionMode`
  `.plan` / `.autopilot` in `SwiftCodeTools+PlanningSupport.swift:28` — and
  every run goes through the single approval gate).
- pbxproj auto-registration claims dropped/corrected everywhere (registration
  is explicit via `project_mutation_controller`, `action: "add"`).
- Where the live tree has no value, the field is left explicitly absent with a
  reason — nothing is invented.

### 2.3 AvailableTools.md (`generate-available-tools.py`)

Fully regenerated from `catalogue.json`: live id / title / description / risk /
required parameters, grouped by the 37 families, alphabetical within a family.
Legacy's framework sections (Authority & Schema Contract, Tool-Selection
Hierarchy, Terminal Governance, file_read Line Ranges, Worked Examples) are
carried over with the corrections in §3. Verified Operational Notes and a
rewritten Known Limitations section are appended. The generator cross-checks
every backticked ID in the Legacy file against the live 433 using the mapping
in §4 plus a non-tool exclusion set (parameters, values, paths, types); it
fails on any unmapped missing ID. Result: 451 backticked IDs in Legacy, 21
not live, all 21 mapped (see §4).

### 2.4 Verification (`verify-staged.py`)

Re-run after every regeneration. Checks: all 33 files exist, non-empty, carry
the re-derivation header; every `system-index-depends` comment preserved
verbatim; every backticked snake_case ID in the staged files is a live tool, a
known-missing ID with a recorded mapping, a `use_app`/`use_system` operation
value, or a documented parameter/value/example name; no stale references
(`AssistToolRegistry`, `AssistMainView`, `AssistEventNormalizer`,
`MiniLogFeed`, `AssistActivityView`, `AgentControlsView`,
`AssistUserTakeover`, `BuildDestinationResolver`, `AssistArtifactsView`,
`AssistErrorRecoveryEngine`, `LocalOpenAIAgentConfig`,
`AntigravityLimitsModelsUI`, `agent_runner.py`, `model_adapter_server.py`,
`bridge/main.py`, `resetForNewTask`, `validate_tools.py`,
`GoogleCloudSDKTransport`, `AssistActivityGroup`, `ToolActivityItem`,
`WorkerActivityItem`); and three names (`AssistErrorRecoveryEngine`,
`NativePreviewHost`, `PROCESS_ALLOWLIST`) appear only inside explicit
"there is no X" passages. **Final run: ALL CHECKS PASSED.**

## 3. Corrections applied (live-tree evidence)

- **Approval model.** Legacy's allow-list / Full Access / Autopilot approval
  model is NOT ported: every run goes through SwiftCode's single approval
  gate (`SwiftCodeTools+Terminal.swift` header). `use_terminal` never runs a
  shell (command string tokenized into argv; shell metacharacters rejected).
  `use_system`'s single mutation (`user_defaults_write`) needs both Legacy's
  `confirm: true` AND the approval gate. `use_workers` plans and persists
  but does not execute (`useWorkersReal` in
  `SwiftCodeTools+WorkersRuntime.swift:174` — "they do not run until a
  subagent runtime is connected").
- **Stale registered descriptions (source fixes needed, not fixed here).**
  `use_terminal`'s registered description still says allow-list / Full Access
  commands "run without an approval prompt" — contradicts the header doc.
  `plan-AskUser`'s registered description still says "blocked at the runtime
  registry layer in Autopilot mode". `generate_xcodeproj`'s live description
  says "Installs XcodeGen automatically if missing" but the handler fails
  honestly (gap-closure remainder). The derived docs describe the real
  behavior and flag all three in the remainder list.
- **Model secrecy.** Legacy's absolute rule ("the underlying model must NEVER
  be revealed", scripted answer "I am Assist, the native AI coding partner
  built directly into SwiftCode") is NOT the destination's policy — no
  "Assist by SwiftCode" string exists in the destination, and Assist Settings
  shows the selected provider's card. Rewritten everywhere to: identity is
  "Assist"; the user selects the provider in Settings; never label a request
  as coming from a provider that did not handle it.
- **No pbxproj auto-registration.** `SwiftCodeTools+FileWriting.swift:68`
  comment confirms it. All "Automatically registers new files in
  project.pbxproj" claims dropped/corrected.
- **`file_read` line ranges.** Legacy-style `lines: {start, end}` (1-based
  inclusive) IS supported and wins over `startLine`/`lineCount`
  (`SwiftCodeTools+Workspace.swift:42-51`); "In the IDE, an open editor's
  unsaved text is read."
- **`code_generate` templates.** Live: `swift_struct`, `swift_class`,
  `swiftui_view`, `test` (`FileWriting.swift:249`).
- **`version_control_operator` rollback.** Live actions: status, commit,
  branch, rollback, diff, push, pull, fetch, clone; ref default HEAD~1. No
  `log` action — use `git_log_viewer`.
- **`take_screenshot`.** Live risk `externalSideEffect` (not `safeRead`).
  capture_mode `fullscreen`/`region`/`window` (default `fullscreen`, not
  `"screen"`). `region` and `window_id` params added. `include_cursor`
  default is TRUE (Legacy said false). Output fields: `path`/`width`/
  `height`/`display_id`/`capture_mode`/`artifact_id`/`base64`/`format`/
  `size_bytes`. No interactive region-selection overlay exists in SwiftCode
  (gap-closure remainder) — Example B rewritten to explicit coordinates.
- **`take_screenrecord`.** Live risk `externalSideEffect`. Duration default
  10s (not 5s). capture_mode `window`/`application_display` (not
  `window`/`display`). `include_audio` IS supported (Legacy said NOT
  supported). `output_format` mov/mp4. H.264 codec claim dropped (no codec
  string in the MCP sources).
- **`use_app`.** Live risk `externalSideEffect` (not `safeMutation`); family
  `terminalTools`; approval-gated (`approveChangeWithoutFile` in
  `AppInteraction.swift:1025`). Live operations (30):
  launch, activate, list_applications, list_windows, select_window,
  close_application, inspect_application, inspect_window, inspect_ui,
  get_accessibility_tree, get_focused_element, take_screenshot, click,
  double_click, right_click, move_pointer, drag, scroll, type_text,
  set_value, press_key, press_shortcut, select_all, copy, paste,
  activate_element, set_element_value, select_menu, wait_for_element,
  wait_for_window, verify. NOT supported: `select_menu_item`,
  `verify_element_state` (corrected to `select_menu` / `verify`).
  `inspect_ui` traverses up to **10** levels deep, max 100 elements
  (Legacy's UseApp §4 said 5 — wrong; UsingApp §5's 10 is right).
  `AssistToolErrorCode` does not exist — error sections rewritten to
  structured errors without code names.
- **`use_system`.** Already destination-accurate — carried verbatim (header
  only). Live operations (11): system_info, dev_environment, process_list,
  network_interfaces, listening_sockets, connectivity, disk_info, system_log,
  service_status, config_read, user_defaults_write. `process_monitor_tool`
  is live.
- **`create_new_app`.** Writes under the workspace root
  (`<workspace>/<appName>`, `ProjectModel.swift:907`) — NOT
  `~/Documents/<appName>` — and does NOT switch the active project session.
  bundleIdentifier default `com.swiftcode.<safeName.lowercased()>`
  (`ProjectModel.swift:903`). Platforms add `iPadOS`.
- **Memory tools.** `save_to_memory` takes `key` + `value` (+ optional
  `category`), NOT Legacy's `content`/`category`/`importance`. `view_memory`
  takes `query`/`category`, NOT `section`. `manage_memory` actions are
  `read`/`view`, `add`/`edit`/`save`, `delete`/`remove`, `clear` (Legacy's
  `append` has no handler case). `context_persistence_store` path is
  `<workspace>/.assist_context_store.json` (`MemorySupport.swift:40`).
- **`code_mutation_engine`.** Requires `path` + `replacement`; Legacy's
  "symbol OR target required" is wrong (symbol/target are optional).
- **CallTool quirks.** `search_skills` limit default 8, max 20
  (`Search.swift:175,738`). `plan-AskUser` renders `PlanUserAskView` but
  has NO 300s timeout in the live description — the 300s claim dropped
  everywhere. `system_notification_tool` adds a `critical` param.
- **ErrorHandling.** `AssistErrorRecoveryEngine` does NOT exist — §3 rewritten
  as a discipline, not a named engine. `AlternativeKeyManager`,
  `AssistModelRouter`, `AntigravityQuotaService` all exist.
- **ContextBudgeting.** No `LIFECYCLE_HOOK_ON_COMPACTION` /
  `OnCompactionArgs` / `CompactionConfig` — compaction rewritten as
  per-provider summarization discipline. `file_read` has no `lineRange` /
  `maxBytes` params — use `lines` (or `startLine` + `lineCount`).
- **ProjectContext / FileOperations / BuildAndTesting / Contexts /
  CreatingAppAsset / Identity / Safeguards.** `activeProject.directoryURL`
  → workspace root. New files registered via `project_mutation_controller`
  (explicit, not automatic).
- **Artifacts.** `AssistArtifactStore` exists; `AssistArtifactsView` does
  NOT. `create_artifact` live risk is **execution** (not safeMutation).
  `delete_artifact` agent_notes protection confirmed. `read_artifact` 60k
  truncation confirmed in the live description.
- **Authentication.** `buildSDKConfiguration`, `verifyRuntimeSession`,
  `GoogleCloudSDKConfiguration`, `KeychainService` all exist. `agent_runner.py`
  and `model_adapter_server.py` are venv Python (not ported) — references
  dropped. Google OAuth has no embedded default client (needs Dylan's client
  secret via Settings or `GOOGLE_CLIENT_SECRET`). Scopes `cloud-platform` +
  `generative-language.retriever` confirmed
  (`GoogleAccountAuthService.swift:545-556`).
- **CodeReview.** `code_review` and `autonomous_review_engine` both live;
  the `task_ready`/`task_failed` JSON verdict contract IS the destination's
  (`ReviewDocs.swift:73-78, 856-857`).
- **DocumentationWithGitHub.** `github_repo` operations confirmed exactly
  (repository_info, list_files, get_directory, get_file, get_tree,
  search_code, fetch_repository — `Git.swift:974-1017`).
  `fetch_documentation` params confirmed (query, url, framework, platform,
  language, includeExamples, maxResults). DocC-JSON-first / HTML-fallback
  pipeline + 24h cache confirmed (`Engines.swift:91-92`).
- **LocalizingApps.** Fully destination-accurate — carried verbatim (header
  only). `localize_app` actions are `localize`/`status`/
  `set_development_region` (`AssetsLocalization.swift:808-809`) — this
  resolves the open question from the 390-reference analysis:
  `set_development_region` maps to the `localize_app` action, not a
  standalone tool.
- **ModelProviders.** `ProviderKind` has 13 cases (`Core.swift:8-27`):
  ollama, llamaCpp, openAI, claudeCode, codex, antigravity, acpAgent,
  openRouter, openCode, hermes, foundationModels, scCloud, metaAssist.
  `LocalOpenAIAgentConfig` and `AntigravityLimitsModelsUI` do NOT exist
  (dropped). `hiddenProviderNames` is session state in
  `AssistModelDiscoveryService`, NOT persisted in UserDefaults (Legacy's
  `com.swiftcode.assist.hidden_provider_names` key is wrong).
  `AssistAvailableModel`, `ThinkingLevel`, `AssistModelDiscoveryService`,
  `sdkDefaultModelIDs`, `AssistSettingsView` all exist.
- **ResponseFormatting / Streaming / Contexts.** `AssistMainView`,
  `AssistEventNormalizer`, `AssistActivityGroup`, `ToolActivityItem`,
  `AssistActivityView`, `MiniLogFeed`, `AgentControlsView`,
  `AssistUserTakeover`, `WorkerActivityItem`, `GoogleCloudSDKTransport` do
  NOT exist — rewritten generically (`ConversationView`, which has
  `message.activity`, line 511; conversation-view activity items; no type
  names). "Operating in Autopilot mode" announcement example dropped.
- **Safeguards.** §5 heading rewritten (no bypass subsection; single approval
  gate; `AssistPermissionsManager` name removed). §6 "Autopilot
  Un-sandboxed Terminal Execution" bullet deleted. Approval-gate paragraph
  rewritten (no allow-list/Full Access; `PROCESS_ALLOWLIST` /
  `Tools/validate_tools.py` removed). `bridge/main.py` dropped from
  host-path examples. The prohibited raw-names list verified — every ID in
  it is live — with only the `AssistToolRegistry` tail changed to the MCP
  registry.
- **WorkingWithArtboards.** `VisualUIDocument`, `VisualUIScene`,
  `VisualUIArtboard`, `DocumentCoordinator`, `FullAppRunManager`,
  `PreviewManager`, `XcodeBuildAPI` all exist; `NativePreviewHost` and
  `BuildDestinationResolver` do NOT. Mode 0 live preview is NOT available
  (no live preview session — gap-closure remainder); Mode 1 (Run Full App)
  kept. Artboard tool risks match Legacy exactly (list/get safeRead; rest
  safeMutation). "Fix with Assist" button reference softened (no Artboards
  window yet).
- **AgentSystemAsset.** The Document Responsibilities table listed only 26 of
  33 files — the 7 missing rows (`ToolRoutingPolicy.md`, `UseApp.md`,
  `TakeScreenshot.md`, `TakeScreenrecord.md`, `WorkingWithArtboards.md`,
  `DocumentationWithGitHub.md`, plus itself) were added. The "Genuine
  dependencies" list (7 entries) was incomplete; the true dependency graph
  was taken from every file's `system-index-depends` comment.
- **AvailableTools risk corrections** (live tree beats Legacy): `create_artifact`
  execution (was safeMutation); `mem_context_snapshot` execution (was
  safeMutation); `file_backup` execution; `project_build` safeMutation (was
  execution); `project_snapshot` safeMutation (was safeRead);
  `safe_undo` is the per-file `SafeUndoJournal`, NOT snapshots;
  `intel_plan_task` plans are in-memory (`PlanningPlanStore`), not persisted;
  `code_review` has no `review_skipped` status (zero hits in the
  destination) — it fails honestly without a provider;
  `intel_explain_code` is static-analysis only
  (`PlanningSupport.staticExplanation`, `Planning.swift:365`), NOT LLM with
  hardcoded OpenAI; `project_snapshot` store is Application Support
  `SwiftCodeSnapshots/<uuid>/` (`ProjectModel.swift:461-465`, post-rebrand
  name); `task_runner`'s internal `project_test` task exists
  (`Terminal.swift:520`); `simulator_boot` description references
  `simulator_screenshot` (a live tool not in Legacy's list).
- **Cloud Toolkit section.** Antigravity SDK built-ins (`view_file`,
  `create_file`, `edit_file`, `run_command`, `list_directory`,
  `search_directory`, `search_web`, `read_url_content`, `start_subagent`)
  have NO destination equivalent — replaced with a no-equivalent note
  mapping to local tools (`file_read`, `file_create`, `file_edit`,
  `use_terminal`, `dir_read`, `search_text`, `fetch_url`, `use_workers`
  planning only).

## 4. Stale-ID mapping (Legacy → destination)

Applied while rewriting; `None` = no destination equivalent, marked absent.

| Legacy ID | Destination |
|---|---|
| `run_command` | `use_terminal` |
| `code_edit` | `file_edit` |
| `create_file` | `file_create` |
| `edit_file` | `file_edit` |
| `view_file` | `file_read` |
| `list_directory` | `dir_read` |
| `list_files` | `file_list` / `dir_read` (standalone); `github_repo` operation `list_files` |
| `file_search` | `search_files` / `search_text` |
| `search_code` | `search_text` (standalone); `github_repo` operation `search_code` |
| `search_web` | `web_search` |
| `search_directory` | `search_files` |
| `semantic_search` | `semantic_query_engine` |
| `start_subagent` | `use_workers` (planning only — no execution runtime) |
| `list_tools` | None (MCP tools/list, not a tool) |
| `fetch_repository` / `repository_info` / `repository_analysis` / `get_directory` / `get_file` / `get_tree` | `github_repo` operations |
| `inspect_artifact` | `read_artifact` |
| `read_url_content` | `fetch_url` |
| `demangle_swift` | None |
| `inspect_with_objdump` | None |
| `set_development_region` | `localize_app` action `set_development_region` |
| `select_menu_item` | `select_menu` (`use_app` action) |
| `verify_element_state` | `verify` (`use_app` action) |

142 live tools are never referenced in the 33 files (expected — the catalogue
is much larger than Legacy's 291).

## 5. File inventory (33 files, 4,548 lines)

Destination path for every file:
`swiftcode/Sources/SwiftCodeAssistant/Resources/System Assets/<file>.md`
(the `Resources/System Assets/` directory does not exist yet — see
`INTEGRATION.md`).

| File | Lines | What it is |
|---|---|---|
| `AgentSystemAsset.md` | 155 | Navigation/routing index: responsibilities table for all 33 files, retrieval triggers, dependency relationships |
| `AgenticLoop.md` | 140 | The Antigravity agent loop and the SwiftCode/Antigravity ownership boundary |
| `ArtifactsGuidelines.md` | 392 | Native Markdown artifact workflow: when to create, quality standards, display titles, Plan integration |
| `Authentication.md` | 50 | Google Cloud SDK authentication and credential handling |
| `AvailableTools.md` | 724 | The tool catalog — fully regenerated from the live 433-tool catalogue, grouped by 37 families |
| `BuildAndTesting.md` | 152 | Build, test, and diagnostic procedures |
| `CallTool.md` | 143 | Tool-call mechanics: parameter rules, quirks, per-tool call notes |
| `CodeReviewSystemAsset.md` | 142 | Code review procedure and the `task_ready`/`task_failed` verdict contract |
| `ContextBudgeting.md` | 75 | Context budget discipline and compaction |
| `Contexts.md` | 78 | Conversation/context persistence and clearing |
| `CreatingAppAsset.md` | 103 | App-creation procedure (`create_new_app`) |
| `DocumentationWithGitHub.md` | 142 | Documentation lookup via `github_repo` / `fetch_documentation` |
| `ErrorHandling.md` | 95 | Error classification and recovery discipline |
| `ExecutionPlans.md` | 154 | Execution plans: structure, lifecycle, persistence |
| `FileOperations.md` | 127 | File read/write/edit rules and line ranges |
| `Identity.md` | 91 | Assist identity and provider-identity policy |
| `LocalizingApps.md` | 225 | Full Apple-app localization procedure (verbatim — destination-accurate) |
| `ModelProviders.md` | 71 | The 13 provider kinds and model selection |
| `ProjectContext.md` | 72 | Project context: workspace root, registration, snapshots |
| `ResponseFormatting.md` | 60 | Response format: Markdown, activity items, announcements |
| `Safeguards.md` | 121 | Safeguards: destructive-operation gates, single approval gate, prohibited names |
| `Skills.md` | 53 | Skill discovery and invocation (`search_skills`) |
| `Streaming.md` | 64 | Streaming presentation in the conversation view |
| `SwiftUsage.md` | 173 | Swift/SwiftUI usage guidance |
| `SystemIndex.md` | 67 | The indexing/retrieval service contract (`system-index-depends`, chunking, persistence, failure semantics) |
| `TakeScreenrecord.md` | 108 | The `take_screenrecord` tool |
| `TakeScreenshot.md` | 117 | The `take_screenshot` tool |
| `TaskCompletion.md` | 55 | Task completion and handoff |
| `ToolRoutingPolicy.md` | 86 | Tool-routing policy: which tool for which operation, terminal governance, risk tiers |
| `UseApp.md` | 125 | The `use_app` tool: native macOS application interaction & Accessibility automation |
| `UsingApp.md` | 154 | Using `use_app`: operations, parameters, verification |
| `UsingSystem.md` | 110 | Using `use_system`: the 11 system operations (verbatim — destination-accurate) |
| `WorkingWithArtboards.md` | 124 | Artboards guidance: modes, tools, no live preview |

## 6. What this slice does NOT do

- The `SystemIndexService` loader itself is NOT part of this slice. The
  files are bundled resources awaiting it; `SystemIndex.md` describes the
  service to build, and `MetaAssistTurnExecutor.swift:46` states "SwiftCode
  has no `SystemIndexService`". The `SwiftCodeAssistant` target needs the
  wiring in `INTEGRATION.md` so the files are bundled at all.
- `docs.search`-adjacent content is Wave 19 slice A, not this slice.
- The stale `use_terminal` / `plan-AskUser` / `generate_xcodeproj`
  registered descriptions are source fixes, not doc fixes — listed in
  `REMAINDER.md`.
- No Swift tools were run (per Dylan's 2026-11-06 instruction). Verification
  is static only: catalogue re-derivation, grep counts, delimiter balance,
  `python3 -I` scripts. The Mac build/test verification remains pending on
  Dylan's Mac; nothing is marked VERIFIED.

## 7. Evidence

- Catalogue derivation: `derive-catalogue.py` run twice, both times
  `tools found: 433, unique: 433, duplicates: none`; risks
  `{execution: 54, safeRead: 229, safeMutation: 114, externalSideEffect: 23,
  potentiallyDestructive: 13}`; `writes=true: 170`; 37 families.
  Tool function: `SwiftCodeTools.swift:65`
  (`annotations: MCPToolAnnotations = .read, writes: Bool = false`).
- Approval model: `SwiftCodeTools+Terminal.swift` header, lines ~40–130
  (single approval gate; no allow-list / Full Access / Autopilot).
  `use_workers` planning-only: `SwiftCodeTools+WorkersRuntime.swift:174`.
  `use_app` approval gate: `AppInteraction.swift:1025`
  (`approveChangeWithoutFile`).
- `file_read` lines: `SwiftCodeTools+Workspace.swift:42-51`.
  `file_write`/`file_create` no pbxproj registration:
  `SwiftCodeTools+FileWriting.swift:68` (comment).
  `code_generate` templates: `FileWriting.swift:249`.
  `project_snapshot` store: `ProjectModel.swift:461-465`.
  `create_new_app` workspace root + bundle ID:
  `ProjectModel.swift:903,907`.
  `search_skills` limit: `Search.swift:175,738`.
- `take_screenshot` params: `Terminal.swift:341`.
  `take_screenrecord` params: `Terminal.swift:361`.
  `use_app` operations: `AppInteraction.swift:122-132` (full list in the
  error string at line 132; `select_window` handler at line 1048).
  `use_system` operations: `Terminal.swift:1373-1374`.
- Review verdict contract: `ReviewDocs.swift:73-78, 856-857`.
  `github_repo` operations: `Git.swift:974-1017`.
  DocC pipeline + 24h cache: `Engines.swift:91-92`.
  `localize_app` actions: `AssetsLocalization.swift:808-809`.
  `ProviderKind` 13 cases: `Core.swift:8-27`.
  `ConversationView.message.activity`: `ConversationView.swift:511`.
  `context_persistence_store`: `MemorySupport.swift:40`.
  Google scopes: `GoogleAccountAuthService.swift:545-556`.
  `intel_explain_code` static-only: `Planning.swift:365`.
  `task_runner` internal `project_test`: `Terminal.swift:520`.
  `PlanningExecutionMode`: `SwiftCodeTools+PlanningSupport.swift:28`.
  `MetaAssistTurnExecutor.swift:46` ("SwiftCode has no `SystemIndexService`").
  `SwiftCodeTools+ReviewDocs.swift:81` ("the full 141-line asset is not
  ported" — now superseded by this slice).
- Stale-description flags (live registered text, verified by grep):
  `use_terminal` description mentions allow-list / Full Access;
  `plan-AskUser` description mentions "blocked at the runtime registry layer
  in Autopilot mode"; `generate_xcodeproj` description says "Installs XcodeGen
  automatically if missing" while the handler fails honestly.
- Destination has no `SystemIndexService`, no SystemAssetsManager, no
  `Resources/` dir in `SwiftCodeAssistant`; `SwiftCodeAssistant` target
  (`swiftcode/Package.swift:113`) has no `resources:` entry.
- Ledger: 33 rows `SwiftCode/Backend/Assist/Functions/System Assets/*.md`,
  all REVIEW_REQUIRED / NOT STARTED (workspace ledger, pre-integration).
- Verification: `verify-staged.py` final run — `checked 33 files / ALL CHECKS
  PASSED`. `generate-available-tools.py` final run — `OK AvailableTools.md:
  433 tools in 37 families, 724 lines`. `adapt-system-assets.py` re-run is
  deterministic (only `AgenticLoop.md`, `Streaming.md`, `AvailableTools.md`
  changed on the re-run, exactly the three files with new fixes).
