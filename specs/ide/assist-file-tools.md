# Assist file tools — shared behaviour

SwiftCode modules: `SwiftCodeMCP` (the MCP server and its tools; the Wave 1 port
registers the tools here).

This spec covers the behaviour shared by the 24 Wave 1 file tools
catalogued in `assist-tool-catalogue.md`: path safety, the session
working-directory model, per-tool defaults and caps, binary and
encoding handling, the artifact store and backup layout, and the full
error-case table. The catalogue is the source of truth for each tool's
ID, schema, and output shape; this spec is the source of truth for how
those tools behave.

## 1. Terms

- **Workspace root**: the root folder of the currently open project /
  workspace. Every tool resolves paths against it. If no project is
  open, there is no workspace root and every path-resolving tool must
  fail closed (Legacy fails with `No active project: workspace root is
  unavailable. Open a project first.`).
- **Session working directory (cwd)**: the per-session directory
  established by `dir_cd`, reported by `dir_pwd`. Defaults to the
  workspace root. Scoped to one session; never shared across sessions;
  never persisted to disk.
- **Workspace-relative path**: a path relative to the workspace root,
  e.g. `Sources/App.swift`. `"."` means the workspace root (or the
  session working directory, depending on the resolver — see §2).
- **Structured data**: the string-to-string map returned with a
  successful result. All values are strings; see
  `assist-tool-catalogue.md` §1.1.

## 2. Path-safety rules

There are three path-resolution behaviours in Legacy. The SwiftCode port
must preserve which tool uses which — they differ observably, and
unifying them would change behaviour.

### 2.1 The session-aware resolver (`AssistFileSystem.resolve`)

Used by: `file_read`, `dir_read`, `dir_cd`, `dir_pwd` (read-only use),
`tree_view`.

- Plain relative paths resolve against the **session working
  directory** (so `dir_cd` affects them).
- A path with a leading `/` resolves against the **workspace root**,
  not the filesystem root: the leading slashes are stripped and the
  remainder is treated as workspace-relative. A path that is exactly
  the workspace root, or starts with the workspace root plus `/`, is
  also accepted and treated the same way.
- `..` components are resolved normally (`..` moves to the parent) and
  are **not** rejected as text. The containment check happens after
  resolution: the resolved path (with symlinks resolved in the longest
  existing ancestor) must equal the workspace root or lie under it,
  otherwise the call fails with
  `Security Error: Path traversal outside workspace bounds is forbidden: <path>`.
- Symlinks in an existing parent are resolved before the containment
  check, so a symlink inside the workspace that points outside it is
  caught even when the leaf itself does not exist yet.
- The workspace root itself is canonicalised (symlinks resolved)
  before comparison.
- Fail-closed when the workspace root is `/`: resolution throws
  `No active project: workspace root is unavailable. Open a project first.`
  A `/` workspace root would otherwise make the containment check pass
  for every path on disk.
- Narrow carve-out: paths exactly equal to `/tmp/swiftcode/scripts`
  or under `/tmp/swiftcode/scripts/` are returned unchanged (the
  isolated scripts directory lives outside the workspace). The check
  is an exact prefix with a `/` boundary, so a sibling such as
  `/tmp/swiftcode/scripts-evil` does **not** ride the bypass.
  `file_read` applies the same carve-out before stripping a
  workspace-root prefix.
- The resolved path is returned standardised.

### 2.2 The strict per-tool resolver (`AssistWorkspacePaths.resolve` and its private copies)

Used by: `dir_size_report`, `file_head_preview`, `file_type_breakdown`,
`find_duplicate_files`, `empty_dirs_find`, `executable_files_scan`,
`symlink_audit`, `file_backup`, and (as private copies of the same
shape) `file_metadata`, `file_hash_verify`, `file_compare_diff`
(per-path), `count_file_lines`.

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
- Relative paths resolve against the **workspace root, not the session
  working directory**. These tools are unaffected by `dir_cd`.
- The standard failure message is
  `Refusing to access path outside the workspace: <raw>` (with
  per-tool variants: `file_compare_diff` uses
  `pathA is outside the workspace: <raw>` / `pathB is outside the workspace: <raw>`;
  `count_file_lines` uses `Path is outside the workspace: <raw>`).
- `AssistWorkspacePaths.relative(url, workspaceRoot:)` renders a
  resolved URL back to a workspace-relative path, returning `"."` for
  the root itself and the absolute path unchanged when it is not under
  the root.

### 2.3 Tilde

A leading `~` is rejected by the strict resolver (§2.2) and is never
expanded to a home directory by any tool in this catalogue. (The
session-aware resolver does not special-case `~` either: it is treated
as an ordinary relative path component, so `~/x` resolves to a
literal `~` directory under the working directory, which in practice
does not exist.)

### 2.4 Absolute vs relative paths

- Leading-`/` paths resolve against the workspace root under both
  resolvers (§2.1, §2.2) — **except** `file_checksum_verifier` and the
  two Finder tools, which use an absolute path verbatim against the
  real filesystem (see §2.5).
