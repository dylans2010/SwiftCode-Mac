# Assist file-writing tools — shared behaviour

SwiftCode modules: `SwiftCodeMCP` (the MCP server and its tools; the Wave 2 port
registers the tools here).

This spec covers the behaviour shared by the 24 Wave 2 file-writing
tools catalogued in `assist-tool-catalogue.md` (§27–§52): which path
resolver each tool uses, atomicity, backups, directory creation,
move/copy/rename/delete semantics, plist and CSV/JSON conversions,
regex replacement, code formatting, code generation, and the full
error-case table. The catalogue is the source of truth for each
tool's ID, schema, and output shape; `assist-approval-model.md` is
the source of truth for how writes are gated; this spec is the
source of truth for how those tools behave once the gate has let
them through.

One tool in this wave does not write: `generate_file_checksum`
computes hashes only. It is specified here (§3.4) because the
subsystem map assigned it to this wave, but its `writes` flag is
`false` and the approval model does not apply to it.

## 1. Terms

- **Workspace root**: the root folder of the currently open project /
  workspace, as in Wave 1 (`assist-file-tools.md` §1). If no project
  is open, there is no workspace root and every path-resolving tool
  must fail closed.
- **Session working directory (cwd)**: the per-session directory
  established by `dir_cd`, reported by `dir_pwd`. Defaults to the
  workspace root. Only the session-aware resolver (§2.1) observes
  it; the strict resolvers (§2.2, §2.3) resolve plain relative
  paths against the workspace root regardless of `dir_cd`.
- **Workspace-relative path**: a path relative to the workspace root,
  e.g. `Sources/App.swift`. `"."` means the workspace root (or the
  session working directory, depending on the resolver — see §2).
- **Structured data**: the string-to-string map returned with a
  successful result. All values are strings; see
  `assist-tool-catalogue.md` §1.1. A tool that returns no structured
  data returns no `data` at all (not an empty map).
- **Atomic write**: a write performed through a temporary file plus
  rename, so a reader never sees a half-written file and a crash
  mid-write leaves either the old content or the new content, never
  a mixture. In Legacy this is `String.write(to:atomically: true)`
  / `Data.write(to:options: .atomic)`.
- **Legacy-only envelope fields**: `duration`,
  `suggestedNextActions`, `beforeContent`, `afterContent` are set by
  some Legacy tools but have no equivalent in SwiftCode's
  `MCPToolResult` and are dropped by the port. The unified diff
  survives as `data["diff"]` (see §8.4).

## 2. Path-safety rules

There are four path-resolution behaviours in this wave. The SwiftCode
port must preserve which tool uses which — they differ observably,
and unifying them would change behaviour. (Wave 1's §2 describes
the same resolvers for the read tools; this section states the
Wave 2 assignment.)

### 2.1 The session-aware resolver (`AssistFileSystem.resolve`)

Used by: `file_write`, `file_create`, `file_append`, `file_delete`,
`file_move`, `file_copy`, `file_rename`, `dir_create`, `dir_delete`,
`code_generate`, `code_insert`, `code_multi_edit`,
`code_refactor`, and (for its writes) `code_format`.

- Plain relative paths resolve against the **session working
  directory** (so `dir_cd` affects them).
- A path with a leading `/` resolves against the **workspace root**,
  not the filesystem root: the leading slashes are stripped and the
  remainder is treated as workspace-relative. A path that is exactly
  the workspace root, or starts with the workspace root plus `/`, is
  also accepted and treated the same way.
- `..` components are resolved normally (`..` moves to the parent)
  and are **not** rejected as text. The containment check happens
  after resolution: the resolved path (with symlinks resolved in
  the longest existing ancestor) must equal the workspace root or
  lie under it, otherwise the call fails with
  `Security Error: Path traversal outside workspace bounds is forbidden: <path>`.
- Symlinks in an existing parent are resolved before the containment
  check, so a symlink inside the workspace that points outside it
  is caught even when the leaf itself does not exist yet.
- The workspace root itself is canonicalised (symlinks resolved)
  before comparison.
- Fail-closed when the workspace root is `/`: resolution throws
  `No active project: workspace root is unavailable. Open a project first.`
- Narrow carve-out in Legacy: paths exactly equal to
  `/tmp/swiftcode/scripts` or under `/tmp/swiftcode/scripts/` are
  returned unchanged. **SwiftCode does not keep this carve-out** — see
  `assist-approval-model.md` §7.2. In SwiftCode those paths are outside
  the workspace and are refused like any other outside path.
- The resolved path is returned standardised.

### 2.2 The strict per-tool resolver (`resolveWorkspaceDataMutationURL`)

Used by: `format_json_file`, `csv_to_json`, `json_to_csv`,
`plist_to_json`, `json_to_plist`, `batch_rename_files` (for its
`directory` argument).

- The raw string is trimmed of surrounding whitespace first.
- Rejected outright (the resolver returns "no URL", and the tool
  reports the path as outside the workspace): an empty string, a
  string containing a NUL byte, a string starting with `~`, and a
  string containing `..` **anywhere** — even a legitimate-looking
  `a/../b`. There is no `..` resolution here; `..` is a textual
  rejection.
- A path with a leading `/` is taken as an absolute filesystem path
  (standardised, symlinks **not** resolved); a relative path is
  appended to the workspace root. Either way the result must equal
  the workspace root or lie under it, otherwise it is rejected.
- Relative paths resolve against the **workspace root, not the
  session working directory**. These tools are unaffected by
  `dir_cd`.
- The standard failure message is
  `Path is outside the workspace: <raw>` (with per-tool variants:
  `csv_to_json` / `json_to_csv` / `plist_to_json` / `json_to_plist`
  use `Destination path is outside the workspace: <raw>` for a
  rejected destination; `batch_rename_files` uses
  `Directory path is outside the workspace: <raw>`).
- Symlinks are standardised but **not** resolved by this resolver;
  a symlink inside the workspace that points outside it is
  therefore followed by the tools that use it. This is the known
  Legacy inconsistency already recorded in Wave 1
  (`assist-file-tools.md` §2.6) — preserved here, not silently
  fixed.

### 2.3 The private strict resolver (`plist_edit`'s `resolvePath`)

Used by: `plist_edit` only.

- Same shape as §2.2 (trim; reject empty and any `..`; leading-`/`
  absolute must be under the root; relative appended to the root;
  relative resolves against the workspace root, not the session
  working directory), but it is a private copy in the tool file,
  and its failure message differs: the tool reports
  `Invalid path '<raw>': must be inside the workspace and must not contain '..'.`
- It does not explicitly reject a leading `~` or a NUL byte as
  text; a `~` is treated as an ordinary relative component (a
  literal `~` directory under the root, which in practice does not
  exist). Preserve this difference: do not import §2.2's `~`/NUL
  rejections into `plist_edit`.

### 2.4 The inline checks in `file_write` and `code_replace`

`file_write` and `code_replace` do their own traversal check
**before** calling the session filesystem, in addition to the
§2.1 resolver:

- The workspace-root prefix is stripped from the raw path, then
  leading `/` characters are stripped.
- If the remaining path contains `..` anywhere, the call fails
  with
  `Path security error: Relative path traversal ('..') is prohibited for safety. Path: '<path>'`
  (`file_write`: error code `permissionDenied`; `code_replace`:
  no code). This rejects even an in-workspace `a/../b`.
- In Legacy, a path with the prefix `/tmp/swiftcode/scripts` skips
  this check entirely (and the scripts directory is created on
  demand). **SwiftCode does not keep this** — see
  `assist-approval-model.md` §7.2. Note also that Legacy's inline
  prefix check has **no `/` boundary** (unlike the resolver's
  carve-out in §2.1): in Legacy, `/tmp/swiftcode/scripts-evil`
  would have passed the inline check in these two tools. That
  inconsistency dies with the carve-out; do not reproduce it.
- No other Wave 2 tool has an inline check. `file_create`,
  `file_append`, and the rest rely on the §2.1 resolver alone.

### 2.5 The tools with no resolver at all

- `code_format` resolves its target with
  `AssistToolingSupport.resolvePath`, which **clamps** instead of
  failing: a path that would escape the workspace (via `..` or an
  absolute path) is silently replaced with the workspace root
  itself. An empty path defaults to `"."`. The tool therefore
  never reports an outside-workspace error; given an escaping
  path it formats the workspace root (see §5.6). The SwiftCode port
  must preserve this clamping behaviour and record it as a known
  Legacy quirk — it must not silently upgrade it to a failure,
  and it must not silently widen it. (Its writes still go through
  the session filesystem, §2.1, so a write outside the workspace
  is impossible even when the read side clamped.)
- `regex_replace_in_files` takes no path at all: it enumerates
  from the workspace root directly (`FileManager.enumerator` at
  the root, skipping hidden files and package descendants). It is
  contained by construction. Its writes go directly to the
  enumerated files, bypassing the session filesystem (§4.2).

