# Assist tool catalogue — Wave 1 file tools

Ycode modules: `YcodeMCP` (the MCP server and its tools; the Wave 1 port
registers the tools below there).

This spec is the catalogue for the 24 file tools ported from SwiftCode
Legacy Assist into Ycode in Wave 1. It is the single source of truth for
each tool's ID, title, description, input schema, output shape,
capability, risk level, permission, and read/write classification. The
companion spec `assist-file-tools.md` covers the behaviour shared by
these tools: path safety, the session working directory, per-tool
defaults and caps, binary handling, the artifact store, and the full
error-case table.

Scope: exactly these 24 tools, verified live from the Legacy registry.
No other tool is in scope for Wave 1, and no tool may be invented,
renamed, or merged with another.

| ID | Title |
|---|---|
| `file_read` | Read File |
| `dir_read` | Read Directory |
| `dir_pwd` | Print Working Directory |
| `dir_cd` | Change Directory |
| `dir_size_report` | Directory Size Report |
| `file_metadata` | File Metadata |
| `file_head_preview` | File Head Preview |
| `file_compare_diff` | Compare Two Files and Generate Diff |
| `file_checksum_verifier` | File Checksum Verifier |
| `file_hash_verify` | Verify File Hash |
| `file_backup` | File Backup |
| `file_type_breakdown` | File Type Breakdown |
| `count_file_lines` | Count File Lines and Code Metrics |
| `find_duplicate_files` | Find Duplicate Files |
| `empty_dirs_find` | Find Empty Directories |
| `executable_files_scan` | Executable Files Scan |
| `tree_view` | Tree View |
| `symlink_audit` | Symlink Audit |
| `list_artifacts` | List Artifacts |
| `read_artifact` | Read Artifact |
| `create_artifact` | Create Artifact |
| `delete_artifact` | Delete Artifact |
| `open_in_finder` | Open in Finder |
| `reveal_in_finder` | Reveal in Finder |

## 1. Conventions

### 1.1 Result envelope

Every tool returns a result with these fields:

- `success` (boolean).
- `output` (string): the human-readable message, in the exact formats
  given per tool below. `<...>` placeholders are substituted, never
  shown literally.
- `data` (optional map of string to string): **all values are strings**.
  Numbers are decimal strings (`"42"`), booleans are `"true"` / `"false"`.
  A tool with no structured data returns no `data` at all (not an empty
  map). This matters: `file_checksum_verifier` returns no `data`.
- `error` / `errorCode` (on failure): the failure message and, where the
  Legacy tool supplies one, a classified error code. The code taxonomy
  is `missingArgument`, `invalidInput`, `notFound`, `permissionDenied`,
  `executionFailed`, `timeout`, `cancelled`, `resourceExhausted`,
  `unsupportedOperation`, `unknown`. Many Legacy tools return a failure
  message with **no** code; the Ycode port must preserve that (absent
  code), not invent one.
- `filesChanged` (list of workspace-relative paths): non-empty only for
  the tools that write files (`file_backup`, `create_artifact`).
- `diff` (optional string): only `file_compare_diff` sets it (it also
  copies the diff into `data["diff"]`).

Failure never returns partial `data`. A failed call returns a failure
message and no success output.

### 1.2 How capability, risk, and permission are derived

Legacy tools declare their own `capability` and `riskLevel`; routing
derives everything else from those declarations:

- `isReadOnly` is true exactly when `riskLevel` is `safeRead`.
- `isMutating` is true exactly when `riskLevel` is `safeMutation` or
  `potentiallyDestructive`.
- `isDestructive` is true exactly when `riskLevel` is
  `potentiallyDestructive`.
- `requiredPermission` (default derivation): mutating tools require
  `fileSystem`; all other tools in this catalogue require `none`. (The
  only overrides in Legacy are for screenshot / screen recording /
  `use_app` / `use_terminal`, none of which are in this catalogue.)
- `requiresVerificationAfterward` is true exactly for mutating tools.
- `outputFormat` is `file` for mutating tools, `text` otherwise.
- `resourceScope` is `Workspace Project` for all 24 tools.
- `canChainResult` is true for all 24 tools.
- Unknown tool IDs fail closed in the Legacy router: they are treated
  as `potentiallyDestructive`, mutating, and requiring verification.
  The Ycode port must do the same for any ID it does not recognise —
  never default an unknown tool to safe/read-only.

### 1.3 Legacy risk level → Ycode MCP annotations

| Legacy `riskLevel` | Ycode `MCPToolAnnotations` | `writes` |
|---|---|---|
| `safeRead` | `readOnly: true, idempotent: true` | `false` |
| `safeMutation` | `readOnly: false, idempotent: true` | `true` |
| `potentiallyDestructive` | `readOnly: false, destructive: true` | `true` |

`writes: true` applies to exactly three tools: `create_artifact`,
`file_backup`, `delete_artifact`. No other tool in this catalogue gets
`writes: true`, and no other tool writes to disk.

**Exception — the Finder tools.** `open_in_finder` and
`reveal_in_finder` declare Legacy `riskLevel: safeRead` and
`isReadOnly: true`, so the table above would give them
`readOnly: true, idempotent: true`. But their behaviour is an external
side effect: they open macOS Finder (see §25/§26). The Ycode port
must additionally set `openWorld: true` for both, must not present
them as pure reads, and must return a failure (not a silent no-op) on
non-macOS platforms, where there is no Finder. See
`assist-file-tools.md` §8.

### 1.4 Read-only vs write

21 tools are read-only. 3 tools write:

| Write tool | Capability | Risk | What it writes |
|---|---|---|---|
| `create_artifact` | `fileModification` | `safeMutation` | `.assist_temp/artifacts/<name>.md` (plus the `.artifacts_index.json` sidecar) |
| `file_backup` | `fileModification` | `safeMutation` | A timestamped `.bak` copy under `.assist_temp/backups/` |
| `delete_artifact` | `fileModification` | `potentiallyDestructive` | Permanently deletes `.assist_temp/artifacts/<name>.md` (and its index entry). No trash, no recovery. Requires `confirm: true`. `agent_notes.md` is protected and can never be deleted through this tool. |

### 1.5 Aliases — accepted, but never canonical

The Legacy registry resolves these aliases to the canonical IDs. The
Ycode port must accept the `read_file` alias for `file_read` (the
implementer note below), and should accept the others where cheap; the
canonical ID is what is registered, listed, and returned in metadata:

- `read_file`, `view_file` → `file_read`
- `directory_read`, `list_directory`, `read_dir`, `list_dir` → `dir_read`
- `open_finder` → `open_in_finder`
- `reveal_finder`, `show_in_finder` → `reveal_in_finder`

**`file_read` alias note for the implementer:** Legacy accepts
`read_file` as an alias for `file_read` (registry alias table and
router metadata both map it). Keep this alias in the Ycode port:
a call for `read_file` must behave exactly as `file_read`, including
its schema and output. Do not register `read_file` as a separate tool.

### 1.6 Collisions with Ycode's existing tools — no merging

Ycode's MCP server already has tools named `file_list` and `file_read`
(`YcodeTools+Workspace`). The Wave 1 tools are **different tools with
different IDs/schemas** and must not be merged with them:

- Ycode `file_list` takes `workspace`, an optional fnmatch `glob`,
  and `limit` (default 500) and returns `files` + `truncated`. Legacy
  `dir_read` takes a required `path` and returns sorted entries with
  `/` directory markers; Legacy `tree_view` takes `path` + `maxDepth`
  and returns a rendered tree string. Keep all three as separate
  tools.
- Ycode `file_read` takes `workspace`, `path`, `startLine` (default 1),
  `lineCount` (default to end, at most 2000), refuses files over 8 MB,
  and returns `path` / `startLine` / `endLine` / `lineCount` / `text`.
  Legacy `file_read` takes `path` + an optional nested `lines`
  `{start, end}` object, has no size cap, numbers every returned line
  as `<n>: <line>`, and returns `content` / `path` / `start` / `end` /
  `totalLines` / `fullyAvailable`. The Wave 1 port registers the Legacy
  behaviour under the Legacy schema; it must not silently adopt Ycode's
  `startLine`/`lineCount`/8 MB behaviour, and must not change the
  existing Ycode `file_read`. If the two cannot coexist under one name
  in one server, the Wave 1 registration keeps the Legacy ID and the
  conflict is escalated — it is not resolved by merging schemas.

### 1.7 Input schemas

Each tool section below transcribes its Legacy `parametersSchema`
verbatim as a JSON Schema code block: every property, its type, its
description, and the `required` list, exactly as declared. Where
Legacy declares no `enum` or `minimum`/`maximum` in the schema, none
is added here — numeric clamps and value validation live in behaviour
(see `assist-file-tools.md`), not in the schema. `additionalProperties`
is not declared by Legacy for any of these tools.

Parameter-name aliases accepted by individual `execute()`
implementations (e.g. `file_read` also accepting `filePath`) are
documented per tool under "Accepted aliases" where they exist. They
are leniency in parsing, not part of the schema.

## 2. `file_read` — Read File

