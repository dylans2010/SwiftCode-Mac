# FILE OPERATIONS & WORKSPACE MANAGEMENT

This asset defines the authoritative behavioral specifications, parameter requirements, risk postures, and failure recoveries for all file and directory management tools.

---

#### `file_read`
**Capability:** File Reading · **Risk:** safeRead  
**When to use:** You need the actual contents of a known file to answer a technical question or continue an implementation task — because the user referenced it, because another tool identified it, or because implementation requires understanding existing code.  
**When NOT to use:** To check existence (use `dir_read` or `tree_view`); on a file you just read and that has not changed on disk.  
**Parameters:**  
- `path` (string, required) — workspace-relative path to the target file.  
**Returns:** Success message plus `content` containing the complete file text.  
**Errors:** Missing `path`; read failure (missing or unreadable file) — verify the path with `dir_read` first.  
**After the result:** Utilize the returned content directly; do not re-read unless a mutation tool modified the file.

---

#### `file_write`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Creating a new file or replacing the entire content of an existing file when you already know the complete intended content.  
**When NOT to use:** For targeted edits to a large file (use `code_replace`); when you have not read the existing file (overwrites blindly).  
**Parameters:**  
- `path` (string, required) — workspace-relative path; `..` and leading `/` absolute paths rejected.  
- `content` (string, required) — the complete new content to write to the file.  
**Returns:** Created/updated message, unified diff, `filesChanged`, before/after content, and `suggestedNextActions` (`syntax_verify` for Swift, `project_build`).  
**Errors:** Missing params; path security error; write failure.  
**After the result:** Inspect the diff; follow the suggested verification when the task needs it.

---

#### `file_append`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Adding content to the end of an existing file (logs, lists, append-only records).  
**When NOT to use:** To create a file (it requires the file to exist — use `file_create`); to insert at a specific position (use `code_insert`).  
**Parameters:**  
- `path` (string, required) — workspace-relative path of an existing file.  
- `content` (string, required) — the content to append to the end of the file.  
**Returns:** Success message confirming appended bytes.  
**Errors:** Missing params; failure when the file does not exist.  
**Notes:** Read-then-write; not idempotent. Verify with `file_read` afterward when content structure matters.

---

#### `file_delete`
**Capability:** File Modification · **Risk:** potentiallyDestructive  
**When to use:** The user explicitly requested removing a file, or cleanup is an essential part of the task and the file is verified unnecessary.  
**When NOT to use:** Speculatively; as a "reset" mechanism; without verifying the path.  
**Parameters:**  
- `path` (string, required) — workspace-relative path of the file to delete.  
**Returns:** Success message. No recovery data.  
**Errors:** Missing `path`; delete failure.  
**Notes:** Irreversible outside snapshots. Consider `project_snapshot` before bulk deletions.

---

#### `file_move`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Relocating a file within the workspace.  
**When NOT to use:** To rename in place within the same directory (use `file_rename`, clearer intent).  
**Parameters:**  
- `source` (string, required) — workspace-relative source file path.  
- `destination` (string, required) — workspace-relative destination path.  
**Returns:** Success message. The source path ceases to exist — update any stored references.

---

#### `file_copy`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Duplicating a file (templates, backups before risky edits).  
**When NOT to use:** As a substitute for reading (copying does not display content).  
**Parameters:**  
- `source` (string, required) — workspace-relative source file path.  
- `destination` (string, required) — workspace-relative destination path.  
**Returns:** Success message. Source remains unchanged.

---

#### `file_rename`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Renaming a file within its current directory.  
**Parameters:**  
- `oldPath` (string, required) — workspace-relative path of the existing file.  
- `newName` (string, required) — bare new file name, not a path. Stays in the same directory.  
**Returns:** Success message.

---

#### `dir_create`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Ensuring a directory exists before writing files into it.  
**Parameters:**  
- `path` (string, required) — workspace-relative directory path. Missing parents are created automatically.  
**Notes:** Effectively idempotent (no error if it already exists).

---

#### `file_create`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Creating a new file when `file_write`'s blind overwrite is undesirable — this tool refuses to clobber unless asked.  
**When NOT to use:** To overwrite existing files without explicit intent (use `file_write`, or pass `overwrite: true`).  
**Parameters:**  
- `path` (string, required) — workspace-relative path for the new file.  
- `content` (string, optional) — initial content for the file.  
- `overwrite` (boolean, optional, default false) — set true to overwrite if file already exists.  
**Returns:** `path` and `bytes`. Parent directories are created automatically.  
**Errors:** Blank path; "File already exists" error unless `overwrite: true`.

---

#### `code_generate`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Scaffolding a new Swift file from a known template (`swift_struct`, `swift_class`, `swiftui_view`, `test`).  
**When NOT to use:** For arbitrary custom content (use `file_create`); when the target file already exists (no overwrite option).  
**Parameters:**  
- `path` (string, required) — workspace-relative path; must not already exist.  
- `template` (string, required) — template name (`swift_struct`, `swift_class`, `swiftui_view`, `test`).  
- `module` (string, optional, default `"SwiftCode"`) — used only by the test template for testable imports.  
**Notes:** Does not create parent directories. File name is derived from the path basename.

---

#### `dir_delete`
**Capability:** File Modification · **Risk:** potentiallyDestructive  
**When to use:** Removing an entire directory tree the task explicitly requires gone.  
**When NOT to use:** Almost always prefer `file_delete` for single files; never delete directories speculatively.  
**Parameters:**  
- `path` (string, required) — workspace-relative directory path to delete.  
**Notes:** Recursive `FileManager.removeItem`; irreversible. Tolerates a missing path (succeeds silently).

---

#### `dir_read`
**Capability:** File Reading · **Risk:** safeRead  
**When to use:** Listing a directory's entries — discovery before reading, verifying a path exists.  
**When NOT to use:** To see file contents (use `file_read`); for a whole-tree overview (use `tree_view`).  
**Parameters:**  
- `path` (string, required) — workspace-relative directory path to list.  
**Returns:** `contents` — newline-joined entry names.

---

#### `tree_view`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Getting oriented in an unfamiliar project — a compact structural overview.  
**When NOT to use:** When you already know the layout; repeatedly (cache the result).  
**Parameters:**  
- `maxDepth` (string, optional, default `"3"`) — decimal string; unparseable values fall back to 3.  
**Returns:** `tree` — indented directory listing. Unreadable subdirectories appear inline as warnings, not failures.

---

### Cloud Toolkit File Tools Reference

#### `view_file`
- **Capability:** Cloud File Inspection · **Risk:** safeRead
- **Parameters:** `file_path` (string, required) — relative path from workspace root; `offset` (integer, optional); `length` (integer, optional).
- **Usage:** Reads file contents from the workspace.

#### `create_file`
- **Capability:** Cloud File Creation · **Risk:** safeMutation
- **Parameters:** `file_path` (string, required) — relative path; `content` (string, required) — full content to write.
- **Usage:** Creates a new file in the workspace.

#### `edit_file`
- **Capability:** Cloud File Modification · **Risk:** safeMutation
- **Parameters:** `file_path` (string, required) — relative path; `edits` (array of objects with `old_text` and `new_text`).
- **Usage:** Applies precise localized edits to existing files.

#### `list_directory`
- **Capability:** Cloud Directory Listing · **Risk:** safeRead
- **Parameters:** `directory_path` (string, optional, defaults to `.`) — relative path to list.
- **Usage:** Discovers files and folder structures in cloud environments.
