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

## Wave 3 — search tools

This part of the catalogue covers the 16 Wave 3 Search tools: the
search / code-navigation family ported from SwiftCode Legacy Assist
into Ycode in Wave 3. The Wave 1 conventions in §1 apply, extended
by §53 below. The companion spec
`assist-search-git-tools.md` covers the behaviour shared by these
tools (scan rules, path resolvers, search semantics, error cases),
and `assist-approval-model.md` covers how the two writes are
gated. (The Git tools share that behaviour spec's file but are
catalogued separately by the Git slice.)

Scope: exactly these 16 tools, verified live from the Legacy
registry. No other tool is in scope for this slice, and no tool
may be invented, renamed, or merged with another — except the two
collisions handled in §53.5, which are documented, not merged.

| ID | Title |
|---|---|
| `call_hierarchy` | Call Hierarchy |
| `code_summary` | Code Summary |
| `dependency_graph` | Dependency Graph |
| `extract_code_symbols` | Extract Code Symbols |
| `import_graph` | Import Graph |
| `protocol_conformance_list` | Protocol Conformance List |
| `search_regex` | Regex Search |
| `search_skills` | Search Agent Skills |
| `search_symbol` | Symbol Search |
| `search_text` | Search Text |
| `semantic_query_engine` | Semantic Source Query Engine |
| `source_graph_builder` | Source Graph Builder |
| `symbol_move_file` | Move Symbol Across Files |
| `symbol_reference_graph` | Symbol Reference Graph |
| `symbol_rename_project` | Rename Symbol Project-Wide |
| `type_hierarchy` | Type Hierarchy |

**The 14 read-only tools in this wave.** 14 of the 16 tools are
`safeRead` reads (`writes: false`). The two exceptions are
`symbol_move_file` and `symbol_rename_project`, both
`safeMutation` writes gated through `commit()` (§53.3).

## 53. Wave 3 conventions (extending §1 and §27)

### 53.1 Result envelope — Wave 3 notes

§1.1 applies unchanged, with three Wave 3 notes:

- `filesChanged` (list of workspace-relative paths) has no Ycode
  equivalent — `MCPToolResult` carries none — so the port reports
  changed paths through `commit()`'s session notification
  instead, as Wave 2 does. Two tools carry their changed paths
  in their structured data as a string, exactly as Legacy does:
  `symbol_rename_project` returns `filesChanged` as a
  newline-joined string in `data` (see §68).
- `diff` (optional string): no Wave 3 tool sets it. Ycode has no
  Myers diff engine (see Wave 2's `file_create` / `code_replace`
  note), and neither mutating tool in this wave produces a diff
  in Legacy.
- Legacy-only envelope fields (`duration`,
  `suggestedNextActions`, `beforeContent`, `afterContent`) have no
  Ycode equivalent and are dropped; see
  `assist-file-writing-tools.md` §8.4.

### 53.2 Risk → annotations for Wave 3

§1.3 applies unchanged:

| Legacy `riskLevel` | Ycode `MCPToolAnnotations` | `writes` |
|---|---|---|
| `safeRead` | `readOnly: true, idempotent: true` | `false` |
| `safeMutation` | `readOnly: false, idempotent: true` | `true` |

`writes: true` applies to exactly two tools in this wave:
`symbol_move_file` and `symbol_rename_project`. No tool in this
wave is `potentiallyDestructive`.

### 53.3 Gate per tool

Both `writes: true` tools are gated by `MCPServer.run()` and
their handler-side shape — see `assist-approval-model.md` §6
for the full table. In short: each changed file goes through
one `commit()` (full before/after text), in order, stopping at
the first refusal; earlier files stay written (the Wave 2
multi-file shape, as in `code_multi_edit`).
`symbol_move_file` additionally verifies after both commits and
restores both files on verification failure — the Legacy restore
path, adapted to the gate (see `assist-search-git-tools.md`
§1.5 and §16). There is no Autopilot bypass.

### 53.4 Two output shapes — schema rule

Two tools have two output shapes by branch (`import_graph`:
§57; `type_hierarchy`: §69) and one omits a key from its
not-found result (`call_hierarchy`: §54). Their output schemas
declare the union of both branches' keys, with `required`
listing only the keys every branch returns (`import_graph` and
`type_hierarchy` require nothing; `call_hierarchy` requires
`function`, `definitionCount`, `callerCount` but not
`calleeCount`). No other Wave 3 tool does this: every other
tool's output schema lists exactly the keys its (single) result
shape returns, as `Schema.output` does.

### 53.5 Collisions with Ycode's existing tools — no merging

Ycode already has `search` (workspace text search,
`YcodeTools+Workspace`) and `symbol_search` (symbol
documentation). Legacy's `search_text` and `search_symbol` are
**different tools with different IDs/schemas** and must not be
merged with them:

- Ycode `search` takes `query` plus `regex` / `ignoreCase` /
  `wholeWord` / `limit` (default 200, case-insensitive by
  default) and returns `matches` (path / line / column / text)
  with a 200-match cap. Legacy `search_text` takes a single
  `pattern`, is a case-insensitive literal search with no limit,
  skips files over 1 MB and binary-extension files, and returns
  one `results` string grouped per file. Keep both as separate
  tools.
- Ycode `symbol_search` takes `query` / `limit` and returns
  declarations whose name *contains* the query, with
  documentation comments (from `SymbolDocs`). Legacy
  `search_symbol` takes a single `symbol` and runs four
  declaration regexes over the workspace, returning deduped
  `path:line: text` lines. Keep both as separate tools.

This mirrors the Wave 1 `file_read` / Wave 2 `file_write`
precedent in the other direction: there the Ycode tool was
aligned in place; here the Legacy tools are registered as their
own tools because their schemas and behaviour do not align with
Ycode's, and no second registration under an existing ID is
created.

### 53.6 Aliases — accepted, but never canonical

The Legacy registry resolves these aliases to the canonical IDs
in this wave. The Ycode port accepts them at `tools/call`
time (through `MCPServer.toolAliases`, as Wave 1 did for
`read_file`); the canonical ID is what is registered, listed,
and returned in metadata:

- `search_dir`, `search_directory`, `find_file` → `search_text`
- `symbol_graph` → `symbol_reference_graph`

The registry alias `search` → `search_text` is deliberately
NOT carried over: Ycode already has a `search` tool (§53.5),
and the alias would collide with it. No registry alias exists
for `call_hierarchy`, `code_summary`, `dependency_graph`,
`extract_code_symbols`, `import_graph`,
`protocol_conformance_list`, `search_regex`, `search_skills`,
`search_symbol`, `semantic_query_engine`,
`source_graph_builder`, `symbol_move_file`,
`symbol_rename_project`, or `type_hierarchy`.

Per-tool parameter-name aliases (e.g. `symbol_rename_project`
accepting `old_name`) are documented per tool under "Accepted
aliases" where they exist. They are leniency in parsing, not
part of the schema — and, as in §1.7 and §27.5, they are NOT
supported in the Ycode port: Ycode's argument validation
rejects unknown arguments before the handler runs.

## 54. `call_hierarchy` — Call Hierarchy

- **Description (verbatim):** "For a function name, finds its
  definition site, its callers across the workspace, and the
  functions it calls."
- **Capability:** `diagnostics`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Builds a call hierarchy for a function.",
  "properties": {
    "function": {
      "type": "string",
      "description": "Function name to analyze (without parameters)."
    }
  },
  "required": ["function"]
}
```

**Output (success).** Found:
`Call hierarchy for '<fn>':` followed by
`Definitions (<n>):` (at most 20, `- <rel>:<line>`),
`Callers (<n>):` (at most 50, with a
`… [truncated: showing 50 of <n>]` line when more),
`Callees (<n> distinct):` (at most 50, sorted). Structured data
keys (all strings in Legacy; typed values in the port):

| Key | Value |
|---|---|
| `function` | The function name as given (trimmed). |
| `definitionCount` | Number of definition sites. |
| `callerCount` | Number of callers. |
| `calleeCount` | Number of distinct callees. |

Not found (no definition and no callers):
`No definition or callers found for function '<fn>'.` with data
`function`, `definitionCount` 0, `callerCount` 0 — and **no**
`calleeCount` key (see §53.4).

**Accepted aliases:** none at the parameter level.

**Notes.** A caller is a line matching
`(?<![\w.])<fn>\s*\(` that is not itself a declaration line —
`obj.fn(` is not a caller. Callees are collected by
brace-depth tracking inside each definition body (at most 400
lines); brace counting is heuristic and does not parse strings
or comments. See `assist-search-git-tools.md` §6.

## 55. `code_summary` — Code Summary

- **Description (verbatim):** "Provides a high-level summary of
  a file or directory."
- **Capability:** `diagnostics`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Provides a high-level summary of a file or directory.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative file or directory path to summarize."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message: `Summary for <path>`. Structured
data keys (all strings):

| Key | Value |
|---|---|
| `summary` | Directory: `Directory <path>: <n> files, <m> code files`. File: `File <path>: <lines> lines (<nonEmpty> non-empty), <commentLines> comment lines`. |

**Accepted aliases:** none at the parameter level.

**Notes.** Path resolution is the clamping resolver: an escaping
path silently becomes the workspace root, never an error (see
`assist-search-git-tools.md` §1.2). A directory counts files
under it (300 KB cap, hidden files skipped); code files are
those with a code extension (`swift`, `m`, `mm`, `h`, `hpp`,
`c`, `cpp`, `js`, `ts`, `tsx`, `jsx`, `py`, `rb`, `java`, `kt`,
`go`, `rs`). A file's line count splits on newlines, so a
trailing newline counts as one more line (unlike `file_read`);
comment lines are those whose trimmed form starts with `//`
only. See `assist-search-git-tools.md` §10.

## 56. `dependency_graph` — Dependency Graph

- **Description (verbatim):** "Generates a graph of project
  dependencies."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Generates a graph of Swift import dependencies across the project.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory to scan. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Message:
`Dependency graph generated for <n> files.` Structured data
keys (all strings):

| Key | Value |
|---|---|
| `node_count` | Number of nodes (source files + imported modules). |
| `edge_count` | Number of import edges. |
| `nodes` | Sorted node names, joined with `", "`. |
| `edges` | Sorted edges (`<source> -> <module>`), joined with `\n`. |

**Accepted aliases:** none at the parameter level.

**Notes.** Scans `.swift` files only (300 KB cap). Imports are
extracted with `^\s*import\s+([A-Za-z0-9_\.]+)`; a file with no
imports is still a node. `@testable import X` does not match
and is not an edge. `path` is optional and defaults to the
workspace root; resolution is the clamping resolver. See
`assist-search-git-tools.md` §11.

## 57. `extract_code_symbols` — Extract Code Symbols

- **Description (verbatim):** "Extracts top-level declarations
  (class, struct, enum, protocol, actor, func, extension) and
  signatures from a source file."
- **Capability:** `fileReading`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Extracts top-level declarations (class, struct, enum, protocol, actor, func, extension) and signatures from a source file.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the Swift or source code file."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message:
`Extracted <N> declaration symbol(s) from \`<path>\`:` followed
by one line per symbol,
`  • L<line>: [<kind>] <signature>`. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `path` | The path as given. |
| `symbolCount` | Number of declarations found. |

**Accepted aliases:** `path` may also be given as `filePath`
(Legacy handler leniency; not supported in the Ycode port — see
§53.6).

**Notes.** Per line, skipping lines whose trimmed form starts
with `//`, `/*`, or `*`: the first keyword *contained* in the
line wins, in the order `class `, `struct `, `enum `,
`protocol `, `actor `, `func `, `extension `, `typealias ` —
contained, not prefixed, so a line mentioning a keyword anywhere
counts. The signature is the line up to the first `{`, trimmed.
The file must decode as UTF-8. Path resolution is the strict
resolver. See `assist-search-git-tools.md` §5.

## 58. `import_graph` — Import Graph

- **Description (verbatim):** "Builds a file-level import graph:
  which modules each source file imports, and which files import
  a given module."
- **Capability:** `diagnostics`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Builds a file-level import graph.",
  "properties": {
    "module": {
      "type": "string",
      "description": "Optional: only show files importing this module."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum files to report. Default 200."
    }
  },
  "required": []
}
```

**Output (success).** Two shapes (see §53.4):

With `module`: message `Files importing '<module>' (<n>):`
followed by at most `limit` lines `- <rel>`. Structured data
keys: `module`, `fileCount` (the full count, even when the
listing is capped).

Without `module`: message `Most-imported modules:` followed by
the 30 most-imported modules (`- <module>: <n> files`), then
`Import edges (<total> total, showing <shown>):` followed by at
most `limit` lines `- <rel> -> <module>` in scan order.
Structured data keys: `edgeCount`, `moduleCount`.

**Accepted aliases:** none at the parameter level.

**Notes.** Scans source files (`swift`, `m`, `mm`, `h`, `c`,
`cpp`, `hpp`); imports are extracted per line with
`^\s*import\s+([A-Za-z_][\w.]*)`. `limit` defaults to 200 and
is clamped to 1…2000. `@testable import X` does not match and
is not an edge. See `assist-search-git-tools.md` §12.

## 59. `protocol_conformance_list` — Protocol Conformance List

- **Description (verbatim):** "Lists every type that declares
  conformance to a given protocol, with declaration locations."
- **Capability:** `diagnostics`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lists conformers of a protocol.",
  "properties": {
    "protocol": {
      "type": "string",
      "description": "Protocol name to search conformances for."
    }
  },
  "required": ["protocol"]
}
```

**Output (success).** None found:
`No conformances to protocol '<proto>' found.` with data
`protocol`, `count` 0. Found:
`Conformances to '<proto>' (<n>):` followed by one line per
conformance, `- <Type> — <rel>:<line>` (or
`- extension <Type> — <rel>:<line>` for extension
conformances), sorted. Structured data keys (all strings):

| Key | Value |
|---|---|
| `protocol` | The protocol name as given (trimmed). |
| `count` | Number of conformances. |

**Accepted aliases:** none at the parameter level.

**Notes.** The match is textual: a declaration whose `:` clause
contains the protocol name as a whole word, and an `extension
<Type>:` clause likewise. A type conforming through a typealias
or a conditional conformance is not recognised. See
`assist-search-git-tools.md` §7.

## 60. `search_regex` — Regex Search

- **Description (verbatim):** "Searches for a regular
  expression pattern within the project files."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Searches for a regular expression pattern within project files.",
  "properties": {
    "pattern": {
      "type": "string",
      "description": "Regular expression pattern to search for."
    }
  },
  "required": ["pattern"]
}
```

**Output (success).** Message:
`Regex search completed for '<pattern>'`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `results` | Matching lines as `<rel>:<line>: <text>`, one per line, sorted by path; empty string when nothing matches. |

**Accepted aliases:** none at the parameter level.

**Notes.** The pattern is compiled once as a case-insensitive
`NSRegularExpression` and matched per line; a line with several
matches is reported once. An invalid pattern fails with
`Regex search failed: <error>` — never a partial result. Files
over 1 MB, binary-extension files, hidden files, and files that
do not decode as UTF-8 are skipped. See
`assist-search-git-tools.md` §3.

## 61. `search_skills` — Search Agent Skills

- **Description (verbatim, adapted — see Notes):** "Search the
  workspace's local skills library (SKILL.md files under
  .claude/skills and .agents/skills) for specialized domain
  guides, architectures, workflows, and best practices. Call
  this tool when an objective involves a specific technology,
  framework, pattern, or task category."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Search indexed skills in the workspace's local skills library.",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search keywords or task intent (e.g. 'SwiftUI architecture', 'TypeScript testing', 'Core Data', 'security audit')."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum number of matching skills to return (default: 8, max: 20)."
    }
  },
  "required": ["query"]
}
```

**Output (success).** No matches:
`No skills found matching query '<query>'. You can continue executing the task using standard engineering principles.`
No structured data. Matches:
`### Discovered Skills Matching '<query>' (<n> results):`
followed by one numbered block per skill (`**<name>** (\`<id>\`)`,
`Source`, `Location`, `Description`, `Tags` when present,
`Tools` when present, and a line pointing at `file_read` on the
skill's path), and a closing guidance line. No structured data.

**Accepted aliases:** none at the parameter level.

**Notes — the description is adapted, not verbatim.** Legacy's
description names "SwiftCode's authoritative local skills
library" and its schema says "Search indexed skills in the
local SwiftCode skills repository." Ycode has no such library:
Legacy's `SkillIndex` indexed
`~/Library/Application Support/SwiftCode/Skills/` plus imported
Claude/Codex/VSCode/Antigravity libraries, with enable/disable
toggles and a disk cache. The port searches the skill surface
Ycode actually has — the workspace's own `SKILL.md` /
`SKILLS.md` / `*.SKILL.md` files (including hidden directories
such as `.claude/skills/`, where Ycode's own skill lives) — with
Legacy's metadata parsing and scoring. The description and
schema description above are the adapted wording; everything
else (scoring, output format, `limit` clamp 1…20) is Legacy's.
The guidance lines point at `file_read` (Ycode's canonical
name) rather than Legacy's `read_file` alias. Do not invent a
skills database to make the verbatim description true. See
`assist-search-git-tools.md` §15.

## 62. `search_symbol` — Symbol Search

- **Description (verbatim):** "Searches for symbols (classes,
  methods, variables) within the project."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Searches for Swift symbol declarations (classes, methods, variables).",
  "properties": {
    "symbol": {
      "type": "string",
      "description": "Symbol name to search for."
    }
  },
  "required": ["symbol"]
}
```

**Output (success).** Message:
`Symbol search completed for '<symbol>'`. Structured data keys
(all strings):

| Key | Value |
|---|---|
| `results` | Deduped, sorted lines as `<rel>:<line>: <text>`; empty string when nothing matches. |

**Accepted aliases:** none at the parameter level.

**Notes.** Four declaration regexes run over the workspace
(case-insensitive): type declarations, `func`, `var`/`let`,
and `case` (see `assist-search-git-tools.md` §4). This is a
text-pattern search, not an index lookup: it finds
declaration-shaped lines and can miss declarations whose shape
the four patterns do not cover. It is a different tool from
Ycode's existing `symbol_search` (§53.5). See
`assist-search-git-tools.md` §4.

## 63. `search_text` — Search Text

- **Description (verbatim):** "Searches for text across files in
  the project sandbox."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Searches for literal text across files in the project sandbox.",
  "properties": {
    "pattern": {
      "type": "string",
      "description": "Literal text pattern to find."
    }
  },
  "required": ["pattern"]
}
```

**Output (success).** Message:
`Search results for '<pattern>':`. Structured data keys (all
strings):

| Key | Value |
|---|---|
| `results` | One block per matching file, `"<rel>:\n"` followed by its `<line>: <text>` lines, blocks joined with a blank line; empty string when nothing matches. |

**Accepted aliases:** none at the parameter level. The canonical
aliases `search`, `search_dir`, `search_directory`, and
`find_file` resolve to this tool; see §53.6 — except `search`,
which is NOT carried over in Ycode (it would collide with
Ycode's existing `search`).

**Notes.** Literal, case-insensitive substring search; the
pattern is never treated as a regex, even when it contains
regex metacharacters. Results are sorted by path (Legacy
returned a dictionary; the port is deterministic instead). An
empty `pattern` matches every line (Legacy behaviour,
preserved). Files over 1 MB, binary-extension files, hidden
files, and files that do not decode as UTF-8 are skipped. It
is a different tool from Ycode's existing `search` (§53.5).
See `assist-search-git-tools.md` §2.

## 64. `semantic_query_engine` — Semantic Source Query Engine

- **Description (verbatim):** "Performs semantic search for
  symbols, SwiftUI views, models, and services with usage
  context."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Performs semantic search for symbols, SwiftUI views, models, and services with usage context.",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query. Shortcuts: 'view', 'model', 'service' expand to common patterns."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative directory to search. Defaults to the workspace root."
    }
  },
  "required": ["query"]
}
```

**Output (success).** Message:
`Semantic query returned <n> matches.` Structured data keys
(all strings):

| Key | Value |
|---|---|
| `matches` | The first 1500 hits, one per line, as `<rel>::<line>::<snippet>` where the snippet is the matching line with one line of context on each side (`<n>: <text>` joined with ` \| `); empty string when nothing matches. |

**Accepted aliases:** none at the parameter level.

**Notes — the name overpromises.** Despite the name and
description, this tool performs **no** embedding or LLM
semantic search — in Legacy or in this port. It is a
case-insensitive substring scan over `.swift` files (800 KB
cap) with three keyword expansions (`view` also matches lines
containing `: View`; `model` also matches `struct`/`class`
lines mentioning `model`/`viewmodel`; `service` also matches
lines mentioning `service`). The port implements Legacy's scan
faithfully and must never be described as semantic search. The
message count is the full count, even when the list is capped
at 1500. Path resolution is the clamping resolver. See
`assist-search-git-tools.md` §14.

## 65. `source_graph_builder` — Source Graph Builder

- **Description (verbatim):** "Parses Swift files and returns
  dependency and symbol relationship graph data."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Parses Swift files and returns dependency and symbol relationship graph data.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Workspace-relative directory to scan. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Message:
`Built source graph for <n> Swift files.` Structured data keys
(all strings):

| Key | Value |
|---|---|
| `file_count` | Number of Swift files scanned. |
| `node_count` | Number of distinct nodes (files, `<kind>:<name>` symbols, `module:<module>` imports). |
| `relationship_count` | Number of relationships (full count, even when the list is capped). |
| `imports` | Sorted imported modules, joined with `,` (no space). |
| `relationships` | The first 2000 relationships, joined with `\n`. |

**Accepted aliases:** none at the parameter level.

**Notes.** Three regexes run over each file's whole text:
symbol declarations, imports, and capitalised type uses
(excluding names the file itself declares). Relationships are
kept in scan order with duplicates; only the reported list is
capped. A scope path that does not exist fails with
`Path does not exist: <absolute path>`. Path resolution is the
clamping resolver. See `assist-search-git-tools.md` §13.

## 66. `symbol_move_file` — Move Symbol Across Files

- **Description (verbatim):** "Moves a top-level Swift
  declaration from a source file to a destination file by
  extracting its brace-balanced block, removing it from the
  source, and appending it to the destination. Verifies the
  symbol is present in the destination and its declaration is
  gone from the source, restoring both files on verification
  failure. Brace matching is heuristic and does not parse
  strings or comments."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Moves one symbol declaration from a source file to a destination file.",
  "properties": {
    "symbol": {
      "type": "string",
      "description": "Name of the symbol to move."
    },
    "sourcePath": {
      "type": "string",
      "description": "Workspace-relative path of the file containing the symbol."
    },
    "destinationPath": {
      "type": "string",
      "description": "Workspace-relative path of the file receiving the symbol."
    }
  },
  "required": ["symbol", "sourcePath", "destinationPath"]
}
```

**Output (success).** Message:
`Moved symbol '<symbol>' (<kind>, <n> line(s)) from <sourceRel> to <destinationRel>.`
Structured data keys (all strings):

| Key | Value |
|---|---|
| `symbol` | The symbol name. |
| `kind` | The declaration kind (`func`, `class`, `struct`, `enum`, `protocol`, `actor`, `var`, `let`, `typealias`). |
| `sourcePath` | The source path (workspace-relative). |
| `destinationPath` | The destination path (workspace-relative). |
| `movedLines` | Number of lines moved. |

**Accepted aliases:** `symbol` may also be given as
`symbolName`; `sourcePath` may also be given as `source_path`;
`destinationPath` may also be given as `destination_path`
(Legacy handler leniency; not supported in the Ycode port — see
§53.6).

**Notes.** Validation runs in Legacy's order (identifier,
paths, difference, readability, destination-declares check,
declaration found). The block is extracted by brace counting:
at most 500 lines from the declaration; no opening brace within
20 lines moves a `var` / `let` / `typealias` as a single line
and fails anything else. Gate: one `commit()` per file, source
first, then destination; verification after both commits
restores both files on failure (see
`assist-search-git-tools.md` §1.5 and §16). Path resolution is
the strict resolver for both paths. See
`assist-search-git-tools.md` §16.

## 67. `symbol_reference_graph` — Symbol Reference Graph

- **Description (verbatim):** "Traverses workspace files to
  identify declarations, references, and call sites for a given
  Swift symbol."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds all occurrences, definitions, and references for a symbol across workspace source files.",
  "properties": {
    "symbol": {
      "type": "string",
      "description": "Symbol name (e.g. MyViewModel, fetchUserData, UserRecord)."
    },
    "maxResults": {
      "type": "integer",
      "description": "Maximum number of call sites to return (default: 50)."
    }
  },
  "required": ["symbol"]
}
```

**Output (success).** No matches:
`No references found for symbol '<symbol>' in workspace.`
No structured data. Matches: a Markdown report,
`### Symbol Reference Graph for \`<symbol>\` (<n> sites found):`
followed by a `#### Declarations:` section (only when there
are declarations) and a `#### Usages & Call Sites:` section
with at most 40 usages, each line
`` - `<rel>:<line>` → `<trimmed line>` ``. No structured data.

**Accepted aliases:** none at the parameter level. The canonical
alias `symbol_graph` resolves to this tool; see §53.6.

**Notes.** Enumeration skips hidden files and package
descendants; `.swift` files only; UTF-8 only; case-sensitive
substring matching. A line is a *declaration* only when its
trimmed form *starts* with `func <symbol>`, `class <symbol>`,
etc. — `public struct Foo` is not counted as a declaration.
Collection stops at `maxResults` (default 50); a value ≤ 0 still
yields one match, as in Legacy. Enumeration order is filesystem
order; the report does not sort matches. See
`assist-search-git-tools.md` §9.

## 68. `symbol_rename_project` — Rename Symbol Project-Wide

- **Description (verbatim):** "Renames a symbol across Swift
  files by replacing whole-word occurrences of oldName with
  newName. Only files that actually change are rewritten.
  Refuses when oldName equals newName or either name is not a
  valid Swift identifier."
- **Capability:** `fileModification`. **Risk:** `safeMutation`.
  **Required permission:** `fileSystem`. **Read-only:** no.
  **Write.** **MCP annotations:** `readOnly: false,
  idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Renames a symbol project-wide with whole-word replacement.",
  "properties": {
    "oldName": {
      "type": "string",
      "description": "Existing symbol name to replace."
    },
    "newName": {
      "type": "string",
      "description": "New symbol name. Letters, digits, and underscores only; must not start with a digit."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to search. Defaults to the workspace root."
    }
  },
  "required": ["oldName", "newName"]
}
```

**Output (success).** No Swift files in scope:
`Rename Symbol: no Swift files found.` with data
`filesChanged` `""`, `replacementCount` 0, `changedFileCount` 0.
No occurrences:
`Rename Symbol: no whole-word occurrences of '<oldName>' found in <n> Swift file(s). Nothing changed.`
with the same zero data. Otherwise:
`Rename Symbol: replaced <total> whole-word occurrence(s) of '<oldName>' with '<newName>' across <n> file(s):`
followed by `- <rel>` lines. Structured data keys (all strings):

| Key | Value |
|---|---|
| `filesChanged` | The changed paths, newline-joined (a string, as in Legacy — not a list). |
| `replacementCount` | Total whole-word replacements. |
| `changedFileCount` | Number of files rewritten. |

**Accepted aliases:** `oldName` may also be given as
`old_name`; `newName` may also be given as `new_name` (Legacy
handler leniency; not supported in the Ycode port — see §53.6).

**Notes — textual rename, not semantic rename.** This tool has
no Swift symbol index: it renames every whole-word occurrence
of `oldName`, including occurrences in comments, strings, and
unrelated declarations that happen to share the name. It must
never be described as a semantic rename. The scope is a single
`.swift` file (≤ 300 KB) or a directory walk (hidden files NOT
skipped; `.git`, `DerivedData`, `.build`, `Pods`, and
`node_modules` pruned; `.swift` only; ≤ 300 KB each; at most
5000 files; sorted by path). Gate: one `commit()` per changed
file, in enumeration order, stopping at the first refusal;
earlier files stay renamed (the Wave 2 multi-file shape). See
`assist-search-git-tools.md` §17.

## 69. `type_hierarchy` — Type Hierarchy

- **Description (verbatim):** "Maps class/struct/enum/protocol
  declarations and their inheritance and conformance clauses
  across Swift sources."
