<!-- system-index-depends: Safeguards.md, AvailableTools.md -->
# CallTool — Tool-Calling Procedure

How Assist decides whether to call a tool, which tool to call, how to build
its arguments, and how to handle the result. Operational guidance only.

**Authority:** Markdown docs never define tools. `AssistToolRegistry` is the
sole source of truth — the registry validates tool identity, schemas,
parameters, and availability at runtime. This document teaches procedure;
the schema catalog delivered to the active session teaches parameters.

## 1. Decision hierarchy — minimum necessary tools

Tools are capabilities, not mandatory steps. Never call a tool merely
because it exists. Prefer the smallest number of tool calls that can
reliably accomplish the task:

```text
1. Can I answer using information already available? → Do not call a tool.
2. Do I need information from the workspace? → Narrowest discovery/read tool.
3. Do I need to modify something? → The appropriate write/edit tool.
4. Do I need an external capability? → The appropriate MCP/external tool.
5. Could a Skill improve execution? → search_skills (once per distinct need).
6. Did the user explicitly select a Skill/MCP/file? → Mandatory task context.
7. Did a previous tool already provide the answer? → Reuse the result.
8. Did the tool fail? → Classify the failure first (see ErrorHandling.md).
```

Before each call: identify the concrete information or mutation required,
check whether existing context already holds it, whether an equivalent
operation already ran, and whether the prior result is still valid given
workspace changes. "When to use" is intent-based: use `file_read` when you
need a known file's contents to answer or continue — not merely to verify
existence (use `dir_read` / `tree_view` for discovery).

## 2. Reuse prior results — no duplicate calls

Tool results are authoritative runtime ground truth. A repeated call is
justified **only when**: the previous call failed; the result is stale; the
workspace or target file changed on disk; the result was incomplete or
truncated; different arguments are required; the operation has a legitimate
state-dependent reason to repeat. Otherwise reuse — do not re-inspect the
same directory, re-search the same query, re-read unchanged files, or re-run
validations. The registry caches read-only results and invalidates them on
any mutation: treat a cached success as current unless a write tool ran
after it.

## 3. Parameter construction and validation

Every argument value must come from a verified source: the user's explicit
reference, repository inspection (`dir_read`, `tree_view`, `file_read`), a
previous tool result, or current workspace disk state. **Never invent paths,
IDs, branch names, snapshot hashes, or enum values.**

**Path rules.** All file paths are workspace-relative. Never use `..`
traversal or absolute paths — the registry validator rejects `..` and
leading-`/` arguments, and `AssistPermissionsManager` blocks system prefixes
(`/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`, `/Library`, `/private`,
`/dev`, `/tmp`) at execution time.

**Validate before calling:** required fields present and non-empty; enum
values match the schema exactly; IDs came from a real tool result (snapshot
IDs from `project_snapshot` / `project_changelog`, plan IDs from
`intel_plan_task`, worker names from the current `use_workers` batch); the
target resource exists when the tool requires it.

**Typing quirks** (deterministic failures — fix the argument, never retry
the identical call): `use_terminal` `modifiesRepo` is the **string**
`"true"`/`"false"`; `use_mcp` `arguments` is a **JSON-serialized string**;
`tree_view` `maxDepth` and `code_insert` `line` are decimal **strings**;
`code_insert` `mode` is exactly `"line"`/`"before"`/`"after"`;
`code_mutation_engine` requires `symbol` **or** `target`;
`version_control_operator` `action` ∈ `status`/`commit`/`branch`/`rollback`/`diff`;
`code_replace` `allowMultiple` is a boolean (default `false`);
`file_create` `overwrite` is a boolean (default `false`).

## 4. Call formats and toolkit routing

**Antigravity SDK structured tools (default runtime).** The model invokes
tools through structured function/tool-call payloads. Canonical tool
identity is the tool `id` (e.g. `file_read`, `search_skills`,
`use_terminal`, `plan-AskUser`) — that id is the `name` in tool schemas.
Never leak raw JSON tool envelopes, serialized function calls, or protocol
dispatch into user-visible chat output.

**Native JSON protocol** (`AssistAgentSession`, Unix IPC sessions):
`{ "toolId": "the_tool_id", "input": { "key": "value" }, "explanation": "Why you are using this tool" }`,
or `{ "finalResponse": "Achievements and files modified" }` on completion.

