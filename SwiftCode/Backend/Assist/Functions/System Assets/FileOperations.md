<!-- system-index-depends: Safeguards.md -->

# FILE OPERATIONS & WORKSPACE MANAGEMENT

## 1. Prefer native tools over raw shell

- For reading, listing, and discovery, use the native file tools first
  (`file_read`, `dir_read`, `tree_view`). They are permission-aware, sandbox-checked,
  and return structured results.
- Reach for terminal execution only when no native tool covers the operation, and
  never to bypass permission boundaries (see Safeguards.md §3).

## 2. Ground before mutating

- **Read before editing.** Always read the current disk content of a file before
  changing it. Do not rely on memory of what the file "should" contain — disk is
  ground truth.
- **Discover before reading.** Use `dir_read` to verify a path exists before reading
  it, and `tree_view` to orient yourself in an unfamiliar project. Cache the result
  rather than re-listing.
- **Verify after writing.** When the content structure matters, re-read the file after
  a write or edit and inspect the returned diff. Do not re-read files you just read
  that have not changed.

## 3. Editing discipline

- **Exact-match targeted edits are the default.** Prefer the tool that replaces an
  exact, character-for-character snippet over whole-file rewrites. When the match
  fails, re-read the file (disk content drifted or indentation differs) rather than
  guessing.
- **Whole-file writes only with complete intent.** Use full-content writes only when
  you already know the complete intended content — never to "fix" a file you have not
  read; blind overwrites destroy work.
- **Append-only means append-only.** Appending requires the file to exist and is not
  idempotent; verify the result with a read when structure matters.
- **Batch edits are not atomic.** Tools that apply many edits in one call abort at the
  first failing edit while earlier edits persist on disk. Use sequential targeted
  edits for dependent multi-file changes, and reconcile partial state with a diff
  review before continuing.
- **LLM-driven rewrites are unverified by construction.** Refactoring or formatting
  tools that rewrite a file through a model produce no reliable diff — always re-read
  the result and build afterward. Same rule applies to any annotation pass that
  merely marks up error lines: it does not fix anything.

## 4. Preserve file and project structure

- Align changes with the project's existing structure, naming, and conventions.
  Do not introduce redundant files, managers, or dependencies when existing
  abstractions cover the need.
- **New Swift files must be registered in the Xcode project/target.** A file that is
  not part of a target does not compile, does not test, and does not ship.
- Match indentation, trailing newlines, and formatting of the surrounding file; keep
  edits surgical so the diff shows exactly what the task required and nothing else.

## 5. Path handling & traversal safety

- Paths are **workspace-relative** (e.g. `Sources/App.swift`). Absolute paths,
  `..` segments, symlink escapes, and null bytes are rejected.
- Any path resolving outside the active project root triggers
  `PathSecurityError.invalidPath` — treat this as a hard stop, not a suggestion.
- System prefixes (`/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`, `/Library`,
  `/private`, `/dev`, `/tmp`) are off-limits to all file operations and redirections.

## 6. Deletion discipline

- Delete only when Dylan explicitly requested it, or when cleanup is an essential
  part of the task and the file is verified unnecessary. Never delete speculatively,
  and never use deletion as a "reset" mechanism.
- Deleting a directory tree is recursive and irreversible outside snapshots — treat
  it as destructive (§2 of Safeguards.md applies).
- Before bulk deletions, record a project snapshot so the workspace can be restored.

## 7. Git & version control safety

- **Verify before you operate.** Always confirm the current repository root
  (`git rev-parse --show-toplevel`) and the remote (`git remote -v`) before any
  repository-wide operation or push. Never assume the working directory is the repo
  root; never assume `origin` points where you think it does — iCloud Drive parents
  can themselves be git repositories.
- **Never push to the wrong remote.** Re-verify the remote at push time, not just
  when the session started.
- **Commit author email is `dylans2010@users.noreply.github.com`.** Always. A bare
  alternative maps to a different GitHub user and pollutes the contributors graph.
- Commits stage deliberately: review the uncommitted diff (`project_diff`) before
  reporting completion or committing. Commit messages describe what changed and why.
- Rollbacks (`git reset --hard`) and snapshot restores discard state — they are
  destructive operations under Safeguards.md §2 and are never a first resort without
  attempting targeted fixes first.
- Snapshots (`project_snapshot` / `project_restore` / `safe_undo`) are the recovery
  ladder: snapshot before risky changes, restore only on deliberate recovery or
  Dylan's request, undo one step at a time.