- **Description (verbatim):** "Reads the content of a file at the
  specified path. Pass lines {start,end} for a 1-based inclusive line
  range; omit lines to read the whole file."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reads the content of a file at the specified path. Pass lines {start,end} for a 1-based inclusive line range; omit lines to read the whole file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "The relative path to the file from the workspace root."
    },
    "lines": {
      "type": "object",
      "description": "Optional 1-based inclusive line range. start defaults to 1, end defaults to the last line. Both must be integers >= 1; start must be <= end. Out-of-range end is clamped to the last line; out-of-range start (start > totalLines) is an error, never invented content.",
      "properties": {
        "start": {
          "type": "integer",
          "description": "1-based first line to return. Default: 1."
        },
        "end": {
          "type": "integer",
          "description": "1-based last line to return, inclusive. Default: last line."
        }
      }
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Successfully read file: <path> (lines <start>-<end> of <totalLines>)`.
Empty file: `File is empty: <path>`. Structured data keys (all strings):

| Key | Value |
|---|---|
| `content` | The selected lines, each prefixed `<lineNumber>: `, joined with `\n`. Empty string for an empty file. |
| `path` | The resolved absolute path. |
| `start` | First returned line (1-based). `"1"` for an empty file. |
| `end` | Last returned line, after clamping. `"0"` for an empty file. |
| `totalLines` | Total lines in the file. |
| `fullyAvailable` | `"true"` only when the whole file was returned (`start == 1` and clamped `end == totalLines`); otherwise `"false"`. |

**Accepted aliases:** `path` may also be given as `filePath`,
`file_path`, `targetFile`, or `file`. `lines` may also be given as a
JSON-stringified object (e.g. `"{\"start\":240,\"end\":280}"`), and its
`start`/`end` accept an integer, an integral double, or a numeric
string. The canonical alias `read_file` (and `view_file`) resolves to
this tool; see §1.5.

**Notes.** Lines are split preserving empty lines; a trailing newline
does not create a phantom line. `start > totalLines` is an error, never
invented content. `end` beyond the last line is clamped. The file must
decode as UTF-8; a binary / non-UTF-8 file fails. Absolute workspace
paths are accepted (the workspace-root prefix is stripped); paths under
`/tmp/swiftcode/scripts` are passed through unchanged (the Legacy
scripts-directory carve-out). See `assist-file-tools.md` §2–§3 for the
full line-range and path rules.

## 3. `dir_read` — Read Directory

- **Description (verbatim):** "Lists the contents of a directory
  (native ls equivalent). Returns sorted entries with directory
  markers, entry count, and the resolved path. Non-recursive — use
  tree_view for a recursive listing."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lists the contents of a directory. Returns sorted entries; directory entries are suffixed with '/'.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the directory to list. Use \".\" for the session working directory."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Successfully read directory: <path> (<count> entries)`. Structured
data keys (all strings):

| Key | Value |
|---|---|
| `contents` | Sorted entry names, one per line; directory entries suffixed with `/`. |
| `count` | Number of entries. |
| `path` | The resolved absolute path. |

**Notes.** Non-recursive. `path` is required (there is no default);
`"."` means the session working directory. Entries are sorted. A
directory entry is marked `/` only when the resolved child exists and
is a directory; an unresolvable child is listed without the marker.

## 4. `dir_pwd` — Print Working Directory

- **Description (verbatim):** "Reports the session working directory
  (native pwd equivalent)."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reports the session working directory. No parameters.",
  "properties": {},
  "required": []
}
```

**Output (success).** Message: `Working directory: <absolutePath>`.
Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | The session working directory as an absolute path. |

**Notes.** Takes no parameters; any supplied arguments are ignored.
The working directory defaults to the workspace root and changes only
via `dir_cd`. See `assist-file-tools.md` §4.

## 5. `dir_cd` — Change Directory

- **Description (verbatim):** "Changes the session working directory
  (native cd equivalent). Subsequent plain relative paths resolve
  against it; use_terminal defaults to it when workingDirectory is
  omitted. Validates existence, directory-ness, and workspace
  containment."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes (it changes
  session state, not the filesystem).
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Changes the session working directory. Path resolves against the current directory; '..' past the workspace root is an error.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Directory to change to, relative to the current directory (or workspace-root-relative with a leading '/')."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Working directory changed to <absolutePath>`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `path` | The new working directory as an absolute path. |
| `previousPath` | The working directory before the change. |
| `contents` | Sorted names of the new directory's entries, one per line (plain names, no `/` markers — unlike `dir_read`). |
| `count` | Number of entries in the new directory. |

**Notes.** `path` resolves against the current directory; `.` is a
no-op; `..` moves to the parent. The target must exist, be a
directory, and stay inside the workspace root. `..` past the workspace
root is an error, not a silent clamp. On failure the working directory
is left unchanged. The change persists for the rest of the session
(Legacy persists it per session ID; the Ycode port must scope it to
the session, never share it across sessions, and never persist it to
disk). See `assist-file-tools.md` §4.

## 6. `dir_size_report` — Directory Size Report

- **Description (verbatim):** "Reports recursive disk usage per
  immediate subdirectory of a directory, largest first."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reports subdirectory sizes.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory. Default: workspace root (.)."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum subdirectories. Default 30, max 200."
    }
  },
  "required": []
}
```

**Output (success).** Message: first line
`Directory sizes under <relativePath>:` followed by one line per
reported child, largest first:
`- <name> — <bytes> bytes (<megabytes> MB)` (megabytes with 2 decimal
places; directory names carry a trailing `/`, plain files do not).
Only the first `limit` rows are shown. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `totalBytes` | Sum of the sizes of **all** immediate children (not just the `limit` shown). |
| `entryCount` | Number of immediate children (all of them, not just the shown rows). |

**Notes.** `path` defaults to `"."`; `limit` defaults to 30 and is
clamped to 1…200. Only immediate children are listed; each
subdirectory's size is recursive. Hidden files/directories are skipped
in the enumeration. The target must be an existing directory.

## 7. `file_metadata` — File Metadata

- **Description (verbatim):** "Returns size, dates, permissions,
  type, and directory status for a file or directory inside the
  workspace."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Returns size, dates, permissions, type, and directory status for a file or directory inside the workspace.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file or directory."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message (exact lines):

```text
Metadata for <relativePath>:
- File name: <name>
- Extension: <extension or "(none)">
- Is directory: <true|false>
- File type: <type>
- Size: <bytes> bytes
- Created: <ISO-8601 with fractional seconds, or "(unknown)">
- Modified: <ISO-8601 with fractional seconds, or "(unknown)">
- Permissions (octal): <octal>
```

Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | Workspace-relative path (`"."` for the root itself). |
| `fileName` | Last path component. |
| `extension` | File extension without the dot; empty string when none. |
| `isDirectory` | `"true"` / `"false"`. |
| `fileType` | Filesystem type raw value (e.g. `regular`, `directory`, `symbolicLink`); `"unknown"` when unavailable. |
| `size` | Size in bytes. |
| `creationDate` | ISO-8601 with fractional seconds; empty string when unknown. |
| `modificationDate` | ISO-8601 with fractional seconds; empty string when unknown. |
| `permissions` | POSIX permissions as an octal string (no leading zero). |
| `permissionsOctal` | Same value as `permissions` (duplicate key, kept for compatibility). |

**Notes.** Works for files and directories. Its path resolver is the
strict per-tool variant: it rejects empty paths, NUL bytes, a leading
`~`, and any `..` component anywhere in the string. See
`assist-file-tools.md` §2.

## 8. `file_head_preview` — File Head Preview

- **Description (verbatim):** "Previews the first N lines of a file
  with encoding detection. Never dumps whole files."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Previews the head of a file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative file path."
    },
    "lines": {
      "type": "integer",
      "description": "Lines to preview. Default 20, max 100."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Preview of <path> [<encoding>, <totalLines> total lines]:` followed
by the numbered head lines (`<n>: <line>`), plus a trailing line
`… [truncated: showing <n> of <totalLines> lines]` when the file has
more lines than shown. Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | The path exactly as supplied. |
| `encoding` | Detected encoding: `utf-8`, `utf-16`, or `iso-latin-1`. |
| `totalLines` | Total lines in the file. |
| `shownLines` | Lines actually shown. |
| `truncated` | `"true"` when the file has more lines than shown; otherwise `"false"`. |

**Notes.** `lines` defaults to 20 and is clamped to 1…100. Encoding
is tried in order UTF-8, UTF-16, ISO Latin-1; a file that decodes as
none of them fails as "not decodable text (likely binary)". Unlike
`file_read`, this tool does **not** strip a phantom trailing line from
the split, so its `totalLines` can differ by one from `file_read`'s
for a file ending in a newline. See `assist-file-tools.md` §6.

## 9. `file_compare_diff` — Compare Two Files and Generate Diff

- **Description (verbatim):** "Compares two files line-by-line and
  produces a formatted unified diff with added/removed stats."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Compares two files line-by-line and produces a formatted unified diff with added/removed stats.",
  "properties": {
    "pathA": {
      "type": "string",
      "description": "Workspace-relative path to the first/original file."
    },
    "pathB": {
      "type": "string",
      "description": "Workspace-relative path to the second/modified file."
    }
  },
  "required": ["pathA", "pathB"]
}
```

**Output (success).** Identical files:
`Files \`<pathA>\` and \`<pathB>\` are identical (<lineCount> lines).`
with data `identical: "true"`, `lineCount: "<n>"`.

Differing files: message
`Unified diff for \`<pathA>\` vs \`<pathB>\` (+<added>, -<removed> lines):`
followed by the diff text. The diff text starts with the header
lines `--- a/<pathA>`, `+++ b/<pathB>`,
`@@ -1,<linesA> +1,<linesB> @@`, then one entry per line position:
unchanged lines as `  <line>`, changed lines as a `- <old>` line
followed by a `+ <new>` line, trailing lines of the longer file as
`- ` / `+ ` lines. Structured data keys (all strings):

| Key | Value |
|---|---|
| `pathA` | First path exactly as supplied. |
| `pathB` | Second path exactly as supplied. |
| `addedLines` | Number of added lines. |
| `removedLines` | Number of removed lines. |
| `identical` | `"false"`. |
| `diff` | The full diff text (also returned as the result's top-level `diff` field). |

**Accepted aliases:** `pathA` may also be given as `fileA`;
`pathB` may also be given as `fileB`.

**Notes.** This is a **positional** line-by-line comparison, not a
real diff algorithm: there is no longest-common-subsequence matching
and no hunks — a single inserted line shifts every following line
into a `-`/`+` pair, and the header is always one hunk spanning both
whole files. The Ycode port must reproduce this exact behaviour, not
substitute a smarter diff. Both files must decode as UTF-8. See
`assist-file-tools.md` §5.

## 10. `file_checksum_verifier` — File Checksum Verifier

- **Description (verbatim):** "Computes and verifies SHA-256, SHA-1,
  or MD5 cryptographic hashes for workspace files."
- **Capability:** `diagnostics`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Calculates cryptographic digests (SHA-256, SHA-1, MD5) for file integrity validation.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Relative path to file in workspace."
    },
    "algorithm": {
      "type": "string",
      "description": "Hash algorithm: 'sha256', 'sha1', 'md5'. Defaults to 'sha256'."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message (exact):

```text
Checksum for `<path>`:
- Algorithm: <ALGORITHM-UPPERCASE>
- Digest: `<lowercase-hex>`
- Byte Size: <bytes> bytes
```

**No structured data is returned** — this is the only tool in the
catalogue that returns a message with no `data`.

**Notes — honest discrepancies the port must preserve or fix
deliberately.**

- Despite the name and description, this tool **never verifies**
  anything: it takes no expected hash and compares against nothing.
  It only computes and reports a digest. Verification is
  `file_hash_verify` (§11). The Ycode port must not claim verification
  for this tool; if the description is kept, the behaviour stays
  compute-only.
- `algorithm` is lowercased; an unrecognised value **silently falls
  back to SHA-256** (the switch's default branch) instead of failing.
  This differs from `file_hash_verify`, which rejects an unknown
  algorithm. The port must preserve the silent fallback unless a later
  decision explicitly changes it — and if changed, that change is a
  behaviour change to record, not a silent fix.
- Path handling is the loose variant: an absolute path is used
  verbatim and a relative path is appended to the workspace root,
  with **no workspace-containment check**. See
  `assist-file-tools.md` §2.5.
- Digests are computed in-process (CryptoKit in Legacy); no
  subprocess is involved.

## 11. `file_hash_verify` — Verify File Hash

- **Description (verbatim):** "Computes a file hash with shasum or
  md5 and compares it to an expected hash. A mismatch is reported as
  a successful comparison with match false, not as a tool error."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Computes a file hash and compares it to an expected hash.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to hash."
    },
    "expectedHash": {
      "type": "string",
      "description": "Expected hash in hexadecimal."
    },
    "algorithm": {
      "type": "string",
      "description": "Hash algorithm: sha256, sha1, or md5. Default: sha256."
    }
  },
  "required": ["path", "expectedHash"]
}
```

**Output (success).** Match:
`Hash match: true. <algorithm> of <relativePath> matches the expected hash.`
Mismatch:
`Hash match: false. <algorithm> of <relativePath> is <computed>, expected <expected>.`
A mismatch is a **success** with `match: "false"`, never an error.
Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | Workspace-relative path. |
| `algorithm` | Normalised algorithm (`sha256`, `sha1`, or `md5`). |
| `computedHash` | Lowercase hex digest actually computed. |
| `expectedHash` | Expected hash, trimmed and lowercased. |
| `match` | `"true"` / `"false"`. |

**Notes.** Expected hex lengths are enforced: SHA-256 = 64, SHA-1 =
40, MD5 = 32 characters, all hex digits; anything else is an error
(see `assist-file-tools.md` §5). Legacy computes the hash by running
`/usr/bin/shasum` (`-a 256` / `-a 1`) or `/usr/bin/md5` (`-q`) — those
are macOS-only paths, so the Ycode port must hash in-process (e.g.
CryptoKit / swift-crypto) while keeping the observable behaviour
identical, including the failure message when hashing fails
(`Failed to compute <algorithm> for <path>.`). The target must be an
existing file; a directory fails.

## 12. `file_backup` — File Backup

- **Description (verbatim):** "Backs up a workspace file to
  .assist_temp/backups/<name>.<timestamp>.bak before a risky edit."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false, idempotent: true`.
  **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Backs up a file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative file to back up."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Backed up <path> to <backupRelativePath> (<bytes> bytes).`