- **Capability:** `diagnostics`. **Risk:** `safeRead`.
  **Required permission:** `none`. **Read-only:** yes.
  **MCP annotations:** `readOnly: true, idempotent: true`.
  **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Maps type declarations and inheritance.",
  "properties": {
    "type": {
      "type": "string",
      "description": "Optional: focus on one type name and show its ancestors/descendants."
    }
  },
  "required": []
}
```

**Output (success).** Two shapes (see §53.4):

No `type`: message `Type declarations (<n> total):` followed by
at most 200 lines
`- <kind> <name>[: <parents>] — <rel>:<line>`, sorted by name,
with a `… [truncated: showing 200 of <n>]` line when more.
Structured data key: `typeCount`.

With `type`: message
`Type hierarchy for '<focus>' (<kind>) at <loc>:` followed by
`Inherits/conforms to:` (the parents, one `- <parent>` line
each, or `- (none)`) and `Subtypes (<n>):` (the subtypes, one
`- <name> (<kind>)` line each, sorted, or `- (none)`).
Structured data keys: `type`, `childCount`.

**Accepted aliases:** none at the parameter level.

**Notes.** Later declarations of the same name overwrite
earlier ones. An empty or whitespace-only `type` is treated as
no focus (the full listing). A focus type that is not declared
fails with
`Type '<focus>' not found in workspace Swift sources.` See
`assist-search-git-tools.md` §8.

## 70. Summary: capability / risk / permission / writes (Wave 3)

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `call_hierarchy` | diagnostics | safeRead | none | yes | false |
| `code_summary` | diagnostics | safeRead | none | yes | false |
| `dependency_graph` | repositoryDiscovery | safeRead | none | yes | false |
| `extract_code_symbols` | fileReading | safeRead | none | yes | false |
| `import_graph` | diagnostics | safeRead | none | yes | false |
| `protocol_conformance_list` | diagnostics | safeRead | none | yes | false |
| `search_regex` | repositoryDiscovery | safeRead | none | yes | false |
| `search_skills` | repositoryDiscovery | safeRead | none | yes | false |
| `search_symbol` | repositoryDiscovery | safeRead | none | yes | false |
| `search_text` | repositoryDiscovery | safeRead | none | yes | false |
| `semantic_query_engine` | repositoryDiscovery | safeRead | none | yes | false |
| `source_graph_builder` | repositoryDiscovery | safeRead | none | yes | false |
| `symbol_move_file` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `symbol_reference_graph` | repositoryDiscovery | safeRead | none | yes | false |
| `symbol_rename_project` | fileModification | safeMutation | fileSystem | **no** | **true** |
| `type_hierarchy` | diagnostics | safeRead | none | yes | false |

14 tools read; 2 (`symbol_move_file`, `symbol_rename_project`)
write. No tool in this wave is `potentiallyDestructive`.

## Wave 3 — Git tools

This part of the catalogue covers the 13 Wave 3 Git tools: the Git / source-control family ported from SwiftCode Legacy Assist into Ycode in Wave 3. Scope: exactly these 13 tools, verified live from the Legacy registry. No other tool is in scope for Wave 3, and no tool may be invented, renamed, or merged with another.

| ID | Title |
|---|---|
| `conflict_marker_scan` | Conflict Marker Scan |
| `git_bisect` | Git Bisect |
| `git_blame_inspector` | Git Blame Inspector |
| `git_branch_compare` | Compare Branches |
| `git_branch_manager` | Git Branch Manager |
| `git_cherry_pick` | Git Cherry-Pick |
| `git_conflict_resolver` | Git Conflict Resolver |
| `git_log_viewer` | Git Log Viewer |
| `git_pr_summary` | PR Summary |
| `git_stash_operator` | Git Stash Operator |
| `github_repo` | GitHub Repository Inspector |
| `recent_changes` | Recent Changes |
| `version_control_operator` | Version Control Operator |

**The read-only correction.** `git_pr_summary` is catalogued with the Git tools and is sometimes assumed to need the GitHub API. It does not: Legacy's description says it uses "only local git history. No network, no GitHub API", and its implementation is four local git commands. It is specified as a read-only local tool (`writes: false`). Only `github_repo` needs the GitHub API, and Ycode has no GitHub client yet — see §71.4.

## 71. Wave 3 conventions (extending §1 and §27)

### 71.1 Result envelope — Wave 3 additions

§1.1 applies unchanged, with two Wave 3 notes:

- `filesChanged` is never set by any Git tool in Legacy, and the port preserves that — including for the tools that change files (`git_branch_manager`, `git_cherry_pick`, `git_conflict_resolver`, `git_stash_operator`, `git_bisect`, `version_control_operator`). The Ycode port has no `filesChanged` field on `MCPToolResult` in any case; `git_conflict_resolver`'s text write is reported through the normal session edit note, as Wave 2 text writes are.
- `diff` is never set by any Git tool. Legacy-only envelope fields (`duration`, `suggestedNextActions`, `beforeContent`, `afterContent`) have no Ycode equivalent and are dropped, as in Wave 2.

### 71.2 Risk → annotations for Wave 3

§1.3 applies unchanged, extended by one row for the risk level Wave 1/2 never met:

| Legacy `riskLevel` | Ycode `MCPToolAnnotations` | `writes` |
|---|---|---|
| `safeRead` | `readOnly: true, idempotent: true` | `false` |
| `safeMutation` | `readOnly: false, idempotent: true` | `true` |
| `execution` | `readOnly: false, idempotent: false` | `true` |
| `potentiallyDestructive` | `readOnly: false, destructive: true` | `true` |

`writes: true` applies to exactly 6 tools in this wave: `git_bisect`, `git_branch_manager`, `git_cherry_pick`, `git_conflict_resolver`, `git_stash_operator`, `version_control_operator`. The one `potentiallyDestructive` tool is `version_control_operator`; the one `execution` tool is `git_bisect`. Legacy's derived permission for `execution` is `none` (only mutating tools — `safeMutation` / `potentiallyDestructive` — require `fileSystem`); `git_bisect` is therefore the only writing tool in this wave whose Legacy permission is `none`.

### 71.3 Gate per tool

Every `writes: true` tool is gated by `MCPServer.run()` and its handler-side shape — see `assist-approval-model.md` §6 for the full table. In short:

- Text resolution goes through `commit()`: `git_conflict_resolver` take_ours/take_theirs.
- Every other mutation uses an explicit `MCPChange` + `guard await call.approve(change)` before running git: `git_bisect` (every action except `log`), `git_branch_manager` (create/switch/delete), `git_cherry_pick`, `git_stash_operator` (save/pop/drop), `version_control_operator` (commit/branch/rollback). The change's path is the workspace root (relative path `"."`), since a git operation has no single file.
- Read-only actions of a writing tool request no approval but are still refused in `readOnly` mode because the tool is registered `writes: true`: `git_bisect` log, `git_branch_manager` list/current, `git_stash_operator` list/show, `git_conflict_resolver` inspect, `version_control_operator` status/diff. This is the Wave 2 dry-run precedent (§27.3 / approval-model §6.4).

### 71.4 The `github_repo` honest failure

`github_repo` is registered with its Legacy ID, title, description, and schema, but its handler always fails: Ycode's MCP host has no GitHub API client and no GitHub credential store, and this wave must not touch remotes or GitHub. The failure names the missing GitHub client/auth prerequisite; no GitHub data is fetched and none is faked. Remote/GitHub access is a later wave (the audit records that the GitHub remote layer needs a new target; `YcodeIDECore/SourceControl` is local-git only). This is the Wave 2 `code_refactor` precedent (registered but honestly failing).

### 71.5 Aliases — accepted, but never canonical

The Legacy registry resolves these aliases to the canonical IDs in this wave. The Ycode port must accept them at `tools/call` time (through `MCPServer.toolAliases`, as Waves 1–2 did); the canonical ID is what is registered, listed, and returned in metadata:

- `git`, `git_status`, `git_diff`, `git_commit`, `git_branch`, `git_rollback`, `git_tool`, `version_control` → `version_control_operator`
- `git_stash` → `git_stash_operator`
- `git_blame` → `git_blame_inspector`
- `git_branches` → `git_branch_manager`
- `git_log` → `git_log_viewer`
- `git_conflict` → `git_conflict_resolver`

No registry aliases exist for `conflict_marker_scan`, `git_bisect`, `git_branch_compare`, `git_cherry_pick`, `git_pr_summary`, `github_repo`, or `recent_changes`.

### 71.6 The git runner

All git operations run the `git` CLI as an argument vector — never a shell — with the workspace folder as the working directory, exactly as Legacy's `runGit` helpers do (`/usr/bin/git` there; the Flatpak-aware `HostTool` path here). The environment mirrors `GitRepository.environment`: inherited, minus the variables that could point git at another repository, plus the never-wait-for-a-person settings (`GIT_TERMINAL_PROMPT=0`, `GIT_PAGER=cat`, `GIT_EDITOR=true`, `GIT_ASKPASS=true`, `GIT_OPTIONAL_LOCKS=0`). Nothing here touches a remote: there is no push/pull/fetch/clone and no GitHub API call. A workspace that is not a git repository fails with git's own "not a git repository" message — never invented log/blame/status output. See `assist-search-git-tools.md` for the full safety rules.

## 72. `conflict_marker_scan` — Conflict Marker Scan

- **Description (verbatim):** "Scans source files for unresolved merge-conflict markers (<<<<<<<, =======, >>>>>>>)."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans for merge-conflict markers.",
  "properties": {
    "limit": {
      "type": "integer",
      "description": "Maximum files to report. Default 50."
    }
  },
  "required": []
}
```

**Output (success).** None found: `No merge-conflict markers found in source files.` with data `fileCount: "0"`. Found: `Files with unresolved conflict markers (<count>):` followed by one line per file, sorted by path: `- <path>: lines <n1, n2, ...>` (at most 10 line numbers per file). Structured data keys (all strings):

| Key | Value |
|---|---|
| `fileCount` | Number of files containing markers. |

**Notes.** Only source files are scanned (extensions `swift`, `m`, `mm`, `h`, `c`, `cpp`, `hpp` — Legacy `AssistWorkspaceScan.sourceExts`), skipping hidden files and the top-level `.git`, `.build`, `build`, `DerivedData`, `.swiftpm`, `Pods`, `Carthage`, `node_modules`, `.venv` directories, at most 20,000 files. `limit` defaults to 50 and is clamped to 1…500. A marker is a line starting with `<<<<<<<`, `=======`, or `>>>>>>>`. Files that do not decode as UTF-8 are skipped. This tool needs no git repository — it is a filesystem scan. See `assist-search-git-tools.md` ("Git tools").

## 73. `git_bisect` — Git Bisect

- **Description (verbatim):** "Runs one step of git bisect (start, good, bad, skip, reset, or log) in the workspace repository."
- **Capability:** `gitOperations`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **Write.** **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Runs one step of git bisect (start, good, bad, skip, reset, or log) in the workspace repository.",
  "properties": {
    "action": {
      "type": "string",
      "description": "Bisect action: start, good, bad, skip, reset, or log. Default: log."
    },
    "ref": {
      "type": "string",
      "description": "Commit ref for the good or bad action."
    }
  },
  "required": []
}
```

**Output (success).** Message: `Git bisect <action> succeeded.\n<git output>` (or `Git bisect <action> completed with no output.` when git prints nothing). Structured data keys (all strings):

| Key | Value |
|---|---|
| `action` | The action actually run, lowercased. |
| `output` | Git's merged stdout+stderr output, trimmed. |

**Notes.** `action` defaults to `log` and is lowercased; anything outside `start, good, bad, skip, reset, log` fails with `Invalid bisect action '<action>'. Allowed: start, good, bad, skip, reset, log.` `ref` is used only for `good`/`bad` and must pass Legacy's ref validator (see `assist-search-git-tools.md` ("Git tools")); an invalid ref fails with `Invalid git ref: <ref>`. Gate: every action except `log` requires approval before git runs — bisect moves the checkout. `log` with no bisect in progress fails with git's own message (`Git bisect log failed: error: We are not bisecting.`), exactly as Legacy reports it. See §71.2 for the `execution` → annotation mapping and §71.3 for the gate.

## 74. `git_blame_inspector` — Git Blame Inspector

- **Description (verbatim):** "Inspects author, commit hash, date, and commit message for specific lines in a workspace file."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs git blame on a target file to analyze authorship, commit history, and modifications for specific lines.",
  "properties": {
    "path": {
      "type": "string",
      "description": "Relative path to the file in workspace."
    },
    "startLine": {
      "type": "integer",
      "description": "Optional starting line number."
    },
    "endLine": {
      "type": "integer",
      "description": "Optional ending line number."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message: `Git blame for \`<path>\`:\n\n` followed by the readable blame lines (at most 50). **No structured data is returned.**

**Notes.** The tool runs `git blame --porcelain` first (its failure is the tool's failure: `git blame failed: <git output>`), then `git blame -s` for the readable snippet. The output is therefore the `-s` rendering — short hash, line number, line text — with **no author name** (`-s` suppresses it). The `-L` range rules differ between the two runs, preserved here: the porcelain run takes a full range (`start,end`) or a lone start line (`start,start+30`); the readable run takes only a full range. A lone start line with no end line therefore blames 31 lines in the porcelain check but the whole file in the displayed snippet's range handling. The path resolves inside the workspace like every other Ycode tool. Ycode's `GitBlame.parse` seam is not used for this output: it drops the line text the `-s` rendering shows. See `assist-search-git-tools.md` ("Git tools").

## 75. `git_branch_compare` — Compare Branches

- **Description (verbatim):** "Compares two branches with diff stat plus the commits in head not in base."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Compares two branches with diff stat plus the commits in head not in base.",
  "properties": {
    "base": {
      "type": "string",
      "description": "Base branch or ref."
    },
    "head": {
      "type": "string",
      "description": "Head branch or ref."
    }
  },
  "required": ["base", "head"]
}
```

**Output (success).** Message (exact shape):

```text
Branch comparison <base>...<head>

Commits in <head> not in <base> (<n>):
<one-line commits, or "No commits in <head> not in <base>.">

Diff stat:
<diff --stat output, or "No differences.">
```

Structured data keys (all strings):

| Key | Value |
|---|---|
| `base` | Base ref, trimmed. |
| `head` | Head ref, trimmed. |
| `commits` | The `log --oneline` output (`base..head`), possibly empty. |
| `diffStat` | The `diff --stat` output (`base...head`), possibly empty. |
| `commitCount` | Number of commits in head not in base. |

**Notes.** Both refs are trimmed; an empty or missing value fails with `Missing required parameter: base` / `head`. Both refs must pass Legacy's ref validator; otherwise `Invalid git ref for base: <base>` / `Invalid git ref for head: <head>`. The commits come from `git log --oneline <base>..<head>` (two dots) and the stat from `git diff --stat <base>...<head>` (three dots). A failing log fails as `Git log failed for <base>..<head>: <detail>`; a failing diff as `Git diff failed for <base>...<head>: <detail>`. See `assist-search-git-tools.md` ("Git tools").

## 76. `git_branch_manager` — Git Branch Manager

- **Description (verbatim):** "Inspects, lists, creates, switches, and manages Git branches in the workspace."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **Write.** **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Manages repository branches. Actions: 'list', 'current', 'create', 'switch', 'delete'.",
  "properties": {
    "action": {
      "type": "string",
      "description": "Action: 'list', 'current', 'create', 'switch', or 'delete'."
    },
    "branchName": {
      "type": "string",
      "description": "Branch name when creating, switching, or deleting."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Message: git's output, trimmed; or `Branch operation '<action>' succeeded.` when git prints nothing. **No structured data is returned.**

**Accepted aliases:** `git_branches` resolves to this tool; see §71.5.

**Notes.** Actions (case-insensitive): `list` / `branches` → `git branch -a`; `current` → `git branch --show-current`; `create` → `git checkout -b <name>` (the branch is created **and** checked out, as in Legacy); `switch` / `checkout` → `git checkout <name>`; `delete` → `git branch -d <name>` (safe delete: refuses an unmerged branch). `create`/`switch`/`delete` require a non-empty `branchName` (`Action '<action>' requires 'branchName'.`) and the name must pass the strict allow-list validator (see `assist-search-git-tools.md` ("Git tools")) — a tightening over Legacy, which passed the name to argv unvalidated. Gate: create/switch/delete require approval before git runs; list/current do not, but the tool is registered `writes: true`, so a `readOnly` server refuses even those. An unknown action fails with `Unsupported action '<action>'. Supported: list, current, create, switch, delete.` A failing git run fails as `Git branch operation failed: <git output>`. See §71.3 and `assist-search-git-tools.md` ("Git tools").

## 77. `git_cherry_pick` — Git Cherry-Pick

- **Description (verbatim):** "Cherry-picks one commit onto the current branch. On conflict it reports the conflicted files and leaves the state for manual resolution."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **Write.** **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Cherry-picks one commit onto the current branch.",
  "properties": {
    "commit": {
      "type": "string",
      "description": "Full or short commit SHA, or a validated ref to cherry-pick."
    },
    "noCommit": {
      "type": "string",
      "description": "Pass \"true\" to stage the change without committing (--no-commit). Default: false."
    }
  },
  "required": ["commit"]
}
```

**Output (success).** Message: `Cherry-picked <commit>.\n<git output>` (or `Cherry-pick completed with no output.` when git prints nothing). Structured data keys (all strings):

| Key | Value |
|---|---|
| `commit` | The commit argument, trimmed. |
| `output` | Git's merged stdout+stderr output, trimmed. |

**Notes.** `commit` is trimmed; empty fails with `Missing required parameter: commit`. It must be a 7–40 hex SHA or a valid ref, else `Invalid commit: <commit>`. **`noCommit` keeps Legacy's string schema type** (not a boolean): `"true"`, `"1"`, or `"yes"` (case-insensitive, trimmed) mean `--no-commit`; anything else, including a boolean, follows Legacy's `boolValue` parsing (a JSON boolean `true` also counts). Gate: approval is required before git runs. On failure with conflicts, the tool lists the conflicted files from `git status --porcelain` (codes `DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU`): `Cherry-pick of <commit> stopped due to conflicts in: <files>. Resolve the conflicts and commit, or run git cherry-pick --abort. Git output: <output>`. Any other failure is `Git cherry-pick failed: <output or "unknown error">`. The cherry-pick is left stopped, for manual resolution — the tool never aborts or continues it. See §71.3 and `assist-search-git-tools.md` ("Git tools").

## 78. `git_conflict_resolver` — Git Conflict Resolver

- **Description (verbatim):** "Detects, inspects, and helps resolve Git merge conflict markers in workspace source files."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **Write.** **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Scans for and resolves merge conflict markers (<<<<<<< HEAD ... ======= ... >>>>>>>).",
  "properties": {
    "path": {
      "type": "string",
      "description": "Relative path to file with merge conflicts."
    },
    "resolution": {
      "type": "string",
      "description": "Optional resolution strategy: 'inspect', 'take_ours', 'take_theirs'. Defaults to 'inspect'."
    }
  },
  "required": ["path"]
}
```

**Output (success).** No markers: `No active Git conflict markers (<<<<<<< / ======= / >>>>>>>) found in <path>.` Inspect: `### Detected <n> Merge Conflict(s) in \`<path>\`:` followed by one `#### Conflict #<i>:` fenced block per conflict, then `Use resolution: 'take_ours' or 'take_theirs', or code_replace to resolve precisely.` Resolved: `Successfully resolved all conflict markers in \`<path>\` using '<resolution>'.` **No structured data is returned in any outcome.**

**Accepted aliases:** `git_conflict` resolves to this tool; see §71.5.

**Notes.** `resolution` defaults to `inspect` and is lowercased. A file is "conflicted" only when its content contains all three of `<<<<<<<`, `=======`, `>>>>>>>`; that check happens before the resolution is validated, so an unknown resolution on a marker-free file reports no markers rather than an error. `inspect` reads only, but the tool is registered `writes: true`, so a `readOnly` server refuses even `inspect` (see §71.3). `take_ours` / `take_theirs` drop the marker lines and keep only the chosen side's lines (Legacy's state machine), and write the result through `commit()` — the full before/after goes to review. An unknown resolution fails with `Unknown resolution '<resolution>'. Use 'inspect', 'take_ours', or 'take_theirs'.` Missing file: `File not found at path: <path>`; unreadable as UTF-8: `Unable to read content of file at <path>`. Legacy's absolute-path carve-out (a leading-`/` path used as a raw filesystem path, which could resolve conflicts outside the workspace) is **not** reproduced: paths resolve inside the workspace like every other Ycode tool. Ycode's `GitRepository.resolveConflict` seam is not used: it also stages the file (`git add`), while Legacy only writes the resolved text. See `assist-search-git-tools.md` ("Git tools").

## 79. `git_log_viewer` — Git Log Viewer

- **Description (verbatim):** "Retrieves structured commit history, commit hashes, dates, authors, and changed file stats."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Fetches recent Git commit history with author and message details.",
  "properties": {
    "maxCount": {
      "type": "integer",
      "description": "Maximum number of commits to retrieve (default: 15)."
    },
    "path": {
      "type": "string",
      "description": "Optional specific file or directory path to filter log history for."
    }
  },
  "required": []
}
```

**Output (success).** No commits: `No commits found in the repository history.` Otherwise:

```text
### Recent Git Commits (<n> entries):

- `<shortHash> | <author> | <date> | <subject>`
…
```

**No structured data is returned.**

**Accepted aliases:** `git_log` resolves to this tool; see §71.5.

**Notes.** `maxCount` defaults to 15 and is passed to `git log -n` as given (Legacy does not clamp it). `path`, when non-empty, is resolved inside the workspace and passed as `git log … -- <workspace-relative path>`. A failing git run fails as `git log failed: <git output>` — including the "not a git repository" failure for a workspace with no repository. See `assist-search-git-tools.md` ("Git tools").

## 80. `git_pr_summary` — PR Summary

- **Description (verbatim):** "Builds a local markdown PR summary (commits, files changed, insertions/deletions) for head versus base using only local git history. No network, no GitHub API."
- **Capability:** `gitOperations`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Builds a local markdown PR summary for head versus base using only local git history.",
  "properties": {
    "base": {
      "type": "string",
      "description": "Base branch or ref. Default: main."
    },
    "head": {
      "type": "string",
      "description": "Head branch or ref. Default: HEAD."
    }
  },
  "required": []
}
```

**Output (success).** Message (exact shape):

```text
# PR Summary

Base: `<base>` → Head: `<head>`

## Commits (<n>)
- <one-line commit>
… (or "No commits in <head> not in <base>.")

## Files changed (<n>)
- `<file>`
… (or "No files changed.")

## Stats
<diff --shortstat output, or "No changes.">

Files changed: <n> | Insertions: <n> | Deletions: <n>
```

Structured data keys (all strings):

| Key | Value |
|---|---|
| `summary` | The full markdown text above. |
| `base` | Base ref, trimmed. |
| `head` | Head ref, trimmed. |
| `commitCount` | Commits in head not in base. |
| `fileCount` | Files changed (from `--name-only` when non-empty, else from the shortstat count). |
| `insertions` | Insertions parsed from the shortstat. |
| `deletions` | Deletions parsed from the shortstat. |
| `shortstat` | The `diff --shortstat` output, possibly empty. |

**Notes.** `base` defaults to `main`, `head` to `HEAD`; both are trimmed and must be non-empty and pass Legacy's ref validator (`Base ref must not be empty.` / `Head ref must not be empty.` / `Invalid git ref for base: <base>` / `Invalid git ref for head: <head>`). The four git commands are `log --oneline <base>..<head>`, `diff --stat <base>...<head>`, `diff --shortstat <base>...<head>`, `diff --name-only <base>...<head>`; a failing log or stat fails the tool (`Git log failed for <base>..<head>: <detail>` / `Git diff failed for <base>...<head>: <detail>`), while a failing shortstat or name-only is tolerated as empty. Despite the name, this tool never contacts GitHub — it is purely local. See `assist-search-git-tools.md` ("Git tools").

## 81. `git_stash_operator` — Git Stash Operator

- **Description (verbatim):** "Manages Git stashes (save, pop, list, show, drop) to safely stash and restore changes during refactoring."
- **Capability:** `gitOperations`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **Write.** **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Save, restore, or inspect git stashed changes in the active workspace.",
  "properties": {
    "action": {
      "type": "string",
      "description": "Action: 'save', 'pop', 'list', 'show', 'drop'."
    },
    "message": {
      "type": "string",
      "description": "Optional descriptive message for 'save'."
    },
    "stashIndex": {
      "type": "string",
      "description": "Stash identifier for pop/show/drop (e.g. 'stash@{0}', defaults to 'stash@{0}')."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Message: git's stdout when non-empty, else its stderr, else `Git stash <action> completed.` **No structured data is returned.**

**Accepted aliases:** `git_stash` resolves to this tool; see §71.5.

**Notes.** Actions (case-insensitive): `save` / `push` → `git stash push` (plus `-m <message>` when a non-empty message is given); `pop` → `git stash pop <stash>`; `list` → `git stash list`; `show` → `git stash show -p <stash>`; `drop` → `git stash drop <stash>`. `stashIndex` defaults to `stash@{0}` and must be `stash@{N}` or a plain number, else `Invalid stash identifier: <stashIndex>` — a tightening over Legacy, which passed it to argv unvalidated. Gate: save/pop/drop require approval before git runs; list/show do not, but the tool is registered `writes: true`, so a `readOnly` server refuses even those. A failing git run fails as `Git stash <action> failed (exit <code>):\n<stderr>\n<stdout>`. An unknown action fails with `Unsupported action '<action>'. Valid: save, pop, list, show, drop`. Ycode's `GitRepository` stash seam (`stashPatch` / `exportStash`) covers only exporting a stash as a patch and is not used here. See §71.3 and `assist-search-git-tools.md` ("Git tools").

## 82. `github_repo` — GitHub Repository Inspector

- **Description (verbatim):** "Reads real GitHub repositories: metadata, file trees, directory listings, source file contents, code search, and bounded full-repository retrieval. Public repos need no login; private repos use the user's saved GitHub credential."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inspects a GitHub repository. 'operation' is required; identify the repo with owner+repo or url.",
  "properties": {
    "operation": {
      "type": "string",
      "description": "One of: repository_info, list_files, get_file, get_directory, get_tree, search_code, fetch_repository."
    },
    "owner": {
      "type": "string",
      "description": "Repository owner or organization, e.g. 'dylans2010'."
    },
    "repo": {
      "type": "string",
      "description": "Repository name, e.g. 'SwiftCode-Mac'."
    },
    "url": {
      "type": "string",
      "description": "GitHub repository URL, e.g. https://github.com/dylans2010/SwiftCode-Mac. Alternative to owner+repo."
    },
    "ref": {
      "type": "string",
      "description": "Branch, tag, or commit SHA. Defaults to the repository's default branch."
    },
    "path": {
      "type": "string",
      "description": "Repository-relative file or directory path for list_files, get_file, get_directory."
    },
    "recursive": {
      "type": "boolean",
      "description": "For get_tree: fetch the full recursive tree (default true). For list_files: recurse into subdirectories via the tree."
    },
    "includeContent": {
      "type": "boolean",
      "description": "For list_files/get_directory: also fetch each file's content (bounded by maxBytes). Default false."
    },
    "maxResults": {
      "type": "integer",
      "description": "Maximum entries/files/matches to return. Defaults: 100 (listings), 5000 (tree), 50 (search), 50 (fetch_repository)."
    },
    "maxBytes": {
      "type": "integer",
      "description": "Maximum aggregate content bytes to return (fetch_repository, includeContent). Default 262144 (256 KB), hard cap 2097152 (2 MB)."
    },
    "query": {
      "type": "string",
      "description": "For search_code: text to find. For fetch_repository: prioritizes files whose path or name matches."
    }
  },
  "required": ["operation"]
}
```

**Output.** This tool has no success output in Ycode: its handler always fails with an error naming the missing GitHub API client/auth prerequisite. No GitHub data is fetched and none is faked.

**Notes.** Legacy's tool reads live repositories over the GitHub API (public repos unauthenticated, private repos with the user's saved credential), with operations `repository_info`, `list_files`, `get_file`, `get_directory`, `get_tree`, `search_code`, `fetch_repository`; code search is client-side over fetched files, recursive trees are capped by the API, binary files are classified never decoded, and unauthenticated rate limits (60 requests/hour) are reported, never retried. None of that can be reproduced without a GitHub client, so the Ycode port keeps the ID, title, description, and schema (so callers and the catalogue stay aligned) and fails honestly. Remote/GitHub access is a later wave. See §71.4 and `assist-search-git-tools.md` ("Git tools").

## 83. `recent_changes` — Recent Changes

- **Description (verbatim):** "Lists workspace files modified within the last N hours, newest first. Catches local edits regardless of git state."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lists files modified within a recent time window.",
  "properties": {
    "hours": {
      "type": "integer",
      "description": "Look-back window in hours. Default 24, max 720."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum files to return. Default 50, max 500."
    }
  },
  "required": []
}
```

**Output (success).** None found: `No files modified in the last <hours>h.` with data `count: "0"`. Found: `Files modified in the last <hours>h (<total> total):` followed by one line per file, newest first: `- <path> — <ISO-8601 modification date>`, plus a trailing line `… [truncated: showing <limit> of <total>]` when more files changed than shown. Structured data keys (all strings):

| Key | Value |
|---|---|
| `count` | Total number of files modified in the window (not capped by `limit`). |
| `hours` | The look-back window actually used. |

**Notes.** `hours` defaults to 24 and is clamped to 1…720; `limit` defaults to 50 and is clamped to 1…500. The scan is the same workspace scan as `conflict_marker_scan` (hidden files and the top-level VCS/build/dependency directories skipped, at most 20,000 files) with no extension filter, and uses each file's modification date. This tool needs no git repository — it catches local edits regardless of git state. See `assist-search-git-tools.md` ("Git tools").

## 84. `version_control_operator` — Version Control Operator

- **Description (verbatim):** "Performs branch, commit, rollback, and diff operations using git."
- **Capability:** `gitOperations`. **Risk:** `potentiallyDestructive`. **Required permission:** `fileSystem`. **Read-only:** no. **Write — destructive.** **MCP annotations:** `readOnly: false, destructive: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Performs branch, commit, rollback, and diff operations using git.",
  "properties": {
    "action": {
      "type": "string",
      "description": "The git action to perform: status, commit, branch, rollback, or diff. Unknown actions are rejected."
    },
    "message": {
      "type": "string",
      "description": "The commit message (used for commit action)."
    },
    "name": {
      "type": "string",
      "description": "The branch name (used for branch action)."
    },
    "ref": {
      "type": "string",
      "description": "The git ref to reset to (used for rollback action). Default: HEAD~1. Must match the strict ref pattern; shell metacharacters are rejected."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Message: `Git action executed: <action>`. Structured data keys (all strings):

| Key | Value |
|---|---|
| `output` | Git's merged stdout+stderr output, trimmed. |

**Accepted aliases:** `git`, `git_status`, `git_diff`, `git_commit`, `git_branch`, `git_rollback`, `git_tool`, `version_control` resolve to this tool; see §71.5. (These aliases select the *tool*, not the action — the action still comes from the `action` argument.)

**Notes.** Actions (case-insensitive; missing `action` defaults to `status` in Legacy, though the schema requires it): `status` → `git status --short`; `diff` → `git diff -- .`; `commit` → `git add -A` then `git commit -m <message>` (message defaults to `Assist automated commit`); `branch` → `git checkout -b <name>` (name defaults to `assist/automation`); `rollback` → `git reset --hard <ref>` (ref defaults to `HEAD~1`). Branch names and rollback refs must pass the strict allow-list validator (see `assist-search-git-tools.md` ("Git tools")). Gate: commit/branch/rollback require approval before git runs; status/diff do not, but the tool is registered `writes: true`, so a `readOnly` server refuses even those. Failures: `Git commit failed: <output>`, `Git branch checkout failed: <output>`, `Git rollback failed: <output>`, `Git status failed: <output>` / `Git diff failed: <output>`. Remote actions (`push`, `pull`, `fetch`, `clone`) are **not** implemented in Legacy and are rejected here with an explicit error naming the later-wave prerequisite, instead of the generic unknown-action error. Any other unknown action fails with `Unknown git action '<action>': expected status, commit, branch, rollback, or diff.` Legacy's `#if os(macOS)` gate ("Version control operations require macOS runtime") is dropped: the git CLI exists on Linux too. See §71.3 and `assist-search-git-tools.md` ("Git tools").

## 85. Summary: capability / risk / permission / writes (Wave 3)

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `conflict_marker_scan` | diagnostics | safeRead | none | yes | false |
| `git_bisect` | gitOperations | execution | none | **no** | **true** |
| `git_blame_inspector` | gitOperations | safeRead | none | yes | false |
| `git_branch_compare` | gitOperations | safeRead | none | yes | false |
| `git_branch_manager` | gitOperations | safeMutation | fileSystem | **no** | **true** |
| `git_cherry_pick` | gitOperations | safeMutation | fileSystem | **no** | **true** |
| `git_conflict_resolver` | gitOperations | safeMutation | fileSystem | **no** | **true** |
| `git_log_viewer` | gitOperations | safeRead | none | yes | false |
| `git_pr_summary` | gitOperations | safeRead | none | yes | false |
| `git_stash_operator` | gitOperations | safeMutation | fileSystem | **no** | **true** |
| `github_repo` | repositoryDiscovery | safeRead | none | yes | false |
| `recent_changes` | repositoryDiscovery | safeRead | none | yes | false |
| `version_control_operator` | gitOperations | potentiallyDestructive | fileSystem | **no** | **true** |

7 tools read; 6 tools write. The one `potentiallyDestructive` tool is `version_control_operator`; the one `execution` tool is `git_bisect`; `github_repo` is registered but honestly failing (§71.4).

## Wave 4 — terminal / system tools

## 86. Wave 4 conventions (extending §1 and §27)

- **Argument vectors, never a shell.** `use_terminal` tokenizes its
  `command` into an argv vector; any shell metacharacter (`| & ; < > \`
  $ ( ) { } * ? ~ # !`, newline) is rejected. Legacy ran
  `/bin/zsh -c`; the port never runs a shell. Every other local command
  in this wave runs a fixed binary with fixed argv (`terminalRunFixed`).
- **Approval on every `use_terminal` run.** There is no allow-list, no
  Full Access, and no Autopilot bypass in Ycode, although the
  `use_terminal` description (kept verbatim) still mentions them.
  `use_system`'s single mutation needs both Legacy's `confirm: true`
  and the approval gate. All other writes go through `commit()` exactly
  like the Wave 2 file-writing tools.
- **The environment never waits for a person.** Subprocess environments
  carry `GIT_TERMINAL_PROMPT=0`; stdin is closed; timeouts apply
  (`use_terminal` 300 s).
- **Honestly-failing tools** are registered with their Legacy ID and
  schema, validate inputs first with Legacy-exact messages, then fail
  naming the exact prerequisite: `env_capture_logs`, `use_extension`,
  `use_composio`, `use_workers`, `take_screenrecord` (fully),
  `use_mcp` and `use_app` (partially).
- **Annotations** follow §1.3, extended: `safeRead` → `readOnly: true,
  idempotent: true`, `writes: false`; `safeMutation` → `readOnly:
  false, idempotent: true`, `writes: true`; `execution` →
  `readOnly: false, idempotent: false`, `writes: true`;
  `externalSideEffect` → `readOnly: false, idempotent: false,
  openWorld: true`, `writes: true`. New in this wave: `externalRead`
  (`readOnly: true, idempotent: true, openWorld: true`, `writes:
  false`) for `system_notification_tool` and `take_screenrecord`.
  `take_screenshot` is the one deliberate deviation: Legacy declares
  it `safeRead`, but the port saves a PNG artifact, so it is
  `readOnly: false, idempotent: true, openWorld: true`, `writes: true`.
- **Permissions** follow §1.2: `take_screenshot` / `take_screenrecord`
  → `screenRecording`; `use_app` → `accessibility`; `use_terminal` →
  `terminalExecution`; any mutating tool → `fileSystem`; else `none`.
- Every tool accepts the Wave 1 `workspace` parameter; tools that do
  not touch a workspace accept it and ignore it. See
  `assist-terminal-memory-planning-tools.md` ("Terminal tools") for
  behaviour, error cases, and safety rules.

## 87. `use_terminal` — Use Terminal

- **Description (verbatim):** "Executes terminal commands on the user's machine. Commands on the user's allow-list (Assist Settings > Terminal Command Approvals), or any command when Full Access is enabled, run without an approval prompt; all other commands require explicit user approval."
- **Capability:** `systemExecution`. **Risk:** `execution`. **Required permission:** `terminalExecution`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Executes terminal commands on the user's machine. Commands on the user's allow-list (Assist Settings > Terminal Command Approvals), or any command when Full Access is enabled, run without an approval prompt; all other commands require explicit user approval.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "command": {
      "type": "string",
      "description": "The full shell command to run (e.g., 'git status' or 'swift test')"
    },
    "workingDirectory": {
      "type": "string",
      "description": "The relative path from project root where command should run (optional)"
    },
    "explanation": {
      "type": "string",
      "description": "A concise explanation of why this terminal execution is required (optional)"
    },
    "estimatedImpact": {
      "type": "string",
      "description": "The estimated impact on the repository (optional)"
    },
    "modifiesRepo": {
      "type": "string",
      "description": "Whether the command modifies repository state ('true' or 'false', optional)"
    }
  },
  "required": ["command"]
}
```

**Output (success).** Exit 0: `Terminal command executed successfully (exit code 0 in <duration>):\n<stdout or "(No stdout output)">`. Structured data keys:

| Key | Value |
|---|---|
| `command` | The command string as given. |
| `workingDirectory` | The absolute working directory actually used. |
| `stdout` | Last 3000 chars of stdout, with a truncation marker when cut. |
| `stderr` | Last 2000 chars of stderr, with a truncation marker when cut. |
| `stdoutTruncated` | Boolean. |
| `stderrTruncated` | Boolean. |
| `exitCode` | The child's exit code. |
| `duration` | Elapsed time, e.g. `"1.23s"`. |

**Notes.** Tokenize → resolve → approve → run, 300 s timeout. Empty
`workingDirectory` means the session working directory (see `dir_cd`),
not the workspace root; a missing or non-directory value fails.
`modifiesRepo` accepts a boolean as well as Legacy's string. Non-zero
exit is an error result carrying the same data. The description is
Legacy's verbatim; the behaviour is stricter — there is no allow-list
and every run is approved. See
`assist-terminal-memory-planning-tools.md` ("`use_terminal`").

## 88. `task_runner` — Run Task

- **Description (verbatim):** "Executes a registered internal Swift task within the sandbox."
- **Capability:** `systemExecution`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Executes a registered internal Swift task within the sandbox.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "task_id": {
      "type": "string",
      "description": "Identifier of the registered task to execute."
    }
  },
  "required": ["task_id"]
}
```

