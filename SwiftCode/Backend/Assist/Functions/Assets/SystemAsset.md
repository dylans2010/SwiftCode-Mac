# SYSTEM ASSET MASTER DIRECTORY & KNOWLEDGE MAP

> **Classification**: Authoritative Table of Contents & Routing Map  
> **Scope**: Master Index of all Modular Instruction & Training Assets for SwiftCode Assist.  
> **Location**: `SwiftCode/Backend/Assist/Functions/Assets/`

---

## 1. Executive Knowledge Map

SwiftCode Assist uses a modular instruction architecture. Rather than injecting a monolithic instruction corpus on every turn, Assist uses this **System Asset Map** to selectively load focused, task-relevant guidance.

Every asset in the catalog provides deep operational principles, safety boundaries, schema rules, and error recovery policies.

```
                               +-----------------------------+
                               |       SystemAsset.md        |
                               |  (Master Index & Map)       |
                               +--------------+--------------+
                                              |
               +------------------------------+------------------------------+
               |                              |                              |
               v                              v                              v
+-----------------------------+ +-----------------------------+ +-----------------------------+
|        FOUNDATION           | |           TOOLING           | |        ORCHESTRATION        |
| - Identity.md               | | - ToolCalling.md            | | - UsingWorkers.md           |
| - CoreRules.md              | | - ToolSchemasAndParameters  | | - ParallelWork.md           |
| - UserRequests.md           | | - UsingTools.md             | | - PlanningAndTaskComplexity |
| - OutputtingWork.md         | | - ToolRouting.md            | | - StreamingAndProgress.md   |
|                             | | - ToolResultsAndErrors.md   | |                             |
+-----------------------------+ +-----------------------------+ +-----------------------------+
               |                              |                              |
               v                              v                              v
+-----------------------------+ +-----------------------------+ +-----------------------------+
|         ENGINEERING         | |     SAFETY & RELIABILITY    | |      CONTEXT & MEMORY       |
| - FileOperations.md         | | - SecurityAndPrivacy.md     | | - Context.md                |
| - SearchAndContext.md       | | - TerminalAndCommandSafety  | | - Memory.md                 |
| - EditingAndPatching.md     | | - RetryAndRecovery.md       | | - MCPAndSkills.md           |
| - BuildTestValidation.md    | | - ModelCompatibility.md     | |                             |
| - GitAndVersionControl.md   | |                             | |                             |
| - SwiftAndConcurrency.md    | |                             | |                             |
+-----------------------------+ +-----------------------------+ +-----------------------------+
```

---

## 2. Catalog & Routing Reference

### Category I: Foundation & Persona
1. **`Identity.md`**
   - **Purpose**: Defines Assist's name, host environment, core role, obedience rules, refusal policies, language competencies, and system boundaries.
   - **Consult When**: Understanding who Assist is, refusal policies, core ethical and behavioral guidelines.
   - **Keywords**: `identity`, `persona`, `refusal`, `obedience`, `environment`, `capabilities`.

2. **`CoreRules.md`**
   - **Purpose**: Core operating principles: Ground Before Mutate, concurrency isolation, non-destructive defaults, state verification.
   - **Consult When**: Starting any task, before performing file changes, resolving structural conflicts.
   - **Keywords**: `ground`, `mutate`, `invariants`, `boundaries`, `concurrency`.

3. **`UserRequests.md`**
   - **Purpose**: Classifying and understanding user intent (conversational, code modification, debugging, explanation, multi-step orchestration).
   - **Consult When**: Dissecting complex requests, handling underspecified requirements.
   - **Keywords**: `user intent`, `classification`, `prompt analysis`, `multi-turn`.

4. **`OutputtingWork.md`**
   - **Purpose**: Response presentation standards: plain inline tool activity rows with SF Symbols and status colors, NO cards or generic thinking bubbles.
   - **Consult When**: Formatting final responses, surfacing tool results to the user.
   - **Keywords**: `presentation`, `inline activity`, `no cards`, `sf symbols`, `markdown`.

---

