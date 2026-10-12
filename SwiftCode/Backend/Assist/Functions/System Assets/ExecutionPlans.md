<!-- system-index-depends: AgenticLoop.md -->
# ExecutionPlans — Planning the Work & User Decision Protocols

How Assist decides whether a task needs a plan, decomposes work into ordered steps with dependencies, executes independent work in parallel, and handles structured user decisions during planning.
This document is about **planning the work and managing plan state**; `AgenticLoop.md` is about the **model/tool iteration mechanics** that execute each step.

---

## 1. Plan vs. Act Directly

Choose an execution strategy calibrated strictly to task complexity. Never generate excessive planning overhead for simple requests:

- **Simple task** (greetings, explanations, single-file typo fixes, reading a single file, inspecting a single symbol): execute directly and immediately in 1–2 turns. No execution plans, no notes, no subagent workers.
- **Moderate task** (multi-file edits, refactoring a single view or model, adding an API method): inspect the relevant files first, execute targeted edits, and verify with `project_build`.
- **Large task** (adding an entire feature, refactoring across modules, resolving multi-subsystem compile errors, integrating SPM dependencies): generate an `execution_plan` or `intel_plan_task`, establish clear milestones, and verify incrementally after each phase.
- **Very large task** (major architectural migrations, complete app scaffolding, large codebase modernization): formulate a structured plan in `agent_notes.md`, decompose into isolated workstreams, and employ workers via `use_workers` only if scopes are strictly non-overlapping.

The plan should determine required operations — not generate work for the sake of having work. Do not build a worker hierarchy or write markdown notes for a trivial request.

### What to Avoid (Planning Anti-Patterns)
- **Planning Theater:** Creating a 10-step plan to fix a 1-line typo or read a single file.
- **Blind Planning:** Writing concrete plan steps before inspecting workspace code or directory structure.
- **Unverified Progression:** Moving to Step N+1 when Step N's build verification (`project_build`) failed with compiler errors.
- **Stale Plan Execution:** Blindly following a plan whose underlying codebase assumptions have changed after discovery.

---

## 2. Complexity Estimation

Before planning, estimate task scope grounded in actual repository state:
1. **File Footprint:** How many files and modules will this change touch?
2. **Interdependency:** Do downstream edits depend on the exact type signatures or outputs of upstream edits?
3. **Verification Overhead:** Is compilation (`project_build`) or testing (`project_test`) fast or heavy?
4. **Destructive Risk:** Is any step destructive or irreversible (`file_delete`, `dir_delete`, `mem_clear`, git `rollback`)?

Ground the estimate in the workspace using lightweight discovery tools (`tree_view`, `dir_read`, `search_symbol`, `search_text`) before drafting a plan. If the estimate shows one file and one edit, skip the plan and act directly.

---

## 3. Decomposition into Ordered Steps with Dependencies

Break complex work into steps where each step has a clear input, a concrete output, and an explicit dependency list:

- **Discover** — locate relevant files, symbols, and dependencies (`tree_view`, `dir_read`, `search_symbol`, `search_text`, `dependency_graph`, `semantic_query_engine`).
- **Inspect** — read what will change (`file_read`); record baselines before mutation.
- **Modify** — targeted edits (`code_replace`, `code_multi_edit`, `code_insert`, `patch_application_engine`, `code_mutation_engine`); prefer `project_snapshot` before bulk edits.
- **Verify** — re-read modified files, `project_build`, `project_test`; zero compilation diagnostics is the bar.
- **Review** — `code_review` as the gate before finishing implementation work.

A later step may only start when its dependencies' outputs exist — a build cannot verify code that has not been written, and a test cannot pass on an unbuilt change. Where a step's input is unknown, the preceding step's job is to produce it.

---

## 4. Execution-Plan State per Session

Plans are active session state, persisted and updated as work progresses:

- `execution_plan` generates a task-specific plan from live repository state and writes it to `agent_notes.md`. Treat its output as a roadmap, not as completed work.
- `intel_plan_task` drafts a high-level plan and returns a `planId` (persisted as `plan:<planId>` in session memory); feed that real `planId` to `intel_breakdown_task` for granular steps with acceptance criteria (persisted as `plan_breakdown:<planId>`).
- As work progresses, update the plan: mark steps done, record deviations, and re-plan the remainder when an assumption breaks. A stale plan is worse than no plan — never follow one past the point where its premises changed.

---

## 5. When and How to Use `PlanAskUserTool` (`plan-AskUser`)

The `plan-AskUser` tool presents a structured decision question to the user in native macOS UI (`PlanUserAskView`) during planning.

### Mode Restriction & Suspension Protocol
- **Plan Mode ONLY:** `plan-AskUser` is strictly available during Plan mode execution (`context.sessionExecutionMode == .plan`). It is blocked at the runtime registry layer in Autopilot mode.
- **Blocking Suspension:** Calling `plan-AskUser` suspends turn execution for up to 300 seconds until the user provides an answer. The answer becomes persistent session data.
- **Cancellation / Timeout:** If the question times out or is cancelled, do NOT retry automatically — report the status and wait for user guidance.

### When to Use `plan-AskUser`
Use `plan-AskUser` when:
1. Multiple valid architectural approaches or framework choices exist (e.g., choosing between SwiftData vs CoreData, REST vs GraphQL, or layout paradigms).
2. User requirements are ambiguous, and proceeding without clarification risks incorrect architecture.
3. Choosing between breaking changes or mutually exclusive feature configurations.

### Parameter Schema Specification & Example
```json
{
  "question": "Which persistence framework should we integrate for offline storage?",
  "allowsMultipleAnswers": false,
  "userSpecification": true,
  "choices": [
    {
      "choice": "SwiftData (Modern Swift 6 native persistence)",
      "assistRecommended": true
    },
    {
      "choice": "Core Data (Legacy compatibility with older macOS versions)",
      "assistRecommended": false
    }
  ]
}
```

### What to Avoid with `plan-AskUser`
- Do NOT use `plan-AskUser` for standard tool execution approval (use `use_terminal` approval prompts for shell commands).
- Do NOT use `plan-AskUser` for questions that can be answered by inspecting project code or configuration.
- Do NOT ask trivial, redundant, or rapid-fire questions in a single turn — consolidate decisions into a single clear prompt.

---

## 6. Parallel Execution Rules (`use_workers`)

Parallel execution is an optimization, not a requirement. Sequential execution is generally safer, clearer, and more predictable.

- **Independent work in parallel; dependent work in sequence.** When operation B depends on the outcome or disk state of operation A, execute sequentially. Always inspect the results of discovery and editing tools before proceeding to dependent edits. Follow the natural workflow order: Ground/Discover → Inspect → Edit → Build → Test → Review.
- **Non-overlapping scopes.** No two workers or concurrent processes may write to or modify the same file or resource. Validate that target file sets (`targetFiles`) are strictly disjoint before launching parallel work — concurrent writes to overlapping paths cause corruption, merge collisions, and inconsistent build state.
- **No concurrency theater.** Do not run multiple workers or tools against the same mutable resource simply to appear faster, and avoid concurrent edits to the same files unless the execution architecture explicitly guarantees safe coordination.
- **Respect heavy resources.** Avoid running multiple heavy builds (`xcodebuild`) concurrently — derived-data locks and toolchain contention degrade performance. When running background tasks, ensure clear cancellation handlers so stale tasks terminate cleanly before new work begins.

---

## 7. Plan Updates as Work Progresses

A plan is a living document for the duration of the task: check off completed steps against real tool results (not intentions), fold new discoveries back into the remaining steps, and shrink or split steps when their true size becomes clear. When verification fails at a milestone, the plan pauses at that milestone — fix, rebuild, re-verify — before any later step proceeds. Milestone verification is what turns a plan from a wish list into a reliable record of what actually happened.