### 2.6 Tilde

A leading `~` is rejected by the §2.2 resolver and is never
expanded to a home directory by any tool in this wave. The
session-aware resolver (§2.1) does not special-case `~` either:
it is treated as an ordinary relative path component, so `~/x`
resolves to a literal `~` directory under the working directory,
which in practice does not exist. `plist_edit` (§2.3) treats `~`
the same way.

## 3. Which resolver each tool uses

| Tool | Resolver | `dir_cd` affects it? |
|---|---|---|
| `file_write` | §2.1 session-aware + §2.4 inline `..` check | Yes |
| `file_create` | §2.1 session-aware | Yes |
| `file_append` | §2.1 session-aware | Yes |
| `file_delete` | §2.1 session-aware | Yes |
| `file_move` | §2.1 session-aware (source and destination) | Yes |
| `file_copy` | §2.1 session-aware (source and destination) | Yes |
| `file_rename` | §2.1 session-aware (old path; new path built in the same directory) | Yes |
| `dir_create` | §2.1 session-aware | Yes |
| `dir_delete` | §2.1 session-aware | Yes |
| `code_generate` | §2.1 session-aware | Yes |
| `code_insert` | §2.1 session-aware | Yes |
| `code_multi_edit` | §2.1 session-aware (each edit's path) | Yes |
| `code_refactor` | §2.1 session-aware | Yes |
| `code_replace` | §2.1 session-aware + §2.4 inline `..` check | Yes |
| `code_format` | §2.5 clamping resolver for the target; §2.1 for its writes | Target: no (clamped to root); writes: via §2.1 |
| `regex_replace_in_files` | §2.5 none (enumerates from the workspace root) | No (no path argument) |
| `plist_edit` | §2.3 private strict resolver | No |
| `format_json_file` | §2.2 strict resolver | No |
| `csv_to_json` | §2.2 strict resolver (source and destination) | No |
| `json_to_csv` | §2.2 strict resolver (source and destination) | No |
| `plist_to_json` | §2.2 strict resolver (source and destination) | No |
| `json_to_plist` | §2.2 strict resolver (source and destination) | No |
| `batch_rename_files` | §2.2 strict resolver (directory) | No |
| `generate_file_checksum` | Strict data-inspection resolver (same shape as §2.2; see §3.4) | No |

## 4. Atomicity, backups, and directory creation

### 4.1 Atomicity — per tool

Legacy text writes through the session filesystem
(`AssistFileSystem.writeFile`) are atomic: the parent directory is
created if missing, then the content is written with
`String.write(to:atomically: true)` (temporary file + rename).
Conversions and `plist_edit` write with `Data.write(to:options:
.atomic)`, which is the same mechanism. Nothing in this wave does
a non-atomic text write.

| Tool | Atomic? | Mechanism |
|---|---|---|
| `file_write`, `file_create`, `file_append`, `code_insert`, `code_replace`, `code_multi_edit`, `code_refactor`, `code_generate`, `code_format` (changed files) | Yes, per file | Session-filesystem write (temp + rename). |
| `format_json_file`, `csv_to_json`, `json_to_csv`, `plist_to_json`, `json_to_plist`, `plist_edit` (set/delete) | Yes, per file | `Data.write(..., .atomic)`. |
| `regex_replace_in_files` | Yes, per file | `String.write(..., atomically: true)` per matched file. A failure writing one file is swallowed (`try?`) — the file keeps its old content and the tool still reports success for the others (see §5.5). |
| `file_copy` | No | `FileManager.copyItem`: a byte copy, not atomic; an interrupted copy can leave a partial destination. |
| `file_move`, `file_rename`, `batch_rename_files` (per rename) | Rename only | `FileManager.moveItem`: a rename within one volume; not a copy-then-delete. Across volumes the platform may copy-then-delete, which is not atomic — Legacy does not handle that case. |
| `file_delete`, `dir_delete` | n/a | `FileManager.removeItem`: immediate, permanent. |
| `dir_create` | n/a | `FileManager.createDirectory` with intermediates. |
| `generate_file_checksum` | n/a | Writes nothing. |

Batch atomicity: no multi-file tool in this wave is atomic as a
batch. `code_multi_edit` says so in its own schema description
("Not atomic: earlier edits persist if a later one fails"). The
same holds for `code_format`, `regex_replace_in_files`, and
`batch_rename_files`, which apply file by file and stop or continue
per their own rules (§5). The SwiftCode port must not add a
transaction or rollback: the observable behaviour is "earlier
files stay changed".

### 4.2 No auto-backup on overwrite

Legacy creates **no backup** when a Wave 2 tool overwrites a file.
Overwriting is silent and in place:

- `file_write` overwrites unconditionally (create or replace, no
  flag, no warning).
- `file_create` refuses an existing file unless `overwrite: true`
  — but when `overwrite: true` is given it overwrites with no
  backup.
- `code_generate` refuses an existing target file outright
  (`Target file already exists: <path>`); there is no overwrite
  option at all.
- `format_json_file` rewrites the file in place.
- The conversion tools (`csv_to_json`, `json_to_csv`,
  `plist_to_json`, `json_to_plist`) overwrite an existing
  destination file silently.
- `plist_edit` set/delete rewrite the plist in place.
- `code_replace` / `code_insert` / `code_multi_edit` /
  `code_refactor` / `code_format` / `regex_replace_in_files`
  rewrite in place.

Backups exist in Legacy only as the separate, explicit `file_backup`
tool (Wave 1). The SwiftCode port must not add an automatic `.bak`,
snapshot, or trash step to any Wave 2 tool: an unrequested backup
is a second write the approval gate never saw (see
`assist-approval-model.md` §5.3). A caller that wants a backup
calls `file_backup` first.

### 4.3 Directory creation — which tools create missing parents

| Tool | Creates missing parent directories? |
|---|---|
| `file_write` | Yes — the session-filesystem write creates them. |
| `file_create` | Yes — explicitly (when the parent is non-empty, not `"."`, and missing) and again via the write itself. |
| `file_append` | Effectively no: the file must already exist to be read first, so there is no missing-parent case. (The write itself would create parents, but it is never reached for a missing file.) |
| `code_generate` | Yes — via the session-filesystem write. |
| `code_insert`, `code_replace`, `code_multi_edit`, `code_refactor` | Moot: the target file must already exist. (The write itself would create parents.) |
| `code_format` | Moot: formatted files already exist. |
| `format_json_file` | No — the file must exist; the write is in place. |
| `csv_to_json`, `json_to_csv`, `plist_to_json`, `json_to_plist` | Yes for the **destination**: the destination's parent is created with intermediates if missing (a failure to create it is swallowed — `try?` — and the subsequent write then fails). |
| `plist_edit` | No — the file must exist; the write is in place. |
| `file_copy`, `file_move` | **No** — the destination's parent must already exist; a missing parent makes the copy/move fail (`Failed to copy file: ...` / `Failed to move file: ...`). |
| `file_rename` | n/a — the new name stays in the same directory. |
| `batch_rename_files` | n/a — renames stay in the same directory. |
| `dir_create` | Yes — creates the directory including all missing parents. |
| `regex_replace_in_files` | n/a — matched files already exist. |

### 4.4 `file_create` vs `file_write` overwrite behaviour

These two tools overlap and differ in exactly one respect — the
existing-file rule:

- `file_write`: no overwrite flag; an existing file is replaced
  silently. `is_new` in the data is `"true"` only when the file
  did not exist before the call.
- `file_create`: `overwrite` defaults to `false`; an existing file
  with `overwrite` false (or absent) fails with
  `File already exists at <path>. Set overwrite=true to replace it.`
  (error code `invalidInput`). With `overwrite: true` it replaces
  the file, and `is_new` is still reported as `"true"` in the data
  (Legacy hardcodes it) even though the file existed. Preserve
  that quirk: `is_new: "true"` for `file_create` does not mean the
  file was new.
- `code_generate` is stricter than both: it refuses an existing
  file with no overwrite option.

## 5. Per-tool behaviour

### 5.1 Text writes: `file_write`, `file_create`, `file_append`

- `file_write` writes `content` as the file's complete new
  content. It accepts the parameter aliases `filePath` /
  `file_path` for `path` and `fileContent` / `file_content` /
  `code` for `content`. Missing `path` or `content` fails with
  `Missing required parameters: 'path' and 'content' are mandatory.`
  (code `missingArgument`). Note the aliases accept any type
  confusion silently: a non-string value for either parameter is
  treated as missing. The output is
  `Created new file: <path> (<N> lines)` or
  `Updated existing file: <path> (<N> lines)`, where `<N>` is the
  count of `content.components(separatedBy: .newlines)` — a
  trailing newline therefore counts as an extra empty line. The
  data carries `diff` (unified diff, Myers algorithm, 3 context
  lines — see §8.4), `path`, and `is_new`. `filesChanged` is
  `[path]`. Legacy also auto-registers a new file in the
  `.pbxproj` and streams the edit through `LiveDiffStreamer`; the
  SwiftCode port does neither (see `assist-approval-model.md` §7.4).
- `file_create` writes `content` (default `""`) as a new file.
  Only `path` is required; a missing or blank `path` fails with
  `Missing required parameter: path` (code `missingArgument`).
  `content` defaults to the empty string when absent; `overwrite`
  defaults to `false`. The output is
  `Created file at <path> (<N> lines)` with the same newline
  counting as `file_write`. The data carries `path`, `bytes`
  (UTF-8 byte count of `content`), `diff` (unified diff from empty
  to `content`), and `is_new` (always `"true"`, §4.4).
  `filesChanged` is `[path]`.
- `file_append` reads the whole file as UTF-8, then writes
  `original + content` back as the whole file (it is a
  read-modify-write, not an `O_APPEND` append — a concurrent
  writer between the read and the write is silently overwritten).
  The file must already exist: a missing file fails with
  `Failed to append to file at <path>: <system error>`. Missing
  `path` / `content` fail with `Missing required parameter: path`
  / `Missing required parameter: content` (no codes). The output
  is `Successfully appended to file: <path>`. It returns **no**
  structured data and **no** `filesChanged`, even though the file
  changed — preserve that Legacy quirk, do not "fix" it by adding
  data. The append is verbatim: no newline is added or normalised
  between the old content and the appended content.

### 5.2 Move / copy / rename / delete

- `file_move` (`source`, `destination`, both required, no codes
  on failure) moves a file. The destination must not already
  exist: the session filesystem refuses with
  `Destination already exists: <destination>. Delete it first or choose another destination.`
  (wrapped by the tool as
  `Failed to move file: Destination already exists: <destination>. Delete it first or choose another destination.`).
  The destination is **never deleted before the move**, so a
  failed move cannot destroy the previous destination content.
  The destination's parent must already exist (§4.3). The source
  must exist; a missing source fails with
  `Failed to move file: <system error>`. The move works for
  directories as well as files (the filesystem layer does not
  check file-vs-directory) — the name says "file" but the
  behaviour does not enforce it; preserve this. Cross-directory
  moves are allowed (the destination is a full path, not a name).
  Success: `Successfully moved file from <source> to
  <destination>`; no data, no `filesChanged`.
- `file_copy` is identical to `file_move` except that the source
  remains: same existing-destination refusal, same
  missing-parent failure, same directory tolerance, same
  cross-directory allowance. Success:
  `Successfully copied file from <source> to <destination>`; no
  data, no `filesChanged`. Legacy auto-registers the destination
  in the `.pbxproj`; the SwiftCode port does not (§7.4 of the approval
  model).
- `file_rename` (`oldPath`, `newName`, both required, no codes)
  renames within the same directory. `newName` must be a single
  path component: it is rejected when empty, containing `/`,
  containing `..`, containing a NUL byte, or equal to `".`, with
  `Invalid newName '<newName>': must be a single file name, not a path.`
  (note the Legacy message's trailing `".` — reproduce it
  verbatim). The new path is built as
  `oldPath.deletingLastPathComponent() + newName`; a rename to the
  current name is a failure, not a no-op:
  `Rename is a no-op: newName matches the current file name.`
  The move itself refuses an existing destination (same message as
  `file_move`). Success: `Successfully renamed file to: <newName>`
  with data `path` = the new path and `filesChanged` = `[newPath]`.
  Note the data key is `path`, not `newPath`, and the message
  names only the new name, not the full path.
- `file_delete` (`path` required) deletes a file permanently.
  Missing `path`: `Missing required parameter: path` (code
  `missingArgument`). A missing file is a failure, not a silent
  success: `No file at <path> — nothing to delete.` (code
  `notFound`). Any other failure:
  `Failed to delete file at <path>: <system error>` (code
  `executionFailed`). **Directory behaviour (Legacy, preserved):**
  Legacy's filesystem layer deletes whatever is at the path —
  `FileManager.removeItem` removes a directory recursively — so
  `file_delete` on a directory deletes the whole directory tree.
  The SwiftCode port preserves this (coordinator decision, Wave 2:
  Legacy behaviour wins over the tightening originally specified
  here); `dir_delete` remains the tool intended for directories.
  Success: `Successfully deleted file: <path>`, data `path`,
  `filesChanged` `[path]`. There is no `confirm` parameter — see
  `assist-approval-model.md` §5.3.
- `dir_create` (`path` required) creates a directory including
  missing parents, and succeeds silently when the directory
  already exists (the filesystem layer checks existence first).
  Success: `Successfully created directory: <path>`, data `path`,
  `filesChanged` `[path]`. Failure:
  `Failed to create directory at <path>: <system error>` (no code).
- `dir_delete` (`path` required) deletes a directory and all its
  contents, recursively and permanently. Missing `path`:
  `Missing required parameter: path` (no code). A missing
  directory is a failure: `No directory at <path> — nothing to delete.`
  (no code). Deleting the workspace root itself is refused by the
  filesystem layer:
  `Failed to delete directory at <path>: Security Error: Refusing to delete the workspace root itself: <path>`.
  A path that exists but is not a directory fails the same way,
  with the underlying error
  `No directory at <path> — nothing to delete.` — i.e.
  `Failed to delete directory at <path>: No directory at <path> — nothing to delete.`
  (the tool's existence pre-check passes for a file, then the
  layer rejects it). Success:
  `Successfully deleted directory: <path>`, data `path`,
  `filesChanged` `[path]`. There is no `confirm` parameter.

### 5.3 In-place edits: `code_replace`, `code_insert`, `code_multi_edit`

- `code_replace` (`path`, `target`, `replacement` required;
  `allowMultiple` boolean, default `false`) replaces an exact
  snippet. Parameter aliases: `path` ← `filePath` / `file_path` /
  `targetFile`; `target` ← `targetContent` / `old_string` /
  `old_str` / `find`; `replacement` ← `replacementContent` /
  `new_string` / `new_str` / `replace`; `allowMultiple` ←
  `allow_multiple`. Matching is literal substring matching, not
  regex and not AST-aware. Occurrence counting is
  `source.components(separatedBy: target).count - 1` (non-overlapping
  occurrences). Zero occurrences fails with
  `Target snippet not found in '<file>'. Please re-read the file with 'file_read' to inspect the exact existing lines before attempting replacement. Target snippet was: '<snippet>'`.
  More than one occurrence with `allowMultiple` false fails with
  `Target snippet matched <count> times in '<file>'. Provide more surrounding lines to uniquely identify the location, or pass 'allowMultiple: true'. Snippet was: '<snippet>'`.
  With `allowMultiple: true` every occurrence is replaced. The
  replacement is `String.replacingOccurrences` (all occurrences,
  non-overlapping, left to right). A third conflict case exists in
  the error type — `File '<file>' state changed unexpectedly on
  disk during operation.` — but no code path in the replacement
  routine throws it (the enum case is defined and the tool
  handles it, but the throw site does not exist in the Legacy
  source read for this spec); the SwiftCode port must keep the
  handler for it and must not invent a condition that triggers
  it. Success output is
  `Successfully updated <path> with targeted replacement.\n\nUnified Diff:\n<diff>`
  — the unified diff is embedded in the message as well as in
  `data["diff"]`. Data: `diff`, `path`. `filesChanged` `[path]`.
  The file is written only after the replacement succeeds; a
  conflict failure writes nothing.
- `code_insert` (`path`, `code` required; `mode` one of `line` /
  `before` / `after`, default `line`; `line` integer, default 1;
  `pattern` required in `before` / `after` modes) inserts a code
  block. Mode and pattern are validated **before** the file is
  read or touched: an unknown mode fails with
  `Unknown mode '<mode>': expected 'line', 'before', or 'after'.`
  (the mode string is lowercased first); a missing `pattern` in
  `before` / `after` mode fails with
  `Missing required parameter for <mode> mode: pattern`; an
  invalid `line` fails with
  `Invalid line: must be an integer >= 1 (got '<value>').`
  (`line` accepts an integer, an integral double, or a numeric
  string — the same leniency as Wave 1's `file_read` lines).
  In `before` / `after` modes the pattern is plain substring
  matching against the file content; a miss fails with
  `Pattern not found in <path>: '<pattern>'. No changes made.`
  and nothing is written. Insertion mechanics: `before` inserts
  `code + "\n"` at the start of the pattern's first occurrence;
  `after` inserts `"\n" + code` at the end of the pattern's first
  occurrence; `line` mode splits the file into lines and inserts
  the code's lines at index `min(line - 1, lineCount)` — a line
  number past the end of file appends (it is clamped, not an
  error). If the result equals the original content, the call
  fails with `Insert made no change to <path>. No changes made.`
  and nothing is written. Success: `Code block inserted into
  <path>`, data `path`, `filesChanged` `[path]`.
- `code_multi_edit` (`edits` array required) applies a list of
  edits, each either a full-file replacement (`path` + `content`)
  or a search/replace (`path` + `search` + `replace`, where
  `replace` defaults to `""`). Validation happens for **all**
  edits before **any** is applied: an `edits` value that is not
  an array of objects fails with
  `Missing required parameter: edits (array of edit objects)`;
  edit N with a missing/empty `path` fails with
  `Edit #<N> is missing a non-empty 'path'. No edits were applied.`
  (1-based numbering); a search/replace edit with a missing/empty
  `search` fails with
  `Edit #<N> for <path> is missing a non-empty 'search'. No edits were applied.`
  In both validation failures nothing has been applied yet. Once
  application starts, the tool is **not atomic**: each edit is
  applied in array order, and a failure names the edits already
  applied. A search that is not found fails with
  `Search text not found in <path>. Edits already applied: <comma-joined paths>.`
  (empty string when none were applied yet — the suffix is still
  present). An edit whose replacement equals the original fails
  with
  `Edit for <path> made no change. Edits already applied: <...>.`
  A filesystem failure fails with
  `Failed to apply edit to <path>: <system error>. Edits already applied: <...>.`
  Search/replace matching is literal substring replacement of
  **all** occurrences (`replacingOccurrences`), not first-only.
  Success: `Multi-file edit completed for <N> files`, data
  `files` = the updated paths comma-joined, `filesChanged` = the
  updated paths. Note the data key is `files`, not `filesChanged`,
  and an empty `edits` array succeeds with `0 files` (no
  validation error for an empty array).

### 5.4 `code_generate` and `code_refactor`

- `code_generate` (`path`, `template` required; `module`
  optional) generates a new file from one of four built-in
  string templates — this is template substitution, not an AST
  transform and not an LLM call. Templates (case-insensitive):
  `swift_struct`, `swift_class`, `swiftui_view`, `test`. The
  file name used inside the template is the target path's file
  name without its extension. `module` is used only by the `test`
  template (for `@testable import`); when absent or empty it
  defaults to the project name resolved from the workspace, or
  `"App"` when no project is found. The rendered templates are,
  exactly:
  - `swift_struct`: `import Foundation`, blank line,
    `public struct <Name> {`, `    public init() {}`, `}`,
    trailing newline.
  - `swift_class`: same shape with
    `public final class <Name>`.
  - `swiftui_view`: `import SwiftUI`, blank line,
    `struct <Name>: View {`, `    var body: some View {`,
    `        Text("<Name>")`, `    }`, `}`, blank line,
    `#Preview {`, `    <Name>()`, `}`, trailing newline.
  - `test`: `import XCTest`, `@testable import <Module>`, blank
    line, `final class <Name>: XCTestCase {`,
    `    func testExample() {`,
    `        XCTFail("Not implemented: replace with a real assertion for <Name>.")`,
    `    }`, `}`, trailing newline. The test deliberately fails
    until a real assertion replaces it (Legacy's comment: "Honest
    scaffold: fails until a real assertion replaces it, instead of
    a vacuous XCTAssertTrue(true) counted as a test").
  An existing target file fails with
  `Target file already exists: <path>` (no overwrite option). An
  unknown template fails with
  `Unknown template '<template>': expected swift_struct, swift_class, swiftui_view, or test.`
  — never a success that writes a comment-only file. Success:
  `Generated file <path> using template '<template>'`, data
  `path`. No `filesChanged` is returned (the Legacy call passes
  only data). No `diff` is returned.
- `code_refactor` (`path`, `action` required) is **LLM-driven**,
  not a local transform: it reads the file, sends the whole file
  plus the natural-language `action` to an LLM (Legacy hardcodes
  the OpenAI provider and its stored API key), strips Markdown
  fences (`` ```swift `` and `` ``` ``) and surrounding whitespace
  from the response, and writes the result back as the file's new
  content. There is no AST, no symbol table, and no verification
  that the result parses or that only the requested change was
  made. Failure modes: missing `path` /
  `action` (`Missing required parameter: path` /
  `Missing required parameter: action`, no codes); LLM failure
  (`Refactor LLM failed: <error or "unknown">`); any other failure
  (`Refactor failed at <path>: <system error>`). Success:
  `Refactoring '<action>' applied to <path>`; no data, no
  `filesChanged`. **Portability question for the implementer,
  flagged not hand-waved:** SwiftCode's MCP layer has no LLM call of
  its own — refactoring must be routed through the host assistant
  (SwiftCodeAssistant / provider system), which is outside this
  wave's scope, or the tool must be registered as unavailable
  with a clear error. The port must not substitute a regex or
  template "refactor" and present it as Legacy's behaviour, and
  must not hardcode an OpenAI key path. Which route is taken is
  an implementation decision this spec leaves open; the behaviour
  specified above (whole-file LLM rewrite, fence-stripping,
  messages) is what either route must reproduce.

### 5.5 `regex_replace_in_files`

(`pattern`, `replacement` required; `fileExtension` default
`"swift"`; `dryRun` boolean default `false`.) Performs ICU regular
expression search and replace across workspace files. Details:

- Regex flavour: `NSRegularExpression` with no options — ICU
  syntax, case-sensitive, no multiline/dot-matches-line-separators
  flags. An invalid pattern fails before any file is touched:
  `Invalid regular expression pattern: <pattern>` (no code).
  There is no scope or directory parameter: the tool always
  enumerates the **whole workspace root**, skipping hidden files
  and package descendants.
- File selection: only files whose extension equals
  `fileExtension` exactly (case-sensitive comparison against
  `pathExtension` — `Swift` does not match `swift`). Files that
  do not decode as UTF-8 are silently skipped (not errors, not
  counted).
- Replacement: `stringByReplacingMatches` with the replacement as
  a template — `$1`, `$2` capture-group references are honoured.
  A file is "modified" when it has at least one match; the match
  count per file is the number of `matches` (non-overlapping).
- Writing: each matched file is written with
  `String.write(atomically: true)` — but a write failure for one
  file is swallowed (`try?`): the file keeps its old content, the
  tool does not report the failure, and the file still counts in
  the report. Preserve this (do not turn it into a hard failure
  without recording a deviation).
- Reporting: the report lists at most **30** files, each as
  `` - `<relativePath>` (<N> matches) ``; `totalReplacements`
  counts **all** matches in **all** matched files, not just the
  listed 30. No matches at all succeeds with
  `No matches found for pattern `<pattern>` in *.<ext> files.`
  A dry run succeeds with
  `[DRY RUN] Would modify <N> file(s) with <T> total replacements:\n\n<list>`
  and writes nothing. A real run succeeds with
  `Successfully modified <N> file(s) with <T> total replacements:\n\n<list>`.
  The tool returns **no structured data and no `filesChanged`**
  in any outcome — the report is the message only. Approval is
  per file (§6.3 of the approval model); in a dry run no approval
  is requested.
- Note the scope consequence: because there is no directory
  parameter, a single call can touch every `.swift` file in the
  workspace. The review UI presents one change per file; the
  implementer must not collapse them into one approval.

### 5.6 `code_format`

(`path` optional, default `"."`) Formats code by **local text
normalisation only**. It does not invoke any formatter binary:
there is no `swiftformat`, `swift-format`, `clang-format`, or
other subprocess anywhere in the Legacy implementation, and no
project style file is read despite the tool description's mention
of "project style guidelines". The normaliser
(`simpleFormat`) does exactly three things, per line:

1. Tabs are expanded to four spaces.
2. Trailing whitespace (spaces/tabs at end of line) is removed.
   Leading whitespace (indentation) is preserved.
3. Runs of blank lines collapse to a single blank line.

The result is the lines joined with `\n` plus a trailing `\n`
(a file that did not end with a newline gains one; a file that
already ended with one keeps exactly one).

- Target selection: if `path` is a directory, every regular file
  under it (recursive, hidden files skipped) with extension
  `swift`, `m`, `h`, `c`, `cpp`, `js`, `ts`, or `py` and size at
  most 300,000 bytes is considered; larger files are silently
  skipped. If `path` is a single file, that file is formatted
  regardless of extension or size. Files that do not decode as
  UTF-8 are silently skipped. Only files whose formatted content
  differs from their current content are written (and therefore
  only those go through approval); unchanged files are untouched.
- Path resolution is the §2.5 clamping resolver: an escaping path
  is silently replaced with the workspace root, so
  `code_format` on `../outside` formats the workspace root. A
  missing path fails with `Path does not exist: <path>` (no code).
- Success: `Code formatting completed at <path>`, data
  `formatted_files` = the count of files actually rewritten
  (as a decimal string). A directory with no matching files, or
  a file already formatted, succeeds with `formatted_files: "0"`.
  A write failure fails the whole call with
  `Failed to format at <path>: <system error>` — files formatted
  before the failure stay formatted (not atomic as a batch).
- **Portability note:** the description promises "project style
  guidelines" but the implementation applies one fixed
  normaliser. The SwiftCode port must reproduce the normaliser, not
  substitute a real formatter: adopting `swift-format` or similar
  would change every output. If a later decision wants a real
  formatter, that is a new tool behaviour to specify, not a
  silent upgrade of this one.

### 5.7 Plist tools: `plist_edit` vs `plist_to_json` / `json_to_plist`

- `plist_edit` (`path`, `key` required; `action` `get` / `set` /
  `delete`, default `get`; `value` string, required for `set`)
  manages one key in a dictionary plist. The plist is read with
  `PropertyListSerialization.propertyList(from:)` and must be a
  top-level dictionary — a plist whose root is an array, string,
  or anything else fails with
  `Plist at '<path>' is not a dictionary plist. Key-based edit requires a top-level dictionary.`
  The input format (XML or binary) is detected automatically;
  the output is always **XML** (format `.xml`), so a binary plist
  edited with `set` / `delete` comes back as XML — record this,
  it is observable. `value` is always stored as a **string**, even
  when the existing value was a number or boolean: `set` replaces
  any type with a string. `get` renders a found value with
  `describeValue`: strings as-is; booleans as `true` / `false`;
  numbers via `NSNumber` description; arrays as
  `array(<count>)`; dictionaries as `dictionary(<count>)`;
  anything else via its description. `get` on a missing key fails
  with `Key '<key>' not found in '<path>'.` `set` on a missing
  `value` fails with `Missing required parameter: value for set action.`
  An unknown action fails with
  `Invalid action '<action>': must be get, set, or delete.`
  (the action string is lowercased first). After a `set`, the
  file is read back and the write is verified: the key must read
  back as a string equal to `value`, otherwise
  `Verification failed: key not present after write.` After a
  `delete`, verification requires the key to be absent, otherwise
  `Verification failed: key still present after delete.` A
  `delete` of a missing key fails with the same
  `Key '<key>' not found in '<path>'.` as `get`. Writes use
  `Data.write(..., .atomic)`. Success messages: get —
  `Key '<key>' = <rendered> in '<path>'.` (data `key`, `value`
  = rendered string, `path`); set — `Set key '<key>' in '<path>'.`
  (data `key`, `value`, `path`); delete —
  `Deleted key '<key>' from '<path>'.` (data `key`, `path`).
  A missing file fails with `Plist file not found at '<path>'.`;
  an unreadable file with `Failed to read plist at '<path>'.`
  (no codes anywhere in this tool).
- `plist_to_json` (`path` required; `destination` optional,
  default `<path>.json`) converts a whole plist to JSON. The
  plist is decoded with `PropertyListSerialization` (any root
  type — unlike `plist_edit`, no dictionary requirement) and
  re-encoded with `JSONSerialization` using `.prettyPrinted` +
  `.sortedKeys`. A value that has no JSON representation (e.g. a
  `Date` or `Data` in the plist) fails the conversion: the catch
  reports `Failed to convert Plist to JSON: <system error>`.
  The destination's parent directories are created if missing.
  Success: `Successfully converted Plist `<path>` to JSON at `<dest>` (<N> bytes).`,
  data `destination`, `size` (byte count of the JSON data as a
  string), `filesChanged` `[dest]`.
- `json_to_plist` (`path` required; `destination` optional,
  default `<path>.plist`; `binary` boolean, default `false`)
  converts a whole JSON file to a plist. JSON is decoded with
  `JSONSerialization` (any root type), then encoded with
  `PropertyListSerialization` in XML (default) or binary
  (`binary: true`) format. A JSON value with no plist
  representation fails: `Failed to convert JSON to Plist: <system error>`.
  Success: `Successfully converted JSON `<path>` to Plist (binary|xml) at `<dest>` (<N> bytes).`,
  data `destination`, `format` (`"binary"` or `"xml"`), `size`,
  `filesChanged` `[dest]`.
- All three conversion tools resolve source and destination with
  the §2.2 strict resolver, so both ends must be inside the
  workspace, and both resolve relative paths against the
  workspace root (not the session working directory). A missing
  source fails with `Plist file not found at: <path>` /
  `JSON file not found at: <path>` (no code); a missing `path`
  argument with `Missing required parameter: path`.

### 5.8 CSV / JSON conversions

- `csv_to_json` (`path` required; `destination` optional,
  default `<path>.json`; `delimiter` optional, default `","`)
  parses a CSV file into a JSON array of objects. The parsing is
  naive string splitting, not a CSV parser:
  - The file must decode as UTF-8; empty lines (whitespace-only)
    are dropped; an empty file (no non-empty lines) fails with
    `CSV file is empty.`
  - The first remaining line is the header. Header and field
    values are split on the delimiter string (the whole string,
    not a single character — a multi-character delimiter splits
    on that substring) and each is trimmed of whitespace/newlines
    **and** of `"` characters at both ends.
  - There is no quote handling: a quoted field containing the
    delimiter is split in two, and an escaped quote (`""`) is not
    unescaped. A row with fewer columns than the header gets `""`
    for the missing values; a row with more columns silently
    drops the extras.
  - All values are strings, including numbers. Duplicate headers
    collapse (later column wins for that key). Headers are
    preserved in insertion order only insofar as
    `JSONSerialization` with `.sortedKeys` re-sorts them on
    output.
  - The output is a JSON array of objects, pretty-printed with
    sorted keys, written atomically. `delimiter` is used verbatim
    as given — the schema description names `,`, tab, and `;`,
    but the code accepts any string and does not validate it.
  - Success: `Successfully converted CSV `<path>` to JSON at `<dest>` (<N> records parsed).`,
    data `destination`, `recordCount`, `filesChanged` `[dest]`.
    A missing source fails with `CSV file not found at: <path>`;
    a missing `path` with `Missing required parameter: path`.
- `json_to_csv` (`path` required; `destination` optional,
  default `<path>.csv`) converts a JSON array of objects to CSV.
  The JSON root must be a **non-empty array of objects**:
  anything else (empty array, object root, scalar, array of
  scalars) fails with
  `JSON root must be a non-empty array of objects to convert to CSV.`
  Headers are the union of all objects' keys, **sorted
  alphabetically** (not first-seen order). Every value is
  stringified with `"\(value)"` (numbers, booleans, nested
  objects/arrays via their description — nested structures are
  **not** serialised as JSON), double quotes are doubled, and
  every field is wrapped in double quotes, including the header.
  Missing keys produce an empty field. Rows are joined with `\n`
  and the file ends with a trailing `\n`. Success:
  `Successfully converted JSON `<path>` to CSV at `<dest>` (<R> rows, <C> columns).`,
  data `destination`, `rowCount`, `columnCount`, `filesChanged`
  `[dest]`. A missing source fails with
  `JSON file not found at: <path>`. Note the asymmetry: `csv_to_json`
  round-trips lossily — quoted delimiters, duplicate headers,
  and nested values do not survive a round trip. The port must
  reproduce the lossy behaviour, not substitute a correct CSV
  library.
- `format_json_file` (`path` required) validates and
  pretty-prints a JSON file **in place**. The JSON is decoded
  with `JSONSerialization.jsonObject(with:options:
  [.fragmentsAllowed])` — so a top-level scalar or fragment is
  accepted — and re-encoded with `.prettyPrinted` + `.sortedKeys`,
  written atomically over the original file. Any decode/encode
  failure is reported as
  `JSON formatting or validation error in `<path>`: <system error>`.
  Success: `Successfully formatted and validated JSON file at `<path>` (<N> bytes).`
  (note the backticks around the path), data `path`,
  `formattedBytes` (byte count of the formatted data),
  `filesChanged` `[path]`. A missing file fails with
  `JSON file not found at: <path>`; a missing `path` argument with
  `Missing required parameter: path`. The tool does not check
  that the file's extension is `.json`.

### 5.9 `batch_rename_files`

(`directory`, `search`, `replacement` required; `extension`
optional filter; `dryRun` boolean, default `false`.) Renames
multiple files in one directory by substring replacement:

- `directory` accepts the alias `path`. The directory must exist
  and be a directory, else `Directory not found at: <dir>`.
  Missing arguments fail with
  `Missing required parameters: directory, search, replacement`
  (one message for all three — a missing `search` alone reports
  the same combined message). A directory outside the workspace
  fails with `Directory path is outside the workspace: <dir>`.
- Matching: the immediate children of the directory only (not
  recursive), sorted by filename. The `extension` filter, when
  given, is lowercased and compared against the file's extension
  lowercased (so `Swift` matches `swift`); files that do not match
  are skipped. A file matches when its filename **contains**
  `search` as a substring; the new name replaces **all**
  occurrences of `search` in the filename
  (`replacingOccurrences`). A file whose new name equals its old
  name is not counted and not renamed. Directories among the
  children are not excluded — a directory whose name contains
  `search` is renamed like a file.
- No matches succeeds with
  `No files in `<dir>` matched search pattern '<search>'.`,
  data `renamedCount: "0"`. (Note: this is success, not an error.)
- A dry run succeeds with
  `Dry run: <N> file(s) would be renamed in `<dir>`:\n  • <old> -> <new>\n...`
  (one `  • old -> new` line per planned rename, all of them —
  no 30-item cap, unlike `regex_replace_in_files`), data
  `dryRun: "true"`, `matchCount: "<N>"`, and writes nothing.
- A real run renames in sorted order with `FileManager.moveItem`.
  A destination that already exists makes that `moveItem` throw,
  failing the whole call with
  `Failed to batch rename files in `<dir>`: <system error>`
  — and renames already performed in this batch **stay renamed**
  (not atomic; the failure message does not name them, unlike
  `code_multi_edit`). Success:
  `Successfully batch-renamed <N> file(s) in `<dir>`:\n  • <old> -> <new>\n...`,
  data `renamedCount: "<N>"`, `filesChanged` = the renamed files'
  new paths (directory + new name).
- Collision note: two source files can map to the same new name
  (e.g. renaming `a-1` and `a-2` by replacing `a-` with `b-`
  is fine, but replacing `1`/`2` patterns can collide). Legacy
  does not pre-check for collisions between planned renames, or
  between a planned rename and an unrenamed file: the first
  conflicting `moveItem` throws and the batch fails partway
  through. Preserve this — do not add a pre-flight collision
  check.

### 5.10 `generate_file_checksum` — read-only, in this wave by assignment

`generate_file_checksum` (`path` required, alias `filePath`)
computes four hashes of a file and writes nothing. It is in this
wave because the subsystem map assigned it to the file-writing
family; that assignment is wrong, and this spec corrects it:

- Capability `fileReading`, risk `safeRead`, required permission
  `none`, read-only yes, `writes: false`. It is a read tool that
  happens to sit in this wave. See the catalogue §27 for the
  correction note.
- Behaviour: the file's bytes are read whole into memory
  (`Data(contentsOf:)`) and hashed in-process with swift-crypto
  (`SHA256`, `SHA512`, `Insecure.MD5`, `Insecure.SHA1` — all four,
  always, in that fixed set; there is no algorithm parameter).
  The output is exactly:
  ```
  Checksums for <path> (<N> bytes):
  - SHA-256: <hex>
  - SHA-512: <hex>
  - SHA-1:   <hex>
  - MD5:     <hex>
  ```
  (note the spacing: `SHA-1:` is followed by three spaces and
  `MD5:` by five, aligning the values). Data keys: `path`,
  `sha256`, `sha512`, `sha1`, `md5`, `size` (byte count as a
  decimal string). All hex is lowercase.
- Path resolution uses the strict data-inspection resolver (same
  shape as §2.2: trims, rejects empty / NUL / leading `~` / any
  `..`, absolute must be under the root, relative against the
  root, no `dir_cd` effect). Failures, all without codes:
  missing `path` → `Missing required parameter: path`; outside
  the workspace → `Path is outside the workspace: <path>`; missing
  file → `File not found at: <path>`; read/hash failure →
  `Failed to compute file checksum: <system error>`.
- Unlike Wave 1's `file_hash_verify` (which shells out to
  `/usr/bin/shasum` and `/usr/bin/md5`), this tool hashes
  in-process. The SwiftCode port hashes in-process too (swift-crypto,
  already a SwiftCode dependency) — no subprocess, no platform
  dependency. Unlike `file_checksum_verifier` (Wave 1), it always
  returns all four hashes and always returns structured data.

## 6. Text handling

- All text tools in this wave read and write UTF-8. A file that
  does not decode as UTF-8 fails the tool that reads it
  (`file_append`, `code_insert`, `code_replace`,
  `code_multi_edit`, `code_refactor`, `csv_to_json`) with that
  tool's read failure (usually
  `Failed to ... at <path>: <system error>` wrapping the decoding
  error). `code_format` and `regex_replace_in_files` silently
  skip undecodable files instead (§5.5, §5.6).
- Line splitting is `components(separatedBy: .newlines)` (which
  splits on `\n`, `\r`, `\r\n`, and the Unicode line separators).
  A trailing newline therefore produces a trailing empty element,
  which is why `file_write`'s line count counts one more line
  than a reader would expect for a file ending in `\n` (§5.1).
- No tool in this wave enforces a size cap on the files it reads
  or writes. `code_format` alone skips files over 300,000 bytes
  when enumerating a directory (§5.6).

## 7. Diff generation

`file_write`, `file_create`, and `code_replace` return a unified
diff in `data["diff"]` (and, for `code_replace`, embedded in the
message). The diff is produced by Legacy's `AssistDiffEngine`
(My­ers algorithm, 3 context lines) over the original and modified
full contents. The SwiftCode port must produce a unified diff with the
same content — same hunks, same context — not a different diff
format. The exact hunk-header format and line prefixes are the
standard unified format (`---` / `+++` / `@@ -a,b +c,d @@` /
` ` / `-` / `+`); the Wave 1 `file_compare_diff` spec records the
positional-diff exception for that tool only, and it does not
apply here. The diff is informational: a diff that cannot be
generated must not fail the write (Legacy generates it after the
write succeeds; if generation threw, the write would already have
happened — the port must preserve write-then-diff ordering, and
on diff failure return the success without `data["diff"]` rather
than failing the call).

## 8. Error-case table

Failure messages are part of the contract: reproduce them
verbatim. Where a Legacy tool supplies a classified error code,
it is shown; where it supplies none, the code column says "—"
and the SwiftCode port must leave the code absent. The error-code
taxonomy is the Wave 1 one (`assist-tool-catalogue.md` §1.1):
`missingArgument`, `invalidInput`, `notFound`,
`permissionDenied`, `executionFailed`, and the rest.

### 8.1 Missing / invalid arguments

| Condition | Message | Code | Tools |
|---|---|---|---|
| `file_write` `path` or `content` missing / non-string | `Missing required parameters: 'path' and 'content' are mandatory.` | `missingArgument` | `file_write` |
| `file_create` `path` missing / blank | `Missing required parameter: path` | `missingArgument` | `file_create` |
| `file_append` `path` missing | `Missing required parameter: path` | — | `file_append` |
| `file_append` `content` missing | `Missing required parameter: content` | — | `file_append` |
| `file_delete` / `dir_delete` / `file_move` `source` / `file_copy` `source` / `file_rename` `oldPath` / `dir_create` `path` missing | `Missing required parameter: path` (or `source` / `oldPath` as named) | `missingArgument` for `file_delete` only; — for the others | `file_delete`, `dir_delete`, `file_move`, `file_copy`, `file_rename`, `dir_create` |
| `file_move` `destination` / `file_copy` `destination` missing | `Missing required parameter: destination` | — | `file_move`, `file_copy` |
| `file_rename` `newName` missing | `Missing required parameter: newName` | — | `file_rename` |
| `file_rename` `newName` not a single component | `Invalid newName '<newName>': must be a single file name, not a path.` | — | `file_rename` |
| `file_rename` no-op | `Rename is a no-op: newName matches the current file name.` | — | `file_rename` |
| `file_create` exists, `overwrite` false | `File already exists at <path>. Set overwrite=true to replace it.` | `invalidInput` | `file_create` |
| `code_generate` `path` / `template` missing | `Missing required parameter: path` / `Missing required parameter: template` | — | `code_generate` |
| `code_generate` unknown template | `Unknown template '<template>': expected swift_struct, swift_class, swiftui_view, or test.` | — | `code_generate` |
| `code_generate` target exists | `Target file already exists: <path>` | — | `code_generate` |
| `code_insert` `path` / `code` missing | `Missing required parameter: path` / `Missing required parameter: code` | — | `code_insert` |
| `code_insert` unknown mode | `Unknown mode '<mode>': expected 'line', 'before', or 'after'.` | — | `code_insert` |
| `code_insert` missing `pattern` in before/after mode | `Missing required parameter for <mode> mode: pattern` | — | `code_insert` |
| `code_insert` invalid `line` | `Invalid line: must be an integer >= 1 (got '<value>').` | — | `code_insert` |
| `code_multi_edit` `edits` not an array of objects | `Missing required parameter: edits (array of edit objects)` | — | `code_multi_edit` |
| `code_multi_edit` edit N missing/empty `path` | `Edit #<N> is missing a non-empty 'path'. No edits were applied.` | — | `code_multi_edit` |
| `code_multi_edit` edit N missing/empty `search` | `Edit #<N> for <path> is missing a non-empty 'search'. No edits were applied.` | — | `code_multi_edit` |
| `code_refactor` `path` / `action` missing | `Missing required parameter: path` / `Missing required parameter: action` | — | `code_refactor` |
| `code_replace` `path` / `target` / `replacement` missing | `Missing required parameter: 'path'` / `Missing required parameter: 'target'` / `Missing required parameter: 'replacement'` | — | `code_replace` |
| `regex_replace_in_files` `pattern` / `replacement` missing | `Missing required parameter: pattern` / `Missing required parameter: replacement` | — | `regex_replace_in_files` |
| `regex_replace_in_files` invalid regex | `Invalid regular expression pattern: <pattern>` | — | `regex_replace_in_files` |
| `plist_edit` `path` / `key` missing or blank | `Missing required parameter: path` / `Missing required parameter: key` | — | `plist_edit` |
| `plist_edit` unknown action | `Invalid action '<action>': must be get, set, or delete.` | — | `plist_edit` |
| `plist_edit` `set` without `value` | `Missing required parameter: value for set action.` | — | `plist_edit` |
| `format_json_file` / conversion tools `path` missing | `Missing required parameter: path` | — | `format_json_file`, `csv_to_json`, `json_to_csv`, `plist_to_json`, `json_to_plist`, `generate_file_checksum` |
| `csv_to_json` empty file | `CSV file is empty.` | — | `csv_to_json` |
| `json_to_csv` root not a non-empty array of objects | `JSON root must be a non-empty array of objects to convert to CSV.` | — | `json_to_csv` |
| `batch_rename_files` any of `directory` / `search` / `replacement` missing | `Missing required parameters: directory, search, replacement` | — | `batch_rename_files` |

### 8.2 Not found / not a file / not a directory

| Condition | Message | Code | Tools |
|---|---|---|---|
| Write fails | `Failed to write file at <path>: <system error>` | `executionFailed` | `file_write` |
| Create fails | `Failed to create file at <path>: <system error>` | `executionFailed` | `file_create` |
| Append read/write fails | `Failed to append to file at <path>: <system error>` | — | `file_append` |
| `file_delete` target missing | `No file at <path> — nothing to delete.` | `notFound` | `file_delete` |
| `file_delete` target is a directory | Deleted recursively, like any other path (Legacy behaviour, §5.2) | — | `file_delete` |
| `file_delete` other failure | `Failed to delete file at <path>: <system error>` | `executionFailed` | `file_delete` |
| `dir_delete` target missing / not a directory | `No directory at <path> — nothing to delete.` | — | `dir_delete` |
| `dir_delete` workspace root | `Failed to delete directory at <path>: Security Error: Refusing to delete the workspace root itself: <path>` | — | `dir_delete` |
| `dir_delete` other failure | `Failed to delete directory at <path>: <system error>` | — | `dir_delete` |
| `dir_create` failure | `Failed to create directory at <path>: <system error>` | — | `dir_create` |
| `file_move` failure (incl. missing source, existing destination, missing parent) | `Failed to move file: <system error>` | — | `file_move` |
| `file_copy` failure (same cases) | `Failed to copy file: <system error>` | — | `file_copy` |
| `file_rename` failure | `Failed to rename file: <system error>` | — | `file_rename` |
| Move/copy destination exists (underlying error) | `Destination already exists: <to>. Delete it first or choose another destination.` | — (wrapped in the `Failed to ...` message above) | `file_move`, `file_copy`, `file_rename` |
| `code_replace` target not found | `Target snippet not found in '<file>'. Please re-read the file with 'file_read' to inspect the exact existing lines before attempting replacement. Target snippet was: '<snippet>'` | — | `code_replace` |
| `code_replace` multiple matches, `allowMultiple` false | `Target snippet matched <count> times in '<file>'. Provide more surrounding lines to uniquely identify the location, or pass 'allowMultiple: true'. Snippet was: '<snippet>'` | — | `code_replace` |
| `code_replace` stale state (defined, never thrown by the replacement routine — see §5.3) | `File '<file>' state changed unexpectedly on disk during operation.` | — | `code_replace` |
| `code_replace` other failure | `Failed to replace in file at <path>: <system error>` | — | `code_replace` |
| `code_insert` pattern not found | `Pattern not found in <path>: '<pattern>'. No changes made.` | — | `code_insert` |
| `code_insert` no change | `Insert made no change to <path>. No changes made.` | — | `code_insert` |
| `code_insert` other failure | `Failed to insert code into <path>: <system error>` | — | `code_insert` |
| `code_multi_edit` search not found mid-batch | `Search text not found in <path>. Edits already applied: <comma-joined paths>.` | — | `code_multi_edit` |
| `code_multi_edit` edit made no change | `Edit for <path> made no change. Edits already applied: <comma-joined paths>.` | — | `code_multi_edit` |
| `code_multi_edit` filesystem failure mid-batch | `Failed to apply edit to <path>: <system error>. Edits already applied: <comma-joined paths>.` | — | `code_multi_edit` |
| `code_format` target missing | `Path does not exist: <path>` | — | `code_format` |
| `code_format` write failure | `Failed to format at <path>: <system error>` | — | `code_format` |
| `code_generate` failure | `Failed generating file <path>: <system error>` | — | `code_generate` |
| `code_refactor` LLM failure | `Refactor LLM failed: <error or "unknown">` | — | `code_refactor` |
| `code_refactor` other failure | `Refactor failed at <path>: <system error>` | — | `code_refactor` |
| `plist_edit` file missing | `Plist file not found at '<path>'.` | — | `plist_edit` |
| `plist_edit` unreadable | `Failed to read plist at '<path>'.` | — | `plist_edit` |
| `plist_edit` root not a dictionary | `Plist at '<path>' is not a dictionary plist. Key-based edit requires a top-level dictionary.` | — | `plist_edit` |
| `plist_edit` key missing (get / delete) | `Key '<key>' not found in '<path>'.` | — | `plist_edit` |
| `plist_edit` set verification fails | `Verification failed: key not present after write.` | — | `plist_edit` |
| `plist_edit` delete verification fails | `Verification failed: key still present after delete.` | — | `plist_edit` |
| `plist_edit` write failure | `Failed to write plist: <system error>` | — | `plist_edit` |
| `format_json_file` file missing | `JSON file not found at: <path>` | — | `format_json_file` |
| `format_json_file` invalid JSON | `JSON formatting or validation error in `<path>`: <system error>` | — | `format_json_file` |
| `csv_to_json` file missing | `CSV file not found at: <path>` | — | `csv_to_json` |
| `csv_to_json` conversion failure | `Failed to convert CSV to JSON: <system error>` | — | `csv_to_json` |
| `json_to_csv` file missing | `JSON file not found at: <path>` | — | `json_to_csv` |
| `json_to_csv` conversion failure | `Failed to convert JSON to CSV: <system error>` | — | `json_to_csv` |
| `json_to_csv` CSV encode failure | `Failed to encode CSV string to UTF-8 data.` | — | `json_to_csv` |
| `plist_to_json` file missing | `Plist file not found at: <path>` | — | `plist_to_json` |
| `plist_to_json` conversion failure | `Failed to convert Plist to JSON: <system error>` | — | `plist_to_json` |
| `json_to_plist` file missing | `JSON file not found at: <path>` | — | `json_to_plist` |
| `json_to_plist` conversion failure | `Failed to convert JSON to Plist: <system error>` | — | `json_to_plist` |
| `batch_rename_files` directory missing / not a directory | `Directory not found at: <dir>` | — | `batch_rename_files` |
| `batch_rename_files` failure mid-batch | `Failed to batch rename files in `<dir>`: <system error>` | — | `batch_rename_files` |
| `generate_file_checksum` file missing | `File not found at: <path>` | — | `generate_file_checksum` |
| `generate_file_checksum` read/hash failure | `Failed to compute file checksum: <system error>` | — | `generate_file_checksum` |

### 8.3 Outside the workspace

| Condition | Message | Tools |
|---|---|---|
| Session-aware resolver traversal | `Security Error: Path traversal outside workspace bounds is forbidden: <path>` (wrapped in the tool's `Failed to ...` message where the tool wraps resolver errors — e.g. `Failed to write file at <path>: Security Error: ...`) | `file_write`, `file_create`, `file_append`, `file_delete`, `file_move`, `file_copy`, `file_rename`, `dir_create`, `dir_delete`, `code_generate`, `code_insert`, `code_multi_edit`, `code_refactor` |
| Inline `..` check | `Path security error: Relative path traversal ('..') is prohibited for safety. Path: '<path>'` | `file_write` (code `permissionDenied`), `code_replace` (no code) |
| Strict-resolver rejection (source path) | `Path is outside the workspace: <raw>` | `format_json_file`, `csv_to_json`, `json_to_csv`, `plist_to_json`, `json_to_plist`, `generate_file_checksum` |
| Strict-resolver rejection (destination path) | `Destination path is outside the workspace: <raw>` | `csv_to_json`, `json_to_csv`, `plist_to_json`, `json_to_plist` |
| Strict-resolver rejection (directory) | `Directory path is outside the workspace: <raw>` | `batch_rename_files` |
| `plist_edit` private-resolver rejection | `Invalid path '<raw>': must be inside the workspace and must not contain '..'.` | `plist_edit` |
| No project open (workspace root is `/`) | `No active project: workspace root is unavailable. Open a project first.` | Any §2.1 tool |

Note: `code_format` has **no** outside-workspace error — its
clamping resolver (§2.5) silently replaces an escaping path with
the workspace root. `regex_replace_in_files` has no path argument
and therefore no outside-workspace error either.

### 8.4 Legacy-only envelope quirks the port drops

- `file_write` and `code_replace` set `suggestedNextActions` to
  `["project_build"]`, and to `["project_build", "project_build"]`
  for `.swift` files (the code inserts a second `"project_build"`
  at index 0 instead of replacing). SwiftCode's `MCPToolResult` has no
  suggested-actions field; the duplication is recorded here and
  dropped, not reproduced.
- `file_write`, `file_create`, `code_replace`, and `code_insert`
  set `duration`, `beforeContent`, and `afterContent` on the
  result. SwiftCode's `MCPToolResult` has no such fields; they are
  dropped. (`beforeContent` / `afterContent` for review purposes
  are the `MCPChange.original` / `proposed` — see the approval
  model §6.1.)
- `file_create` hardcodes `duration: 0.1` (a literal, not a
  measurement). Dropped with the rest.

## 9. What this spec does not cover

- The approval gate itself (policy modes, per-change approval,
  refusal handling, the Autopilot rejection) — see
  `assist-approval-model.md`.
- The Legacy session loop, providers, and `AssistManager` /
  `AssistAgentSession` — not ported, as in Wave 1.
- `file_backup` (Wave 1) — the only backup mechanism; no Wave 2
  tool creates backups.
- File-reading tools (Wave 1), search/navigation tools, and the
  rest of the Legacy registry — out of scope for Wave 2.
- `code_refactor`'s LLM provider routing (which assistant /
  provider performs the refactor in SwiftCode) — flagged as an open
  implementation decision in §5.4.
- Whether SwiftCode auto-registers newly created files in a project
  model (Legacy's `XcodeProjWriter.addFileReference`) — a
  project-model decision for a later spec, not a Wave 2 tool
  behaviour.

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 24 IDs, titles, descriptions, capabilities, risk levels, and input schemas; registry lines 68–77, 91–95, 202, 238, 310–316, 319 | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift`, read directly; `Tools/AssistWriteFileTool.swift`, `AssistCreateFileTool.swift`, `AssistAppendFileTool.swift`, `AssistDeleteFileTool.swift`, `AssistMoveFileTool.swift`, `AssistCopyFileTool.swift`, `AssistRenameFileTool.swift`, `AssistCreateDirectoryTool.swift`, `AssistDeleteDirectoryTool.swift`, `AssistGenerateFileTool.swift`, `AssistFormatCodeTool.swift`, `AssistInsertCodeBlockTool.swift`, `AssistMultiFileEditTool.swift`, `AssistRefactorTool.swift`, `AssistReplaceInFileTool.swift`, `AssistRegexReplaceInFilesTool.swift`, `AssistPlistEditTool.swift`, `AssistDataMutationTools.swift`, `AssistDataInspectionTools.swift` (`AssistGenerateFileChecksumTool`), read directly |
| Registry aliases (`write_file` → `file_write`, `create_file` → `file_create`, `delete_file` → `file_delete`, `move_file` → `file_move`, `copy_file` → `file_copy`, `rename_file` → `file_rename`, `create_directory`/`make_directory`/`directory_create` → `dir_create`, `delete_directory`/`remove_directory`/`directory_delete` → `dir_delete`, `edit_file`/`replace_in_file` → `code_replace`, `insert_code_block`/`insert_code` → `code_insert`, `regex_replace` → `regex_replace_in_files`) | 1 | Legacy `AssistToolRegistry.swift` alias table, read directly |
| Session-aware resolution, symlink handling, `/` fail-closed, `/tmp/swiftcode/scripts` carve-out; atomic `writeFile` with parent creation; `moveFile`/`copyFile` existing-destination refusal; `deleteDirectory` root refusal and not-a-directory error; `deleteFile` removes whatever is at the path | 1 | Legacy `SwiftCode/Backend/Assist/AssistFileSystem.swift`, read directly |
| Strict data-mutation resolver (rejects empty / NUL / `~` / any `..`; relative → root) and data-inspection resolver (same shape) | 1 | Legacy `Tools/AssistDataMutationTools.swift` (`resolveWorkspaceDataMutationURL`); `Tools/AssistDataInspectionTools.swift` (`resolveWorkspaceDataInspectionURL`), read directly |
| `plist_edit` private resolver, XML-only output, string-only `set`, `describeValue` rendering, read-back verification | 1 | Legacy `Tools/AssistPlistEditTool.swift`, read directly |
| `file_write` / `code_replace` inline `..` check and `/tmp/swiftcode/scripts` prefix check without a `/` boundary; `code_replace` conflict messages; `staleFileState` case defined but never thrown by the replacement routine | 1 | Legacy `Tools/AssistWriteFileTool.swift`, `Tools/AssistReplaceInFileTool.swift`, `AssistDiffEngine.swift` (`applyTargetedReplacement`, `DiffConflictError`), read directly |
| `code_format` local-only normaliser (tabs → 4 spaces, trailing-whitespace strip, blank-run collapse, trailing newline), clamping resolver, 300,000-byte enumeration cap, extension set | 1 | Legacy `Tools/AssistFormatCodeTool.swift`, `Tools/AssistToolingSupport.swift` (`resolvePath`, `enumeratedFiles`, `readText`), read directly |
| `code_generate` four templates rendered verbatim, `module` default, no-overwrite rule; `code_refactor` hardcoded OpenAI provider + stored key, fence-stripping, whole-file rewrite | 1 | Legacy `Tools/AssistGenerateFileTool.swift`, `Tools/AssistRefactorTool.swift`, read directly |
| `code_insert` mode/pattern/line validation order, `insertBefore`/`insertAfter` mechanics (first occurrence, `\n` joining), line-mode clamping past end of file | 1 | Legacy `Tools/AssistInsertCodeBlockTool.swift`, `Functions/AssistCodeFunctions.swift`, read directly |
| `code_multi_edit` validate-all-first, not-atomic application, per-edit failure messages naming applied edits, literal all-occurrences replacement | 1 | Legacy `Tools/AssistMultiFileEditTool.swift`, read directly |
| `regex_replace_in_files` whole-workspace enumeration, `NSRegularExpression` no-options, `$n` templates, 30-item report cap, swallowed per-file write failures, no data | 1 | Legacy `Tools/AssistRegexReplaceInFilesTool.swift`, read directly |
| Conversion tools: naive CSV splitting (no quote handling, missing → `""`, extras dropped), JSON→CSV sorted headers + always-quoted fields, plist any-root-type conversion, `format_json_file` fragments-allowed + sorted keys + in-place atomic rewrite | 1 | Legacy `Tools/AssistDataMutationTools.swift` (`AssistFormatJsonFileTool`, `AssistCsvToJsonTool`, `AssistJsonToCsvTool`, `AssistPlistToJsonTool`, `AssistJsonToPlistTool`, `AssistBatchRenameFilesTool`), read directly |
| `batch_rename_files` immediate-children-only matching, substring replacement of all occurrences, directory children not excluded, no collision pre-check, partway failure leaves earlier renames | 1 | Legacy `Tools/AssistDataMutationTools.swift` (`AssistBatchRenameFilesTool`), read directly |
| `generate_file_checksum` capability `fileReading`, risk `safeRead`, four in-process swift-crypto hashes, exact output spacing, no writes | 1 | Legacy `Tools/AssistDataInspectionTools.swift` (`AssistGenerateFileChecksumTool`, lines 334–399), read directly |
| `suggestedNextActions` duplication for `.swift` files, hardcoded `duration: 0.1` in `file_create`, `beforeContent`/`afterContent` envelope fields | 1 | Legacy `Tools/AssistWriteFileTool.swift`, `AssistCreateFileTool.swift`, `AssistReplaceInFileTool.swift`, `AssistInsertCodeBlockTool.swift`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