### Category II: Tooling Architecture & Protocols
5. **`ToolCalling.md`**
   - **Purpose**: Strict tool-calling protocol, parameter validation, structured invocation syntax, avoiding raw protocol leakage.
   - **Consult When**: Formulating tool calls, handling native vs Antigravity SDK tool dispatches.
   - **Keywords**: `toolId`, `parameters`, `structured calling`, `validation`, `protocol`.

6. **`ToolSchemasAndParameters.md`**
   - **Purpose**: Authoritative reference of all registered tool schemas, argument definitions, required types, and parameter constraints.
   - **Consult When**: Inspecting parameter definitions for any registered tool.
   - **Keywords**: `schema`, `argument types`, `required parameters`, `tool registry`.

7. **`UsingTools.md`**
   - **Purpose**: Operational discipline for invoking tools safely: read before edit, single-responsibility calls, idempotency.
   - **Consult When**: Deciding the best tool for an action and avoiding tool misuse.
   - **Keywords**: `tool discipline`, `safe mutation`, `destructive caution`, `idempotency`.

8. **`ToolRouting.md`**
   - **Purpose**: Directing tool invocations across Native Swift Tools, Antigravity SDK Tools, MCP Servers, and System Tools.
   - **Consult When**: Choosing between competing tool backends or cross-environment delegation.
   - **Keywords**: `routing`, `native tools`, `sdk tools`, `mcp`, `system tools`.

9. **`ToolResultsAndErrors.md`**
   - **Purpose**: Interpreting tool outputs, decoding error signals, handling truncated output, executing recovery strategies.
   - **Consult When**: A tool returns failure, error, or unexpected output.
   - **Keywords**: `tool error`, `exit code`, `diagnostics`, `recovery`, `error handling`.

---

### Category III: Codebase Engineering & Operations
10. **`FileOperations.md`**
    - **Purpose**: Reading, writing, inspecting, and deleting project files. Path sanitization, preventing path traversal attacks.
    - **Consult When**: Using `file_read`, `file_write`, `dir_list`, `file_delete`.
    - **Keywords**: `files`, `directory`, `read`, `write`, `path sanitization`.

11. **`SearchAndContext.md`**
    - **Purpose**: Codebase exploration: ripgrep text search, symbol search, AST lookup, fuzzy matching.
    - **Consult When**: Locating symbol declarations, references, error locations.
    - **Keywords**: `search`, `grep`, `symbols`, `codebase exploration`, `ast`.

12. **`EditingAndPatching.md`**
    - **Purpose**: Precision text editing: line-range replacement, unified diff patching, atomic file updates.
    - **Consult When**: Modifying existing code without corrupting surrounding context.
    - **Keywords**: `patching`, `replace_file_content`, `diff`, `refactoring`.

13. **`BuildTestValidation.md`**
    - **Purpose**: Xcode and Swift build pipelines: `xcodebuild`, compiler error diagnostics, dependency resolution.
    - **Consult When**: Building targets, diagnosing compiler failures, validating changes.
    - **Keywords**: `xcodebuild`, `swift build`, `compiler error`, `validation`.

14. **`GitAndVersionControl.md`**
    - **Purpose**: Source control operations: committing, branching, staging, working tree status, conflict resolution.
    - **Consult When**: Managing git state, inspecting repositories, recording milestones.
    - **Keywords**: `git`, `commit`, `branch`, `working tree`, `diff`.

15. **`SwiftAndConcurrency.md`**
    - **Purpose**: Swift 6 language rules, strict concurrency checking, `@MainActor`, `Sendable`, Swift Concurrency patterns.
    - **Consult When**: Writing or refactoring Swift code to satisfy modern compiler invariants.
    - **Keywords**: `swift 6`, `concurrency`, `actors`, `sendable`, `async/await`.

---

### Category IV: Multi-Agent & Orchestration
16. **`UsingWorkers.md`**
    - **Purpose**: Subagent delegation policies: role definitions, bounded file ownership, deliverables.
    - **Consult When**: Decomposing large tasks into concurrent subagents (>3 tasks).
    - **Keywords**: `subagents`, `workers`, `delegation`, `roles`, `concurrency`.

17. **`ParallelWork.md`**
    - **Purpose**: Managing parallel workflows: file isolation, preventing concurrent file edits, pipeline batching.
    - **Consult When**: Launching multiple subagents or background tasks simultaneously.
    - **Keywords**: `parallelism`, `lock contention`, `isolation`, `batching`.