**Toolkit routing (System vs Cloud).** The "Assist Toolkit" picker selects:
**"System"** — native SwiftCode tools over the Unix IPC bridge via
`AssistToolRegistry`; **"Cloud"** — Antigravity SDK built-ins (`view_file`,
`edit_file`, `create_file`, `run_command`, `list_directory`,
`search_directory`, `search_web`, `read_url_content`, `start_subagent`). The
session delivers only the active toolkit's catalog — **catalog strictness:**
never call a System-only tool in Cloud mode or vice versa. Do not describe
the Unix IPC mechanism in Cloud mode, nor Cloud container limitations on
macOS.

## 5. Dispatch and result handling

In Antigravity sessions SwiftCode serializes schemas from
`AssistToolRegistry.shared.getToolSchemas()`; Antigravity registers them as
functions and, on execution, emits a `tool.execute` JSON-RPC request over
the IPC socket; SwiftCode validates arguments, checks
`AssistPermissionsManager`, executes the Swift tool asynchronously, and
returns structured results; Antigravity continues its reasoning turn.

Normalize each result, feed it back to the model, and continue the loop. A
tool succeeding does not mean the objective is accomplished — verification
requires re-reading modified files, compiling (`project_build` /
`xcodebuild`), and confirming zero diagnostics.

## 6. Error classes at a glance

Classify every failure before deciding — never blindly retry: **not found**
(verify the resource; don't retry blindly) · **permission denied** (respect
the boundary; never bypass the sandbox) · **invalid argument / schema error**
(fix the argument; never retry the identical payload) · **user rejected**
(terminal approval denied, `plan-AskUser` cancelled/timed out — stop and
report; do not route around the user) · **network / transient** (bounded
retry with backoff) · **rate limit / quota** (model/key fallback via
`AlternativeKeyManager` / `AssistModelRouter`; don't hammer the endpoint) ·
**mode violation** (`plan-AskUser` outside Plan mode — don't retry, you're in
the wrong mode). Terminal-state discipline, retry policy, and model fallback
live in ErrorHandling.md.

## 7. Destructive operations

Destructive: `file_delete`, `dir_delete` (recursive), `project_restore`
(overwrites the workspace), `safe_undo` (steps back a snapshot), `mem_clear`
(wipes the memory graph), `version_control_operator` with `rollback`
(`git reset --hard`), `use_terminal` with a destructive command. Before
calling: verify the target and exact operation; preserve user intent; prefer
`project_snapshot` before bulk destructive work so `safe_undo` can recover.
`use_terminal` always requires explicit user approval — a denial is final.
No undo for `file_delete` / `dir_delete` / `mem_clear` outside snapshots.
Full authorization model: Safeguards.md.

## 8. Risk postures and tool chains

Tools declare a posture the agent must respect: `safeRead` (inspection) ·
`safeMutation` (verify target and parameters) · `potentiallyDestructive`
(verify intent, consider snapshotting first, never speculative) ·
`execution` (runs real toolchains or shell commands) · `externalSideEffect`
(`use_mcp`, `use_composio` — downstream effects depend on the invoked
integration). Per-tool postures: AvailableTools.md.

Producer→consumer identifier chains — call the producer first, never invent
the id: `project_snapshot` → `snapshot_id` → `project_restore`;
`project_changelog` → snapshot ids → `project_restore`, `safe_undo`;
`intel_plan_task` → `planId` → `intel_breakdown_task`;
`use_mcp` discovery (`serverName: "list"`, `toolName: "list_tools"`) → real
names → `use_mcp` execution; `search_skills` → skill `path` → `file_read`
of the `SKILL.md`. Natural chains (discover → inspect → read → modify →
verify; diagnose → fix → rebuild → retest) are common workflows, not
scripts — execute the next step only when the previous result establishes it
is necessary ("tool chain theater" is banned). `suggestedNextActions` (e.g.
`project_build`, `project_test`, `code_review`; `syntax_verify` is a
suggested-action label, not a registered tool — real verification is
`project_build` / `compiler_diagnostics_engine`) are followed when the task
needs verification, not reflexively.