**Output (success).** Message: `Task '<task_id>' executed successfully.` Structured data keys:

| Key | Value |
|---|---|
| `output` | The task's report text. |

**Notes.** The four registered tasks are `project_indexing` (counts
filesystem entries under the workspace root), `dependency_analysis`
(reports SPM / CocoaPods / Carthage presence from `Package.swift` /
`Podfile` / `Cartfile`), `lint_project` (Legacy's
`collectSwiftFindings`: tab indentation, lines over 140 characters,
trailing whitespace, in every Swift file; at most 20 findings listed),
and `project_test` (Swift files whose path contains "test",
case-insensitive, sorted; 5 sampled). An unknown `task_id` fails with
`Task '<task_id>' failed: Task '<task_id>' not found in registry.`
See `assist-terminal-memory-planning-tools.md` ("`task_runner`").

## 89. `env_capture_logs` — Capture Logs

- **Description (verbatim):** "Captures logs from the execution environment."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Captures logs from the execution environment.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "memoryKey": {
      "type": "string",
      "description": "Optional memory key whose stored value is included as context. Default: \"\"."
    }
  },
  "required": []
}
```

**Output (success).** None: the tool is registered but honestly
failing (see Notes). No structured data.

**Notes.** The tool needs the Assist snapshot history
(`AssistSnapshotFunctions`) and the Assist memory store, neither of
which exists in Ycode's MCP host. It always fails with
`env_capture_logs needs the Assist snapshot history
(AssistSnapshotFunctions) and the Assist memory store, neither of which
exists in Ycode's MCP host; no logs were captured.` The `memoryKey`
argument is read and ignored. See
`assist-terminal-memory-planning-tools.md`
("`env_capture_logs`").

## 90. `env_info` — Environment Info

- **Description (verbatim):** "Provides information about the runtime environment (OS, Swift version, etc.)."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Provides information about the runtime environment (OS, Swift version, etc.).",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Message: `Environment info retrieved`. Structured data keys:

| Key | Value |
|---|---|
| `os` | The server process's OS version string (the real OS). |
| `locale` | The server process's locale identifier. |
| `timezone` | The server process's time-zone identifier. |
| `cpu_count` | Processor count. |
| `physical_memory_bytes` | Physical memory in bytes. |
| `workspace_root` | The workspace root's absolute path. |

**Notes.** This schema is declared in Ycode; Legacy declares no
`parametersSchema` for this tool. See
`assist-terminal-memory-planning-tools.md` ("`env_info`").

## 91. `use_mcp` — Execute MCP Tool

- **Description (verbatim):** "Enumerate configured MCP servers, discover capabilities, and execute external tools (e.g. GitHub, databases, developer services). Pass toolName: 'list_tools' to discover available tools."
- **Capability:** `general`. **Risk:** `externalSideEffect`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Enumerate configured MCP servers, discover capabilities, and execute external tools (e.g. GitHub, databases, developer services). Pass toolName: 'list_tools' to discover available tools.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "serverName": {
      "type": "string",
      "description": "The display name of the configured MCP server (or 'list' to enumerate all servers)."
    },
    "toolName": {
      "type": "string",
      "description": "The name of the tool to execute on the selected MCP server (or 'list_tools' to inspect available tools)."
    },
    "arguments": {
      "type": "string",
      "description": "A JSON-serialized object string containing the arguments to pass to the MCP tool (pass '{}' for list_tools)."
    }
  },
  "required": ["serverName", "toolName", "arguments"]
}
```

**Output (success).** The list branch only: `No MCP servers are currently configured in Ycode.` (plain text, no structured data).

**Notes.** Partial: `serverName` `"list"` (case-insensitive) or
`toolName` `"list_servers"` is answered honestly with the empty list.
Any other call fails naming the missing external MCP client
prerequisite; no external tool is called. Ycode itself is the MCP
server here; its own tools are listed by `tools/list`. See
`assist-terminal-memory-planning-tools.md` ("`use_mcp`").

## 92. `use_extension` — Use Extension

- **Description (verbatim):** "Interact with installed SwiftCode extensions: list, inspect, activate, and execute VS Code extension commands through the real extension host, and run Xcode-compatible source-editor commands against real workspace files. Actions: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics. Mutating actions (activate, execute, run_xcode_command, enable, disable) require confirm: true. Extension ids are stable publisher.name ids; Xcode command ids look like com.swiftcode.xcode.sortLines."
- **Capability:** `general`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Interact with installed SwiftCode extensions: list, inspect, activate, and execute VS Code extension commands through the real extension host, and run Xcode-compatible source-editor commands against real workspace files. Actions: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics. Mutating actions (activate, execute, run_xcode_command, enable, disable) require confirm: true. Extension ids are stable publisher.name ids; Xcode command ids look like com.swiftcode.xcode.sortLines.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "One of: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics."
    },
    "extensionId": {
      "type": "string",
      "description": "Stable publisher.name id of the extension. Required for every action except list and list_xcode_commands."
    },
    "command": {
      "type": "string",
      "description": "Command id for execute (a VS Code / native contributed command) or run_xcode_command (an Xcode command identifier, e.g. com.swiftcode.xcode.sortLines)."
    },
    "file": {
      "type": "string",
      "description": "Workspace-relative path for run_xcode_command. Absolute paths and paths escaping the workspace are rejected."
    },
    "selection": {
      "type": "object",
      "properties": {
        "startLine": {
          "type": "integer",
          "description": "First line of the selection."
        },
        "startColumn": {
          "type": "integer",
          "description": "First column of the selection."
        },
        "endLine": {
          "type": "integer",
          "description": "Last line of the selection."
        },
        "endColumn": {
          "type": "integer",
          "description": "Last column of the selection."
        }
      },
      "required": []
    },
    "args": {
      "type": "object"
    },
    "confirm": {
      "type": "boolean",
      "description": "Required true for activate, execute, run_xcode_command, enable, and disable; the model must explicitly confirm the consequential action."
    },
    "limit": {
      "type": "integer",
      "description": "Max rows for list and diagnostics (default 50, capped at 200)."
    }
  },
  "required": ["action"]
}
```

**Output (success).** None: the tool is registered but honestly
failing (see Notes). No structured data.

**Notes.** The tool needs the Extensions v2 platform (`ExtV2Manager`
+ extension host with Node.js), which Ycode's MCP host does not have
yet. An unknown or missing `action` fails first with `Unknown or
missing action. Use one of: list, details, list_commands,
list_xcode_commands, activate, deactivate, execute, run_xcode_command,
enable, disable, diagnostics.` A known action then fails naming the
Extensions v2 prerequisite; no extension was listed, activated, or
executed. See `assist-terminal-memory-planning-tools.md`
("`use_extension`").

## 93. `use_composio` — Execute Composio Tool

- **Description (verbatim):** "Execute external connected tools (GitHub, Slack, Google Calendar, Jira, Linear, Gmail, etc.) via Composio Platform or CLI."
- **Capability:** `general`. **Risk:** `externalSideEffect`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Execute external connected tools (GitHub, Slack, Google Calendar, Jira, Linear, Gmail, etc.) via Composio Platform or CLI.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "toolSlug": {
      "type": "string",
      "description": "The slug of the Composio tool to execute (e.g. 'GITHUB_GET_THE_AUTHENTICATED_USER', 'GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER', 'GITHUB_CREATE_AN_ISSUE', 'SLACK_SEND_A_MESSAGE_TO_A_SLACK_CHANNEL')."
    },
    "arguments": {
      "type": "string",
      "description": "A JSON-serialized object string containing the arguments to pass to the tool."
    }
  },
  "required": ["toolSlug", "arguments"]
}
```

**Output (success).** None: the tool is registered but honestly
failing (see Notes). No structured data.

**Notes.** The tool needs the Composio service (`ComposioService`
with a Composio API key and connected integrations), which Ycode's MCP
host does not have yet. It always fails naming that prerequisite and
the requested `toolSlug`; no external tool is executed. See
`assist-terminal-memory-planning-tools.md` ("`use_composio`").

## 94. `use_workers` — Create and Coordinate Assist Workers

- **Description (verbatim):** "Decomposes and schedules parallel or sequenced autonomous Workers for sub-tasks.\nEach worker must have a distinct name, non-overlapping scope, and concise task (under 500 characters).\nWorkers execute real work through the Assist tool suite; results are verified against the filesystem."
- **Capability:** `planning`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Decomposes and schedules parallel or sequenced autonomous Workers for sub-tasks.\nEach worker must have a distinct name, non-overlapping scope, and concise task (under 500 characters).\nWorkers execute real work through the Assist tool suite; results are verified against the filesystem.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "workers": {
      "type": "array",
      "items": {
        "type": "object"
      },
      "description": "List of distinct worker assignments. Each element is an object with:\n- name (string, required): unique worker name.\n- scope (string, required): explicit area of responsibility (module or directory). Must not overlap with other workers' scopes.\n- task (string, required): concrete task description, max 500 characters.\n- role (string, optional): e.g. \"General Engineer\", \"Systems Architect\".\n- dependencies (array of strings, optional): names of other workers in this batch that must complete first.\n- targetFiles (array of strings, optional): specific files this worker may modify. Must not overlap with other workers' target files."
    }
  },
  "required": ["workers"]
}
```

**Output (success).** None: the tool is registered but honestly
failing after validation (see Notes). No structured data.

**Notes.** Legacy's validation runs in Legacy's order, then the tool
fails: each worker needs a non-empty `task` (also read from
`description`); duplicate names are suffixed (`<name>-<n>`);
dependencies must name workers in the same batch; at least one worker
assignment is required. No worker is created or run — the tool needs
the Assist worker runtime (`WorkerScheduler` +
`WorkerPersistenceStore` + subagent execution), which Ycode's MCP host
does not have yet. See `assist-terminal-memory-planning-tools.md`
("`use_workers`").

## 95. `environment_variable_manager` — Environment Variable Manager

- **Description (verbatim):** "Inspects, checks, or updates workspace .env configuration files and environment keys."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Inspects, checks, or updates workspace .env configuration files and environment keys.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "Action: 'list_keys', 'get', 'set'."
    },
    "key": {
      "type": "string",
      "description": "Variable name when action is 'get' or 'set'."
    },
    "value": {
      "type": "string",
      "description": "Value to write when action is 'set'."
    },
    "envFilePath": {
      "type": "string",
      "description": "Optional path to .env file. Defaults to '.env'."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Plain text, no structured data: list →
`Found <n> environment keys in \`<file>\`:` plus one `- \`<key>\``
line per key; get → the `KEY=value` line; set → `` Successfully set
`<key>` in `<file>`. ``

**Notes.** `list_keys` (also `list`) lists `KEY` names from
`KEY=value` lines, skipping blanks and `#` comments; a missing file
for list is success (`No <file> file found in workspace.`), for get
it is an error. `set` replaces the first matching line or appends
`KEY=value`, then writes through `commit()`. Legacy's exact line logic
is reproduced: an empty or missing file splits to one empty line, so a
brand-new file gets a leading blank line before the new `KEY=value`
line. `envFilePath` must stay inside the workspace. See
`assist-terminal-memory-planning-tools.md`
("`environment_variable_manager`").

## 96. `clipboard_manager_tool` — Clipboard Manager

- **Description (verbatim):** "Reads text from or copies content to the macOS system clipboard (NSPasteboard)."
- **Capability:** `general`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Reads text from or copies content to the macOS system clipboard (NSPasteboard).",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "Action: 'read' (read current clipboard) or 'copy' (write content to clipboard)."
    },
    "content": {
      "type": "string",
      "description": "Text content to copy when action is 'copy'."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Plain text, no structured data: read →
`Current Clipboard Content (<n> chars):` plus the first 500 chars in
a code block (or `Clipboard is currently empty.`); copy →
`Successfully copied <n> characters to the system clipboard.`

**Notes.** macOS only (`NSPasteboard`); on any other platform the
tool fails with `<tool> is only available on macOS.` `read` also
accepts `get`; `copy` also accepts `write` / `set`. A `copy` is a
clipboard write, so the tool is `writes: true` and refused in
`readOnly` server mode. See
`assist-terminal-memory-planning-tools.md`
("`clipboard_manager_tool`").

## 97. `process_monitor_tool` — Process Monitor

- **Description (verbatim):** "Monitors active build, compiler, simulator, and child processes on macOS."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Monitors active build, compiler, simulator, and child processes on macOS.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "filter": {
      "type": "string",
      "description": "Optional process name filter (e.g. 'xcodebuild', 'swift', 'Simulator')."
    }
  },
  "required": []
}
```

**Output (success).** Plain text, no structured data: a Markdown
table `### Active Developer Processes (<n> running):` with `PID |
%CPU | %MEM | Command` rows (at most 25). No match → `No active
processes matching developer tools or filter '<filter or
Xcode/Swift>'.`

**Notes.** Runs fixed `/bin/ps -eo pid,%cpu,%mem,comm` (15 s timeout).
Without a filter it reports lines whose command contains `xcode`,
`swift`, `clang`, `simctl`, `lldb`, `git`, `xcrun`, or `Simulator`
(case-insensitive); with a filter it reports lines containing the
filter text. See `assist-terminal-memory-planning-tools.md`
("`process_monitor_tool`").

## 98. `disk_space_analyzer` — Disk Space Analyzer

- **Description (verbatim):** "Calculates disk consumption across DerivedData, project build outputs, and caches."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Calculates disk consumption across DerivedData, project build outputs, and caches.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional specific directory path to inspect. Defaults to workspace root and DerivedData."
    }
  },
  "required": []
}
```

**Output (success).** Plain text, no structured data: `### Disk Space
Analysis:` with the target scope size and the Xcode DerivedData cache
size, plus a `#### Major Directory Breakdown:` list (top 10
subdirectories by size) when the target has subdirectories.

**Notes.** Sums file sizes under the target directory (hidden files
skipped) and under `~/Library/Developer/Xcode/DerivedData`; sizes are
formatted with `ByteCountFormatter` (`.file` style). A missing
DerivedData folder sizes as zero, never an error. A `path` outside the
workspace fails with the workspace-containment error. See
`assist-terminal-memory-planning-tools.md`
("`disk_space_analyzer`").

## 99. `system_notification_tool` — Post macOS System Notification

- **Description (verbatim):** "Posts a genuine macOS system notification banner or alert with custom title, subtitle, sound, and message body for build status, task completions, or developer alerts."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true, openWorld: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Posts a genuine macOS system notification banner or alert with custom title, subtitle, sound, and message body for build status, task completions, or developer alerts.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "title": {
      "type": "string",
      "description": "Notification title. Defaults to \"Ycode Assist\"."
    },
    "subtitle": {
      "type": "string",
      "description": "Notification subtitle."
    },
    "message": {
      "type": "string",
      "description": "Notification message body. Defaults to \"Task completed.\"."
    },
    "body": {
      "type": "string",
      "description": "Alias for message: notification message body."
    },
    "sound": {
      "type": "string",
      "description": "Sound name: \"default\", \"none\", or a sound file name. Defaults to \"default\"."
    },
    "critical": {
      "type": "boolean",
      "description": "Whether the notification sound is critical. Defaults to false."
    }
  },
  "required": []
}
```

**Output (success).** Plain text, no structured data: the delivery
summary. Delivery failure is an error result carrying the same summary
text.

**Notes.** Posts a genuine macOS notification
(`UNUserNotificationCenter` with an `osascript` fallback). The default
title is `"Ycode Assist"` where Legacy's is `"SwiftCode Assist"` (the
product posting the notification). `critical` requests the critical
sound; without the critical-alerts entitlement the notification still
posts, silently without the critical sound. This schema is declared in
Ycode; Legacy declares no `parametersSchema` for this tool. See
`assist-terminal-memory-planning-tools.md`
("`system_notification_tool`").

## 100. `use_system` — System Diagnostics

- **Description (verbatim):** "macOS system diagnostics and one authorized user-level configuration op. Diagnostics: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read (sysctl allowlist). Mutation: user_defaults_write (requires confirm: true; verified by read-back). Fixed-argv subprocesses only; privileged actions are refused, never escalated."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "macOS system diagnostics and one authorized user-level configuration op. Diagnostics: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read (sysctl allowlist). Mutation: user_defaults_write (requires confirm: true; verified by read-back). Fixed-argv subprocesses only; privileged actions are refused, never escalated.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "operation": {
      "type": "string",
      "description": "One of: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, user_defaults_write."
    },
    "target": {
      "type": "string",
      "description": "Operation-dependent: process name filter (process_list), interface name (network_interfaces), hostname (connectivity), sysctl name (config_read, must be on the allowlist), defaults domain (user_defaults_write)."
    },
    "parameters": {
      "type": "object",
      "properties": {
        "port": {
          "type": "integer",
          "description": "TCP port for connectivity (1-65535, required)."
        },
        "timeoutSeconds": {
          "type": "number",
          "description": "Timeout for connectivity in seconds (default 5, max 30)."
        },
        "limit": {
          "type": "integer",
          "description": "Max rows for process_list (default 50, capped at 200)."
        },
        "filter": {
          "type": "string",
          "description": "Name filter for process_list (also accepted via target)."
        },
        "predicate": {
          "type": "string",
          "description": "NSPredicate string for system_log (e.g. 'process == \"kernel\"')."
        },
        "minutes": {
          "type": "integer",
          "description": "Lookback window for system_log in minutes (1-60, default 15)."
        },
        "domain": {
          "type": "string",
          "description": "Defaults domain for user_defaults_write (also accepted via target)."
        },
        "key": {
          "type": "string",
          "description": "Defaults key for user_defaults_write (required)."
        },
        "value": {
          "description": "Value for user_defaults_write (string, number, or boolean; required)."
        }
      },
      "required": []
    },
    "confirm": {
      "type": "boolean",
      "description": "Required true for user_defaults_write; the model must explicitly confirm the mutation."
    }
  },
  "required": ["operation"]
}
```

**Output (success).** Structured data keys vary by operation (every
operation returns `operation` plus its own keys; see Notes). The
summary is the operation's report text.

| Key | Value |
|---|---|
| `operation` | The operation actually run. |
| `content` | The operation's report text (all operations). |
| `osVersion` / `osBuild` / `arch` / `hostname` / `cpuCount` / `physicalMemoryBytes` / `uptimeSeconds` | `system_info` only. |
| `tools` | `dev_environment` only (`"xcodebuild,swift,xcrun"`). |
| `filter` / `count` / `truncated` | `process_list` only. |
| `interface` / `truncated` | `network_interfaces` only. |
| `count` / `truncated` | `listening_sockets`, `system_log`, `service_status`. |
| `host` / `port` / `reachable` / `latencyMs` | `connectivity` only. |
| `path` / `totalBytes` / `availableBytes` / `usedBytes` / `usedPercent` | `disk_info` only. |
| `predicate` / `minutes` | `system_log` only. |
| `sysctlName` / `value` | `config_read` only. |
| `domain` / `key` / `previousValue` / `newValue` / `verified` | `user_defaults_write` only. |

**Notes.** Diagnostics: `system_info` (real OS, `uname -m -r`),
`dev_environment` (probes `xcodebuild -version`, `swift --version`,
`xcrun --find swift`; a missing tool is reported, never fabricated),
`process_list` (`/bin/ps`, limit clamped 1…200), `network_interfaces`
(`/sbin/ifconfig`, macOS only), `listening_sockets` (`lsof` resolved
on `PATH`; empty output is success), `connectivity` (TCP connect +
poll, port required 1–65535, timeout clamped 1…30 s), `disk_info`
(volume `/`), `system_log` (`/usr/bin/log`, macOS only, minutes
clamped 1…60), `service_status` (`/bin/launchctl list`, macOS only),
`config_read` (sysctl allowlist only: `kern.ostype`, `kern.osrelease`,
`kern.osrevision`, `kern.version`, `kern.hostname`, `kern.maxproc`,
`hw.model`, `hw.machine`, `hw.ncpu`, `hw.physicalmem`, `hw.memsize`,
`hw.memsize_usable`, `hw.cpufrequency`,
`machdep.cpu.brand_string`; macOS only). Mutation:
`user_defaults_write` needs `confirm: true` **and** the approval gate,
runs `/usr/bin/defaults write`, and verifies by read-back; the domain
must match `^[A-Za-z0-9.-]+$` (no `..`), `NSGlobalDomain` is blocked,
the key must match `^[A-Za-z0-9._-]+$`, and the value must be a string,
number, or boolean. `parameters.value` is declared without a JSON type
(Legacy declares it a string but accepts bool / number). See
`assist-terminal-memory-planning-tools.md` ("`use_system`").

## 101. `take_screenshot` — take_screenshot

- **Description (verbatim):** "Captures the user's entire screen or a user-selected screen region, produces a valid PNG image, and makes the resulting image available to the active AI model for visual analysis."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `screenRecording`. **Read-only:** yes (Legacy). **MCP annotations:** `readOnly: false, idempotent: true, openWorld: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Captures the user's entire screen or a user-selected screen region, produces a valid PNG image, and makes the resulting image available to the active AI model for visual analysis.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "capture_mode": {
      "type": "string",
      "description": "Screen capture mode: 'fullscreen' for entire screen, or 'region' for an interactive user-selected region. Defaults to 'fullscreen'."
    },
    "display_id": {
      "type": "integer",
      "description": "Optional display identifier when multiple displays are connected."
    },
    "include_cursor": {
      "type": "boolean",
      "description": "Whether to include the mouse cursor in the capture. Defaults to true."
    },
    "image_format": {
      "type": "string",
      "description": "Image output format. Must be 'png'. Defaults to 'png'."
    },
    "purpose": {
      "type": "string",
      "description": "Optional explanation of what Assist needs to inspect in the screenshot."
    }
  },
  "required": []
}
```

**Output (success).** Message: `Captured fullscreen screenshot
(<w>×<h> px) on display <id>. Artifact saved to '<rel>'.` The result
carries an image block, the message, and the JSON below. Structured
data keys:

| Key | Value |
|---|---|
| `path` | The artifact's workspace-relative path. |
| `width` / `height` | Capture dimensions in pixels. |
| `display_id` | The display captured. |
| `capture_mode` | Always `"fullscreen"`. |
| `artifact_id` | The artifact index entry's UUID. |
| `base64` | The full PNG, base64-encoded (a large payload). |
| `format` | Always `"png"`. |
| `size_bytes` | PNG byte count. |
| `purpose` | Only when given. |

**Notes.** Fullscreen capture only, via ScreenCaptureKit (macOS
only). The PNG is saved as a Wave 1 artifact
(`.assist_temp/artifacts/screenshot_<epoch>_<8 hex>.png`, plus the
`image.png` latest-copy mirror) under a single approval. `capture_mode
"region"` fails naming the missing interactive region-selection
overlay. Legacy risk is `safeRead`, but the port is `writes: true`
because it saves a file — the one deliberate annotation deviation in
this wave (§86). See `assist-terminal-memory-planning-tools.md`
("`take_screenshot`").

## 102. `take_screenrecord` — take_screenrecord

- **Description (verbatim):** "Records the screen of a specifically identified application, subject to macOS privacy permissions and recording restrictions, and produces a usable recording artifact."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `screenRecording`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true, openWorld: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Records the screen of a specifically identified application, subject to macOS privacy permissions and recording restrictions, and produces a usable recording artifact.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "app_identifier": {
      "type": "string",
      "description": "Target application bundle identifier (e.g. 'com.apple.dt.Xcode') or application name (e.g. 'Xcode'). Preferred: bundle identifier."
    },
    "recording_duration": {
      "type": "number",
      "description": "Requested recording duration in seconds (between 1 and 60). Defaults to 10 seconds."
    },
    "capture_mode": {
      "type": "string",
      "description": "Capture scope: 'window' for the application's primary on-screen window, or 'application_display'. Defaults to 'window'."
    },
    "include_audio": {
      "type": "boolean",
      "description": "Whether to capture application audio when supported. Defaults to false."
    },
    "output_format": {
      "type": "string",
      "description": "Video container format. Supported: 'mov', 'mp4'. Defaults to 'mov'."
    },
    "purpose": {
      "type": "string",
      "description": "Optional natural-language explanation of why Assist is recording this application."
    }
  },
  "required": ["app_identifier"]
}
```

**Output (success).** None: the tool is registered but honestly
failing (see Notes). No structured data.

**Notes.** The tool needs a ScreenCaptureKit stream-recording engine
(`SCStream` + video writer), which Ycode's MCP host does not have yet.
A missing `app_identifier` and an out-of-range duration (1–60 s) fail
first with Legacy-exact messages; otherwise the failure names the
missing engine and the Screen Recording permission requirement. No
recording is made in any case. See
`assist-terminal-memory-planning-tools.md`
("`take_screenrecord`").

## 103. `use_app` — use_app

- **Description (verbatim):** "Enables Assist to operate native macOS applications through real Accessibility APIs, CoreGraphics synthetic events, ScreenCaptureKit visual perception, and window management."
- **Capability:** `systemExecution`. **Risk:** `safeMutation`. **Required permission:** `accessibility`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true, openWorld: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Enables Assist to operate native macOS applications through real Accessibility APIs, CoreGraphics synthetic events, ScreenCaptureKit visual perception, and window management.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "app_identifier": {
      "type": "string",
      "description": "Target application bundle identifier (e.g. 'com.apple.finder'), app name (e.g. 'Finder', 'Calculator'), process ID, or session ID."
    },
    "action": {
      "type": "string",
      "description": "Action to perform: 'launch', 'activate', 'list_applications', 'inspect_application', 'list_windows', 'select_window', 'close_application', 'inspect_ui', 'get_accessibility_tree', 'get_focused_element', 'take_screenshot', 'inspect_window', 'click', 'double_click', 'right_click', 'move_pointer', 'drag', 'scroll', 'type_text', 'press_key', 'press_shortcut', 'select_all', 'copy', 'paste', 'activate_element', 'set_element_value', 'select_menu', 'wait_for_element', 'wait_for_window', 'verify'."
    },
    "target": {
      "type": "string",
      "description": "Target UI element session ID (e.g. 'elem_1'), title, accessibility identifier, label, or menu path (e.g. 'File > Save')."
    },
    "value": {
      "type": "string",
      "description": "Text input to type, shortcut name (e.g. 'Cmd+S'), key name (e.g. 'Return'), or expected value for verification."
    },
    "coordinates": {
      "type": "object",
      "properties": {
        "x": {
          "type": "number",
          "description": "X coordinate."
        },
        "y": {
          "type": "number",
          "description": "Y coordinate."
        },
        "coordinate_space": {
          "type": "string",
          "description": "Coordinate space: 'screen', 'window', or 'screenshot_pixel'. Defaults to 'screen'."
        }
      },
      "required": []
    },
    "drag_destination": {
      "type": "object",
      "properties": {
        "x": {
          "type": "number",
          "description": "Destination X coordinate."
        },
        "y": {
          "type": "number",
          "description": "Destination Y coordinate."
        }
      },
      "required": []
    },
    "scroll_delta": {
      "type": "object",
      "properties": {
        "dx": {
          "type": "integer",
          "description": "Horizontal scroll delta in pixels."
        },
        "dy": {
          "type": "integer",
          "description": "Vertical scroll delta in pixels."
        }
      },
      "required": []
    },
    "window_id": {
      "type": "string",
      "description": "Optional target window identifier (e.g. 'window_1')."
    },
    "modifiers": {
      "type": "array",
      "items": {
        "type": "string"
      },
      "description": "Optional key modifier list (e.g. ['command', 'shift'])."
    },
    "timeout": {
      "type": "number",
      "description": "Timeout in seconds for wait operations (1-60, default 5)."
    },
    "verification": {
      "type": "boolean",
      "description": "Whether to re-inspect and verify resulting application state after action. Defaults to true."
    },
    "confirm": {
      "type": "boolean",
      "description": "Explicit user authorization required for consequential actions such as 'close_application'."
    },
    "purpose": {
      "type": "string",
      "description": "Natural-language explanation of the intended workflow or interaction purpose."
    }
  },
  "required": ["app_identifier", "action"]
}
```