Structured data keys (all strings):

| Key | Value |
|---|---|
| `source` | The path exactly as supplied. |
| `backup` | Workspace-relative backup path, `.assist_temp/backups/<name>.<stamp>.bak`. |
| `bytes` | Byte count of the source file. |

`filesChanged` is `[<backupRelativePath>]`.

**Notes.** The backup directory `.assist_temp/backups/` is created
(including intermediates) if missing. The stamp is an ISO-8601
timestamp with `:` replaced by `-` (e.g.
`2026-11-05T22-52-44Z`). The copy is verified by byte count: if the
backup's size differs from the source's, the backup is deleted and
the tool fails with
`Backup verification failed (size mismatch); backup removed.`
The tool checks only that the path exists — it does not check that
it is a file rather than a directory. See `assist-file-tools.md` §7.

## 13. `file_type_breakdown` — File Type Breakdown

- **Description (verbatim):** "Breaks down a directory by file
  extension: file counts and total bytes per type."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Breaks down files by extension.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory. Default: workspace root (.)."
    }
  },
  "required": []
}
```

**Output (success).** Message:
`File type breakdown for <path>:` followed by a Markdown table with
headers `Extension | Files | Bytes`, one row per extension, sorted by
file count descending. Extensions are lowercased with a leading dot
(`.swift`); files with no extension are grouped under
`(no extension)`. Structured data keys (all strings):

| Key | Value |
|---|---|
| `typeCount` | Number of distinct extension groups. |

**Notes.** `path` defaults to `"."`. The walk is recursive and skips
hidden files. Directories are not counted; only files contribute to
counts and bytes. The message carries the full table; the structured
data carries only the group count.

## 14. `count_file_lines` — Count File Lines and Code Metrics

- **Description (verbatim):** "Calculates total lines, code lines,
  comment lines, and blank lines across workspace files."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Calculates total lines, code lines, comment lines, and blank lines across workspace files.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to a file or directory to analyze."
    },
    "extension": {
      "type": "string",
      "description": "Optional extension filter when analyzing directory (e.g. 'swift', 'm', 'h')."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message (exact lines):

```text
Code Metrics for <path> (<fileCount> file(s)):
- Total Lines: <totalLines>
- Code Lines: <codeLines>
- Comment Lines: <commentLines>
- Blank Lines: <blankLines>
- Total File Size: <human-readable size> (<totalBytes> bytes)
```

Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | The path exactly as supplied. |
| `fileCount` | Number of files analysed. |
| `totalLines` | Total lines across all files. |
| `codeLines` | Lines classified as code. |
| `commentLines` | Lines classified as comments. |
| `blankLines` | Blank lines. |
| `totalBytes` | Total bytes across all files. |

**Accepted aliases:** `path` may also be given as `targetPath`.

**Notes.** Line classification, per line after trimming whitespace:
blank → blank; starts with `//`, `/*`, `*`, or `#` → comment;
otherwise → code. This is a prefix heuristic, not a parser (a line
starting with `*` inside a block comment and a `#` preprocessor line
both count as comments; a trailing `//` comment on a code line counts
as code). When `path` is a directory the walk is recursive, skips
hidden files and package descendants, and only regular files are
counted; the `extension` filter (compared lowercased, without a dot)
applies only to directories — a single file is analysed regardless of
the filter. Files that do not decode as UTF-8 are **silently skipped**
from the counts but still included in `fileCount`. See
`assist-file-tools.md` §5.

## 15. `find_duplicate_files` — Find Duplicate Files

- **Description (verbatim):** "Finds byte-identical duplicate files
  under a directory using SHA-256 content hashing."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds duplicate files by content hash.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory. Default: workspace root (.)."
    },
    "minSize": {
      "type": "integer",
      "description": "Ignore files smaller than this many bytes. Default 1."
    }
  },
  "required": []
}
```

**Output (success).** No duplicates:
`No duplicate files found under <path>.` with data
`groupCount: "0"`. Duplicates found:
`Duplicate file groups (<groupCount>):` followed by at most 50 lines,
one per group: `- <path1>, <path2>, ...` (paths within a group sorted,
groups sorted by first path). Structured data keys (all strings):

| Key | Value |
|---|---|
| `groupCount` | Total number of duplicate groups (the full count, even when only 50 are shown). |

**Notes.** `path` defaults to `"."`; `minSize` defaults to 1 and is
clamped to a minimum of 0 (a negative value behaves as 0). Files are
first grouped by size, then same-size files are SHA-256-hashed
(streamed in 1 MB chunks) and grouped by digest; only groups of two
or more count. Hidden files are skipped. Only the first 50 groups are
listed in the message; `groupCount` is not capped.

## 16. `empty_dirs_find` — Find Empty Directories

- **Description (verbatim):** "Finds empty directories under a path —
  candidates for cleanup."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds empty directories.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory. Default: workspace root (.)."
    }
  },
  "required": []
}
```

**Output (success).** None found:
`No empty directories under <path>.` with data `count: "0"`. Found:
`Empty directories (<count>):` followed by one line per directory:
`- <relativePath>/`. Structured data keys (all strings):

| Key | Value |
|---|---|
| `count` | Number of empty directories found. |

**Notes.** `path` defaults to `"."`. "Empty" means the directory
contains no entries at all as reported by a plain directory listing
(hidden entries count as entries, so a directory containing only a
hidden file is not empty). The search is recursive; the starting
directory itself is never reported (only its descendants). Results
are sorted.

## 17. `executable_files_scan` — Executable Files Scan

- **Description (verbatim):** "Lists files with the executable bit
  set under a directory — a hygiene check for accidental +x bits in
  repos."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans for executable files.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory. Default: workspace root (.)."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum results. Default 100, max 1000."
    }
  },
  "required": []
}
```

**Output (success).** None found:
`No executable files under <path>.` with data `count: "0"`. Found:
`Executable files under <path> (<count>):` followed by one line per
file: `- <relativePath>` (sorted). Structured data keys (all strings):

| Key | Value |
|---|---|
| `count` | Number of executable files found (at most `limit`). |

**Notes.** `path` defaults to `"."`; `limit` defaults to 100 and is
clamped to 1…1000. The walk is recursive and skips hidden files.
Enumeration stops as soon as `limit` hits are collected, so with a
small `limit` the scan may not visit the whole tree. "Executable"
means the file has any executable permission bit set, as reported by
the platform's executable check.

## 18. `tree_view` — Tree View

- **Description (verbatim):** "Generates a tree-like representation
  of the project structure."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Generates a tree-like representation of the project structure. Symlinks are listed as leaves, never followed (prevents symlink-cycle recursion). Output is capped; a truncation marker is appended when the cap is hit.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to render. Default: \".\" (workspace root)."
    },
    "maxDepth": {
      "type": "integer",
      "description": "Maximum tree depth. Clamped to 1...10. Default: 3."
    }
  },
  "required": []
}
```

**Output (success).** Message: `Project Tree generated`. Structured
data keys (all strings):

| Key | Value |
|---|---|
| `tree` | The rendered tree, with `\n… [truncated at 2000 entries]` appended when the entry cap was hit. |
| `path` | The resolved absolute path of the tree root. |
| `entries` | Number of entries emitted (the root itself is not counted). |
| `truncated` | `"true"` when the 2000-entry cap was hit; otherwise `"false"`. |

**Notes.** Tree format: the root line is `📂 <name>`; each level is
indented by two spaces; directories recurse; files are `📄 <name>`;
symlinks are `🔗 <name>` leaves and are **never followed**. A
directory whose canonical path was already visited renders as
`↩︎ [already visited: <name>]` instead of recursing. Entries within a
directory are sorted by name. `maxDepth` defaults to 3 and is clamped
to 1…10; a non-integer or `< 1` value is an error
(`Invalid maxDepth: must be an integer >= 1 (got '<value>').`).
`maxDepth` bounds directory descent: files directly inside a
directory at the maximum depth are still listed, but subdirectories
below it are not. The entry cap is 2000; when hit, rendering stops
and the truncation marker is appended. Unlike most tools in this
catalogue, the walk does **not** skip hidden files. See
`assist-file-tools.md` §3 and §5.

## 19. `symlink_audit` — Symlink Audit

- **Description (verbatim):** "Finds symbolic links under a
  directory, reporting each target and flagging broken links."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits symbolic links.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory. Default: workspace root (.)."
    }
  },
  "required": []
}
```

**Output (success).** None found:
`No symbolic links under <path>.` with data `count: "0"`,
`brokenCount: "0"`. Found:
`Symbolic links under <path> (<count>, <brokenCount> broken):`
followed by one line per link, sorted by path:
`- <relativePath> -> <target>` with ` [BROKEN]` appended for broken
links. Structured data keys (all strings):

| Key | Value |
|---|---|
| `count` | Number of symbolic links found. |
| `brokenCount` | Number of those links whose target does not exist. |

**Notes.** `path` defaults to `"."`. The walk is recursive and does
**not** skip hidden files. A link is broken when its target does not
exist: a relative target is resolved against the link's parent
directory, an absolute target is used as-is. The reported target is
the raw destination string, or `(unknown)` when it cannot be read.
There is no result limit.

## 20. `list_artifacts` — List Artifacts

- **Description (verbatim):** "Lists all Markdown artifacts in the
  native artifact store, including agent_notes.md, newest first."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lists artifacts.",
  "properties": {},
  "required": []
}
```

**Output (success).** None:
`No artifacts yet. Use create_artifact to produce the first one.`
with data `count: "0"`. Found: `Artifacts (<count>):` followed by one
line per artifact:
`- <Title> [<Kind display name>] — <relativePath>` with
` — <description, first 100 characters>` appended when the artifact
has a description. Structured data keys (all strings):

| Key | Value |
|---|---|
| `count` | Number of artifacts listed. |

