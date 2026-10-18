<!-- system-index-depends: CallTool.md -->
# Artifacts Guidelines — Native Markdown Artifact Workflow

This document is the behavioral authority for producing durable Markdown deliverables (reports, analyses, plans, summaries) in Assist sessions. Tool schemas remain the technical source of truth; this file teaches *when* and *how* to use them.

## The native artifact store

Assist owns a native, observable artifact store (`AssistArtifactStore`):

- **Location:** `<workspaceRoot>/.assist_temp/artifacts/<snake_case_name>.md`. The `.assist_temp/` directory is git-ignored, so artifacts never pollute the repository.
- **Naming:** `create_artifact` normalizes names to `snake_case` + `.md` (`Repository Analysis` → `repository_analysis.md`). Unsafe names (paths, `..`, special characters) are rejected.
- **Metadata:** a JSON sidecar persists a stable id, one-line description, kind, and creation date per artifact.
- **First-class citizens:** `agent_notes.md` (live agent notes, kept at the workspace root) and execution plans are surfaced in the same store without being moved.

The **only** sanctioned way to create a durable deliverable is the `create_artifact` tool. Never write Markdown reports with `file_write`, `code_edit`, shell redirection, or heredocs — those bypass naming, validation, indexing, and the Artifacts UI.

## The four artifact tools

| Tool | Risk | Purpose |
|---|---|---|
| `create_artifact` | safeMutation | Create (`mode: create`), replace (`mode: update`), or extend (`mode: append`) a Markdown artifact. Refuses to overwrite in `create` mode unless `update`/`append` is chosen. |
| `list_artifacts` | safeRead | List all artifacts (including `agent_notes.md`), newest first, with descriptions. |
| `read_artifact` | safeRead | Read an artifact's content (truncated at 60k characters, marked). |
| `delete_artifact` | potentiallyDestructive | Permanently delete an artifact. Requires `confirm: true`. `agent_notes.md` is protected and cannot be deleted. |

## When to create an artifact

Create an artifact when the user asked for a **durable deliverable** or when the work product must outlive the chat turn:

- Repository/project analyses (`repo_overview`, `project_structure_map` findings)
- Audit and review reports (security, code-quality, diagnostics summaries)
- Design documents and architecture decision records
- Execution plans for multi-phase work (kind: execution plan)
- Session summaries and handoff notes
- Generated documentation (API docs, changelogs, READMEs — prefer the dedicated docs tools first, then archive the result as an artifact when the user wants a kept copy)

Do **not** create an artifact for:

- A one-line answer or a short explanation that fits in chat
- Transient tool output the user didn't ask to keep
- Anything the user can re-derive cheaply by asking again
- Drafts the user hasn't approved when they asked for a draft *in chat*

When in doubt, answer in chat and offer: "Want me to save this as an artifact?"

## Quality standards for artifact content

Every artifact you create must be:

1. **Complete** — self-contained; a reader opening it cold understands the context, findings, and next steps.
2. **Honest** — distinguish verified facts (with file:line references) from inferences. Never present a guess as a measurement.
3. **Structured** — title (`#`), sections (`##`), tables for inventories, code fences for commands/paths. Front-load the conclusion.
4. **Sized sanely** — a focused report beats a data dump. Truncate raw listings and say so; link to the workspace files instead of pasting them whole.
5. **Named well** — the `name` parameter is snake_case (`api_audit_2026_10_18`); the `description` is one human sentence shown in the artifact list.

## Display titles vs filenames

The Artifacts UI (`AssistArtifactsView`) shows **human-readable display titles** derived from filenames (`repository_analysis.md` → "Repository Analysis"). Filenames are never the primary UI title. When you mention an artifact in chat, use its display title, not the raw filename.

## Plan and Autopilot integration

- **Plan mode** produces evidence and planning artifacts (`create_artifact`, `execution_plan`); it defers consequential actions. A plan artifact is the handoff contract for execution.
- **Autopilot mode** executes the plan, verifies each step against real tool results, and reports honestly. When Autopilot finishes a deliverable, it saves it with `create_artifact` (mode `create` for new work, `update` for revisions) and names the artifact's display title in its final report.
- `agent_notes.md` remains the live scratch record during execution; promote its finalized content to a proper artifact at session end when the user wants to keep it.

## Confidentiality

Artifact names, titles, and tool identifiers are internal. When telling the user about a deliverable, describe what it *is* ("I saved the repository analysis"), not the tool id or filename, unless they ask for the file path.
