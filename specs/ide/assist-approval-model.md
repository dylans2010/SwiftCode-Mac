# Assist approval model — how SwiftCodeMCP gates writes

SwiftCode modules: `SwiftCodeMCP` (the MCP server and its tools).

This spec is the approval model for every tool that writes files. It
extends the mechanism Wave 1 already built — `MCPServer.run()` plus the
`commit()` / `call.approve()` path in `SwiftCodeTools+Content.swift` and
`SwiftCodeTools+Artifacts.swift` — into the documented model. It does **not**
invent a second gate: there is exactly one gate, the write policy, and
every write tool goes through it. The companion specs are
`assist-tool-catalogue.md` (which tool writes, its risk, and its gate)
and `assist-file-writing-tools.md` (what each Wave 2 tool does once the
gate has let it through).

Scope: the approval decision itself — the three `MCPWritePolicy`
modes, what each does to a write tool, what counts as approval, what
happens on refusal, which gate each Wave 2 tool uses, the rejected
Legacy Autopilot bypass, and the Legacy path rules that SwiftCode keeps or
replaces. The user-facing review UI (how the IDE shows a proposal) is
out of scope; this spec only defines the `MCPChange` a tool must
present and the rule that nothing is written before approval returns
true.

## 1. Terms

- **Write tool**: a tool registered with `writes: true`. Exactly the
  tools whose Legacy `riskLevel` is `safeMutation` or
  `potentiallyDestructive` (see `assist-tool-catalogue.md` §1.2),
  plus nothing else. A tool's `writes` flag is static, fixed at
  registration; it never depends on the call's arguments.
- **Write policy**: the server's `MCPWritePolicy` — `readOnly`,
  `allow`, or `review`. One policy per server, set at startup
  (`swiftcode mcp --allow-writes` selects `allow`; the IDE's agent mode
  selects `review`; anything else is `readOnly`).
- **`MCPChange`**: one proposed change — `tool`, absolute `path`,
  workspace-relative `relativePath`, `original` (file text before,
  nil for a new file), `proposed` (file text after, or `""` for a
  change that is not a text write — see §6), and a human-readable
  `summary`. It is what the review shows and what approval answers.
- **Approval**: the `call.approve(change)` closure returning `true`
  for that exact `MCPChange`. Approval is per change, not per tool
  and not per session: a tool that touches N files asks N times (see
  §6.3).

## 2. The single gate: `MCPServer.run()`

`run()` is the only place the policy is enforced, and it runs before
the tool handler:

1. The tool's arguments are validated first (`argumentProblem`).
   A malformed call fails before the policy is consulted.
2. If `tool.writes` is true, the policy decides:
   - `readOnly` → the call fails immediately with
     `MCPServer.readOnlyMessage(tool.name)`:
     `<tool> changes files, and this SwiftCode MCP server is read-only.
     Start it with `swiftcode mcp --allow-writes`, or use agent mode in
     the SwiftCode IDE, where each change is reviewed as a proposal.`
     The handler never runs. Nothing is written, read, or listed as
     a side effect of the refused call.
   - `allow` → `call.approve` is replaced with a closure that always
     returns `true`, and the handler runs. Approval is still
     requested by the handler (see §6) — it is just pre-granted.
     The handler must still call `commit()` / `approve()`; it must
     not skip the call because the policy is `allow`. (If a future
     policy ever stops pre-granting, handlers that skipped the call
     would write ungated.)
   - `review(ask)` → `call.approve` is replaced with `ask`, and the
     handler runs. Each change is shown to the reviewer through the
     `MCPChange` the handler builds; the handler writes only what
     `approve()` returns `true` for.
3. If `tool.writes` is false, `call.approve` is replaced with a
   closure that always returns `false`, and the handler runs. A
   read-only tool can therefore never approve a change by accident:
   any handler code path that asked for approval would be refused.
   (Read-only tools must not ask in the first place; the `false`
   closure is a backstop, not a path.)

No other component may gate writes. In particular:

- No tool may consult the policy itself, keep its own allow-list,
  or cache an approval from an earlier call.
- No per-tool flag, environment variable, UserDefaults key, or
  model-supplied argument may bypass `run()` or pre-answer
  `approve()`. A `confirm` / `dryRun` / `overwrite` argument is
  tool input, not policy (see §5 and §6.4).