**Notes.** Takes no parameters. The list is newest first (by
modification date). It includes `agent_notes.md`, which lives at the
workspace root (not in the artifact store directory) and is listed
with relative path `agent_notes.md`. Kind display names: `Artifact`,
`Agent Notes`, `Execution Plan`, `Image Screenshot`,
`Screen Recording`. See `assist-file-tools.md` §7.

## 21. `read_artifact` — Read Artifact

- **Description (verbatim):** "Reads a Markdown artifact's full
  content from the native artifact store (truncated at 60k
  characters)."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reads an artifact's content.",
  "properties": {
    "name": {
      "type": "string",
      "description": "Artifact name (snake_case, .md optional). Example: repository_analysis"
    }
  },
  "required": ["name"]
}
```

**Output (success).** Message: `# <Title>` followed by a blank line
and then the artifact content. The content itself is **not** in the
structured data — only its length is. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `filename` | Normalised filename, e.g. `repository_analysis.md`. |
| `title` | Display title derived from the filename. |
| `kind` | Kind raw value: `artifact`, `agent_notes`, `execution_plan`, `image`, or `screen_recording`. |
| `truncated` | `"true"` when the content exceeded 60,000 characters; otherwise `"false"`. |
| `contentLength` | Character count of the returned (possibly truncated) content. |

**Notes.** Content is truncated at 60,000 characters; a truncated
read appends
`\n… [truncated: showing first 60000 of <total> characters. The recommended write ceiling for new artifacts is ~25,000 characters — link workspace files instead of pasting them whole.]`
The name is normalised the same way as for `create_artifact`
(lowercased, spaces/hyphens to underscores, `.md` enforced); an
unsafe name fails. `agent_notes.md` is readable through this tool.
See `assist-file-tools.md` §7.

## 22. `create_artifact` — Create Artifact

- **Description (verbatim):** "Creates (or updates/appends) a
  Markdown artifact in the native artifact store at
  .assist_temp/artifacts/<name>.md. The single way to produce durable
  deliverables. Optional kind parameter: \"artifact\" (default) or
  \"execution_plan\" for multi-phase plans/handoffs; when omitted, the
  store infers the kind from the filename. Keep content to a
  recommended ~25,000-character ceiling."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false, idempotent: true`.
  **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a Markdown artifact.",
  "properties": {
    "name": {
      "type": "string",
      "description": "Artifact name, snake_case (.md added automatically). Example: repository_analysis"
    },
    "content": {
      "type": "string",
      "description": "Full Markdown document content."
    },
    "description": {
      "type": "string",
      "description": "One-line description shown in the artifact list. Default: first meaningful line."
    },
    "mode": {
      "type": "string",
      "description": "create (default) | update | append."
    },
    "kind": {
      "type": "string",
      "description": "artifact (default) | execution_plan. Use execution_plan for multi-phase work plans and handoff documents; use artifact for everything else. When omitted, the store infers the kind from the filename (contains _plan, or starts/ends with plan_)."
    }
  },
  "required": ["name", "content"]
}
```

**Output (success).** Message:
`Artifact '<Title>' saved (<mode>) at <relativePath>.`
Structured data keys (all strings):

| Key | Value |
|---|---|
| `filename` | Normalised filename, e.g. `repository_analysis.md`. |
| `title` | Display title derived from the filename. |
| `relativePath` | `.assist_temp/artifacts/<filename>`. |
| `mode` | The mode actually used, lowercased (`create`, `update`, or `append`). |
| `kind` | Kind raw value (`artifact` or `execution_plan` for this tool). |
| `contentLength` | Character count of the supplied `content` (not the final file length after an append). |

`filesChanged` is `[<relativePath>]`.

**Notes.** Modes: `create` fails if the artifact already exists;
`update` fails if it does not exist; `append` creates it if missing,
otherwise appends after a blank line. Content is trimmed and stored
with a trailing newline; the write is verified by reading the file
back. Kind: an explicit `kind` always wins; when omitted, the kind is
inferred from the filename — execution plan only when the stem
contains `_plan`, starts with `plan_`, or ends with `_plan` (a bare
`plan` substring, e.g. `airplane_notes.md`, does **not** count).
`~25,000` characters is a recommended ceiling, not an enforced limit.
See `assist-file-tools.md` §7.

## 23. `delete_artifact` — Delete Artifact

- **Description (verbatim):** "Permanently deletes a Markdown
  artifact from the native artifact store. agent_notes.md is protected
  and cannot be deleted."
- **Capability:** `fileModification`. **Risk:**
  `potentiallyDestructive`. **Required permission:** `fileSystem`.
  **Read-only:** no. **Write — destructive, permanent.**
  **MCP annotations:** `readOnly: false, destructive: true`.
  **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Deletes an artifact permanently.",
  "properties": {
    "name": {
      "type": "string",
      "description": "Artifact name (snake_case, .md optional)."
    },
    "confirm": {
      "type": "boolean",
      "description": "Must be true to delete. Safety interlock."
    }
  },
  "required": ["name", "confirm"]
}
```

**Output (success).** Message:
`Artifact '<filename>' deleted permanently.`
Structured data keys (all strings):

| Key | Value |
|---|---|
| `filename` | Normalised filename of the deleted artifact. |

**Notes.** `confirm` must be the boolean `true`; anything else
(including a missing value, `false`, or the string `"true"`) fails
with `Deletion requires confirm: true. The artifact was NOT deleted.`
and nothing is deleted. `agent_notes.md` is protected: deleting it
fails with
`Artifact 'agent_notes.md' is managed by its own workflow and cannot be deleted through delete_artifact.`
The delete is permanent — there is no trash, no backup, and no
undo. The artifact's index entry is removed along with the file. See
`assist-file-tools.md` §7.

## 24. `open_in_finder` — Open in Finder

- **Description (verbatim):** "Opens a file or directory in Finder
  or its default application."
- **Capability:** `systemExecution`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes in the Legacy
  declaration — but see the warning below: this is an external side
  effect, not a pure read.
  **MCP annotations:** `readOnly: true, idempotent: true`,
  **plus `openWorld: true`** (see §1.3).
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Opens a file or directory in macOS Finder or default application.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative or absolute path to the file or directory."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Opened in Finder: <lastPathComponent>`. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `path` | The target as an absolute path. |

**Notes.** Opens the target with the macOS Finder / its default
application: a directory opens in a Finder window; a file opens in
its default application. If the Finder open reports failure, Legacy
falls back to running `/usr/bin/open <path>` and succeeds only if
that exits 0. **macOS-only**: on a platform without Finder /
`NSWorkspace` / `/usr/bin/open` the Ycode port must fail with a clear
error, never silently succeed. No workspace-containment check is
applied: an absolute path is used as-is and a relative path is
appended to the workspace root. The target must exist. See
`assist-file-tools.md` §8.

## 25. `reveal_in_finder` — Reveal in Finder

- **Description (verbatim):** "Reveals and selects a file or
  directory in macOS Finder."
- **Capability:** `systemExecution`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes in the Legacy
  declaration — but see the warning below: this is an external side
  effect, not a pure read.
  **MCP annotations:** `readOnly: true, idempotent: true`,
  **plus `openWorld: true`** (see §1.3).
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reveals and highlights a file or directory in Finder.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative or absolute path to the item to reveal."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Revealed in Finder: <lastPathComponent>`. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `path` | The target as an absolute path. |

**Notes.** Reveals and selects the target in a Finder window (the
Finder is brought forward with the item highlighted). Unlike
`open_in_finder` there is no `/usr/bin/open` fallback: the reveal is
attempted once and success is reported unconditionally after the call
returns. **macOS-only**: on a platform without Finder the Ycode port
must fail with a clear error, never silently succeed. No
workspace-containment check is applied: an absolute path is used
as-is and a relative path is appended to the workspace root. The
target must exist. See `assist-file-tools.md` §8.

## 26. Summary: capability / risk / permission / writes

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `file_read` | fileReading | safeRead | none | yes | false |
| `dir_read` | fileReading | safeRead | none | yes | false |
| `dir_pwd` | fileReading | safeRead | none | yes | false |
| `dir_cd` | fileReading | safeRead | none | yes | false |
| `dir_size_report` | fileReading | safeRead | none | yes | false |
| `file_metadata` | fileReading | safeRead | none | yes | false |
| `file_head_preview` | fileReading | safeRead | none | yes | false |
| `file_compare_diff` | fileReading | safeRead | none | yes | false |
| `file_checksum_verifier` | diagnostics | safeRead | none | yes | false |
| `file_hash_verify` | fileReading | safeRead | none | yes | false |
| `file_backup` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `file_type_breakdown` | fileReading | safeRead | none | yes | false |
| `count_file_lines` | fileReading | safeRead | none | yes | false |
| `find_duplicate_files` | fileReading | safeRead | none | yes | false |
| `empty_dirs_find` | fileReading | safeRead | none | yes | false |
| `executable_files_scan` | fileReading | safeRead | none | yes | false |
| `tree_view` | repositoryDiscovery | safeRead | none | yes | false |
| `symlink_audit` | fileReading | safeRead | none | yes | false |
| `list_artifacts` | fileReading | safeRead | none | yes | false |
| `read_artifact` | fileReading | safeRead | none | yes | false |
| `create_artifact` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `delete_artifact` | fileModification | potentiallyDestructive | fileSystem | **no** | **true** |
| `open_in_finder` | systemExecution | safeRead | none | yes* | false |
| `reveal_in_finder` | systemExecution | safeRead | none | yes* | false |

\* Declared read-only in Legacy, but an external side effect in
fact: both open Finder windows. Ycode must add `openWorld: true` and
fail on non-macOS. See §1.3 and §24–§25.

## Wave 2 — file-writing tools

This part of the catalogue covers the 24 Wave 2 tools: the
file-writing family ported from SwiftCode Legacy Assist into Ycode
in Wave 2. The Wave 1 conventions in §1 apply, extended by §27
below. The companion spec `assist-file-writing-tools.md` covers
the behaviour shared by these tools, and
`assist-approval-model.md` covers how their writes are gated.

Scope: exactly these 24 tools, verified live from the Legacy
registry. No other tool is in scope for Wave 2, and no tool may be
invented, renamed, or merged with another — except `file_write`,
which already exists in Ycode and is aligned, not duplicated (see
§28).

| ID | Title |
|---|---|
| `file_write` | Write File |
| `file_create` | Create File |
| `file_append` | Append to File |
| `file_delete` | Delete File |
| `file_move` | Move File |
| `file_copy` | Copy File |
| `file_rename` | Rename File |
| `dir_create` | Create Directory |
| `dir_delete` | Delete Directory |
| `code_generate` | Generate File |
| `code_format` | Format Code |
| `code_insert` | Insert Code Block |
| `code_multi_edit` | Multi-file Edit |
| `code_refactor` | Refactor |
| `code_replace` | Replace in File |
| `regex_replace_in_files` | Regex Replace in Files |
| `plist_edit` | Edit Plist |
| `format_json_file` | Format and Validate JSON File |
| `csv_to_json` | Convert CSV to JSON |
| `json_to_csv` | Convert JSON to CSV |
| `plist_to_json` | Convert Plist to JSON |
| `json_to_plist` | Convert JSON to Plist |
| `batch_rename_files` | Batch Rename Files |
| `generate_file_checksum` | Generate File Cryptographic Checksum |