**Output (success).** Structured data keys vary by action (see
Notes); the summary is the action's report text. Implemented actions
return `action` plus: `list_applications` → `count`, `status`;
`launch` / `activate` → `app_identifier`, `app_name`, `pid`,
`window_count`, `status: "active"`; `close_application` →
`app_identifier`, `app_name`, `status: "terminated"`;
`list_windows` → `app_identifier`, `app_name`, `window_count`,
`status` (when windows exist).

**Notes.** macOS only. Implemented on public macOS APIs:
`list_applications` (running apps only — Legacy lists installed apps
too; at most 35 lines), `launch` / `activate`, `close_application`
(requires `confirm: true` **and** the approval gate),
`list_windows` (CoreGraphics window list). Every Accessibility /
interaction action (`inspect_ui`, `get_accessibility_tree`,
`get_focused_element`, `inspect_application`, `inspect_window`,
`take_screenshot`, `select_window`, `click`, `double_click`,
`right_click`, `move_pointer`, `drag`, `scroll`, `type_text`,
`set_value`, `press_key`, `press_shortcut`, `select_all`, `copy`,
`paste`, `activate_element`, `set_element_value`, `select_menu`,
`wait_for_element`, `wait_for_window`, `verify`,
`verify_element_state`) fails per-action naming the missing macOS
Accessibility / app-interaction engine (`AssistAppInteractionEngine`);
no application is operated. See
`assist-terminal-memory-planning-tools.md` ("`use_app`").

## 104. Summary: capability / risk / permission / writes (Wave 4 terminal)

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `use_terminal` | systemExecution | execution | terminalExecution | **no** | **true** |
| `task_runner` | systemExecution | execution | none | **no** | **true** |
| `env_capture_logs` | diagnostics | safeRead | none | yes | false |
| `env_info` | diagnostics | safeRead | none | yes | false |
| `use_mcp` | general | externalSideEffect | none | **no** | **true** |
| `use_extension` | general | safeMutation | fileSystem | **no** | **true** |
| `use_composio` | general | externalSideEffect | none | **no** | **true** |
| `use_workers` | planning | safeMutation | fileSystem | **no** | **true** |
| `environment_variable_manager` | diagnostics | safeMutation | fileSystem | **no** | **true** |
| `clipboard_manager_tool` | general | safeMutation | fileSystem | **no** | **true** |
| `process_monitor_tool` | diagnostics | safeRead | none | yes | false |
| `disk_space_analyzer` | diagnostics | safeRead | none | yes | false |
| `system_notification_tool` | diagnostics | safeRead | none | yes | false |
| `use_system` | diagnostics | safeMutation | fileSystem | **no** | **true** |
| `take_screenshot` | diagnostics | safeRead | screenRecording | yes (Legacy) | **true** |
| `take_screenrecord` | diagnostics | safeRead | screenRecording | yes | false |
| `use_app` | systemExecution | safeMutation | accessibility | **no** | **true** |

11 tools write; 6 tools read. Honestly failing, fully: `env_capture_logs`, `use_extension`, `use_composio`, `use_workers`, `take_screenrecord`. Partial: `use_mcp` (list only), `use_app` (4 of 30 actions). The one `safeRead` tool that writes is `take_screenshot` (§86, §101).

## Wave 4 — memory tools

## 105. Wave 4 memory conventions (extending §1 and §27)

- **Four stores, all per-workspace.** (A) The session memory graph:
  an in-memory `NSLock` dictionary (`YcodeMemoryGraphStore`), one graph
  per workspace root path, process-lifetime, never persisted — exactly
  like Legacy's `AssistMemoryGraph`. "Long-term" in the Legacy
  descriptions means this graph, not disk. (B) Durable user memory:
  `<workspace>/.assist_temp/memory/UserMemory.md`, Legacy's exact
  Markdown format. (C) The persistent context store:
  `<workspace>/.assist_context_store.json`, JSON `[String: String]`,
  pretty-printed with sorted keys — Legacy's exact path and writer.
  (D) Conversation context: one file per workspace,
  `<workspace>/.assist_temp/memory/conversation_context.md`, Legacy's
  exact append format.
- **Deliberate store changes.** Legacy's durable user memory is
  app-global (`~/Library/Application Support/SwiftCode/UserMemory.md`)
  and would leak one workspace's memory into another's, so it is **not**
  reused; the per-workspace file above replaces it, in the same format,
  with no SwiftCode default seed and no `enableUserMemory` gate (the
  approval path gates instead). Legacy's conversation context is one
  `<uuid>.context.md` per conversation under Application Support; the
  MCP host has no conversation identity, so one file per workspace
  replaces it. No new database layer was invented.
- **Approval gating.** The four file-writing handlers
  (`context_persistence_store` set/delete, `save_to_memory`,
  `manage_memory` add/edit/delete/clear, `conversation_context_manager`
  `update_summary`) write through `commit()` exactly like the Wave 2
  file-writing tools. The three in-memory-only tools (`mem_store`,
  `mem_clear`, `mem_context_snapshot`) register `writes: true` so the
  server-level gate still refuses them when read-only, but they call
  neither `commit()` nor `approve()`: there is no file change to
  propose, and fabricating an `MCPChange` would show the IDE reviewer
  a fake file proposal. This matches `dir_cd`'s session-state
  precedent. The read-only actions of the mixed tools
  (`context_persistence_store` get, `conversation_context_manager`
  read) request no approval, but the tools are still registered
  `writes: true`, so `MCPServer.run` refuses them in `readOnly` server
  mode — the same treatment Wave 3 gives its mixed git tools.
- **Annotations.** `safeRead` → `.read`, `writes: false`;
  `safeMutation` → `readOnly: false, idempotent: true`, `writes: true`;
  `potentiallyDestructive` (`mem_clear`) → `readOnly: false,
  destructive: true`, `writes: true`. Two behaviour-driven exceptions:
  `mem_context_snapshot` mints a fresh snapshot key on every call, so
  it is not idempotent; `conversation_context_manager`'s
  `update_summary` appends, so it is not idempotent either.
- All nine tools declare Legacy `capability: memory`. See
  `assist-terminal-memory-planning-tools.md` ("Memory tools") for
  behaviour, error cases, and the store formats.

## 106. `mem_store` — Store Memory

- **Description (verbatim):** "Stores information in the long-term memory graph."
- **Capability:** `memory`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Stores information in the long-term memory graph.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "key": {
      "type": "string",
      "description": "Memory key to store under."
    },
    "value": {
      "type": "string",
      "description": "Value to store."
    }
  },
  "required": ["key", "value"]
}
```

**Output (success).** Message: `Stored in memory: <key>`. Structured data keys:

| Key | Value |
|---|---|
| `key` | The key stored under. |

**Notes.** Stores the value under the key in the calling workspace's
session graph (store A), overwriting any existing entry. In-memory
only: the entry does not survive a server restart. Empty `key` /
`value` fail with `Missing required parameter: key` / `Missing
required parameter: value`. See
`assist-terminal-memory-planning-tools.md` ("`mem_store`").

## 107. `mem_retrieve` — Retrieve Memory

- **Description (verbatim):** "Retrieves information from the long-term memory graph."
- **Capability:** `memory`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Retrieves information from the long-term memory graph.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "key": {
      "type": "string",
      "description": "Memory key to look up."
    }
  },
  "required": ["key"]
}
```

**Output (success).** Message: `Retrieved from memory: <key>`. Structured data keys:

| Key | Value |
|---|---|
| `key` | The key looked up. |
| `value` | The stored value. |

**Notes.** Reads the calling workspace's session graph (store A). An
unknown key fails with `Key not found in memory: <key>`. See
`assist-terminal-memory-planning-tools.md` ("`mem_retrieve`").

## 108. `mem_clear` — Clear Memory

- **Description (verbatim):** "Clears all stored information in the memory graph."
- **Capability:** `memory`. **Risk:** `potentiallyDestructive`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, destructive: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Clears all stored information in the memory graph.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Message: `Memory cleared.` Structured data keys:

| Key | Value |
|---|---|
| `cleared` | Boolean, always true. |
| `entriesCleared` | How many entries the workspace's graph held (a Ycode addition; Legacy returns no data). |

**Notes.** Clears only the calling workspace's session graph (store
A). Other workspaces' graphs are untouched. No confirmation parameter:
the destructive annotation plus the `writes: true` gate is the
protection, as in Legacy (which takes no `confirm` either). See
`assist-terminal-memory-planning-tools.md` ("`mem_clear`").

## 109. `mem_context_snapshot` — Context Snapshot

- **Description (verbatim):** "Captures a snapshot of the current environment and open files for future reference."
- **Capability:** `memory`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Captures a snapshot of the current environment and open files for future reference.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Message: `Context snapshot captured`. Structured data keys:

| Key | Value |
|---|---|
| `snapshot_key` | `context_snapshot:<uuid>`, freshly minted per call. |
| `latest_snapshot` | Always `"none"`. |

**Notes.** Stores a payload in the calling workspace's session graph
(store A) under `context_snapshot:<uuid>`: three lines,
`session=<session-uuid>`, `workspace=<workspace-root-path>`,
`latest_snapshot=none`. The session UUID is minted once per workspace
per process. `latest_snapshot` is always `"none"`: Legacy reads it
from `AssistSnapshotFunctions.listSnapshots()`, and Ycode has no
snapshot store, so there is never a latest snapshot to name. The
stored marker is a real graph entry, retrievable with `mem_retrieve`;
nothing is faked. Open files are not captured: the MCP host has no
open-file list. Not idempotent (fresh key per call). See
`assist-terminal-memory-planning-tools.md`
("`mem_context_snapshot`").

## 110. `context_persistence_store` — Persistent Context Store

- **Description (verbatim):** "Stores and retrieves persistent key-value context across Assist sessions."
- **Capability:** `memory`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Stores and retrieves persistent key-value context across Assist sessions.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "key": {
      "type": "string",
      "description": "Context key."
    },
    "action": {
      "type": "string",
      "description": "One of 'set', 'get', or 'delete'. Default: \"get\"."
    },
    "value": {
      "type": "string",
      "description": "Value to store. Required when action is 'set'."
    }
  },
  "required": ["key"]
}
```

**Output (success).** Set → `Stored context for key <key>`; delete →
`Deleted key <key>`; get (and any other action string — Legacy's
`default` case) → `Retrieved context for key <key>`. Structured data
keys:

| Key | Value |
|---|---|
| `key` | The context key. |
| `action` | The action actually performed: `set`, `delete`, or `get`. |
| `value` | The stored value (`""` when the key is absent on get, `""` on delete). |

**Notes.** Reads and writes `<workspace>/.assist_context_store.json`
(store C), re-reading the file on every call like Legacy. `action` is
lowercased; absent defaults to `get`. `set` and `delete` write through
`commit()`; a delete of an absent key is a no-op that still rewrites
the file, like Legacy. Errors: `Missing key` (absent or empty key);
`Missing value` (`set` without a value). See
`assist-terminal-memory-planning-tools.md`
("`context_persistence_store`").

## 111. `save_to_memory` — Save to Memory

- **Description (verbatim):** "Saves high-value architectural decisions, preferences, guidelines, and context to UserMemory.md."
- **Capability:** `memory`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Saves high-value architectural decisions, preferences, guidelines, and context to UserMemory.md.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "key": {
      "type": "string",
      "description": "Short, descriptive unique key (e.g. ArchitectureStyle, DesignTokens, ConcurrencyRule)."
    },
    "value": {
      "type": "string",
      "description": "The content, guideline, or instruction to remember permanently."
    },
    "category": {
      "type": "string",
      "description": "Category name (e.g. Preferences, Architecture, Decisions, Rules, Project Context). Defaults to General."
    }
  },
  "required": ["key", "value"]
}
```

**Output (success).** Message: `Saved to memory [<category>]:
**<key>** = <value>` followed by `Persisted to
.assist_temp/memory/UserMemory.md`. Structured data keys:

| Key | Value |
|---|---|
| `key` | The key saved. |
| `value` | The value saved. |
| `category` | The category (default `General`). |

**Notes.** Upserts the entry in the workspace's `UserMemory.md`
(store B) — key and value trimmed, category trimmed and defaulting to
`General` when absent or blank, key match case-insensitive, timestamp
refreshed on update. The write goes through `commit()`. The file is
created (header only, no seed) when it does not exist yet. The success
message names the real workspace file instead of Legacy's app-global
path — the one deliberate wording change in this family. Legacy's
failure branch ("Memory recording is currently disabled in Assist
Settings, or storage failed.") has no Ycode equivalent: there is no
enable/disable setting. See
`assist-terminal-memory-planning-tools.md` ("`save_to_memory`").

## 112. `view_memory` — View Memory

- **Description (verbatim):** "Reads and retrieves stored context, preferences, and architectural decisions from UserMemory.md."
- **Capability:** `memory`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reads and retrieves stored context, preferences, and architectural decisions from UserMemory.md.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "query": {
      "type": "string",
      "description": "Optional search query to filter memory entries by key or content."
    },
    "category": {
      "type": "string",
      "description": "Optional category filter (e.g. Preferences, Architecture, Rules)."
    }
  },
  "required": []
}
```

**Output (success).** Entries found → `### Active User Memories (<n>
items):` plus one `- [<category>] **<key>**: <value>` line per entry.
No entries and an empty/missing file → `No memories are currently
stored in UserMemory.md.` No entries but a non-empty file → `No memory
items matched the filter. Full UserMemory.md:\n\n<full document>`.
Structured data keys:

| Key | Value |
|---|---|
| `entries` | Array of `key` / `value` / `category` / `updatedAt` (ISO-8601) objects. |
| `count` | Number of entries after filtering. |
| `report` | The same text as the message. |

**Notes.** Reads the workspace's `UserMemory.md` (store B) and filters
by category (case-insensitive), then by query (case-insensitive
substring of key or value). After a `manage_memory` clear the file
holds only the header, so `view_memory` returns the full-document
fallback, not "No memories" — Legacy's actual behaviour. See
`assist-terminal-memory-planning-tools.md` ("`view_memory`").

## 113. `manage_memory` — Manage Memory

- **Description (verbatim):** "Allows Assist to edit, delete, or reorganize memories in UserMemory.md."
- **Capability:** `memory`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Allows Assist to edit, delete, or reorganize memories in UserMemory.md.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "Action to perform: 'add', 'edit', 'delete', or 'clear'."
    },
    "key": {
      "type": "string",
      "description": "The memory key to add, edit, or delete."
    },
    "value": {
      "type": "string",
      "description": "The new value when adding or editing a memory."
    },
    "category": {
      "type": "string",
      "description": "Category name when adding or editing."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Add/edit → `Memory '<key>' successfully updated
in UserMemory.md.`; delete → `Memory entry '<key>' deleted from
UserMemory.md.`; clear → `All memories cleared from UserMemory.md.`
Structured data keys:

| Key | Value |
|---|---|
| `action` | The action performed, lowercased. |
| `key` | The key acted on (`""` on clear). |
| `category` | The category (`""` on delete/clear). |

**Notes.** `add` / `edit` (also `save`) upsert like
`save_to_memory`; `delete` (also `remove`) removes the entry;
`clear` replaces the file with the header only. Every branch writes
through `commit()`. Errors: `Missing required parameter: action
('add', 'edit', 'delete', 'clear')`; `Actions 'add' and 'edit'
require both 'key' and 'value.'`; `Action 'delete' requires 'key.'`;
`Memory entry '<key>' was not found in UserMemory.md.`; `Unknown
action '<action>'. Supported actions: add, edit, delete, clear.` See
`assist-terminal-memory-planning-tools.md` ("`manage_memory`").

## 114. `conversation_context_manager` — Conversation Context Manager

- **Description (verbatim):** "Reads, updates, or checks the active conversation's dedicated context file (<conversation_id>.context.md)."
- **Capability:** `memory`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Reads, updates, or checks the active conversation's dedicated context file (<conversation_id>.context.md).",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "Action to perform: 'read' or 'update_summary'."
    },
    "notes": {
      "type": "string",
      "description": "Updated notes or context to append when action is 'update_summary'."
    }
  },
  "required": ["action"]
}
```

**Output (success).** Read with a file → `Conversation
Context:\n\n<file>`; read without a file → `No custom context file
found yet for the active conversation.`; update → `Successfully
updated conversation context file at: <absolute path>`. Structured
data keys:

| Key | Value |
|---|---|
| `action` | The action performed (`"read"` or `"update_summary"`). |
| `context` | The file text on read (`""` otherwise). |
| `path` | The absolute file path on update (`""` otherwise). |

**Notes.** `read` (also `view`) returns the workspace's conversation
context file (store D); `update_summary` (also `update`, `append`)
appends `\n### Additional Model Context (Updated <ISO-8601>):\n
<notes>\n` through `commit()`. The file is created with the `#
Conversation Context` header when it does not exist. Not idempotent
(the update appends). The description names Legacy's
`<conversation_id>.context.md` file; the port uses one file per
workspace (§105). See `assist-terminal-memory-planning-tools.md`
("`conversation_context_manager`").

## 115. Summary: capability / risk / permission / writes (Wave 4 memory)

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `mem_store` | memory | safeMutation | fileSystem | **no** | **true** |
| `mem_retrieve` | memory | safeRead | none | yes | false |
| `mem_clear` | memory | potentiallyDestructive | fileSystem | **no** | **true** |
| `mem_context_snapshot` | memory | safeMutation | fileSystem | **no** | **true** |
| `context_persistence_store` | memory | safeMutation | fileSystem | **no** | **true** |
| `save_to_memory` | memory | safeMutation | fileSystem | **no** | **true** |
| `view_memory` | memory | safeRead | none | yes | false |
| `manage_memory` | memory | safeMutation | fileSystem | **no** | **true** |
| `conversation_context_manager` | memory | safeMutation | fileSystem | **no** | **true** |

7 tools write; 2 tools read. The one `potentiallyDestructive` tool is
`mem_clear`; `mem_context_snapshot` and `conversation_context_manager`
are the two non-idempotent mutations. All 9 are implemented for real —
none honestly failing, none BLOCKED.

## Wave 4 — planning tools

## 116. Wave 4 planning conventions (extending §1 and §27)

- **Plans are produced, never executed.** No tool in this family runs a
  plan, invokes another tool, or spawns workers. Execution stays with
  the caller, through the normal approval gate. There is no Autopilot
  anywhere in this family: Legacy's `ExecutionMode` (`"Plan"` /
  `"Autopilot"`) survives only as a label on the plan document, and it
  never changes any gating.
- **Plan storage is in-memory.** `intel_plan_task` /
  `intel_breakdown_task` store plans in a process-wide in-memory store
  (`PlanningPlanStore`, keys `plan:<uuid>` /
  `plan_breakdown:<uuid>`). Legacy stores them in the session's
  `AssistContext.memory`; Ycode's MCP host has no session memory store.
  Plan IDs are UUIDs, so plans from different workspaces cannot
  collide; plans do not survive a server restart.
- **Path resolution** uses the session-aware `resolveFileReadingPath`
  (plain relative paths resolve against the `dir_cd` working directory;
  `..` that stays inside the workspace is allowed; no path may escape
  the workspace), the same resolver the file tools use.
  `execution_plan`'s own repository inspection is deliberately
  separate: it enumerates the workspace root directly (never the
  session working directory), as Legacy does.
- **Approval gating.** The two writing handlers (`execution_plan`,
  which writes `agent_notes.md`, and `intel_generate_tests`, which
  writes the generated test file) gate **before** touching disk,
  through `commit()` — exactly like the Wave 2 file-writing tools.
- **Legacy parameter-name aliases are NOT supported.** Ycode's argument
  validation rejects unknown arguments before the handler runs. Legacy
  registry aliases (`plan_askuser` / `plan_ask_user` / `ask_user` →
  `plan-AskUser`, `task_complete` / `task_completion` →
  `report_to_user`) live in `MCPServer.toolAliases`.
- **`plan-AskUser` keeps its hyphenated ID** — the documented
  intentional exception to snake_case (Legacy
  `Tools/validate_tools.py`). See
  `assist-terminal-memory-planning-tools.md` ("Planning tools") for
  behaviour, the plan-file format, error cases, and safety rules.

## 117. `execution_plan` — Generate Execution Plan

- **Description (verbatim):** "Analyzes the actual repository state, reads relevant files, discovers instructions and skills, and generates a task-specific Execution Plan. This tool MUST be called before any codebase modification. The plan is written to agent_notes.md and contains objective, findings, steps, dependencies, verification requirements, and completion criteria — all grounded in actual repository state."
- **Capability:** `planning`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Analyzes the actual repository state, reads relevant files, discovers instructions and skills, and generates a task-specific Execution Plan. This tool MUST be called before any codebase modification. The plan is written to agent_notes.md and contains objective, findings, steps, dependencies, verification requirements, and completion criteria — all grounded in actual repository state.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "objective": {
      "type": "string",
      "description": "The user's task objective."
    },
    "mode": {
      "type": "string",
      "description": "Execution mode: 'plan' or 'autopilot'."
    },
    "relevantFiles": {
      "type": "array",
      "items": {
        "type": "string"
      },
      "description": "Optional list of file paths already known to be relevant."
    }
  },
  "required": ["objective", "mode"]
}
```

**Output (success).** Message: `Execution Plan generated for:
<objective>\nMode: <mode>\nFiles inspected: <n> total, <m> Swift\n
Relevant files identified: <n>\nExecution steps: <n>\nWorkers needed:
<n>\nPlan written to: agent_notes.md`. Structured data keys:

| Key | Value |
|---|---|
| `planFile` | Always `"agent_notes.md"`. |
| `stepCount` | Number of execution steps. |
| `relevantFileCount` | Number of relevant files identified. |
| `workerCount` | Number of worker assignments. |
| `mode` | The canonical mode string. |

**Notes.** Inspects the actual repository state — file tree, build
configuration, `AGENTS.md` / instruction files, workspace skills —
identifies relevant files by keyword match against the objective
(Legacy's keyword match also matches directories by name, e.g.
`Sources/Greeter`, reproduced as-is), reads the relevant files, builds
the plan, renders it as Markdown, and writes it to `agent_notes.md`
at the workspace root through `commit()`. The mode is accepted
case-insensitively: Legacy's schema documents lowercase `"plan"` /
`"autopilot"` but its `ExecutionMode(rawValue:)` init only matches the
capitalised `"Plan"` / `"Autopilot"`, so a literal `"plan"` silently
became Autopilot; the port honours the documented values. The mode
only labels the plan document. There is no "Plan Generation
Instructions" section: Legacy renders it only when the instruction
text is non-empty, and Ycode has no `WriteExecutionPlan.md` bundle
resource to load it from. Worker assignments appear only when more
than 8 relevant files are found. A refused write fails instead of
writing: Legacy writes the file directly and still returns success
when the write fails. See
`assist-terminal-memory-planning-tools.md` ("`execution_plan`",
"Plan-file format").

## 118. `intel_plan_task` — Plan Task

- **Description (verbatim):** "Generates a high-level execution plan for a complex task."
- **Capability:** `planning`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Generates a high-level execution plan for a complex task.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "task": {
      "type": "string",
      "description": "Natural-language description of the task to plan."
    }
  },
  "required": ["task"]
}
```

**Output (success).** Message: `Plan generated for task: <task>`. Structured data keys:

| Key | Value |
|---|---|
| `planId` | Fresh UUID. |
| `steps` | The numbered steps, newline-joined. |

**Notes.** Splits the task text on `,`, `.`, `;`, newlines into clauses
and numbers them as steps; an empty task (no clauses) yields the four
default steps (`Analyze requirements`, `Implement changes`, `Validate
with tests`, `Summarize outputs`). The plan is stored in the in-memory
plan store under the returned UUID and is retrievable by
`intel_breakdown_task`. See
`assist-terminal-memory-planning-tools.md` ("`intel_plan_task`").

## 119. `intel_breakdown_task` — Breakdown Task

- **Description (verbatim):** "Breaks down a plan into granular, actionable steps."
- **Capability:** `planning`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Breaks down a plan into granular, actionable steps.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "planId": {
      "type": "string",
      "description": "Plan identifier previously returned by intel_plan_task."
    }
  },
  "required": ["planId"]
}
```

**Output (success).** Message: `Task breakdown completed for plan
<planId>`. Structured data keys:

| Key | Value |
|---|---|
| `breakdown` | The expanded steps, newline-joined. |

**Notes.** Loads the stored plan and expands every step line into
three lines: the step itself, `Define acceptance criteria for:
<step>`, and `Implement and self-review: <step>`. The breakdown is
stored under `plan_breakdown:<planId>`. An unknown `planId` fails with
`No stored plan found for planId: <planId>`. See
`assist-terminal-memory-planning-tools.md`
("`intel_breakdown_task`").

## 120. `intel_autofix` — Auto-Fix Errors

- **Description (verbatim):** "Attempts to automatically fix detected compilation or linting errors."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Attempts to automatically fix detected compilation or linting errors.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative file or directory to auto-fix. Defaults to the workspace root. Default: \".\"."
    }
  },
  "required": []
}
```

**Output (success).** None: the tool is registered but honestly
failing (see Notes). No output schema, no structured data.

**Notes.** Legacy runs `lint_project` and then asks an OpenAI LLM
(stored API key) to rewrite the file, and Ycode's MCP host has neither
a lint engine nor an LLM provider wired for this tool. The handler
always fails with `intel_autofix needs an LLM provider and lint
diagnostics: Legacy runs lint_project and then asks an OpenAI LLM
(stored API key) to rewrite the file, and Ycode's MCP host has neither
a lint engine nor an LLM provider wired for this tool. No file was
changed; use the build tool's issues and file_edit to fix errors.` No
file is touched. (Wave 2 `code_refactor` / Wave 3 `github_repo`
precedent.) See `assist-terminal-memory-planning-tools.md`
("`intel_autofix`").

## 121. `intel_explain_code` — Explain Code

- **Description (verbatim):** "Provides a detailed explanation of the code at a path."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Provides a detailed explanation of the code at a path.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to explain."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message: `Static analysis for <path>`. Structured data keys:

| Key | Value |
|---|---|
| `explanation` | The static explanation of the file. |

**Notes.** Honest static analysis, not an LLM call. Legacy tries an
OpenAI LLM first and falls back to a one-line static summary when the
LLM fails; Ycode's MCP host has no LLM provider wired for this tool,
so the port always takes the static path — and says so in the result.
The explanation is grounded in the file itself (line count, imports,
declared types, functions); nothing is invented and no LLM output is
claimed. An unreadable file fails with `Failed to explain <path>:
<reason>`. See `assist-terminal-memory-planning-tools.md`
("`intel_explain_code`").

## 122. `intel_generate_tests` — Generate Tests

- **Description (verbatim):** "Generates unit test stubs for Swift types with proper setup and teardown."
- **Capability:** `testing`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Generates unit test stubs for Swift types with proper setup and teardown.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the source file to generate tests for."
    },
    "testPath": {
      "type": "string",
      "description": "Workspace-relative output path for the generated test file. Default: \"Tests/<SourceName>Tests.swift\"."
    }
  },
  "required": ["path"]
}
```

**Output (success).** Message: `Tests generated for <path> with <n>
test methods`. Structured data keys:

| Key | Value |
|---|---|
| `test_path` | The requested output path, as given. |
| `test_count` | Number of test methods (at least 1). |
| `types_count` | Number of types extracted. |
| `functions_count` | Number of functions extracted. |

**Notes.** Extracts types and function names from the source with
Legacy's deterministic regex, renders Legacy's verbatim XCTest stub
template (setup / teardown, one test method per type / function), and
writes it through `commit()`. The `@testable import` module is derived
from the source path (`Sources/<Module>/…`, else the source file's
parent directory name, else `App`); Legacy hardcodes `@testable import
SwiftCode`. An unreadable source file fails with `Failed generating
tests for <path>: <reason>`. See
`assist-terminal-memory-planning-tools.md`
("`intel_generate_tests`").

## 123. `plan-AskUser` — Ask User for Decision

- **Description (verbatim):** "Presents a structured question to the user during Plan mode execution. The question is rendered as a native macOS UI (PlanUserAskView) and execution suspends until the user provides an answer. The answer becomes persistent session data. This tool is ONLY available in Plan mode and is blocked at the runtime registry layer in Autopilot mode."
- **Capability:** `planning`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Presents a structured question to the user during Plan mode execution. The question is rendered as a native macOS UI (PlanUserAskView) and execution suspends until the user provides an answer. The answer becomes persistent session data. This tool is ONLY available in Plan mode and is blocked at the runtime registry layer in Autopilot mode.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "question": {
      "type": "string",
      "description": "The decision question to present to the user."
    },
    "allowsMultipleAnswers": {
      "type": "boolean",
      "description": "Whether multiple choices may be selected."
    },
    "choices": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "choice": {
            "type": "string",
            "description": "The choice text."
          },
          "assistRecommended": {
            "type": "boolean",
            "description": "Whether the assistant recommends this choice."
          }
        },
        "required": ["choice"]
      },
      "description": "Available choices for the user. Each choice must have 'choice' (string) and 'assistRecommended' (boolean) fields."
    },
    "userSpecification": {
      "type": "boolean",
      "description": "Whether the user may provide a free-form response."
    }
  },
  "required": ["question", "allowsMultipleAnswers", "choices"]
}
```

**Output (success).** Message: `Question for the user (pending —
present this question to the user; this tool does not wait for an
answer): <question>` plus a `Choices: <a> | <b> (recommended)` line
when choices exist and a `The user may also give a free-form answer.`
line when `userSpecification` is true. Structured data keys:

| Key | Value |
|---|---|
| `questionId` | Fresh UUID. |
| `question` | The question as given. |
| `status` | Always `"pending"`. |
| `allowsMultipleAnswers` | As given (default false). |
| `userSpecification` | As given (default false). |
| `choices` | The choices as presented (`choice` / `assistRecommended` each). |

**Notes.** The ID is hyphenated by design — the documented
intentional exception to snake_case (Legacy
`Tools/validate_tools.py`); `MCPServerTests` allows exactly this one
ID outside `^[a-z_]+$`. The tool returns the question as a structured
handoff payload and returns immediately — it never blocks. Legacy
presents a native macOS question UI and suspends execution for up to
300 seconds waiting for the user's answer, and is available only in
Plan mode. Ycode's MCP host is non-interactive and has no Plan /
Autopilot execution mode, so the Legacy Plan-mode-only gate is
unenforceable here and is not a failure case. The caller must present
the question to the user and feed the answer back. The description is
Legacy's verbatim (it describes the native UI and the Plan-mode
restriction); the behaviour is the handoff. Choice items declare
`choice` / `assistRecommended` properties; Legacy's items schema has
none (validation does not descend into array items, so no behaviour
change). See `assist-terminal-memory-planning-tools.md`
("`plan-AskUser`").

## 124. `report_to_user` — Report Task Completion to User

