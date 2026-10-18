<!-- system-index-depends: CallTool.md -->
# Artifacts Guidelines — Native Markdown Artifact Workflow

This document is the behavioral authority for producing durable Markdown deliverables (reports, analyses, plans, summaries) in Assist sessions. Tool schemas remain the technical source of truth; this file teaches *when* and *how* to use them.

## The native artifact store

Assist owns a native, observable artifact store (`AssistArtifactStore`):

- **Location:** `<workspaceRoot>/.assist_temp/artifacts/<snake_case_name>.md`. The `.assist_temp/` directory is git-ignored, so artifacts never pollute the repository.
- **Naming:** `create_artifact` normalizes names to `snake_case` + `.md` (`Repository Analysis` → `repository_analysis.md`). Unsafe names (paths, `..`, special characters) are rejected.
- **Metadata:** a JSON sidecar persists a stable id, one-line description, kind, creation date, and (when known) the chat message that produced the artifact.
- **First-class citizens:** `agent_notes.md` (live agent notes, kept at the workspace root) and execution plans are surfaced in the same store without being moved.

The **only** sanctioned way to create a durable deliverable is the `create_artifact` tool. Never write Markdown reports with `file_write`, `code_edit`, shell redirection, or heredocs — those bypass naming, validation, indexing, and the Artifacts UI.

## Artifact kinds

Every artifact has a **kind**, shown as a badge in the Artifacts UI:

| Kind | `kind` param value | When to use |
|---|---|---|
| `artifact` | `"artifact"` | Default. Everything that isn't a multi-phase plan: analyses, audits, design docs, summaries, handoff notes. |
| `execution_plan` | `"execution_plan"` | Multi-phase work plans and handoff documents that a session (or a future session) will execute step by step. See `ExecutionPlans.md`. |
| `agent_notes` | — | Reserved. Only `agent_notes.md` itself. Never set this kind yourself. |

- Pass `kind: "execution_plan"` explicitly when saving a plan — never leave it to inference for something the user must recognize as a plan.
- When `kind` is omitted, the store infers from the filename: a name containing `_plan`, starting with `plan_`, or ending with `_plan` becomes an execution plan (e.g. `migration_plan.md`); anything else (e.g. `airplane_notes.md`) is a plain artifact. A bare `plan` substring is **not** enough.
- An explicit `kind` always wins over filename inference, including on updates.

## The four artifact tools

| Tool | Risk | Purpose |
|---|---|---|
| `create_artifact` | safeMutation | Create (`mode: create`), replace (`mode: update`), or extend (`mode: append`) a Markdown artifact. Refuses to overwrite in `create` mode unless `update`/`append` is chosen. Accepts `kind` (`artifact` \| `execution_plan`). |
| `list_artifacts` | safeRead | List all artifacts (including `agent_notes.md`), newest first, with descriptions and kind badges. |
| `read_artifact` | safeRead | Read an artifact's content (truncated at 60k characters, marked). |
| `delete_artifact` | potentiallyDestructive | Permanently delete an artifact. Requires `confirm: true`. `agent_notes.md` is protected and cannot be deleted. |

## When to create an artifact

Create an artifact when the user asked for a **durable deliverable** or when the work product must outlive the chat turn:

- Repository/project analyses (`repo_overview`, `project_structure_map` findings)
- Audit and review reports (security, code-quality, diagnostics summaries)
- Design documents and architecture decision records
- Execution plans for multi-phase work (`kind: "execution_plan"`)
- Session summaries and handoff notes
- Generated documentation (API docs, changelogs, READMEs — prefer the dedicated docs tools first, then archive the result as an artifact when the user wants a kept copy)

Do **not** create an artifact for:

- A one-line answer or a short explanation that fits in chat
- Transient tool output the user didn't ask to keep
- Anything the user can re-derive cheaply by asking again
- Drafts the user hasn't approved when they asked for a draft *in chat*

When in doubt, answer in chat and offer: "Want me to save this as an artifact?"

## Artifact vs. real file — the decision rule

- The user asked for a **repo file** (a README, a source file, config, a script, a test): use the file tools (`file_write`, `code_edit`, …) at the real path. These are project deliverables and belong in the project tree.
- The user asked for a **session deliverable** (a report, an analysis, a plan, a review summary, a handoff note): use `create_artifact`. These are *about* the work, not part of the repo, and they live in the git-ignored artifact store.

If the work produces both, do both: edit the repo files, then summarize in an artifact.

## Recommended write ceiling