**The 24th tool.** The subsystem map (§2.1) says this family is
24 tools but its printed list names only 23. The 24th is
`file_create`: the registry registers `AssistCreateFileTool()` at
line 75, and the tool declares `id = "file_create"`
(`Tools/AssistCreateFileTool.swift:4`, capability
`fileModification`, risk `safeMutation`). The list above is the
23 named tools plus `file_create`.

**The read-only tool in this wave.** `generate_file_checksum`
declares capability `fileReading` and risk `safeRead` and only
computes hashes (SHA-256 / SHA-512 / SHA-1 / MD5) — it writes
nothing. It stays in this wave because the map assigned it here,
but it is specified as a read-only tool (`writes: false`), and
its family classification is corrected here: it is a
file-reading / diagnostics tool, not a file-writing tool. See
§27.4 and §51.

## 27. Wave 2 conventions (extending §1)

### 27.1 Result envelope — Wave 2 additions

§1.1 applies unchanged, with two Wave 2 notes:

- `filesChanged` (list of workspace-relative paths) is non-empty
  for the tools that change files and report it. Four Wave 2
  tools change files but return **no** `filesChanged` in Legacy
  (`file_append`, `file_move`, `file_copy`, `code_generate`) and
  one returns none in any outcome (`regex_replace_in_files`);
  the port preserves that (see the per-tool sections), it does
  not "fix" it.
- `diff` (optional string): `file_write`, `file_create`, and
  `code_replace` set it (and also copy the diff into
  `data["diff"]`). No other Wave 2 tool sets it. Legacy-only
  envelope fields (`duration`, `suggestedNextActions`,
  `beforeContent`, `afterContent`) have no Ycode equivalent and
  are dropped; see `assist-file-writing-tools.md` §8.4.

### 27.2 Risk → annotations for Wave 2

§1.3 applies unchanged:

| Legacy `riskLevel` | Ycode `MCPToolAnnotations` | `writes` |
|---|---|---|
| `safeRead` | `readOnly: true, idempotent: true` | `false` |
| `safeMutation` | `readOnly: false, idempotent: true` | `true` |
| `potentiallyDestructive` | `readOnly: false, destructive: true` | `true` |

`writes: true` applies to exactly 23 tools in this wave — every
tool below except `generate_file_checksum`. The two
`potentiallyDestructive` tools are `file_delete` and
`dir_delete`; every other writing tool is `safeMutation`.

### 27.3 Gate per tool

Every `writes: true` tool is gated by `MCPServer.run()` and its
handler-side shape — see `assist-approval-model.md` §6 for the
full table. In short: text writes go through `commit()`;
copy/move/rename/delete/directory/binary-plist operations use an
explicit `MCPChange` + `guard await call.approve(change)` before
touching disk; multi-file tools approve one file at a time, in
order, stopping at the first refusal; dry-run calls
(`regex_replace_in_files`, `batch_rename_files` with
`dryRun: true`) request no approval but are still refused in
`readOnly` mode because the tool is registered `writes: true`.

### 27.4 The checksum correction

`generate_file_checksum` is catalogued with the Wave 2 tools
because the subsystem map assigned it to this family, but its
Legacy declaration is `capability: fileReading`, `riskLevel:
safeRead`, `isReadOnly: true`. It therefore takes the `safeRead`
row of the §1.3 table (`readOnly: true, idempotent: true`,
`writes: false`), runs in `readOnly` server mode, and never calls
`approve()` or `commit()`. Its presence here corrects the map's
family assignment; a future re-organisation of the catalogue may
move it with the read tools without changing its specification.

### 27.5 Aliases — accepted, but never canonical

The Legacy registry resolves these aliases to the canonical IDs
in this wave. The Ycode port must accept them at `tools/call`
time (through `MCPServer.toolAliases`, as Wave 1 did for
`read_file`); the canonical ID is what is registered, listed,
and returned in metadata:

- `write_file` → `file_write`
- `create_file` → `file_create`
- `delete_file` → `file_delete`
- `move_file` → `file_move`
- `copy_file` → `file_copy`
- `rename_file` → `file_rename`
- `create_directory`, `make_directory`, `directory_create` → `dir_create`
- `delete_directory`, `remove_directory`, `directory_delete` → `dir_delete`
- `edit_file`, `replace_in_file` → `code_replace`
- `insert_code_block`, `insert_code` → `code_insert`
- `regex_replace` → `regex_replace_in_files`

No registry alias exists for `file_append`, `code_generate`,
`code_format`, `code_multi_edit`, `code_refactor`,
`format_json_file`, `csv_to_json`, `json_to_csv`,
`plist_to_json`, `json_to_plist`, `batch_rename_files`,
`plist_edit`, or `generate_file_checksum`. In particular, the
registry alias `plist` points at `plist_editor`, a different
tool — it is **not** an alias for `plist_edit` — and
`checksum_verifier` points at `file_checksum_verifier`, a
different tool — it is **not** an alias for
`generate_file_checksum`. Do not add either mapping.

Per-tool parameter-name aliases (e.g. `file_write` accepting
`filePath`) are documented per tool under "Accepted aliases"
where they exist. They are leniency in parsing, not part of the
schema — as in §1.7.

### 27.6 `file_write` collision — align, do not duplicate

Ycode already has a `file_write` in `YcodeTools+Content.swift`
(`workspace` / `path` / `content`; returns `path` / `created` /
`lineCount`; writes through `commit()`). The Wave 1 precedent
for the `file_read` collision was to **align** the existing
Ycode tool with Legacy behaviour (the Ycode `file_read` gained
Legacy's `lines` object while keeping its own `startLine` /
`lineCount` / 8 MB behaviour), not to register a duplicate. The
same applies here: there is exactly one `file_write`
registration, the existing one, aligned as specified in §28. No
second `file_write` is specified or registered.

## 28. `file_write` — Write File (aligned with Ycode's existing tool)

- **Description (verbatim):** "Writes or overwrites a file with
  the specified content, generating unified diffs."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Writes or overwrites a file with the specified content.",
  "properties": {
    "path": {
      "type": "string",
      "description": "The relative path to write the file within the project workspace."
    },
    "content": {
      "type": "string",
      "description": "The complete content to write into the file."
    }
  },
  "required": ["path", "content"]
}
```

**Output (success).** Message:
`Created new file: <path> (<N> lines)` when the file did not
exist, `Updated existing file: <path> (<N> lines)` when it did,
where `<N>` counts `content` split on newlines (a trailing
newline counts as an extra empty line). Structured data keys
(all strings):

| Key | Value |
|---|---|
| `diff` | Unified diff (Myers, 3 context lines) from the original content to the new content. |
| `path` | The path as given (workspace-relative). |
| `is_new` | `"true"` when the file did not exist before the call, `"false"` otherwise. |

`filesChanged` is `[<path>]`, and the `diff` field of the result
is the same unified diff.

**Accepted aliases:** `path` may also be given as `filePath`
or `file_path`; `content` may also be given as `fileContent`,
`file_content`, or `code`. The canonical alias `write_file`
resolves to this tool; see §27.5.

**Alignment note (Ycode's existing `file_write` vs Legacy).**
The single registration is Ycode's, in
`YcodeTools+Content.swift`; align it to Legacy as follows, and
register nothing else under this ID:

- Input: keep Ycode's `workspace` parameter (Ycode convention;
  every Ycode tool takes it) and its required `[path,
  content]`. Add Legacy's parameter aliases above, which Ycode
  does not currently accept.
- Description: adopt Legacy's verbatim description above; Ycode's
  current description ("Creates a file or replaces its whole
  contents…") is replaced, not kept alongside.
- Annotations: Ycode currently registers this tool with
  `readOnly: false, destructive: true`. Legacy declares
  `safeMutation`, which maps (§27.2) to `readOnly: false,
  idempotent: true` — **not** destructive. Change the
  annotations to match; a whole-file overwrite is a safe
  mutation in Legacy's classification, and only
  `potentiallyDestructive` tools get `destructive: true`.
- Output: adopt Legacy's message forms above (Ycode currently
  returns `Created <rel>.` / `Wrote <rel>.`). Keep Ycode's data
  keys `created` (boolean, same meaning as Legacy's `is_new`)
  and `lineCount`, and add Legacy's `diff` and `is_new` keys.
  The line counts agree: Ycode's
  `content.split(separator: "\n", omittingEmptySubsequences:
  false).count` and Legacy's
  `content.components(separatedBy: .newlines).count` give the
  same number for the same content. Keep `filesChanged`
  behaviour (Ycode's `commit()` already notifies the session).
- Behaviour deltas that are **not** aligned (deliberate
  deviations, see `assist-approval-model.md` §7.4): Legacy
  auto-registers a new file in the `.pbxproj`
  (`XcodeProjWriter.addFileReference`) and streams the edit
  through `LiveDiffStreamer`; Ycode does neither. Legacy's
  `suggestedNextActions: ["project_build"]` (duplicated for
  `.swift` files) has no Ycode equivalent and is dropped.
- Path handling: Legacy's inline `..` check (§2.4 of
  `assist-file-writing-tools.md`) and the session-aware resolver
  already match what Ycode's `resolve` + `commit()` do, except
  the `/tmp/swiftcode/scripts` carve-out, which Ycode does not
  keep (see `assist-approval-model.md` §7.2).

## 29. `file_create` — Create File

- **Description (verbatim):** "Creates a new file with full
  content and intermediate directories when needed."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a new file with full content, creating intermediate directories when needed.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to create. Must be non-blank."
    },
    "content": {
      "type": "string",
      "description": "File body. Default: \"\"."
    },
    "overwrite": {
      "type": "boolean",
      "description": "Must be true to replace an existing file. Default: false."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Created file at <path> (<N> lines)`, where `<N>` counts
`content` split on newlines (same counting as `file_write`).
Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |
| `bytes` | UTF-8 byte count of `content`. |
| `diff` | Unified diff from empty to `content`. |
| `is_new` | Always `"true"` — even when `overwrite: true` replaced an existing file (Legacy quirk; see `assist-file-writing-tools.md` §4.4). |

`filesChanged` is `[<path>]`, and the `diff` field of the result
is the same unified diff.

**Accepted aliases:** none at the parameter level. The canonical
alias `create_file` resolves to this tool; see §27.5.

**Notes.** `content` defaults to `""` when absent; `overwrite`
defaults to `false`. An existing file with `overwrite` false
fails with
`File already exists at <path>. Set overwrite=true to replace it.`
(code `invalidInput`). Missing parent directories are created.
See `assist-file-writing-tools.md` §4.3–§4.4 and §5.1.

## 30. `file_append` — Append to File

