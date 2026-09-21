# Technical Implementation Blueprint: Next-Generation Code Editor (Universal IDE)

> **Document Classification**: Master Engineering Specification & Implementation Contract  
> **Target Audience**: Autonomous AI Agents & Systems Engineers building the new code editor.  
> **Scope**: Contains the functional architectures, domain models, algorithms, tool schemas, communication protocols, and execution workflows audited from the 1,500+ file SwiftCode codebase.  
> **Design Constraint**: All SwiftCode-specific visual styling, color palettes, and view frames are omitted. The new code editor must implement **every functional capability, engine, tool, and protocol** specified herein using its own native design system and UI components.
> **Excluded by Requirement**: Linux Virtualization Engine / VMs, standalone Syntax Highlighting / Tokenization lexer, File Management / Scaffolding Templates (Section 3), and P2P Real-Time Collaboration (Section 21).

---

## Table of Contents

1. [Executive Architecture & State Machine](#1-executive-architecture--state-machine)
2. [Code Editor Subsystem](#2-code-editor-subsystem)
3. [Autonomous AI Agent Architecture](#3-autonomous-ai-agent-architecture)
4. [Agent Tooling Suite (142 Tools + 63 Assist Tools)](#4-agent-tooling-suite-142-tools--63-assist-tools)
5. [Agent Skills System & Model Context Protocol (MCP) Host](#5-agent-skills-system--model-context-protocol-mcp-host)
6. [AI Model Infrastructure (Local, Remote, On-Device)](#6-ai-model-infrastructure-local-remote-on-device)
7. [Build Systems, Compilers & Deployment Pipeline](#7-build-systems-compilers--deployment-pipeline)
8. [Physical Device Deployment & SwiftCode Connect Protocol](#8-physical-device-deployment--swiftcode-connect-protocol)
9. [SwiftUI Live Preview & Simulation Engine](#9-swiftui-live-preview--simulation-engine)
10. [Source Control, Git Engine & 3-Way Conflict Resolver](#10-source-control-git-engine--3-way-conflict-resolver)
11. [Visual UI Builder & Artboard Canvas](#11-visual-ui-builder--artboard-canvas)
12. [Database Explorer & Data Studio](#12-database-explorer--data-studio)
13. [StoreKit Workspace & In-App Purchase Simulation](#13-storekit-workspace--in-app-purchase-simulation)
14. [Personal Documentation & Architecture Knowledge Base](#14-personal-documentation--architecture-knowledge-base)
15. [Developer Operations, Diagnostics & Telemetry](#15-developer-operations-diagnostics--telemetry)
16. [Built-In Developer Utilities Suite (156 Tools)](#16-built-in-developer-utilities-suite-156-tools)
17. [Offline Coding Dictionary & API Reference System](#17-offline-coding-dictionary--api-reference-system)
18. [Extension & Plugin Ecosystem](#18-extension--plugin-ecosystem)
19. [Global Command Palette & Keyboard Shortcuts Matrix](#19-global-command-palette--keyboard-shortcuts-matrix)
20. [Implementation Master Checklist](#20-implementation-master-checklist)

---

## 1. Executive Architecture & State Machine

### 1.1 Unidirectional State Pipeline
The editor is governed by a unidirectional downward dependency model:
```
+-------------------------------------------------------------+
|                     PRESENTATION LAYER                      |
|  - UI-Agnostic ViewModels, State Observers, Action Triggers |
+------------------------------+------------------------------+
                               | (Observes state / Triggers)
                               v
+-------------------------------------------------------------+
|                     SERVICE & ACTOR LAYER                   |
|  - Concurrency-safe Actors (Git, Build, Compiler, AI, Net)  |
+------------------------------+------------------------------+
                               | (Mutates / Validates)
                               v
+-------------------------------------------------------------+
|                      CORE DOMAIN LAYER                      |
|  - Immutable Models, AST Entities, Protocols, Result Enums  |
+-------------------------------------------------------------+
```

### 1.2 Concurrency & Thread-Safety Contracts
1. **Actor Isolation**: All I/O-intensive services (Git execution, file diffing, process pipelines, build log streaming, socket networking) run inside dedicated Swift `actor` instances or background async tasks.
2. **Main-Thread Guarantees**: UI-observable view models (`@Observable` or `@MainActor`) receive mutated domain models strictly through structured concurrency (`async`/`await`), preventing UI thread blocking.
3. **Cancellation Propagation**: Every long-running operation (build, test, AI generation, terminal execution) must support cooperative cancellation via `Task.isCancelled` and process termination handlers.

### 1.3 Security & Keychain Storage Protocol
The application delegates secret management to the operating system Keychain:
- **Service Name**: `com.editor.security.keychain`
- **Stored Keys**:
  - `openrouter_api_key`: Remote LLM API token.
  - `github_personal_access_token`: GitHub OAuth / PAT token.
  - `codex_user_api_key` / `codex_app_api_key`: Codex bridge authentication tokens.
  - `deploy_vercel_token` / `deploy_netlify_token`: Web deployment credentials.
  - `connect_truststore_keys`: Cryptographic client public keys for companion device pairing.
- **Path Traversal Protection**: Every file path passed to an internal service or agent tool must be sanitized against standard directory traversal attacks (`../`, symlink cycles, null byte injection). Paths resolving outside the current project root trigger an immediate `PathSecurityError.invalidPath`.

---

## 2. Code Editor Subsystem

### 2.1 Tab & Document Coordinator
- **`DocumentCoordinator`**: Manages open file documents, preserving dirty states, undo/redo stacks, and cursor locations.
- **Document Entity Model**:
  ```swift
  public struct SourceFileDocument: Identifiable, Sendable {
      public let id: UUID
      public let fileURL: URL
      public var content: String
      public var isDirty: Bool
      public var encoding: String.Encoding
      public var lineEndings: LineEndingStyle // .lf, .crlf
      public var cursorPosition: CursorPosition
      public var selections: [TextSelection]
  }
  ```
- **Tab State Tracking**: Supports multiple split panes (side-by-side or stacked), pinned tabs, and automated workspace tab persistence across restarts.

### 2.2 Minimap Viewport Engine
- **Scaled Miniature Renderer**: Projects document tokens onto a condensed canvas (1:6 vertical scale).
- **Viewport Rect Tracking**: Tracks the active visible line range of the primary editor viewport, rendering an interactive translucent scrubber.
- **Diagnostic Overlays**: Renders error badges (red), warning badges (yellow), search match highlights, and git addition/modification/deletion gutters directly on the minimap strip.
- **Scrubbing Navigation**: Clicking or dragging on the minimap smoothly interpolates the primary scroll view to the corresponding document offset.

### 2.3 AST Scope Detection & Code Folding
- **Block Boundary Analyzer**: Analyzes indentation levels and scope delimiters (`{ ... }`, `[ ... ]`, `( ... )`, `func`, `class`, `struct`, `enum`, `if`, `guard`).
- **Folding State Registry**: Tracks folded line ranges `[StartLine...EndLine]`.
- **Placeholder Rendering**: Collapses folded regions into an inline indicator (e.g. `...`) while preserving internal cursor navigation and searchability.

### 2.4 Ghost-Text Inline AI Autocomplete (`AISuggestionEngine`)
- **Debounced Trigger**: Listens for typing pauses (configurable 250ms–500ms debounce).
- **Context Extraction**:
  - Pre-cursor context: 80 lines preceding cursor.
  - Post-cursor context: 30 lines following cursor.
  - Active file metadata: language identifier, file imports, declared symbols.
- **Ghost Rendering**: Renders speculative continuation text directly in the editor buffer using an inline muted rendering style.
- **Key Interception**:
  - `Tab`: Commits entire suggested snippet into document buffer.
  - `Opt + RightArrow`: Accepts next word of suggestion.
  - `Escape` / typing non-matching character: Immediately dismisses suggestion without modifying document.

### 2.5 Specialized Document Editors
- **`InfoPlistEditor`**:
  - Key-value schema editor for Apple `Info.plist` files.
  - Human-friendly translation of raw keys (e.g. `NSCameraUsageDescription` $\to$ "Privacy - Camera Usage Description").
  - Type-safe value inputs: Boolean, String, Array of Strings, Dictionary.
- **`EntitlementsEditorManager`**:
  - Capabilities toggle manager updating `.entitlements` XML files.
  - Pre-defined schemas for App Sandbox, Push Notifications, Keychain Sharing, Network Server/Client, iCloud Containers, Associated Domains, and Sign in with Apple.
- **`MarkdownFileView`**:
  - Live split-view or toggle preview rendering GitHub Flavored Markdown (GFM).
  - Handles headings (H1-H6), task checklists (`- [ ]`), fenced code blocks with copy actions, tables, blockquotes, and internal asset links.

---

## 3. Autonomous AI Agent Architecture (Assist Engine)

The autonomous agent system in SwiftCode is centered around the **Assist Architecture**, comprising `AssistAgentSession`, `_AssistCriticalAutonomousEngine`, `_AssistCriticalExecutionEngine`, `_AssistCriticalValidationEngine`, `_AssistCriticalCodebaseAnalyzer`, and 23 specialized cognitive engines.

### 3.1 Core Domain Models & Session State Machine

#### State Hierarchy & Transition Model
The session state is tracked via an authoritative state machine implemented in `AssistAgentSession.swift`:
```swift
public enum AgentSessionStatus: String, Codable, Sendable {
    case idle                  = "Idle"
    case receivingRequest      = "Receiving Request"
    case analyzingRepository   = "Analyzing Repository"
    case collectingContext     = "Collecting Context"
    case planning              = "Formulating Execution Plan"
    case selectingTools        = "Selecting Tools"
    case executingTool         = "Executing Tool"
    case validating            = "Validating Implementation"
    case reviewing             = "Autonomous Code Review"
    case generatingSummary     = "Compiling Summary"
    case completing            = "Finalizing Task"
    case terminated            = "Terminated / Succeeded"
    case failed                = "Execution Failed"
}

public struct StateTransition: Codable, Sendable {
    public let timestamp: Date
    public let fromState: AgentSessionStatus
    public let toState: AgentSessionStatus
    public let reason: String
}

public struct AgentEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let state: AgentSessionStatus
    public let summary: String
    public let toolResult: String?
}

public struct ExecutionSummaryData: Codable, Sendable {
    public let objective: String
    public let totalDuration: TimeInterval
    public let toolCallCount: Int
    public let filesCreatedCount: Int
    public let filesModifiedCount: Int
    public let filesDeletedCount: Int
    public let validationCount: Int
    public let reviewerConfidence: Double
    public let finalOutcome: String
}
```

#### The Atomic State Transition Contract
Every state change in the editor must execute through the isolated transition helper:
```swift
@MainActor
public func transition(to newState: AgentSessionStatus, reason: String, toolResult: String? = nil) {
    let oldState = self.state.status
    guard oldState != newState else { return }

    let transition = StateTransition(fromState: oldState, toState: newState, reason: reason)
    self.state.stateHistory.append(transition)
    self.state.status = newState

    pipelineLogger.info("[State Transition] \(oldState.rawValue) -> \(newState.rawValue) | Reason: \(reason)")
    DiagnosticEventBus.shared.logEvent(
        component: "AssistAgentSession",
        severity: "INFO",
        category: "state_transition",
        message: "Transitioned from \(oldState.rawValue) to \(newState.rawValue). Reason: \(reason)"
    )

    let event = AgentEvent(state: newState, summary: reason, toolResult: toolResult)
    self.state.events.append(event)
    updateAgentNotes()
}
```

---

### 3.2 End-to-End Autonomous Execution Lifecycle

```
[Start Session]
       │
       ▼
[Phase 0: Pre-Flight Environment Validation]
  ├── Verify selected model is non-empty
  ├── Confirm execution mode is "Agent Mode" (`com.swiftcode.assist.mode == true`)
  └── Validate provider API key in Keychain (or AFM local model enablement)
       │
       ▼
[Phase 1: Codebase Archaeology (`_AssistCriticalCodebaseAnalyzer`)]
  ├── Recursively scan directory structure
  ├── Enumerate Swift/source files and active build schemes
  └── Emit baseline diagnostics to `DiagnosticEventBus`
       │
       ▼
[Phase 2: Validation 1/3 (Repository Baseline Verification)]
  ├── Validate baseline syntax and build configurations
  └── Establish clean Git working tree baseline
       │
       ▼
┌───> [Phase 3: Context Assembly & Prompt Construction]
│       ├── Generate repo manifest summary
│       ├── Load active file buffers
│       ├── Serialize dynamic tool schemas from `AssistToolRegistry`
│       ├── Discover active Agent Skills (`SKILL.md`)
│       └── Inject recent tool execution history
│            │
│            ▼
│     [Phase 4: Model Query & JSON Extraction]
│       ├── Dispatch prompt to selected LLM (streaming or non-streaming)
│       ├── Extract strict JSON response (sanitize markdown code fences)
│       └── Determine branch: Tool Call vs. `finalResponse`
│            │
│            ├───────────────────────────────────────────────┐
│            │ (Tool Call: `toolId` + `input`)               │ (`finalResponse`)
│            ▼                                               ▼
│     [Phase 5: Tool Execution & Verification]    [Phase 6: Validation 3/3 (Pre-Review)]
│       ├── Dispatch to `AssistToolRegistry`       ├── Deep AST syntax pass
│       ├── Execute atomic file modifications      └── Dependency integrity audit
│       ├── Capture stdout/stderr/results                    │
│       ├── Post-Edit Validation Check (2/3)                 ▼
│       └── Append to conversation history        [Phase 7: Autonomous Code Review Gate]
│            │                                      ├── Dispatch `code_review` tool
│            │                                      ├── Evaluate reviewer confidence
│            │                                      │   (Threshold: confidence >= 0.85)
│            │                                      ├───────────────┬───────────────┐
│            │                                      │ (Approved)    │ (Rejected)    │
│            │                                      ▼               ▼               │
│            │                           [Phase 8: Summary]  [Feedback Re-injection]│
│            │                             ├── Duration      ├── Extract issues     │
│            │                             ├── Metrics       ├── Inject fixes       │
│            │                             └── Terminate     └── Reset loop count   │
│            │                                  │                   │               │
│            └──────────────────────────────────┴───────────────────┴───────────────┘
```

---

### 3.3 Prompt Engineering & Strict JSON Protocol Contract

The Assist agent interacts with LLMs using a rigid JSON communication protocol. The system prompt template must be injected exactly as specified in SwiftCode:

#### Exact System Prompt Template
```markdown
# SYSTEM PROMPT (OPERATING POLICY)
<AssetSystemPromptContent>

# HIDDEN RUNTIME INSTRUCTIONS & ROLE
Execution Key: com.SwiftCode.Assist-Agent
Execution Mode: com.SwiftCode.Assist-Agent

You are an autonomous Swift/macOS coding agent working in the Universal Code Editor.
Your goal is: "{objective}"

You can execute local actions by outputting a JSON object.
Choose one of the available tools, or output a final response when the task is complete.

You MUST respond in exactly this JSON format (no markdown backticks, no text outside the JSON):
{
  "toolId": "the_tool_id",
  "input": { "key": "value" },
  "explanation": "Why you are using this tool"
}
OR, if the goal is fully achieved and no more tools are needed:
{
  "finalResponse": "A clear, detailed description of your achievements and the files modified"
}

# ATTACHED FILES FOR THIS TASK (READ-ONLY REFERENCE)
<AttachedFilesBlock>

# DISCOVERED SYSTEM SKILLS
<SkillsBlock>

# CONVERSATION CONTEXT & WORKSPACE
<RepoManifestSummary>

# ACTIVE FILE CONTENTS
<ActiveFileContentsBlock>

# AVAILABLE TOOLS
<SerializedToolSchemas>

# SECURITY CONSTRAINTS
- Never use relative traversal (e.g. "..") or root paths (e.g. "/").
- Always double check file paths before reading/writing.
```

#### Robust JSON Extraction Algorithm
To handle LLM output variations (such as speculative conversational text or markdown code blocks), the agent implements `extractJSON(from:)`:
```swift
public func extractJSON(from response: String) -> [String: Any]? {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

    // 1. Direct JSON attempt
    if let data = trimmed.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        return json
    }

    // 2. Fenced Markdown block extraction (```json ... ```)
    if let startRange = trimmed.range(of: "```json"),
       let endRange = trimmed.range(of: "```", range: startRange.upperBound..<trimmed.endIndex) {
        let block = trimmed[startRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = block.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
    }

    // 3. Regex boundary scanner ({ ... })
    if let firstBrace = trimmed.firstIndex(of: "{"),
       let lastBrace = trimmed.lastIndex(of: "}") {
        let block = trimmed[firstBrace...lastBrace]
        if let data = block.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
    }

    return nil
}
```

---

### 3.4 The Three-Tier Validation System (`_AssistCriticalValidationEngine`)

To ensure generated code never breaks existing workspaces, execution enforces three mandatory validation passes:

1. **Validation 1/3 (Pre-Planning Baseline)**:
   - Invoked before the agent generates its execution plan.
   - Verifies that target project paths exist, build scheme files are readable, and the initial workspace compiles without pre-existing errors.
2. **Validation 2/3 (Post-Edit Incremental Pass)**:
   - Invoked immediately following any file-modifying tool call (`AssistWriteFileTool`, `AssistInsertCodeBlockTool`, `AssistReplaceInFileTool`).
   - Executes an isolated background compiler pass (`swiftc -typecheck <ModifiedFile>`) to detect syntax errors, missing symbols, and import violations.
   - If an error is detected, the error diagnostic is injected directly into the conversation history as a high-priority system feedback item, prompting immediate remediation.
3. **Validation 3/3 (Pre-Review Synthesis Pass)**:
   - Invoked when the model outputs `finalResponse`.
   - Compiles all modified targets, audits the package dependency graph, and verifies that public symbol signatures remain consistent.

---

### 3.5 Autonomous Code Review Gate (`CodeReviewTool`)

When the model emits `finalResponse`, the session **does not immediately terminate**. It must pass an autonomous code review gate:

1. **Invocation**: The session invokes the `code_review` tool against the active changes.
2. **Evaluation Criteria**:
   - Status must equal `"task_ready"`.
   - Reviewer confidence score must be $\ge 0.85$.
   - Must contain zero critical architecture, security, or concurrency violations.
3. **Approval Path**:
   - Compiles `ExecutionSummaryData` (duration, tool calls, files modified/created/deleted).
   - Transitions to `.completing`, then `.terminated`.
4. **Rejection Path & Feedback Injection**:
   - If the review fails, the agent increments `codeReviewAttempts`.
   - Extracts structured feedback arrays: `strengths`, `issues`, and `recommendedFixes`.
   - Formats feedback into a system revision request:
     ```
     - Action: Final Response. Code Review Result: FAILED - Revisions required.
       Strengths:
       - <Strength 1>
       Issues detected:
       - <Issue 1>
       Recommended Fixes:
       - <Fix 1>
     Please review these issues, update your plan, make the required modifications to the codebase, verify them, and call code_review again.
     ```
   - Injects this feedback into `conversationHistory`, resets the no-progress stability counter, and loops back to `planning`.

---

### 3.6 Continuous Autonomous Takeover & Multi-Goal Expansion

When continuous takeover mode is enabled (`assist.takeoverEnabled == true`), the agent operates indefinitely without user intervention:

1. **`AssistGoalExpansionEngine`**:
   - Upon completing the primary task, analyzes the generated codebase to discover necessary follow-up work (e.g. unit test generation, DocC documentation, edge-case hardening, performance benchmarks).
   - Returns an array of newly synthesized follow-up goals: `expandedGoals: [String]`.
2. **`AssistTaskContinuationEngine`**:
   - Evaluates whether to proceed based on safety limits:
     ```swift
     let shouldContinue = await taskContinuation.shouldContinue(currentGoal: currentIntent, completedPlan: plan)
     ```
   - If affirmative, dequeues the next task, resets the iteration counters, saves the session state to `AssistExecutionContextPersistenceStore`, and restarts the execution cycle with the next objective.

---

### 3.7 Cognitive Heuristics & Self-Healing Engines

1. **`AssistLoopStabilityRegulator`**:
   - Tracks execution signatures across the last 15 iterations.
   - Detects three distinct failure patterns:
     - `.infiniteLoop(reason)`: Repeated identical tool calls with identical arguments.
     - `.oscillation(pattern)`: Alternating between two mutually breaking changes (e.g. editing line A breaks line B, editing line B breaks line A).
     - `.noProgress(iterations)`: Iteration count exceeds 15 without changing disk state.
   - Remediation: Forces an adaptive strategy shift by mutating the active prompt with: `"Break out of loop/stagnation. Try a completely different technique for: <goal>"`.
2. **`AssistContextDriftDetector`**:
   - Computes semantic alignment between `originalGoal` and current `currentIntent`.
   - If `driftScore > 0.8`, automatically cancels intermediate diversions and resets `currentIntent = originalIntent`.
3. **`AssistFailureRootCauseAnalyzer` & `AssistRecoveryStrategyGenerator`**:
   - Maps compiler diagnostics to structured root causes: `MissingImport`, `TypeMismatch`, `UnresolvedIdentifier`, `AccessViolation`.
   - Generates deterministic recovery actions:
     - Missing import $\to$ Scans project for type declaration and inserts required `import <Module>`.
     - Type mismatch $\to$ Generates cast or converts model properties.
4. **`_AssistCriticalExecutionEngine` & `CodePatchEngine`**:
   - Before modifying any file, saves an in-memory snapshot (`Checkpoint`).
   - If recovery fails after 2 iterations, triggers `RollbackChanges` to revert the project to the pre-modification baseline.
   - When creating new files (`createMissingFile`), automatically maps and writes four coordinated entries to the project manifest (`PBXFileReference`, `PBXBuildFile`, `PBXSourcesBuildPhase`, `PBXGroup`) to prevent broken target references.

---

## 4. Agent Tooling Suite (142 Tools + 63 Assist Tools)

The new code editor must provide complete functional implementations for all 205 tools detailed below. Every tool conforms to the standard `ExecutableTool` interface:
```swift
public protocol ExecutableTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parametersSchema: ToolParametersSchema { get }
    func execute(arguments: [String: Any], context: ToolExecutionContext) async throws -> ToolResult
}
```

### 4.1 The 142 Agentic Tools (`Tools/Agentic`)

#### File & Directory Operations (14 Tools)
1. **`CreateFile`**: Arguments: `path: String`, `content: String`, `overwrite: Bool`. Creates file with UTF-8 encoding.
2. **`ReadFile`**: Arguments: `path: String`, `startLine: Int?`, `lineCount: Int?`. Returns sliced or full content with line numbers.
3. **`ReadMultipleFiles`**: Arguments: `paths: [String]`. Reads up to 20 files in parallel; returns a dictionary of `{ path: content }`.
4. **`EditFile`**: Arguments: `path: String`, `targetContent: String`, `replacementContent: String`. Replaces specific target block.
5. **`WriteFile`**: Arguments: `path: String`, `content: String`. Overwrites entire file contents atomically.
6. **`CopyFile`**: Arguments: `sourcePath: String`, `destinationPath: String`. Copies file with attribute preservation.
7. **`MoveFile`**: Arguments: `sourcePath: String`, `destinationPath: String`. Moves/renames files.
8. **`DeleteFile`**: Arguments: `path: String`, `moveToTrash: Bool`. Deletes file or moves to system trash.
9. **`CreateDirectory`**: Arguments: `path: String`, `recursive: Bool`. Creates directory hierarchy.
10. **`DeleteDirectory`**: Arguments: `path: String`, `recursive: Bool`. Deletes directory.
11. **`ListDirectory`**: Arguments: `path: String`, `recursive: Bool`, `maxDepth: Int?`. Returns file names, sizes, types, and modification dates.
12. **`DownloadFile`**: Arguments: `url: String`, `destinationPath: String`. Downloads remote URL directly to disk.
13. **`UploadFile`**: Arguments: `filePath: String`, `endpoint: String`, `headers: [String: String]?`. Uploads file via HTTP multipart POST.
14. **`TreeView`**: Arguments: `path: String`, `maxDepth: Int?`. Generates ASCII visualization of folder tree.

#### Search & Indexing (11 Tools)
15. **`FindText`**: Arguments: `query: String`, `caseSensitive: Bool`. Literal search returning matching lines with line numbers.
16. **`ReplaceText`**: Arguments: `searchQuery: String`, `replacement: String`, `filePattern: String?`. Project-wide search and replace.
17. **`Grep`**: Arguments: `pattern: String`, `path: String?`, `includeGlobs: [String]?`. Fast regex grep across codebase.
18. **`GlobSearch`**: Arguments: `glob: String`. Resolves matching file paths (e.g. `Sources/**/*.swift`).
19. **`SearchFiles`**: Arguments: `query: String`. Fuzzy file name search.
20. **`CodeIndex`**: Arguments: `symbolName: String`. Queries symbol declarations across the project AST index.
21. **`SemanticCodeSearch`**: Arguments: `naturalLanguageQuery: String`. Embeds query and returns semantically similar code snippets.
22. **`CrossReferenceSearch`**: Arguments: `symbolName: String`. Locates all call sites and usages of a symbol.
23. **`CallHierarchy`**: Arguments: `functionName: String`. Returns caller tree and callee tree.
24. **`DocumentationSearch`**: Arguments: `query: String`. Searches offline developer documentation.
25. **`APIReferenceSearch`**: Arguments: `framework: String`, `query: String`. Queries API references for framework classes and methods.

#### Version Control & Git (20 Tools)
26. **`GitStatus`**: Returns clean/dirty state, branch name, staged, unstaged, and untracked files.
27. **`GitAdd`**: Arguments: `files: [String]`. Stages specified files or `["."]` for all.
28. **`GitCommitTool`**: Arguments: `message: String`. Commits staged changes.
29. **`GitDiff`**: Arguments: `staged: Bool`, `filePath: String?`. Returns unified diff string.
30. **`GitLog`**: Arguments: `maxCount: Int?`. Returns commit history (hash, author, date, message).
31. **`GitBranchTool`**: Arguments: `action: String` (list/create/delete), `name: String?`. Manages branches.
32. **`GitCheckout`**: Arguments: `branchOrCommit: String`, `createBranch: Bool`. Switches branches.
33. **`GitPull`**: Arguments: `remote: String?`, `branch: String?`, `rebase: Bool`. Pulls remote commits.
34. **`GitPush`**: Arguments: `remote: String?`, `branch: String?`, `force: Bool`. Pushes local commits.
35. **`GitMerge`**: Arguments: `branch: String`. Merges target branch into active branch.
36. **`GitRebase`**: Arguments: `upstream: String`. Rebases active branch onto upstream.
37. **`GitCherryPick`**: Arguments: `commitHash: String`. Cherry-picks commit onto current branch.
38. **`GitStash`**: Arguments: `action: String` (save/pop/apply/list/drop), `message: String?`. Stash manager.
39. **`GitReset`**: Arguments: `target: String`, `mode: String` (soft/mixed/hard). Resets git HEAD.
40. **`GitRevert`**: Arguments: `commitHash: String`. Creates revert commit.
41. **`GitBlame`**: Arguments: `filePath: String`. Returns per-line commit hash and author attribution.
42. **`GitShow`**: Arguments: `object: String`. Shows commit metadata and unified diff.
43. **`GitTag`**: Arguments: `action: String` (list/create/push/delete), `name: String?`. Manages git tags.
44. **`GitWorktreeTool`**: Arguments: `action: String`, `path: String?`, `branch: String?`. Manages linked worktrees.
45. **`GitClone`**: Arguments: `url: String`, `targetDirectory: String`. Clones remote repository.

#### Build, Compilation & Static Analysis (12 Tools)
46. **`XcodeBuild`**: Arguments: `scheme: String`, `configuration: String`, `destination: String?`. Invokes `xcodebuild`.
47. **`SwiftPackageManager`**: Arguments: `subcommand: String` (build/test/resolve/update), `flags: [String]?`. Runs `swift` toolchain.
48. **`AndroidBuild`**: Arguments: `task: String` (e.g. `assembleDebug`). Runs `./gradlew`.
49. **`RunBuild`**: Triggers active project build pipeline.
50. **`ReadBuildLogs`**: Arguments: `filterSeverity: String?`. Retrieves recent build log output.
51. **`RunLinter`**: Arguments: `path: String?`. Runs configured linters (SwiftLint, ESLint, Flake8).
52. **`RunFormatter`**: Arguments: `path: String?`. Normalizes code formatting.
53. **`RunTypeChecker`**: Arguments: `path: String?`. Standalone compiler type-checking pass.
54. **`RunStaticAnalysis`**: Runs static analyzers to detect dead code and memory leaks.
55. **`CodeAnalysisTool`**: Computes code maintainability index, halstead metrics, and cyclomatic complexity.
56. **`DetectBugs`**: AI-driven static scan for nil dereferences, race conditions, and retain cycles.
57. **`FixBugs`**: Applies automated fixes for identified diagnostics.

#### Testing & QA (4 Tools)
58. **`RunTests`**: Arguments: `testTarget: String?`, `filter: String?`. Executes test suite.
59. **`GenerateUnitTests`**: Arguments: `filePath: String`. Generates complete test suite for classes in file.
60. **`GenerateIntegrationTests`**: Arguments: `modules: [String]`. Synthesizes cross-module integration tests.
61. **`RunBenchmark`**: Arguments: `target: String`. Measures execution latency and throughput.

#### Package Managers (18 Tools)
62. **`InstallDependencies`**: Detects project type and installs dependencies.
63. **`UpdateDependencies`**: Updates dependency manifests to newest compatible versions.
64. **`RemoveDependencies`**: Arguments: `packageNames: [String]`. Uninstalls packages.
65. **`DependencyAudit`**: Scans dependency tree for known CVE vulnerabilities.
66. **`DependencyGraph`**: Generates dependency adjacency graph and detects cycles.
67. **`PackageSearch`**: Arguments: `query: String`, `ecosystem: String` (spm/npm/pypi/cargo). Searches registries.
68. **`CocoaPods`**: Arguments: `action: String` (install/update/outdated). Runs `pod`.
69. **`Carthage`**: Arguments: `action: String` (bootstrap/update). Runs `carthage`.
70. **`Npm`**: Arguments: `arguments: [String]`. Executes `npm`.
71. **`Yarn`**: Arguments: `arguments: [String]`. Executes `yarn`.
72. **`Pnpm`**: Arguments: `arguments: [String]`. Executes `pnpm`.
73. **`Bun`**: Arguments: `arguments: [String]`. Executes `bun`.
74. **`PythonPip`**: Arguments: `arguments: [String]`. Executes `pip`.
75. **`Cargo`**: Arguments: `arguments: [String]`. Executes `cargo`.
76. **`GoBuild`**: Arguments: `arguments: [String]`. Executes `go`.
77. **`Gradle`**: Arguments: `arguments: [String]`. Executes `gradle`.
78. **`JavaMaven`**: Arguments: `arguments: [String]`. Executes `mvn`.
79. **`DotNetCLI`**: Arguments: `arguments: [String]`. Executes `dotnet`.

#### Containers & Mobile Frameworks (8 Tools)
80. **`DockerBuild`**: Arguments: `tag: String`, `dockerfilePath: String?`. Builds Docker image.
81. **`DockerRun`**: Arguments: `image: String`, `ports: [String: String]?`, `env: [String: String]?`. Runs container.
82. **`DockerCompose`**: Arguments: `action: String` (up/down/build). Executes `docker compose`.
83. **`ViewContainerLogs`**: Arguments: `containerId: String`, `tail: Int?`. Fetches container stdout/stderr.
84. **`KubernetesApply`**: Arguments: `manifestPath: String`. Executes `kubectl apply -f`.
85. **`ReactNative`**: Arguments: `subcommand: String`. Executes React Native CLI commands.
86. **`Flutter`**: Arguments: `subcommand: String`. Executes Flutter CLI commands.
87. **`Expo`**: Arguments: `subcommand: String`. Executes Expo CLI commands.

#### Database & Schema (3 Tools)
88. **`SQLQuery`**: Arguments: `databasePath: String`, `sql: String`. Executes query against SQLite or PostgreSQL.
89. **`DatabaseSchemaInspector`**: Arguments: `databasePath: String`. Introspects tables, columns, indexes.
90. **`DatabaseMigrationTool`**: Arguments: `migrationName: String`, `upSQL: String`, `downSQL: String`. Creates migration.

#### System, Shell & Network (12 Tools)
91. **`ExecuteTerminalCommand`**: Arguments: `command: String`, `timeoutSeconds: Int?`. Executes shell command.
92. **`StopRunningProcess`**: Arguments: `pid: Int`. Terminates process by PID.
93. **`GetProcessLogs`**: Arguments: `pid: Int`. Reads stdout/stderr buffer of running child process.
94. **`RunApplication`**: Launches active project build executable.
95. **`ReadEnvironmentVariables`**: Retrieves active process environment variables.
96. **`UpdateEnvironmentVariables`**: Arguments: `variables: [String: String]`. Updates `.env` or project scheme.
97. **`HTTPRequest`**: Arguments: `url: String`, `method: String`, `headers: [String: String]?`, `body: String?`. Sends HTTP request.
98. **`FetchURL`**: Arguments: `url: String`. Fetches URL content as string/markdown.
99. **`WebSearch`**: Arguments: `query: String`. Performs live web search.
100. **`OpenBrowser`**: Arguments: `url: String`. Opens URL in default system browser.
101. **`BrowserAutomation`**: Arguments: `action: String`, `url: String?`, `selector: String?`. Headless browser automation.
102. **`NetworkInspector`**: Returns recent HTTP network traffic captured by IDE proxy.

#### Diagnostics, Profiling & Accessibility (8 Tools)
103. **`CrashAnalyzer`**: Arguments: `crashReportPath: String`. Parses crash dump exception codes and stack frames.
104. **`SymbolicateCrashLogs`**: Arguments: `crashLogPath: String`, `dsymPath: String`. Symbolicates addresses.
105. **`PerformanceProfiler`**: Measures CPU and memory metrics over a time duration.
106. **`MemoryProfiler`**: Analyzes process heap allocations and checks for retain cycles.
107. **`UIInspector`**: Dumps view hierarchy of active preview or simulator window.
108. **`AccessibilityInspector`**: Evaluates active UI hierarchy against WCAG contrast and accessibility traits.
109. **`LicenseScan`**: Scans codebase dependencies against SPDX open-source license definitions.
110. **`SecurityScan`**: Scans files for hardcoded secrets, plain-text API keys, and unsafe functions.

#### Code Generation & Documentation (6 Tools)
111. **`GenerateCode`**: Arguments: `prompt: String`, `contextFiles: [String]?`. Synthesizes code snippets.
112. **`ExplainCode`**: Arguments: `filePath: String`, `startLine: Int?`, `endLine: Int?`. Explains code functionality.
113. **`RefactorCode`**: Arguments: `filePath: String`, `refactoringType: String`. Applies structural refactoring.
114. **`ReviewCode`**: Arguments: `filePath: String`. Returns code quality review.
115. **`GenerateDocumentation`**: Arguments: `filePath: String`. Produces DocC / docstrings for all exported symbols.
116. **`GenerateComments`**: Arguments: `filePath: String`, `lineRange: [Int]`. Adds explanatory comments.

#### GitHub Issues & PRs (7 Tools)
117. **`ReadIssues`**: Arguments: `state: String?` (open/closed), `labels: [String]?`. Lists GitHub issues.
118. **`CreateIssue`**: Arguments: `title: String`, `body: String`, `labels: [String]?`. Opens GitHub issue.
119. **`UpdateIssue`**: Arguments: `issueNumber: Int`, `state: String?`, `comment: String?`. Updates issue.
120. **`SearchIssues`**: Arguments: `query: String`. Searches issues using GitHub search API.
121. **`ReadPullRequest`**: Arguments: `prNumber: Int`. Retrieves PR diff, checks, and comments.
122. **`CreatePullRequest`**: Arguments: `title: String`, `body: String`, `base: String`, `head: String`. Creates PR.
123. **`ReviewPullRequest`**: Arguments: `prNumber: Int`, `event: String` (APPROVE/REQUEST_CHANGES), `body: String`. Submits PR review.

#### Data Parsing (4 Tools)
124. **`ParseJSON`**: Arguments: `jsonString: String`. Validates and formats JSON.
125. **`ParseXML`**: Arguments: `xmlString: String`. Validates and traverses XML DOM.
126. **`ParseYAML`**: Arguments: `yamlString: String`. Parses YAML into JSON dictionary.
127. **`ParseMarkdown`**: Arguments: `markdown: String`. Parses Markdown AST.

#### Agent State, Memory & Task Management (14 Tools)
128. **`TaskPlanner`**: Arguments: `goal: String`. Generates structured multi-phase execution roadmap.
129. **`ChecklistPlan`**: Arguments: `action: String` (get/update/complete), `itemIndex: Int?`. Manages checklist.
130. **`ProgressTracker`**: Arguments: `percentage: Double`, `phase: String`. Updates agent progress bar.
131. **`AskUser`**: Arguments: `question: String`, `options: [String]?`. Prompts user with question or choices.
132. **`QuestionHandler`**: Processes user responses to prompt choices.
133. **`AIContextMemory`**: Arguments: `action: String` (store/retrieve/clear), `key: String`, `value: String?`. Key-value memory.
134. **`CheckpointCreator`**: Arguments: `checkpointName: String`. Creates rollback snapshot of project.
135. **`RollbackChanges`**: Arguments: `checkpointName: String`. Restores project state to checkpoint.
136. **`TodoManager`**: Arguments: `action: String` (scan/add/remove), `todoText: String?`. Scans/manages TODO comments.
137. **`ProjectAudit`**: Runs complete audit of code structure, dependencies, and compilation.
138. **`ProjectIndexingTool`**: Triggers full-workspace symbol and file re-indexing.
139. **`ManageSecrets`**: Arguments: `key: String`, `value: String`. Securely stores secret in Keychain.
140. **`TakeScreenshot`**: Arguments: `target: String` (simulator/window). Captures visual screenshot.
141. **`ListTools`**: Returns complete catalog of tools and JSON parameter schemas.

### 4.2 The 63 Assist Engine Tools (`Backend/Assist/Tools`)
A specialized internal toolset operating directly within the Assist execution loop:
1. `AssistReadFileTool`: Cached file reader.
2. `AssistWriteFileTool`: Atomic file write with disk sync check.
3. `AssistAppendFileTool`: Appends lines to files safely.
4. `AssistInsertCodeBlockTool`: Inserts code block relative to anchor pattern.
5. `AssistReplaceInFileTool`: Exact-match string substitution.
6. `AssistMultiFileEditTool`: Executes coordinated multi-file edits in an atomic transaction.
7. `AssistDeleteFileTool`: Deletes file with snapshot creation.
8. `AssistCopyFileTool`: Duplicates file within project groups.
9. `AssistMoveFileTool`: Moves file and updates target configuration references.
10. `AssistRenameFileTool`: Renames file and updates import statements.
11. `AssistCreateFileTool`: Scaffolds new file with standardized header comment.
12. `AssistCreateDirectoryTool`: Creates folder structure.
13. `AssistDeleteDirectoryTool`: Safely removes directories.
14. `AssistReadDirectoryTool`: Reads directory contents with glob filters.
15. `AssistTreeViewTool`: ASCII directory tree generator.
16. `AssistSearchTool`: Fast indexed text search.
17. `AssistRegexSearchTool`: Regular expression pattern finder.
18. `AssistSymbolSearchTool`: Queries AST symbol index for declarations.
19. `AssistDiffTool`: Generates contextual diffs of recent edits.
20. `AssistPatchApplicationEngine`: AST-aware patch applicator.
21. `AssistUndoTool`: Reverts the last agent action.
22. `AssistSnapshotProjectTool`: Creates a full workspace snapshot.
23. `AssistRestoreSnapshotTool`: Restores workspace to snapshot state.
24. `AssistValidateChangesTool`: Validates modifications against compile rules.
25. `AssistFormatCodeTool`: Normalizes formatting on modified files.
26. `AssistLintTool`: Runs linter on modified files.
27. `AssistAutoFixErrorsTool`: Automatically resolves compiler warnings/errors.
28. `AssistBuildProjectTool`: Triggers background compilation and captures diagnostics.
29. `AssistTestRunnerTool`: Runs test cases relevant to modified files.
30. `AssistTaskRunnerTool`: Runs configured project build tasks.
31. `AssistEnvironmentInfoTool`: Retrieves system information (macOS, Xcode, Swift, CPU architecture).
32. `AssistExplainCodeTool`: Generates technical explanations for code blocks.
33. `AssistRefactorTool`: Executes scoped refactorings.
34. `AssistGenerateFileTool`: Scaffolds complete source files from functional specs.
35. `AssistGenerateTestsTool`: Creates unit tests for modified source files.
36. `AssistPlanTaskTool`: Breaks down complex prompts into subtasks.
37. `AssistBreakdownTaskTool`: Generates child tasks for long-running workflows.
38. `AssistCodeSummaryTool`: Summarizes file architecture and responsibilities.
39. `AssistComplexityAnalysisTool`: Measures cyclomatic and cognitive complexity.
40. `AssistDependencyGraphTool`: Maps imports and dependencies between workspace files.
41. `AssistLogCaptureTool`: Captures system, build, and debug console logs.
42. `AssistStoreMemoryTool`: Persists key facts into the agent's long-term memory store.
43. `AssistRetrieveMemoryTool`: Queries the agent's persistent memory store.
44. `AssistClearMemoryTool`: Clears or invalidates stale agent memory entries.
45. `AssistContextSnapshotTool`: Captures active workspace state into context.
46. `AssistChangeLogTool`: Generates user-facing changelog summaries.
47. `AssistVersionControlOperator`: High-level Git operations coordinator.
48. `AssistProjectMutationController`: Orchestrates project-level manifest mutations.
49. `AssistAutomatedRepairEngine`: Self-healing engine that detects, investigates, and repairs build breakages.
50. `AssistAutonomousReviewEngine`: Reviews agent-generated code against quality gates.
51. `AssistCodeMutationEngine`: Applies code transformations.
52. `AssistCompilerDiagnosticsEngine`: Evaluates compiler errors and maps them to fixes.
53. `AssistContextPersistenceStore`: Persists session context across restarts.
54. `AssistDependencyResolutionEngine`: Resolves missing packages and imports.
55. `AssistExternalResourceGateway`: Interfaces with web resources and remote APIs.
56. `AssistRuntimeDiagnosticsEngine`: Monitors running app crashes and logs.
57. `AssistSemanticQueryEngine`: Semantic search interface for the codebase.
58. `AssistSourceGraphBuilder`: Builds whole-codebase AST symbol reference graphs.
59. `AssistToolingSupport`: Dynamic tool registry and dispatcher.
60. `AssistTool`: Base protocol defining tool schema, execution, and validation.
61. `CodeReview`: Standalone code review evaluation tool.
62. `UseMCP`: Dispatches tool requests to connected Model Context Protocol servers.
63. `UseTermFunction`: Executes shell functions with interactive terminal approval.

---

## 5. Agent Skills System & Model Context Protocol (MCP) Host

### 5.1 The Agent Skills Framework

#### Skill Package Architecture & Frontmatter Schema
Each skill is organized as an isolated bundle containing a `SKILL.md` markdown file with strict YAML frontmatter parsed by `SkillsParser`:
```swift
public struct SkillScheme: Codable, Sendable, Hashable {
    public let name: String
    public let summary: String
    public let version: String
    public let author: String
    public let tags: [String]
    public let recommendedTools: [String]
    public let guidance: [String]
}
```

#### Skill Discovery & Prompt Injection
At session launch, `AssistSkillsCheck.shared.discoverSkills()` audits both the global customizations directory (`~/.config/editor/skills/`) and the active workspace directory (`.skills/`). When discovered, skills are formatted into an active system block injected directly into the LLM context:
```markdown
# DISCOVERED SYSTEM SKILLS
- Name: swift-concurrency-audit
  Description: Audits Swift code for Sendable violations and data races
  Recommended Tools: RunTypeChecker, CodeAnalysisTool, DetectBugs
  Guidance: Always verify actor isolation on mutable classes. Ensure cross-actor closures are @Sendable.
```

---

### 5.2 Model Context Protocol (MCP) Host (`Frameworks/Internal/MCP`)

The editor embeds a complete, native Swift implementation of the **Model Context Protocol (MCP)** specification (2024-11-05 revision).

#### 1. JSON-RPC 2.0 Messaging Wire Formats
Defined in `MCPClient.swift`:
```swift
public enum JSONRPCID: Codable, Sendable, Hashable {
    case integer(Int)
    case string(String)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSONRPC ID")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        case .null: try container.encodeNil()
        }
    }

    public var integerValue: Int? {
        switch self {
        case .integer(let val): return val
        case .string(let val): return Int(val)
        case .null: return nil
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: JSONValue?

    public init(id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: JSONValue?
    public let error: JSONRPCError?
}

public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?
}
```

#### 2. Transport Session Protocol
```swift
public protocol MCPTransportSession: Sendable {
    func connect(messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async throws
    func send(request: JSONRPCRequest) async throws -> JSONRPCResponse
    func send(notification: JSONRPCNotification) async throws
    func disconnect()
}
```

#### 3. Stdio Transport Engine (`StdioTransportSession`)
The `StdioTransportSession` launches an external process (e.g. Node.js or Python CLI servers) and communicates via standard I/O pipes:
```swift
public final class StdioTransportSession: MCPTransportSession, @unchecked Sendable {
    private let server: MCPServer
    private let activeProcess = OSAllocatedUnfairLock<Process?>(initialState: nil)
    private let stdioOutputTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
    private let writePipe = OSAllocatedUnfairLock<Pipe?>(initialState: nil)
    private let pendingRequests = OSAllocatedUnfairLock<[Int: CheckedContinuation<JSONRPCResponse, Error>]>(initialState: [:])

    public func connect(messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async throws {
        guard let exePath = server.executablePath, !exePath.isEmpty else {
            throw MCPError.invalidConfiguration("Executable path is missing for stdio transport")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = server.launchArguments ?? []

        // Merge system environment with configured variables
        var fullEnv = ProcessInfo.processInfo.environment
        if let envVars = server.envVariables {
            for (k, v) in envVars { fullEnv[k] = v }
        }
        process.environment = fullEnv

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        activeProcess.withLock { $0 = process }
        writePipe.withLock { $0 = inPipe }

        // Read stdout line-by-line asynchronously
        let outputHandle = outPipe.fileHandleForReading
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                for try await line in outputHandle.bytes.lines {
                    guard let data = line.data(using: .utf8) else { continue }
                    if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
                        if let rpcID = response.id, let id = rpcID.integerValue {
                            let continuation = self.pendingRequests.withLock { $0.removeValue(forKey: id) }
                            continuation?.resume(returning: response)
                        } else {
                            messageHandler(response)
                        }
                    }
                }
            } catch {
                logger.error("Stdio stream closed: \(error.localizedDescription)")
            }
        }
        stdioOutputTask.withLock { $0 = task }
    }

    public func send(request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let writeHandle = writePipe.withLock({ $0?.fileHandleForWriting }) else {
            throw MCPError.connectionFailed("Stdio pipe unavailable.")
        }
        let data = try JSONEncoder().encode(request)
        guard var lineData = String(data: data, encoding: .utf8) else {
            throw MCPError.decodingFailed("Failed to encode request payload.")
        }
        lineData += "\n"

        guard let reqID = request.id?.integerValue else {
            throw MCPError.requestValidationFailed("Request missing integer ID")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.withLock { $0[reqID] = continuation }
            do {
                try writeHandle.write(contentsOf: lineData.data(using: .utf8)!)
            } catch {
                pendingRequests.withLock { _ = $0.removeValue(forKey: reqID) }
                continuation.resume(throwing: error)
            }
        }
    }
}
```

#### 4. The MCP Handshake Protocol Sequence
When establishing a connection with any MCP server:
```
IDE (Client)                                          MCP Server
    │                                                      │
    ├───────── 1. initialize Request (JSON-RPC) ──────────>│
    │   {                                                  │
    │     "protocolVersion": "2024-11-05",                 │
    │     "capabilities": {                                │
    │       "roots": { "listChanged": true },              │
    │       "sampling": {}                                 │
    │     },                                               │
    │     "clientInfo": {                                  │
    │       "name": "UniversalIDE",                        │
    │       "version": "1.0.0"                             │
    │     }                                                │
    │   }                                                  │
    │                                                      │
    │<──────── 2. initialize Response ─────────────────────┤
    │   {                                                  │
    │     "protocolVersion": "2024-11-05",                 │
    │     "capabilities": { "tools": {}, "resources": {} },│
    │     "serverInfo": { "name": "...", "version": "..." }│
    │   }                                                  │
    │                                                      │
    ├───────── 3. notifications/initialized ──────────────>│
    │   { "method": "notifications/initialized" }          │
    │                                                      │
    ├───────── 4. tools/list Request ─────────────────────>│
    │<──────── 5. tools/list Response (Tool Catalog) ──────┤
    │                                                      │
    ├───────── 6. resources/list Request ─────────────────>│
    │<──────── 7. resources/list Response (Data Sources) ──┤
```

#### 5. Dynamic Tool Discovery & Schema Transformation
When `tools/list` returns, each `MCPTool` item is registered into `MCPServer.discoveredTools`:
```swift
public struct MCPTool: Codable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchema: MCPToolSchema
}

public struct MCPToolSchema: Codable, Sendable, Hashable {
    public let type: String
    public let properties: [String: MCPToolProperty]?
    public let required: [String]?
}

public struct MCPToolProperty: Codable, Sendable, Hashable {
    public let type: String
    public let description: String?
    public let `enum`: [String]?
}
```
The internal schema transformer maps these properties directly into the editor's native `JSONSchema` specifications, making them immediately visible to the LLM during prompt assembly.

#### 6. Tool Execution Bridge (`UseMCP.swift`)
The AI agent interacts with external MCP servers through the unified `use_mcp` tool:
```swift
@MainActor
public final class UseMCP: AssistTool {
    public let id = "use_mcp"
    public let name = "Execute MCP Tool"
    public let description = "Executes a tool on a connected Model Context Protocol (MCP) server."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "serverName": JSONSchema(type: "string", description: "The name of the connected MCP server."),
                "toolName":   JSONSchema(type: "string", description: "The name of the target tool."),
                "arguments":  JSONSchema(type: "string", description: "JSON-serialized object string of arguments.")
            ],
            required: ["serverName", "toolName", "arguments"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let serverName = input["serverName"] as? String,
              let toolName = input["toolName"] as? String,
              let argsString = input["arguments"] as? String else {
            return .failure("Missing required arguments (serverName, toolName, arguments).")
        }

        let manager = MCPServerManager.shared
        guard let server = manager.servers.first(where: { 
            $0.displayName.lowercased() == serverName.lowercased() || $0.id.uuidString == serverName 
        }) else {
            return .failure("MCP Server '\(serverName)' not configured.")
        }

        guard server.status == .connected else {
            return .failure("MCP Server '\(server.displayName)' is disconnected.")
        }

        let data = argsString.data(using: .utf8) ?? Data()
        guard let decodedArgs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Arguments must be a valid JSON-serialized object string.")
        }

        // Send tools/call JSON-RPC request to server
        let client = manager.client(for: server.id)
        let response = try await client.callTool(name: toolName, arguments: decodedArgs)
        return .success(response.contentSummary)
    }
}
```

#### 7. Server Manager & Keychain Persistence (`MCPServerManager.swift`)
- **Persistence Store**: Server records (`MCPServer`) are saved to `~/Library/Application Support/UniversalIDE/mcp_servers.json`.
- **Sensitive Credentials**: Authentication tokens, OAuth bearer tokens, and sensitive environment keys are stored in the macOS Keychain under service `com.editor.mcp.<serverID>`.
- **Status Observer**: Exposes observable status flags (`.disconnected`, `.connecting`, `.connected`, `.failed`) for UI connection status indicators and diagnostic logs.

---

## 6. AI Model Infrastructure (Local, Remote, On-Device)

### 6.1 Local Apple Silicon Runner (MLX Integration)
- **`MLXIntegration` & `MLXModelContainer`**:
  - Leverages Apple Silicon unified memory and Neural Engine via MLX.
  - Loads GGUF and MLX quantized weights (4-bit, 8-bit).
  - Implements token streaming via `AsyncThrowingStream<String, Error>`.
- **`OfflineModelDownloader`**:
  - Connects to Hugging Face API to query and download models (Llama 3, Qwen 2.5, DeepSeek Coder).
  - Manages chunked, resumable downloads to `~/Documents/Models/`.
- **`DeviceCapabilityAnalyzer`**:
  - Queries physical RAM via `sysctl hw.memsize`.
  - Recommends model parameters:
    - $\le 8\text{ GB}$: 3B parameters (4-bit).
    - $16\text{ GB}$: 7B–8B parameters (4-bit).
    - $\ge 32\text{ GB}$: 14B–32B parameters.

### 6.2 Apple Intelligence & CoreML Service
- **`AppleIntelligenceService`**:
  - Leverages macOS system frameworks (`NaturalLanguage`, `CoreML`, `Translation`).
  - Zero-token-cost local operations: Text summarization, code rewrite, docstring generation.
- **`CodeSuggestionsML`**:
  - Local CoreML neural network delivering offline inline completions under 50ms latency.

### 6.3 Cloud Providers & Streaming
- **`OpenRouterService`**:
  - SSE streaming connection to OpenRouter API (`https://openrouter.ai/api/v1/chat/completions`).
  - Automatic fallback cascade: If primary model times out or returns 429, routes request to secondary configured model.
  - Computes prompt and completion token counts to maintain usage statistics.
- **`CodexBridgeManager`**:
  - Interfaces with a local Node.js bridge service running on `localhost:3003` for OpenAI Codex compatibility.

---

## 7. Build Systems, Compilers & Deployment Pipeline

### 7.1 Swift Package Manager Engine
- **`SwiftPackageBuildService`**:
  - Executes `swift build --triple <target>` and `swift test`.
  - Parses `Package.resolved` to audit dependency pins.

### 7.2 Xcode CLI Build Engine
- **`XcodeBuildService` & `XcodeBuildManager`**:
  - Discovers installed Xcode developer tools via `xcode-select -p`.
  - Invokes `xcodebuild`:
    ```bash
    xcodebuild -scheme <Scheme> -workspace <Workspace> -configuration Debug \
      -destination 'generic/platform=iOS' SYMROOT=<BuildDir> build
    ```
- **Diagnostic Regex Parsers**:
  - Clang / Swiftc Compiler Diagnostics:
    `^(/[^:]+):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$`
    Captures: File path, line number, column offset, severity, message.
  - Linker Diagnostics:
    `^Undefined symbols for architecture\s+(\w+):\s*"([^"]+)",\s*referenced from:`
    Captures: Target architecture, missing symbol name.

### 7.3 IPA Packaging & Code Signing
- **`IPABuildService`**:
  - Step 1: Compiles `.xcarchive` using `xcodebuild archive`.
  - Step 2: Generates `ExportOptions.plist` specifying signing method (`app-store`, `ad-hoc`, `enterprise`, `development`).
  - Step 3: Invokes `xcodebuild -exportArchive -archivePath <Path> -exportPath <OutputDir> -exportOptionsPlist <PlistPath>`.
  - Step 4: Validates that `.ipa` package exists and verifies signature using `codesign --verify --deep --strict`.

### 7.4 Cloud Web Deployments
- **`VercelManager`**: Prepares git commits, bundles static assets, and triggers Vercel deployments via REST API (`POST /v13/deployments`).
- **`NetlifyManager`**: Deploys compiled web output directories to Netlify via `POST /api/v1/sites/{site_id}/deploys`.
- **`GitHubPagesManager`**: Automates pushing production builds to the `gh-pages` branch of the connected repository.

---

## 8. Physical Device Deployment & SwiftCode Connect Protocol

### 8.1 DeviceConnectKit (Physical Apple Device Management)
- **Device Discovery (`DeviceDiscovery`)**:
  - Detects physical iOS, iPadOS, watchOS, and tvOS devices connected via USB or paired over Wi-Fi.
  - Uses `devicectl` (macOS 14+) or `mobiledevice` subsystem.
- **Deployment Pipeline**:
  - Mounts Developer Disk Images (DDI) matching the connected device's OS version.
  - Installs signed `.app` bundles via `devicectl device install app`.
  - Launches installed apps via `devicectl device process launch`.
- **Real-Time Console Stream (`DeviceConnectConsole`)**:
  - Streams live device sysdiagnose logs filtered by subsystem and process ID.

### 8.2 SwiftCode Connect Interoperability Protocol (V1 Specification)
Enables a mobile companion app (iPad/iPhone) to act as an authoritative remote controller for the desktop IDE over Wi-Fi.

#### Protocol Service Discovery
- **Bonjour Service Type**: `_swiftcodeconnect._tcp`
- **Default Port**: Dynamically allocated (fallback: TCP 8088 / WebSocket 8089)
- **TXT Record**: `txtvers=1`, `proto=1`, `macName=<Hostname>`, `appVers=1.0`

#### Security Handshake & Trust Store
1. Mobile discovers host via Bonjour.
2. Mobile sends `pairing_request` containing device ID, device model, and user name.
3. Desktop displays a native prompt showing a 6-digit PIN.
4. Mobile enters matching PIN.
5. Host issues cryptographic session token saved in System Keychain (`com.editor.connect.truststore`).

#### Envelope Framing
All messages over TCP framing or WebSockets use standard JSON:
```json
{
  "protocolVersion": 1,
  "messageID": "UUID",
  "correlationID": "UUID",
  "type": "string",
  "timestamp": "ISO8601",
  "payload": {}
}
```

#### Message Catalog & Operations
- `build_request` / `cancel_build_request`: Initiates or cancels desktop build.
- `build_progress` / `build_diagnostic` / `build_completed`: Streams compiler events to mobile.
- `test_request` / `test_progress` / `test_completed`: Remote test execution.
- `git_status_request` / `git_status_response`: Retrieves repository status.
- `file_list_request` / `file_read_request` / `file_write_request`: Remote file inspection and editing.
- `terminal_execute_request` / `terminal_output`: Remote shell commands.
- `terminal_approval_required`: Dispatches approval challenge when high-risk commands execute on Mac.
- `assist_query_request` / `assist_response`: Routes AI queries to execute authoritatively on desktop.

#### Granular Permissions Matrix
Each paired companion device is assigned explicit permissions:
`project.read`, `git.read`, `build.execute`, `tests.execute`, `logs.read`, `terminal.execute`, `files.read`, `files.write`, `assist.use`.

---

## 9. SwiftUI Live Preview & Simulation Engine

### 9.1 Dynamic SwiftUI Preview Engine
- **`PreviewRuntimeCompiler`**:
  - Compiles active SwiftUI file into a dynamic library:
    ```bash
    swiftc -emit-library -dynamiclib -o <TempDylibPath> <SourceFilePath> \
      -I <BuildProductsDir> -L <BuildProductsDir>
    ```
  - Uses `dlopen` to load the compiled dylib into the preview runner process.
  - Dynamically extracts view type conforming to `SwiftUI.View` and mounts it in an isolated preview host window.
- **`PreviewLiveReloadManager`**:
  - Watches file save events.
  - Triggers debounced recompilation (under 300ms) and hot-swaps the active view without restarting the host IDE.
- **Preview Host Controls**:
  - Color scheme toggle (Light / Dark).
  - Orientation toggle (Portrait / Landscape).
  - Dynamic Type size stepper.
  - Localization environment injection.

### 9.2 Apple Simulator Subsystem (`simctl`)
- **Lifecycle Management**:
  - Discovers runtimes and devices via `xcrun simctl list -j`.
  - Commands: `boot`, `shutdown`, `erase`, `clone`, `create`, `delete`.
- **Interactive Simulator Tools**:
  - Install & Launch: `xcrun simctl install <UDID> <AppPath>` and `xcrun simctl launch <UDID> <BundleID>`.
  - APNS Push Notification Injection: `xcrun simctl push <UDID> <BundleID> <Payload.apns>`.
  - Location Simulation: `xcrun simctl location <UDID> set <Latitude>,<Longitude>`.
  - Status Bar Overrides: `xcrun simctl status_bar <UDID> override --time "9:41" --batteryState charged --batteryLevel 100`.
  - Media Capture: `xcrun simctl io <UDID> screenshot <OutputPath.png>` and `xcrun simctl io <UDID> recordVideo <OutputPath.mp4>`.

---

## 10. Source Control, Git Engine & 3-Way Conflict Resolver

### 10.1 Porcelain Git Engine
- **`GitService`**: Runs Git commands using `--porcelain=v2` for deterministic parsing.
- **Status Parsing Model**:
  - Parses status lines `1 <XY> sub <mH> <mI> <mW> <hH> <hI> <path>` to extract staged (`X`) and unstaged (`Y`) states (`M` modified, `A` added, `D` deleted, `R` renamed).
- **Hunk Staging Engine**:
  - Generates patch hunks from `git diff -U3`.
  - Applies single hunks to the index via `git apply --cached -`.

### 10.2 3-Way Visual Merge Conflict Resolver
- **Conflict Parser**:
  - Scans files containing Git conflict delimiters:
    ```
    <<<<<<< HEAD (Current Change)
    Original lines
    =======
    Incoming lines
    >>>>>>> branch-name (Incoming Change)
    ```
- **Resolver Engine (`GitConflictResolverView`)**:
  - Structures conflicts into an array of `ConflictHunk(id, currentText, incomingText, range)`.
  - Provides deterministic resolution actions:
    - `Accept Current`: Replaces hunk with `currentText`.
    - `Accept Incoming`: Replaces hunk with `incomingText`.
    - `Accept Both`: Replaces hunk with `currentText + "\n" + incomingText`.
    - `Custom Edit`: Allows direct buffer editing.
  - Automatically clears conflict state when all conflict markers in the file are eliminated.

### 10.3 GitHub Ecosystem Integration
- **`GitHubAPI`**:
  - REST client with personal access token / OAuth2 authentication.
  - Pull Requests: List, create, review, merge (Squash, Rebase, Merge commit).
  - Issues: List with label and milestone filtering, create, update, comment.
  - Gists (`GitHubGistService`): Create public/secret gists from editor selections, list revisions, copy raw URLs.

### 10.4 Developer Workflows (Visual CI/CD Builder)
- **`WorkflowManager`**:
  - Visual builder for multi-step automation pipelines.
  - Step models: Shell command, Lint pass, Build scheme, Run test target, Deployment trigger.
  - Supports environment variable injection (`${{ env.KEY }}`).
  - Export: Automatically translates visual workflows into valid GitHub Actions `.github/workflows/ci.yml` files.

---

## 11. Visual UI Builder & Artboard Canvas

### 11.1 Artboard Canvas Architecture
- **Infinite Artboard System**:
  - Multi-device canvas supporting side-by-side frames (e.g. iPhone 15 Pro, iPad Air, Mac Desktop).
  - Pan, zoom (10% to 400%), and snap-to-grid alignment guides.
- **Component Palette**:
  - Visual library of UI primitives (Text, Image, Button, TextField, Toggle, Slider, Picker).
  - Container primitives (`VStack`, `HStack`, `ZStack`, `LazyVGrid`, `ScrollView`, `List`).
  - Shape primitives (`Rectangle`, `RoundedRectangle`, `Circle`, `Capsule`).

### 11.2 Visual Styling & Layout Inspector
- **Interactive Attribute Controls**:
  - Frame dimensions (width, height, min/ideal/max constraints).
  - Padding (all edges, horizontal, vertical, custom per edge).
  - Colors, gradients (linear/radial), and opacity.
  - Corner radius, borders, and shadows (radius, x, y, color).
  - Typography: Font family, weight, size, line spacing, text alignment.

### 11.3 Visual Animations & Bindings Panels
- **Animations Panel**: Interactive configuration of curves (`linear`, `easeInOut`), spring physics (`mass`, `stiffness`, `damping`), and keyframes.
- **Bindings Panel**: Connects UI component values directly to ViewModel `@Published` / `@Observable` properties.

### 11.4 Bidirectional Code-for-Artboard Generator (`CodeForArtboard`)
- **AST Sync Pipeline**:
  - Visual Canvas $\to$ Code: Dragging a component or updating a property serializes directly into valid SwiftUI code, updating the source buffer.
  - Code $\to$ Visual Canvas: Editing SwiftUI code re-parses the view AST and updates visual elements on the canvas in real time.
- **Full App Runner (`RunFullAppView`)**: Launches the view hierarchy in an interactive window with full gesture and state interactivity.

---

## 12. Database Explorer & Data Studio

### 12.1 Multi-Engine Driver Support
- **SQLite Engine**: Connects to local `.sqlite`, `.db`, and Core Data / SwiftData persistent stores.
- **Supabase / PostgreSQL Engine (`SupabaseService`)**: Connects to remote PostgreSQL instances over TCP or Supabase REST APIs.

### 12.2 Schema Introspection
- Executes standard introspection queries:
  - SQLite: `PRAGMA table_info(<tableName>)`, `PRAGMA foreign_key_list(<tableName>)`, `PRAGMA index_list(<tableName>)`.
  - PostgreSQL: Queries `information_schema.tables`, `information_schema.columns`, and `information_schema.table_constraints`.
- Generates visual entity-relationship diagrams (ERD) mapping tables, primary keys, and foreign keys.

### 12.3 Interactive Data Grid
- **Paged Table View**: Displays table rows with customizable page size (25–500 rows).
- **Filtering & Sorting**: Multi-column ascending/descending sorts and SQL `WHERE` filter clauses.
- **Inline Editing**: Double-click cell editing with visual dirty-state indicators. Changes are held in a mutation queue until the user clicks "Commit Changes" (wrapped in a database transaction) or "Rollback".
- **Row Operations**: Add new record, duplicate record, delete selected records.

### 12.4 SQL Console & Text-to-SQL AI
- **SQL Editor**: Query editor with syntax highlighting, autocomplete for tables and columns, and query execution timer.
- **`DatabaseAIService`**: Natural language to SQL prompt generator. Translates plain English instructions into safe, parameterized SQL queries with performance analysis.

### 12.5 Migrations & Import/Export
- **Migration Engine**: Generates timestamped migration files (`V{timestamp}__{description}.sql`) with forward (`UP`) and backward (`DOWN`) sections.
- **Import / Export**: Exports data to CSV, JSON, or SQL dump scripts; imports CSV files with automatic data type inference.

---

## 13. StoreKit Workspace & In-App Purchase Simulation

### 13.1 `.storekit` Configuration Editor
- Reads, parses, and writes Apple `.storekit` configuration files (`StoreKitParser`, `StoreKitEncoder`).
- **Product Types**:
  - Consumable In-App Purchases.
  - Non-Consumable In-App Purchases.
  - Non-Renewing Subscriptions.
  - Auto-Renewable Subscriptions.
- **Subscription Hierarchy**:
  - Subscription groups with ranking levels.
  - Durations: 1 Week, 1 Month, 2 Months, 3 Months, 6 Months, 1 Year.
  - Introductory Offers: Free Trial, Pay as You Go, Pay Up Front.
  - Promotional Offers with custom offer codes.

### 13.2 Local Transaction Simulation Engine
- **`StoreKitSimulationService`**:
  - Intercepts StoreKit framework transactions in local preview and simulator runs.
  - Simulates purchase approvals, user cancellations, and ask-to-buy flows.
  - Accelerated renewal testing: Simulates subscription renewals every 10 seconds.
  - Simulates edge-case lifecycles: Billing retry states, grace periods, subscription expirations, user refunds, and family sharing revocations.
- **Receipt & Entitlement Inspector**: Decodes and inspects simulated JWS receipt payloads and active entitlements.

---

## 14. Personal Documentation & Architecture Knowledge Base

### 14.1 Structured Architecture & Planning Editors
- **Architecture Editor**: Supports C4 architecture models (Context, Containers, Components, Code) and Architecture Decision Records (ADR).
- **Feature Planning Editor**: User story mapping, acceptance criteria tracking, and edge-case documentation.
- **Release Checklist Editor**: Interactive launch checklists covering compliance, asset sizes, certificates, and privacy manifests.
- **API Documentation Editor**: OpenAPI-compatible documentation templates for endpoints, headers, payloads, and error responses.

### 14.2 Developer Journal & Internal Wiki
- **`JournalManager`**: Calendar-indexed daily work log tracking tasks completed, blockers encountered, and active git commits.
- **`WikiPage` System**:
  - Bidirectional wiki link syntax: Typing `[[Page Name]]` creates automatic hyperlinks between documentation pages.
  - Backlinks Inspector: Displays all documents referencing the active page.
- **`DocumentVersion` History**: File-level change tracking allowing side-by-side comparison of documentation revisions.
- **`DocumentationAnalyzer`**: Scans codebase and automatically generates DocC documentation for undocumented APIs.

---

## 15. Developer Operations, Diagnostics & Telemetry

### 15.1 Operations Command Center (`Views/Utilities/Operations`)
- **`SCTimelineView`**: Real-time chronological telemetry event stream logging file saves, git commits, build passes, agent turns, and tool outputs.
- **`BuildHistoryView`**: Historical archive of previous builds with duration graphs, compiler warning counts, and output artifacts.
- **`SCLogsView` & `UnifiedLogger`**: Central log viewer aggregating system logs, app stdout/stderr, and agent debug traces with multi-criteria filtering.

### 15.2 Diagnostics & Performance Suite (`Views/Developer`)
- **Realtime Metrics Dashboard**: Real-time graphs for CPU utilization, RAM usage, disk I/O, and network activity.
- **Memory Leak Detector**: Heap allocation tracking and retain cycle graph analysis.
- **Thread Inspector**: Active threads, GCD dispatch queues, and stack traces with deadlock detection warnings.
- **Crash Log Analyzer & Symbolicator**: Parses `.ips` and `.crash` reports, invoking `atos` with project dSYMs to symbolicate stack frames into file and line locations.
- **Binary Tools & Mach-O Inspector**:
  - Analyzes compiled binaries using `nm`, `otool`, and `lipo`.
  - Displays binary slice architectures (arm64, x86_64), linked dynamic libraries, and codesigning entitlements.
- **Network & API Inspector**: Intercepts HTTP/HTTPS traffic, displaying request/response headers, status codes, payload bodies, and timing waterfalls. Includes an integrated mock response server.
- **WebView Debugger**: WebKit web inspector providing DOM inspection, console logging, and network traffic for embedded web views.
- **Feature Flags Manager**: Interface to toggle development feature flags, bypass paywalls, and simulate API failures.

---

## 16. Built-In Developer Utilities Suite (156 Tools)

The editor embeds 156 offline developer tools (`Views/Dev Tools`). Every utility must be implemented with input, output, and transformation logic:

### 16.1 Code & Schema Generators (15 Tools)
1. `JSONToSwiftView`: JSON $\to$ Swift `Codable` structs with optional `CodingKeys` and default initializers.
2. `JSONToTSView`: JSON $\to$ TypeScript interfaces / type aliases.
3. `JSONToPythonView`: JSON $\to$ Python Pydantic models / dataclasses.
4. `JSONToGoView`: JSON $\to$ Go struct definitions with `json:"..."` tags.
5. `JSONToRustView`: JSON $\to$ Rust structs with `serde::Deserialize, serde::Serialize`.
6. `JSONToKotlinView`: JSON $\to$ Kotlin `@Serializable data class`.
7. `JSONToJavaView`: JSON $\to$ Java POJOs with Jackson / Gson annotations.
8. `JSONToCSharpView`: JSON $\to$ C# records / classes with `System.Text.Json` attributes.
9. `JSONToDartView`: JSON $\to$ Dart classes for Flutter with `fromJson` / `toJson`.
10. `JSONToPHPView`: JSON $\to$ PHP 8 typed classes with constructor promotion.
11. `JSONSchemaGeneratorView`: JSON $\to$ JSON Schema Draft-07 specification.
12. `JSONTypeAnalyzerView`: Interspects JSON payloads, reporting field types, optionality, and null frequencies.
13. `JSONToCSVView`: Flattens nested JSON arrays into tabular CSV format.
14. `JSONToTOMLView`: JSON $\to$ TOML format converter.
15. `QRCodeGeneratorView`: Generates QR code images from text/URLs with selectable error correction levels (L, M, Q, H).

### 16.2 Format Converters & Parsers (18 Tools)
16. `YAMLToJSONView`: Parses YAML to formatted JSON.
17. `JSONFormatterView`: Validates and pretty-prints JSON with configurable indentation (2 or 4 spaces).
18. `YAMLConverterView`: Bi-directional YAML $\leftrightarrow$ JSON converter.
19. `TOMLToJSONView`: Converts TOML configurations to JSON.
20. `CSVToJSONView`: Parses CSV strings into structured JSON objects using header rows.
21. `CSVParserDevToolView`: Validates CSV formatting, column alignment, and delimiter escaping.
22. `XMLToJSONView`: Converts XML DOM trees to JSON representation.
23. `XMLFormatterView`: Pretty-prints and indents XML strings.
24. `SQLFormatterView`: Normalizes and pretty-prints SQL queries.
25. `Base64ConverterView`: Encodes plain text to Base64 and decodes Base64 to text.
26. `Base64FileConverterView`: Encodes binary files to Base64 strings and exports Base64 strings as binary files.
27. `Base64ImageDecoderView`: Decodes Base64 image strings and renders visual preview.
28. `Base32ConverterDevToolView`: RFC 4648 Base32 encoder and decoder.
29. `BinaryConverterView`: Interconverts numbers between Binary, Octal, Decimal, and Hexadecimal.
30. `BinaryHexConverterDevToolView`: Converts raw binary bitstreams to hexadecimal byte sequences.
31. `HexDecimalConverterView`: Fast hex-to-decimal and decimal-to-hex converter.
32. `ASCIIHexConverterDevToolView`: Converts ASCII text strings to space-separated hex byte strings.
33. `EpochConverterDevToolView`: Converts Unix timestamps (seconds, milliseconds) to ISO-8601 and local dates.

### 16.3 Cryptography & Security (15 Tools)
34. `AESEncryptionDevToolView`: Encrypts/decrypts text using AES-128/256 (CBC/GCM) with custom key and IV.
35. `RSAKeyGeneratorView`: Generates public/private RSA key pairs (2048-bit, 4096-bit) in PEM format.
36. `HashGeneratorView`: Computes cryptographic digests: MD5, SHA-1, SHA-256, SHA-384, SHA-512.
37. `HMACGeneratorView`: Computes HMAC signatures using SHA-256/SHA-512 with a secret key.
38. `BcryptHashGeneratorView`: Generates and verifies Bcrypt password hashes with selectable salt rounds (4–14).
39. `JWTDecoderView`: Decodes JSON Web Tokens; inspects headers, claims, expiration dates, and signatures.
40. `PasswordGeneratorView`: Generates cryptographically secure passwords with custom character sets.
41. `PasswordStrengthMeterView`: Calculates entropy bits and cracking time estimates for passwords.
42. `CSRFTokenDevToolView`: Generates cryptographically secure anti-CSRF tokens.
43. `CertificateDecoderView`: Decodes X.509 SSL/TLS certificates, displaying subject, issuer, validity, and SANs.
44. `SSLCheckerView`: Performs SSL/TLS handshake against target hosts to audit cipher suites and expiration.
45. `AppReceiptInspectorDevToolView`: Decodes and validates Apple PKCS #7 App Store receipt payloads.
46. `BiometricAuthSimDevToolView`: Simulates Touch ID / Face ID authentication challenges and error codes.
47. `EncryptionToolDevToolView`: Multi-cipher workspace (DES, 3DES, ChaCha20).
48. `UnixPermissionsCalculatorView`: Interactive chmod calculator converting between numeric octal (e.g. 755) and symbolic notation (`rwxr-xr-x`).

### 16.4 Text & String Utilities (16 Tools)
49. `CaseConverterView`: Converts text between camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE, and Title Case.
50. `TextCaseSwapperView`: Inverts casing (uppercase $\leftrightarrow$ lowercase) across characters.
51. `CharacterEscaperDevToolView`: Escapes strings for Swift, C, Java, JavaScript, and HTML.
52. `JSONStringEscaperView`: Escapes control characters and quotes for embedding inside JSON strings.
53. `StringEscaperView`: Generic string delimiter and escape tool.
54. `StringLengthCounterView`: Counts characters, words, sentences, lines, and UTF-8/UTF-16 byte counts.
55. `TextCounterView`: Detailed readability metrics (Flesch-Kincaid grade, reading time).
56. `TextDeduplicatorView`: Strips duplicate lines from text blocks with case-sensitivity options.
57. `TextLineRemoverView`: Removes empty lines, whitespace-only lines, or lines matching regex filters.
58. `LoremIpsumGeneratorView`: Generates placeholder text by words, sentences, or paragraphs.
59. `UUIDGeneratorView`: Generates UUID v4 (random) and v5 (namespace-based) with case and hyphen toggles.
60. `RandomStringGeneratorView`: Generates random alphanumeric strings with custom exclusions.
61. `BarcodeGeneratorDevToolView`: Generates Code-128, EAN-13, and UPC barcode images.
62. `ASCIIArtGeneratorView`: Converts text banners into ASCII art fonts.
63. `HTMLEntityConverterView`: Encodes characters to HTML entities (`&amp;`, `&lt;`) and decodes them.
64. `URLSlugGeneratorView`: Converts article titles into sanitized, URL-safe slugs.

### 16.5 Regex & Scheduling (4 Tools)
65. `RegexTesterView`: Tests regular expressions against text with real-time match highlighting and capture group extraction.
66. `AdvancedRegexDebuggerDevToolView`: Step-by-step regex backtracking visualizer.
67. `RegexSyntaxCheatsheetView`: Reference guide for regex character classes, quantifiers, and assertions.
68. `CronParserView` / `CronGeneratorView`: Visual crontab expression builder and human-readable schedule parser.

### 16.6 Web & Network Utilities (18 Tools)
69. `APITesterView`: Lightweight HTTP request client with method, headers, query parameters, body, and response viewer.
70. `APIResponseViewerDevToolView`: Formatted JSON/XML response viewer with collapsible trees and header inspection.
71. `CURLGeneratorDevToolView`: Visual request builder outputting ready-to-run `curl` commands.
72. `CURLConverterDevToolView`: Parses `curl` command strings into Swift `URLRequest`, JavaScript `fetch`, and Python `requests`.
73. `DNSLookupView`: Resolves DNS records: A, AAAA, CNAME, MX, TXT, NS, SOA.
74. `WhoisLookupView`: Queries WHOIS registration databases for domains and IP ranges.
75. `IPAddressInfoView`: Inspects IP address geolocation, ISP, ASN, and reverse DNS.
76. `PortScannerView`: Scans TCP ports on local or remote hosts to detect open listening sockets.
77. `PortLookupView`: Searches standard service ports by port number or protocol name.
78. `SubnetCalculatorView`: IPv4/IPv6 CIDR subnet calculator (network address, broadcast address, usable hosts).
79. `NetworkReachabilityDevToolView`: Tests endpoint ping latency, packet loss, and jitter.
80. `WebhookTesterView`: Generates temporary local webhook listeners to capture and inspect incoming payloads.
81. `HTTPStatusView`: Complete reference guide for all HTTP status codes (100–599) with usage recommendations.
82. `HTTPHeaderParserView`: Explains standard and security-related HTTP headers (CORS, CSP, HSTS, Cache-Control).
83. `HTTPRequestHeaderBuilderView`: Visual builder for crafting HTTP request header configurations.
84. `CookieParserView`: Decodes, inspects, and validates `Set-Cookie` attributes (Secure, HttpOnly, SameSite).
85. `UserAgentParserView`: Parses user agent strings, extracting browser engine, OS version, and device type.
86. `URLEncoderView` / `URLDecomposerView`: URL encoder/decoder and URL component parser (scheme, host, path, query items).

### 16.7 CSS, Layout & Design Utilities (15 Tools)
87. `CSSBorderRadiusGeneratorView`: Visual playground for generating 8-point CSS `border-radius` curves.
88. `CSSShadowGeneratorView`: Multi-layer CSS `box-shadow` generator with blur, spread, and color controls.
89. `CSSFlexboxPlaybookView`: Interactive sandbox demonstrating flexbox layout behaviors.
90. `CSSUnitConverterView`: Converts between px, rem, em, %, vh, vw, and pt.
91. `BezierCurveVisualizerDevToolView`: Interactive cubic and quadratic bezier curve editor with timing coordinates.
92. `BezierPathCodeDevToolView`: Generates Swift `UIBezierPath` and `Path` drawing code from visual curves.
93. `ColorConverterView`: Converts colors across HEX, RGB, HSL, HSV, CMYK, and Swift `Color` syntax.
94. `HexToRGBAndHSLConverterView`: Rapid color channel conversion calculator.
95. `ColorContrastAnalyzerView` / `ContrastCheckerDevToolView`: WCAG 2.1 contrast ratio calculator for normal and large text.
96. `AccessibilityContrastGridDevToolView`: Matrix testing contrast ratios across multiple foreground/background combinations.
97. `ColorPaletteGeneratorDevToolView`: Generates monochromatic, analogous, complementary, and triadic color palettes.
98. `ColorGradientGeneratorView`: Generates linear and radial gradients with CSS and SwiftUI export code.
99. `ColorBlendingDevToolView` / `ColorMixerDevToolView`: Blends color channels across various blend modes (multiply, screen, overlay).
100. `AspectRatioCalculatorView`: Calculates aspect ratios (16:9, 4:3, 21:9) and dimension scalings.
101. `SFSymbolsReferenceView`: Searchable reference catalog of Apple SF Symbols with rendering modes and keywords.

### 16.8 Minifiers & Asset Optimizers (6 Tools)
102. `JSMinifierView`: Minifies JavaScript, stripping whitespace and comments.
103. `CSSMinifierView`: Compresses CSS stylesheets.
104. `HTMLMinifierView`: Strips unnecessary whitespace and comments from HTML documents.
105. `SVGMinifierView`: Optimizes SVG vector files by stripping metadata and rounding coordinates.
106. `GzipCompressorView`: Tests gzip compression ratios and compressed byte sizes.
107. `ImageBase64View`: Converts raster images (PNG, JPEG, WebP) to Base64 data URIs.

### 16.9 System, Hardware & OS Utilities (14 Tools)
108. `CPUMonitorDevToolView`: Real-time CPU core usage and load average graphs.
109. `FPSMonitorDevToolView`: Measures UI frame rate rendering stability and frame drop spikes.
110. `EnergyImpactMonitorDevToolView`: Measures energy impact and battery drain metrics.
111. `BatteryStatusDevToolView`: Inspects battery health, cycle count, temperature, and charging state.
112. `DiskUsageAnalyzerDevToolView`: Visualizes workspace disk footprint by directory and file type.
113. `DeviceInfoView`: Complete system information (macOS kernel version, CPU architecture, GPU cores, memory size).
114. `EnvVarInspectorDevToolView`: Inspects active environment variables and process PATH entries.
115. `ClipboardInspectorDevToolView`: Inspects clipboard pasteboard flavors (plain text, RTF, HTML, TIFF, custom UTIs).
116. `AppSandboxExplorerDevToolView`: Inspects application sandbox container directories (Documents, Caches, Application Support).
117. `AppStateInspectorDevToolView`: Live inspector for active state stores and notification observers.
118. `CacheViewerDevToolView`: Inspects and clears in-memory and disk caches.
119. `BundleSizeAnalyzerDevToolView`: Analyzes compiled app bundle sizes and resource asset breakdowns.
120. `DeepLinkTesterDevToolView`: Tests custom URL scheme and Universal Link handling.
121. `MACAddressGeneratorView`: Generates unicast and multicast MAC addresses.

### 16.10 Developer Cheatsheets & Reference Guides (16 Tools)
122. `SwiftLanguageReferenceView`: Comprehensive syntax guide covering modern Swift features (concurrency, macros, generics).
123. `SwiftConcurrencyCheatsheetView`: Patterns and anti-patterns for `async/await`, `TaskGroup`, `Actors`, and Sendable checking.
124. `SwiftUIPerformanceCheatsheetView`: Best practices for view invalidation, `@Observable`, identity, and list rendering.
125. `GitCheatsheetView`: Common Git workflows, recovery commands, and cherry-picking instructions.
126. `GitBranchingStrategiesView`: Guide comparing GitFlow, GitHub Flow, and Trunk-Based Development.
127. `LLDBDebuggerCheatsheetView`: LLDB commands for breakpoints, memory read/write, expression execution, and thread inspection.
128. `SwiftLintConfigurationGuideView`: Documentation on SwiftLint rule configurations and disable directives.
129. `AppStoreGuidelinesCheatsheetView`: Apple App Store Review Guidelines summary and common rejection causes.
130. `AppleSiliconOptimizationCheatsheetView`: Optimization techniques for ARM64, NEON, Accelerate framework, and Neural Engine.
131. `iOSScreenResolutionsView`: Complete reference guide for all Apple device screen dimensions, points, pixels, and safe area insets.
132. `XcodeShortcutsCheatsheetView`: Default Xcode keyboard shortcuts reference.
133. `MarkdownSyntaxCheatsheetView`: Syntax guide for GitHub Flavored Markdown tables, alerts, and formatting.
134. `SemVerCheckerView`: Validates Semantic Versioning strings and compares version precedence.
135. `TimestampConverterView`: Converts timestamps across diverse international timezones.
136. `TimezoneConverterView`: Timezone offset calculator with daylight saving time indicators.
137. `DateFormatterDevToolView`: Interactive testbed for `DateFormatter` format strings (`yyyy-MM-dd HH:mm:ss.SSS`).

### 16.11 Units, Measurements & Miscellaneous (19 Tools)
138. `LengthConverterView`: Converts units between Metric and Imperial (meters, feet, inches, nautical miles).
139. `WeightConverterView`: Converts grams, kilograms, pounds, ounces, and stones.
140. `TemperatureConverterView`: Converts Celsius, Fahrenheit, and Kelvin.
141. `PercentageCalculatorView`: Calculates percentage changes, markups, and proportions.
142. `MIMETypeLookupView`: Searchable directory of MIME types and associated file extensions.
143. `DiffCheckerView`: Standalone side-by-side text difference checker with word-level diffing.
144. `MarkdownPreviewerView`: Standalone markdown renderer with live HTML output tab.
145. `BreakpointManagerDevToolView`: Central list of all active project breakpoints with condition filters.
146. `DesignerDevToolView`: Quick design scratchpad for testing color combinations and typography scales.
147. `DevToolsMainView`: Searchable launcher and dashboard for all 156 tools.
148. `ExpandedDevTools`: Grid and category view for developer tool discovery.
149. `AppIconSelectView`: Interactive app icon switcher allowing users to select alternate editor app icons.
150. `AppIconManager`: Handles dynamic application icon replacement via macOS system APIs.
151. `AppIconPreviewGenerator`: Script and tool pipeline generating all standard icon set variants (16x16 through 1024x1024).
152. `CreditAndLicensesView`: Displays open-source software attributions and dependency licenses.
153. `ProjectInspectorView`: High-level metrics on project files, lines of code, and architecture graphs.
154. `LocalizationManagerView`: Visual interface for managing string catalogs and translations.
155. `TerminalView`: Embedded terminal emulator for executing shell commands within the project environment.
156. `CodeDictionarySearchView`: Interactive search interface for the coding dictionary.

---

## 17. Offline Coding Dictionary & API Reference System

### 17.1 High-Performance Local Dictionary Index
- **`DictionaryManager`**:
  - Offline searchable database of Apple & Swift framework APIs (Swift standard library, SwiftUI, Foundation, Combine, SwiftData, CoreData, UIKit, AppKit).
  - Sub-millisecond token search using local SQLite Full-Text Search (FTS5).

### 17.2 Entity Data Schema
```swift
public struct DictionaryEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let framework: String
    public let declaration: String
    public let summary: String
    public let parameters: [DictionaryParameter]
    public let returnValue: DictionaryReturnValue?
    public let examples: [DictionaryExample]
    public let commonMistakes: [DictionaryMistake]
}
public struct DictionaryParameter: Codable, Sendable {
    public let name: String
    public let type: String
    public let description: String
}
public struct DictionaryExample: Codable, Sendable {
    public let title: String
    public let code: String
}
public struct DictionaryMistake: Codable, Sendable {
    public let description: String
    public let explanation: String
    public let fix: String
}
```

---

## 18. Extension & Plugin Ecosystem

### 18.1 Extension Manifest Specification
Extensions are distributed as bundles containing an `extension.json` manifest:
```json
{
  "id": "com.developer.swift-formatter",
  "name": "Swift Formatter Extension",
  "version": "1.2.0",
  "description": "Standardizes Swift code formatting and indentation",
  "author": "Engineering",
  "category": "formatter",
  "capabilities": ["code_formatter", "save_hook"],
  "entryPoint": "main.swift",
  "swiftCodeAssistCapable": true,
  "configFields": [
    {
      "key": "indentWidth",
      "type": "number",
      "defaultValue": 4,
      "description": "Number of spaces per indentation level"
    }
  ]
}
```

### 18.2 Sandboxed Script Execution & Tool Injection
- **`ExtensionManager` & `PluginManager`**:
  - Sandboxes extension scripts, injecting an internal RPC bridge over stdin/stdout.
  - When `swiftCodeAssistCapable` is true, the extension's capabilities are registered into the agent's tool catalog, enabling the autonomous agent to invoke third-party extension actions during task solving.

---

## 19. Global Command Palette & Keyboard Shortcuts Matrix

### 19.1 Command Palette Router
- **Trigger**: `Cmd + Shift + P`
- **Fuzzy Search Index**: Indexes all menu items, toolbar tools, dev tools, and active open files.
- **Categorized Results**:
  - `Actions`: Run Build, Run Tests, Open Terminal, Launch Agent.
  - `Navigation`: Open File, Go to Line, Jump to Symbol.
  - `Dev Tools`: Launch any of the 156 built-in developer tools.
  - `Ask AI`: Direct prompt input to trigger the assistant from the palette.

### 19.2 Global Keyboard Shortcuts Matrix

| Action | Primary Shortcut | Menu Category | Subsystem Executed |
| :--- | :--- | :--- | :--- |
| **Command Palette** | `Cmd + Shift + P` | Edit | Global Palette Router |
| **Save File** | `Cmd + S` | File | `DocumentCoordinator.saveCurrentFile()` |
| **Save All** | `Cmd + Opt + S` | File | `DocumentCoordinator.saveAll()` |
| **Find in Files** | `Cmd + F` | Edit | `CodeSearchView` |
| **Go to Line** | `Cmd + L` | Edit | `GoToLineView` |
| **Format Code** | `Cmd + Shift + F` | Edit | `CodeFormatter.format()` |
| **Next Editor Tab** | `Cmd + Shift + }` | Window | `TabCoordinator.nextTab()` |
| **Previous Editor Tab** | `Cmd + Shift + {` | Window | `TabCoordinator.previousTab()` |
| **Run Build** | `Cmd + B` | Project | `XcodeBuildService.build()` |
| **Run Tests** | `Cmd + U` | Project | `SwiftPackageBuildService.test()` |
| **Toggle AI Agent** | `Cmd + Shift + A` | Project | `AssistAgentSession.toggle()` |
| **Embedded Terminal** | `Cmd + Shift + T` | Project | `TerminalView.toggle()` |
| **Visual UI Builder** | `Cmd + Opt + V` | Window | `VisualUIBuilderWindowManager.show()` |
| **Database Explorer** | `Cmd + Opt + E` | Window | `DatabaseExplorerWindowManager.show()` |
| **Personal Documentation** | `Cmd + Opt + D` | Window | `PersonalDocWindowManager.show()` |
| **Source Control Window** | `Cmd + Opt + G` | Window | `SourceControlWindowManager.show()` |
| **Operations Workspace** | `Cmd + Opt + O` | Window | `OperationsWindowManager.show()` |
| **Project Notes** | `Cmd + Opt + N` | Window | `ProjectNotesWindowManager.show()` |
| **Git: Commit** | `Cmd + Shift + C` | Git | `GitService.commit()` |
| **Git: Push** | `Cmd + Shift + H` | Git | `GitService.push()` |
| **Git: Pull** | `Cmd + Shift + L` | Git | `GitService.pull()` |
| **Git: Switch Branch** | `Cmd + Shift + B` | Git | `GitService.switchBranch()` |
| **Git: Cherry Pick** | `Cmd + Shift + K` | Git | `GitService.cherryPick()` |
| **Git: Stash Changes** | `Cmd + Shift + Z` | Git | `GitService.stash()` |
| **Git: Apply Stash** | `Cmd + Shift + V` | Git | `GitService.applyStash()` |
| **Git: Rebase Branch** | `Cmd + Shift + X` | Git | `GitService.rebase()` |
| **Git: Merge Branch** | `Cmd + Shift + M` | Git | `GitService.merge()` |
| **Git: Discard Changes**| `Cmd + Shift + U` | Git | `GitService.discardChanges()` |
| **Git: Create PR** | `Cmd + Shift + Q` | Git | `GitHubService.createPR()` |

---

## 20. Implementation Master Checklist

When executing the build of the new code editor, verify that each module satisfies the following checklist:

- [ ] **State & Security**: Keychain integration, path traversal protection, actor-isolated I/O pipelines.
- [ ] **Code Editor**: Tab coordinator, minimap with viewport scrubber, AST code folding, ghost-text inline AI autocomplete (`AISuggestionEngine`), Info.plist and Entitlements editors, GFM live markdown preview.
- [ ] **AI Agent Engine**: Autonomous execution loop (Plan $\to$ Implement $\to$ Validate $\to$ Recover), all 23 Assist cognitive engines, checklist state manager, AST code patch engine with checkpoint rollback.
- [ ] **Tooling Suite**: Full functional implementation of all **142 Agentic Tools** and **63 Assist Tools**.
- [ ] **Skills & MCP**: `SkillScheme` YAML frontmatter parser, skill authoring wizard, MCP JSON-RPC 2.0 host supporting `stdio` and `SSE` transports.
- [ ] **AI Models**: Local Apple Silicon MLX runner with Hugging Face model downloader, Apple Intelligence/CoreML on-device models, OpenRouter SSE streaming with automatic fallback, local Codex bridge.
- [ ] **Build Pipeline**: SPM toolchain integration, `xcodebuild` CLI runner with compiler diagnostic regex parsers, `IPABuildService` automated codesigning and archive export, cloud deployment managers (Vercel, Netlify, GitHub Pages).
- [ ] **Device & Companion Protocol**: `DeviceConnectKit` physical Apple device deployment and sysdiagnose streaming; `SwiftCode Connect` Bonjour & WebSocket companion protocol with pairing challenge, message envelope, and permission matrix.
- [ ] **Preview & Simulation**: Dynamic runtime compiler (`swiftc -emit-library` $\to$ `.dylib` JIT loading), live reload watcher, `simctl` bridge with APNS injection, location spoofing, and video capture.
- [ ] **Source Control**: Porcelain Git engine with single-hunk staging, 3-way visual merge conflict resolver, GitHub API integration (PRs, Issues, Discussions, Gists), visual CI/CD workflow builder.
- [ ] **Visual UI Builder**: Infinite multi-device artboard canvas, properties inspector, animations panel, bindings panel, bidirectional code-for-artboard generator, interactive full app runner.
- [ ] **Database Explorer**: SQLite, Core Data, and Supabase/PostgreSQL engines, ERD schema visualizer, paged CRUD grid with transactional commit, SQL editor with text-to-SQL AI assistant, migrations engine.
- [ ] **StoreKit Workspace**: Visual `.storekit` editor, local purchase simulation, accelerated subscription renewal cycles, receipt inspector.
- [ ] **Personal Documentation**: Architecture C4 editor, ADR editor, Feature planner, Release checklist, bidirectional Wiki link resolver (`[[...]]`), DocC analyzer.
- [ ] **Operations & Diagnostics**: Real-time telemetry timeline, CPU/RAM/FPS/Energy metrics dashboard, memory leak detector, thread inspector, Mach-O binary inspector (`nm`, `otool`, `lipo`), crash symbolicator (`atos`), network proxy, feature flags manager.
- [ ] **Dev Utilities**: All **156 Built-In Developer Utilities** (code generators for 10+ languages, formatters, cryptography tools, network utilities, CSS/design tools, cheatsheets).
- [ ] **Coding Dictionary**: Offline FTS5-indexed Apple & Swift API dictionary with parameters, examples, and common mistake fixes.
- [ ] **Extensions**: Manifest parser, sandboxed execution bridge, agent tool injection.
- [ ] **Command Architecture**: Command Palette with fuzzy search and complete global keyboard shortcut router.
