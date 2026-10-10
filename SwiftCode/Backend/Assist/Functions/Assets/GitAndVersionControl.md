# GIT & VERSION CONTROL MANAGEMENT

This asset defines version control operations, project snapshots, rollbacks, diff inspections, and safe undo workflows.

---

#### `version_control_operator`
**Capability:** Version Control (Git) · **Risk:** potentiallyDestructive  
**When to use:**  
- `action: "status"` or `"diff"`: Read-only inspection of working tree changes.  
- `action: "commit"` or `"branch"`: Creating commits or branches when the task calls for version control checkpoints.  
- `action: "rollback"`: Reverting working tree changes only when deliberate recovery is necessary.  
**Parameters:**  
- `action` (string, optional, default `"status"`) — one of `"status"`, `"commit"`, `"branch"`, `"rollback"`, or `"diff"`.  
- `message` (string, optional) — commit message when `action` is `"commit"`.  
- `name` (string, optional) — branch name when `action` is `"branch"`.  
- `ref` (string, optional, default `"HEAD~1"`) — target ref when `action` is `"rollback"`.  
**Notes:**  
- `"commit"` stages all changes (`git add -A`).  
- `"rollback"` executes `git reset --hard` — **destructive operation**, discards uncommitted disk modifications.  
- macOS only. Exit codes are not checked automatically — read the returned stdout.

---

#### `project_snapshot`
**Capability:** General · **Risk:** safeRead  
**When to use:** Before initiating risky, destructive, or bulk codebase modifications so that `safe_undo` or `project_restore` can restore state if issues occur.  
**Parameters:**  
- `message` (string, optional, default `"Manual Snapshot"`) — descriptive label for the snapshot.  
**Returns:** `snapshot_id` (string UUID) for later restoration.  
**Notes:** Each call records a distinct snapshot. Not idempotent.

---

#### `project_restore`
**Capability:** General · **Risk:** potentiallyDestructive  
**When to use:** Rolling the workspace back to a known-good snapshot when an implementation breaks or on user request.  
**When NOT to use:** As a first resort without attempting targeted fixes; without verifying the snapshot ID.  
**Parameters:**  
- `snapshot_id` (string, required) — snapshot identifier obtained from `project_snapshot` or `project_changelog`.  
**Returns:** Success confirmation. The workspace is overwritten with the contents of the specified snapshot.  
**Errors:** Missing `snapshot_id`; snapshot not found on disk.

---

#### `project_diff`
**Capability:** Version Control (Git) · **Risk:** safeRead  
**When to use:** Reviewing uncommitted working tree changes against Git HEAD before reporting completion or committing.  
**Parameters:** None.  
**Returns:** Branch summary, unified `diff`, `staged_count`, `unstaged_count`, and `suggestedNextActions` (`project_build`, `code_review`).  
**Errors:** Fails when the workspace is not a valid Git repository.

---

#### `project_changelog`
**Capability:** General · **Risk:** safeRead  
**When to use:** Listing all available snapshots to find a `snapshot_id` for `project_restore`, or reviewing recent snapshot history.  
**Parameters:** None.  
**Returns:** `log` lines with timestamps, messages, and snapshot IDs.

---

#### `safe_undo`
**Capability:** General · **Risk:** potentiallyDestructive  
**When to use:** Reverting the most recent agent modification by stepping back one snapshot.  
**When NOT to use:** When fewer than two snapshots exist; as a substitute for precision editing.  
**Parameters:** None.  
**Returns:** `restored_snapshot` ID.  
**Errors:** "At least two snapshots are required to undo." Each call rewinds one snapshot in history.