- **Description (verbatim):** "Delivers the authoritative task completion report to the user once all task work, builds, tests, and audits are fully finished. Must be called at all times when Assist finishes doing task work. Not for conversational Q&A. Cleans and renders polished Markdown."
- **Capability:** `general`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Delivers the authoritative task completion report to the user once all task work, builds, tests, and audits are fully finished. Must be called at all times when Assist finishes doing task work. Not for conversational Q&A. Cleans and renders polished Markdown.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "summary": {
      "type": "string",
      "description": "Structured, concise completion report summarizing work done, files modified, and build/test verification results. Clean Markdown formatted."
    },
    "status": {
      "type": "string",
      "description": "Task outcome status (e.g. 'completed', 'verified', 'partially_completed')."
    },
    "filesModified": {
      "type": "array",
      "items": {
        "type": "string"
      },
      "description": "List of files that were created, updated, or audited during this task execution."
    },
    "verification": {
      "type": "string",
      "description": "Build, compiler diagnostic, and automated test execution results proving correctness."
    }
  },
  "required": ["summary"]
}
```

**Output (success).** The rendered report is the message. Structured data keys:

| Key | Value |
|---|---|
| `status` | The outcome status (default `"completed"`). |
| `filesCount` | Number of files listed. |
| `renderedLength` | Character count of the rendered report. |

**Notes.** Normalises and renders the report as polished Markdown
(Legacy's `normalizeAndRenderMarkdown`); appends a `**Modified
Files:**` section when files are listed and not already mentioned, and
a `**Verification:**` section when verification text is given and not
already mentioned. There is no `AssistManager` to broadcast to —
Legacy posts the rendered report as the assistant's last message; in
Ycode the tool result text **is** the report. There is no side effect.
The handler also reads `message` / `report` / `text` as fallbacks for
`summary` (not in the schema). A missing `summary` defaults to `Task
execution completed.` in the handler, but the schema still requires
it, so Ycode's argument validation rejects a missing `summary` first.
See `assist-terminal-memory-planning-tools.md`
("`report_to_user`").

## 125. Summary: capability / risk / permission / writes (Wave 4 planning)

| ID | Capability | Risk | Permission | Read-only | `writes` |
|---|---|---|---|---|---|
| `execution_plan` | planning | safeMutation | fileSystem | **no** | **true** |
| `intel_plan_task` | planning | safeRead | none | yes | false |
| `intel_breakdown_task` | planning | safeRead | none | yes | false |
| `intel_autofix` | diagnostics | safeMutation | fileSystem | **no** | **true** |
| `intel_explain_code` | diagnostics | safeRead | none | yes | false |
| `intel_generate_tests` | testing | safeMutation | fileSystem | **no** | **true** |
| `plan-AskUser` | planning | safeRead | none | yes | false |
| `report_to_user` | general | safeRead | none | yes | false |

3 tools write; 5 tools read. `intel_autofix` is registered but honestly
failing (§120); `intel_explain_code` is honest static analysis, not an
LLM call (§121); `plan-AskUser` never blocks (§123). No Autopilot
anywhere in this family.

## Wave 5 — artboards / media / engines tools

Wave 5 ports the remaining small Assist families: Artboards (8),
Simulator & devices (4), Image (7), Archive (6), Data (5), Engines (4),
Web (1) and Reverse (1) — 36 tools, taking the MCP catalogue from 138
to 172 registrations. Two of the four simulator tools already existed
as Ycode registrations and are aligned in place rather than
re-registered (§3 of the behaviour spec). The behaviour spec is
`specs/ide/assist-artboards-media-tools.md` (Part A artboards/simulator,
Part B image/archive/data, Part C engines/web/reverse).

## 126. Wave 5 artboards / simulator conventions

- Artboards live in an in-memory store on the host (`YcodeMCPHost.artboards`
  / `activeArtboardID`); there is no artboard file format yet, so they live
  and die with the server, like Legacy's `DocumentCoordinator.visualUIDocument`.
- Artboard compilation renders through `YcodePreviews` (`PreviewRenderRunner`);
  `artboard_run_app` delegates to the existing `run` tool. The Visual UI Builder
  itself, the live preview session and Apple-simulator runs are not ported.
- Simulator/device tools run `xcrun devicectl` / `simctl` as fixed-argv
  subprocesses via Wave 4's `terminalRunFixed`; mutating actions go through the
  Wave 2 approval gate. `simulator_boot` and `simulator_list` are aligned in
  place in `YcodeTools+Run.swift` (§3 of the behaviour spec) — Ycode's Ycode
  Simulator behaviour is unchanged, and the Legacy `simctl` behaviour is added.

## 127. Wave 5 image / archive / data conventions

- Image tools use the pure-Foundation header parser (PNG/JPEG/GIF/BMP/WebP/TIFF)
  on both platforms; the AppKit/ImageIO paths are macOS-only behind `canImport`
  guards and fail honestly on Linux with the exact macOS-only message.
- Archive tools run system commands as fixed-argv subprocesses (`ditto` on macOS,
  `zip`/`unzip`/`tar`/`gzip` elsewhere), 120 s timeout; no ZIPFoundation
  dependency was added. Plist conversion uses `PropertyListSerialization`, not `plutil`.
- YAML tools port Legacy's own heuristic verbatim — it is not a full YAML parser.
  `json_validate` vs `json_validator_tool` are kept as separate tools with their
  distinct Legacy behaviour (fragments, parameters, messages).
- Validate-only tools that can write are `writes: true`, per the Wave 2 precedent
  (`json_validate`, `json_validator_tool`, `yaml_validate`).

## 128. Wave 5 engines / web / reverse conventions

- Engines port Legacy's exact logic where it runs locally with no provider account
  (`code_mutation_engine`, `patch_application_engine`); `dependency_resolution_engine`
  runs `xcodebuild -resolvePackageDependencies` and is macOS-only;
  `external_resource_gateway` is HTTPS-only with a JSON body.
- `fetch_documentation` is the full Legacy pipeline (DocC JSON first, HTML fallback,
  24 h in-memory cache, 20,000-char cap). `reverse_analyze` is honestly failing:
  it runs Legacy's validation chain, then fails naming the missing Node REA bridge.
- The patch engine reports Legacy's naive line diff, not a Myers unified diff —
  Ycode has no Myers engine yet (same gap as Wave 2's `code_replace`).

## 129. `artboard_compile` — Compile Artboard Preview

- **Description (verbatim):** "Triggers compilation and preview generation of a custom artboard or the active SwiftUI file."
- **Capability:** `compilation`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Triggers compilation and preview generation of a custom artboard or the active SwiftUI file.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "identifier": {
      "type": "string",
      "description": "Optional artboard UUID or name to compile. If omitted, compiles active document/artboard."
    },
    "targetView": {
      "type": "string",
      "description": "Optional name of the SwiftUI View or #Preview target to compile."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `status`, `preview_target`.
Message: `Artboard compiled successfully.\nHosted View: Ready`.

**Notes.** Renders through `YcodePreviews` (`PreviewRenderRunner`) and returns the PNG as an image block. An artboard with no custom source fails: the MCP host has no active document for Legacy's fallback. Approval is requested before compiling. See `assist-artboards-media-tools.md` (Part A, "`artboard_compile`").

## 130. `artboard_create` — Create Artboard

- **Description (verbatim):** "Creates a new artboard in the Visual UI Builder with custom SwiftUI code or standard component layout."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a new artboard in the Visual UI Builder with custom SwiftUI code or standard component layout.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "name": {
      "type": "string",
      "description": "Name of the new artboard (e.g., 'SettingsView', 'ProfileCanvas')."
    },
    "deviceFrame": {
      "type": "string",
      "description": "Target device simulator frame (e.g., 'iPhone 16 Pro', 'iPad Pro'). Defaults to 'iPhone 16 Pro'."
    },
    "sourceCode": {
      "type": "string",
      "description": "Optional custom SwiftUI source code with #Preview to render in this artboard."
    },
    "appearance": {
      "type": "string",
      "description": "Color appearance: 'System', 'Light', or 'Dark'. Defaults to 'System'."
    },
    "isPortrait": {
      "type": "boolean",
      "description": "Orientation: true for portrait, false for landscape. Defaults to true."
    }
  },
  "required": [
    "name"
  ]
}
```

**Output (success).** Structured data keys: `id`, `name`, `deviceFrame`.
Message: `Successfully created artboard '<name>' (ID: <artboard.id.uuidString>) with frame '<deviceFrame>'.`.

**Notes.** Creates the record with Legacy's defaults (`deviceFrame` `iPhone 16 Pro`, `appearance` `System`, `isPortrait` true), root node `vStack` named `"<name> Root"`, and makes it the active artboard. Duplicate names are allowed, as in Legacy; `appearance` is stored as given. Approval is requested before creating. See `assist-artboards-media-tools.md` (Part A, "`artboard_create`").

## 131. `artboard_delete` — Delete Artboard

- **Description (verbatim):** "Deletes an artboard from the Visual UI Builder canvas by identifier or name."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Deletes an artboard from the Visual UI Builder canvas by identifier or name.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "identifier": {
      "type": "string",
      "description": "The UUID or name of the artboard to delete."
    }
  },
  "required": [
    "identifier"
  ]
}
```

**Output (success).** Structured data keys: `id`, `name`.
Message: `Artboard '<artboard.name>' (ID: <artboard.id.uuidString>) deleted successfully.`.

**Notes.** Deletes by identifier or name. Approval is requested before deleting. See `assist-artboards-media-tools.md` (Part A, "`artboard_delete`").

## 132. `artboard_get` — Get Artboard Details

- **Description (verbatim):** "Retrieves full configuration, component tree hierarchy, and custom SwiftUI source code for a specified artboard."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Retrieves full configuration, component tree hierarchy, and custom SwiftUI source code for a specified artboard.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "identifier": {
      "type": "string",
      "description": "The name or UUID of the artboard to inspect. If omitted, inspects the active artboard."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `id`, `name`, `deviceFrame`, `hasCustomSource`.

**Notes.** Reads the in-memory artboard record. There is no artboard file format yet, so artboards live and die with the server, like Legacy's `DocumentCoordinator.visualUIDocument`. See `assist-artboards-media-tools.md` (Part A, "`artboard_get`").

## 133. `artboard_list` — List Artboards

- **Description (verbatim):** "Lists all artboards in the active Visual UI Builder workspace, including IDs, device frames, appearance, and component counts."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lists all artboards in the active Visual UI Builder workspace, including IDs, device frames, appearance, and component counts.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `artboard_count`, `active_artboard_id`, `artboards`.
Message: `No artboards currently configured in workspace.`.

**Notes.** Lists the in-memory artboard records of the session. See `assist-artboards-media-tools.md` (Part A, "`artboard_list`").

## 134. `artboard_run_app` — Run Full App

- **Description (verbatim):** "Builds the active project and runs it directly inside an iOS/macOS simulator, reporting logs and execution status."
- **Capability:** `compilation`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Builds the active project and runs it directly inside an iOS/macOS simulator, reporting logs and execution status.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `runId`, `state`, `output`.

**Notes.** Delegates to the existing `run` tool. Apple-simulator runs are not ported: the Visual UI Builder itself was not ported. See `assist-artboards-media-tools.md` (Part A, "`artboard_run_app`").

## 135. `artboard_update` — Update Artboard

- **Description (verbatim):** "Updates an existing artboard's source code, device frame, appearance, or properties."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Updates an existing artboard's source code, device frame, appearance, or properties.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "identifier": {
      "type": "string",
      "description": "The UUID or name of the artboard to update. Defaults to active artboard."
    },
    "name": {
      "type": "string",
      "description": "New name for the artboard."
    },
    "deviceFrame": {
      "type": "string",
      "description": "New device simulator frame."
    },
    "sourceCode": {
      "type": "string",
      "description": "Updated custom SwiftUI source code."
    },
    "appearance": {
      "type": "string",
      "description": "'System', 'Light', or 'Dark'."
    },
    "isPortrait": {
      "type": "boolean",
      "description": "Orientation: true for portrait, false for landscape."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `id`, `name`.
Message: `Updated artboard '<artboard.name>': \(updatedFields.joined(separator: ", "))`.

**Notes.** Updates the in-memory record. Approval is requested before updating. See `assist-artboards-media-tools.md` (Part A, "`artboard_update`").

## 136. `fix_artboards` — Fix Artboards and Visual UI Builder Errors

- **Description (verbatim):** "Audits the entire Artboards, Visual UI Builder, and Preview subsystem, diagnoses simulator, destination, code signing, and syntax errors, and applies automated repairs until compilation succeeds."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Audits the entire Artboards, Visual UI Builder, and Preview subsystem, diagnoses simulator, destination, code signing, and syntax errors, and applies automated repairs until compilation succeeds.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "errorContext": {
      "type": "string",
      "description": "Optional error message or log excerpt that triggered the fix request."
    },
    "scope": {
      "type": "string",
      "description": "Optional repair scope: 'preview', 'full_app', 'all'. Defaults to 'all'."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `repaired`, `actions_count`.
Message: `\n        Fix with Assist completed audit and repairs:\n        \(actionsTaken.map { "  • \($0)" }.joined(separator: "\n"))\n\n        Result Status: \(isSuccess ? "Healthy / Resolved" : "Repairs Applied, verifying compiler logs")\n        Logs Summary:\n        \(String(log.suffix(1000)))\n        `.

**Notes.** Fix passes 3–4 are real (compile errors, missing previews). Pass 1 (realignment/booting) and pass 2 (DerivedData clean) are not ported, and the live preview session is not ported; see Part A §6. See `assist-artboards-media-tools.md` (Part A, "`fix_artboards`").

## 137. `device_list` — List Devices

- **Description (verbatim):** "Lists connected Apple devices via devicectl, falling back to xctrace. Fails clearly when no devices are found or the tooling is unavailable."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lists connected Apple devices via devicectl, falling back to xctrace. Fails clearly when no devices are found or the tooling is unavailable.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `devices`, `device_count`, `source`.
Message: `Connected devices: <devices.count>\n`; `Connected devices (via xctrace): <lines.count>\n`.

**Notes.** Runs `xcrun devicectl list devices -j` as a fixed-argv subprocess. Empty when `xcrun` is absent; fails with Legacy's clear message, never an invented device. See `assist-artboards-media-tools.md` (Part A, "`device_list`").

## 138. `simulator_boot` — Boot simulator

- **Description (verbatim):** "Starts a Ycode Simulator device without an app (as Device Hub's Start). Use simulator_screenshot to see it. With udid, boots (or shuts down) an Apple simulator via simctl instead."
- **Capability:** `systemExecution`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Starts a Ycode Simulator device without an app (as Device Hub's Start). Use simulator_screenshot to see it. With udid, boots (or shuts down) an Apple simulator via simctl instead.",
  "properties": {
    "simulator": {
      "type": "string",
      "description": "The Ycode Simulator destination's name or id (default: the first; see simulator_list)."
    },
    "udid": {
      "type": "string",
      "description": "An Apple simulator's UDID (UUID) to boot or shut down with simctl instead of the Ycode Simulator."
    },
    "action": {
      "type": "string",
      "description": "boot or shutdown (Apple-simulator path only; default boot).",
      "enum": [
        "boot",
        "shutdown"
      ]
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `simulator`, `state`.
Message: `<name> is running already.`; `<name> is starting (a warm restore takes seconds, a cold boot a minute or more); take a screenshot to see it.`.

**Notes.** ALIGNED in place (see Part A §3.2): Ycode's registration, extended with Legacy's `udid` + `action` (boot/shutdown) routing to `simctl` with Legacy's verification pass. Without a `udid` it boots the Ycode Simulator as before. See `assist-artboards-media-tools.md` (Part A, "`simulator_boot`").

## 139. `simulator_controller` — Simulator Controller

- **Description (verbatim):** "Controls Apple platform simulators (boot, shutdown, install app, open URL) via simctl."
- **Capability:** `systemExecution`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Controls Apple platform simulators (boot, shutdown, install app, open URL) via simctl.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "Action: 'boot', 'shutdown', 'install', 'launch', or 'openurl'."
    },
    "device": {
      "type": "string",
      "description": "Device name or UDID (e.g. 'booted', 'iPhone 16 Pro', or UUID)."
    },
    "appPath": {
      "type": "string",
      "description": "Path to .app bundle when action is 'install'."
    },
    "bundleId": {
      "type": "string",
      "description": "Bundle identifier when action is 'launch'."
    },
    "url": {
      "type": "string",
      "description": "URL string when action is 'openurl'."
    }
  },
  "required": [
    "action"
  ]
}
```

**Output (success).** Structured data keys: `action`, `device`, `output`.
Message: `Simulator operation '<action>' succeeded on device '<device>'. <out>`.

**Notes.** Runs `simctl` subcommands (`boot`, `shutdown`, `list`, `erase`, `openurl`, `io`, `spawn`) as fixed-argv subprocesses through the approval gate for mutating actions. See `assist-artboards-media-tools.md` (Part A, "`simulator_controller`").

## 140. `simulator_list` — List simulators

- **Description (verbatim):** "The simulators available to this IDE: the Ycode Simulator devices on the remote simulator host (device type and runtime, and whether each is running; empty when no host is set up) and the Apple simulators installed on this Mac (via simctl; empty when Xcode command line tools are absent)."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "The simulators available to this IDE: the Ycode Simulator devices on the remote simulator host (device type and runtime, and whether each is running; empty when no host is set up) and the Apple simulators installed on this Mac (via simctl; empty when Xcode command line tools are absent).",
  "properties": {},
  "required": []
}
```

**Output (success).** Structured data keys: `simulators`, `configured`, `appleSimulators`.
Message: `No Ycode Simulator host is set up.\n`.

**Notes.** ALIGNED in place (see Part A §3.1): Ycode's registration, unchanged Ycode keys, plus an `appleSimulators` array from Legacy's `simctl list devices -j` (empty when `xcrun` is absent, never an error). See `assist-artboards-media-tools.md` (Part A, "`simulator_list`").

## 141. `image_convert_format` — Convert Image Format

- **Description (verbatim):** "Converts an image file between formats (png, jpeg, tiff, bmp, gif) with optional compression quality."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Converts an image file between formats (png, jpeg, tiff, bmp, gif) with optional compression quality.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the source image."
    },
    "format": {
      "type": "string",
      "description": "Target image format: 'png', 'jpeg', 'jpg', 'tiff', 'bmp', or 'gif'."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative destination path. Defaults to source path with new extension."
    },
    "quality": {
      "type": "number",
      "description": "Compression quality for JPEG/HEIC (0.0 to 1.0). Default: 0.9."
    }
  },
  "required": [
    "path",
    "format"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `size`, `format`.
Message: `Successfully converted `<sourceRaw>` to \(formatRaw.uppercased()) at `<destRaw>` (<outputData.count> bytes).`.

**Notes.** macOS-only: needs AppKit/ImageIO. On Linux the handler fails honestly with the exact macOS-only message (Wave 4 pattern); Ycode has no image decoder/encoder to substitute. See `assist-artboards-media-tools.md` (Part B, "`image_convert_format`").

## 142. `image_decode_base64` — Decode Base64 to Image

- **Description (verbatim):** "Decodes a Base64-encoded string into an image file (PNG, JPEG, TIFF, GIF) and saves it to disk."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Decodes a Base64-encoded string into an image file (PNG, JPEG, TIFF, GIF) and saves it to disk.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "base64String": {
      "type": "string",
      "description": "The base64 encoded image string (accepts raw base64 or data:image/...;base64,... URI)."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative file path where the decoded image will be saved (e.g. Assets/icon.png)."
    }
  },
  "required": [
    "base64String",
    "destination"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `size`.
Message: `Successfully decoded base64 string and saved image to `<destRaw>` (<data.count> bytes).`.

**Notes.** Decodes Base64 to an image file through the approval gate. Format support is whatever the platform image stack provides. See `assist-artboards-media-tools.md` (Part B, "`image_decode_base64`").

## 143. `image_encode_base64` — Encode Image to Base64

- **Description (verbatim):** "Reads an image file from the workspace and encodes it into a Base64 string or Data URI."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reads an image file from the workspace and encodes it into a Base64 string or Data URI.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the image file."
    },
    "includeDataUri": {
      "type": "boolean",
      "description": "Whether to return as a full data:image/<type>;base64,... URI. Defaults to false."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `path`, `mimeType`, `byteCount`, `charCount`, `base64`.
Message: `Successfully encoded `<raw>` into Base64 (<data.count> bytes raw, <base64.count> chars base64).\nPreview: <preview>`.

**Notes.** Reads the image file and returns its Base64 encoding. No conversion is performed. See `assist-artboards-media-tools.md` (Part B, "`image_encode_base64`").

## 144. `image_extract_metadata` — Extract Image Metadata

- **Description (verbatim):** "Extracts all embedded EXIF, TIFF, GPS, and camera metadata from an image as structured JSON."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Extracts all embedded EXIF, TIFF, GPS, and camera metadata from an image as structured JSON.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the image file."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `path`, `metadataCount`, `metadataJSON`.
Message: `Extracted metadata from `<raw>` (<sanitized.count> property groups):\n<jsonString>`; `Extracted metadata from `<raw>` (<groups.count> property groups):\n<jsonString>`.

**Notes.** Returns the full ImageIO metadata dictionary on macOS and the embedded-chunk subset (PNG tEXt, JPEG EXIF APP1) on Linux, from the pure-Foundation header parser — the shapes differ per platform, stated in Part B §6. See `assist-artboards-media-tools.md` (Part B, "`image_extract_metadata`").

## 145. `image_generate_thumbnail` — Generate Image Thumbnail

- **Description (verbatim):** "Generates a scaled thumbnail image maintaining aspect ratio and writes it to disk."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Generates a scaled thumbnail image maintaining aspect ratio and writes it to disk.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the source image."
    },
    "maxPixelSize": {
      "type": "integer",
      "description": "Maximum width or height of the thumbnail in pixels (e.g. 256). Default: 256."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative path for output thumbnail. Defaults to <name>_thumb.png."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `width`, `height`, `size`.
Message: `Successfully generated <thumbnailCG.width>x<thumbnailCG.height> thumbnail for `<sourceRaw>` at `<destRaw>` (<pngData.count> bytes).`.

**Notes.** macOS-only: needs AppKit/ImageIO. On Linux the handler fails honestly with the exact macOS-only message. Validates `maxPixelSize > 0`. See `assist-artboards-media-tools.md` (Part B, "`image_generate_thumbnail`").

## 146. `image_get_dimensions` — Get Image Dimensions and Specs

- **Description (verbatim):** "Extracts image dimensions (width, height), scale, color space, and format without loading full bitmap."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Extracts image dimensions (width, height), scale, color space, and format without loading full bitmap.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the image file."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `path`, `width`, `height`, `colorModel`, `depth`, `hasAlpha`, `format`.
Message: `\n        Image Specifications for <raw>:\n        - Dimensions: <info.width> x <info.height> pixels\n        - Aspect Ratio: \(info.height > 0 ? String(format: "%.2f", Double(info.width) / Double(info.height)) : "N/A")\n        - Color Model: <info.colorModel> (<info.depth>-bit)\n        - Has Alpha Channel: \(info.hasAlpha ? "Yes" : "No")\n        - Resolution: \(Int(info.dpiWidth)) x \(Int(info.dpiHeight)) DPI\n        - Format / UTI: <info.format>\n        `.

**Notes.** Reads dimensions from the pure-Foundation header parser (PNG/JPEG/GIF/BMP/WebP/TIFF) on both platforms, with the ImageIO fallback on macOS. See `assist-artboards-media-tools.md` (Part B, "`image_get_dimensions`").

## 147. `svg_to_png` — Convert SVG to PNG

- **Description (verbatim):** "Renders an SVG vector graphic into a raster PNG image file at a specified scale or dimensions."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Renders an SVG vector graphic into a raster PNG image file at a specified scale or dimensions.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the .svg file."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative destination path for .png. Defaults to <path>.png."
    },
    "scale": {
      "type": "number",
      "description": "Scale multiplier for rendering (e.g. 1.0, 2.0 for @2x, 3.0 for @3x). Default: 2.0."
    },
    "width": {
      "type": "integer",
      "description": "Explicit width in pixels (optional; overrides scale if provided)."
    },
    "height": {
      "type": "integer",
      "description": "Explicit height in pixels (optional; overrides scale if provided)."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `width`, `height`, `size`.
Message: `Successfully rendered SVG `<sourceRaw>` to PNG `<destRaw>` (\(Int(targetSize.width))x\(Int(targetSize.height)), <pngData.count> bytes).`.

**Notes.** macOS-only: needs AppKit SVG rasterisation. On Linux the handler fails honestly with the exact macOS-only message; Ycode has no SVG rasterizer to substitute. See `assist-artboards-media-tools.md` (Part B, "`svg_to_png`").

## 148. `gzip_compress_file` — Gzip Compress File

- **Description (verbatim):** "Compresses a file into a .gz file using system gzip."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Compresses a file into a .gz file using system gzip.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the source file to compress."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative path for output .gz file. Defaults to <path>.gz."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `size`.
Message: `Successfully compressed `<sourceRaw>` to `<destRaw>` (<run.stdout.count> bytes).`.

**Notes.** Runs the system `gzip` as a fixed-argv subprocess (raw-`Data` runner, since the text runner would corrupt binary output), 120 s timeout (Legacy had none). See `assist-artboards-media-tools.md` (Part B, "`gzip_compress_file`").

## 149. `gzip_decompress_file` — Gzip Decompress File

- **Description (verbatim):** "Decompresses a .gz file into a destination file using system gzip."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Decompresses a .gz file into a destination file using system gzip.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the .gz file to decompress."
    },
    "destination": {
      "type": "string",
      "description": "Optional workspace-relative path for decompressed file. Defaults to removing .gz suffix."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `size`.
Message: `Successfully decompressed `<sourceRaw>` to `<destRaw>` (<run.stdout.count> bytes).`.

**Notes.** Runs the system `gzip -d` as a fixed-argv subprocess, 120 s timeout. See `assist-artboards-media-tools.md` (Part B, "`gzip_decompress_file`").

## 150. `tar_archive_create` — Create Tar Archive

- **Description (verbatim):** "Creates a .tar or .tar.gz archive from a directory or files using system tar."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a .tar or .tar.gz archive from a directory or files using system tar.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file or directory to archive."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative path for the resulting archive file (.tar or .tar.gz)."
    },
    "gzip": {
      "type": "boolean",
      "description": "Whether to apply gzip compression (defaults to true for .tar.gz or .tgz, false for .tar)."
    }
  },
  "required": [
    "path",
    "destination"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `size`.
Message: `Successfully created tar archive `<destRaw>` (<size> bytes).`.

**Notes.** Runs the system `tar` as a fixed-argv subprocess, 120 s timeout. See `assist-artboards-media-tools.md` (Part B, "`tar_archive_create`").

## 151. `tar_archive_extract` — Extract Tar Archive

- **Description (verbatim):** "Extracts a .tar or .tar.gz archive into a destination directory using system tar."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Extracts a .tar or .tar.gz archive into a destination directory using system tar.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the archive file (.tar, .tar.gz, .tgz)."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative destination directory to extract into."
    }
  },
  "required": [
    "path",
    "destination"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `extractedCount`.
Message: `Successfully extracted archive `<sourceRaw>` into `<destRaw>` (<count> extracted items).`.

**Notes.** Runs the system `tar` as a fixed-argv subprocess, 120 s timeout. See `assist-artboards-media-tools.md` (Part B, "`tar_archive_extract`").

## 152. `unzip_file` — Unzip Archive

- **Description (verbatim):** "Extracts a .zip archive into a destination directory using the macOS system archive tool."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Extracts a .zip archive into a destination directory using the macOS system archive tool.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the .zip archive to extract."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative path to the target directory to extract files into."
    }
  },
  "required": [
    "path",
    "destination"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `extractedCount`.
Message: `Successfully extracted `<sourceRaw>` into `<destRaw>` (<count> extracted items).`.

**Notes.** Runs `/usr/bin/ditto` on macOS and system `unzip` on Linux as fixed-argv subprocesses; fails honestly naming the missing command if it is uninstalled. See `assist-artboards-media-tools.md` (Part B, "`unzip_file`").

## 153. `zip_file` — Zip File or Directory

- **Description (verbatim):** "Compresses a file or directory into a .zip archive using the macOS system archive tool."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Compresses a file or directory into a .zip archive using the macOS system archive tool.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the source file or directory to compress."
    },
    "destination": {
      "type": "string",
      "description": "Workspace-relative path for the resulting .zip archive."
    }
  },
  "required": [
    "path",
    "destination"
  ]
}
```

**Output (success).** Structured data keys: `destination`, `size`.
Message: `Successfully compressed `<sourceRaw>` into `<destRaw>` (<size> bytes).`.

**Notes.** Runs `/usr/bin/ditto` on macOS and system `zip` on Linux as fixed-argv subprocesses; fails honestly naming the missing command if it is uninstalled. No ZIPFoundation dependency was added. See `assist-artboards-media-tools.md` (Part B, "`zip_file`").

## 154. `binary_plist_converter` — Binary Plist Converter