- A path that literally equals the workspace root's absolute path, or
  starts with it plus `/`, is accepted by the session-aware resolver
  and treated as workspace-relative.
- Plain relative paths resolve against the session working directory
  for the §2.1 tools and against the workspace root for the §2.2
  tools. This is the one observable difference `dir_cd` makes.

### 2.5 The two tools with no containment check

`file_checksum_verifier` and the two Finder tools (`open_in_finder`,
`reveal_in_finder`) do **not** call either resolver:

- `file_checksum_verifier`: an absolute path is used verbatim as a
  filesystem path; a relative path is appended to the workspace root.
  No containment check is performed, so an absolute path outside the
  workspace is hashed without complaint. The SwiftCode port must either
  preserve this (and record it as a known gap) or tighten it and
  record the tightening as a deliberate behaviour change — it must
  not silently change.
- `open_in_finder` / `reveal_in_finder`: an absolute path is used
  verbatim; a relative path is appended to the workspace root. No
  containment check is performed. The target must exist, but it may
  be anywhere on disk. See §8.

### 2.6 Symlink policy

- Symlinks are resolved (in the longest existing ancestor) before the
  containment check in the session-aware resolver (§2.1), so a
  workspace symlink pointing outside the workspace is refused.
- The strict resolver (§2.2) standardises but does **not** resolve
  symlinks; a symlink inside the workspace that points outside it is
  therefore followed by the tools that use this resolver. This is a
  known Legacy inconsistency, recorded here so the SwiftCode port can
  decide deliberately (tightening it is a behaviour change to record,
  not a silent fix).
- `tree_view` **never follows symlinks**: a symlink is rendered as a
  `🔗 <name>` leaf and never descended into, which also prevents
  symlink-cycle recursion. It additionally tracks visited canonical
  directory paths and renders a repeat visit as
  `↩︎ [already visited: <name>]` instead of recursing.
- `symlink_audit` is the tool that finds and reports symlinks (with
  targets and broken-link flags); it does not follow them either.
- All other tools follow symlinks implicitly through the platform's
  file operations (no special handling).

## 3. Reading files: line ranges, caps, and text handling

### 3.1 `file_read` line ranges

- `lines` is optional. Omitted, the whole file is read.
- `start` defaults to 1; `end` defaults to the last line. Both must be
  integers ≥ 1. Non-integer values are accepted leniently when they
  parse as an integer: an integral double (e.g. `240.0`) or a numeric
  string (e.g. `"240"`). `lines` may also arrive as a JSON-stringified
  object. Anything else fails with
  `Invalid lines.start: must be an integer >= 1 (got '<value>').`
  (and the same for `end`).