- **Description (verbatim):** "Appends content to the end of a
  file."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Appends content to the end of an existing file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the existing file to append to. The file must already exist."
    },
    "content": {
      "type": "string",
      "description": "Text content to append to the end of the file."
    }
  },
  "required": ["path", "content"]
}
```

**Output (success).** Message:
`Successfully appended to file: <path>`. No structured data,
no `filesChanged` — even though the file changed (Legacy quirk;
see `assist-file-writing-tools.md` §5.1).

**Accepted aliases:** none.

**Notes.** The file must already exist; a missing file fails.
The append is a read-modify-write of the whole file
(`original + content`), verbatim, with no newline added or
normalised. See `assist-file-writing-tools.md` §5.1.

## 31. `file_delete` — Delete File

- **Description (verbatim):** "Deletes a file at the specified
  path."
- **Capability:** `fileModification`. **Risk:**
  `potentiallyDestructive`. **Required permission:**
  `fileSystem`. **Read-only:** no. **Write — destructive,
  permanent.** **MCP annotations:** `readOnly: false,
  destructive: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Deletes a file. Destructive and irreversible.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to delete."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Successfully deleted file: <path>`. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |

`filesChanged` is `[<path>]`.

**Accepted aliases:** none at the parameter level. The canonical
alias `delete_file` resolves to this tool; see §27.5.

**Notes.** There is **no** `confirm` parameter — do not invent
one (see `assist-approval-model.md` §5.3). A missing file is a
failure (`No file at <path> — nothing to delete.`, code
`notFound`), not a silent success. Deletion is permanent: no
trash, no backup, no undo. The Ycode port must refuse a
directory passed to this tool (Legacy's filesystem layer would
recursively remove it); see `assist-file-writing-tools.md`
§5.2. Gate: explicit approval per deletion, in every mode that
lets the tool run; see `assist-approval-model.md` §5–§6.

## 32. `file_move` — Move File

- **Description (verbatim):** "Moves a file from source to
  destination path."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Moves a file from a source path to a destination path.",
  "properties": {
    "source": {
      "type": "string",
      "description": "Workspace-relative path of the existing file to move."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative destination path."
    }
  },
  "required": ["source", "destination"]
}
```

**Output (success).** Message:
`Successfully moved file from <source> to <destination>`. No
structured data, no `filesChanged`.

**Accepted aliases:** none. The canonical alias `move_file`
resolves to this tool; see §27.5.

**Notes.** The destination must not already exist (the move
refuses rather than overwriting, and never deletes the
destination first). The destination's parent must already exist.
Cross-directory moves are allowed, and the move works for
directories as well as files despite the name. Gate: explicit
`MCPChange` + approval before the move; see
`assist-approval-model.md` §6.2. See
`assist-file-writing-tools.md` §5.2.

## 33. `file_copy` — Copy File

- **Description (verbatim):** "Copies a file from source to
  destination path."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Copies a file from a source path to a destination path.",
  "properties": {
    "source": {
      "type": "string",
      "description": "Workspace-relative path of the existing file to copy."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative destination path."
    }
  },
  "required": ["source", "destination"]
}
```

**Output (success).** Message:
`Successfully copied file from <source> to <destination>`. No
structured data, no `filesChanged`.

**Accepted aliases:** none. The canonical alias `copy_file`
resolves to this tool; see §27.5.

**Notes.** Same destination rules as `file_move`: the
destination must not already exist, its parent must already
exist, cross-directory copies are allowed, directories copy
like files. The copy is a byte copy, not atomic. Gate: explicit
`MCPChange` + approval before the copy; see
`assist-approval-model.md` §6.2. See
`assist-file-writing-tools.md` §4.1 and §5.2.

## 34. `file_rename` — Rename File

- **Description (verbatim):** "Renames a file at the specified
  path."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Renames a file within its current directory.",
  "properties": {
    "oldPath": {
      "type": "string",
      "description": "Workspace-relative path of the existing file."
    },
    "newName": {
      "type": "string",
      "description": "New file name (a single path component, not a path) within the same directory."
    }
  },
  "required": ["oldPath", "newName"]
}
```

**Output (success).** Message:
`Successfully renamed file to: <newName>`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `path` | The new path (same directory as the old path). |

`filesChanged` is `[<newPath>]`.

**Accepted aliases:** none. The canonical alias `rename_file`
resolves to this tool; see §27.5.

**Notes.** `newName` must be a single path component (no `/`,
no `..`, no NUL, not empty, not `"."`); renaming to the current
name fails as a no-op. The destination must not already exist.
Gate: explicit `MCPChange` + approval before the rename; see
`assist-approval-model.md` §6.2. See
`assist-file-writing-tools.md` §5.2.

## 35. `dir_create` — Create Directory

- **Description (verbatim):** "Creates a new directory at the
  specified path."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a new directory, including any missing parent directories.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the directory to create."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Successfully created directory: <path>`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |

`filesChanged` is `[<path>]`.

**Accepted aliases:** none. The canonical aliases
`create_directory`, `make_directory`, and `directory_create`
resolve to this tool; see §27.5.

**Notes.** Missing parents are created. Succeeds silently when
the directory already exists. Gate: explicit `MCPChange` +
approval before creating; see `assist-approval-model.md` §6.2.

## 36. `dir_delete` — Delete Directory

- **Description (verbatim):** "Deletes a directory and all its
  contents."
- **Capability:** `fileModification`. **Risk:**
  `potentiallyDestructive`. **Required permission:**
  `fileSystem`. **Read-only:** no. **Write — destructive,
  permanent, recursive.** **MCP annotations:** `readOnly: false,
  destructive: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Deletes a directory and all of its contents. Destructive and irreversible.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the directory to delete."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Successfully deleted directory: <path>`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |

`filesChanged` is `[<path>]`.

**Accepted aliases:** none at the parameter level. The canonical
aliases `delete_directory`, `remove_directory`, and
`directory_delete` resolve to this tool; see §27.5.

**Notes.** There is **no** `confirm` parameter — do not invent
one (see `assist-approval-model.md` §5.3). A missing directory
is a failure, not a silent success. The workspace root itself
cannot be deleted. Deletion is recursive and permanent: no
trash, no backup, no undo. Gate: explicit approval per deletion,
in every mode that lets the tool run; see
`assist-approval-model.md` §5–§6.

## 37. `code_generate` — Generate File

- **Description (verbatim):** "Generates a new file with
  boilerplate or specific logic."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Generates a new file from a built-in template. Refuses to overwrite existing files.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative target path. Must not already exist."
    },
    "template": {
      "type": "string",
      "description": "One of: swift_struct, swift_class, swiftui_view, test (case-insensitive)."
    },
    "module": {
      "type": "string",
      "description": "Module name used only by the test template for @testable import. Defaults to the user's project name."
    }
  },
  "required": ["path", "template"]
}
```

**Output (success).** Message:
`Generated file <path> using template '<template>'`.
Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |

No `filesChanged`, no `diff`.

**Accepted aliases:** none.

**Notes.** Four built-in string templates only (see
`assist-file-writing-tools.md` §5.4 for their exact contents):
`swift_struct`, `swift_class`, `swiftui_view`, `test`
(case-insensitive). An existing target file fails, with no
overwrite option. An unknown template fails — never a success
that writes a comment-only file. The `test` template
deliberately fails until a real assertion replaces it. Gate:
`commit()`; see `assist-approval-model.md` §6.1.

## 38. `code_format` — Format Code

- **Description (verbatim):** "Formats the code according to
  project style guidelines."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Formats code files with basic normalization (indentation, trailing whitespace, blank lines).",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative file or directory to format. Default: \".\"."
    }
  },
  "required": []
}
```

**Output (success).** Message:
`Code formatting completed at <path>`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `formatted_files` | Count of files actually rewritten. |

**Accepted aliases:** none.

**Notes.** No formatter binary is invoked: the implementation
is a fixed local normaliser (tabs → 4 spaces, trailing
whitespace stripped, blank runs collapsed to one, trailing
newline added), despite the description's mention of "project
style guidelines". `path` defaults to `"."` (the workspace
root). A directory formats its recursive `swift` / `m` / `h` /
`c` / `cpp` / `js` / `ts` / `py` files up to 300,000 bytes;
hidden files and undecodable files are skipped; only changed
files are written (and therefore only those go through
approval). An escaping path is silently clamped to the workspace
root, never an error (see `assist-file-writing-tools.md` §2.5).
Gate: one `commit()` per changed file; see
`assist-approval-model.md` §6.1 and §6.3.

## 39. `code_insert` — Insert Code Block

- **Description (verbatim):** "Inserts a block of code at a
  specific line or before/after a symbol."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Inserts a block of code at a line number or before/after a symbol pattern. Pattern misses are failures, never silent no-ops.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to modify."
    },
    "code": {
      "type": "string",
      "description": "Code block to insert."
    },
    "mode": {
      "type": "string",
      "description": "One of 'line', 'before', or 'after'. Default: \"line\". Unknown modes are rejected."
    },
    "line": {
      "type": "integer",
      "description": "1-based line number for 'line' mode. Appends past end of file. Default: 1."
    },
    "pattern": {
      "type": "string",
      "description": "Anchor text for 'before'/'after' modes. Required in those modes."
    }
  },
  "required": ["path", "code"]
}
```

**Output (success).** Message:
`Code block inserted into <path>`. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |

`filesChanged` is `[<path>]`.

**Accepted aliases:** none at the parameter level. The canonical
aliases `insert_code_block` and `insert_code` resolve to this
tool; see §27.5.

**Notes.** `mode` defaults to `line` (lowercased before
matching); `line` defaults to 1 and appends when past the end of
file; `pattern` is plain substring matching against the file's
first occurrence — a miss is a failure, never a silent no-op.
Mode / pattern / line are validated before the file is touched.
Gate: `commit()`; see `assist-approval-model.md` §6.1. See
`assist-file-writing-tools.md` §5.3.

## 40. `code_multi_edit` — Multi-file Edit

- **Description (verbatim):** "Applies edits across multiple
  files simultaneously."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Applies edits across multiple files. Not atomic: earlier edits persist if a later one fails; the failure names which edits were already applied. Each edit requires a non-empty 'path'. Search/replace edits require a non-empty 'search' (an empty search would corrupt the file).",
  "properties": {
    "edits": {
      "type": "array",
      "description": "Array of edit objects. Each object requires a non-empty 'path', plus either 'content' (full-file replacement) or 'search' + 'replace'."
    }
  },
  "required": ["edits"]
}
```

**Output (success).** Message:
`Multi-file edit completed for <N> files`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `files` | The updated paths, comma-joined. |

`filesChanged` is the updated paths (as a list).

**Accepted aliases:** none.

**Notes.** Each edit is either a full-file replacement (`path`
+ `content`) or a search/replace (`path` + `search` +
`replace`, where `replace` defaults to `""`). All edits are
validated before any is applied; once application starts the
tool is **not atomic** — a failure names the edits already
applied, which stay applied. Search/replace is literal
substring replacement of all occurrences. An empty `edits`
array succeeds with `0 files`. Gate: one `commit()` per file,
in order, stopping at the first refusal; see
`assist-approval-model.md` §6.1 and §6.3. See
`assist-file-writing-tools.md` §5.3.

## 41. `code_refactor` — Refactor