- The policy is not per-tool: `readOnly` refuses every write tool,
  including `file_backup` and the dry-run form of a tool (see §6.4).

## 3. Policy modes

| Mode | Selected by | Effect on a write tool | Effect on a read-only tool |
|---|---|---|---|
| `readOnly` | Default; `swiftcode mcp` without `--allow-writes` | Refused in `run()` before the handler, with `readOnlyMessage`. Nothing written. | Runs normally. |
| `allow` | `swiftcode mcp --allow-writes` | Handler runs with `approve` pre-granted (`true`). Every `commit()` / `approve()` call still happens and still returns `true`. | Runs normally (`approve` is `false`, unused). |
| `review(ask)` | Agent mode in the SwiftCode IDE | Handler runs; every change is presented as an `MCPChange` and written only if the reviewer accepts it. A rejected change returns `MCPServer.rejectedMessage` (see §4). | Runs normally (`approve` is `false`, unused). |

`allowsWrites` is true for `allow` and `review`, false for
`readOnly`. There is no fourth mode, no per-tool override, and no
mode that writes without ever asking: `allow` asks and is
pre-answered; `review` asks and waits for a human. The server never
silently upgrades `readOnly` to `allow` (for example because a tool
looks harmless, because the caller is local, or because a previous
call was approved).

## 4. Refusal

When `approve(change)` returns `false`, the tool must:

1. Write nothing — not the refused file, not a backup of it, not a
   partial form of it, and not any other file in the same call that
   the reviewer has not also approved. (For a multi-file tool, files
   approved before the refusal stay written; files after it are not
   attempted — see §6.3.)
2. Return the exact message `MCPServer.rejectedMessage`:
   `The change was rejected in SwiftCode's review; nothing was written.`
   as an error result (`isError: true`). It must not substitute its
   own wording, and must not report partial success.
3. Leave no reviewer-visible side effect behind: no diff-stream
   entry, no session mutation record, no `.pbxproj` registration,
   no artifact-index update for the refused change.

`commit()` already implements this: it throws
`MCPToolError(MCPServer.rejectedMessage)` when `approve()` returns
`false`, before touching disk. Handlers that approve explicitly (see
§6.2) must do the same — `guard await call.approve(change) else {
throw MCPToolError(MCPServer.rejectedMessage) }` — before touching
disk.

The read-only refusal (§2, `readOnlyMessage`) is different from a
review refusal: it happens in `run()` before the handler, it names
the remedy (`--allow-writes` or IDE agent mode), and it is not an
approval decision. Do not conflate the two messages.

## 5. Explicit approval for risk >= potentiallyDestructive — and never Autopilot-by-default

### 5.1 The rule

Every tool with Legacy `riskLevel` `potentiallyDestructive`
(`file_delete`, `dir_delete`, and, from Wave 1,
`delete_artifact`) requires explicit approval for each change it
makes, in **every** policy mode that lets it run at all:

- In `review` mode the reviewer must accept the specific
  `MCPChange`; there is no way to pre-approve destructive tools as
  a class.
- In `allow` mode the approval is pre-granted by the operator's
  explicit choice to start the server with `--allow-writes`. That
  choice is the explicit approval: it is made once, on the command
  line, by the person running the server, and it is visible in the
  process invocation. It is not a default, not a stored preference,
  and not something a tool call can set.
- In `readOnly` mode destructive tools are refused outright (§2).

`safeMutation` tools follow the same gate (§6); the
`potentiallyDestructive` rule adds that their `MCPChange` must
describe the destruction plainly in its `summary` (e.g. `Delete
<path> permanently`, never a euphemism), and that no argument may
weaken it (see §5.3).

### 5.2 The rejected Legacy design: Autopilot

Legacy's `AssistPermissionsManager` implements an Autopilot mode
that this migration **must not port**. The rejection is deliberate
and permanent:

- Legacy reads `com.swiftcode.assist.executionMode` from
  UserDefaults and **defaults to Autopilot when the key is absent**
  (`isAutopilotActive()` returns true unless the stored value is
  something else). Autopilot is therefore the default, not an
  opt-in.
- In Autopilot, `isPathAllowed()` bypasses the sandbox path
  restrictions for every path except ones containing `..` or under
  `/System/` and `/sbin/` — the blocked-path list (`/usr`, `/bin`,
  `/etc`, `/var`, `/Library`, `/private`, `/dev`, `/tmp`) is
  ignored.