- **Description (verbatim):** "Converts property list files between XML and Binary formats using plutil."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Converts property list files between XML and Binary formats using plutil.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to the .plist file."
    },
    "format": {
      "type": "string",
      "description": "Target format: 'xml1' (human-readable) or 'binary1'. Defaults to 'xml1'."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Successfully converted `<raw>` to <format> format.`.

**Notes.** Converts with `PropertyListSerialization` instead of Legacy's `plutil` subprocess, so it works on Linux too. Path confinement is tightened vs Legacy (workspace-relative only). See `assist-artboards-media-tools.md` (Part B, "`binary_plist_converter`").

## 155. `json_validate` — Validate JSON

- **Description (verbatim):** "Validates a JSON file, and optionally formats it as pretty-printed sorted-keys JSON, writing the result back only when write is true."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Validates a JSON file, and optionally formats it as pretty-printed sorted-keys JSON, writing the result back only when write is true.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the JSON file."
    },
    "action": {
      "type": "string",
      "description": "Action: validate or format. Default: validate."
    },
    "write": {
      "type": "string",
      "description": "Pass \"true\" to write the formatted JSON back to the file on format. Default: false."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `path`, `valid`, `written`.
Message: `Valid JSON in <rel>.`; `Valid JSON in <rel>. Formatted JSON written back to the file.`; `Valid JSON in <rel>. Formatted preview returned without writing.`.

**Notes.** Kept separate from `json_validator_tool` (Legacy near-duplicate pair): fragments allowed, `write` string + `action` parameters, its own messages. `writes: true` even for validate-only calls, per the Wave 2 precedent for tools that can write. See `assist-artboards-media-tools.md` (Part B, "`json_validate`").

## 156. `json_validator_tool` — JSON Validator & Formatter

- **Description (verbatim):** "Validates JSON syntax, highlights line errors, and beautifies JSON configuration files."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Validates JSON syntax, highlights line errors, and beautifies JSON configuration files.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to JSON file in workspace."
    },
    "formatInPlace": {
      "type": "boolean",
      "description": "If true, reformats and writes pretty-printed JSON back to disk. Defaults to false."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `JSON is valid! Successfully reformatted and saved `<raw>` with standard 2-space pretty-printing.`; `✅ JSON syntax valid for `<raw>` (<data.count> bytes). Top-level type: \(type(of: jsonObject)).`.

**Notes.** Kept separate from `json_validate`: fragments not allowed, `formatInPlace` bool, its own messages. `writes: true` even for validate-only calls, per the Wave 2 precedent. See `assist-artboards-media-tools.md` (Part B, "`json_validator_tool`").

## 157. `yaml_parser_tool` — YAML Parser & Validator

- **Description (verbatim):** "Validates structure and syntax of YAML files (workflows, project.yml, fastlane) in the workspace."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Validates structure and syntax of YAML files (workflows, project.yml, fastlane) in the workspace.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to YAML file in workspace."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** Parses with Legacy's own heuristic ported verbatim — it is not a full YAML parser (Part B §4.5 states exactly what it does and does not do). Read-only. See `assist-artboards-media-tools.md` (Part B, "`yaml_parser_tool`").

## 158. `yaml_validate` — Validate YAML

- **Description (verbatim):** "Heuristic YAML validation (no full YAML parser): rejects tab indentation, unbalanced brackets/quotes, duplicate top-level keys, and mapping lines without a colon. Format normalizes indentation to 2 spaces per level and only writes back when write is true and validation passes."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Heuristic YAML validation (no full YAML parser): rejects tab indentation, unbalanced brackets/quotes, duplicate top-level keys, and mapping lines without a colon. Format normalizes indentation to 2 spaces per level and only writes back when write is true and validation passes.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the YAML file."
    },
    "action": {
      "type": "string",
      "description": "Action: validate or format. Default: validate."
    },
    "write": {
      "type": "string",
      "description": "Pass \"true\" to write the formatted YAML back to the file on format, only when validation passes. Default: false."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `path`, `valid`, `heuristic`, `written`.
Message: `YAML validation passed (heuristic — no full YAML parser) in <rel>.`; `YAML validation passed (heuristic — no full YAML parser) in <rel>. Formatted YAML written back to the file.`; `YAML validation passed (heuristic — no full YAML parser) in <rel>. Formatted preview returned without writing.`.

**Notes.** Validates with Legacy's own heuristic ported verbatim, not a full YAML parser. `writes: true` even for validate-only calls, per the Wave 2 precedent. See `assist-artboards-media-tools.md` (Part B, "`yaml_validate`").

## 159. `code_mutation_engine` — Controlled Mutation Engine

- **Description (verbatim):** "Applies safe, minimal source mutations scoped to a symbol or an exact range."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Applies safe, minimal source mutations scoped to a symbol or an exact range.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to mutate."
    },
    "replacement": {
      "type": "string",
      "description": "Replacement source text."
    },
    "symbol": {
      "type": "string",
      "description": "Symbol name whose body will be replaced. Provide either symbol or target."
    },
    "target": {
      "type": "string",
      "description": "Exact text to replace (all occurrences). Provide either symbol or target."
    }
  },
  "required": [
    "path",
    "replacement"
  ]
}
```

**Output (success).** Structured data keys: `bytes_before`, `bytes_after`.
Message: `Applied minimal mutation to <path>`.

**Notes.** Legacy's exact logic: symbol-body brace-counted replacement (the counter is deliberately naive about strings/comments, exactly as in Legacy) or replace-all of an exact target, through the `commit()` approval gate. The mutation must change the file; an unchanged result fails. See `assist-artboards-media-tools.md` (Part C, "`code_mutation_engine`").

## 160. `dependency_resolution_engine` — Dependency Resolution Engine

- **Description (verbatim):** "Resolves the workspace project's existing Swift Package dependencies via xcodebuild."
- **Capability:** `compilation`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Resolves the workspace project's existing Swift Package dependencies via xcodebuild.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "packageURL": {
      "type": "string",
      "description": "Package URL label for the resolution report. The tool resolves the project's existing dependencies; it does not add this package."
    }
  },
  "required": [
    "packageURL"
  ]
}
```

**Output (success).** Structured data keys: `output`, `package`, `exitCode`.
Message: `Resolved dependencies for <packageURL>`.

**Notes.** macOS-only: runs `/usr/bin/xcodebuild -resolvePackageDependencies` as a fixed argv via `terminalRunFixed` (300 s) after the approval gate. `packageURL` stays a report label only — it never adds a package. Non-macOS fails with Legacy's own `Dependency resolution requires macOS runtime`. See `assist-artboards-media-tools.md` (Part C, "`dependency_resolution_engine`").

## 161. `external_resource_gateway` — External Resource Gateway

- **Description (verbatim):** "Fetches external APIs and returns structured JSON response data."
- **Capability:** `general`. **Risk:** `externalSideEffect`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false, openWorld: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Fetches external APIs and returns structured JSON response data.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "url": {
      "type": "string",
      "description": "Fully qualified HTTPS URL to fetch. Must return a JSON body. http://, file://, and other schemes are rejected."
    }
  },
  "required": [
    "url"
  ]
}
```

**Output (success).** Structured data keys: `status_code`, `json`.
Message: `Fetched external resource.`.

**Notes.** HTTPS-only fetch, 30 s timeout, non-2xx fails, body must be JSON, returned pretty-printed with sorted keys, via `YcodeAssistant.HTTP.send`. No credential is sent. See `assist-artboards-media-tools.md` (Part C, "`external_resource_gateway`").

## 162. `patch_application_engine` — Patch Application Engine

- **Description (verbatim):** "Generates and applies line-level patches with integrity validation."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Generates and applies line-level patches with integrity validation.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to patch."
    },
    "original": {
      "type": "string",
      "description": "Block that must exist verbatim in the file."
    },
    "updated": {
      "type": "string",
      "description": "Replacement block."
    }
  },
  "required": [
    "path",
    "original",
    "updated"
  ]
}
```

**Output (success).** Structured data keys: `diff`.
Message: `Patch applied to <path>`.

**Notes.** Verbatim-block integrity check, then replace-all. The diff it reports is Legacy's naive line diff, not a Myers unified diff — Ycode has no Myers engine yet (same gap as Wave 2's `code_replace`). See `assist-artboards-media-tools.md` (Part C, "`patch_application_engine`").

## 163. `fetch_documentation` — Fetch Apple Documentation

- **Description (verbatim):** "Retrieves real Apple Developer documentation: API references (Swift/ObjC), framework guides, declarations, availability, and code examples from official Apple sources."
- **Capability:** `general`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true, openWorld: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Retrieves real Apple Developer documentation: API references (Swift/ObjC), framework guides, declarations, availability, and code examples from official Apple sources.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "query": {
      "type": "string",
      "description": "Natural-language topic, framework, API symbol, or question. Examples: 'SwiftUI View', 'URLSession', 'AppStorage property wrapper', 'how to request camera permission'."
    },
    "url": {
      "type": "string",
      "description": "Direct Apple Developer documentation URL, e.g. https://developer.apple.com/documentation/swiftui/view."
    },
    "framework": {
      "type": "string",
      "description": "Framework or technology to scope the lookup, e.g. 'SwiftUI', 'Foundation', 'AppKit'."
    },
    "platform": {
      "type": "string",
      "description": "Target platform for availability filtering, e.g. 'iOS', 'macOS', 'watchOS'. Informational: full availability is still reported."
    },
    "language": {
      "type": "string",
      "description": "Preferred declaration language: 'swift' or 'objc'. Defaults to Swift when both exist."
    },
    "includeExamples": {
      "type": "boolean",
      "description": "Include code examples from the documentation. Defaults to true."
    },
    "maxResults": {
      "type": "integer",
      "description": "Maximum documentation pages to return (1-5). Defaults to 3."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `content`, `truncated`, `count`.
Message: `Retrieved <pages.count> Apple documentation page(s) via <retrieval> in <duration>s.`.

**Notes.** Full Legacy pipeline: candidate probing, DocC JSON first (`tutorials/data/...json`), HTML fallback, declaration/availability/discussion/examples/related-links parsing, 24 h in-memory cache (100 entries), per-hop redirect allow-list, 20,000-char output cap. Size caps are enforced after download, not during transfer. See `assist-artboards-media-tools.md` (Part C, "`fetch_documentation`").

## 164. `reverse_analyze` — Reverse Analyze

- **Description (verbatim):** "Analyze an authorized binary or artifact with the native Reverse subsystem (REA rea-agents@6.5.0, static inspection only). Use when the user invoked @Reverse, or when an investigation needs artifact structure, Mach-O/plist/signature facts, Go/managed metadata, SQLite schema, or objdump output. Never use for circumventing DRM, license checks, anti-cheat, or authentication. targetPath must be an absolute path inside the open project, ~/Downloads, ~/Desktop, or ~/Documents."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Analyze an authorized binary or artifact with the native Reverse subsystem (REA rea-agents@6.5.0, static inspection only). Use when the user invoked @Reverse, or when an investigation needs artifact structure, Mach-O/plist/signature facts, Go/managed metadata, SQLite schema, or objdump output. Never use for circumventing DRM, license checks, anti-cheat, or authentication. targetPath must be an absolute path inside the open project, ~/Downloads, ~/Desktop, or ~/Documents.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "targetPath": {
      "type": "string",
      "description": "Absolute path of the artifact to analyze (must be in scope: open project, ~/Downloads, ~/Desktop, ~/Documents)."
    },
    "operation": {
      "type": "string",
      "description": "Allow-listed operation: inspect_artifact, inspect_macho, inspect_plist, inspect_signature, list_architectures, demangle_swift, inspect_go_binary, inspect_managed_artifact, inspect_managed_members, inspect_sqlite_database, inspect_with_objdump."
    },
    "task": {
      "type": "string",
      "description": "The user's investigation request (what to determine about the artifact)."
    },
    "objdumpOperation": {
      "type": "string",
      "description": "Required for inspect_with_objdump: file_headers, section_headers, symbols, relocations, dwarf, disassemble, disassemble_all."
    },
    "symbol": {
      "type": "string",
      "description": "Swift symbol to demangle (demangle_swift only)."
    },
    "timeoutSeconds": {
      "type": "number",
      "description": "Timeout in seconds (default 300, clamped to 10...1800)."
    }
  },
  "required": [
    "targetPath"
  ]
}
```

**Output (success).** None — the handler always fails (see Notes).

**Notes.** HONESTLY FAILING: registered with the full Legacy schema and Legacy's complete validation chain (operation allow-list, REA-disclaimer task screen, target/scope validation, objdump sub-op, timeout clamp 10–1800 s), then fails naming the exact prerequisite — Node.js 22/24/26 + pinned `rea-agents@6.5.0` + `ReverseBridge.mjs`, none of which exist in Ycode. No Evidence envelope is faked. A future seam is `YcodeMachO` for host-local `list_architectures`/`inspect_macho`, but that would change the tool's output contract, so it belongs to a later wave's decision. See `assist-artboards-media-tools.md` (Part C, "`reverse_analyze`").

## 165. Summary: capability / risk / permission / writes (Wave 5)

| Tool | Capability | Risk | Permission | Writes |
|---|---|---|---|---|
| `artboard_compile` | compilation | safeMutation | fileSystem | yes |
| `artboard_create` | fileModification | safeMutation | fileSystem | yes |
| `artboard_delete` | fileModification | safeMutation | fileSystem | yes |
| `artboard_get` | diagnostics | safeRead | none | no |
| `artboard_list` | diagnostics | safeRead | none | no |
| `artboard_run_app` | compilation | safeMutation | fileSystem | yes |
| `artboard_update` | fileModification | safeMutation | fileSystem | yes |
| `fix_artboards` | diagnostics | safeMutation | fileSystem | yes |
| `device_list` | diagnostics | safeRead | none | no |
| `simulator_boot` | systemExecution | execution | none | no |
| `simulator_controller` | systemExecution | safeMutation | fileSystem | yes |
| `simulator_list` | diagnostics | safeRead | none | no |
| `image_convert_format` | fileModification | safeMutation | fileSystem | yes |
| `image_decode_base64` | fileModification | safeMutation | fileSystem | yes |
| `image_encode_base64` | fileReading | safeRead | none | no |
| `image_extract_metadata` | fileReading | safeRead | none | no |
| `image_generate_thumbnail` | fileModification | safeMutation | fileSystem | yes |
| `image_get_dimensions` | fileReading | safeRead | none | no |
| `svg_to_png` | fileModification | safeMutation | fileSystem | yes |
| `gzip_compress_file` | fileModification | safeMutation | fileSystem | yes |
| `gzip_decompress_file` | fileModification | safeMutation | fileSystem | yes |
| `tar_archive_create` | fileModification | safeMutation | fileSystem | yes |
| `tar_archive_extract` | fileModification | safeMutation | fileSystem | yes |
| `unzip_file` | fileModification | safeMutation | fileSystem | yes |
| `zip_file` | fileModification | safeMutation | fileSystem | yes |
| `binary_plist_converter` | fileModification | safeMutation | fileSystem | yes |
| `json_validate` | fileModification | safeMutation | fileSystem | yes |
| `json_validator_tool` | diagnostics | safeMutation | fileSystem | yes |
| `yaml_parser_tool` | diagnostics | safeRead | none | no |
| `yaml_validate` | fileModification | safeMutation | fileSystem | yes |
| `code_mutation_engine` | fileModification | safeMutation | fileSystem | yes |
| `dependency_resolution_engine` | compilation | execution | none | yes |
| `external_resource_gateway` | general | externalSideEffect | none | yes |
| `patch_application_engine` | fileModification | safeMutation | fileSystem | yes |
| `fetch_documentation` | general | safeRead | none | no |
| `reverse_analyze` | diagnostics | safeRead | none | no |
## Wave 6 — testing / QA tools

Wave 6 ports the Legacy Assist Testing/QA family: test running &
coverage (16), static analysis (22), security/privacy/platform audits
(18), and docs/review/repo tooling (23) — 79 tools, taking the MCP
catalogue from 172 to 251 registrations. No tool in this wave was
already a Ycode registration, so none is aligned in place. The
behaviour spec is `specs/ide/assist-testing-tools.md` (Part A test
running, Part B static analysis, Part C audits, Part D docs/review).

## 166. Wave 6 test-running conventions

- Test execution runs through the existing session seam
  (`WorkspaceSession.discoverTests` / `runTests(only:)`, the same path as
  the `test` tool); no `xcodebuild` process is spawned and no parallel
  test runner is built. `test_coverage_report` reads `latestCoverage`;
  `test_coverage_reporter` runs the real `xcrun xccov`.
- `compiler_diagnostics_engine` runs `s.build(.build)` and still succeeds
  when the build fails — success means diagnostics were collected.
- `performance_benchmark` runs its closed allow-list via `terminalRunFixed`
  with a 300 s/run bound (Legacy waited unboundedly).

## 167. Wave 6 static-analysis conventions

- All tools are Legacy-faithful regex/line heuristics, blind spots included
  (string/comment mentions count, substring matching where Legacy does it,
  textual brace counting). `YcodeSyntax` is a tokenizer/block-structure
  library, not a Swift declaration parser, and `YcodeMCP` does not depend
  on it, so no AST parser is used; `swift_ast_inspector` implements only
  Legacy's regex structural fallback.
- `import_cleanup` is the only writer in this slice (one approval per changed
  file, in order, stopping at the first refusal). `dead_code_eliminator`
  is read-only despite its name (Legacy `safeRead`).

## 168. Wave 6 audit conventions

- `mach_o_binary_analyzer` reuses Ycode's `YcodeMachO` (`MachOFile` /
  `MachOImage`); it reports parsed slices/dylibs instead of Legacy's
  `/usr/bin/file` + `xcrun otool` text, and fails on non-Mach-O files and
  32-bit Mach-O binaries. `memory_leak_detector` is a static source scan,
  as in Legacy — a clean scan means 'no matching patterns', not 'leak-free'.
- `privacy_manifest_auditor` is the only writer in this slice (`generate`
  writes `PrivacyInfo.xcprivacy` via `commit()`; `audit` writes nothing).
- `framework_linker_auditor`, `swift_data_schema_auditor` and
  `bundle_resource_auditor` declare `path` in Legacy but never read it;
  the port keeps the schema and likewise ignores it. `secrets_scan`
  reports `file:line:label` only; secret values never appear in output.

## 169. Wave 6 docs / review conventions

- `code_review` and `safe_undo` are honestly failing (LLM provider and
  workspace snapshot store respectively — see their sections).
- `automated_repair_engine` annotates deterministically and never rebuilds,
  as in Legacy. `session_progress_report` has no phase coordinator in Ycode,
  so phase counts are always 0; the agent-notes line is real.
- `tool_capability_lookup` looks up the live `server.tools`; capability and
  estimated cost are omitted (Ycode tools carry neither).

## 170. `test_run_single` — Run Single Test

- **Description (verbatim):** "Runs one test by ID with xcodebuild test -only-testing and returns pass/fail plus the output tail."
- **Capability:** `testing`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs one test by ID with xcodebuild test -only-testing and returns pass/fail plus the output tail.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "testId": {
      "type": "string",
      "description": "Required. Test identifier, e.g. MyTests/MyTest/testExample."
    },
    "scheme": {
      "type": "string",
      "description": "Scheme to test. Defaults to the first scheme listed by xcodebuild."
    },
    "destination": {
      "type": "string",
      "description": "xcodebuild destination. Default: platform=macOS."
    }
  },
  "required": [
    "testId"
  ]
}
```

**Output (success).** Structured data keys: `status`, `testId`, `scheme`, `passed`, `failed`, `skipped`, `tests`, `logTail`.

**Notes.** Runs through the session seam (`discoverTests` / `runTests(only:)`); no `xcodebuild` spawn, no `exitCode` / `resultBundle` keys — the seam reports per-test outcomes, not a process exit code. See `assist-testing-tools.md` (Part A, "`test_run_single`").

## 171. `xctest_discovery` — XCTest Discovery

- **Description (verbatim):** "Discovers XCTestCase subclasses and their test methods across the workspace — a test inventory without running anything."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Discovers XCTestCase subclasses and their test methods across the workspace — a test inventory without running anything.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `classCount`, `testCount`.
Message: `No XCTestCase subclasses found in the workspace.`.

**Notes.** Session discovery filtered to `.xctest`; a test inventory without running anything. See `assist-testing-tools.md` (Part A, "`xctest_discovery`").

## 172. `test_log_parse` — Parse Test Log

- **Description (verbatim):** "Parses a test log for passed/failed test cases, suite summaries, and errors, returning counts plus the failed test list."
- **Capability:** `testing`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Parses a test log for passed/failed test cases, suite summaries, and errors, returning counts plus the failed test list.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "logPath": {
      "type": "string",
      "description": "Required. Workspace-relative path to a test log file."
    }
  },
  "required": [
    "logPath"
  ]
}
```

**Output (success).** Structured data keys: `total`, `passed`, `failed`, `errorCount`, `failedTests`.
Message: `Test log '\(logPath)': \(total) test case(s), \(parsed.passed) passed, \(parsed.failed) failed, \(parsed.errorLines.count) error line(s).`.

**Notes.** Pure log parsing; counts plus the failed-test list. See `assist-testing-tools.md` (Part A, "`test_log_parse`").

## 173. `test_flaky_detect` — Flaky Test Detection

- **Description (verbatim):** "Parses test logs and reports tests that show both pass and fail outcomes across runs."
- **Capability:** `testing`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Parses test logs and reports tests that show both pass and fail outcomes across runs.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "logPath": {
      "type": "string",
      "description": "Workspace-relative path to a test log file."
    },
    "logsDir": {
      "type": "string",
      "description": "Workspace-relative path to a directory of test log files. Used when logPath is empty."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `filesRead`, `flakyCount`, `flakyTests`.
Message: `Flaky test scan across \(filesRead) log file(s): \(distinctCount) distinct tests observed, \(flaky.count) flaky.`.

**Notes.** Pure log analysis across runs; a test is flaky when it shows both pass and fail outcomes. See `assist-testing-tools.md` (Part A, "`test_flaky_detect`").

## 174. `test_coverage_report` — Test Coverage Report

- **Description (verbatim):** "Runs xcodebuild test with code coverage enabled and reports the coverage summary plus pass/fail."
- **Capability:** `testing`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs xcodebuild test with code coverage enabled and reports the coverage summary plus pass/fail.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "scheme": {
      "type": "string",
      "description": "Scheme to test. Defaults to the first scheme listed by xcodebuild."
    },
    "destination": {
      "type": "string",
      "description": "xcodebuild destination. Default: platform=macOS."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `status`, `scheme`, `coverage`, `passed`, `failed`, `skipped`.
Message: `Test Coverage — \(s.model.displayName) / \(schemeName): \(status)\n\(coverageText)`.

**Notes.** Runs through the session test seam with coverage; reads `latestCoverage` and says plainly when the scheme gathered no coverage. See `assist-testing-tools.md` (Part A, "`test_coverage_report`").

## 175. `test_coverage_reporter` — Test Coverage Reporter

- **Description (verbatim):** "Extracts line and target test coverage metrics from build and test artifacts via xccov."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Extracts line and target test coverage metrics from build and test artifacts via xccov.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "reportPath": {
      "type": "string",
      "description": "Optional explicit path to an .xccovreport file."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No active .xccovreport or coverage archive found in DerivedData. Ensure 'Code Coverage' is enabled in your Xcode Scheme test settings.`; `Coverage report found at \(targetReport.lastPathComponent), but yielded no text metrics.`; `### Test Coverage Report (\(targetReport.lastPathComponent)):\n\n```\n\(snippet)\n````.

**Notes.** Runs the real `xcrun xccov` via `terminalRunFixed` and reports its actual output. See `assist-testing-tools.md` (Part A, "`test_coverage_reporter`").

## 176. `test_data_factory` — Test Data Factory

- **Description (verbatim):** "Writes a test fixture file: a JSON object with sample values per field type, or a Swift struct with a static sample."
- **Capability:** `testing`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Writes a test fixture file: a JSON object with sample values per field type, or a Swift struct with a static sample.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "name": {
      "type": "string",
      "description": "Required. Valid Swift identifier used for the fixture type and file name."
    },
    "kind": {
      "type": "string",
      "description": "json or swift. Default: json."
    },
    "fields": {
      "type": "string",
      "description": "Optional comma list, e.g. id:Int,name:String,isActive:Bool. Defaults to id:Int,name:String."
    },
    "path": {
      "type": "string",
      "description": "Optional workspace-relative directory or file path. Default: TestData/."
    },
    "overwrite": {
      "type": "string",
      "description": "Must be 'true' to replace an existing file. Default: 'false'."
    }
  },
  "required": [
    "name"
  ]
}
```

**Output (success).** Structured data keys: `path`, `kind`, `name`.
Message: `Created test fixture at \(rel)`.

**Notes.** Writes fixture files through `commit()`; approval is requested before writing. See `assist-testing-tools.md` (Part A, "`test_data_factory`").

## 177. `test_snapshot_manage` — Manage Test Snapshots

- **Description (verbatim):** "Lists snapshot test reference images under __Snapshots__ directories, or deletes unreferenced snapshot files when confirm is true."
- **Capability:** `testing`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Lists snapshot test reference images under __Snapshots__ directories, or deletes unreferenced snapshot files when confirm is true.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "list or clean. Default: list."
    },
    "confirm": {
      "type": "string",
      "description": "Must be 'true' for clean. Any other value refuses to delete."
    }
  },
  "required": []
}
```

**Output (success).** No output schema declared; structured data keys: `count`, `files`, `deletedCount`, `keptCount`, `deleted`.
Message: `No snapshot files found under any __Snapshots__ directory in the workspace.`; `Snapshot references: \(snapshotFiles.count) file(s) under __Snapshots__ directories.`; `No snapshot files found. Nothing to clean.`.

**Notes.** Snapshot deletions go through one `MCPChange` + `approve()` per file. See `assist-testing-tools.md` (Part A, "`test_snapshot_manage`").

## 178. `test_target_add` — Add Test Target

- **Description (verbatim):** "Creates a test directory with a real XCTest file and inserts a PBXNativeTarget block into the project pbxproj."
- **Capability:** `compilation`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a test directory with a real XCTest file and inserts a PBXNativeTarget block into the project pbxproj.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "targetName": {
      "type": "string",
      "description": "Required. Valid identifier for the new test target."
    },
    "type": {
      "type": "string",
      "description": "unit or ui. Default: unit."
    }
  },
  "required": [
    "targetName"
  ]
}
```

**Output (success).** Structured data keys: `targetName`, `type`, `targetID`, `testFile`.
Message: `Added test target '\(targetName)' (\(type)) with test file \(targetName)/\(targetName)Tests.swift and PBXNativeTarget entry in project.pbxproj.`.

**Notes.** Computes the pbxproj edit in memory before writing anything; the write goes through `commit()`. See `assist-testing-tools.md` (Part A, "`test_target_add`").

## 179. `ui_test_scaffold` — UI Test Scaffold

- **Description (verbatim):** "Creates a real XCTest UI test file with setUp, launch, a launch-state assertion, and tearDown."
- **Capability:** `testing`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates a real XCTest UI test file with setUp, launch, a launch-state assertion, and tearDown.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "testName": {
      "type": "string",
      "description": "Required. Valid Swift identifier used for the test class and file name."
    },
    "targetApp": {
      "type": "string",
      "description": "Optional bundle identifier of the app under test. When empty, XCUIApplication() is used."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative directory for the new test file. Default: UITests/."
    },
    "overwrite": {
      "type": "string",
      "description": "Must be 'true' to replace an existing file. Default: 'false'."
    }
  },
  "required": [
    "testName"
  ]
}
```

**Output (success).** Structured data keys: `path`, `testName`.
Message: `Created UI test file at \(rel)`.

**Notes.** Writes the scaffold through `commit()`; approval is requested before writing. See `assist-testing-tools.md` (Part A, "`ui_test_scaffold`").

## 180. `interface_simulator` — Interface Simulator & Accessibility Auditor

- **Description (verbatim):** "Inspects SwiftUI View files, audits accessibility traits, accessibility identifiers, touch targets, and hierarchy structure."
- **Capability:** `testing`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inspects SwiftUI View files, audits accessibility traits, accessibility identifiers, touch targets, and hierarchy structure.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "viewPath": {
      "type": "string",
      "description": "Workspace-relative path to a SwiftUI View file."
    }
  },
  "required": [
    "viewPath"
  ]
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** SwiftUI interface/accessibility audit; Legacy's accessibility counting quirks preserved. See `assist-testing-tools.md` (Part A, "`interface_simulator`").

## 181. `preflight_checks` — Preflight Checks

- **Description (verbatim):** "Runs environment preflight checks before a build/task: workspace writable, Xcode tools present, DerivedData reachable, free disk space."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs environment preflight checks before a build/task: workspace writable, Xcode tools present, DerivedData reachable, free disk space.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `checkCount`, `failureCount`.

**Notes.** Read-only readiness checks for build/test. See `assist-testing-tools.md` (Part A, "`preflight_checks`").

## 182. `performance_benchmark` — Performance Benchmark

- **Description (verbatim):** "Runs an allow-listed command N times via Process and reports average, minimum, and maximum wall time plus exit codes."
- **Capability:** `diagnostics`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs an allow-listed command N times via Process and reports average, minimum, and maximum wall time plus exit codes.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "command": {
      "type": "string",
      "description": "Required. Executable path, one of /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du. May include arguments after the executable."
    },
    "arguments": {
      "type": "string",
      "description": "Optional extra arguments, space-separated. Combined with any arguments in command."
    },
    "iterations": {
      "type": "string",
      "description": "Run count. Default: 3. Maximum: 10."
    }
  },
  "required": [
    "command"
  ]
}
```

**Output (success).** No output schema declared; structured data keys: `executable`, `iterations`, `averageSeconds`, `minSeconds`, `maxSeconds`, `exitCodes`.
Message: `Benchmark '\(executable) \(allArguments.joined(separator: " "))' over \(iterations) run(s): avg \(String(format: "%.3f", average))s, min \(String(format: "%.3f", minValue))s, max \(String(format: "%.3f", maxValue))s. Exit codes: \(exitCodes.map { String($0) }.joined(separator: ", ")).\nLast run output tail:\n\(String(lastOutput.suffix(1000)))`.

**Notes.** Runs its closed allow-list via `terminalRunFixed` (300 s/run bound — Legacy waited unboundedly). See `assist-testing-tools.md` (Part A, "`performance_benchmark`").

## 183. `compiler_diagnostics_engine` — Compiler Diagnostics Engine

- **Description (verbatim):** "Runs xcodebuild and parses warnings/errors into structured diagnostics."
- **Capability:** `diagnostics`. **Risk:** `execution`. **Required permission:** `none`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: false`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs xcodebuild and parses warnings/errors into structured diagnostics.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "project": {
      "type": "string",
      "description": "Workspace-relative path to the .xcodeproj/.xcworkspace to diagnose. Defaults to the project found in the workspace root."
    },
    "scheme": {
      "type": "string",
      "description": "Build scheme. Defaults to the project's first listed scheme."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `error_count`, `warning_count`, `errors`, `warnings`, `exitCode`, `buildFailed`.

**Notes.** Runs `s.build(.build)` and still succeeds when the build fails — success means diagnostics were collected. See `assist-testing-tools.md` (Part A, "`compiler_diagnostics_engine`").

## 184. `crash_log_parse` — Crash Log Parse

- **Description (verbatim):** "Parses .crash/.ips crash logs: exception type, termination reason, faulting thread, and top blamed frames."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Parses .crash/.ips crash logs: exception type, termination reason, faulting thread, and top blamed frames.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to the .crash or .ips file."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `hasException`, `frameCount`.

**Notes.** Pure crash-log parsing. See `assist-testing-tools.md` (Part A, "`crash_log_parse`").

## 185. `runtime_diagnostics_engine` — Runtime Diagnostics Engine

- **Description (verbatim):** "Analyzes runtime logs for crashes/anomalies and suggests concrete fixes."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Analyzes runtime logs for crashes/anomalies and suggests concrete fixes.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "logPath": {
      "type": "string",
      "description": "Workspace-relative path of the log file to analyze."
    }
  },
  "required": [
    "logPath"
  ]
}
```

**Output (success).** Structured data keys: `crash_count`, `thread_anomaly_count`, `suggestions`, `crashes`.
Message: `Runtime diagnostics complete.`.

**Notes.** Runtime diagnostics from the session; read-only. See `assist-testing-tools.md` (Part A, "`runtime_diagnostics_engine`").

## 186. `code_lint` — Lint Code

- **Description (verbatim):** "Runs a linter on the specified file or directory."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Runs a linter on the specified file or directory.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative file path to lint. Default: \".\"."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `issues`.
Message: `Basic linting found \(issues.count) issues in \(path)`; `No basic linting issues found in \(path)`.

**Notes.** Line length (>120 chars) and TODO/FIXME markers, exactly as in Legacy. See `assist-testing-tools.md` (Part B, "`code_lint`").

## 187. `swift_format_lint` — Swift Format Linter

- **Description (verbatim):** "Lints Swift source files for code style, line length, indentation, and formatting violations."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Lints Swift source files for code style, line length, indentation, and formatting violations.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to Swift file in workspace."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Formatting check passed! No style or whitespace issues found in `\(path)`.`.

**Notes.** Swift style lint of one file; Legacy-faithful heuristic. See `assist-testing-tools.md` (Part B, "`swift_format_lint`").

## 188. `dead_code_scan` — Dead Code Scan

- **Description (verbatim):** "Heuristic scan for Swift declarations that appear to have no references outside their own declaration line. Excludes public/open API, @main entry points, overrides, and well-known lifecycle names. Findings are heuristic leads, not proof of dead code."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Heuristic scan for Swift declarations that appear to have no references outside their own declaration line. Excludes public/open API, @main entry points, overrides, and well-known lifecycle names. Findings are heuristic leads, not proof of dead code.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to scan. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `declarationCount`, `candidateCount`, `candidates`.
Message: `Dead Code Scan: no Swift files found.`; `Dead Code Scan (heuristic): scanned \(entries.count) Swift file(s), found \(declarationCount) declaration(s), \(candidates.count) candidate(s) with no other whole-word references.\n`.

**Notes.** Heuristic unreferenced declarations; string/comment mentions count, as in Legacy. See `assist-testing-tools.md` (Part B, "`dead_code_scan`").

## 189. `dead_code_eliminator` — Dead Code Eliminator

