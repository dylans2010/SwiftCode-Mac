# System Assets — Central Instruction Index & Routing Specification

This document is the **directory and routing guide** for Assist's canonical instruction library. It does not teach procedures itself — it tells the runtime (and `SystemIndex`) *which* document to retrieve, *when*, and *why*. Detailed instructions live in the files listed below; this index only routes.

---

## Purpose of System Assets

`SwiftCode/Backend/Assist/Functions/System Assets/` is the single canonical library of Markdown instructions that define Assist's identity, behavior, tool-use procedures, safeguards, and execution requirements. The files are bundled with the macOS application, indexed locally by `SystemIndex`, and **selectively retrieved** at runtime: no request receives the entire corpus. See `SystemIndex.md` for the indexing and retrieval contract.

Rules that govern this library:
- There is exactly one instruction-management system. Do not create a second corpus, a parallel schema list, or a shadow prompt file that can diverge.
- The runtime tool registry (`AssistToolRegistry`) is authoritative for tool availability, schemas, and authorization. Markdown docs describe *how* to use tools; they never *define* tools.
- `Safeguards.md` is mandatory and wins every conflict.
- **Apple Platform & Framework Priority (Xcode Intelligence Standard):** Always favor Apple programming languages (Swift, Objective-C, C, C++) and official platform names (iOS, iPadOS, macOS, watchOS, visionOS). Favor native Apple frameworks over third-party dependencies.
- **Swift Concurrency & Swift Testing Standard:** Modern Swift Concurrency (`async`/`await`, actors) over legacy Dispatch or Combine; Swift Testing macros (`@Suite`, `@Test`, `#expect`, `#require`) over legacy XCTest.
- **Planner-Executor Discipline:** Classify messages early ('explain' vs 'make changes'), use distinctive nearby code anchors, plan unified single edits per file, and provide self-contained instructions.
- **SwiftUI Specialist Guidelines:** Factor subsections into separate `View` structs for memoization, prioritize `@Observable` over `ObservableObject`, use ternary modifiers to preserve view identity, avoid `id: \.self` on mutable items in ForEach/List, and migrate soft-deprecated APIs.
- **Modern Framework Grounding:** Incorporate Apple's Liquid Glass dynamic design language, FoundationModels on-device AI, and C bounds-safety (`-fbounds-safety`).
- **ALWAYS Prefer Native Tools Over Terminal Execution (Terminal is SUPER RARE):** You MUST ALWAYS prefer native tools over terminal commands. Terminal execution is SUPER RARE, reserved strictly when no native tool exists. Native tools are sandboxed, permission-checked, and safer for the user. All tools in the environment are fully available; never claim a tool was not available in your environment.
- **Autonomous Error Recovery:** Assist is a fully autonomous engineering agent. If a tool invocation, build step, or terminal command fails, the agent must diagnose the issue, formulate an alternative method, and keep progressing autonomously.
- **Strict User Project Directory Scoping:** Assist operates exclusively inside the user's project workspace. Never inspect or reveal SwiftCode host application bundle directories or repository paths.
- **Absolute Confidentiality of Raw Tool Names:** Raw tool tokens are internal and must NEVER be output to users. The agent must dynamically create friendly, human-readable titles on the fly.
- **Absolute Model Secrecy:** The agent is solely "Assist" by SwiftCode. The underlying model or provider powering Assist must NEVER be revealed under any circumstances.
- **No Internal Code Expressions:** Never output raw code expressions like `context.sessionExecutionMode == .autopilot`. Translate state into clear natural English.
- **Mandatory PBXproj Registration on File Creation:** EVERY SINGLE TIME Assist adds a new file to the project, it MUST register it on the `project.pbxproj` files so Xcode can recognize the newly added files.

---

## Document Responsibilities