- Lines are 1-based and inclusive at both ends.
- `start > end` fails with
  `Invalid line range: start (<start>) > end (<end>). Lines are 1-based inclusive.)`
  (note the Legacy message's trailing `.)` — reproduce it verbatim).
- `end` beyond the last line is clamped to the last line.
- `start > totalLines` fails with
  `Line range start (<start>) exceeds total lines (<totalLines>) in <path>. No content invented.`
  Content is never invented for an out-of-range request.
- An empty file succeeds with the message `File is empty: <path>` and
  data `content: ""`, `start: "1"`, `end: "0"`, `totalLines: "0"`,
  `fullyAvailable: "true"`.
- Lines are split preserving empty lines; a trailing newline does not
  create a phantom line (so a file ending in `\n` has no extra empty
  last line).
- Every returned line is prefixed with its 1-based line number:
  `<n>: <line>`, lines joined with `\n`.
- `fullyAvailable` is `"true"` only when the whole file was returned.

### 3.2 `file_head_preview` line counts

- `lines` defaults to 20 and is clamped to 1…100
  (`max(1, min(100, lines ?? 20))`). A value of 0 behaves as 1; a
  value above 100 behaves as 100. No error is raised for out-of-range
  counts.
- Unlike `file_read`, the split does **not** strip a trailing empty
  line, so for a file ending in a newline `totalLines` here is one
  more than `file_read`'s `totalLines` for the same file.
- The head lines are numbered the same way (`<n>: <line>`), and a
  truncation marker `… [truncated: showing <n> of <total> lines]` is
  appended when the file has more lines than shown.

### 3.3 Binary / non-UTF-8 handling

| Tool | Behaviour for non-UTF-8 / binary content |
|---|---|
| `file_read` | Fails: `Failed to read file at <path>: <system error>`. The read is UTF-8 only. |
| `file_head_preview` | Tries UTF-8, then UTF-16, then ISO Latin-1, and reports the detected encoding. Fails only if none decode: `File is not decodable text (likely binary): <path>`. Because ISO Latin-1 decodes almost any byte sequence, most binary files decode as `iso-latin-1` rather than failing. |
| `file_compare_diff` | Both files must decode as UTF-8; a decoding failure fails the tool: `Failed to read files for comparison: <system error>`. |
| `count_file_lines` | Files that do not decode as UTF-8 are **silently skipped** from all line/byte counts, but still counted in `fileCount`. |
| `file_checksum_verifier`, `file_hash_verify`, `find_duplicate_files` | Hash raw bytes; encoding is irrelevant. |
| All other tools | Operate on filesystem metadata / directory listings; file content encoding is irrelevant. |

### 3.4 Size caps on reads

- Legacy `file_read` has **no size cap**. (SwiftCode's existing
  `file_read` MCP tool refuses files over 8 MB and caps reads at 2000
  lines — that is SwiftCode's tool, not this one; do not import those
  limits here. See `assist-tool-catalogue.md` §1.6.)
- `read_artifact` truncates content at 60,000 characters (§7).
- `create_artifact` has a recommended ~25,000-character ceiling that
  is **not enforced** (§7).

## 4. Session working-directory model (`dir_cd` / `dir_pwd`)

- The working directory is per-session state, keyed by session ID.
  It is held in memory only, never written to disk, and never shared
  across sessions. A new session starts at the workspace root.
- `dir_pwd` reports it as an absolute path. It takes no parameters.
- `dir_cd`:
  - `path` is required; a missing or empty `path` fails with
    `Missing required parameter: path`.
  - `path` resolves against the **current** directory: `.` is a no-op
    (stays where it is), `..` moves to the parent, a plain relative
    path descends from the current directory, and a leading-`/` path
    resolves against the workspace root.
  - The target must exist and be a directory; otherwise the failure
    is `Failed to change directory to <path>: <system error>`, where
    the underlying error is `Directory does not exist or is not a directory: <path>`.
  - `..` past the workspace root is an **error, not a clamp**: the
    containment check rejects it and the failure message is
    `Failed to change directory to <path>: Security Error: Path traversal outside workspace bounds is forbidden: <path>`.
  - On **any** failure the working directory is left unchanged. The
    change is applied only after existence, directory-ness, and
    containment have all passed, and is then persisted for the rest
    of the session.
  - On success the tool returns the new absolute path, the previous
    absolute path, and a sorted listing of the new directory's entries
    (plain names, no `/` markers) with its count — a shell-like
    orientation listing.
- Which tools observe the working directory: only the §2.1 tools
  (`file_read`, `dir_read`, `tree_view`, and `dir_cd` itself) resolve
  plain relative paths against it. All §2.2 tools resolve plain
  relative paths against the workspace root regardless of `dir_cd`.
  In Legacy, `use_terminal` also defaults its working directory to
  it when no working directory is given; that is outside Wave 1 but
  the SwiftCode port must keep the session directory available for it.

## 5. Per-tool behaviour notes (defaults and caps)

### 5.1 `tree_view`

- `path` defaults to `"."` (the workspace root / current directory —
  resolved through the session-aware resolver).
- `maxDepth` defaults to 3. It accepts an integer, an integral double,
  or a numeric string ≥ 1; anything else fails with
  `Invalid maxDepth: must be an integer >= 1 (got '<value>').`
  (error code `invalidInput`). The accepted value is clamped to
  1…10.
- `maxDepth` bounds **directory descent**: directories are rendered
  down to that depth, files directly inside a directory at the
  maximum depth are still listed, but subdirectories below it are
  not rendered.
- The entry cap is **2000 entries** (the root itself is not counted).
  When the cap is hit, rendering stops and the data's `tree` value
  gets the suffix `\n… [truncated at 2000 entries]` and `truncated`
  becomes `"true"`.
- Format: root line `📂 <name>`; two spaces of indent per level;
  directories recurse; files `📄 <name>`; symlinks `🔗 <name>` (never
  followed); a repeat visit to a canonical directory renders
  `↩︎ [already visited: <name>]`; a directory that cannot be read
  renders `⚠️ Error reading directory: <system error>`. Entries
  within a directory are sorted by name.
- Hidden files are **not** skipped (unlike most other tools here).
- A path that cannot be resolved fails with
  `Failed to render tree at <path>: <system error>` (error code
  `notFound`).

### 5.2 `dir_read`

- `path` is required; there is no default. `"."` means the session
  working directory.
- Entries are sorted; directories are suffixed `/`.

### 5.3 `dir_size_report`

- `path` defaults to `"."`; `limit` defaults to 30, clamped to
  1…200 (`max(1, min(200, limit ?? 30))`).
- Only immediate children are listed; each subdirectory's size is
  computed recursively. A plain-file child contributes its own size.
- Rows are sorted largest first; only the first `limit` rows appear
  in the message. `totalBytes` and `entryCount` in the data cover
  **all** immediate children, not just the shown rows.
- Hidden files/directories are skipped.
- The target must be an existing directory, else `Not a directory: <raw>`.

### 5.4 `file_compare_diff`

- Positional line-by-line comparison, **not** a real diff algorithm:
  there is no longest-common-subsequence matching and no hunks. Lines
  are compared by index; equal lines render as `  <line>`; a differing
  position renders `- <old>` then `+ <new>`; lines past the end of
  the shorter file render as `- ` / `+ ` lines. The header is always
  a single hunk covering both whole files:
  `--- a/<pathA>`, `+++ b/<pathB>`,
  `@@ -1,<linesA> +1,<linesB> @@`. A single inserted line therefore
  shifts every following line into a `-`/`+` pair. The SwiftCode port
  must reproduce this, not substitute a smarter diff.
- Identical files (byte-identical content) succeed with
  `identical: "true"` and no diff.
- Both files must exist and decode as UTF-8.

### 5.5 `count_file_lines`

- `path` is required. The `extension` filter is optional; when given
  it is compared lowercased and without a leading dot (e.g. `swift`).
- The filter applies **only when `path` is a directory**. A single
  file is analysed regardless of the filter.
- Directory walks are recursive, skip hidden files and package
  descendants, and count only regular files.
- Line classification (after trimming whitespace): empty → blank;
  starts with `//`, `/*`, `*`, or `#` → comment; otherwise → code.
  This is a prefix heuristic, not a parser.
- Files that do not decode as UTF-8 are silently skipped from the
  counts but still included in `fileCount`.
- `Total File Size` in the message is a human-readable size plus the
  raw byte count in parentheses.

### 5.6 Hash tools

- `file_hash_verify` / `file_checksum_verifier` algorithms:
  `sha256`, `sha1`, `md5` (case-insensitive; surrounding whitespace
  trimmed for `file_hash_verify`).
- Expected hex lengths enforced by `file_hash_verify`: SHA-256 = 64,
  SHA-1 = 40, MD5 = 32 characters, all hex digits. Anything else is
  an error (see §9).
- `file_hash_verify` reports a mismatch as **success with
  `match: "false"`**, not an error.
- `file_checksum_verifier` never verifies anything (no expected hash
  is accepted) and silently falls back to SHA-256 for an unknown
  algorithm; it also returns no structured data. See
  `assist-tool-catalogue.md` §10.
- Legacy `file_hash_verify` computes hashes by running the macOS
  binaries `/usr/bin/shasum` (`-a 256` / `-a 1`) and `/usr/bin/md5`
  (`-q`). The SwiftCode port must hash in-process (CryptoKit /
  swift-crypto on Apple platforms; an equivalent on Linux) with
  identical observable behaviour, including the failure
  `Failed to compute <algorithm> for <path>.` when hashing fails.

### 5.7 Scan tools

- `find_duplicate_files`: `path` defaults to `"."`; `minSize`
  defaults to 1, clamped to a minimum of 0. Files are grouped by
  size first, then same-size files are SHA-256-hashed (streamed in
  1 MB chunks) and grouped by digest. Only groups of two or more
  count. The message lists at most **50 groups**; `groupCount` is the
  full count. Hidden files are skipped.
- `empty_dirs_find`: `path` defaults to `"."`. "Empty" means the
  directory listing is empty — hidden entries count, so a directory
  containing only a hidden file is not empty. Recursive; the starting
  directory itself is never reported. Results sorted.
- `executable_files_scan`: `path` defaults to `"."`; `limit`
  defaults to 100, clamped to 1…1000. Enumeration stops as soon as
  `limit` hits are collected, so a small `limit` may leave part of
  the tree unvisited. "Executable" means any executable permission
  bit is set. Hidden files are skipped. Results sorted.
- `symlink_audit`: `path` defaults to `"."`. No result limit. Hidden
  files are **not** skipped. A link is broken when its target does
  not exist (relative targets resolve against the link's parent
  directory). The reported target is the raw destination string, or
  `(unknown)` when unreadable.
- `file_type_breakdown`: `path` defaults to `"."`. Recursive, hidden
  files skipped, directories not counted. Extensions are lowercased;
  files with no extension group under `(no extension)`. Rows are
  sorted by file count descending. The structured data carries only
  `typeCount`; the table lives in the message.

### 5.8 `file_metadata`

- Works for files and directories.
- Permissions are reported as an octal string **without** a leading
  zero (e.g. `644`, not `0644`), in both the `permissions` and
  `permissionsOctal` data keys.
- Dates are ISO-8601 with fractional seconds; when a date is
  unavailable the message shows `(unknown)` and the data value is
  the empty string.
- Uses the strict per-tool resolver (§2.2): any `..` anywhere in the
  string is rejected, as is a leading `~`.

## 6. Finder tools — external side effects

- `open_in_finder` and `reveal_in_finder` are **macOS-only**. They
  depend on Finder / `NSWorkspace`. On a platform without Finder the
  SwiftCode port must fail with a clear error; it must never report
  success without having opened or revealed anything.
- `open_in_finder`: opens the target in Finder (directories) or its
  default application (files). If the Finder open reports failure,
  Legacy falls back to `/usr/bin/open <path>` and succeeds only when
  that exits 0; otherwise it fails with
  `Failed to open path in Finder: <absolutePath>`.
- `reveal_in_finder`: brings Finder forward with the target selected.
  There is no `/usr/bin/open` fallback; success is reported after
  the reveal call returns.
- Both require the target to exist, and both apply **no**
  workspace-containment check (§2.5).
- Both are declared `safeRead` / read-only in Legacy, but opening a
  Finder window is an external side effect. The SwiftCode port must set
  `openWorld: true` for both and must not present them as pure reads
  (see `assist-tool-catalogue.md` §1.3).

## 7. Artifact store and backups

### 7.1 Layout

- Artifacts live at `.assist_temp/artifacts/<filename>` under the
  workspace root. The store keeps a sidecar index at
  `.assist_temp/artifacts/.artifacts_index.json` mapping filenames to
  description, kind, creation date, and the producing message ID.
- `agent_notes.md` is special: it lives at the **workspace root**
  (`agent_notes.md`), not in the artifact directory, but it is listed
  by `list_artifacts` and readable by `read_artifact`.
- Backups live at `.assist_temp/backups/<name>.<stamp>.bak` under the
  workspace root. The backup directory is created (with intermediates)
  on demand.

### 7.2 Artifact name normalisation

A requested name is normalised before use; an unsafe name fails with
`Invalid artifact name '<name>'. Use snake_case with a .md extension (e.g. repository_analysis.md).`

- Trim surrounding whitespace; lowercase.
- A trailing `.md` or `.markdown` is stripped and `.md` re-added.
- Spaces and hyphens become underscores; runs of underscores collapse
  to one; leading/trailing underscores are trimmed.
- The stem must match `^[a-z0-9_]+$` after normalisation and be at
  most 120 characters. Names containing `/`, `\`, or `..` are rejected.
- The display title is derived from the stem: underscores become
  spaces and each word is capitalised (`repository_analysis.md` →
  `Repository Analysis`; `agent_notes.md` → `Agent Notes`).

### 7.3 Kind inference

- Kinds: `artifact` (default), `execution_plan`,
  `agent_notes` (only `agent_notes.md`), `image`, `screen_recording`
  (the last two are for binary artifacts and are not produced by any
  Wave 1 tool).
- An explicit `kind` argument to `create_artifact` always wins.
- When omitted, the kind is inferred from the filename: execution plan
  only when the stem **contains** `_plan`, **starts with** `plan_`,
  or **ends with** `_plan`. A bare `plan` substring (e.g.
  `airplane_notes.md`) does **not** count.
- Only `artifact` and `execution_plan` are valid `kind` values for
  `create_artifact`; anything else fails with
  `Invalid kind '<kind>'. Use artifact or execution_plan.`

### 7.4 Modes (`create_artifact`)

- `create` (default): fails if the artifact already exists —
  `Artifact '<filename>' already exists. Use mode 'update' to replace it or 'append' to add to it.`
- `update`: fails if the artifact does not exist —
  `No artifact named '<filename>' exists in the artifact store.`
- `append`: creates the artifact if missing; otherwise appends the new
  content after a blank line. Existing content is trimmed first, then
  joined as `<existing>\n\n<new>\n`.
- Any other mode fails with
  `Invalid mode '<mode>'. Use create, update, or append.`
  (The mode string is lowercased before matching.)
- Content is trimmed and stored with a trailing newline. Empty or
  whitespace-only content fails with
  `Missing required parameter: content (must be non-empty Markdown)`
  at the tool level, or `Artifact content is empty. Provide a non-empty Markdown document.` at the store level.
- The write is verified by reading the file back; a mismatch fails
  with `Failed to write artifact: verification read-back mismatch for <filename>`.
- `description`, when omitted or empty, defaults to the first
  meaningful line of the content: the first non-empty line, with
  leading `#` markers stripped, capped at 140 characters. In the list
  output the description is further capped at 100 characters.
- Content length: the recommended ceiling is **~25,000 characters**
  and is not enforced. `read_artifact` truncates at **60,000**
  characters (§7.5).

### 7.5 Reading artifacts

- `read_artifact` returns the content prefixed by `# <Title>` and a
  blank line in the message. The content is **not** in the structured
  data — only `contentLength` (of the returned, possibly truncated,
  text) and `truncated`.
- Truncation at 60,000 characters appends:
  `\n… [truncated: showing first 60000 of <total> characters. The recommended write ceiling for new artifacts is ~25,000 characters — link workspace files instead of pasting them whole.]`
- A missing artifact fails with
  `No artifact named '<filename>' exists in the artifact store.`
- A file that cannot be decoded as UTF-8 fails with
  `Failed to read artifact: could not decode <filename> as UTF-8`.

### 7.6 Deleting artifacts

- `delete_artifact` requires the boolean `confirm: true`. Anything
  else fails with
  `Deletion requires confirm: true. The artifact was NOT deleted.`
  and nothing is deleted.
- `agent_notes.md` is protected and can never be deleted through this
  tool:
  `Artifact 'agent_notes.md' is managed by its own workflow and cannot be deleted through delete_artifact.`
- Deletion is permanent: the file and its index entry are removed.
  There is no trash, backup, or undo.
- A missing artifact fails with
  `No artifact named '<filename>' exists in the artifact store.`

### 7.7 Backups (`file_backup`)

- Backup filename: `<lastPathComponent>.<stamp>.bak`, where `<stamp>`
  is an ISO-8601 timestamp with `:` replaced by `-`
  (e.g. `2026-11-05T22-52-44Z`). The stamp has second resolution;
  two backups of the same file within the same second would collide
  (Legacy does not disambiguate — the copy would fail).
- The backup directory `.assist_temp/backups/` is created with
  intermediates if missing; failure to create it fails with
  `Cannot create backup directory: <system error>`.
- After copying, the byte counts of source and backup are compared.
  On mismatch the backup is deleted and the tool fails with
  `Backup verification failed (size mismatch); backup removed.`
- The tool checks only that the path exists (`No file at path: <raw>`
  otherwise). It does **not** check that the path is a file rather
  than a directory.
- The backup path is resolved through the strict resolver (§2.2):
  relative paths resolve against the workspace root, `..` is
  rejected, and the source must be inside the workspace.

## 8. Error-case table

Failure messages are part of the contract: reproduce them verbatim,
including the trailing `.)` in the `file_read` range message. Where a
Legacy tool supplies a classified error code, it is shown; where it
supplies none, the code column says "—" and the SwiftCode port must leave
the code absent.

### 8.1 Missing / invalid arguments

| Condition | Message | Code | Tools |
|---|---|---|---|
| `path` missing (or, for `file_read`, none of `path` / `filePath` / `file_path` / `targetFile` / `file` present) | `Missing required parameter: path` | `missingArgument` for `file_read`; — for the others | `file_read`, `dir_read`, `file_metadata`, `file_head_preview`, `file_checksum_verifier`, `file_hash_verify`, `file_backup`, `file_compare_diff` (see below), `count_file_lines`, `dir_cd` |
| `file_read` `lines.start` / `lines.end` not an integer ≥ 1 | `Invalid lines.start: must be an integer >= 1 (got '<value>').` / same for `end` | `invalidInput` | `file_read` |
| `file_read` `start > end` | `Invalid line range: start (<start>) > end (<end>). Lines are 1-based inclusive.)` | `invalidInput` | `file_read` |
| `file_read` `start > totalLines` | `Line range start (<start>) exceeds total lines (<totalLines>) in <path>. No content invented.` | `invalidInput` | `file_read` |
| `pathA` / `pathB` missing | `Missing required parameters: pathA and pathB` | — | `file_compare_diff` |
| `expectedHash` missing / blank | `Missing required parameter: expectedHash` | — | `file_hash_verify` |
| `file_hash_verify` unknown algorithm | `Invalid algorithm '<algorithm>'. Allowed: sha256, sha1, md5.` | — | `file_hash_verify` |
| `file_hash_verify` expected hash wrong length / non-hex | `Invalid expectedHash for <algorithm>. Expected <64\|40\|32> hexadecimal characters.` | — | `file_hash_verify` |
| `tree_view` `maxDepth` not an integer ≥ 1 | `Invalid maxDepth: must be an integer >= 1 (got '<value>').` | `invalidInput` | `tree_view` |
| `create_artifact` `name` missing / blank | `Missing required parameter: name` | — | `create_artifact` |
| `create_artifact` `content` missing / blank | `Missing required parameter: content (must be non-empty Markdown)` | — | `create_artifact` |
| `create_artifact` invalid `mode` | `Invalid mode '<mode>'. Use create, update, or append.` | — | `create_artifact` |
| `create_artifact` invalid `kind` | `Invalid kind '<kind>'. Use artifact or execution_plan.` | — | `create_artifact` |
| `create_artifact` / `read_artifact` / `delete_artifact` unsafe name | `Invalid artifact name '<name>'. Use snake_case with a .md extension (e.g. repository_analysis.md).` | — | `create_artifact`, `read_artifact`, `delete_artifact` |
| `delete_artifact` `confirm` not boolean `true` | `Deletion requires confirm: true. The artifact was NOT deleted.` | — | `delete_artifact` |
| `delete_artifact` `name` missing / blank | `Missing required parameter: name` | — | `delete_artifact` |
| `read_artifact` `name` missing / blank | `Missing required parameter: name` | — | `read_artifact` |
| Finder `path` missing / blank | `Missing required argument: 'path'` | — | `open_in_finder`, `reveal_in_finder` |
| `dir_cd` `path` missing / empty | `Missing required parameter: path` | — | `dir_cd` |

### 8.2 Not found / not a file / not a directory

| Condition | Message | Tools |
|---|---|---|
| Path cannot be read (UTF-8) | `Failed to read file at <path>: <system error>` | `file_read` |
| Directory listing fails | `Failed to read directory at <path>: <system error>` | `dir_read` |
| `dir_cd` target missing / not a directory | `Failed to change directory to <path>: <system error>` (underlying: `Directory does not exist or is not a directory: <path>`) | `dir_cd` |
| `tree_view` path unresolvable | `Failed to render tree at <path>: <system error>` | `tree_view` |
| `file_metadata` path missing | `No file or directory at path: <raw>` | `file_metadata` |
| `file_metadata` attribute read fails | `Failed to read metadata for <raw>: <system error>` | `file_metadata` |
| `file_head_preview` unreadable | `Cannot read file: <raw>` | `file_head_preview` |
| `file_head_preview` undecodable | `File is not decodable text (likely binary): <raw>` | `file_head_preview` |
| `file_compare_diff` A / B missing | `File A not found: <pathA>` / `File B not found: <pathB>` | `file_compare_diff` |
| `file_compare_diff` read/decode fails | `Failed to read files for comparison: <system error>` | `file_compare_diff` |
| `count_file_lines` path missing | `Path not found: <path>` | `count_file_lines` |
| `file_checksum_verifier` file missing | `File not found at: <path>` | `file_checksum_verifier` |
| `file_checksum_verifier` unreadable | `Unable to read data from file at: <path>` | `file_checksum_verifier` |
| `file_hash_verify` path missing or a directory | `Hash verification requires an existing file: <path>` | `file_hash_verify` |
| `file_hash_verify` hashing fails | `Failed to compute <algorithm> for <path>.` | `file_hash_verify` |
| `file_backup` path missing | `No file at path: <raw>` | `file_backup` |
| `dir_size_report` target not a directory | `Not a directory: <raw>` | `dir_size_report` |
| Scan target cannot be enumerated | `Cannot enumerate directory: <raw>` | `dir_size_report` (via empty listing fallback), `file_type_breakdown`, `find_duplicate_files`, `empty_dirs_find`, `executable_files_scan`, `symlink_audit` |
| `executable_files_scan` enumeration fails | `Cannot enumerate directory: <raw>` | `executable_files_scan` |
| Finder target missing | `Path does not exist: '<path>' (resolved to <absolutePath>)` | `open_in_finder`, `reveal_in_finder` |
| `open_in_finder` open fails (including `/usr/bin/open` fallback) | `Failed to open path in Finder: <absolutePath>` | `open_in_finder` |
| Artifact missing (`update` mode, read, delete) | `No artifact named '<filename>' exists in the artifact store.` | `create_artifact`, `read_artifact`, `delete_artifact` |
| Artifact already exists (`create` mode) | `Artifact '<filename>' already exists. Use mode 'update' to replace it or 'append' to add to it.` | `create_artifact` |
| Artifact content empty (store level) | `Artifact content is empty. Provide a non-empty Markdown document.` | `create_artifact` |
| Artifact write / read-back verification fails | `Failed to write artifact: <detail>` (including `verification read-back mismatch for <filename>`) | `create_artifact` |
| Artifact unreadable as UTF-8 | `Failed to read artifact: could not decode <filename> as UTF-8` | `read_artifact` |
| Backup directory cannot be created | `Cannot create backup directory: <system error>` | `file_backup` |
| Backup copy fails | `Backup failed: <system error>` | `file_backup` |
| Backup size verification fails | `Backup verification failed (size mismatch); backup removed.` | `file_backup` |

### 8.3 Outside the workspace

| Condition | Message | Tools |
|---|---|---|
| Strict-resolver rejection (empty, NUL, `~`, any `..`, or resolves outside the root) | `Refusing to access path outside the workspace: <raw>` | `dir_size_report`, `file_head_preview`, `file_type_breakdown`, `find_duplicate_files`, `empty_dirs_find`, `executable_files_scan`, `symlink_audit`, `file_backup`, `file_metadata` |
| Session-aware resolver traversal | `Security Error: Path traversal outside workspace bounds is forbidden: <path>` (wrapped: `Failed to read file at <path>: ...`, `Failed to read directory at <path>: ...`, `Failed to change directory to <path>: ...`, `Failed to render tree at <path>: ...`) | `file_read`, `dir_read`, `dir_cd`, `tree_view` |
| `file_compare_diff` A / B outside | `pathA is outside the workspace: <raw>` / `pathB is outside the workspace: <raw>` | `file_compare_diff` |
| `count_file_lines` path outside | `Path is outside the workspace: <raw>` | `count_file_lines` |
| `file_hash_verify` path outside | `Refusing to access path outside the workspace: <raw>` | `file_hash_verify` |
| No project open (workspace root is `/`) | `No active project: workspace root is unavailable. Open a project first.` | Any §2.1 tool |
| `dir_cd` `..` past the root | `Failed to change directory to <path>: Security Error: Path traversal outside workspace bounds is forbidden: <path>` | `dir_cd` |

Note the gap: `file_checksum_verifier`, `open_in_finder`, and
`reveal_in_finder` have **no** outside-workspace error — they accept
absolute paths anywhere on disk (§2.5).

### 8.4 Protected artifact

| Condition | Message | Tool |
|---|---|---|
| Deleting `agent_notes.md` | `Artifact 'agent_notes.md' is managed by its own workflow and cannot be deleted through delete_artifact.` | `delete_artifact` |

## 9. What this spec does not cover

- Tools outside the 24 in `assist-tool-catalogue.md` (notably
  `file_write`, `file_create`, `file_delete`, `use_terminal`,
  `search_*`, and the rest of the Legacy registry) are out of scope
  for Wave 1.
- The Legacy permission/approval UX around mutating tools (which
  session states expose which capabilities, the phase gate) is out of
  scope; only the per-tool `requiredPermission` derivation is
  specified here.
- SwiftCode's own MCP write policy (`swiftcode mcp --allow-writes`, the
  read-only server mode) gates the three `writes: true` tools; the
  exact user-facing behaviour when writes are disallowed is defined
  by the MCP server, not by this spec.
