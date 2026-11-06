# Assist search tools — behaviour (Wave 3, Search slice)

Ycode modules: `YcodeMCP` (the MCP server and its tools; the Wave 3
port registers the tools below there).

This spec covers the behaviour shared by the 16 Legacy Assist search
/ code-navigation tools ported into Ycode in Wave 3, plus the
per-tool behaviour that the catalogue
(`assist-tool-catalogue.md` §§54–69) does not repeat: the workspace
scan rules, the two path resolvers these tools use, the exact search
semantics, and the full error-case table. The catalogue is the single
source of truth for each tool's ID, title, description, input schema,
output shape, capability, risk level, permission, and read/write
classification; this spec is the single source of truth for how the
tools behave.

Scope: exactly these 16 tools, verified live from the Legacy
registry. No other tool is in scope for this slice, and no tool may
be invented, renamed, or merged with another — except the two
collisions handled in §1.6, which are documented, not merged.

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

## 1. Conventions shared by the search tools

### 1.1 The workspace scan

All 16 tools scan the workspace (the folder of the open workspace),
never the whole filesystem. Three scan shapes exist, one per Legacy
helper, and the port keeps them distinct:

- **`searchText` scan** (`search_text`, `search_regex`,
  `search_symbol`): Legacy's `AssistSearchFunctions.searchText`.
  Recursive enumeration with hidden files skipped; only regular
  files; files over 1 MB are skipped; files whose extension is in
  the binary set (`png`, `jpg`, `jpeg`, `gif`, `pdf`, `zip`, `exe`,
  `dylib`, `a`) are skipped; files that do not decode as UTF-8 are
  silently skipped. There is no skipped-directory rule and no
  per-file count cap. Matching lines are reported as
  `<line>: <text>` (1-based line numbers, original line text
  preserved including leading whitespace).
- **Source scan** (`call_hierarchy`, `import_graph`,
  `protocol_conformance_list`, `type_hierarchy`): Legacy's
  `AssistWorkspaceScan.files` / `swiftFiles`. Recursive enumeration
  with hidden files skipped; a file is skipped when the *first*
  path component relative to the root is a skipped directory
  (`.git`, `.build`, `build`, `DerivedData`, `.swiftpm`, `Pods`,
  `Carthage`, `node_modules`, `.venv`) — only the first component
  is checked, so a nested `.build` directory is not skipped.
  Directories are never returned. Default caps: 20,000 files
  (`files`), 8,000 Swift files (`swiftFiles`). Source extensions
  for `import_graph`: `swift`, `m`, `mm`, `h`, `c`, `cpp`, `hpp`.
- **Enumerated-files scan** (`code_summary`,
  `dependency_graph`, `semantic_query_engine`,
  `source_graph_builder`): Legacy's
  `AssistToolingSupport.enumeratedFiles`. Recursive enumeration with
  hidden files skipped; regular files only; files over
  `maxFileSize` are skipped (default 300,000 bytes;
  `semantic_query_engine` and `source_graph_builder` pass
  800,000). There is no skipped-directory rule.

