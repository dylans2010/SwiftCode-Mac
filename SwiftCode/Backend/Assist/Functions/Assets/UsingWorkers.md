## 6. WORKER & SUBAGENT DELEGATION POLICY

Workers and subagents are optional execution capabilities. The existence of a Worker capability (`use_workers`, `start_subagent`) does **NOT** imply that a worker should be created.

---

## 1. Direct Execution by Default
Always prefer direct execution by the primary agent when the task is small, sequential, or easily completed without parallelization.

### When NOT to create Workers:
Do **NOT** spawn Workers or subagents for:
- Greetings ("hello", "hi", "good morning");
- Simple questions or architectural explanations;
- Single-file reads, inspections, or edits;
- Simple text or regex searches across the codebase;
- Fixing typos, updating imports, or renaming a small symbol;
- Single build or test runs;
- Straightforward tool calls that the primary agent can execute directly.

### When Workers ARE Justified:
Worker creation is appropriate only for:
- Auditing entire large codebases across independent domains (e.g. backend vs UI vs database);
- Investigating multiple independent, non-overlapping subsystems simultaneously;
- Running multi-domain migrations requiring parallel isolated research;
- High-volume independent file processing where workstreams do not intersect.

### Worker Count & Discipline:
- **Default to 0 Workers.**
- Prefer 1 Worker or a small number of Workers only when genuinely independent workstreams exist.
- Every Worker task must have a clear objective, explicit non-overlapping scope, and bounded responsibility.

---

#### `use_workers`
**Capability:** Task Planning · **Risk:** safeMutation  
**When to use:** Decomposing genuinely independent workstreams into parallel or sequenced workers in SwiftCode Assist.  
**Parameters:**  
- `workers` (array of objects or JSON string, required) — list of worker specifications.  
  - `name` (string, required): Unique identifier for the worker.  
  - `scope` (string, required): Distinct non-overlapping architectural domain or subsystem.  
  - `task` (string, required): Clear instructions; **must be ≤ 500 characters**.  
  - `role` (string, optional): Specialty role name.  
  - `dependencies` (array of strings, optional): Must reference worker names defined in the same batch.  
  - `targetFiles` (array of strings, optional): Explicit files this worker will modify; **must not overlap across workers in the same batch**.  
**Returns:** Per-worker execution summaries with filesystem reconciliation (`verifiedClaims`, `discrepancyCount`).  
**Errors:** Validation failures (duplicate names, overlapping scopes or target files, unknown dependencies, task description exceeding 500 chars) — fix the specification rather than retrying as-is.  
**Notes:** Workers execute real mutations through the complete tool suite. This is the highest-risk planning tool.

---

#### `start_subagent`
**Capability:** Cloud Subagent Delegation · **Risk:** safeMutation  
**When to use:** Spawning an independent subagent worker in Google Antigravity Cloud Toolkit sessions.  
**Usage:** Dispatches an isolated subagent with its own conversation context and objective. Subagents report results back to the primary agent upon completion.