- **Description (verbatim):** "Performs code refactoring (e.g.,
  extract method, rename variable) intelligently."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Performs an LLM-driven refactoring of a file. Requires an OpenAI API key.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to refactor."
    },
    "action": {
      "type": "string",
      "description": "Natural-language description of the refactoring to perform."
    }
  },
  "required": ["path", "action"]
}
```

**Output (success).** Message:
`Refactoring '<action>' applied to <path>`. No structured data,
no `filesChanged`.

**Accepted aliases:** none.

**Notes.** This tool is **LLM-driven**, not a local transform:
Legacy sends the whole file plus the natural-language action to
an LLM (hardcoded OpenAI provider, stored API key), strips
Markdown fences from the response, and writes the result back
as the file's new content. There is no AST and no verification
that the result parses. The Ycode port must route the LLM call
through the host assistant or register the tool as unavailable
with a clear error — it must not substitute a regex/template
"refactor", and must not hardcode an OpenAI key path. See
`assist-file-writing-tools.md` §5.4. Gate: `commit()`; see
`assist-approval-model.md` §6.1.

## 42. `code_replace` — Replace in File

- **Description (verbatim):** "Replaces a specific targeted code
  snippet within an existing file, ensuring exact match and
  providing unified diffs."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Replaces occurrences of a targeted code block with a replacement.",
  "properties": {
    "path": {
      "type": "string",
      "description": "The relative path to the file to modify."
    },
    "target": {
      "type": "string",
      "description": "The exact existing text snippet to find and replace."
    },
    "replacement": {
      "type": "string",
      "description": "The new text snippet to insert in place of the target."
    },
    "allowMultiple": {
      "type": "boolean",
      "description": "Whether to replace multiple occurrences if found (default false)."
    }
  },
  "required": ["path", "target", "replacement"]
}
```

**Output (success).** Message:
`Successfully updated <path> with targeted replacement.\n\nUnified Diff:\n<diff>`
— the unified diff is embedded in the message as well as in
`data["diff"]`. Structured data keys (all strings):

| Key | Value |
|---|---|
| `diff` | Unified diff (Myers, 3 context lines) from the original content to the modified content. |
| `path` | The path as given (workspace-relative). |

`filesChanged` is `[<path>]`, and the `diff` field of the result
is the same unified diff.

**Accepted aliases:** `path` may also be given as `filePath`,
`file_path`, or `targetFile`; `target` may also be given as
`targetContent`, `old_string`, `old_str`, or `find`;
`replacement` may also be given as `replacementContent`,
`new_string`, `new_str`, or `replace`; `allowMultiple` may also
be given as `allow_multiple`. The canonical aliases `edit_file`
and `replace_in_file` resolve to this tool; see §27.5.

**Notes.** Matching is literal substring matching, not regex
and not AST-aware. Zero occurrences and multiple occurrences
(with `allowMultiple` false) are both failures — the file is
written only after the replacement succeeds. Gate: `commit()`;
see `assist-approval-model.md` §6.1. See
`assist-file-writing-tools.md` §5.3.

## 43. `regex_replace_in_files` — Regex Replace in Files

- **Description (verbatim):** "Performs regular expression
  search and replace across multiple workspace files with
  dry-run support."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Regex search and replace across workspace files matching file extension or directory scope.",
  "properties": {
    "pattern": {
      "type": "string",
      "description": "Regular expression pattern to find."
    },
    "replacement": {
      "type": "string",
      "description": "Replacement string (supports $1, $2 capturing group templates)."
    },
    "fileExtension": {
      "type": "string",
      "description": "File extension filter (e.g. 'swift', 'json', 'md'). Defaults to 'swift'."
    },
    "dryRun": {
      "type": "boolean",
      "description": "If true, only reports changes without writing to disk. Defaults to false."
    }
  },
  "required": ["pattern", "replacement"]
}
```

**Output (success).** Message, when matches are found:
`Successfully modified <N> file(s) with <T> total replacements:\n\n- \`<rel>\` (<M> matches)\n...`
(listing at most 30 files; `<T>` counts all matches in all
matched files). Dry run:
`[DRY RUN] Would modify <N> file(s) with <T> total replacements:\n\n...`
No matches:
`` No matches found for pattern `<pattern>` in *.<ext> files. ``
No structured data, no `filesChanged` in any outcome.

**Accepted aliases:** none at the parameter level. The canonical
alias `regex_replace` resolves to this tool; see §27.5.

**Notes.** ICU regex (`NSRegularExpression`, no options,
case-sensitive); `$1` / `$2` capture templates in the
replacement. There is no scope parameter: the tool always
enumerates the whole workspace root (hidden files and package
descendants skipped; undecodable files silently skipped). A
per-file write failure is swallowed — the file keeps its old
content and still counts in the report. A dry run requests no
approval but is still refused in `readOnly` mode (the tool is
registered `writes: true`); see `assist-approval-model.md`
§6.4. Gate otherwise: one `commit()` per matched file; see
§6.1 and §6.3 there. See `assist-file-writing-tools.md` §5.5.

## 44. `plist_edit` — Edit Plist

- **Description (verbatim):** "Gets, sets, or deletes a key in
  a plist file using PropertyListSerialization."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write** (for `set` / `delete`; `get` reads only — but the
  tool is registered `writes: true` because its `set` / `delete`
  actions write, and the flag is static per tool). **MCP
  annotations:** `readOnly: false, idempotent: true`.
  **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Manages one key in a plist file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the plist file (required)."
    },
    "action": {
      "type": "string",
      "description": "get, set, or delete. Default: get."
    },
    "key": {
      "type": "string",
      "description": "Plist key (required)."
    },
    "value": {
      "type": "string",
      "description": "String value for set action."
    }
  },
  "required": ["path", "key"]
}
```

**Output (success).** Messages and structured data keys (all
strings), by action:

| Action | Message | Data keys |
|---|---|---|
| `get` | `Key '<key>' = <rendered> in '<path>'.` | `key`, `value` (rendered value), `path` |
| `set` | `Set key '<key>' in '<path>'.` | `key`, `value`, `path` |
| `delete` | `Deleted key '<key>' from '<path>'.` | `key`, `path` |

No `filesChanged` is returned for any action (the Legacy calls
pass only data).

**Accepted aliases:** none. The registry alias `plist` points
at `plist_editor`, a different tool — it is **not** an alias
for `plist_edit` (see §27.5).

**Notes.** The plist must have a top-level dictionary. `set`
always stores a string, whatever the previous type was, and the
file is rewritten as XML even when it was binary. `set` and
`delete` are verified by reading the file back. `get` renders
non-string values as `true` / `false`, numbers,
`array(<count>)`, or `dictionary(<count>)`. Gate: `commit()`
for `set` / `delete`; a `get` call builds no change and asks
nothing — but it is still refused in `readOnly` mode, because
the tool is registered `writes: true` (static per tool; see
`assist-approval-model.md` §6.4 for the same rule applied to
dry runs). See `assist-file-writing-tools.md` §5.7.

## 45. `format_json_file` — Format and Validate JSON File

- **Description (verbatim):** "Validates and pretty-prints a
  JSON file with consistent indentation and sorted keys."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Validates and pretty-prints a JSON file with consistent indentation and sorted keys.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the JSON file to format."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`` Successfully formatted and validated JSON file at `<path>` (<N> bytes). ``
Structured data keys (all strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |
| `formattedBytes` | Byte count of the formatted JSON data. |

`filesChanged` is `[<path>]`.

**Accepted aliases:** `path` may also be given as `filePath`.

**Notes.** Rewrites the file **in place** (same path, no
destination parameter). Top-level fragments are accepted. The
file's extension is not checked. Gate: `commit()`; see
`assist-approval-model.md` §6.1. See
`assist-file-writing-tools.md` §5.8.

## 46. `csv_to_json` — Convert CSV to JSON

- **Description (verbatim):** "Parses a tabular CSV file and
  converts records into a structured JSON array of objects."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Parses a tabular CSV file and converts records into a structured JSON array of objects.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the input CSV file."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative destination path for .json file. Defaults to <path>.json."
    },
    "delimiter": {
      "type": "string",
      "description": "Delimiter character: ',' (default), '\t', or ';'."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`` Successfully converted CSV `<path>` to JSON at `<dest>` (<N> records parsed). ``
Structured data keys (all strings):

| Key | Value |
|---|---|
| `destination` | The destination path as given. |
| `recordCount` | Number of records parsed. |

`filesChanged` is `[<dest>]`.

**Accepted aliases:** `path` may also be given as `csvPath`.

**Notes.** Parsing is naive string splitting, not a CSV parser:
no quote handling, missing columns become `""`, extra columns
are dropped, all values are strings. The destination defaults
to `<path>.json`; its parent directories are created if missing.
Gate: `commit()`; see `assist-approval-model.md` §6.1. See
`assist-file-writing-tools.md` §5.8.

## 47. `json_to_csv` — Convert JSON to CSV

- **Description (verbatim):** "Converts a JSON array of objects
  into a standard CSV tabular file."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Converts a JSON array of objects into a standard CSV tabular file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the input JSON file."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative destination path for .csv file. Defaults to <path>.csv."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`` Successfully converted JSON `<path>` to CSV at `<dest>` (<R> rows, <C> columns). ``
Structured data keys (all strings):

| Key | Value |
|---|---|
| `destination` | The destination path as given. |
| `rowCount` | Number of rows (objects). |
| `columnCount` | Number of columns (headers). |

`filesChanged` is `[<dest>]`.

**Accepted aliases:** `path` may also be given as `jsonPath`.

**Notes.** The JSON root must be a non-empty array of objects.
Headers are the union of all keys, sorted alphabetically; every
field is double-quoted with doubled quotes; nested values are
stringified, not serialised as JSON. The destination defaults to
`<path>.csv`; its parent directories are created if missing.
Gate: `commit()`; see `assist-approval-model.md` §6.1. See
`assist-file-writing-tools.md` §5.8.

## 48. `plist_to_json` — Convert Plist to JSON

- **Description (verbatim):** "Converts an Apple Property List
  (.plist) file directly into formatted JSON format."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Converts an Apple Property List (.plist) file directly into formatted JSON format.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the .plist file."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative destination path for .json file. Defaults to <path>.json."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`` Successfully converted Plist `<path>` to JSON at `<dest>` (<N> bytes). ``
Structured data keys (all strings):

| Key | Value |
|---|---|
| `destination` | The destination path as given. |
| `size` | Byte count of the JSON data. |

`filesChanged` is `[<dest>]`.

**Accepted aliases:** `path` may also be given as `plistPath`.

**Notes.** Any plist root type is accepted (unlike
`plist_edit`, which requires a dictionary). A plist value with
no JSON representation fails the conversion. The destination
defaults to `<path>.json`; its parent directories are created
if missing. Gate: `commit()`; see `assist-approval-model.md`
§6.1. See `assist-file-writing-tools.md` §5.7.

## 49. `json_to_plist` — Convert JSON to Plist

- **Description (verbatim):** "Converts a JSON file into an
  Apple Property List (.plist, XML or Binary format)."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Converts a JSON file into an Apple Property List (.plist, XML or Binary format).",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the .json file."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative destination path for .plist. Defaults to <path>.plist."
    },
    "binary": {
      "type": "boolean",
      "description": "Whether to encode as binary plist (default false: XML plist)."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`` Successfully converted JSON `<path>` to Plist (binary|xml) at `<dest>` (<N> bytes). ``
Structured data keys (all strings):

| Key | Value |
|---|---|
| `destination` | The destination path as given. |
| `format` | `"binary"` or `"xml"`. |
| `size` | Byte count of the plist data. |

`filesChanged` is `[<dest>]`.

**Accepted aliases:** `path` may also be given as `jsonPath`.

**Notes.** XML is the default; `binary: true` selects binary
plist. The destination defaults to `<path>.plist`; its parent
directories are created if missing. Gate: `commit()` for XML
(the proposed text is the plist XML); explicit `MCPChange` +
approval for binary (the content cannot be shown as proposed
text); see `assist-approval-model.md` §6.1–§6.2. See
`assist-file-writing-tools.md` §5.7.

## 50. `batch_rename_files` — Batch Rename Files

- **Description (verbatim):** "Renames multiple files in a
  directory matching a prefix, suffix, or substring pattern."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Renames multiple files in a directory matching a prefix, suffix, or substring pattern.",
  "properties": {
    "directory": {
      "type": "string",
      "description": "Workspace-relative directory containing the files to rename."
    },
    "search": {
      "type": "string",
      "description": "Target substring or pattern in filenames to replace."
    },
    "replacement": {
      "type": "string",
      "description": "String to replace the search target with."
    },
    "extension": {
      "type": "string",
      "description": "Optional file extension filter (e.g. 'swift', 'png')."
    },
    "dryRun": {
      "type": "boolean",
      "description": "If true, simulates the rename without modifying files. Default: false."
    }
  },
  "required": ["directory", "search", "replacement"]
}
```

