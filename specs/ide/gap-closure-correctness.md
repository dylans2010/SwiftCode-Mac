# Gap closure: correctness gaps

Date: 2026-11-06. Slice: correctness gaps (family 4 of the
gap-closure wave). Destination: SwiftCode-Mac main `d3cf493`
(Ycode base, SwiftPM; the slice started on `f9f66c05` and the
Wave 18 landing moved HEAD mid-task — the slice's files were
re-verified against `d3cf493`, which did not touch any of them).
Legacy: SwiftCode-Legacy `d51a8f0d` (read-only). Ledger: all six tools below were already
`IMPLEMENTED`; this spec closes the honest-gap notes on those
rows — it completes no new ledger row, and the ledger is not
edited by this slice.

The six gaps, each verified live against Legacy and the
destination before any code was written:

1. Myers diff engine — real O(ND) diff, wired where the naive
   patch diff was used.
2. Parameter-name aliases — Legacy's registry normalisation,
   applied before argument validation.
3. `safe_undo` — a real snapshot store with a restore path.
4. `session_progress_report` — phase counts wired to real
   session progress.
5. `swift_ast_inspector` — real AST inspection via swift-syntax.
6. `symbol_rename_project` — toward a real symbol rename.

No Swift toolchain exists in this environment, so everything
below is statically checked only; `swift build` / `swift test`
and live runs stay pending on Dylan's Mac (see §8).

## 1. Myers diff engine

### Legacy evidence