- In Autopilot, `authorizeOperation()` returns `true` for every
  operation without consulting risk, the destructive-tool list, or
  the `requiresApproval` / `isApproved` flags. The permission
  system exists in the code path and does nothing.
- The flags themselves default to permissive:
  `requiresApproval = false`, `isApproved = true`.

Why it is rejected, not adapted:

1. A default-on bypass is the opposite of the model in §2–§3:
   the safe state must be the default state. A system that writes
   and deletes unless someone has configured it not to cannot be
   made safe by adding a review UI on top, because the bypass sits
   underneath the review.
2. The bypass is keyed to a mutable UserDefaults string, readable
   and writable by any process with access to the defaults domain.
   A mode that can be flipped by writing a string is not a
   permission boundary.
3. `authorizeOperation()` bypasses on the operation name, not on a
   presented change: there is no `MCPChange`-equivalent, nothing
   for a reviewer to accept or reject, and no record of what was
   approved. Porting it would mean porting a second gate that
   answers "yes" before the first gate is asked.
4. The SwiftCode host has no session loop, no phase gate, and no
   `AssistPermissionsManager` equivalent to attach it to; the only
   gate is `MCPWritePolicy`, and it has no Autopilot case and must
   never gain one.

Consequences for the port:

- No `ExecutionMode`, no `isAutopilotActive()`, no
  `authorizeOperation()` bypass, no `requiresApproval` /
  `isApproved` pair. Do not reintroduce them under other names
  ("auto-approve", "trusted mode", "agent mode" as a policy).
- The IDE's agent mode is `review`, not Autopilot under another
  name: it presents each change and waits.
- If a future product decision wants a one-click "approve all"
  affordance, it belongs in the review UI as a per-session,
  per-conversation, explicitly invoked action by the human — never
  as a server mode, a stored default, or a tool argument.

### 5.3 Destructive tools: `file_delete` and `dir_delete`

Legacy gives these two tools **no `confirm` parameter**. Their
schemas contain only `path`, and their `execute()` implementations
check nothing beyond existence (and, for `dir_delete`, the
workspace-root refusal). The safeguard in Legacy is the router /
permissions layer — which Autopilot bypasses (§5.2). The SwiftCode
safeguard is therefore the gate in §2–§4, not a parameter:

- Both tools are `writes: true`, `potentiallyDestructive`,
  `destructive: true`. In `readOnly` mode they are refused before
  the handler. In `review` mode each deletion is presented as an
  `MCPChange` and written only on acceptance. In `allow` mode they
  run only because the operator started the server with
  `--allow-writes`.
- **Do not invent a `confirm` parameter for them.** `delete_artifact`
  (Wave 1) has `confirm: true` because Legacy's
  `AssistDeleteArtifactTool` declares it; `file_delete` and
  `dir_delete` do not, and adding one would diverge from the Legacy
  schema the catalogue preserves verbatim. A caller that wants a
  second confirmation uses the review UI, not a new argument.
- Additional behaviour-level safeguards, specified in
  `assist-file-writing-tools.md` and preserved from Legacy:
  - Deleting a missing file / directory is a failure, not a
    silent success (`No file at <path> — nothing to delete.`,
    `No directory at <path> — nothing to delete.`).
  - `dir_delete` refuses the workspace root itself
    (`Security Error: Refusing to delete the workspace root
    itself: <path>`).
  - Deletion is permanent: no trash, no backup, no undo. Legacy
    creates no backup on delete, and the SwiftCode port must not
    silently create one either — a backup the caller did not ask
    for is a second write the reviewer never approved. (The
    caller can use `file_backup` first; that is a separate,
    separately approved call.)
  - `file_delete` on a directory deletes the whole tree (see
    `assist-file-writing-tools.md` §5.2): Legacy's filesystem
    layer removes whatever is at the path, and the SwiftCode port
    preserves that behaviour (coordinator decision, Wave 2);
    `dir_delete` remains the tool intended for directories.

## 6. Which gate each Wave 2 tool uses

There are two handler-side shapes, inherited from Wave 1. A tool
uses exactly one.

### 6.1 Text writes go through `commit()`

`commit(change, call, session)` asks `approve()` and then writes
the proposed text atomically (temp file + rename), creating parent
directories, and notifies the session. It is the gate for every
tool whose effect is "this file now contains this text":