18. **`PlanningAndTaskComplexity.md`**
    - **Purpose**: Deconstructing complex objectives: step-by-step milestones, progress tracking, dependency trees.
    - **Consult When**: Formulating plans for multi-step tasks before execution.
    - **Keywords**: `planning`, `milestones`, `task breakdown`, `execution tree`.

19. **`StreamingAndProgress.md`**
    - **Purpose**: Streaming lifecycle management: start, progress, output chunks, completion, cancellation.
    - **Consult When**: Streaming real-time updates and preventing visually stuck states.
    - **Keywords**: `streaming`, `progress events`, `output chunks`, `lifecycle`.

---

### Category V: Safety, Reliability & Models
20. **`SecurityAndPrivacy.md`**
    - **Purpose**: Credential security, Keychain access, redacting tokens, sandbox protections, untrusted data handling.
    - **Consult When**: Interacting with API keys, secrets, remote endpoints, or external code.
    - **Keywords**: `security`, `keychain`, `sandbox`, `credentials`, `privacy`.

21. **`TerminalAndCommandSafety.md`**
    - **Purpose**: Shell command execution guardrails: process isolation, timeout enforcement, preventing destructive shell actions.
    - **Consult When**: Using `use_terminal` or executing background shell tasks.
    - **Keywords**: `terminal`, `shell safety`, `process execution`, `guardrails`.

22. **`RetryAndRecovery.md`**
    - **Purpose**: Self-healing loops: loop detection, oscillation prevention, stagnation recovery, exponential backoff.
    - **Consult When**: Experiencing repeated tool errors or circular logic.
    - **Keywords**: `self-healing`, `loop detector`, `recovery`, `retry`.

23. **`ModelCompatibility.md`**
    - **Purpose**: Cross-model support: Gemini, OpenAI, Anthropic, OpenRouter, Mistral, Qwen, Ollama, LM Studio.
    - **Consult When**: Routing requests across providers and ensuring structured tool-call compatibility.
    - **Keywords**: `providers`, `gemini`, `openai`, `ollama`, `tool calling support`.

---

### Category VI: Knowledge, Memory & Skills
24. **`Context.md`**
    - **Purpose**: Workspace context management: file buffers, AST symbol graph, project topology, token budget awareness.
    - **Consult When**: Managing prompt context size and extracting relevant workspace symbols.
    - **Keywords**: `context`, `workspace topology`, `ast symbols`, `token budgeting`.

25. **`Memory.md`**
    - **Purpose**: The User Memory System: `capture_memory`, `retrieve_memory`, `manage_memory`, and persistent `UserMemory.md`.
    - **Consult When**: Saving facts about the user, retrieving preferences, updating user memory.
    - **Keywords**: `user memory`, `capture_memory`, `retrieve_memory`, `manage_memory`, `UserMemory.md`.

26. **`MCPAndSkills.md`**
    - **Purpose**: Model Context Protocol (MCP) servers and Antigravity Skills integration and discovery.
    - **Consult When**: Using external MCP tools or activating dynamic agent skills.
    - **Keywords**: `mcp`, `skills`, `tool extensions`, `external servers`.

---

## 3. Dynamic Asset Selection Protocol

When constructing model requests, `LoadUpSystemAssets` employs the following rules:
1. **Mandatory Core**: `CoreRules.md`, `Identity.md`, `SecurityAndPrivacy.md`, `OutputtingWork.md` are prioritized for foundational alignment.
2. **Context-Specific Injection**: Based on the user's intent:
   - For file operations & editing: Inject `FileOperations.md`, `EditingAndPatching.md`.
   - For building & debugging: Inject `BuildTestValidation.md`, `SwiftAndConcurrency.md`.
   - For subagents & multi-task work: Inject `UsingWorkers.md`, `ParallelWork.md`, `PlanningAndTaskComplexity.md`.
   - For user facts & preferences: Inject `Memory.md`.
   - For external tools / MCP: Inject `MCPAndSkills.md`.
3. **Token Budget Enforcement**: Loaded assets must never exceed the allocated system prompt token budget.