All three scans read files as UTF-8 and silently skip files that do
not decode (the `searchText` scan and the enumerated-files scan) or
return no lines for them (the source scan's `readLines`).

### 1.2 Path resolvers

Two resolvers, matching the two Legacy shapes (see
`assist-file-writing-tools.md` §2 for the same split):

- **Clamping resolver** (`code_summary`, `dependency_graph`,
  `semantic_query_engine`, `source_graph_builder`): Legacy's
  `AssistToolingSupport.resolvePath`. An absent path means the
  workspace root. A path that would escape the workspace (via `..`
  or an absolute path) is silently replaced with the workspace
  root itself — never an error. These tools therefore never report
  an outside-workspace error for their `path` parameter.
- **Strict resolver** (`extract_code_symbols`,
  `symbol_move_file`, `symbol_rename_project`): Legacy's strict
  per-tool resolvers. Empty paths, NUL bytes, a leading `~`, and
  any `..` component are rejected; a leading `/` is a filesystem
  absolute path that must lie under the workspace root; anything
  else is relative to the workspace root (never the session
  working directory). A rejected path fails with the tool's own
  Legacy message (see §8). One narrowing: the Ycode strict
  resolver rejects a leading `~`, while Legacy's private
  resolvers for `symbol_move_file` / `symbol_rename_project`
  would have treated `~foo` as a relative path under the root; a
  `~`-leading path fails either way in practice, since no such
  file exists.

Tools with no `path` parameter (`call_hierarchy`, `import_graph`,
`protocol_conformance_list`, `search_regex`, `search_skills`,
`search_symbol`, `search_text`, `symbol_reference_graph`,
`type_hierarchy`) always scan the workspace root.

### 1.3 Result envelope

§1.1 of the catalogue applies unchanged: `success`, `output`
(the human-readable message in the exact formats given per tool),
`data` (all values strings in Legacy; typed JSON values — integers
and booleans — in the Ycode port, with Legacy's keys verbatim),
`error` / `errorCode` on failure, `filesChanged` only for the tools
that write files. Failure never returns partial `data`.

Two tools carry no structured data in Legacy
(`symbol_reference_graph`, `search_skills`) and return a plain text
result in the port. Two tools have two output shapes by branch
(`import_graph`, `type_hierarchy`); their output schemas declare
the union of both branches' keys with nothing required. One tool
(`call_hierarchy`) omits `calleeCount` from its not-found result;
its schema requires the other three keys.

### 1.4 Capability, risk, permission

All 16 tools follow the catalogue §1.2 derivation. 14 are
`safeRead` (read-only, `none` permission, annotations
`readOnly: true, idempotent: true`, `writes: false`). The two
mutating tools are `safeMutation` (`fileModification`,
`fileSystem` permission, annotations `readOnly: false,
idempotent: true`, `writes: true`):

| Write tool | Capability | Risk | What it writes |
|---|---|---|---|
| `symbol_move_file` | `fileModification` | `safeMutation` | The source file (declaration removed) and the destination file (declaration appended). |
| `symbol_rename_project` | `fileModification` | `safeMutation` | Every Swift file in scope that contains a whole-word occurrence of `oldName`. Only files that actually change are rewritten. |

### 1.5 Gate per tool

Every `writes: true` tool is gated by `MCPServer.run()` and its
handler-side shape — see `assist-approval-model.md` §6. In short:
each changed file goes through one `commit()` (full before/after
text shown to the reviewer), in order, stopping at the first
refusal; earlier files stay written (the Wave 2 multi-file shape,
as in `code_multi_edit`). `MCPServer.run` already refuses
`writes: true` tools when the server is read-only. There is no
Autopilot bypass.

`symbol_move_file` additionally verifies after both commits (the
declaration must be present in the destination and gone from the
source) and restores both files on verification failure — the
Legacy restore path, adapted to the gate: the restore is a direct
write undoing approved changes (net-zero), not a second approval.
If the destination commit fails after the source commit, the
source is restored the same way and the failure is reported, so a
refusal still leaves the workspace unchanged.

### 1.6 Collisions with Ycode's existing tools — no merging

Ycode's MCP server already has tools named `search` (workspace
text search, `YcodeTools+Workspace`) and `symbol_search` (symbol
documentation). Legacy's `search_text` and `search_symbol` are
**different tools with different IDs and schemas** and must not be
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
- Legacy's registry alias `search` → `search_text` is
  deliberately NOT carried over: it would collide with Ycode's
  existing `search`. The other aliases in §1.7 are carried over.

### 1.7 Aliases — accepted, but never canonical

The Legacy registry resolves these aliases to the canonical IDs.
The Ycode port accepts them at `tools/call` time (through
`MCPServer.toolAliases`, as Wave 1 did for `read_file`); the
canonical ID is what is registered, listed, and returned in
metadata:

- `search_dir`, `search_directory`, `find_file` → `search_text`
- `symbol_graph` → `symbol_reference_graph`

`search` → `search_text` is NOT an alias in Ycode (see §1.6).
No registry alias exists for `call_hierarchy`, `code_summary`,
`dependency_graph`, `extract_code_symbols`, `import_graph`,
`protocol_conformance_list`, `search_regex`, `search_skills`,
`search_symbol`, `semantic_query_engine`,
`source_graph_builder`, `symbol_move_file`,
`symbol_rename_project`, or `type_hierarchy`.

Per-tool parameter-name aliases (e.g. `search_symbol` accepting
`filePath`, `symbol_rename_project` accepting `old_name`) are
documented per tool in the catalogue where they exist. They are
leniency in parsing, not part of the schema — and, as in Wave 1–2,
they are NOT supported in the Ycode port: Ycode's argument
validation rejects unknown arguments before the handler runs.

## 2. `search_text` — plain-text search

Literal, case-insensitive substring search over the workspace
(`searchText` scan, §1.1). A line matches when it contains the
pattern (`localizedCaseInsensitiveContains`); every matching line
of a file is reported. Results are sorted by path (Legacy returned
a dictionary, whose order no caller could depend on; the port is
deterministic instead).

Output: message `Search results for '<pattern>':`, data key
`results` — one block per matching file, `"<rel>:\n"` followed by
its `<line>: <text>` lines, blocks joined with a blank line. No
matches is a success with an empty `results` string, not an error.

Error cases: a missing `pattern` fails with
`Missing required parameter: pattern`. An empty `pattern` is
accepted and matches every line (Legacy's
`localizedCaseInsensitiveContains("")` is true for every line) —
this is Legacy behaviour, preserved, not a bug to fix silently.
A regex is never compiled here: the pattern is literal even when
it contains regex metacharacters.

## 3. `search_regex` — regex search

Regular-expression search over the workspace (`searchText` scan
with `isRegex: true`, §1.1). The pattern is compiled once as a
case-insensitive `NSRegularExpression` and matched per line
(`firstMatch` per line; a line with several matches is reported
once). Results are sorted by path; each matching line is reported
as `"<rel>:<line>: <text>"`.

Output: message `Regex search completed for '<pattern>'`, data key
`results` — the matching lines joined with `\n` (empty string
when nothing matches).

Error cases: a missing `pattern` fails with
`Missing required parameter: pattern`. An invalid pattern fails
with `Regex search failed: <error>` — the compilation error is
reported, never a partial result.

## 4. `search_symbol` — symbol search

Four declaration regexes (the symbol escaped for regex) run over
the workspace, each through the `searchText` scan
(case-insensitive regex, §1.1):

1. `\b(class|struct|enum|protocol|actor|typealias|extension)\s+<symbol>\b`
2. `\bfunc\s+<symbol>\s*[\(\<]`
3. `\b(var|let)\s+<symbol>\s*[:=]`
4. `\bcase\s+<symbol>\b`

All matches from all four patterns are collected as
`"<rel>:<line>: <text>"`, deduped, and sorted. A pattern that
fails to compile is skipped (Legacy logs it and continues with
the other patterns).

Output: message `Symbol search completed for '<symbol>'`, data
key `results` — the deduped lines joined with `\n`. No matches
is a success with an empty `results` string.

Error cases: a missing `symbol` fails with
`Missing required parameter: symbol`. This is a text-pattern
search, not an index lookup: it finds declaration-shaped lines,
and it can miss declarations whose shape the four patterns do
not cover (e.g. `init`, or a declaration split across lines).

## 5. `extract_code_symbols` — extract declarations from one file

Reads one file and reports its top-level-ish declarations. Path
resolution is the strict resolver (§1.2). The file must decode
as UTF-8.

Per line (1-based), skipping lines whose trimmed form starts
with `//`, `/*`, or `*`: the first keyword contained in the line
wins, in this order: `class `, `struct `, `enum `,
`protocol `, `actor `, `func `, `extension `, `typealias `
(note: *contained*, not *prefixed* — a line mentioning a keyword
anywhere counts, and the kind is the first keyword in that list
order, not the first keyword in the line). The signature is the
line up to the first `{`, trimmed.

Output: message
`Extracted <N> declaration symbol(s) from \`<path>\`:` followed
by one line per symbol, `  • L<line>: [<kind>] <signature>`.
Data keys: `path` (as supplied), `symbolCount`. A file with no
declarations succeeds with `symbolCount` 0 and an empty symbol
list.

Error cases: a missing `path` fails with
`Missing required parameter: path`; a path outside the workspace
fails with `Path is outside the workspace: <path>`; a missing
file fails with `File not found at: <path>`; an undecodable file
fails with
`Failed to read and extract symbols from \`<path>\`: <error>`.

## 6. `call_hierarchy` — call hierarchy for a function

Scans Swift files (source scan, §1.1) for a function name. A
definition is a line whose declared function name (Legacy's
`declaredFuncName`: a `func ` line, name stripped of generics
and parameters) equals the requested name. A caller is any other
line matching `(?<![\w.])<fn>\s*\(` — a call not preceded by a
word character or `.` (so `obj.fn(` is not a caller, and neither
is a declaration line). Callees are the function names called
inside each definition body: brace-depth tracking from the
definition line, up to 400 lines, collecting
`(?<![\w.])([A-Za-z_][\w]*)\s*\(` matches, excluding the function
itself.

Output: message
`Call hierarchy for '<fn>':` followed by
`Definitions (<n>):` (at most 20, `- <rel>:<line>`),
`Callers (<n>):` (at most 50, with a
`… [truncated: showing 50 of <n>]` line when more),
`Callees (<n> distinct):` (at most 50, sorted). Data keys:
`function`, `definitionCount`, `callerCount`, `calleeCount`.
When neither a definition nor a caller exists, the message is
`No definition or callers found for function '<fn>'.` with data
`function`, `definitionCount` 0, `callerCount` 0 — and no
`calleeCount` key.

Error cases: a missing, empty, or whitespace-only `function`
fails with `Missing required parameter: function`. Brace counting
is heuristic (it does not parse strings or comments), so a `{`
inside a string literal shifts the callee scan exactly as it
does in Legacy.

## 7. `protocol_conformance_list` — conformers of a protocol

Scans Swift files (source scan, §1.1) with two regexes (the
protocol name escaped):

- Declaration: `^\s*(?:\w+\s+)*(class|struct|enum|actor)\s+([A-Za-z_][\w]*)\s*:[^\{]*\b<proto>\b`
- Extension: `^\s*extension\s+([A-Za-z_][\w]*)\s*:[^\{]*\b<proto>\b`

A declaration match reports `<Type> — <rel>:<line>`; an
extension match reports
`extension <Type> — <rel>:<line>`. Results are the two lists
concatenated and sorted.

Output: no conformances →
`No conformances to protocol '<proto>' found.` with data
`protocol`, `count` 0. Otherwise
`Conformances to '<proto>' (<n>):` followed by one `- <entry>`
line per conformance, with data `protocol`, `count`.

Error cases: a missing, empty, or whitespace-only `protocol`
fails with `Missing required parameter: protocol`. The match is
textual: a type whose inheritance clause merely mentions the
protocol name as a substring of a longer name does not match
(`\b` guards both ends), but a type conforming through a
typealias or a conditional conformance is not recognised.

## 8. `type_hierarchy` — type declarations and inheritance

Scans Swift files (source scan, §1.1) with the declaration
regex
`^\s*(?:public|private|internal|fileprivate|open)?\s*(?:final\s+)?(class|struct|enum|protocol|actor)\s+([A-Za-z_][\w]*)\s*(?::\s*([^\{]+))?`
— kind, name, and an optional `:` clause whose comma-separated
entries are the parents (superclass + protocols, in source
order). Later declarations of the same name overwrite earlier
ones.

Two modes:

- **No `type`:** lists every declaration, sorted by name, at
  most 200, as `- <kind> <name>[: <parents>] — <rel>:<line>`,
  with a `… [truncated: showing 200 of <n>]` line when more.
  Message `Type declarations (<n> total):`, data `typeCount`.
- **Focus `type`:** shows the type's kind and location, its
  parents (`- (none)` when there are none), and its subtypes —
  declarations whose parent list contains the focus name —
  as `- <name> (<kind>)`, sorted, with `Subtypes (<n>):` and
  `- (none)` when there are none. Data keys: `type`,
  `childCount`.

Error cases: a focus type that is not declared fails with
`Type '<focus>' not found in workspace Swift sources.` An empty
or whitespace-only `type` is treated as no focus (the full
listing).

## 9. `symbol_reference_graph` — all sites for a symbol

Recursive enumeration of the workspace (hidden files and package
descendants skipped; `.swift` files only; UTF-8 only). A file is
examined only when its whole text contains the symbol
(case-sensitive substring). Every line containing the symbol is
reported; a line is a *declaration* when its trimmed form starts
with `func <symbol>`, `class <symbol>`, `struct <symbol>`,
`enum <symbol>`, `protocol <symbol>`, `actor <symbol>`,
`var <symbol>`, or `let <symbol>` — note the prefix must be at
the start of the trimmed line, so `public struct Foo` is *not*
counted as a declaration. Collection stops at `maxResults`
(default 50; a value ≤ 0 still yields one match, as in Legacy —
the stop check runs after the first append).

Output: no matches →
`No references found for symbol '<symbol>' in workspace.`
(no structured data). Otherwise a Markdown report:
`### Symbol Reference Graph for \`<symbol>\` (<n> sites found):`
followed by a `#### Declarations:` section (only when there are
declarations) and a `#### Usages & Call Sites:` section with at
most 40 usages, each line
`- \`<rel>:<line>\` → \`<trimmed line>\``. No structured data is
returned in either case.

Error cases: a missing, empty, or whitespace-only `symbol` fails
with `Missing required parameter: symbol`. Enumeration order is
filesystem order (Legacy enumerates the same way); the report
does not sort matches.

## 10. `code_summary` — summary of a file or directory

Path resolution is the clamping resolver (§1.2): an escaping
path silently becomes the workspace root.

- **Directory:** counts the files under it
  (`enumeratedFiles`, default 300 KB cap, §1.1) and how many of
  those are code files (extension in `swift`, `m`, `mm`, `h`,
  `hpp`, `c`, `cpp`, `js`, `ts`, `tsx`, `jsx`, `py`, `rb`,
  `java`, `kt`, `go`, `rs`). Data key `summary`:
  `Directory <path>: <n> files, <m> code files`.
- **File:** the file must decode as UTF-8. Lines are split on
  newlines — a trailing newline counts as one more line (the
  `.newlines` split, unlike `file_read`, which strips the phantom
  line). Non-empty lines are those with non-whitespace content;
  comment lines are those whose trimmed form starts with `//`
  (only `//` — `/*` and `*` do not count here). Data key
  `summary`:
  `File <path>: <lines> lines (<nonEmpty> non-empty), <commentLines> comment lines`.

Both branches report the message `Summary for <path>` (the path
as supplied).

Error cases: a missing `path` fails with
`Missing required parameter: path`; a path that does not exist
fails with `Path does not exist: <path>`; a file that is not
readable as UTF-8 text fails with
`File at <path> is not readable as UTF-8 text`.

## 11. `dependency_graph` — Swift import graph

Scans `.swift` files under the scope directory
(`enumeratedFiles`, 300 KB cap, §1.1) and extracts imports with
the regex `^\s*import\s+([A-Za-z0-9_\.]+)` (multiline anchors).
Nodes are the source files' workspace-relative paths plus every
imported module name; edges are `<source> -> <module>`.

Output: message
`Dependency graph generated for <n> files.` Data keys:
`node_count`, `edge_count`, `nodes` (sorted, joined with `", "`),
`edges` (sorted, joined with `\n`). A file with no imports is
still a node. `@testable import X` does not match the regex
(it requires the line to start with `import`), so testable
imports are not edges — exactly as in Legacy.

Error cases: none beyond the path rules — an empty scope yields
an empty graph, not an error. The `path` parameter is optional
and defaults to the workspace root.

## 12. `import_graph` — file-level import graph

Scans source files (source scan, §1.1) and extracts imports
with the per-line regex `^\s*import\s+([A-Za-z_][\w.]*)`.
Two modes:

- **With `module`:** lists the files importing that module,
  sorted and deduplicated, at most `limit` (default 200, clamped
  to 1…2000). Message `Files importing '<module>' (<n>):`
  followed by `- <rel>` lines. Data keys: `module`,
  `fileCount` (the full count, even when the listing is capped).
- **Without `module`:** the 30 most-imported modules as
  `- <module>: <n> files` (ties in unspecified order), then
  `Import edges (<total> total, showing <shown>):` followed by
  at most `limit` `- <rel> -> <module>` lines in scan order.
  Data keys: `edgeCount`, `moduleCount`.

`@testable import X` does not match the regex (see §11).
`limit` is clamped to 1…2000; a non-integer limit behaves as
the default 200.

## 13. `source_graph_builder` — source relationship graph

Scans `.swift` files under the scope directory
(`enumeratedFiles`, 800 KB cap, §1.1). Three regexes run over
each file's whole text:

- Symbols: `\b(class|struct|enum|protocol|func)\s+([A-Za-z_][A-Za-z0-9_]*)`
  → nodes `<kind>:<name>` and relationships
  `<rel> -> <kind>:<name>`.
- Imports: `^\s*import\s+([A-Za-z0-9_\.]+)` (multiline anchors)
  → nodes `module:<module>` and relationships
  `<rel> -> module:<module>`.
- Type uses: `\b([A-Z][A-Za-z0-9_]*)\b` → relationships
  `<rel> -> type:<Name>`, excluding names the file itself
  declares (its own symbols are not "uses").

Nodes also include every scanned file's workspace-relative path.
Relationships are kept in scan order with duplicates (a type used
twice in one file appears twice); the reported list is capped at
2000 entries, but `relationship_count` is the full count.

Output: message `Built source graph for <n> Swift files.` Data
keys: `file_count`, `node_count`, `relationship_count`,
`imports` (sorted modules, joined with `,` — no space),
`relationships` (first 2000, joined with `\n`).

Error cases: a scope path that does not exist fails with
`Path does not exist: <absolute path>` (the resolved absolute
path, not the path as supplied). The `path` parameter is
optional and defaults to the workspace root.

## 14. `semantic_query_engine` — keyword query with shortcuts

Despite the name, this tool performs **no** embedding or LLM
semantic search — in Legacy or in this port. It is a
case-insensitive substring scan over `.swift` files under the
scope directory (`enumeratedFiles`, 800 KB cap, §1.1), with
three keyword expansions:

- `view`: a line also matches when it contains `: View`
  (a SwiftUI view declaration).
- `model`: a line also matches when it contains `struct` or
  `class` *and* its lowercase form contains `model` or
  `viewmodel`.
- `service`: a line also matches when its lowercase form
  contains `service`.

A matching line is reported with one line of context on each
side (clamped to the file): `"<rel>::<line>::<n-1>: <prev> |
<n>: <line> | <n+1>: <next>"` (the context lines are omitted at
the file edges). The query itself is matched case-insensitively
against every line regardless of the shortcuts.

Output: message `Semantic query returned <n> matches.` Data key
`matches` — the first 1500 hits joined with `\n` (the message
count is the full count, even when the list is capped).

Error cases: a missing, empty, or whitespace-only `query` fails
with `Missing required parameter: query`. Path resolution is the
clamping resolver (§1.2); `path` is optional and defaults to the
workspace root.

## 15. `search_skills` — search the workspace skills library

Searches the workspace's local skills library: `SKILL.md` /
`SKILLS.md` / `*.SKILL.md` / `*.SKILLS.md` files anywhere under
the workspace (including hidden directories such as
`.claude/skills/` — Ycode's own skill lives there), one skill per
containing directory. There is no Application Support library, no
enable/disable toggle, and no disk cache in the port: Legacy's
`SkillIndex` indexed `~/Library/Application Support/SwiftCode/Skills/`
plus imported Claude/Codex/VSCode/Antigravity libraries, which
Ycode does not have. The port searches the skill surface Ycode
actually has — the workspace's own skill files — and must not
invent a skills database.

Metadata parsing mirrors Legacy's `SkillIndex.parseSkillMetadata`:
YAML frontmatter between `---` markers (`name:`,
`description:`, `tags:`, `tools:`, `source:`), a `metadata.json`
sidecar in the skill directory (which overrides frontmatter),
and a fallback to the leading `# ` heading and first
non-heading line. The skill ID is the containing directory's
name, lowercased, with spaces and underscores turned into
hyphens. The source defaults to `Ycode` ("Ycode Workspace
Skills"); a path under `.claude/skills/` defaults to `Claude`
("Claude Skills"), under `.agents/skills/` to `Project`
("Project Skills"); a frontmatter `source:` overrides with the
same mapping Legacy uses (claude / codex / vscode / antigravity
/ project / user).

Scoring mirrors Legacy exactly: exact name match +100, name
contains the whole query +50, per token name +20, description
+10, tag contains +15, searchable text (name + description +
tags + first 2000 characters of the file) +5. Results are
highest score first, at most `limit` (default 8, clamped to
1…20).

Output: no matches →
`No skills found matching query '<query>'. You can continue executing the task using standard engineering principles.`
(no structured data). Otherwise:
`### Discovered Skills Matching '<query>' (<n> results):`
followed by one numbered block per skill (`**<name>** (\`<id>\`)`,
`Source`, `Location`, `Description`, `Tags` when present,
`Tools` when present, and a line pointing at `file_read` on the
skill's path), and a closing guidance line. The `Location` is
the skill file's absolute path. The guidance lines point at
`file_read` (Ycode's canonical name) rather than Legacy's
`read_file` alias. No structured data is returned.

Error cases: a missing, empty, or whitespace-only `query` fails
with `Missing required parameter 'query'.` (with quotes and a
period, exactly as in Legacy).

## 16. `symbol_move_file` — move one declaration between files

Moves one top-level Swift declaration from a source file to a
destination file. Path resolution is the strict resolver (§1.2)
for both paths. Validation, in Legacy's order:

1. `symbol`, `sourcePath`, `destinationPath` must be present and
   non-empty (`Missing required parameter: <name>`).
2. `symbol` must be a valid identifier — letters, digits, and
   underscores only, not starting with a digit
   (`Invalid symbol '<symbol>': identifiers may contain only letters, digits, and underscores, and must not start with a digit.`).
3. Both paths must resolve inside the workspace
   (`Invalid sourcePath: path must stay inside the workspace and must not contain '..'.` — same for `destinationPath`).
4. The two paths must differ
   (`Refusing move: sourcePath and destinationPath must differ.`).
5. Both files must read as UTF-8
   (`Could not read source file at <rel>.` /
   `Could not read destination file at <rel>.`).
6. The destination must not already declare the symbol
   (`Refusing move: destination already declares '<symbol>'.`).
7. The declaration must be found in the source
   (`Symbol '<symbol>' declaration not found in <rel>.`).

The declaration is the first line matching
`\b(func|class|struct|enum|protocol|actor|var|let|typealias)\s+<symbol>\b`.
Its block is extracted by brace counting (Legacy's heuristic:
braces are counted per line, strings and comments are not
parsed; at most 500 lines from the declaration; if no opening
brace appears within 20 lines, a `var` / `let` / `typealias`
moves as a single line, anything else fails with
`Move failed: could not find the opening brace for '<symbol>' (<kind>) within 20 lines of its declaration.`;
an unbalanced block fails with
`Move failed: declaration block for '<symbol>' is unbalanced or exceeds 500 lines.`).
The block is removed from the source and appended to the
destination (a blank line is added first; a missing trailing
newline on the destination is added).

Gate: one `commit()` per file, source first, then destination
(see §1.5). After both commits the tool verifies the declaration
is present in the destination and gone from the source; on
failure both files are restored and the tool fails with
`Move verification failed (still in source: <bool>, in destination: <bool>). Original contents were restored.`

Output: message
`Moved symbol '<symbol>' (<kind>, <n> line(s)) from <sourceRel> to <destinationRel>.`
Data keys: `symbol`, `kind`, `sourcePath`, `destinationPath`,
`movedLines`.

## 17. `symbol_rename_project` — whole-word rename across Swift files

Renames a symbol across Swift files by whole-word text
replacement. **This is a textual rename, not a semantic rename:**
it has no Swift symbol index, so it renames every whole-word
occurrence of `oldName` — including occurrences in comments,
strings, and unrelated declarations that happen to share the
name. Callers that need a semantic rename must use a real
refactoring engine; this tool must never be described as one.

Path resolution is the strict resolver (§1.2) for the optional
`path` scope (absent or empty means the workspace root). The
scope is either a single `.swift` file (≤ 300 KB) or a directory
walked recursively (hidden files are NOT skipped; `.git`,
`DerivedData`, `.build`, `Pods`, and `node_modules` directories
are pruned; `.swift` files only; ≤ 300 KB each; at most 5000
files; sorted by path).

Validation, in Legacy's order: `oldName` / `newName` present and
non-empty; both valid identifiers (same rule as §16);
`oldName != newName`
(`Refusing rename: oldName and newName are identical ('<oldName>').`);
the scope path must resolve inside the workspace
(`Invalid path: path must stay inside the workspace and must not contain '..'.`).

Each file containing at least one whole-word occurrence
(`\b<oldName>\b`, case-sensitive) is rewritten with all
occurrences replaced. Only files that actually change are
rewritten. Gate: one `commit()` per changed file, in enumeration
order, stopping at the first refusal; earlier files stay renamed
(the Wave 2 multi-file shape, §1.5).

Output: no Swift files in scope →
`Rename Symbol: no Swift files found.` with data `filesChanged`
`""`, `replacementCount` 0, `changedFileCount` 0. No occurrences
→
`Rename Symbol: no whole-word occurrences of '<oldName>' found in <n> Swift file(s). Nothing changed.`
with the same zero data. Otherwise
`Rename Symbol: replaced <total> whole-word occurrence(s) of '<oldName>' with '<newName>' across <n> file(s):`
followed by `- <rel>` lines, with data `filesChanged` (the
changed paths, newline-joined — a string, as in Legacy),
`replacementCount`, `changedFileCount`.

## 18. Error cases — summary table

| Case | Message |
|---|---|
| Missing required argument (any tool) | `Missing required parameter: <name>` (except `search_skills`, whose query failure is `Missing required parameter 'query'.`) |
| Blank `function` / `protocol` / `symbol` / `query` (where trimmed) | `Missing required parameter: <name>` |
| `search_text` failure (scan throws) | `Search failed: <error>` |
| `search_regex` invalid pattern | `Regex search failed: <error>` |
| `extract_code_symbols` outside workspace | `Path is outside the workspace: <path>` |
| `extract_code_symbols` missing file | `File not found at: <path>` |
| `extract_code_symbols` undecodable file | `` Failed to read and extract symbols from `<path>`: <error> `` |
| `code_summary` missing path | `Path does not exist: <path>` |
| `code_summary` undecodable file | `File at <path> is not readable as UTF-8 text` |
| `source_graph_builder` missing scope | `Path does not exist: <absolute path>` |
| `type_hierarchy` unknown focus type | `Type '<focus>' not found in workspace Swift sources.` |
| `symbol_move_file` invalid identifier | `Invalid symbol '<symbol>': identifiers may contain only letters, digits, and underscores, and must not start with a digit.` |
| `symbol_move_file` bad path | `Invalid sourcePath: path must stay inside the workspace and must not contain '..'.` (same for `destinationPath`) |
| `symbol_move_file` same paths | `Refusing move: sourcePath and destinationPath must differ.` |
| `symbol_move_file` unreadable file | `Could not read source file at <rel>.` (same for destination) |
| `symbol_move_file` destination declares symbol | `Refusing move: destination already declares '<symbol>'.` |
| `symbol_move_file` symbol not found | `Symbol '<symbol>' declaration not found in <rel>.` |
| `symbol_move_file` unbalanced block | `Move failed: declaration block for '<symbol>' is unbalanced or exceeds 500 lines.` |
| `symbol_move_file` no opening brace | `Move failed: could not find the opening brace for '<symbol>' (<kind>) within 20 lines of its declaration.` |
| `symbol_move_file` verification failure | `Move verification failed (still in source: <bool>, in destination: <bool>). Original contents were restored.` |
| `symbol_rename_project` invalid identifier | `Invalid oldName '<name>': …` (same for `newName`) |
| `symbol_rename_project` identical names | `Refusing rename: oldName and newName are identical ('<name>').` |
| `symbol_rename_project` bad scope path | `Invalid path: path must stay inside the workspace and must not contain '..'.` |
| Approval refused (either mutating tool) | The server's rejection message; files approved before the refusal stay changed (see §1.5). |
| Read-only server (either mutating tool) | Refused by `MCPServer.run` before the handler runs. |

`..` escapes are errors for the strict-resolver tools and
silently clamped to the workspace root for the clamping-resolver
tools (§1.2) — the two behaviours are Legacy's, preserved
separately, not unified.

## Git tools

Behaviour shared by the 13 Git tools ported in Wave 3 (`conflict_marker_scan`, `git_bisect`, `git_blame_inspector`, `git_branch_compare`, `git_branch_manager`, `git_cherry_pick`, `git_conflict_resolver`, `git_log_viewer`, `git_pr_summary`, `git_stash_operator`, `github_repo`, `recent_changes`, `version_control_operator`). See `assist-tool-catalogue.md` §71–§85 for each tool's ID, schema, capability/risk/permission, and gate.

#### Git safety rules (non-negotiable)

- **Workspace-confined only.** Every git operation runs with the workspace folder as its working directory, and git discovers the repository upward from there. Every path argument resolves with `resolveFileReadingPath` (plain relative paths against the session working directory; `..` past the workspace root is an error, never a clamp). `git_conflict_resolver` does **not** reproduce Legacy's absolute-path carve-out: a leading-`/` path is workspace-root-relative (or an absolute path inside the workspace), never a raw filesystem path outside it.
- **Argument vector, never a shell.** Git is run via `YcodeSubprocess` with an explicit argument array (`HostTool.path("git")`). No command string is ever assembled, so shell metacharacters in a branch, ref, message, or path cannot inject a command — but arguments are still validated, because a leading `-` could be parsed as a git flag.
- **No remotes, no GitHub.** There is no push/pull/fetch/clone and no GitHub API call in this wave. `version_control_operator` rejects `push`/`pull`/`fetch`/`clone` with an explicit error naming the later-wave prerequisite. `github_repo` is registered but honestly failing (see catalogue §71.4). `git_pr_summary` is local-only by design.
- **No destructive git operation without the Wave 2 approval gate.** Anything that mutates history, the working tree, or the index (bisect steps other than `log`, branch create/switch/delete, cherry-pick, conflict-resolution writes, stash save/pop/drop, `version_control_operator` commit/branch/rollback) goes through `commit()` (text resolution) or an explicit `MCPChange` + `call.approve()` (every other mutation) **before** git runs, and the tool is registered `writes: true` so `MCPServer.run` refuses it in `readOnly` server mode. Read-only operations (`log`, `blame`, branch list/compare, status/diff read, conflict-marker scan, `recent_changes`, `git_pr_summary`) are `writes: false` — except the read-only actions of a writing tool, which request no approval but are still refused in `readOnly` mode (catalogue §71.3).
- **Never fake git output.** If `git` cannot start, the tool fails with `Failed to launch git: <reason>`. If the workspace is not a git repository, the tool fails with git's own "not a git repository" message. Non-zero git exits are reported with git's own merged stdout+stderr text, never invented log/blame/status content.
- **The git environment never waits for a person.** Every git command runs with `GIT_TERMINAL_PROMPT=0`, `GIT_PAGER=cat`, `GIT_EDITOR=true`, `GIT_SEQUENCE_EDITOR=true`, `GIT_MERGE_AUTOEDIT=no`, `GIT_ASKPASS=true`, `SSH_ASKPASS_REQUIRE=never`, `GCM_INTERACTIVE=never`, and `GIT_OPTIONAL_LOCKS=0` (so reads never rewrite the index), and with the `GIT_DIR` / `GIT_WORK_TREE` / `GIT_INDEX_FILE` / `GIT_CEILING_DIRECTORIES` family stripped, so nothing can point git at another repository. This mirrors `GitRepository.environment`.

#### Behaviour

- **One runner.** All git operations go through a single runner (`runGit` in `YcodeTools+Git.swift`): `Subprocess.run` with the `git` executable, the argument vector, the environment above, and the workspace folder as the working directory. It throws only when git cannot start; a non-zero exit is returned with its status and output, so each tool reports git's own message. Ycode's `GitRepository` seams were not used as the implementation path: their return types (Ref lists, status maps, parsed blame commits without line text) do not reproduce Legacy's verbatim git output, `GitRepository.resolveConflict` also stages the file while Legacy only writes it, and most operations (bisect, cherry-pick, stash, `log` with a format, `diff --stat`) have no seam method at all.
- **Ref validation (Legacy's shared validator).** `git_bisect` refs, `git_branch_compare` base/head, `git_pr_summary` base/head, and `git_cherry_pick` commits use Legacy's `isValidRef`: `HEAD` and `HEAD~N` / `HEAD^N` forms pass; anything with a space, shell metacharacter (`; & | \` $ ( ) < > " ' \`), `..`, `~`, `^`, `:`, `?`, `*`, `[`, a leading `-`, `@{`, a leading/trailing `/`, or `//` fails. `git_cherry_pick` additionally accepts a 7–40 hex SHA. Branch names and rollback refs (`git_branch_manager`, `version_control_operator`) use the stricter allow-list from Legacy's `version_control_operator`: letters, digits, `.` `_` `/` `-`, plus the `HEAD` / `HEAD[~^]N` forms; at most 256 characters; no `..`, no leading/trailing `/`, no `.lock` suffix, no leading `-` or `.`. Stash identifiers (`git_stash_operator` pop/show/drop) must be `stash@{N}` or a plain number.
- **Filesystem scans (`conflict_marker_scan`, `recent_changes`).** Both use Legacy's `AssistWorkspaceScan.files` rules: hidden files skipped; top-level `.git`, `.build`, `build`, `DerivedData`, `.swiftpm`, `Pods`, `Carthage`, `node_modules`, `.venv` skipped (only the first path component is checked, so a nested `build` directory is *not* skipped — reproduced as-is); at most 20,000 files. `conflict_marker_scan` additionally filters to source extensions (`swift`, `m`, `mm`, `h`, `c`, `cpp`, `hpp`) and skips files that do not decode as UTF-8. Neither tool needs a git repository.
- **Blame is two git runs.** `git_blame_inspector` runs `git blame --porcelain` first (its failure is the tool's failure), then `git blame -s` for the readable snippet that becomes the message (at most 50 lines). The `-L` range rules differ between the runs: porcelain takes a full range or a lone start line (`start,start+30`); the readable run takes only a full range. The output is the `-s` rendering (short hash, line number, line text — no author name). A failure of the readable run is ignored, as in Legacy.
- **Cherry-pick stops, never finishes.** On failure, `git_cherry_pick` re-reads `git status --porcelain` and, when unmerged paths are present (codes `DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU`), reports them and leaves the cherry-pick stopped for manual resolution. The tool never aborts or continues a cherry-pick.
- **Conflict resolution is a text write.** `git_conflict_resolver` `take_ours` / `take_theirs` drops the marker lines and keeps only the chosen side's lines (Legacy's state machine), then writes the whole file through `commit()` — the full before/after goes to review, like every Wave 2 text write. A file counts as conflicted only when it contains all three of `<<<<<<<`, `=======`, `>>>>>>>`; that check precedes resolution validation.
- **PR summary is four local commands.** `git_pr_summary` runs `log --oneline <base>..<head>` (two dots), `diff --stat <base>...<head>` (three dots), `diff --shortstat <base>...<head>`, and `diff --name-only <base>...<head>`. A failing log or stat fails the tool; a failing shortstat or name-only is tolerated as empty. The insertion/deletion/file counts are parsed from the shortstat text; `fileCount` comes from `--name-only` when it is non-empty, else from the shortstat count.

#### Error cases

| Situation | Result |
|---|---|
| Workspace is not a git repository (any git-backed tool) | Failure with git's own message, e.g. `git log failed: fatal: not a git repository (or any of the parent directories): .git` — never invented output |
| `git` cannot start | `Failed to launch git: <reason>` |
| Path escapes the workspace (`..`, absolute outside path) | Workspace-containment error (`<path> is outside the workspace folder <root>`) |
| Invalid ref / commit / branch name / stash identifier | `Invalid git ref: <ref>` / `Invalid git ref for base: <base>` / `Invalid git ref for head: <head>` / `Invalid commit: <commit>` / `Invalid branch name: <name>` / `Invalid stash identifier: <stash>` / `Invalid git ref: <ref>` (rollback) |
| Unknown action | `Invalid bisect action '<action>'. Allowed: start, good, bad, skip, reset, log.` · `Unsupported action '<action>'. Supported: list, current, create, switch, delete.` (branch manager) · `Unsupported action '<action>'. Valid: save, pop, list, show, drop` (stash) · `Unknown git action '<action>': expected status, commit, branch, rollback, or diff.` (version_control_operator) · `Unknown resolution '<resolution>'. Use 'inspect', 'take_ours', or 'take_theirs'.` (conflict resolver) |
| Missing required argument | `Missing required parameter: <name>` (Legacy's message; Ycode's argument validation also enforces the schema `required` list first) |
| Missing branch name / stash message context | `Action 'create' requires 'branchName'.` / `Action 'switch' requires 'branchName'.` / `Action 'delete' requires 'branchName'.` |
| Remote operation (`version_control_operator` push/pull/fetch/clone) | `Git <action> needs remote access, which is out of scope for this wave (local operations only). Remote operations (push/pull/fetch/clone) are a later wave.` |
| `github_repo` (any operation) | Failure naming the missing GitHub API client/auth prerequisite; nothing fetched, nothing faked |
| Approval refused (any mutating git operation) | `The change was rejected in Ycode's review; nothing was written.` and git never runs |
| Writes in `readOnly` server mode (any `writes: true` tool, including its read-only actions) | `<tool> changes files, and this Ycode MCP server is read-only. Start it with \`ycode mcp --allow-writes\`, or use agent mode in the Ycode IDE, where each change is reviewed as a proposal.` |
| `git bisect log` with no bisect in progress | `Git bisect log failed: error: We are not bisecting.` (git's own message, reported as Legacy reports it) |
| Cherry-pick conflict | `Cherry-pick of <commit> stopped due to conflicts in: <files>. Resolve the conflicts and commit, or run git cherry-pick --abort. Git output: <output>` |
| Conflict resolver on a marker-free file | Success: `No active Git conflict markers (<<<<<<< / ======= / >>>>>>>) found in <path>.` (checked before the resolution is validated) |
| `git_log_viewer` with no commits | Success: `No commits found in the repository history.` |

#### What was not ported (exact blockers)

- **`github_repo` (all 7 operations):** needs a GitHub API client plus authentication (public repos unauthenticated, private repos with the user's saved GitHub credential). Ycode's MCP host has no GitHub client and no GitHub credential store; the audit records that the GitHub remote layer needs a new target (`YcodeIDECore/SourceControl` is local-git only). Blocker: a GitHub-service target + credential flow — a later wave. The tool is registered and honestly failing, never faked.
- **Remote git operations in `version_control_operator`:** Legacy implements none (only status/commit/branch/rollback/diff), and this wave must not touch remotes. Blocker: the same later-wave remote/GitHub work.
- **Anything else:** nothing. All other behaviour ported, including `git_pr_summary`, which is local-only despite its name.
## Evidence

| Claim | Level | Source |
|---|---|---|
| All 16 IDs, titles, descriptions, capabilities, risk levels, and input schemas | 1 | Legacy source, read directly: `SwiftCode/Backend/Assist/Tools/AssistCallHierarchyTool.swift`, `AssistCodeSummaryTool.swift`, `AssistDependencyGraphTool.swift`, `AssistImportGraphTool.swift`, `AssistProtocolConformanceListTool.swift`, `AssistRegexSearchTool.swift`, `search_skills.swift`, `AssistSymbolSearchTool.swift`, `AssistSearchTool.swift`, `AssistSemanticQueryEngine.swift`, `AssistSourceGraphBuilder.swift`, `AssistSymbolMoveFileTool.swift`, `AssistSymbolReferenceGraphTool.swift`, `AssistSymbolRenameProjectTool.swift`, `AssistTypeHierarchyTool.swift`, `AssistDataInspectionTools.swift` (`extract_code_symbols`), `AssistToolRegistry.swift` (register lines 83–87, 127–128, 144, 173, 245–246, 318, 332–335) |
| Search scan rules (1 MB cap, binary extensions, hidden files, case-insensitive literal/regex) | 1 | Legacy `SwiftCode/Backend/Assist/Functions/AssistSearchFunctions.swift`, read directly |
| Source scan rules (skipped dirs, first-component rule, caps, source extensions) and `declaredFuncName` | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistToolSharedHelpers.swift` (`AssistWorkspaceScan`), read directly |
| Enumerated-files scan (300 KB default, regular files only) and code extensions; clamping `resolvePath` | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistToolingSupport.swift`, read directly |
| Registry aliases `search`/`search_dir`/`search_directory`/`find_file` → `search_text`, `symbol_graph` → `symbol_reference_graph` | 1 | Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` alias table, read directly |
| `search_skills` metadata parsing, scoring, and output format | 1 | Legacy `SwiftCode/Backend/Assist/Tools/search_skills.swift` and `SwiftCode/Core/AI/Agent/Skills/SkillIndex.swift`, read directly |
| Ycode has no skills catalogue; its skill surface is workspace `.claude/skills` / `.agents/skills` | 1 | Ycode `ycode/Sources/YcodeMCP/AgentSkill.swift` (`paths`, `markdown`, `install`), read directly |
| Ycode's existing `search` and `symbol_search` schemas that must not be merged with `search_text` / `search_symbol` | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Workspace.swift` (`search`, `symbol_search`, `SymbolDocs`), read directly |
| Gate shape (`commit()` per file, approval before disk, read-only refusal in `run()`) | 1 | Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`MCPWritePolicy`, `run`); `YcodeTools+Content.swift` (`commit`); `specs/ide/assist-approval-model.md` §6 |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
| Wave 3 (Git): all 13 IDs, schemas, safety rules, ref validation, and error cases; `github_repo` honestly failing for lack of a GitHub client | 1 | Legacy Git tool sources listed in the catalogue Evidence table (Wave 3 Git rows); `AssistToolRegistry.swift` alias table, read directly |