Legacy's `AssistDiffEngine` (`SwiftCode/Backend/Assist/
AssistDiffEngine.swift`) generates unified diffs via
`MyersDiffAlgorithm.shared.computeUnifiedDiff(filePath:oldContent:
newContent:contextLines: 3)` — a real Myers minimal diff,
rendered with `--- a/<file>` / `+++ b/<file>` headers and
`@@ -a,b +c,d @@` hunk headers (counts always present).
`AssistWriteFileTool` returns that diff under the `diff` data
key alongside `is_new`.

### Destination before

No Myers engine existed. Two positional diffs stood in:

- `file_compare_diff` (`YcodeTools+FileInspection.swift`):
  lines at the same index compared; one inserted line made the
  whole tail read as changed.
- `EnginesPatch.unifiedDiff` (`YcodeTools+EnginesSupport.swift`,
  Wave 5): same positional shape, no hunk headers, no context
  lines.

`file_create` and `code_replace` (`YcodeTools+FileWriting.swift`)
returned no `diff` key, and `file_write`
(`YcodeTools+Content.swift`) neither — all recorded as "pending
Myers engine" in the Wave 2 notes.

### What now exists

`ycode/Sources/YcodeIDECore/MyersDiff.swift` — `public enum
MyersDiff`, an original implementation of the published Myers
O(ND) algorithm (E. W. Myers, Algorithmica 1986): forward greedy
search with a stored V-trace, then backtracking to a minimal
edit script. No Legacy code is copied. `diff(old:new:)` returns
operations plus added/removed counts; `unifiedDiff(old:new:file:
contextLines: 3)` renders Legacy's format (headers, hunk
headers, 3 context lines); `editDistance(old:new:)` returns the
minimal distance, or `nil` when the fallback ran.

Two engineering choices:

- Common prefix/suffix trimming before the search, so D stays
  tiny for near-identical files of any size.
- A cap (`maxEditDistance = 4096`): the trace is O(D²) in memory,
  so when D would exceed the cap the result falls back to the old
  positional diff with `usedFallback == true`. The fallback is
  still a correct (non-minimal) diff; callers that need minimality
  check the flag. `editDistance` returns `nil` in that case
  rather than a non-minimal number.

One deliberate deviation from Legacy's line counting: empty text
is zero lines, not one empty line (Legacy's
`components(separatedBy: .newlines)` counts `""` as one line).
Diffing an empty file against `"x\n"` is one insertion, not a
deletion of a phantom empty line plus an insertion.
`file_compare_diff`'s own `lineCount` keeps Legacy's counting;
only the diff engine differs.

### Wiring

- Owned file: `file_create` and `code_replace` now return a
  `diff` key (output schemas extended), rendered by the new
  `FileWritingSupport.unifiedDiff(old:new:file:)` helper in
  `ycode/Sources/YcodeMCP/YcodeTools+FileWritingSupport.swift`
  (new file; the family's calling convention — `old == nil` is a
  new file, rendered as all-insertion).
- Coordinator patches (exact old/new text in the slice report):
  P2 `file_compare_diff` uses `MyersDiff` for its diff text and
  counts; P3 `EnginesPatch.unifiedDiff` delegates to
  `MyersDiff.unifiedDiff`; P4 `file_write` gains the `diff` key
  via `FileWritingSupport`.

### Tests

`ycode/Tests/YcodeIDECoreTests/CorrectnessGapTests.swift`
(`CorrectnessGapDiffTests`): empty/empty, identical, pure
insert, pure delete, interleaved, middle insertion leaving the
tail equal (the positional diff's failure case), a 2,000-line
file with one middle insertion (one hunk), far-apart changes
splitting into two hunks, huge edit distance falling back
honestly (`usedFallback`, `editDistance == nil`).
`ycode/Tests/YcodeMCPTests/CorrectnessGapTests.swift`: diff keys
on `file_create` (new + overwrite) and `code_replace` through
the server.

## 2. Parameter-name aliases

### Legacy evidence

Legacy's `AssistToolRegistry.validate`
(`SwiftCode/Backend/Assist/AssistToolRegistry.swift`, "Common
parameter aliases") normalises arguments before its
required/type checks:

- `path` ← `filePath` / `file_path` / `targetFile` / `file`
- `content` ← `fileContent` / `file_content` / `code` / `data`
- `target` ← `targetContent` / `old_string` / `old_str` / `find`
- `replacement` ← `replacementContent` / `new_string` /
  `new_str` / `replace`
- `command` ← `cmd`

One per-tool alias verified live in addition:
`AssistDataMutationTools` reads `input["path"] ??
input["csvPath"]`, so `csvPath` is a `path` alias (for
`csv_to_json`). Legacy keeps the alias key in the arguments
after copying (its schema check has no unknown-key rejection),
and an alias only fills a missing canonical — a caller passing
both keeps the canonical value.

### Destination before

`MCPTool.argumentProblem` (`MCPServer.swift`) rejects unknown
arguments before any handler runs
(`additionalProperties: false`), so an aliased call failed with
`unknown argument "filePath"` and an alias could never satisfy
the `required` list. Waves 1–6 recorded this as unimplemented.

### What now exists

`ycode/Sources/YcodeMCP/MCPParameterAliases.swift` —
`public enum MCPParameterAliases` with Legacy's table verbatim
(plus `csvPath`) and `normalized(_:declaredProperties:)`.

Rules (Legacy's, plus the one Ycode needs):

- An alias only fills its canonical when the canonical is
  absent; a caller passing both keeps the canonical value.
- The alias key is dropped either way (Legacy could keep it;
  Ycode cannot — an unconsumed alias key would still trip the
  unknown-argument rejection, which would make "pass both"
  fail for having supplied a redundant name).
- An alias key is only consumed when it is NOT itself a
  declared property of the tool being called. `code` is the
  canonical parameter of `code_insert`, `data` of
  `ai_context_memory` — those must never be swallowed as
  `content` aliases. A declared alias keeps its own meaning.
- A null alias value is dropped, not copied.

### Wiring

Coordinator patch P1 (`MCPServer.run`): normalise the call's
arguments with `MCPParameterAliases.normalized(_:declaredProperties:)`
before `argumentProblem`, and hand the rewritten arguments to
the handler. This is the single funnel — every `tools/call`
goes through `run()` — so no per-tool change is needed. The
table lives in the new file, not in `MCPServer.swift`, so the
patch is three lines.

### Tests

`CorrectnessGapTests` (`aliasTable`,
`aliasDoesNotOverrideCanonical`,
`aliasDoesNotSwallowDeclaredProperties`): every Legacy pair,
canonical-wins, null-alias drop, declared-property protection
(`code`, `data`), unknown keys passing through untouched.
End-to-end (aliased `file_write` via `tools/call`) must be
re-run after P1 lands; the engine tests cover the logic now.

## 3. `safe_undo`: a real snapshot store

### Legacy evidence

`AssistUndoTool` (`SwiftCode/Backend/Assist/Tools/
AssistUndoTool.swift`): lists snapshots via
`AssistSnapshotFunctions.listSnapshots()`, requires at least
two (current baseline + previous state), restores
`snapshots[1]` into the workspace. `AssistSnapshotFunctions`
stores full-tree copies under `AssistSnapshots/<uuid>/files`
plus `metadata.json`.

Verified live: snapshots are only ever created explicitly.
The only `createSnapshot` callers in Legacy are the snapshot
tool itself and UI surfaces — the agent loop never snapshots
per action. So Legacy's undo only works after two explicit
snapshots exist; after a single write with no snapshots it
fails with "At least two snapshots are required".

### Decision: a separate lightweight journal, not the `project_snapshot` store

The destination's Wave 7 `project_snapshot` store
(`YcodeSnapshots/<uuid>/files` + `metadata.json`,
`YcodeTools+ProjectModel.swift`) is the same full-tree layout
as Legacy's. This slice deliberately does NOT unify
`safe_undo` with it, for three reasons:

1. A full-tree copy per write is far too heavy to take before
   every modification — and without a per-write snapshot, undo
   after a single write would still fail exactly as Legacy's
   does (fewer than two snapshots).
2. The two stores answer different questions: a point-in-time
   workspace restore (`project_snapshot` / `project_restore`)
   vs. reverting the last modification (`safe_undo`). Wave 8
   set the precedent for keeping such stores separate
   (`checkpoint_creator` vs. `project_snapshot`).
3. The journal records only what changed — one entry per
   committed file, holding its previous text — at O(changed
   file) cost, which is exactly what "reverts the last
   modification made by the agent" needs.

### What now exists

`ycode/Sources/YcodeIDECore/SafeUndoJournal.swift` —
`public final class SafeUndoJournal` (shared instance; a
`baseDirectory` initializer exists for tests). Storage:
Application Support `YcodeUndo/<workspace-key>/journal.json`
(never inside the workspace), keyed by an FNV-1a hash of the
workspace root path. Entries hold the workspace-relative path,
the previous text (`nil` = the file did not exist), an
`unrecorded` flag, the tool, and the date; capped at 100
entries per workspace.

`ycode/Sources/YcodeMCP/CorrectnessGapHandlers.swift` —
`correctnessSafeUndo`: pops the last entry, asks approval
(`approveFileWritingChange`, the file-writing approval path),
then restores the previous text — or removes the file when it
did not exist before the change. The entry is consumed only
after approval succeeds, so a refused undo leaves the journal
untouched. An `unrecorded` entry (previous content too large —
over 1 MB — or not UTF-8) is refused honestly instead of
deleting the file. An empty journal fails with the reason, and
nothing is changed.

### Wiring

- Coordinator patch P-commit (`YcodeTools+Content.swift`,
  `commit()`): after approval succeeds and before writing,
  record the change — `SafeUndoJournal.shared.record(
  workspaceRoot:folder, relativePath:change.relativePath,
  original: <current on-disk text or nil>, unrecorded: <could
  not be read as UTF-8 or over the cap>, tool: call.name)`.
  The original is read from disk at record time, NOT taken
  from `MCPChange.original`: several `commit()` callers pass
  `original: nil` for files that may already exist, and
  recording that would make undo delete a pre-existing file.
  Recording only happens for changes that passed approval;
  a failed write leaves a harmless stale entry (its recorded
  original equals the current content).
- Coordinator patch P5 (`YcodeTools+ReviewDocs.swift`):
  `reviewDocsSafeUndo` delegates to `correctnessSafeUndo`, and
  the file header's honestly-failing note is replaced.

Scope limit, stated plainly: only `commit()` text writes are
journaled. Non-text operations that bypass `commit()` (copy /
move / rename / delete / directory operations, which approve
directly) are NOT undoable by `safe_undo` — the tool's
description does not claim otherwise, and the failure message
when the journal is empty says which writes are recorded.

### Tests

`CorrectnessGapDiffTests`' companion suite
(`CorrectnessGapUndoJournalTests`, IDECore): record/pop
round-trip, nil-original, unrecorded entry, 100-entry cap,
per-workspace isolation, persistence across instances, clear.
MCP tests (`CorrectnessGapTests`): restore previous content,
removal of a file that did not exist, refusal of an unrecorded
entry, empty-journal failure. The MCP tests seed the journal
directly (the way `commit()` records it); the end-to-end
write-then-undo check must be re-run after P-commit lands.

## 4. `session_progress_report`: real session progress

### Legacy evidence

`AssistSessionProgressReportTool`: reads
`AgentPhaseCoordinator.shared.phases` (engineering phases
with `PhaseStatus` pending / inProgress / completed / failed /
skipped, plus per-phase failures) and `AgentNotesManager`
(last-saved time). Counts by status; the message starts
"Session progress: N of M phases completed." with In progress
/ Failed / Pending lines and the agent-notes line. With no
phases: "No engineering phases are registered for this
session."

### Destination before

Ycode has no phase coordinator, so the counts were always 0
and the message always the no-phases line. Only the
agent-notes line was real (workspace `agent_notes.md`
modification time).

### What now exists

`correctnessSessionProgress` (in `CorrectnessGapHandlers.swift`):
the report reads the workspace's real plan state — the
Agentic plan store (`AgenticPlanningPlanStore`, written by
`task_planner` / `checklist_plan` / `intel_plan_task`) — plus
the live session activity (`WorkspaceSession.activity`:
building / running / paused / finished) and failed-test count,
and the agent-notes line as before. The output keys are
Legacy's (`phaseCount`, `completed`, `inProgress`, `failed`,
`pending`); a plan task is a phase here, and the summary says
so ("(N plan(s), P% by task weight)") rather than pretending
`AgentPhaseCoordinator` phases exist. Statuses map directly:
`completed` / `in_progress` / `failed` / `skipped` / anything
else → pending. The no-plans case keeps Legacy's exact
no-phases message and zero counts.

### Wiring

- Coordinator patch P8 (`YcodeTools+AgenticPlanning.swift`):
  add `func plans(workspace: String) -> [AgenticPlanningPlan]`
  to `AgenticPlanningPlanStore` (the `plans` dictionary is
  `private`, so no other file can enumerate it). COMPILE
  DEPENDENCY: `CorrectnessGapHandlers.swift` calls it, so the
  YcodeMCP target does not build until P8 is applied.
- Coordinator patch P5 (`YcodeTools+ReviewDocs.swift`):
  `reviewDocsSessionProgress` delegates to
  `correctnessSessionProgress`, and the header deviation note
  is replaced.

### Tests

MCP tests: a seeded plan with 2 completed / 1 in-progress /
1 failed / 1 queued tasks reports phaseCount 5 with the right
per-status counts and Legacy-shaped message; no plans reports
all zeros with the no-phases message.

## 5. `swift_ast_inspector`: real AST inspection

### Legacy evidence

`AssistSwiftASTInspectorTool`: primary path runs
`xcrun swiftc -dump-ast` and filters its lines; when that is
unavailable it falls back to a regex structural parser
(`(class|struct|enum|protocol|extension|actor)\s+(\w+)` with
an inheritance clause). The port (Wave 6) implemented only
the regex fallback — never shelling out to Apple's toolchain.

### Destination before

Regex only, as documented in
`YcodeTools+StaticAnalysis.swift`: a type name inside a string
or a comment was reported as a declaration; there were no line
numbers, no functions, no imports, no parse-error signal.

### What now exists

`ycode/Sources/YcodeMCP/SwiftASTInspection.swift` — `enum
SwiftASTInspection`, parsing with `SwiftParser` (`Parser.parse`)
and walking the tree with a `SyntaxVisitor`. Reports types
(class / struct / enum / protocol / actor / extension) with
line numbers, inheritance clauses and nesting (qualified
names), functions with parameter lists and return types,
variables, enum cases, typealiases, and imports — in source
order, members nested under their enclosing type. The symbol
filter keeps Legacy's case-insensitive substring match (a
matching member keeps its ancestors, with only matching
descendants). `hasError` (`tree.hasError`) is reported as a
"parse errors; results may be incomplete" note.

Why swift-syntax directly, not `YcodeSyntax`: `YcodeSyntax`
is a tokenizer / block-structure library — it exposes
`SyntaxDocument` tokens and classification, but no parse tree
(`SwiftClassifier` is internal and classification-only). The
engine therefore uses the same swift-syntax 604.0.0 library
`YcodeSyntax` is built on, via a direct product dependency
(see §7) — it does not duplicate `YcodeSyntax`'s lexer work
and does not re-implement parsing.

Limits, stated plainly: this is syntactic, not semantic.
There is no type checker, so there is no resolved type of an
expression, no overload set, and no cross-file symbol index.
It replaces Legacy's regex fallback, not `swiftc -dump-ast`
(which would need a Swift toolchain and is not ported).

### Wiring

- Coordinator patch P6 (`YcodeTools+StaticAnalysis.swift`):
  `staticAnalysisSwiftASTInspector` delegates to
  `correctnessSwiftASTInspector` (same path resolution and
  failure messages), the tool description gains "(parsed with
  swift-syntax)", and the header deviation note is replaced.
  The old regex body is deleted by the patch.
- Package wiring (§7): `SwiftSyntax` + `SwiftParser` products
  on the YcodeMCP target.

### Tests

MCP tests: a fixture with a class (inheritance, var, func),
struct, enum, imports and a `"class Fake {}"` string literal
— the inspector reports the real declarations with line
numbers and does NOT report `Fake`; the symbol filter narrows
to the matching function; a brace-unclosed file reports parse
errors and still reports the recovered declaration. Direct
engine tests cover `hasError` and `kind(of:)`.

## 6. `symbol_rename_project`: toward a real symbol rename

### Legacy evidence

`AssistSymbolRenameProjectTool` (Wave 3 port): whole-word
textual replacement (`\boldName\b` over raw file text), one
`commit()` per changed file, stopping at the first refusal.
The Wave 3 note already recorded it as textual, not a
symbol-index rename: it also renamed same-named occurrences
in comments and strings.

### What now exists

`ycode/Sources/YcodeMCP/SymbolRenameEngine.swift` — a
token-aware rename on the same swift-syntax parse. It walks
the parse tree's tokens and renames only real identifier
tokens, rebuilding the source from trivia + token text (so
formatting round-trips exactly). Occurrences inside string
literals and comments are never identifier tokens, so they are
left alone; `import <oldName>` paths are skipped explicitly
(the token's parent is `ImportPathComponentSyntax`); the count
of skipped whole-word occurrences is reported. Validation,
scope enumeration (`renameScopeFiles`: `.swift` files, ≤300 KB,
≤5000, sorted), the per-file approval shape and the output
keys (`filesChanged`, `replacementCount`, `changedFileCount`)
are unchanged from the Wave 3 handler.

Honest limit (in the tool description, the spec, and the
summary): this is syntactic, not semantic. There is no type
checker and no cross-file symbol index, so shadowing is not
resolved — a same-named local in an unrelated scope is renamed
too, and a member referenced through a different spelling
(e.g. a stringly-typed key) is not renamed. What it guarantees
is token accuracy within each file: every replacement is an
identifier token, and no string, comment, or import path is
touched. A semantic rename needs an index-backed rename; this
tool does not claim to be one.

### Wiring

Coordinator patch P7 (`YcodeTools+Search.swift`):
`renameSymbolProject` delegates to
`correctnessRenameSymbolProject`, the tool description states
the token-aware behaviour and the limit, and the header note
is replaced. The old regex body is deleted by the patch.

### Tests

MCP tests: direct engine test (2 replacements, 3 skipped, the
string/comment/import untouched, declaration found as
`struct`); tool-level test on a fixture file (counts in the
structured result, on-disk state, skipped count in the
summary); a string-only occurrence changes nothing and says so.

## 7. Package.swift wiring needed (coordinator applies)

`ycode/Package.swift` — YcodeMCP target only:

- Add `"YcodeSyntax"`? NO — not needed: the AST/rename
  engines import `SwiftSyntax` / `SwiftParser` directly (see
  §5 for why `YcodeSyntax` itself is not used).
- Add `.product(name: "SwiftSyntax", package: "swift-syntax")`
  and `.product(name: "SwiftParser", package: "swift-syntax")`
  to the `.target(name: "YcodeMCP", ...)` dependencies.
  `swift-syntax` 604.0.0 is already a package dependency
  (used by YcodeSyntax and YcodeStrings).
- No test-target change: `YcodeMCPTests` already depends on
  `YcodeMCP` + `YcodeIDECore`; the new MCP tests use only
  those modules. `YcodeIDECoreTests` already depends on
  `YcodeIDECore` (+ `YcodeSyntax`).

## 8. What is still pending

- Mac `swift build` / `swift test` for everything in this
  slice (no Swift toolchain in this environment; static checks
  only — see the slice report for the exact checks run).
  After the coordinator applies patches P1–P8 + P-commit,
  re-run the full `YcodeMCPTests` / `YcodeIDECoreTests` suites
  and the end-to-end checks listed in §2/§3 (aliased
  `file_write` via `tools/call`; write-then-`safe_undo`).
- Dylan must supply nothing new for this slice: no API key, no
  endpoint, no account. The honest limits above (no semantic
  rename, no `swiftc -dump-ast`, non-text operations not
  undoable) are design limits, not missing credentials.
- `file_compare_diff` / patch-engine / `file_write` diff
  behaviour changes only land when the coordinator applies
  P2/P3/P4; until then those three still use the old code
  while `file_create` / `code_replace` already report Myers
  diffs.

## Evidence

- Legacy sources read (read-only): `SwiftCode/Backend/Assist/
  AssistDiffEngine.swift`, `AssistToolRegistry.swift`
  (validate, "Common parameter aliases"),
  `AssistSnapshotFunctions.swift`, `Tools/AssistUndoTool.swift`,
  `Tools/AssistSessionProgressReportTool.swift`,
  `AgentPhaseCoordinator.swift` (phase model),
  `Tools/AssistSwiftASTInspectorTool.swift`,
  `Tools/AssistSymbolRenameProjectTool.swift`,
  `Tools/AssistWriteFileTool.swift` (diff key),
  `Tools/AssistDataMutationTools.swift` (`csvPath`),
  `Tools/AssistPatchApplicationEngine.swift` (naive diff note).
  Evidence level 1 (Dylan's own code, authorised for direct
  porting under MIT) + level 2 (the Ycode destination as the
  format/behaviour reference for the unified-diff rendering
  already in the repo).
- Destination verified live: `YcodeTools+FileWriting.swift`
  (no diff keys, aliases rejected), `YcodeTools+FileInspection.
  swift` + `YcodeTools+EnginesSupport.swift` (positional
  diffs), `MCPServer.swift` (`argumentProblem`, `run()`),
  `YcodeTools+ReviewDocs.swift` (`safe_undo` always failing,
  phase counts always 0), `YcodeTools+StaticAnalysis.swift`
  (regex inspector), `YcodeTools+Search.swift` (textual
  rename), `YcodeTools+ProjectModel.swift` (`YcodeSnapshots`
  store), `YcodeTools+AgenticPlanning.swift` (plan store,
  `private` dict), `YcodeTools+Content.swift` (`commit()`),
  `ycode/Sources/YcodeSyntax/` (no parse-tree API),
  `ycode/Package.swift` (swift-syntax 604.0.0 already a
  dependency).
- The Myers implementation is an original implementation of
  the published algorithm, not a copy of Legacy's
  `MyersDiffAlgorithm` or any other implementation.
