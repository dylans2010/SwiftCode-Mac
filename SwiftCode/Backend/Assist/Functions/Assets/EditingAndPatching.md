# CODE EDITING, PATCHING & MUTATION

This asset specifies precise code modification tools, indentation preservation rules, patch validation strategies, and conflict handling.

---

#### `code_replace`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Targeted edits to an existing file when you know the exact snippet to change. This is the **default and preferred editing tool** in SwiftCode Assist.  
**When NOT to use:** For whole-file rewrites (use `file_write`); with an approximate target — the match must be exact character-for-character.  
**Parameters:**  
- `path` (string, required) — workspace-relative path to the target file.  
- `target` (string, required) — exact existing snippet to replace, including exact whitespace and indentation.  
- `replacement` (string, required) — replacement snippet to substitute into the file.  
- `allowMultiple` (boolean, optional, default false) — set true to replace all instances across the file if multiple occur.  
**Returns:** Success message, unified diff, `filesChanged`, before/after content, and `suggestedNextActions`.  
**Errors:**  
- Target not found: Re-read the file via `file_read` — disk content may have changed or indentation may differ.  
- Target matched multiple times: Pass `allowMultiple: true` only if replacing all matches is genuinely intended.  
- Stale-file conflict: Re-read and retry with verified fresh context.  
**After the result:** Inspect the diff; run `project_build` when the task needs compiler validation.

---

#### `code_multi_edit`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Applying many small edits across files in a single tool invocation.  
**When NOT to use:** When edits must be strictly atomic — this tool is **not atomic**: it aborts at the first failing edit while preceding edits persist on disk. Prefer sequential `code_replace` calls for dependent multi-file changes.  
**Parameters:**  
- `edits` (array, required) — list of edit descriptors. Each element requires a `path` string; `content`, `search`, and `replace` strings control per-edit behavior.  
**Returns:** `files` — comma-joined list of modified paths.  
**Errors:** Aborts on the first failing edit; inspect disk state using `project_diff` to reconcile partial modifications.

---

#### `code_refactor`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Requesting an automated model-performed refactoring (extract method, rename symbol, restructure view) when you can describe the intent clearly.  
**When NOT to use:** For deterministic edits you can express exactly in code (use `code_replace`).  
**Parameters:**  
- `path` (string, required) — workspace-relative file path.  
- `action` (string, required) — refactoring instruction describing the desired structural modification.  
**Notes:** Sends the entire file to an LLM engine and rewrites the file with the reply. Output quality may vary; no diff or conflict checking. Always verify by reading the result and building.

---

#### `code_format`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Normalizing whitespace, indentation, and formatting in a file or directory tree.  
**Parameters:**  
- `path` (string, optional, default `"."`) — workspace-relative path to format.  
**Returns:** `formatted_files` count. Only files with modified formatting are rewritten.  
**Notes:** Normalizes tabs to spaces, strips trailing whitespace, collapses extraneous blank lines, and guarantees trailing newline. Idempotent.

---

#### `code_insert`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Inserting a new block of code at a specific line number or relative to an anchor pattern.  
**Parameters:**  
- `path` (string, required) — workspace-relative path.  
- `code` (string, required) — code snippet to insert.  
- `mode` (string, optional: `line`, `before`, `after`, default `"line"`) — insertion strategy.  
- `line` (string, optional, default `"1"`) — 1-based line number (decimal string). Appends past EOF if line exceeds count.  
- `pattern` (string, optional) — anchor pattern string; required for `before` and `after` modes.  
**Notes:** No duplicate-position guard; verify placement with `file_read` when precise positioning matters.

---

#### `code_mutation_engine`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Minimal scoped mutations — replacing a symbol body or exact target text.  
**Parameters:**  
- `path` (string, required) — workspace-relative file path.  
- `replacement` (string, required) — new code snippet.  
- `symbol` or `target` (string, required — at least one must be provided) — target symbol name or literal snippet.  
**Returns:** `bytes_before`, `bytes_after`.  
**Errors:** Path not allowed (permission check); symbol body not found; target not found; no-op guarded.  
**Notes:** Target mode replaces all occurrences. Requires workspace sandbox authorization.

---

#### `patch_application_engine`
**Capability:** File Modification · **Risk:** safeMutation  
**When to use:** Applying a patch block with an integrity check that the original block exists verbatim in the file.  
**Parameters:**  
- `path` (string, required) — workspace-relative file path.  
- `original` (string, required) — exact original code block expected in the file.  
- `updated` (string, required) — updated code block to replace the original.  
**Errors:** Integrity check failed (original block not found) — re-read the file; content has drifted.  
**Notes:** Replaces all occurrences of the original block. Not idempotent across re-runs.