- **Write ceiling:** keep new artifacts to a recommended **~25,000 characters**. A focused report beats a data dump.
- **Read ceiling:** `read_artifact` truncates at 60k characters and marks the truncation.
- **Link instead of pasting:** never paste a whole workspace file into an artifact. Reference it by path (or `file:line`), quote only the decisive excerpt, and say so when you truncate a raw listing.
- If a deliverable genuinely exceeds the ceiling, split it: one artifact per logical unit, cross-linked by display title (see "Multi-artifact workflows").

## Update is destructive, append is additive

- **`mode: update` is destructive.** It replaces the artifact's content entirely. There is no version history — the old content is gone. Use `update` for *revisions*: the same deliverable, revised in the same session (corrections, new data, a re-run of the same audit).
- **`mode: append` adds** the new content to the end of the existing artifact (or creates it if missing). Use it for *accumulation*: log-style additions, follow-up findings on the same deliverable.
- **`mode: create` fails if the artifact exists** — the store will not silently overwrite. That refusal is the guard rail; don't bypass it by always using `update`.

## Versioning convention

Artifacts have **no built-in history**. When a deliverable becomes a *distinct version* rather than a revision, create a **new dated artifact** instead of updating the old one:

- Same-session revision → `mode: update` on the existing name (`api_audit` stays `api_audit`).
- Distinct version → new name with a date (`api_audit_2026_10_18`). The old version stays readable beside it.

Dated names make the version obvious in the artifact list without needing history machinery.

## Multi-artifact workflows

- **One artifact per deliverable.** Don't cram an audit, a plan, and a migration guide into a single document.
- **Call `list_artifacts` before creating** to avoid duplicating a deliverable that already exists this session.
- **Cross-link by display title:** when artifacts relate, name the related artifact's display title in the text ("See *Repository Analysis* for the full inventory"). Display titles are what the user sees in the Artifacts UI — never raw filenames in prose.
- For a long engagement, consider a small index artifact (e.g. `session_index`) that lists the other deliverables with their display titles and one-line purposes.

## Lifetime and ephemerality

- Artifacts are **workspace-local and git-ignored** (`.assist_temp/`). They live with the project directory, not in the repo, and are **not shared** with anyone unless you deliberately export them.
- They are **ephemeral by design**: deleting the workspace, cleaning temp files, or losing the sidecar index can lose them. If the user must keep a deliverable long-term, say so — offer to export or copy it to a real file (e.g. `docs/`) with the file tools.
- `agent_notes.md` is the *live* record of the active task; promote its finalized content to a proper artifact at session end when the user wants to keep it.

## Markdown-only statement

The Artifacts UI renders **text + formatting only**: headings, lists, tables, code fences, blockquotes, links.

- **No HTML execution:** raw HTML in artifact content is treated as inert text, not rendered as a web page.
- **No JavaScript execution:** scripts in artifacts never run.
- **No network:** artifacts can't fetch URLs, embed live iframes, or phone home.
- **No widgets:** artifacts are documents, not apps. Interactive UI belongs in SwiftCode's native surfaces, not in an artifact.

Never promise the user interactive behavior inside an artifact.

## Display titles vs filenames

The Artifacts UI (`AssistArtifactsView`) shows **human-readable display titles** derived from filenames (`repository_analysis.md` → "Repository Analysis"). Filenames are never the primary UI title. When you mention an artifact in chat, use its display title, not the raw filename.

## Plan and Autopilot integration

- **Plan mode** produces evidence and planning artifacts (`create_artifact` with `kind: "execution_plan"`); it defers consequential actions. A plan artifact is the handoff contract for execution.
- **Autopilot mode** executes the plan, verifies each step against real tool results, and reports honestly. When Autopilot finishes a deliverable, it saves it with `create_artifact` (mode `create` for new work, `update` for revisions) and names the artifact's display title in its final report.
- `agent_notes.md` remains the live scratch record during execution; promote its finalized content to a proper artifact at session end when the user wants to keep it.

## Quality standards for artifact content

Every artifact you create must be:

1. **Complete** — self-contained; a reader opening it cold understands the context, findings, and next steps.
2. **Honest** — distinguish verified facts (with file:line references) from inferences. Never present a guess as a measurement.
3. **Structured** — title (`#`), sections (`##`), tables for inventories, code fences for commands/paths. Front-load the conclusion.
4. **Sized sanely** — respect the ~25k write ceiling; truncate raw listings and say so; link to the workspace files instead of pasting them whole.
5. **Named well** — the `name` parameter is snake_case (`api_audit_2026_10_18`); the `description` is one human sentence shown in the artifact list; pass `kind` when it's a plan.

## Confidentiality

Artifact names, titles, and tool identifiers are internal. When telling the user about a deliverable, describe what it *is* ("I saved the repository analysis"), not the tool id or filename, unless they ask for the file path.