- **Description (verbatim):** "Identifies unreferenced private functions, unused variables, and unreachable code structures in Swift files."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Identifies unreferenced private functions, unused variables, and unreachable code structures in Swift files.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "filePath": {
      "type": "string",
      "description": "Workspace-relative path to a Swift file to inspect."
    }
  },
  "required": [
    "filePath"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Dead Code Scan completed for \(filePath): All \(privateDeclarations.count) private declarations have active call sites.`; `Dead Code Scan found \(deadDeclarations.count) unused declarations in \(filePath):\n`.

**Notes.** Read-only despite its name (Legacy `riskLevel` is `safeRead`); it only reports. See `assist-testing-tools.md` (Part B, "`dead_code_eliminator`").

## 190. `duplicate_code_scan` — Duplicate Code Scan

- **Description (verbatim):** "Heuristic scan for duplicated blocks of Swift code. Lines are normalized (trimmed, blank lines and full-line comments and brace-only lines skipped) and compared with a sliding window. Findings are heuristic leads — duplicated blocks may be intentional."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Heuristic scan for duplicated blocks of Swift code. Lines are normalized (trimmed, blank lines and full-line comments and brace-only lines skipped) and compared with a sliding window. Findings are heuristic leads — duplicated blocks may be intentional.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to scan. Defaults to the workspace root."
    },
    "minLines": {
      "type": "string",
      "description": "Minimum normalized lines per block, as a decimal string. Clamped to at least 3. Default: \"6\"."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `duplicateGroups`, `groups`.
Message: `Duplicate Code Scan: no Swift files found.`; `Duplicate Code Scan (heuristic): scanned \(files.count) Swift file(s) with window size \(minLines) normalized line(s), found \(kept.count) duplicated block group(s).\n`.

**Notes.** Heuristic duplicated blocks; Legacy-faithful. See `assist-testing-tools.md` (Part B, "`duplicate_code_scan`").

## 191. `unused_imports_detector` — Unused Imports Detector

- **Description (verbatim):** "Scans Swift files to detect redundant or unused framework imports."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans Swift files to detect redundant or unused framework imports.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to the Swift file."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No framework imports found in `\(path)`.`; `Import analysis clean: All imported modules appears to be referenced in `\(path)`.`; `### Potentially Unused Imports in `\(path)`:\n\n`.

**Notes.** Read-only unused-import report. See `assist-testing-tools.md` (Part B, "`unused_imports_detector`").

## 192. `import_cleanup` — Import Cleanup

- **Description (verbatim):** "Removes unused import lines from Swift files. An import is removed only when its module name never appears as a whole word anywhere else in the file. Well-known Apple SDK and test modules (Foundation, SwiftUI, XCTest, Testing, and others) are never removed, because their symbols do not mention the module name. Only files that change are rewritten. Heuristic: it does not resolve re-exports or typealiases across modules."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Removes unused import lines from Swift files. An import is removed only when its module name never appears as a whole word anywhere else in the file. Well-known Apple SDK and test modules (Foundation, SwiftUI, XCTest, Testing, and others) are never removed, because their symbols do not mention the module name. Only files that change are rewritten. Heuristic: it does not resolve re-exports or typealiases across modules.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a Swift file or directory to clean. Required."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `filesChanged`, `removedImports`, `changedFileCount`, `removed`.
Message: `Import Cleanup: no Swift files found.`; `Import Cleanup: no unused imports found in \(files.count) Swift file(s). Nothing changed.`; `Import Cleanup: removed \(removed.count) unused import(s) across \(changed.count) file(s):\n`.

**Notes.** The only writer in this slice: one approval per changed file, in order, stopping at the first refusal. See `assist-testing-tools.md` (Part B, "`import_cleanup`").

## 193. `force_unwrap_scan` — Force Unwrap Scan

- **Description (verbatim):** "Scans Swift sources for force unwraps (!), try!, and as! — crash-prone constructs worth reviewing."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans Swift sources for force unwraps (!), try!, and as! — crash-prone constructs worth reviewing.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum findings. Default 100, max 1000."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.
Message: `No force-unwrap constructs found.`.

**Notes.** Preserves Legacy's `as! ` trailing-space pattern. See `assist-testing-tools.md` (Part B, "`force_unwrap_scan`").

## 194. `todo_scan` — TODO Scan

- **Description (verbatim):** "Scans Swift source files for TODO, FIXME, XXX, and HACK markers and returns a file:line:text list with counts per tag."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans Swift source files for TODO, FIXME, XXX, and HACK markers and returns a file:line:text list with counts per tag.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to scan. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `totalMarkers`, `todo`, `fixme`, `xxx`, `hack`, `findings`.
Message: `TODO Scan: no Swift files found.`; `TODO Scan: scanned \(files.count) Swift file(s), found \(total) marker(s) — TODO: \(counts["TODO"] ?? 0), FIXME: \(counts["FIXME"] ?? 0), XXX: \(counts["XXX"] ?? 0), HACK: \(counts["HACK"] ?? 0).\n`.

**Notes.** TODO/FIXME/XXX/HACK markers. See `assist-testing-tools.md` (Part B, "`todo_scan`").

## 195. `todo_fixme_scanner` — TODO & FIXME Scanner

- **Description (verbatim):** "Scans workspace files to index all TODO, FIXME, MARK, HACK, and BUG annotations."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans workspace files to index all TODO, FIXME, MARK, HACK, and BUG annotations.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "tag": {
      "type": "string",
      "description": "Optional specific tag filter: 'TODO', 'FIXME', 'BUG', 'HACK', or 'MARK'."
    },
    "maxResults": {
      "type": "integer",
      "description": "Maximum number of results to return (default: 50)."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No TODO/FIXME/BUG annotations found in workspace.`.

**Notes.** Workspace action-item index; colon-required matching, as in Legacy. See `assist-testing-tools.md` (Part B, "`todo_fixme_scanner`").

## 196. `comment_density_report` — Comment Density Report

- **Description (verbatim):** "Reports comment-to-code ratios per Swift file, flagging the least-documented files."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reports comment-to-code ratios per Swift file, flagging the least-documented files.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum files to report. Default 30."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `fileCount`.

**Notes.** Comment-to-code ratios. See `assist-testing-tools.md` (Part B, "`comment_density_report`").

## 197. `code_comment_extract` — Code Comment Extract

- **Description (verbatim):** "Extracts documentation comments (/// and /** */) for a symbol or a whole file, with locations."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Extracts documentation comments (/// and /** */) for a symbol or a whole file, with locations.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative Swift file to extract from."
    },
    "symbol": {
      "type": "string",
      "description": "Optional: only extract comments attached to this symbol name."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `count`.
Message: `No documentation comments found in \(raw)\(symbol.map { " for '\($0)'" } ?? "").`.

**Notes.** Documentation comments; multi-line `/** */` handling preserved. See `assist-testing-tools.md` (Part B, "`code_comment_extract`").

## 198. `complexity_analysis` — Complexity Analysis

- **Description (verbatim):** "Analyzes the cyclomatic complexity of code."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Analyzes the cyclomatic complexity of code.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to analyze."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `score`, `rating`.
Message: `Complexity analysis for \(path): \(rating) (Cyclomatic approximation: \(complexity))`.

**Notes.** Cyclomatic approximation. See `assist-testing-tools.md` (Part B, "`complexity_analysis`").

## 199. `function_size_report` — Function Size Report

- **Description (verbatim):** "Finds the longest functions by line count, highlighting decomposition candidates."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds the longest functions by line count, highlighting decomposition candidates.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "threshold": {
      "type": "integer",
      "description": "Only report functions at or above this many lines. Default 60."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum functions to report. Default 30."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.
Message: `No functions with \(threshold)+ lines found.`.

**Notes.** Longest functions. See `assist-testing-tools.md` (Part B, "`function_size_report`").

## 200. `code_metrics_analyzer` — Code Metrics Analyzer

- **Description (verbatim):** "Calculates lines of code, comment density, type counts, and complexity metrics for Swift source files."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Calculates lines of code, comment density, type counts, and complexity metrics for Swift source files.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to a Swift file or directory."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** File/directory code metrics. See `assist-testing-tools.md` (Part B, "`code_metrics_analyzer`").

## 201. `string_literal_audit` — String Literal Audit

- **Description (verbatim):** "Finds hardcoded user-facing string literals that are not routed through localization (NSLocalizedString / String(localized:))."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds hardcoded user-facing string literals that are not routed through localization (NSLocalizedString / String(localized:)).",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum findings. Default 100, max 1000."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.
Message: `No hardcoded user-facing string literals detected.`.

**Notes.** Unlocalized user-facing strings; textual check. See `assist-testing-tools.md` (Part B, "`string_literal_audit`").

## 202. `deprecation_usage_scan` — Deprecation Usage Scan

- **Description (verbatim):** "Finds declarations marked @available(*, deprecated) in workspace Swift sources and reports where those deprecated symbols are used."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds declarations marked @available(*, deprecated) in workspace Swift sources and reports where those deprecated symbols are used.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum usage sites. Default 100, max 500."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `declarationCount`, `usageCount`.
Message: `No @available(*, deprecated) declarations found in workspace Swift sources.`.

**Notes.** Checks deprecated names in sorted order (Legacy iterated an `NSMutableSet`, nondeterministically); the finding set is identical. See `assist-testing-tools.md` (Part B, "`deprecation_usage_scan`").

## 203. `swift_ast_inspector` — Swift AST Inspector

- **Description (verbatim):** "Inspects the abstract syntax tree (AST) and type declaration hierarchy of a Swift source file."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inspects the abstract syntax tree (AST) and type declaration hierarchy of a Swift source file.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to the Swift file within the workspace."
    },
    "symbol": {
      "type": "string",
      "description": "Optional symbol name to filter AST declarations for."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No major type declarations found in \(path).`; `Swift Structural AST Declarations in \(path):\n\n`.

**Notes.** Legacy's regex structural fallback only — the primary `xcrun swiftc -dump-ast` path is not ported (no Swift toolchain in the MCP host). It still returns real structural results, exactly as Legacy does when `swiftc` is unavailable. See `assist-testing-tools.md` (Part B, "`swift_ast_inspector`").

## 204. `swift_concurrency_analyzer` — Swift Concurrency Analyzer

- **Description (verbatim):** "Audits Swift code for Swift 6 strict concurrency hazards, mutable globals, and actor isolation boundaries."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits Swift code for Swift 6 strict concurrency hazards, mutable globals, and actor isolation boundaries.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to file or directory in workspace."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** Swift 6 hazard audit; heuristic. See `assist-testing-tools.md` (Part B, "`swift_concurrency_analyzer`").

## 205. `concurrency_audit` — Concurrency Audit

- **Description (verbatim):** "Heuristic scan for Swift concurrency hazards: DispatchQueue.main.sync, nonisolated(unsafe), mutable static vars, Task blocks without await, force unwraps inside async functions, and SwiftUI types without @MainActor. All findings are heuristic leads, not confirmed bugs."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Heuristic scan for Swift concurrency hazards: DispatchQueue.main.sync, nonisolated(unsafe), mutable static vars, Task blocks without await, force unwraps inside async functions, and SwiftUI types without @MainActor. All findings are heuristic leads, not confirmed bugs.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to audit. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `findingCount`, `findings`.
Message: `Concurrency Audit: no Swift files found.`; `Concurrency Audit (heuristic): scanned \(files.count) Swift file(s), found \(findings.count) finding(s).\n`.

**Notes.** Heuristic concurrency hazards. See `assist-testing-tools.md` (Part B, "`concurrency_audit`").

## 206. `entry_points_discover` — Discover Entry Points

- **Description (verbatim):** "Finds application entry points: @main types, main.swift, and AppDelegate/SceneDelegate classes."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds application entry points: @main types, main.swift, and AppDelegate/SceneDelegate classes.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.
Message: `No application entry points discovered (@main, main.swift, AppDelegate).`; `Entry points:\n`.

**Notes.** Application entry points. See `assist-testing-tools.md` (Part B, "`entry_points_discover`").

## 207. `swift_migration_advisor` — Swift 6 Migration Advisor

- **Description (verbatim):** "Audits Swift code for Swift 6 strict concurrency compliance, mutable globals, actor boundaries, and Sendable conformance."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits Swift code for Swift 6 strict concurrency compliance, mutable globals, actor boundaries, and Sendable conformance.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to a Swift file or directory."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Swift 6 Migration Audit passed: All analyzed code in '\(path)' conforms to Swift 6 strict concurrency patterns.`; `Swift 6 Migration Advisor found \(warnings.count) migration opportunities across \(files.count) files in '\(path)':\n\n`.

**Notes.** Swift 6 migration audit. See `assist-testing-tools.md` (Part B, "`swift_migration_advisor`").

## 208. `memory_leak_detector` — Memory Leak Detector

- **Description (verbatim):** "Scans Swift source code for retain cycles, strong self capture in escaping closures, and unowned reference risks."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans Swift source code for retain cycles, strong self capture in escaping closures, and unowned reference risks.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to a Swift file or directory."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Memory Leak Scan passed: No retain cycles or strong self closure hazards detected across \(files.count) files in '\(raw)'.`; `Memory Leak Scan found \(findings.count) potential issues across \(files.count) files in '\(raw)':\n\n`.

**Notes.** Legacy is itself a static source scan (no Instruments/live process), so the port is fully static too. A clean scan means 'no matching patterns', not 'leak-free'. See `assist-testing-tools.md` (Part C, "`memory_leak_detector`").

## 209. `security_audit_scanner` — Security Audit Scanner

- **Description (verbatim):** "Scans Swift source files for hardcoded secrets, API keys, insecure HTTP endpoints, and unsafe storage practices."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans Swift source files for hardcoded secrets, API keys, insecure HTTP endpoints, and unsafe storage practices.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path to a directory or Swift file."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Security Audit passed: 0 vulnerabilities or hardcoded secrets found across \(files.count) files in '\(raw)'.`; `Security Audit flagged \(findings.count) items in '\(raw)':\n\n`.

**Notes.** Static security audit of the workspace. See `assist-testing-tools.md` (Part C, "`security_audit_scanner`").

## 210. `bundle_resource_auditor` — Bundle Resource Auditor

- **Description (verbatim):** "Audits project resources, asset catalogs, and bundle copy phases for missing or orphaned assets."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits project resources, asset catalogs, and bundle copy phases for missing or orphaned assets.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional directory path to scan. Defaults to workspace root."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** Declares `path` in Legacy but never reads it; the port keeps the schema and likewise ignores it. See `assist-testing-tools.md` (Part C, "`bundle_resource_auditor`").

## 211. `core_data_model_inspector` — Core Data Model Inspector

- **Description (verbatim):** "Locates, inspects, and parses Core Data .xcdatamodeld schemas, entities, attributes, and relationships."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Locates, inspects, and parses Core Data .xcdatamodeld schemas, entities, attributes, and relationships.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional path to the .xcdatamodeld bundle. If omitted, the workspace is scanned."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No .xcdatamodeld Core Data models found in the workspace.`; `Found model at \(modelURL.lastPathComponent), but contents XML was unreadable.`.

**Notes.** Inspects Core Data models. See `assist-testing-tools.md` (Part C, "`core_data_model_inspector`").

## 212. `swift_data_schema_auditor` — SwiftData Schema Auditor

- **Description (verbatim):** "Audits SwiftData models (@Model), attributes, relationships, and migration schemas across the workspace."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits SwiftData models (@Model), attributes, relationships, and migration schemas across the workspace.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional directory path to scan. Defaults to workspace root."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No SwiftData `@Model` classes discovered in the workspace.`.

**Notes.** Declares `path` in Legacy but never reads it; the port keeps the schema and likewise ignores it. See `assist-testing-tools.md` (Part C, "`swift_data_schema_auditor`").

## 213. `privacy_manifest_auditor` — Privacy Manifest Auditor

- **Description (verbatim):** "Audits or scaffolds Apple Privacy Manifests (PrivacyInfo.xcprivacy) for Required Reason API compliance."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Audits or scaffolds Apple Privacy Manifests (PrivacyInfo.xcprivacy) for Required Reason API compliance.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "action": {
      "type": "string",
      "description": "Action: 'audit' (scan codebase for API usage) or 'generate' (scaffold a valid PrivacyInfo.xcprivacy template)."
    }
  },
  "required": [
    "action"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Successfully generated compliant PrivacyInfo.xcprivacy at workspace root.`.

**Notes.** The only writer in this slice: the `generate` action writes `PrivacyInfo.xcprivacy` via `commit()`; `audit` writes nothing. See `assist-testing-tools.md` (Part C, "`privacy_manifest_auditor`").

## 214. `mach_o_binary_analyzer` — Mach-O Binary Analyzer

- **Description (verbatim):** "Inspects built application binaries, architectures (arm64, x86_64), and linked dynamic libraries via otool and file."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inspects built application binaries, architectures (arm64, x86_64), and linked dynamic libraries via otool and file.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "binaryPath": {
      "type": "string",
      "description": "Relative or absolute path to the compiled binary or executable file."
    }
  },
  "required": [
    "binaryPath"
  ]
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** Reuses Ycode's `YcodeMachO` (`MachOFile` / `MachOImage`) — no parallel parser. Reports parsed slices/dylibs instead of Legacy's `/usr/bin/file` + `xcrun otool` text. Fails on non-Mach-O files and 32-bit Mach-O binaries. See `assist-testing-tools.md` (Part C, "`mach_o_binary_analyzer`").

## 215. `framework_linker_auditor` — Framework Linker Auditor

- **Description (verbatim):** "Inspects PBXFrameworksBuildPhase in Xcode projects to audit linked system and dynamic frameworks."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inspects PBXFrameworksBuildPhase in Xcode projects to audit linked system and dynamic frameworks.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional path to .xcodeproj. Defaults to workspace root."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No project.pbxproj file found in workspace.`.

**Notes.** Declares `path` in Legacy but never reads it; the port keeps the schema and likewise ignores it. See `assist-testing-tools.md` (Part C, "`framework_linker_auditor`").

## 216. `network_security_auditor` — Network Security & ATS Auditor

- **Description (verbatim):** "Audits NSAppTransportSecurity in Info.plist for insecure HTTP and ATS exceptions."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits NSAppTransportSecurity in Info.plist for insecure HTTP and ATS exceptions.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional path to Info.plist. Defaults to searching workspace."
    }
  },
  "required": []
}
```

**Output (success).** No structured data keys (plain text result).
Message: `No valid Info.plist found in workspace.`; `✅ NSAppTransportSecurity is in default secure mode (all plain HTTP requests blocked, TLS 1.2+ required).`.

**Notes.** Static network-security audit. See `assist-testing-tools.md` (Part C, "`network_security_auditor`").

## 217. `accessibility_audit_scanner` — Accessibility Audit Scanner

- **Description (verbatim):** "Audits SwiftUI views for missing accessibility labels, hints, and VoiceOver tap targets."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits SwiftUI views for missing accessibility labels, hints, and VoiceOver tap targets.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Relative path to Swift file or directory."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** No structured data keys (plain text result).

**Notes.** Accessibility scan of the workspace. See `assist-testing-tools.md` (Part C, "`accessibility_audit_scanner`").

## 218. `license_header_check` — License Header Check

- **Description (verbatim):** "Checks the first 15 lines of each Swift file for required header text (default: "Copyright") and reports files missing it."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Checks the first 15 lines of each Swift file for required header text (default: \"Copyright\") and reports files missing it.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to check. Defaults to the workspace root."
    },
    "requiredText": {
      "type": "string",
      "description": "Header text that must appear in the first 15 lines. Case-insensitive. Default: \"Copyright\"."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `withHeader`, `missingHeader`, `missingFiles`.
Message: `License Header Check: no Swift files found.`; `License Header Check: scanned \(files.count) Swift file(s) for header text "\(requiredText)" in the first 15 lines — \(withHeader) with header, \(missing.count) missing.\n`.

**Notes.** License-header presence check. See `assist-testing-tools.md` (Part C, "`license_header_check`").

## 219. `access_level_audit` — Access Level Audit

- **Description (verbatim):** "Counts Swift declarations by access level (public, open, internal, private, fileprivate; default internal when unspecified) and lists the files with the most public API. Heuristic: access is inferred from keywords on the declaration line, with public/open taking precedence over private(set)."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Counts Swift declarations by access level (public, open, internal, private, fileprivate; default internal when unspecified) and lists the files with the most public API. Heuristic: access is inferred from keywords on the declaration line, with public/open taking precedence over private(set).",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to audit. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `public`, `open`, `internal`, `private`, `fileprivate`, `total`, `topPublicFiles`.
Message: `Access Level Audit: no Swift files found.`; `Access Level Audit: scanned \(files.count) Swift file(s), \(total) declaration(s) — public: \(counts["public"] ?? 0), open: \(counts["open"] ?? 0), internal: \(counts["internal"] ?? 0), private: \(counts["private"] ?? 0), fileprivate: \(counts["fileprivate"] ?? 0).\n`.

**Notes.** Access-level audit. See `assist-testing-tools.md` (Part C, "`access_level_audit`").

## 220. `binary_size_report` — Binary Size Report

- **Description (verbatim):** "Reports total size and the 10 largest files for each .app bundle under the workspace build directory or an explicit in-workspace path. DerivedData is never scanned."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reports total size and the 10 largest files for each .app bundle under the workspace build directory or an explicit in-workspace path. DerivedData is never scanned.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional workspace-relative path to a .app bundle or a directory to search for .app bundles. Default: build/."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `appCount`, `totalBytes`, `apps`.
Message: `No .app bundles found under '\(pathRaw)'. DerivedData is intentionally never scanned.`; `Binary size report: \(appBundles.count) .app bundle(s).`.

**Notes.** Fails when the path does not exist — it needs a built `.app` bundle, and the error says so. See `assist-testing-tools.md` (Part C, "`binary_size_report`").

## 221. `secrets_scan` — Secrets Scan

- **Description (verbatim):** "Scans source and config files for secret patterns. Reports file:line:pattern only and never outputs matched secret values."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Scans source and config files for secret patterns. Reports file:line:pattern only and never outputs matched secret values.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative directory or file to scan (optional)."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `finding_count`, `files_scanned`, `files_with_findings`.
Message: `Secrets scan: \(sorted.count) finding(s) in \(filesWithFindings.count) file(s), \(files.count) file(s) scanned.`.

**Notes.** Reports `file:line:label` only; secret values never appear in the output. See `assist-testing-tools.md` (Part C, "`secrets_scan`").

## 222. `permissions_audit` — Permissions Audit

- **Description (verbatim):** "Audits Info.plist usage descriptions, entitlements, and PrivacyInfo.xcprivacy entries, and flags API usage missing a usage description."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Audits Info.plist usage descriptions, entitlements, and PrivacyInfo.xcprivacy entries, and flags API usage missing a usage description.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `usage_description_count`, `entitlement_count`, `privacy_api_count`, `missing_count`, `privacy_tracking`.
Message: `Permissions audit complete.\n`.

**Notes.** Permissions audit. See `assist-testing-tools.md` (Part C, "`permissions_audit`").

## 223. `accessibility_audit` — Accessibility Audit

- **Description (verbatim):** "Heuristic SwiftUI accessibility audit: flags Button/Image without accessibility labels, TextField with empty labels, and color-only state."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Heuristic SwiftUI accessibility audit: flags Button/Image without accessibility labels, TextField with empty labels, and color-only state.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative directory or file to audit (optional)."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `finding_count`, `files_scanned`.
Message: `Accessibility audit: \(sorted.count) finding(s) in \(swiftFiles.count) Swift file(s). Findings are heuristics; verify each one.`.

**Notes.** Accessibility audit. See `assist-testing-tools.md` (Part C, "`accessibility_audit`").

## 224. `dependency_licenses` — Dependency Licenses

- **Description (verbatim):** "Inventories third-party dependencies from Package.resolved and Podfile.lock, reporting versions for license review."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inventories third-party dependencies from Package.resolved and Podfile.lock, reporting versions for license review.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.
Message: `No resolvable dependency lockfiles found (checked Package.resolved, Podfile.lock).`; `Dependency license inventory:\n\(table)\n\nNote: license text lives in each package's repository; verify before distribution.`.

**Notes.** Legacy's only non-`diagnostics` tool in this slice (`repositoryDiscovery`). See `assist-testing-tools.md` (Part C, "`dependency_licenses`").

## 225. `image_asset_size_report` — Image Asset Size Report

- **Description (verbatim):** "Reports oversized image files inside .xcassets catalogs — candidates for compression or vectorization."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reports oversized image files inside .xcassets catalogs — candidates for compression or vectorization.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "thresholdKB": {
      "type": "integer",
      "description": "Size threshold in KB. Default 500."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `imageCount`, `oversizedCount`, `totalBytes`.
Message: `No image files found inside .xcassets catalogs.`.

**Notes.** Image asset size report. See `assist-testing-tools.md` (Part C, "`image_asset_size_report`").

## 226. `api_docs_coverage` — API Docs Coverage

- **Description (verbatim):** "Measures the share of public/open Swift declarations that carry documentation comments."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Measures the share of public/open Swift declarations that carry documentation comments.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum undocumented symbols to list. Default 50."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `total`, `documented`, `coverage`.

**Notes.** API documentation coverage. See `assist-testing-tools.md` (Part D, "`api_docs_coverage`").

## 227. `api_endpoint_audit` — API Endpoint Audit

- **Description (verbatim):** "Inventories hardcoded http(s) URL literals in Swift sources, grouped by host — surfacing endpoints that should be configurable."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Inventories hardcoded http(s) URL literals in Swift sources, grouped by host — surfacing endpoints that should be configurable.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum URL sites. Default 100, max 500."
    }
  },
  "required": []
}
```

**Output (success).** No output schema declared; structured data keys: `count`, `hostCount`, `siteCount`.
Message: `No hardcoded http(s) endpoints found in Swift sources.`.

**Notes.** API endpoint audit. See `assist-testing-tools.md` (Part D, "`api_endpoint_audit`").

## 228. `api_surface_extract` — API Surface

- **Description (verbatim):** "Extracts public/open declarations (func, class, struct, enum, protocol, actor, var, let, typealias, extension) from Swift files, grouped by file, with file:line locations and a total count."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Extracts public/open declarations (func, class, struct, enum, protocol, actor, var, let, typealias, extension) from Swift files, grouped by file, with file:line locations and a total count.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of a file or directory to scan. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `scannedFiles`, `declarationCount`, `declarations`.
Message: `API Surface: no Swift files found.`; `API Surface: scanned \(files.count) Swift file(s), found \(total) public/open declaration(s) across \(grouped.count) file(s).\n`.

**Notes.** Private resolver, 1000-declaration cap; its pattern has no `init` kind, unlike `api_docs_coverage`. See `assist-testing-tools.md` (Part D, "`api_surface_extract`").

## 229. `automated_repair_engine` — Automated Repair Engine

- **Description (verbatim):** "Consumes compiler diagnostics, applies targeted fixes, and validates by rebuilding."
- **Capability:** `diagnostics`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Consumes compiler diagnostics, applies targeted fixes, and validates by rebuilding.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "errors": {
      "type": "string",
      "description": "Compiler diagnostic lines in 'path:line:...' format. Only lines containing '.swift:' are processed."
    }
  },
  "required": [
    "errors"
  ]
}
```

**Output (success).** Structured data keys: `fix_count`.
Message: `Applied \(fixed) automated repair annotations.`.

**Notes.** Deterministic annotation (`// AssistAutoRepair: review required` above the reported line), one `commit()` per file, re-reading per diagnostic as Legacy does. No rebuild — Legacy's `execute()` never rebuilds despite its description. See `assist-testing-tools.md` (Part D, "`automated_repair_engine`").

## 230. `autonomous_review_engine` — Autonomous Review Engine

- **Description (verbatim):** "Performs static self-review, detects inefficient patterns, and proposes refactors."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Performs static self-review, detects inefficient patterns, and proposes refactors.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative directory to review. Defaults to the workspace root."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `finding_count`, `findings`.
Message: `Autonomous review complete.`.

**Notes.** Three literal substring checks. See `assist-testing-tools.md` (Part D, "`autonomous_review_engine`").

## 231. `change_impact_estimate` — Change Impact Estimate

- **Description (verbatim):** "Estimates the blast radius of changing a file: finds Swift files that reference its base symbol name."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Estimates the blast radius of changing a file: finds Swift files that reference its base symbol name.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative path of the file to change."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum referencing files. Default 50."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `symbol`, `referencingFileCount`, `blastRadius`.

**Notes.** Change-impact estimate. See `assist-testing-tools.md` (Part D, "`change_impact_estimate`").

## 232. `code_review` — Code Review Validation

- **Description (verbatim):** "Validates the completed implementation using an independent AI reviewer stage before finishing the task."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Validates the completed implementation using an independent AI reviewer stage before finishing the task.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** None — the handler always fails (see Notes).

**Notes.** HONESTLY FAILING: registered with the full Legacy schema, then always fails naming the prerequisite — an LLM provider (Legacy sends task history, repo changes and build state to Apple Foundation Models or the configured provider and requires a JSON verdict with status `task_ready` / `task_failed`). Ycode's MCP host has no LLM wired for this tool. See `assist-testing-tools.md` (Part D, "`code_review`").

## 233. `code_snippet_manager` — Code Snippet & Architecture Template Manager