| Tool | What `commit()` writes |
|---|---|
| `file_write` | Whole new file content (create or replace). |
| `file_create` | Whole new file content (create, or replace when `overwrite: true`). |
| `file_append` | Original content + appended content (read-modify-write of the whole file). |
| `code_replace` | Whole file content after the targeted replacement. |
| `code_insert` | Whole file content after the insertion. |
| `code_multi_edit` | Whole file content per edited file — one `commit()` per file, in order (see §6.3). |
| `code_format` | Whole formatted content per changed file — one `commit()` per file, only for files whose content actually changed. |
| `code_generate` | Whole generated file content (from a built-in template). |
| `code_refactor` | Whole refactored file content (LLM-produced; see `assist-file-writing-tools.md` §5.7). |
| `format_json_file` | Whole pretty-printed JSON content (in place). |
| `csv_to_json`, `json_to_csv`, `plist_to_json` | Whole converted text content at the destination. |
| `json_to_plist` (XML) | Whole converted plist XML text at the destination. |
| `plist_edit` (set / delete) | Whole re-serialised plist XML text. |
| `regex_replace_in_files` | Whole replaced content per matched file — one `commit()` per file (see §6.3). |

For these tools the `MCPChange` is exact: `original` is the
file's current text (nil when the file is new), `proposed` is the
complete new text, and `summary` names the operation and the
workspace-relative path (e.g. `Replace Sources/App.swift`,
`Create Sources/New.swift`). The reviewer sees the full before /
after, not a summary of it.

`commit()` skips the physical write when the file on disk already
contains exactly `proposed` — but only **after** `approve()` has
returned true. Approval is never skipped because the change would
be a no-op. (Legacy's `code_format` skips unchanged files without
asking; the SwiftCode port preserves that by not building a change for
an unchanged file at all — no `MCPChange` exists, so there is
nothing to approve. That is different from building a change and
not asking about it.)

### 6.2 Non-text operations use an explicit `MCPChange` + `approve()` before touching disk

`commit()` writes text; it does not fit a byte copy, a move, a
rename, a directory operation, a delete, or a binary write. Those
tools build an explicit `MCPChange` and guard on approval
**before** touching the filesystem, exactly as Wave 1's
`file_backup` and `delete_artifact` do:

```swift
let change = MCPChange(tool: call.name, path: <absolute path>,
    relativePath: <workspace-relative path>,
    original: <text before, or nil>,
    proposed: "",
    summary: "<plain description of the operation>")
guard await call.approve(change) else {
    throw MCPToolError(MCPServer.rejectedMessage)
}
// ... only now touch disk ...
```

| Tool | `MCPChange` shape | Disk operation (after approval) |
|---|---|---|
| `file_copy` | `path` = destination absolute path; `original` = nil; `summary` = `Copy <source> to <destination>` | `FileManager.copyItem` (refuses an existing destination). |
| `file_move` | `path` = destination absolute path; `original` = source text if the source is UTF-8 text, else nil; `summary` = `Move <source> to <destination>` | `FileManager.moveItem` (refuses an existing destination). |
| `file_rename` | `path` = new absolute path; `original` = source text if UTF-8, else nil; `summary` = `Rename <oldPath> to <newName>` | `FileManager.moveItem` within the same directory. |
| `file_delete` | `path` = file absolute path; `original` = file text if UTF-8, else nil; `summary` = `Delete <path> permanently` | `FileManager.removeItem` (permanent). |
| `dir_delete` | `path` = directory absolute path; `original` = nil; `summary` = `Delete directory <path> and all its contents permanently` | `FileManager.removeItem` (recursive, permanent). |
| `dir_create` | `path` = directory absolute path; `original` = nil; `summary` = `Create directory <path>` | `FileManager.createDirectory` with intermediates. |
| `batch_rename_files` | One change per rename (see §6.3); `path` = new absolute path; `original` = nil; `summary` = `Rename <old> to <new>` | `FileManager.moveItem` per rename. |
| `json_to_plist` (binary) | `path` = destination absolute path; `original` = nil; `proposed` = `""` (binary content cannot be shown as proposed text); `summary` = `Convert <path> to binary plist at <destination>` | Write binary plist data. |

`proposed: ""` for these tools means "the change is not a text
replacement" — it does not mean "the file becomes empty". The
reviewer judges the operation from the `summary` (and, for
file operations, from `original` when it is text). A handler must
never put a placeholder or truncated text into `proposed` for a
non-text operation.

