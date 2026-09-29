# WriteExecutionPlan.md — System Instruction for Execution Plan Generation

This document is the system instruction for the Execution Plan generation process. It is NOT itself the Execution Plan. The generated plan belongs in `agent_notes.md`.

## Purpose

The `execution_plan` tool MUST follow this instruction to generate a task-specific, evidence-based Execution Plan before any codebase modification begins.

## Mandatory Pre-Plan Pipeline

Before generating the plan, the tool MUST:

1. **Understand the user's request** — Parse the objective into concrete, verifiable goals.
2. **Inspect actual repository state** — Enumerate files, directory structure, and build configuration.
3. **Read relevant files** — Read files that are directly related to the task. Do not guess file contents.
4. **Read relevant architecture** — Identify the architectural patterns, module boundaries, and conventions in use.
5. **Read AGENTS instructions** — Discover and read all applicable AGENTS.md / Agents.md files.
6. **Read applicable Skills** — Discover and read all applicable SKILL.md files.
7. **Identify actual implementation** — Determine what code currently exists and what it does.
8. **Identify actual defects** — Find the real bugs, gaps, or issues that need to be addressed.
9. **Identify dependencies** — Map file dependencies, module dependencies, and build dependencies.
10. **Identify relevant files** — List the specific files that will need to be read, modified, or created.
11. **Identify required changes** — Specify the exact changes needed in each file.
12. **Identify risks** — Flag potential risks: breaking changes, data loss, security concerns, performance regressions.
13. **Identify Workers** — Determine if the task should be decomposed into parallel Worker assignments.
14. **Identify tools** — Map each step to a specific tool from the available tool registry.
15. **Identify verification** — Define how each step will be verified (build, test, lint, type-check).
16. **Break the task into bounded steps** — Each step must have a clear, single responsibility.
17. **Order work by dependencies** — Steps must be sequenced so dependencies are satisfied before dependents run.
18. **Define measurable completion criteria** — Each step must have a concrete, checkable completion condition.
19. **Avoid speculative work** — Do not include steps for features or changes not directly required by the objective.
20. **Avoid invented information** — Never fabricate file contents, function signatures, or repository state.
21. **Avoid hardcoded assumptions** — Base all findings on actual repository inspection.
22. **Avoid claiming implementation before implementation** — The plan describes what WILL be done, not what HAS been done.
23. **Avoid claiming verification before verification** — Verification steps are planned, not completed.

## Plan Structure

The generated Execution Plan MUST contain these sections:

```markdown
## Objective
[Clear, verifiable statement of what will be accomplished]

## Execution Mode
[Plan or Autopilot]

## Repository Findings
[Actual findings from inspecting the repository — file counts, structure, build system]

## Current State
[What currently exists — relevant files, their purpose, current behavior]

## Relevant Files
[List of specific files that will be read, modified, or created]

## Relevant Architecture
[Architectural patterns, module boundaries, conventions identified]

## Detected Problems
[Actual defects, gaps, or issues found during inspection]

## Required Changes
[Specific changes needed, mapped to files]

## Dependencies
[File dependencies, module dependencies, build dependencies]

## Execution Steps
[Numbered, ordered steps with tool assignments]

## Worker Assignments
[If applicable — Worker names, scopes, tasks, dependencies]

## Tool Requirements
[Tools needed for each step]

## User Decisions Required
[If in Plan mode — decisions that need user input]

## Verification Requirements
[How each step will be verified — build, test, lint, type-check]

## Risk Areas
[Potential risks and mitigation strategies]

## Recovery Strategy
[What to do if a step fails]

## Completion Criteria
[Measurable conditions that must be met for the task to be complete]
```

## Tool Constraints

- Every step MUST reference a real tool from the tool registry.
- Every file path MUST be based on actual repository inspection.
- Every verification step MUST specify a concrete verification method.
- The plan MUST NOT contain placeholder text, TODO markers, or "TBD" entries.
- The plan MUST NOT claim work has been completed before it has been done.
- The plan MUST NOT include steps that cannot be verified.

## Output

The tool writes the generated plan to `agent_notes.md` in the workspace root. The plan is a living document that evolves as execution progresses.
