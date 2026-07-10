# AGENTS.md

## 0. What This File Is
This is the operating contract for any autonomous agent working in this repository. It is read before every task, not just the first one. If an instruction elsewhere conflicts with this file, this file wins unless the current AED explicitly and visibly overrides a specific clause.

## 1. Project Snapshot
- SwiftCode, Swift 6, Xcode 26, deployment target macOS 15+.
- Build system: native Xcode project (`.xcodeproj`), not SPM-only.
- This is one of several related codebases (SwiftCode-Mac, Tools-Kit, Browse). Conventions from one do not automatically apply to another unless this file says so.

## 2. Mandatory Procedure — Every Task, No Exceptions

### 2.1 Before writing code
- [ ] Read the AED completely before touching any file.
- [ ] Identify every file the task will touch, and every file it must NOT touch.
- [ ] Scan the surrounding module for existing patterns — naming, error handling, actor boundaries — and match them instead of introducing a new style.
- [ ] If the AED says "no new files," that's absolute. Solve it inside existing files.

### 2.2 While writing code
- [ ] Concurrency: `actor` for shared mutable state; `@Observable` for anything SwiftUI observes. Never `ObservableObject`, never `@Published`, never Combine.
- [ ] Logging: `Logger` from `os.log` exclusively. `print()` is never acceptable, including "temporary" debug output.
- [ ] Force-unwraps (`!`) require an inline comment directly above stating the specific invariant that makes the unwrap safe. No comment, no unwrap — use `guard let` / `if let` / a typed error instead.
- [ ] No hardcoded values that could plausibly change — pull from a constant, config, or existing enum. Covers magic numbers, URLs, and string keys.
- [ ] No stubs, no `// TODO: implement`, no mocked responses, no simulated SDK behavior. A partially working feature is a failed task, not a partial success — see §6.

### 2.3 After writing code
- [ ] Every new Swift file is registered in `.xcodeproj` — exact procedure in §4. Compiling locally but not being registered makes it an orphan file, which is a failed task.
- [ ] No broken imports, no unused imports left behind.
- [ ] Re-read the diff once, specifically hunting for shortcuts — a suppressed warning, an unjustified force-unwrap, a copy-pasted block that should have been refactored.

## 3. Concurrency & Observation Rules (Swift 6 strict mode)
- Shared mutable state lives behind an `actor`. If a type needs to be read from multiple isolation domains, make the type itself an actor rather than adding locks.
- `@MainActor` is applied at the type level for UI-bound state, not scattered per-method — a type is either UI-bound or it isn't.
- Do not redeclare conformances the compiler already synthesizes or that are already inherited. Check what's already satisfied before adding `: Sendable`, `: Equatable`, etc. — this is the direct cause of the redundant-conformance errors already seen on this project.
- Anything crossing an actor boundary must be `Sendable`. `@unchecked Sendable` is a last resort and requires a comment explaining exactly what makes it safe.
- Prefer structured concurrency (`async let`, `TaskGroup`) over a bare `Task { }`. If an unstructured `Task` is unavoidable, state which actor it's expected to run on.

## 4. Xcode Project File Integration (CRITICAL — read this twice)
Every new Swift file requires exactly four entries in `project.pbxproj`, each keyed by a 24-character uppercase hex UUID:

1. `PBXBuildFile` entry — one new UUID, references the file's `PBXFileReference` UUID.
2. `PBXFileReference` entry — a second new UUID, declares the file itself (path, `lastKnownFileType = sourcecode.swift`).
3. That `PBXFileReference` UUID added to the `children` array of the correct `PBXGroup` — the group matching where the file actually lives, not an arbitrary one.
4. The `PBXBuildFile` UUID added to the `files` array of the target's `PBXSourcesBuildPhase`.

Two UUIDs generated, each referenced across two of the four locations. Wrong UUID length, a reused UUID, or the wrong group is exactly how this project file has corrupted before. Treat this as procedure, not a suggestion.

No orphan files. No missing target memberships. No untracked assets. No broken module references. Any one of these invalidates the task.

### Known UUIDs for Groups and Build Phases
Use these exact uppercase 24-character hexadecimal UUIDs when placing files into the corresponding directories:
* **Core/AI**: `DA941B6FA862048858B975DF`
* **Core/AI/Agent**: `9FAB492FE3914F789AA58201`
* **Tools/Agentic**: `D3C76C44A71C4A3EB65045B1`
* **ViewModels**: `C38806164DD566333A92A410`
* **Views**: `FE18E54E76741F54A82CD586`
* **Utilities**: `576E45E47FC5098A3A96ECB8`
* **Dashboard**: `EA26B0E5D067B5922CF6F2C8`
* **Backend/AI**: `DF6B1A5F79682983F71C7E7E`
* **Backend/Git**: `E063E218D13ACDDD0B728F8D`
* **Persistence/Templates**: `265E9A432B28B39C005F9A10`
* **Models**: `2B21AC80A9DC86CB7D9BD14F`
* **Services**: `57AFC04E569B8BDE2658ECD4`
* **GitHub**: `718173758FBD56C156A0D0F5`
* **Dev Tools**: `2B4CEE860D734A23837F5302`
* **UI/Styles/Styling**: `B0020001B0020001B0020001`
* **Sources Build Phase**: `9BF8BFB9B87ED46BDA700029`