Note the asymmetry with `commit()`: `commit()` notifies the
session and delegate after writing; a handler using the explicit
shape must do the same itself after the disk operation
(`s.noteFileEdited(...)`, `delegate?.mcpHostDidWrite(...)`), as
Wave 1's `deleteArtifact` / `backupFile` do. Forgetting the
notification leaves the IDE showing stale file state after an
approved write.

### 6.3 Multi-file tools: one approval per file, in order, stop at the first refusal

`code_multi_edit`, `code_format`, `regex_replace_in_files`, and
`batch_rename_files` touch more than one file. They are not one
change and must not be presented as one:

- Build and approve one `MCPChange` per file, in the order the
  tool processes files (edits array order for `code_multi_edit`;
  enumeration order for `code_format` and
  `regex_replace_in_files`; sorted filename order for
  `batch_rename_files`).
- Write a file only after its own approval returns true.
- On the first refusal, stop: do not attempt the remaining files,
  and return `rejectedMessage` as an error. Files approved and
  written before the refusal stay written — Legacy's
  `code_multi_edit` is explicitly not atomic, and the SwiftCode port
  preserves that (see `assist-file-writing-tools.md` §4.3). The
  error message says nothing was written **for the refused change**;
  it does not claim the whole call wrote nothing when earlier files
  already changed. (The literal `rejectedMessage` text —
  "nothing was written" — refers to the refused change; the tool
  must not invent a different message for the multi-file case, and
  the per-file `filesChanged` in the result is not produced at all
  because the call fails.)
- In `allow` mode every per-file approval is pre-granted, so the
  tool proceeds through all files exactly as Legacy does.

### 6.4 Dry-run tools: no disk write, but still gated at the server

`regex_replace_in_files` (`dryRun: true`) and `batch_rename_files`
(`dryRun: true`) write nothing: they report what would change and
return success. The handler must therefore **not** call `approve()`
for a dry run — there is no change to approve — and must not write
anything on any path through the dry-run branch.

But the `writes` flag is static per tool (§1): both tools are
registered `writes: true` because their non-dry-run form writes.
So in `readOnly` mode a dry-run call is still refused in `run()`
with `readOnlyMessage`, before the handler can see `dryRun`. This
is a deliberate simplification, not an oversight: the server cannot
know from the registration whether this particular call will
write, and a flag the model supplies must never downgrade the
server's policy. A caller that wants a dry run starts the server
with `--allow-writes` (or uses IDE review mode, where the dry run
presents no changes and therefore asks nothing).

### 6.5 `generate_file_checksum`: the read-only exception

`generate_file_checksum` is in this wave but writes nothing. It is
registered `writes: false` with `readOnly: true, idempotent: true`
annotations (see `assist-tool-catalogue.md` §27), and it never
calls `approve()` or `commit()`. It runs in `readOnly` mode like
any other read tool. Its presence in this wave corrects the
subsystem map's family assignment, not its behaviour — see
`assist-file-writing-tools.md` §3.4.

## 7. Paths: what Legacy allowed, what SwiftCode keeps, what confinement replaces

Wave 1 already confines all tool paths to the workspace. This
section records the Legacy rules against that confinement, so the
Wave 2 implementer does not reintroduce any of them.

### 7.1 Kept: the workspace-containment rule and its messages

- Every Wave 2 tool resolves paths inside the workspace root.
  The session-aware resolver (`AssistFileSystem.resolve`) and the
  strict resolvers (`resolveWorkspaceDataMutationURL`,
  `resolveWorkspaceDataInspectionURL`, `plist_edit`'s private
  `resolvePath`) all enforce it; which tool uses which is specified
  in `assist-file-writing-tools.md` §2.
- The failure messages are preserved verbatim per resolver (§2 of
  that spec): the session-aware
  `Security Error: Path traversal outside workspace bounds is
  forbidden: <path>`, the strict
  `Path is outside the workspace: <raw>` (and its per-tool
  variants), and `file_write` / `code_replace`'s inline
  `Path security error: Relative path traversal ('..') is
  prohibited for safety. Path: '<path>'`.
- `..` is rejected or contained exactly as each resolver does it
  — the session-aware resolver resolves `..` and then checks
  containment; the strict resolvers reject any `..` as text.
  The implementer must not unify them.
