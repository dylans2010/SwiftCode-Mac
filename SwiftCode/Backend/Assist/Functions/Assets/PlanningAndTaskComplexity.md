## 8. EXECUTION PLANNING & TASK COMPLEXITY

Choose an execution strategy calibrated directly to task complexity. Never generate excessive planning overhead for simple requests.

---

## 1. Task Complexity Tiers

### Simple Task
- **Examples**: Greetings, explanations, single-file typo fixes, reading a single file.
- **Strategy**: Execute directly and immediately without creating execution plans or spawning workers.

### Moderate Task
- **Examples**: Multi-file edits, refactoring a single view or model, adding an API method.
- **Strategy**: Inspect relevant files, execute targeted edits with `code_replace`, verify with `project_build`.

### Large Task
- **Examples**: Adding an entire feature, refactoring across modules, resolving multi-subsystem compile errors.
- **Strategy**: Generate an `execution_plan`, establish clear milestones, verify incrementally after each phase.

### Very Large Task
- **Examples**: Major architectural migrations, complete app scaffolding, large codebase modernization.
- **Strategy**: Formulate structured plan in `agent_notes.md`, decompose into isolated workstreams, and employ workers only if scopes are strictly non-overlapping.

---

## 2. Planning & Interactive Decision Tools

#### `execution_plan`
**Capability:** Task Planning · **Risk:** safeRead  
**When to use:** Generating a task-specific execution plan from live repository state before modifying code.  
**Parameters:**  
- `objective` (string, required) — the primary task objective.  
- `mode` (string, optional, default `"autopilot"`) — execution mode (`"plan"` or `"autopilot"`).  
- `relevantFiles` (array of strings, optional) — list of workspace-relative paths to focus on.  
**Returns:** Plan summary, `planFile` (`agent_notes.md`), `stepCount`, `relevantFileCount`, `workerCount`, `mode`.  
**Notes:** Writes and updates `agent_notes.md`. Treat its output as a roadmap, not completed work.

---

#### `plan-AskUser`
**Capability:** Task Planning · **Risk:** safeRead  
**When to use:** A genuine architectural or design decision requires user clarification during **Plan mode**.  
**When NOT to use:** In Autopilot mode (blocked at the registry layer); for trivial progress updates; when the answer is clear from context.  
**Parameters:**  
- `question` (string, required) — the decision or choice to present to the user.  
- `allowsMultipleAnswers` (boolean, required) — whether multiple choices can be selected.  
- `choices` (array, required) — list of options, each containing a `choice` string and `assistRecommended` boolean.  
- `userSpecification` (boolean, optional, default false) — set true to allow free-form custom user text input.  
**Returns:** Question plus the user's selected answer (`questionID`, `answer`).  
**Notes:** Suspends execution up to 300 seconds waiting for user response. If cancelled or timed out, report status transparently.

---

#### `intel_plan_task`
**Capability:** Task Planning · **Risk:** safeRead  
**When to use:** Drafting a high-level plan for a complex task before acting.  
**Parameters:**  
- `task` (string, required) — description of the high-level task.  
**Returns:** `planId` (UUID string) and `steps`; persists in session memory as `plan:<planId>`. Feed `planId` to `intel_breakdown_task` for granular steps.

---

#### `intel_breakdown_task`
**Capability:** Task Planning · **Risk:** safeRead  
**When to use:** Expanding an existing plan into granular steps with acceptance criteria.  
**Parameters:**  
- `planId` (string, required) — plan identifier obtained from `intel_plan_task`.  
**Returns:** `breakdown` text; persisted as `plan_breakdown:<planId>`.

---

#### `intel_autofix`
**Capability:** Diagnostics & Profiling · **Risk:** safeMutation  
**When to use:** Attempting LLM-driven fixes for compilation errors at a target path.  
**Parameters:**  
- `path` (string, optional, default `"."`) — path to fix.

---

#### `intel_generate_tests`
**Capability:** Testing & QA · **Risk:** safeMutation  
**When to use:** Generating XCTest stubs for a Swift source file.  
**Parameters:**  
- `path` (string, required) — Swift source file to generate tests for.  
- `testPath` (string, optional) — destination test file path.  
**Returns:** `test_path`, `test_count`, `types_count`, `functions_count`.

---

#### `intel_explain_code`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Generating an explanation of a file's architecture and logic.  
**Parameters:**  
- `path` (string, required) — path of the file to explain.

---

#### `create_new_app`
**Capability:** General · **Risk:** safeMutation  
**When to use:** Scaffolding a new native macOS or iOS application project from scratch.  
**Parameters:**  
- `appName` (string, required) — name of the application.  
- `applicationDescription` (string, required) — detailed description of the app.  
- `bundleIdentifier`, `version`, `build`, `platform`, `projectLocation`, `uiPreferences`, `architecturePreferences`, `additionalRequirements`, `overwriteExistingMetadata` (optional).  
**Notes:** Switches the active project session. Not idempotent.