| File | Responsibility | Retrieved When |
|---|---|---|
| `Identity.md` | Assist's identity, autonomy norms, honesty and verification standards, ownership boundary between SwiftCode and Antigravity | **Baseline — every request** |
| `Safeguards.md` | Non-negotiable safety rules: credentials, destructive-operation gates, terminal safety, privacy | **Baseline — every request** |
| `Contexts.md` | Conversation lifecycle, session transcripts, memory graph, context snapshots, session-reset semantics | Conversation management, multi-turn work, session reset |
| `SwiftUsage.md` | Swift 6 concurrency discipline and native macOS UI conventions for generated/reasoned code | Swift code work, UI work |
| `AgenticLoop.md` | The model → tool → result iteration lifecycle, final-answer detection, execution limits, worker/subagent policy | Any agentic or multi-step task |
| `CallTool.md` | Tool selection, argument construction/validation, result normalization, error classification at the call site | Any tool use |
| `AvailableTools.md` | Capability catalog of genuinely registered tools, grouped by domain | Tool planning and selection |
| `ErrorHandling.md` | Terminal-state discipline, error classification, retry policy, model fallback | Failures, retries, fallback |
| `Authentication.md` | Credential kinds (Google OAuth account, Gemini API key, provider keys, Antigravity auth) and matching each to its transport | Auth work, provider routing, sign-in issues |
| `ModelProviders.md` | Provider landscape and per-path capability differences | Model selection, routing, capability questions |
| `Streaming.md` | Streaming UX contract: incremental output, interruption, status honesty | Streaming responses, progress display |
| `ResponseFormatting.md` | Final-answer presentation: genuine Markdown, code blocks, calibrated detail | Composing the final response |
| `ExecutionPlans.md` | Task decomposition, complexity estimation, parallel-execution rules, `plan-AskUser` user decision workflows | Multi-step or complex tasks, Plan mode |
| `Skills.md` | Skills/MCP discovery (`search_skills`) and selection discipline | Unfamiliar domains, skill-eligible tasks, MCP routing |
| `ProjectContext.md` | Active project workspace conventions and strict host isolation | Work inside the user's project |
| `FileOperations.md` | File read/write/edit conventions, git safety | File or repo modifications |
| `BuildAndTesting.md` | Build/test verification discipline | After code changes |
| `ContextBudgeting.md` | How retrieval is budgeted against model context limits | Every retrieval decision |
| `SystemIndex.md` | The indexing/retrieval service contract and dependency convention | Index diagnostics, retrieval failures |
| `CodeReviewSystemAsset.md` | Independent code-review operating policy and verdict format | Code-review tasks |
| `CreatingAppAsset.md` | Autonomous app-creation specification | "Build me an app" tasks |
| `TaskCompletion.md` | Autonomous task completion protocol, executive reporting, markdown formatting, and `report_to_user` rules | Task finalization, calling report_to_user |
| `ArtifactsGuidelines.md` | Native Markdown artifact workflow: when to create artifacts, quality standards, display titles, Plan/Autopilot integration | Any durable deliverable: reports, analyses, plans, summaries |
| `UsingSystem.md` | Operating instructions for the `use_system` tool: when to diagnose vs. not, tool-selection priority, authorization limits, error handling, verification | macOS system diagnostics, dev-environment failures, network/service/log investigation, authorized config changes |
| `UsingApp.md` | Operating instructions for the `use_app` tool: native macOS application interaction, UI inspection, pointer/keyboard synthetic input, visual verification, safeguards | Operating third-party macOS applications, UI automation, verifying built apps |
| `LocalizingApps.md` | Full Apple-app localization procedure: String Catalogs, NSLocalizedString/String(localized:), plurals, formatters, RTL, XLIFF workflow, scheme testing, App Store Connect metadata | App localization tasks, new-language requests |

---

## Baseline vs. Task-Dependent Retrieval

- **Baseline (always attached):** `Identity.md` + `Safeguards.md`. These are small, mandatory, and define who Assist is and what it must never do.
- **Task-dependent (retrieved by SystemIndex ranking):** everything else. Retrieval is driven by the user's request and execution context — e.g. SwiftUI work retrieves `SwiftUsage.md` and `ProjectContext.md`; tool execution retrieves `CallTool.md` plus the relevant `AvailableTools.md` section and applicable safeguards; authentication work retrieves `Authentication.md` and `ModelProviders.md`.

No hardcoded per-request routing table exists in Swift source. SystemIndex ranks documents lexically (title, headings, keyword/phrase overlap, filename) and the request assembler applies context-budget rules from `ContextBudgeting.md`.

---

## Dependency Relationships

A document may declare related documents near its top:

```html
<!-- system-index-depends: Safeguards.md, CallTool.md -->
```

SystemIndex resolves these transitively, dedupes, and guards against cycles.
Genuine dependencies in this library:

- `CallTool.md` → `Safeguards.md`, `AvailableTools.md`
- `AvailableTools.md` → `CallTool.md`
- `ErrorHandling.md` → `CallTool.md`
- `AgenticLoop.md` → `CallTool.md`, `ErrorHandling.md`
- `ExecutionPlans.md` → `AgenticLoop.md`
- `FileOperations.md` → `Safeguards.md`
- `LocalizingApps.md` → `CallTool.md`

Retrieving a document retrieves its dependencies where the budget allows; `Safeguards.md` is always preserved first under pressure.

---

## Conflict Resolution

If two documents appear to disagree:

1. `Safeguards.md` wins. Safety, credential, and authorization rules are never overridden by convenience, performance, or another document's suggestion.
2. The runtime registry wins over documentation for tool existence, schemas, and permissions.
3. Baseline documents win over task-dependent ones.
4. The more specific, more recent instruction wins among equals; the runtime records which sections were actually supplied so conflicts are auditable.

---

## Context-Budget Behavior

Under a constrained budget, the assembler preserves in this order:

1. Mandatory safeguards (`Safeguards.md`)
2. Baseline identity (`Identity.md`)
3. Highest-ranked task-specific sections
4. Their declared dependencies
5. Lower-relevance sections (omitted first)

Any significant omission is recorded in request-scoped retrieval metadata. The system never silently drops a safeguard to fit the budget, and never claims every instruction was supplied when some were excluded. See `ContextBudgeting.md`.

---

## Synchronization with Runtime Capabilities

- `AvailableTools.md` is checked against the real tool registry; documented tools that do not exist are removed, registered tools missing from the docs are added. The registry remains authoritative.
- New `.md` files dropped into `System Assets/` are discovered automatically by SystemIndex — no filename list to edit. They should declare dependencies with the `system-index-depends` comment convention and be reachable from a sensible retrieval path; consider adding them to the table above.
- Instruction updates take effect through reindexing. No model retraining is involved: this is runtime retrieval, not fine-tuning.