- `file_checksum_verifier`'s missing containment check and silent
  SHA-256 fallback, and the strict resolver's non-resolution of
  symlinks, are recorded as known Legacy behaviours to preserve or
  change deliberately — not as oversights to fix silently.

## Evidence

| Claim | Level | Source |
|---|---|---|
| Session-aware resolution: cwd-relative plain paths, leading-`/` → workspace root, symlink resolution in longest existing ancestor, containment check, `/` root fails closed, `/tmp/swiftcode/scripts` carve-out | 1 | Legacy `SwiftCode/Backend/Assist/AssistFileSystem.swift` (`resolve`, `setCurrentDirectory`, `readFile`, `currentDirectory`), read directly |
| Strict resolver: rejects empty / NUL / leading `~` / any `..`; relative → workspace root; absolute must be under root; `relative()` rendering | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistToolSharedHelpers.swift` (`AssistWorkspacePaths`); private copies in `AssistFileMetadataTool.swift`, `AssistFileHashVerifyTool.swift`, `AssistDataInspectionTools.swift` (`resolveWorkspaceDataInspectionURL`) |
| `dir_cd` / `dir_pwd` semantics, per-session in-memory store, failure leaves cwd unchanged, `.` no-op, `..` past root is an error | 1 | Legacy `Tools/AssistChangeDirectoryTool.swift`; `SwiftCode/Backend/Assist/AssistWorkingDirectoryStore.swift` |
| `file_read` line-range rules, aliases, JSON-stringified `lines`, clamping, empty-file result, numbered lines | 1 | Legacy `Tools/AssistReadFileTool.swift`, read directly |
| `file_head_preview` encoding fallback order (UTF-8 → UTF-16 → ISO Latin-1), 1…100 clamp, truncation marker | 1 | Legacy `Tools/AssistFileHeadPreviewTool.swift`, read directly |
| `file_compare_diff` positional comparison, single-hunk header, identical-file result | 1 | Legacy `Tools/AssistDataInspectionTools.swift` (`AssistFileCompareDiffTool`), read directly |
| `count_file_lines` classification heuristic, extension filter directory-only, silent skip of non-UTF-8 files, hidden/package skipping | 1 | Legacy `Tools/AssistDataInspectionTools.swift` (`AssistCountFileLinesTool`), read directly |
| `tree_view` maxDepth parsing/clamping, 2000-entry cap, symlink leaves, visited-set marker, hidden files not skipped | 1 | Legacy `Tools/AssistTreeViewTool.swift`, read directly |
| Hash tools: expected-length validation, mismatch-as-success, `/usr/bin/shasum` and `/usr/bin/md5` subprocesses, `file_checksum_verifier` silent SHA-256 fallback and no `data` | 1 | Legacy `Tools/AssistFileHashVerifyTool.swift`, `Tools/AssistFileChecksumVerifierTool.swift`, read directly |
| Scan-tool defaults/caps: `dir_size_report` limit 30/max 200, `executable_files_scan` limit 100/max 1000 with early stop, `find_duplicate_files` minSize 1 and 50-group display cap, `empty_dirs_find` hidden-entries-count rule, `symlink_audit` no hidden skipping and broken-link rule | 1 | Legacy `Tools/AssistDirSizeReportTool.swift`, `AssistExecutableFilesScanTool.swift`, `AssistFindDuplicateFilesTool.swift`, `AssistEmptyDirsFindTool.swift`, `AssistSymlinkAuditTool.swift`, `AssistFileTypeBreakdownTool.swift`, read directly |
| Artifact store layout, name normalisation, kind inference, modes, 60k read truncation, ~25k recommended ceiling, `agent_notes.md` root location and protection, index sidecar | 1 | Legacy `SwiftCode/Backend/Assist/AssistArtifactStore.swift`; `Tools/AssistToolSharedHelpers.swift` (`AssistArtifactNaming`); `Tools/AssistCreateArtifactTool.swift`, `AssistDeleteArtifactTool.swift`, `AssistReadArtifactTool.swift`, `AssistListArtifactsTool.swift`, read directly |
| Backup naming (ISO-8601 stamp with `:` → `-`), byte-count verification, no file-vs-directory check | 1 | Legacy `Tools/AssistFileBackupTool.swift`, read directly |
| Finder tools: `NSWorkspace` open / reveal, `/usr/bin/open` fallback for open only, no containment check, no fallback for reveal | 1 | Legacy `Tools/AssistFinderTools.swift`, read directly |
| Error messages and codes as tabulated | 1 | Each Legacy tool `execute()` listed above; `AssistToolResultFormatter.swift` (`AssistToolErrorCode`); `AssistModels.swift` (`AssistToolResult`) |
| `file_metadata` octal permissions without leading zero, ISO-8601 fractional-second dates, `(unknown)` handling | 1 | Legacy `Tools/AssistFileMetadataTool.swift`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