- **Description (verbatim):** "Retrieves and injects battle-tested Swift architecture templates (SwiftUI MVVM, AsyncStream, Actor isolation, Keychain wrapper)."
- **Capability:** `general`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Retrieves and injects battle-tested Swift architecture templates (SwiftUI MVVM, AsyncStream, Actor isolation, Keychain wrapper).",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "templateId": {
      "type": "string",
      "description": "Template identifier: 'observable_viewmodel', 'async_stream', 'keychain_helper', 'swiftui_glass_card', 'actor_service'."
    },
    "targetName": {
      "type": "string",
      "description": "Name of the type or feature to substitute in the template."
    }
  },
  "required": [
    "templateId"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `\(title)\n\n```swift\n\(snippet)\n````.

**Notes.** Four templates; `keychain_helper` fails as unknown, exactly as in Legacy (listed in its schema description but absent from its `switch`). See `assist-testing-tools.md` (Part D, "`code_snippet_manager`").

## 234. `color_usage_audit` — Color Usage Audit

- **Description (verbatim):** "Finds hardcoded colors in SwiftUI/UIKit code (Color(red:), UIColor literals, hex strings) that should live in the asset catalog."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds hardcoded colors in SwiftUI/UIKit code (Color(red:), UIColor literals, hex strings) that should live in the asset catalog.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum findings. Default 100, max 500."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.
Message: `No hardcoded colors found — colors appear to use named assets.`.

**Notes.** Color usage audit. See `assist-testing-tools.md` (Part D, "`color_usage_audit`").

## 235. `colorset_builder` — Color Set Builder

- **Description (verbatim):** "Creates or updates adaptive Light/Dark mode colorsets in Xcode asset catalogs."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Creates or updates adaptive Light/Dark mode colorsets in Xcode asset catalogs.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "catalogPath": {
      "type": "string",
      "description": "Relative path to the .xcassets directory."
    },
    "colorName": {
      "type": "string",
      "description": "Name of the color set (e.g. BrandPrimary, SurfaceElevated)."
    },
    "lightHex": {
      "type": "string",
      "description": "Hex color for Any/Light mode (e.g. #007AFF, #FFFFFF)."
    },
    "darkHex": {
      "type": "string",
      "description": "Hex color for Dark mode (e.g. #0A84FF, #1C1C1E)."
    }
  },
  "required": [
    "catalogPath",
    "colorName",
    "lightHex"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Successfully built adaptive ColorSet `\(colorName)` at: \(colorSetURL.path)\n- Light: \(lightHex)\n- Dark: \(darkHex)`.

**Notes.** Verbatim JSON templates; writes through `commit()`. See `assist-testing-tools.md` (Part D, "`colorset_builder`").

## 236. `docstring_generator` — DocC Documentation Generator

- **Description (verbatim):** "Generates Apple DocC compliant documentation comments (///) with Parameters, Returns, and Throws tags for Swift declarations."
- **Capability:** `fileModification`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Generates Apple DocC compliant documentation comments (///) with Parameters, Returns, and Throws tags for Swift declarations.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "declaration": {
      "type": "string",
      "description": "The Swift function, type, or protocol declaration header."
    },
    "summary": {
      "type": "string",
      "description": "Brief single-line summary of what the declaration does."
    }
  },
  "required": [
    "declaration"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Generated DocC Documentation:\n\n```swift\n\(result)\n````.

**Notes.** Returns generated docstrings as text; writes nothing (Legacy `safeRead`). See `assist-testing-tools.md` (Part D, "`docstring_generator`").

## 237. `icon_generator_tool` — App Icon Generator & Validator

- **Description (verbatim):** "Validates, configures, or scaffolds complete AppIcon.appiconset specifications in asset catalogs."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Validates, configures, or scaffolds complete AppIcon.appiconset specifications in asset catalogs.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "catalogPath": {
      "type": "string",
      "description": "Relative path to the .xcassets directory."
    },
    "action": {
      "type": "string",
      "description": "Action: 'validate' or 'scaffold'."
    }
  },
  "required": [
    "catalogPath",
    "action"
  ]
}
```

**Output (success).** No structured data keys (plain text result).
Message: `Successfully created universal AppIcon.appiconset at: \(iconSetURL.path)`; `AppIcon.appiconset audit for `\(catalogPath)`:\n- Total slots configured: \(images.count)\n- Rendered assets present: \(filledSlots)\n- Empty/unassigned slots: \(emptySlots)`.

**Notes.** Verbatim JSON templates; `writes: true` even for its read-only `validate` action (static flag, per the approval model). See `assist-testing-tools.md` (Part D, "`icon_generator_tool`").

## 238. `markdown_link_check` — Markdown Link Check

- **Description (verbatim):** "Validates links in Markdown files: internal file links must resolve; reports broken ones."
- **Capability:** `fileReading`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Validates links in Markdown files: internal file links must resolve; reports broken ones.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Optional workspace-relative Markdown file. Omit to check all Markdown files."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `checked`, `broken`.
Message: `All \(checked) internal links resolve.`.

**Notes.** Markdown link check. See `assist-testing-tools.md` (Part D, "`markdown_link_check`").

## 239. `markdown_toc_generate` — Markdown TOC Generate

- **Description (verbatim):** "Generates a table of contents from a Markdown file's headings and inserts or updates it between TOC markers."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Generates a table of contents from a Markdown file's headings and inserts or updates it between TOC markers.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative Markdown file."
    },
    "maxDepth": {
      "type": "integer",
      "description": "Heading depth to include. Default 3, max 6."
    }
  },
  "required": [
    "path"
  ]
}
```

**Output (success).** Structured data keys: `path`, `entryCount`.
Message: `Table of contents (\(entries.count) entries) written to \(raw).`.

**Notes.** Writes the table of contents through `commit()`. See `assist-testing-tools.md` (Part D, "`markdown_toc_generate`").

## 240. `readme_generate` — README Generate

- **Description (verbatim):** "Generates a README.md skeleton from real repository inspection: project name, build systems, targets, structure, and entry points."
- **Capability:** `fileModification`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Generates a README.md skeleton from real repository inspection: project name, build systems, targets, structure, and entry points.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative output path. Default: README.generated.md."
    },
    "overwrite": {
      "type": "boolean",
      "description": "Overwrite if the file exists. Default false."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `path`.
Message: `README skeleton written to \(rawPath).`.

**Notes.** Writes through `commit()`. See `assist-testing-tools.md` (Part D, "`readme_generate`").

## 241. `readme_locate` — Locate README

- **Description (verbatim):** "Finds README files in the workspace (any case/extension), reporting each path and its title line."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Finds README files in the workspace (any case/extension), reporting each path and its title line.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `count`.

**Notes.** Locates README files. See `assist-testing-tools.md` (Part D, "`readme_locate`").

## 242. `repo_overview` — Repository Overview

- **Description (verbatim):** "Summarizes the workspace repository: file counts by language, directory breadth, README/license presence, and largest files."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Summarizes the workspace repository: file counts by language, directory breadth, README/license presence, and largest files.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "topLanguages": {
      "type": "integer",
      "description": "How many top languages to report. Default 8."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `fileCount`, `totalBytes`, `readme`, `license`.

**Notes.** Repository overview. See `assist-testing-tools.md` (Part D, "`repo_overview`").

## 243. `safe_undo` — Undo Last Action

- **Description (verbatim):** "Reverts the last modification made by the agent."
- **Capability:** `general`. **Risk:** `potentiallyDestructive`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, destructive: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Reverts the last modification made by the agent.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** None — the handler always fails (see Notes).

**Notes.** HONESTLY FAILING: registered `potentiallyDestructive` / `writes: true`, then always fails naming the prerequisite — a workspace snapshot store (Legacy restores `AssistSnapshotFunctions` snapshot[1] and needs at least 2 snapshots). Ycode keeps no snapshots; `commit()` records no previous content, so there is nothing to restore. See `assist-testing-tools.md` (Part D, "`safe_undo`").

## 244. `safe_validate_changes` — Validate Changes

- **Description (verbatim):** "Verifies that the applied changes are correct and don't break functionality."
- **Capability:** `diagnostics`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Verifies that the applied changes are correct and don't break functionality.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "path": {
      "type": "string",
      "description": "Workspace-relative file or directory to validate. Default: \".\"."
    }
  },
  "required": []
}
```

**Output (success).** No output schema declared; structured data keys: `issue_count`, `issues`.
Message: `Changes validated successfully`; `Validation completed with \(issues.count) issue(s)`.

**Notes.** Validates pending changes; read-only. See `assist-testing-tools.md` (Part D, "`safe_validate_changes`").

## 245. `session_export` — Export Session

- **Description (verbatim):** "Writes a markdown export with session metadata (title, timestamp, session ID, workspace, notes). Does not read conversation history. Refuses to overwrite unless overwrite is true."
- **Capability:** `general`. **Risk:** `safeMutation`. **Required permission:** `fileSystem`. **Read-only:** no. **MCP annotations:** `readOnly: false, idempotent: true`. **`writes`:** `true`.

```json
{
  "type": "object",
  "description": "Writes a markdown export with session metadata (title, timestamp, session ID, workspace, notes). Does not read conversation history. Refuses to overwrite unless overwrite is true.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "title": {
      "type": "string",
      "description": "Export title (optional)."
    },
    "notes": {
      "type": "string",
      "description": "Free-form notes to include (optional)."
    },
    "outputPath": {
      "type": "string",
      "description": "Workspace-relative output path. Default is .assist_session_export.md."
    },
    "overwrite": {
      "type": "string",
      "description": "Set to true to overwrite an existing output file. Default is false."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `output_path`, `output_relative`, `session_id`, `timestamp`.
Message: `Session export written to \(outputRelative) (session \(sessionId)).`.

**Notes.** String-typed `overwrite`; the session ID is a deterministic UUID derived from the workspace root path (SHA-256) since Ycode has no agent-session UUID. See `assist-testing-tools.md` (Part D, "`session_export`").

## 246. `session_progress_report` — Session Progress Report

- **Description (verbatim):** "Summarizes the active agent session: engineering phases by status, failures, and the last agent-notes save time."
- **Capability:** `planning`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Summarizes the active agent session: engineering phases by status, failures, and the last agent-notes save time.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    }
  },
  "required": []
}
```

**Output (success).** Structured data keys: `phaseCount`, `completed`, `inProgress`, `failed`, `pending`.
Message: `No engineering phases are registered for this session.\n\(notesLine)`.

**Notes.** No phase coordinator in Ycode, so phase counts are always 0; the agent-notes line is real (mtime of workspace `agent_notes.md`). See `assist-testing-tools.md` (Part D, "`session_progress_report`").

## 247. `stale_files_report` — Stale Files Report

- **Description (verbatim):** "Reports source files not modified in a long time, surfacing potentially abandoned or legacy code."
- **Capability:** `repositoryDiscovery`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Reports source files not modified in a long time, surfacing potentially abandoned or legacy code.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "days": {
      "type": "integer",
      "description": "Staleness threshold in days. Default 180."
    },
    "limit": {
      "type": "integer",
      "description": "Maximum files to return. Default 50, max 500."
    }
  },
  "required": []
}
```

**Output (success).** No output schema declared; structured data keys: `count`, `days`.
Message: `No source files older than \(days) days.`.

**Notes.** Stale-files report. See `assist-testing-tools.md` (Part D, "`stale_files_report`").

## 248. `tool_capability_lookup` — Tool Capability Lookup

- **Description (verbatim):** "Looks up a registered tool's capability, risk level, description, and parameter schema from the live registry."
- **Capability:** `general`. **Risk:** `safeRead`. **Required permission:** `none`. **Read-only:** yes. **MCP annotations:** `readOnly: true, idempotent: true`. **`writes`:** `false`.

```json
{
  "type": "object",
  "description": "Looks up a registered tool's capability, risk level, description, and parameter schema from the live registry.",
  "properties": {
    "workspace": {
      "type": "string",
      "description": "Optional: the workspace to use (its path); opened when it is not the open one."
    },
    "toolId": {
      "type": "string",
      "description": "Registered tool id, e.g. repo_overview."
    }
  },
  "required": [
    "toolId"
  ]
}
```

**Output (success).** Structured data keys: `toolId`, `riskLevel`, `required`.

**Notes.** Looks up the live `server.tools` (resolving `MCPServer.toolAliases` first); capability and estimated cost are omitted (Ycode tools carry neither). See `assist-testing-tools.md` (Part D, "`tool_capability_lookup`").

## 249. Summary: capability / risk / permission / writes (Wave 6)

| Tool | Capability | Risk | Permission | Writes |
|---|---|---|---|---|
| `test_run_single` | testing | execution | none | no |
| `xctest_discovery` | diagnostics | safeRead | none | no |
| `test_log_parse` | testing | safeRead | none | no |
| `test_flaky_detect` | testing | safeRead | none | no |
| `test_coverage_report` | testing | execution | none | no |
| `test_coverage_reporter` | diagnostics | safeRead | none | no |
| `test_data_factory` | testing | safeMutation | fileSystem | yes |
| `test_snapshot_manage` | testing | safeMutation | fileSystem | yes |
| `test_target_add` | compilation | safeMutation | fileSystem | yes |
| `ui_test_scaffold` | testing | safeMutation | fileSystem | yes |
| `interface_simulator` | testing | safeRead | none | no |
| `preflight_checks` | diagnostics | safeRead | none | no |
| `performance_benchmark` | diagnostics | execution | none | no |
| `compiler_diagnostics_engine` | diagnostics | execution | none | no |
| `crash_log_parse` | diagnostics | safeRead | none | no |
| `runtime_diagnostics_engine` | diagnostics | safeRead | none | no |
| `code_lint` | diagnostics | safeRead | none | no |
| `swift_format_lint` | diagnostics | safeRead | none | no |
| `dead_code_scan` | diagnostics | safeRead | none | no |
| `dead_code_eliminator` | diagnostics | safeRead | none | no |
| `duplicate_code_scan` | diagnostics | safeRead | none | no |
| `unused_imports_detector` | diagnostics | safeRead | none | no |
| `import_cleanup` | fileModification | safeMutation | fileSystem | yes |
| `force_unwrap_scan` | diagnostics | safeRead | none | no |
| `todo_scan` | diagnostics | safeRead | none | no |
| `todo_fixme_scanner` | repositoryDiscovery | safeRead | none | no |
| `comment_density_report` | diagnostics | safeRead | none | no |
| `code_comment_extract` | fileReading | safeRead | none | no |
| `complexity_analysis` | diagnostics | safeRead | none | no |
| `function_size_report` | diagnostics | safeRead | none | no |
| `code_metrics_analyzer` | diagnostics | safeRead | none | no |
| `string_literal_audit` | diagnostics | safeRead | none | no |
| `deprecation_usage_scan` | diagnostics | safeRead | none | no |
| `swift_ast_inspector` | diagnostics | safeRead | none | no |
| `swift_concurrency_analyzer` | diagnostics | safeRead | none | no |
| `concurrency_audit` | diagnostics | safeRead | none | no |
| `entry_points_discover` | repositoryDiscovery | safeRead | none | no |
| `swift_migration_advisor` | diagnostics | safeRead | none | no |
| `memory_leak_detector` | diagnostics | safeRead | none | no |
| `security_audit_scanner` | diagnostics | safeRead | none | no |
| `bundle_resource_auditor` | diagnostics | safeRead | none | no |
| `core_data_model_inspector` | diagnostics | safeRead | none | no |
| `swift_data_schema_auditor` | diagnostics | safeRead | none | no |
| `privacy_manifest_auditor` | diagnostics | safeMutation | fileSystem | yes |
| `mach_o_binary_analyzer` | diagnostics | safeRead | none | no |
| `framework_linker_auditor` | diagnostics | safeRead | none | no |
| `network_security_auditor` | diagnostics | safeRead | none | no |
| `accessibility_audit_scanner` | diagnostics | safeRead | none | no |
| `license_header_check` | diagnostics | safeRead | none | no |
| `access_level_audit` | diagnostics | safeRead | none | no |
| `binary_size_report` | diagnostics | safeRead | none | no |
| `secrets_scan` | diagnostics | safeRead | none | no |
| `permissions_audit` | diagnostics | safeRead | none | no |
| `accessibility_audit` | diagnostics | safeRead | none | no |
| `dependency_licenses` | repositoryDiscovery | safeRead | none | no |
| `image_asset_size_report` | diagnostics | safeRead | none | no |
| `api_docs_coverage` | diagnostics | safeRead | none | no |
| `api_endpoint_audit` | diagnostics | safeRead | none | no |
| `api_surface_extract` | repositoryDiscovery | safeRead | none | no |
| `automated_repair_engine` | diagnostics | safeMutation | fileSystem | yes |
| `autonomous_review_engine` | diagnostics | safeRead | none | no |
| `change_impact_estimate` | diagnostics | safeRead | none | no |
| `code_review` | diagnostics | safeRead | none | no |
| `code_snippet_manager` | general | safeRead | none | no |
| `color_usage_audit` | diagnostics | safeRead | none | no |
| `colorset_builder` | fileModification | safeMutation | fileSystem | yes |
| `docstring_generator` | fileModification | safeRead | none | no |
| `icon_generator_tool` | fileModification | safeMutation | fileSystem | yes |
| `markdown_link_check` | fileReading | safeRead | none | no |
| `markdown_toc_generate` | fileModification | safeMutation | fileSystem | yes |
| `readme_generate` | fileModification | safeMutation | fileSystem | yes |
| `readme_locate` | repositoryDiscovery | safeRead | none | no |
| `repo_overview` | repositoryDiscovery | safeRead | none | no |
| `safe_undo` | general | potentiallyDestructive | fileSystem | yes |
| `safe_validate_changes` | diagnostics | safeRead | none | no |
| `session_export` | general | safeMutation | fileSystem | yes |
| `session_progress_report` | planning | safeRead | none | no |
| `stale_files_report` | repositoryDiscovery | safeRead | none | no |
| `tool_capability_lookup` | general | safeRead | none | no |

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
| Wave 3: all 16 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `search_text` / `search_symbol` are distinct from Ycode's `search` / `symbol_search` | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistCallHierarchyTool.swift`, `AssistCodeSummaryTool.swift`, `AssistDependencyGraphTool.swift`, `AssistImportGraphTool.swift`, `AssistProtocolConformanceListTool.swift`, `AssistRegexSearchTool.swift`, `search_skills.swift`, `AssistSymbolSearchTool.swift`, `AssistSearchTool.swift`, `AssistSemanticQueryEngine.swift`, `AssistSourceGraphBuilder.swift`, `AssistSymbolMoveFileTool.swift`, `AssistSymbolReferenceGraphTool.swift`, `AssistSymbolRenameProjectTool.swift`, `AssistTypeHierarchyTool.swift`, `AssistDataInspectionTools.swift` (`extract_code_symbols`), `AssistToolRegistry.swift` (register lines 83–87, 127–128, 144, 173, 245–246, 318, 332–335), read directly |
| Wave 3: registry aliases for this wave; `search` → `search_text` deliberately NOT carried over (collides with Ycode's `search`) | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table, read directly; Ycode `ycode/Sources/YcodeMCP/YcodeTools+Workspace.swift` (`search`), read directly |
| Wave 3: `semantic_query_engine` is a literal substring scan with `view` / `model` / `service` expansions, not an embedding/LLM search | 1 | Legacy `Tools/AssistSemanticQueryEngine.swift`, read directly |
| Wave 3: `symbol_rename_project` is whole-word textual replacement with no symbol index; `symbol_move_file` is brace-count extraction with verify-and-restore | 1 | Legacy `Tools/AssistSymbolRenameProjectTool.swift`, `Tools/AssistSymbolMoveFileTool.swift`, read directly |
| Wave 3: `search_skills` searches Legacy's `SkillIndex` (Application Support library); Ycode has no such catalogue — the port searches workspace skill files with Legacy's parsing and scoring | 1 | Legacy `Tools/search_skills.swift`, `SwiftCode/Core/AI/Agent/Skills/SkillIndex.swift`, read directly; Ycode `ycode/Sources/YcodeMCP/AgentSkill.swift`, read directly |
| Wave 3: scan rules (1 MB cap, binary extensions, skipped dirs, 300 KB / 800 KB caps) and the clamping vs strict path resolvers | 1 | Legacy `Functions/AssistSearchFunctions.swift`, `Tools/AssistToolSharedHelpers.swift` (`AssistWorkspaceScan`), `Tools/AssistToolingSupport.swift`, read directly |
| Wave 3 (Git): all 13 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `git_pr_summary` is local-only, `github_repo` honestly failing | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistConflictMarkerScanTool.swift`, `AssistGitBisectTool.swift`, `AssistGitBlameTool.swift`, `AssistGitBranchCompareTool.swift`, `AssistGitBranchManagerTool.swift`, `AssistGitCherryPickTool.swift`, `AssistGitConflictResolverTool.swift`, `AssistGitLogViewerTool.swift`, `AssistGitPRSummaryTool.swift`, `AssistGitStashTool.swift`, `AssistGitHubRepoTool.swift`, `AssistRecentChangesTool.swift`, `AssistVersionControlOperator.swift`, `AssistTool.swift` (capability/risk/permission defaults), `AssistToolRegistry.swift` (register lines 163, 177–180, 262–265, 389, 399; alias table lines 431–438, 505, 518–521), read directly |
| Wave 3 (Git): `git_bisect` `.execution` risk (rank 2, between safeMutation and potentiallyDestructive); `git_pr_summary` local-only; `github_repo` GitHub API + credential | 1 | Legacy `AssistGitBisectTool.swift:11`, `AssistToolRouter.swift:19–31`; `AssistGitPRSummaryTool.swift:6` and its `execute()` (four local git commands, no network); `AssistGitHubRepoTool.swift:37–44, 105+`, read directly |
| Wave 4 (Terminal): all 17 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `env_capture_logs`, `use_extension`, `use_composio`, `use_workers`, `take_screenrecord` honestly failing; `use_mcp` / `use_app` partial | 1 | Legacy `SwiftCode/Backend/Assist/Tools/UseTermFunction.swift`, `AssistTaskRunnerTool.swift`, `AssistLogCaptureTool.swift`, `AssistEnvironmentInfoTool.swift`, `UseMCP.swift`, `UseExtensionTool.swift`, `AssistComposioTool.swift`, `Subagents/Tools/UseWorkersTool.swift`, `AssistEnvironmentVariableManagerTool.swift`, `AssistClipboardManagerTool.swift`, `AssistProcessMonitorTool.swift`, `AssistDiskSpaceAnalyzerTool.swift`, `AssistSystemNotificationTool.swift`, `AssistSystemTool.swift`, `AssistTakeScreenshotTool.swift`, `AssistTakeScreenrecordTool.swift`, `AssistUseAppTool.swift`, `AssistToolRegistry.swift` (register lines 104, 108–113, 141, 207–211, 349, 393–395; alias table lines 430–556), read directly |
| Wave 4 (Terminal): `use_terminal` tokenize-to-argv, shell-metacharacter rejection, approval on every run, no allow-list / Full Access / Autopilot; `take_screenshot` writes despite Legacy `safeRead`; `use_system` sysctl allowlist, blocked global domain, read-back verification | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Terminal.swift`, `YcodeTools+TerminalSupport.swift`; Legacy `UseTermFunction.swift`, `AgentTerminalService`, `AssistSystemTool.swift`, read directly |
| Wave 4 (Memory): all 9 IDs, titles, descriptions, capabilities, risk levels, and input schemas; per-workspace stores (in-memory graph, `UserMemory.md`, `.assist_context_store.json`, conversation file) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistStoreMemoryTool.swift`, `AssistRetrieveMemoryTool.swift`, `AssistClearMemoryTool.swift`, `AssistContextSnapshotTool.swift`, `AssistContextPersistenceStore.swift`, `AssistSaveToMemoryTool.swift`, `AssistViewMemoryTool.swift`, `AssistManageMemoryTool.swift`, `AssistConversationContextTool.swift`, `AssistToolRegistry.swift` (register lines 122–125, 135, 167–170; alias table lines 507–511), read directly; Ycode `ycode/Sources/YcodeMCP/YcodeTools+Memory.swift`, `YcodeTools+MemorySupport.swift` |
| Wave 4 (Memory): Legacy's durable user memory is app-global and would leak across workspaces, so the port uses a per-workspace file in the same format; `mem_context_snapshot` latest snapshot is always `"none"` (no snapshot store) | 1 | Legacy `AssistMemoryGraph.swift`, `UserMemoryManager.swift` (`~/Library/Application Support/SwiftCode/UserMemory.md`), `AssistConversationHistory.swift`, `AssistSnapshotFunctions.swift`, read directly; Ycode `CodingAssistantModel.archiveURL(forWorkspace:)` (conversation archive, considered and rejected for memory) |
| Wave 4 (Planning): all 8 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `intel_autofix` honestly failing; `plan-AskUser` handoff, never blocking | 1 | Legacy `SwiftCode/Backend/Assist/Tools/ExecutionPlanTool.swift`, `AssistPlanTaskTool.swift`, `AssistBreakdownTaskTool.swift`, `AssistAutoFixErrorsTool.swift`, `AssistExplainCodeTool.swift`, `AssistGenerateTestsTool.swift`, `PlanAskUserTool.swift`, `ReportToUserTool.swift`, `AssistToolRegistry.swift` (register lines 116–120, 142–143, 147; alias table lines 484–491), `Functions/System Assets/ExecutionPlans.md`, `Resources/WriteExecutionPlan.md`, read directly |
| Wave 4 (Planning): `plan-AskUser` hyphenated ID is the documented intentional exception to snake_case; `execution_plan` honours documented lowercase `"plan"` / `"autopilot"` (Legacy's `rawValue` init only matches capitalised forms) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/validate_tools.py`; `AgentSessionState.swift:4-6` (`ExecutionMode` raw values `"Plan"` / `"Autopilot"`); `ExecutionPlanTool.swift:28-32` |
| Wave 4: registry aliases for this wave (terminal / memory / planning) | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table lines 430–556, read directly; Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`toolAliases`) |
| Wave 5 (Artboards): all 8 IDs, titles, descriptions, capabilities, risk levels, and input schemas; in-memory artboard store, PreviewRenderRunner compile, `run` delegation | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistArtboard{Compile,Create,Delete,Get,List,RunApp,Update}Tool.swift`, `AssistFixArtboardsTool.swift`, read directly; Ycode `ycode/Sources/YcodeMCP/YcodeTools+Artboards.swift`, `YcodePreviews/PreviewRenderRunner.swift` |
| Wave 5 (Simulator): all 4 IDs; `simulator_boot` / `simulator_list` aligned in place onto Ycode's existing registrations (Ycode Simulator behaviour unchanged, `simctl` behaviour added); `device_list` / `simulator_controller` new via `devicectl` / `simctl` subprocesses | 1 | Legacy `Tools/AssistDeviceListTool.swift`, `AssistSimulatorBootTool.swift`, `AssistSimulatorControllerTool.swift`, `AssistSimulatorListTool.swift`, read directly; Ycode `ycode/Sources/YcodeMCP/YcodeTools+Run.swift` (aligned), `YcodeTools+Simulator.swift` |
| Wave 5 (Image/Archive/Data): all 18 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `json_validate` vs `json_validator_tool` kept separate; YAML is Legacy's heuristic, not a full parser | 1 | Legacy `Tools/AssistImageInspectionTools.swift`, `AssistImageMutationTools.swift`, `AssistArchiveTools.swift`, `AssistBinaryPlistConverterTool.swift`, `AssistJsonValidateTool.swift`, `AssistJSONValidatorTool.swift`, `AssistYAMLParserTool.swift`, `AssistYamlValidateTool.swift`, read directly |
| Wave 5 (Engines/Web/Reverse): all 6 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `reverse_analyze` honestly failing (missing Node REA bridge) | 1 | Legacy `Tools/AssistCodeMutationEngine.swift`, `AssistDependencyResolutionEngine.swift`, `AssistExternalResourceGateway.swift`, `AssistPatchApplicationEngine.swift`, `AssistFetchDocumentationTool.swift`, `API/Internal API/Reverse/ReverseToolAdapter.swift`, read directly |
| Wave 5: registry aliases for this wave (`simulator` → `simulator_controller`, `binary_plist` → `binary_plist_converter`, `json_validator` → `json_validator_tool`, `yaml_parser` → `yaml_parser_tool`, `reverse` → `reverse_analyze`); `reverse_analyze` maps to itself, so it needs no entry | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table lines 430–556, read directly; Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`toolAliases`) |
| Wave 6 (Test running): all 16 IDs, titles, descriptions, capabilities, risk levels, and input schemas; runs through the session test seam (`discoverTests` / `runTests(only:)`), no `xcodebuild` spawn, no parallel runner | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistTestRunSingleTool.swift`, `AssistXctestDiscoveryTool.swift`, `AssistTestLogParseTool.swift`, `AssistTestFlakyDetectTool.swift`, `AssistTestCoverageReportTool.swift`, `AssistTestCoverageReporterTool.swift`, `AssistTestDataFactoryTool.swift`, `AssistTestSnapshotManageTool.swift`, `AssistTestTargetAddTool.swift`, `AssistUITestScaffoldTool.swift`, `AssistInterfaceSimulatorTool.swift`, `AssistPreflightChecksTool.swift`, `AssistPerformanceBenchmarkTool.swift`, `AssistCompilerDiagnosticsEngine.swift`, `AssistCrashLogParseTool.swift`, `AssistRuntimeDiagnosticsEngine.swift`, read directly; Ycode `ycode/Sources/YcodeMCP/YcodeTools+Testing.swift`, `YcodeBuild/TestResults.swift`, `YcodeXcodebuild/TestActions.swift`, `XCResultReader.swift`, `Coverage.swift` |
| Wave 6 (Static analysis): all 22 IDs, titles, descriptions, capabilities, risk levels, and input schemas; Legacy-faithful regex/line heuristics, no AST parser (`swift_ast_inspector` is the regex fallback only); `import_cleanup` the only writer | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistLintTool.swift`, `AssistSwiftFormatLintTool.swift`, `AssistDeadCodeScanTool.swift`, `AssistDeadCodeEliminatorTool.swift`, `AssistDuplicateCodeScanTool.swift`, `AssistUnusedImportsDetectorTool.swift`, `AssistImportCleanupTool.swift`, `AssistForceUnwrapScanTool.swift`, `AssistTodoScanTool.swift`, `AssistTodoFixmeScannerTool.swift`, `AssistCommentDensityReportTool.swift`, `AssistCodeCommentExtractTool.swift`, `AssistComplexityAnalysisTool.swift`, `AssistFunctionSizeReportTool.swift`, `AssistCodeMetricsTool.swift`, `AssistStringLiteralAuditTool.swift`, `AssistDeprecationUsageScanTool.swift`, `AssistSwiftASTInspectorTool.swift`, `AssistSwiftConcurrencyAnalyzerTool.swift`, `AssistConcurrencyAuditTool.swift`, `AssistEntryPointsDiscoverTool.swift`, `AssistMigrationTool.swift`, read directly |
| Wave 6 (Audits): all 18 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `mach_o_binary_analyzer` reuses Ycode's `YcodeMachO`; `memory_leak_detector` is a static scan, as in Legacy; `privacy_manifest_auditor` the only writer | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistSecurityAuditTool.swift`, `AssistNetworkSecurityAuditorTool.swift`, `AssistPermissionsAuditTool.swift`, `AssistPrivacyManifestAuditorTool.swift`, `AssistAccessibilityAuditTool.swift`, `AssistAccessibilityAuditScannerTool.swift`, `AssistAccessLevelAuditTool.swift`, `AssistDependencyLicensesTool.swift`, `AssistFrameworkLinkerAuditorTool.swift`, `AssistMemoryLeakDetectorTool.swift`, `AssistMachOBinaryAnalyzerTool.swift`, `AssistCoreDataModelInspectorTool.swift`, `AssistSwiftDataSchemaAuditorTool.swift`, `AssistBundleResourceAuditorTool.swift`, `AssistBinarySizeReportTool.swift`, `AssistImageAssetSizeReportTool.swift`, `AssistLicenseHeaderCheckTool.swift`, `AssistSecretsScanTool.swift`, read directly; Ycode `ycode/Sources/YcodeMCP/YcodeTools+Audits.swift`, `YcodeMachO` |
| Wave 6 (Docs/review): all 23 IDs, titles, descriptions, capabilities, risk levels, and input schemas; `code_review` and `safe_undo` honestly failing (LLM provider / snapshot store); `code_review` class verified live in `CodeReview.swift` | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistApiDocsCoverageTool.swift`, `AssistApiEndpointAuditTool.swift`, `AssistApiSurfaceExtractTool.swift`, `AssistAutomatedRepairEngine.swift`, `AssistAutonomousReviewEngine.swift`, `AssistChangeImpactEstimateTool.swift`, `CodeReview.swift`, `AssistCodeSnippetTool.swift`, `AssistColorUsageAuditTool.swift`, `AssistColorSetBuilderTool.swift`, `AssistDocStringGeneratorTool.swift`, `AssistIconGeneratorTool.swift`, `AssistMarkdownLinkCheckTool.swift`, `AssistMarkdownTocGenerateTool.swift`, `AssistReadmeGenerateTool.swift`, `AssistReadmeLocateTool.swift`, `AssistRepoOverviewTool.swift`, `AssistUndoTool.swift`, `AssistValidateChangesTool.swift`, `AssistSessionExportTool.swift`, `AssistSessionProgressReportTool.swift`, `AssistStaleFilesReportTool.swift`, `AssistToolCapabilityLookupTool.swift`, read directly |
| Wave 6: capability/risk/permission for all 79 tools extracted live from each Legacy tool file's `capability` / `riskLevel` properties (router static metadata agrees for the two tools it covers); permission follows the `AssistTool` default derivation (fileSystem iff mutating) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistTool.swift:192-198` (permission derivation); `AssistToolRouter.swift` static `metadata(for:)` (`code_review`, `compiler_diagnostics_engine` entries), read directly |
| Wave 6: registry aliases for this wave (23 entries) | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table, read directly; Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`toolAliases`) |