**Output (success).** Messages, by outcome:

- No matches:
  `` No files in `<dir>` matched search pattern '<search>'. ``
  Data keys (all strings): `renamedCount` = `"0"`.
- Dry run:
  `Dry run: <N> file(s) would be renamed in `<dir>`:\n  • <old> -> <new>\n...`
  Data keys: `dryRun` = `"true"`, `matchCount` = `"<N>"`.
- Renamed:
  `Successfully batch-renamed <N> file(s) in `<dir>`:\n  • <old> -> <new>\n...`
  Data keys: `renamedCount` = `"<N>"`. `filesChanged` is the
  renamed files' new paths.

**Accepted aliases:** `directory` may also be given as `path`.

**Notes.** Immediate children only (not recursive), sorted by
filename; `extension` is compared lowercased; matching is
substring containment and replacement replaces all occurrences
in the filename; directories among the children are renamed
like files. No collision pre-check: a conflicting rename fails
the batch partway through, leaving earlier renames applied. A
dry run requests no approval but is still refused in `readOnly`
mode (the tool is registered `writes: true`); see
`assist-approval-model.md` §6.4. Gate otherwise: one explicit
`MCPChange` + approval per rename; see §6.2–§6.3 there. See
`assist-file-writing-tools.md` §5.9.

## 51. `generate_file_checksum` — Generate File Cryptographic Checksum

- **Description (verbatim):** "Computes SHA-256, SHA-512, SHA-1,
  and MD5 cryptographic checksums of a file on disk."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Computes SHA-256, SHA-512, SHA-1, and MD5 cryptographic checksums of a file on disk.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the file to hash."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
```
Checksums for <path> (<N> bytes):
- SHA-256: <hex>
- SHA-512: <hex>
- SHA-1:   <hex>
- MD5:     <hex>
```
(note the spacing: `SHA-1:` is followed by three spaces and
`MD5:` by five, aligning the values). Structured data keys (all
strings):

| Key | Value |
|---|---|
| `path` | The path as given (workspace-relative). |
| `sha256` | Lowercase hex SHA-256 digest. |
| `sha512` | Lowercase hex SHA-512 digest. |
| `sha1` | Lowercase hex SHA-1 digest. |
| `md5` | Lowercase hex MD5 digest. |
| `size` | Byte count of the file. |

**Accepted aliases:** `path` may also be given as `filePath`.

**Notes.** This tool writes nothing: it reads the file's bytes
whole into memory and hashes them in-process (swift-crypto).
All four hashes are always computed; there is no algorithm
parameter. It runs in `readOnly` server mode. See §27.4 and
`assist-file-writing-tools.md` §5.10.

## 52. Summary: capability / risk / permission / writes (Wave 2)

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `file_write` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `file_create` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `file_append` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `file_delete` | fileModification | potentiallyDestructive | fileSystem | **no** | **true** |
| `file_move` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `file_copy` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `file_rename` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `dir_create` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `dir_delete` | fileModification | potentiallyDestructive | fileSystem | **no** | **true** |
| `code_generate` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `code_format` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `code_insert` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `code_multi_edit` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `code_refactor` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `code_replace` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `regex_replace_in_files` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `plist_edit` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `format_json_file` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `csv_to_json` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `json_to_csv` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `plist_to_json` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `json_to_plist` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `batch_rename_files` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `generate_file_checksum` | fileReading | safeRead | none | yes | false |

23 tools write; 1 (`generate_file_checksum`) reads. The two
`potentiallyDestructive` tools are `file_delete` and
`dir_delete`.

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 24 IDs, titles, descriptions, capabilities, risk levels, and input schemas | 1 | Legacy source, read directly: `SwiftCode/Backend/Assist/Tools/AssistReadFileTool.swift`, `AssistReadDirectoryTool.swift`, `AssistChangeDirectoryTool.swift`, `AssistDirSizeReportTool.swift`, `AssistFileMetadataTool.swift`, `AssistFileHeadPreviewTool.swift`, `AssistDataInspectionTools.swift` (`file_compare_diff`, `count_file_lines`), `AssistFileChecksumVerifierTool.swift`, `AssistFileHashVerifyTool.swift`, `AssistFileBackupTool.swift`, `AssistFileTypeBreakdownTool.swift`, `AssistFindDuplicateFilesTool.swift`, `AssistEmptyDirsFindTool.swift`, `AssistExecutableFilesScanTool.swift`, `AssistTreeViewTool.swift`, `AssistSymlinkAuditTool.swift`, `AssistCreateArtifactTool.swift`, `AssistDeleteArtifactTool.swift`, `AssistListArtifactsTool.swift`, `AssistReadArtifactTool.swift`, `AssistFinderTools.swift` |
| `read_file` / `view_file` → `file_read`, `open_finder` → `open_in_finder`, `reveal_finder` / `show_in_finder` → `reveal_in_finder`, `list_dir` / `list_directory` / `directory_read` → `dir_read` aliases | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table; `AssistToolRouter.swift` metadata switch |
| Capability / risk / permission derivation rules, `isReadOnly` / `isMutating` / `isDestructive` defaults, fail-closed unknown-tool rule | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistTool.swift` (`AssistTool` protocol extension defaults); `AssistToolRouter.swift` `ToolCapability`, `ToolRiskLevel`, `ToolPermissionRequirement`, `metadata(for:)` and `metadata(for tool:)` |
| Result envelope fields and all-string `data` values | 1 | Legacy `SwiftCode/Backend/Assist/AssistModels.swift` (`AssistToolResult`); `AssistToolResultFormatter.swift` (`AssistToolErrorCode`) |
| Ycode MCP annotation shape (`readOnly`, `destructive`, `idempotent`, `openWorld`; `.read` preset; `writes` flag) | 1 | Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`MCPToolAnnotations`, `MCPToolDefinition`); `ycode/Sources/YcodeMCP/MCPCommand.swift` (`--allow-writes`, write policy) |
| Ycode `file_list` / `file_read` schemas that must not be merged with the Legacy tools | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Workspace.swift` |
| `file_checksum_verifier` computes only (no expected hash, no comparison), silent SHA-256 fallback for unknown algorithms, no structured data, no containment check | 1 | Legacy `Tools/AssistFileChecksumVerifierTool.swift`, read directly |
| `file_hash_verify` uses `/usr/bin/shasum` and `/usr/bin/md5` subprocesses | 1 | Legacy `Tools/AssistFileHashVerifyTool.swift`, read directly |
| Finder tools use `NSWorkspace` (`open`, `activateFileViewerSelecting`) with a `/usr/bin/open` fallback for open only | 1 | Legacy `Tools/AssistFinderTools.swift`, read directly |
| Artifact store layout, name normalisation, kind inference, modes, truncation, protected `agent_notes.md` | 1 | Legacy `SwiftCode/Backend/Assist/AssistArtifactStore.swift`; `Tools/AssistToolSharedHelpers.swift` (`AssistArtifactNaming`) |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
| Wave 2: all 24 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `file_create` as the 24th tool (registry line 75, `AssistCreateFileTool.swift:4`) | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` (register lines 68–77, 91–95, 202, 238, 310–316, 319); `Tools/AssistWriteFileTool.swift`, `AssistCreateFileTool.swift`, `AssistAppendFileTool.swift`, `AssistDeleteFileTool.swift`, `AssistMoveFileTool.swift`, `AssistCopyFileTool.swift`, `AssistRenameFileTool.swift`, `AssistCreateDirectoryTool.swift`, `AssistDeleteDirectoryTool.swift`, `AssistGenerateFileTool.swift`, `AssistFormatCodeTool.swift`, `AssistInsertCodeBlockTool.swift`, `AssistMultiFileEditTool.swift`, `AssistRefactorTool.swift`, `AssistReplaceInFileTool.swift`, `AssistRegexReplaceInFilesTool.swift`, `AssistPlistEditTool.swift`, `AssistDataMutationTools.swift`, `AssistDataInspectionTools.swift` (`AssistGenerateFileChecksumTool`), read directly |
| Wave 2: `generate_file_checksum` is `fileReading` / `safeRead`, computes four hashes, writes nothing — family-classification correction | 1 | Legacy `Tools/AssistDataInspectionTools.swift` (`AssistGenerateFileChecksumTool`, lines 334–399), read directly |
| Wave 2: registry aliases for this wave; `plist` → `plist_editor` and `checksum_verifier` → `file_checksum_verifier` are different tools, not aliases for `plist_edit` / `generate_file_checksum` | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table, read directly |
| Wave 2: `file_write` alignment — Ycode's existing registration in `YcodeTools+Content.swift` (workspace/path/content, `path`/`created`/`lineCount`, `commit()`), its `destructive: true` annotation vs Legacy `safeMutation` | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Content.swift` (`file_write` tool, `commit`, `writeFile`), read directly; Wave 1 `file_read` alignment precedent in `YcodeTools+Workspace.swift` (Legacy `lines` object added to the existing registration) |
| Wave 2: output messages and structured data keys; `file_append` / `file_move` / `file_copy` return no data and no `filesChanged`; `code_generate` returns no `filesChanged`; `regex_replace_in_files` returns no data in any outcome | 1 | Each Legacy Wave 2 tool `execute()` listed above, read directly |
| Wave 2: `file_delete` / `dir_delete` schemas contain only `path` (no `confirm` parameter) | 1 | Legacy `Tools/AssistDeleteFileTool.swift`, `Tools/AssistDeleteDirectoryTool.swift`, read directly |
