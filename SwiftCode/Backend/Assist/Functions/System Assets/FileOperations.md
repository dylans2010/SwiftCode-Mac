<!-- system-index-depends: Safeguards.md -->

# FILE OPERATIONS & WORKSPACE MANAGEMENT

File system modification protocols, targeted code edits, directory operations, Xcode project file registration, and git workspace safety. This document governs **how to inspect, edit, rename, move, and patch files safely**; `Safeguards.md` defines destructive operation guardrails.

---

## 1. Prefer Native Tools Over Raw Shell

- For reading, listing, and discovery, use the native file tools first (`file_read`, `dir_read`, `tree_view`). They are permission-aware, sandbox-checked, and return structured results.
- Reach for terminal execution (`use_terminal`) only when no native tool covers the operation, and never to bypass permission boundaries (see `Safeguards.md` §3).

---

## 2. Ground Before Mutating

- **Read before editing.** Always read the current disk content of a file (`file_read`) before changing it. Do not rely on memory of what the file "should" contain — disk is ground truth.
- **Discover before reading.** Use `dir_read` to verify a path exists before reading it, and `tree_view` to orient yourself in an unfamiliar project. Cache the result rather than re-listing.
- **Verify after writing.** When the content structure matters, re-read the file after a write or edit and inspect the returned diff. Do not re-read files you just read that have not changed.

---

## 3. Editing Discipline & Tool Selection

- **Exact-match targeted edits are the default.** Prefer `code_replace` or `code_mutation_engine` (replaces exact, character-for-character snippet) over whole-file rewrites. When the match fails, re-read the file with `file_read` (disk content drifted or indentation differs) rather than guessing.
- **Coordinated Multi-File Edits (`code_multi_edit`):** Perform multiple string replacement edits in a single file in one pass.
- **Patch Application Engine (`patch_application_engine`):** Apply unified diff patches with verbatim target block integrity checks. Replaces all matching blocks.
- **Whole-file writes (`file_write`) only with complete intent.** Use full-content writes only when you already know the complete intended content — never to "fix" a file you have not read; blind overwrites destroy work.
- **Append-only (`file_append`) means append-only.** Appending requires the file to exist and is not idempotent; verify the result with a read when structure matters.
- **Batch edits are not atomic.** Tools that apply many edits in one call abort at the first failing edit while earlier edits persist on disk. Use sequential targeted edits for dependent multi-file changes, and reconcile partial state with a diff review before continuing.
- **LLM-driven rewrites are unverified by construction.** Refactoring or formatting tools that rewrite a file through a model produce no reliable diff — always re-read the result and build (`project_build`) afterward. Same rule applies to any annotation pass (`automated_repair_engine`) that merely marks up error lines: it does not fix anything.

---

## 4. Preserve File Structure & Xcode Project Registration (`project_mutation_controller`)

- Align changes with the project's existing structure, naming, and conventions. Do not introduce redundant files, managers, or dependencies when existing abstractions cover the need.
- **New Swift files must be registered in the Xcode project/target.** Use `project_mutation_controller` (`action: "add"`) to register newly created `.swift` files in the USER's project `project.pbxproj` (resolved from the workspace root — never SwiftCode's own bundle). A file that is not part of a target does not compile, does not test, and does not ship. Prefer `project_mutation_controller` over editing `project.pbxproj` with text replace tools.
- Match indentation, trailing newlines, and formatting of the surrounding file; keep edits surgical so the diff shows exactly what the task required and nothing else.

---

## 5. Path Handling & Traversal Safety

- Paths are **workspace-relative** (e.g. `Sources/App.swift`). Absolute paths, `..` segments, symlink escapes, and null bytes are rejected.
- Any path resolving outside the active project root triggers `PathSecurityError.invalidPath` — treat this as a hard stop, not a suggestion.
- System prefixes (`/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`, `/Library`, `/private`, `/dev`, `/tmp`) are off-limits to all file operations and redirections.

---

## 6. Deletion Discipline

- Delete (`file_delete`, `dir_delete`) only when explicitly requested by the user, or when cleanup is an essential part of the task and the file is verified unnecessary. Never delete speculatively, and never use deletion as a "reset" mechanism.
- Deleting a directory tree (`dir_delete`) is recursive and irreversible outside snapshots — treat it as destructive (§2 of `Safeguards.md` applies).
- Before bulk deletions, record a project snapshot (`project_snapshot`) so the workspace can be restored (`project_restore` / `safe_undo`).

---

## 7. Git & Version Control Safety (`version_control_operator`)

- **Verify before you operate.** Always confirm current repository root (`version_control_operator` `action: "status"`) and remote (`git remote -v`) before any repository-wide operation or push. Never assume working directory is repo root; never assume `origin` points where you think it does — iCloud Drive parents can themselves be git repositories.
- **Never push to the wrong remote.** Re-verify the remote at push time, not just when the session started.
- **Commit Author Email:** Always use `dylans2010@users.noreply.github.com`. A bare alternative maps to a different GitHub user and pollutes the contributors graph.
- Commits stage deliberately: `version_control_operator` `action: "commit"` stages all changes (`git add -A`). Review uncommitted diff (`project_diff`) before committing. Excludes `.artifact.md` and `app_summary.md` (`AssistGitManager`). Commit messages describe what changed and why.
- Rollbacks (`version_control_operator` `action: "rollback"` / `git reset --hard`) and snapshot restores discard state — they are destructive operations under `Safeguards.md` §2 and are never a first resort without attempting targeted fixes first.
- Snapshots (`project_snapshot` / `project_restore` / `safe_undo`) are the recovery ladder: snapshot before risky changes, restore only on deliberate recovery or user request, undo one step at a time.