- Symlinks in an existing parent are resolved before the
  containment check by the session-aware resolver; the strict
  resolvers standardise without resolving symlinks (the known
  Legacy inconsistency, recorded in Wave 1's `assist-file-tools.md`
  §2.6 — preserved here, not silently fixed).

### 7.2 Not kept: the `/tmp/swiftcode/scripts` carve-out

Legacy's session-aware resolver returns paths exactly equal to
`/tmp/swiftcode/scripts` or under it unchanged — an isolated
scripts directory outside the workspace — and `file_write` /
`code_replace` special-case the same prefix (without the `/`
boundary; see `assist-file-writing-tools.md` §2.4). The
`AssistPermissionsManager` also always allows that directory and
creates it in `init`.

SwiftCode does **not** keep this carve-out:

- There is no isolated scripts directory in SwiftCode, and no Wave 2
  tool has a reason to write outside the workspace. A path under
  `/tmp/swiftcode/scripts` is outside the workspace and is refused
  like any other outside path.
- `file_write` / `code_replace` in SwiftCode therefore do not need
  their inline `/tmp` special case at all: the session-aware
  resolver (which SwiftCode's `resolveFileReadingPath` implements)
  refuses outside paths, and the tools' own `..` check is the only
  inline check that survives.
- This is a deliberate deviation, recorded here so it is not
  mistaken for an omission. If a later wave introduces a scripts
  feature, its spec must define its own directory and its own
  approval story; it must not resurrect the Legacy carve-out
  silently.

### 7.3 Replaced by confinement: the blocked-path list

Legacy's `AssistPermissionsManager` keeps a blocked-path list —
`/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`, `/Library`,
`/private`, `/dev`, `/tmp` — plus an allow-list, consulted by
`isPathAllowed()` (except in Autopilot, where it is bypassed, §5.2).

SwiftCode does not port the list, because workspace confinement makes
it redundant: a tool path must resolve inside the workspace root,
and the workspace root is a project folder, not a system directory.
A path under `/etc` or `/System` cannot be inside a workspace
rooted in a project folder, so it is refused by containment before
any block-list would matter. Porting the list would add a second,
overlapping rule that could only disagree with containment (for
example if a workspace were legitimately rooted under `/tmp`).
The blocked-path list is therefore **replaced by confinement**,
not kept. The one case confinement does not cover — a workspace
rooted at `/` — is handled the way Legacy handles it: fail closed
with `No active project: workspace root is unavailable. Open a
project first.`

### 7.4 Not kept: Legacy's side channels around the gate

These Legacy behaviours bypass or sit beside any approval, and
none of them is ported:

- `LiveDiffStreamer` begin / stream / complete / reconcile calls
  in `file_write`, `file_create`, `code_replace`, and
  `code_insert`: they broadcast in-flight mutation state to the
  IDE. SwiftCode has no such streamer; the `MCPChange` proposal is the
  only pre-write broadcast.
- `XcodeProjWriter.shared.addFileReference` calls in `file_write`,
  `file_create`, `code_generate`, and `file_copy`: Legacy
  auto-registers a new file in the `.pbxproj`. SwiftCode projects are
  SwiftPM or Xcode projects opened through SwiftCode's own model; a
  new file's project membership is the IDE's business, not a tool
  side effect, and it must not happen as an unreviewed write
  alongside an approved one. (Whether SwiftCode auto-registers new
  files at all is a project-model decision for a later spec.)
- `ProjectSessionStore.shared.recordAssistFileMutation` calls:
  Legacy's session mutation log. SwiftCode's equivalent is the
  session notification in `commit()` /
  `noteFileEdited` / `mcpHostDidWrite` (§6.2).
- The `suggestedNextActions: ["project_build"]` (duplicated for
  `.swift` files — see `assist-file-writing-tools.md` §8.4) and
  `duration` / `beforeContent` / `afterContent` envelope fields:
  SwiftCode's `MCPToolResult` has no such fields, so they are dropped,
  not reimplemented. The unified diff survives as `data["diff"]`
  (see the catalogue).

## 8. Unknown tool IDs fail closed

An ID the server does not recognise is treated as
`potentiallyDestructive`, mutating, and requiring verification —
exactly as Legacy's `AssistToolRouter.metadata(for:)` does for its
default case, and as Wave 1's catalogue §1.2 specifies. In SwiftCode
terms: `tools/call` for an unknown name throws
`JSONRPCError.invalidParams("Unknown tool: <name>")` before `run()`
is reached, so an unknown tool never executes and never writes.
There is no fallback registration, no prefix matching, and no
"close enough" alias: aliases are resolved only through the
explicit `toolAliases` table (see the catalogue §27.5), and an
alias that points at a write tool inherits that tool's `writes:
true` and its gate.

## 9. What this spec does not cover

- The per-tool behaviour once the gate has passed (schemas,
  resolvers, atomicity, conversions, error tables) — see
  `assist-file-writing-tools.md` and `assist-tool-catalogue.md`.
- The IDE review UI: how proposals are rendered, grouped, or
  accepted in bulk. This spec constrains only what the tools
  present (`MCPChange`) and the rule that nothing is written
  before approval.
- The Legacy session loop, providers, and `AssistManager` /
  `AssistAgentSession` — not ported, as in Wave 1.
- `use_terminal` and any future execution tool: executing a shell
  command is not a file write, and its approval story belongs to
  its own wave's spec. Nothing here authorises it.

## Evidence

| Claim | Level | Source |
|---|---|---|
| `MCPWritePolicy` modes, `run()` refusal / pre-grant / review wiring, `readOnlyMessage`, `rejectedMessage`, non-write tools get `approve = { _ in false }`, unknown tool throws `invalidParams` | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/MCPServer.swift` (`MCPWritePolicy`, `run()`, `readOnlyMessage`, `rejectedMessage`, `dispatch` `tools/call`), read directly |
| `commit()` asks `approve()` then writes atomically with parent creation, skips the write when disk already matches (after approval), notifies session/delegate; explicit `MCPChange` + `guard await call.approve(change)` for byte-copy/delete in Wave 1 | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Content.swift` (`commit`, `writeFile`, `editFile`, `setString`); `SwiftCodeTools+Artifacts.swift` (`createArtifact`, `deleteArtifact`, `backupFile`), read directly |
| `--allow-writes` selects `allow`, otherwise `readOnly`; IDE agent mode is review | 1 | SwiftCode `swiftcode/Sources/SwiftCodeMCP/MCPCommand.swift` (`--allow-writes`, `server.writePolicy = options.allowWrites ? .allow : .readOnly`), read directly |
| Autopilot defaults on when the UserDefaults key is absent; `isPathAllowed` bypass; `authorizeOperation` bypass; `requiresApproval = false`, `isApproved = true`; blocked paths; isolated-scripts directory always allowed and created in `init` | 1 | Legacy `SwiftCode/Backend/Assist/AssistPermissionsManager.swift`, read directly |
| Capability / risk / permission derivation, `isReadOnly` / `isMutating` / `isDestructive` defaults, fail-closed unknown-tool metadata | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistTool.swift` (protocol extension defaults); `AssistToolRouter.swift` (`metadata(for:)`, default case), read directly |
| `/tmp/swiftcode/scripts` carve-out with `/` boundary in the session-aware resolver; fail-closed on `/` workspace root; symlink resolution in longest existing ancestor | 1 | Legacy `SwiftCode/Backend/Assist/AssistFileSystem.swift` (`resolve`), read directly |
| `file_write` / `code_replace` inline `..` check and `/tmp/swiftcode/scripts` prefix check without a `/` boundary | 1 | Legacy `Tools/AssistWriteFileTool.swift`, `Tools/AssistReplaceInFileTool.swift`, read directly |
| `file_delete` / `dir_delete` schemas contain only `path` (no `confirm`); `delete_artifact` is the only Wave 1/2 tool with a `confirm` parameter | 1 | Legacy `Tools/AssistDeleteFileTool.swift`, `Tools/AssistDeleteDirectoryTool.swift`, `Tools/AssistDeleteArtifactTool.swift`, read directly |
| Legacy side channels: `LiveDiffStreamer` calls, `XcodeProjWriter.addFileReference`, `ProjectSessionStore.recordAssistFileMutation`, `suggestedNextActions` | 1 | Legacy `Tools/AssistWriteFileTool.swift`, `AssistCreateFileTool.swift`, `AssistReplaceInFileTool.swift`, `AssistInsertCodeBlockTool.swift`, `AssistGenerateFileTool.swift`, `AssistCopyFileTool.swift`, read directly |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