Every UUID you generate for new items must be a unique, 24-character uppercase hexadecimal string.

## 5. What Must Never Happen
- Never invent an API, framework, or SDK method that doesn't exist to make something compile. If the correct API is unclear, say so in the PR description instead of fabricating one.
- Never delete or weaken a test to make CI pass.
- Never suppress a compiler warning or error instead of fixing what's causing it.
- Never touch a file outside the AED's stated scope, even if something else looks wrong nearby — flag it instead (§7).
- Never commit a secret, API key, or credential, even a placeholder-looking one in a comment.
- Never mark a task complete when part of it is stubbed, mocked, or deferred.

## 6. Functional Completeness Mandate
A stub, placeholder, or "will implement later" comment is not a smaller version of the feature — it is a missing feature. Tasks are binary: fully done against the AED's stated scope, or not done. This is a CAF-9 violation (§8) and invalidates the task's completion status even if everything else about it is correct.

## 7. Ambiguity Protocol
There's no human in the loop mid-task, so silence isn't an option and neither is guessing recklessly. When the AED underspecifies something:
1. Choose the interpretation most consistent with the existing architecture and least destructive to revert.
2. Document the assumption explicitly in the PR description — what was ambiguous, what you chose, and why.
3. Only leave part of the task undone if the ambiguous action is both irreversible and broad in scope (e.g., an unclear boundary on a destructive purge). Even then, finish everything unambiguous first and flag only the remainder.

## 8. Failure Taxonomy
This repository uses the CAF (Critical Architecture Failure) codes from the agentic-prompt-compiler skill, plus one addition already established in prior work:

| Code | Violation |
|---|---|
| CAF-1 | Mock or placeholder usage |
| CAF-2 | Missing project registration |
| CAF-3 | Skipped architecture synthesis |
| CAF-4 | Simulated API or SDK behavior |
| CAF-5 | Incomplete feature expansion |
| CAF-6 | Broken dependency graph |
| CAF-7 | Missing validation phase |
| CAF-9 | Stub/placeholder treated as complete (Functional Completeness Mandate) |
| CAF-X | System-level architectural violation |

If a fuller CAF-1–20+ taxonomy already exists elsewhere in this project (System.md or similar), reconcile numbering against that source rather than treating this table as exhaustive — don't assign a new meaning to a code that's already taken.

Any CAF-1, CAF-2, or CAF-9 invalidates the entire task.

## 9. Commit & PR Conventions

### 9.1 Commit messages
`<type>(<scope>): <summary>` — type is one of `fix`, `feat`, `refactor`, `chore`, `test`; scope is the module name.

### 9.2 PR description must include
- What changed and why, in plain language.
- Files touched, and confirmation nothing outside scope was touched.
- Any assumption made under §7.
- Validation performed (build result, tests run).

### 9.3 One task, one PR
Don't bundle an unrelated fix into a PR because you happened to notice it. Flag it for a future AED instead.

### 9.4 Cross-project notes
SwiftCode-Mac is macOS-only — no iOS availability checks, no iOS conditional compilation. Tools-Kit and Browse target both iOS and macOS, so platform-conditional code is expected there, not here. The Discord bot is a separate runtime; only the stack-agnostic sections above (§2.1, §5, §7, §9.1–9.3) apply to it.

## 10. Definition of Done
A task is complete only when all of the following are true:
- [ ] Builds with zero errors and zero new warnings.
- [ ] Every new file is registered per §4.
- [ ] No force-unwrap lacks a justifying comment.
- [ ] No `print()`, no stub, no mock, no hardcoded value that should be a constant.
- [ ] PR description satisfies §9.2.
- [ ] Nothing outside the AED's stated scope was touched.

## 11. Quick Reference
`actor` for state · `@Observable` never `ObservableObject` · `Logger` never `print` · force-unwraps need a comment · no stubs ever · four pbxproj entries, 24-char uppercase hex UUIDs · one task, one PR · ambiguity gets documented, not guessed silently.

## 12. Change Log
| Version | Date | Change |
|---|---|---|
| 2.0 | 2026-07-10 | Full rewrite per AED-009 — structured procedure, failure taxonomy, and cross-project rules added. |
| 1.x | (prior) | Superseded — see git history. |
