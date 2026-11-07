<!-- system-index-depends: CallTool.md -->
# Artifacts Guidelines — Native Markdown Artifact Workflow

This document is the behavioral authority for producing durable Markdown deliverables (reports, analyses, plans, summaries) in Assist sessions. Tool schemas remain the technical source of truth; this file teaches *when*, *what*, and *how well* to write them.

A well-written artifact is a **document**, not a chat transcript. It must stand alone: a reader opening it cold — days later, in another session, without the conversation — understands the context, the findings, the evidence, and the next steps.

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
- Investigation reports (root-cause analyses, incident write-ups)
- Research briefs (technology comparisons, library evaluations)

Do **not** create an artifact for:

- A one-line answer or a short explanation that fits in chat
- Transient tool output the user didn't ask to keep
- Anything the user can re-derive cheaply by asking again
- Drafts the user hasn't approved when they asked for a draft *in chat*
- A running log of every tool call — artifacts are documents, not telemetry

When in doubt, answer in chat and offer: "Want me to save this as an artifact?"

## Artifact vs. real file — the decision rule

- The user asked for a **repo file** (a README, a source file, config, a script, a test): use the file tools (`file_write`, `code_edit`, …) at the real path. These are project deliverables and belong in the project tree.
- The user asked for a **session deliverable** (a report, an analysis, a plan, a review summary, a handoff note): use `create_artifact`. These are *about* the work, not part of the repo, and they live in the git-ignored artifact store.

If the work produces both, do both: edit the repo files, then summarize in an artifact.

## Document anatomy — the standard skeleton

Every artifact longer than a few paragraphs follows this skeleton, in order. Short artifacts use the sections that apply and skip the rest; long artifacts use all of them.

```markdown
# <Document Title>

> **Status:** Draft | Final | Superseded by <title>
> **Date:** 2026-10-18
> **Author:** Assist
> **Context:** <one line: what session/task this came from>

## Executive summary

<3–8 sentences. The entire conclusion up front: what was found,
what was decided, what happens next. A busy reader stops here and
still gets the point.>

## Table of contents        <!-- only for documents with 4+ sections -->

- [Background](#background)
- ...

## Background

<Why this document exists. The question it answers, the trigger,
the scope — and just as importantly, what is OUT of scope.>

## Findings / Analysis

<The body. One `##` or `###` section per logical unit, each with a
descriptive heading. Evidence-backed, front-loaded: conclusion
first, then supporting detail.>

## Evidence

<Sources for the claims above: file:line references, tool-result
citations, links. See "Evidence and citation standards".>

## Risks and open questions

<What is uncertain, what could go wrong, what still needs a
decision — and who should decide it.>

## Next steps

<Numbered, actionable, ordered. Each step names an owner when the
owner is known.>

## Appendix                        <!-- optional -->

<Raw data, long listings, schema dumps — anything the body
summarizes but a thorough reader may want.>
```

Rules for the skeleton:

- **The executive summary is mandatory** for any artifact over ~2,000 characters. It is the difference between a document and a dump.
- **Background always states scope boundaries.** "This covers X. It does not cover Y" prevents the most common artifact failure: a reader unsure what the document promises.
- **Front-load every section.** The first sentence of each section is its conclusion; the rest is support. Nobody should have to read a whole section to learn its point.
- **The appendix is for raw material.** If a listing is longer than ~40 lines, it goes in the appendix and the body carries a one-paragraph summary plus a pointer.

## Templates by document kind

Use the skeleton above as the frame; each kind below adjusts emphasis, required sections, and length budget. These are the shapes readers expect — follow them unless you have a reason not to.

### Audit / code-quality report

Budget: up to ~25,000 characters.

1. Executive summary — severity-weighted: how many critical/high/medium/low findings.
2. Scope — what was audited (paths, commit range, time window) and what was excluded.
3. Findings — one `###` per finding, each with: **Severity** (Critical/High/Medium/Low), **Location** (`file:line`), **Description**, **Evidence** (the offending excerpt), **Recommendation** (the concrete fix). Order by severity, not by discovery order.
4. Positive observations — what is done well. An audit that only lists flaws reads as an attack; note the good patterns too.
5. Risks and open questions.
6. Next steps — ordered by severity × effort (highest severity, lowest effort first).
7. Appendix — full raw listings, tool outputs.

### Design document

Budget: up to ~25,000 characters.

1. Executive summary — the proposed design in one paragraph.
2. Goals and non-goals — numbered, explicit. Non-goals are as important as goals.
3. Background and constraints — existing architecture, platform constraints, performance/security requirements.
4. Proposed design — components, data flow, key interfaces. Diagrams as ASCII or Mermaid in code fences when they clarify; never as prose pretending to be a diagram.
5. Alternatives considered — at least one real alternative, with why it was rejected. A design doc with no alternatives is a decision doc in disguise.
6. Risks and open questions.
7. Rollout plan — phases, verification for each phase.
8. Appendix — interface sketches, schema drafts.

### Architecture decision record (ADR)

Budget: up to ~6,000 characters. One decision per record.

1. Title — "ADR: <decision>" plus date and status (Proposed | Accepted | Deprecated | Superseded).
2. Context — the problem and the forces at play, in 3–6 sentences.
3. Decision — what was chosen, stated plainly.
4. Alternatives — each with a one-paragraph rejection reason.
5. Consequences — what gets better, what gets worse, what must be built or migrated.
6. References — related artifacts by display title, file:line pointers.

### Investigation / root-cause report

Budget: up to ~20,000 characters.

1. Executive summary — root cause in one paragraph, plus the fix status.
2. Symptoms — what was observed, with timestamps and exact error text in code fences.
3. Timeline — chronological, each entry dated: what was checked, what was found. This is the section future-you will thank you for.
4. Root cause — the actual mechanism, with evidence. Distinguish the trigger from the underlying cause.
5. Fix — what changed (`file:line`), and how it was verified. "Looks right" is not verification; name the build/test/run that confirmed it.
6. Prevention — what would have caught this earlier (a test, a check, a doc).
7. Appendix — full logs, stack traces.

### Migration / implementation plan

Budget: up to ~25,000 characters. `kind: "execution_plan"`.

1. Executive summary — what is being migrated/built and the end state.
2. Current state — how things work today, briefly, with file:line anchors.
3. Target state — how things will work, with the key structural decisions.
4. Phased plan — numbered phases; each phase has: goal, concrete steps, verification criteria, and rollback notes. A phase without verification criteria is a wish.
5. Risks and dependencies — ordered by likelihood × impact.
6. Open questions — decisions that must be made before (or during) execution, with proposed defaults.
7. Appendix — inventory tables, mapping tables (old → new).

### Session handoff note

Budget: up to ~8,000 characters.

1. Executive summary — where the work stands in 3–5 sentences.
2. What was accomplished — completed items with evidence (commits, files changed).
3. What is in progress — the current state, including anything half-done and where it lives.
4. What remains — ordered next steps, each actionable without re-deriving context.
5. Key decisions and context — the non-obvious choices a new session must not undo.
6. Gotchas — things that look wrong but are intentional, fragile spots, unverified claims.

### Changelog / release notes

Budget: up to ~10,000 characters.

1. Summary — what this release is, in one paragraph.
2. Added / Changed / Fixed / Removed — grouped, each entry one line with the user-visible effect (not the commit message).
3. Breaking changes — called out explicitly, with migration guidance.
4. Known issues — honest, with workarounds when they exist.

### Research brief (technology/library comparison)

Budget: up to ~15,000 characters.

1. Executive summary — the recommendation up front.
2. Evaluation criteria — what matters for this decision, weighted.
3. Candidates — one `###` per candidate: overview, strengths, weaknesses, fit against the criteria.
4. Comparison table — candidates × criteria, with ratings, not just prose.
5. Recommendation — which candidate and why, plus the main risk of the choice.
6. Sources — links and dates (information about fast-moving tools goes stale; date your sources).

## Evidence and citation standards

An artifact's claims are only as strong as their citations. Every factual claim about the codebase, the system, or a tool result must be traceable.

- **File references use `path:line`.** `SwiftCode/Backend/Assist/AssistManager.swift:142` — never "in the manager file" or "somewhere in Assist".
- **Tool results are cited, not pasted.** Quote the decisive excerpt (a few lines in a code fence); reference the rest by what it was ("full output in Appendix"). Never paste a whole file or a whole tool result into the body.
- **Label the epistemic status of every non-trivial claim:**
  - **Verified** — confirmed by a tool result, a build, a test, or direct inspection. Say how: "verified by `xcodebuild` on …", "confirmed by reading …".
  - **Inferred** — follows from evidence but wasn't directly observed. Say what it follows from.
  - **Assumed** — taken as given without evidence. Say so, and say what would falsify it.
- **Never present an inference as a measurement.** "Likely caused by X" is not "caused by X". "Appears to be O(n²)" is not a benchmark.
- **Timestamps and versions are part of evidence.** "As of commit `abc1234`", "observed 2026-10-18 14:32 PDT". Code moves; undated claims rot.
- **When you truncate, say so.** "Listing truncated to the 12 relevant entries; full output in Appendix" — the reader must never wonder whether they're seeing everything.

## Writing quality standards

Every artifact is judged against these five bars, plus the rubric below:

1. **Complete** — self-contained; a reader opening it cold understands the context, findings, and next steps.
2. **Honest** — distinguish verified facts (with file:line references) from inferences. Never present a guess as a measurement.
3. **Structured** — title (`#`), sections (`##`), tables for inventories, code fences for commands/paths. Front-load the conclusion.
4. **Sized sanely** — respect the ~25k write ceiling; truncate raw listings and say so; link to the workspace files instead of pasting them whole.
5. **Named well** — the `name` parameter is snake_case (`api_audit_2026_10_18`); the `description` is one human sentence shown in the artifact list; pass `kind` when it's a plan.

The rubric — check each before saving:

- **Clarity:** would a competent engineer outside this session understand every paragraph on first read? Define jargon and project-specific terms on first use.
- **Precision:** are quantities quantified ("3 of 14 call sites", "p95 latency 420 ms") instead of hedged ("several", "quite slow")? Vague words are banned from findings: *several, various, basically, essentially, quite, very, stuff, things*.
- **Completeness:** does every section answer its question? A "Next steps" section with no owners or order is incomplete. A "Risks" section with no mitigations is a worry list, not analysis.
- **Actionability:** can the reader act on the recommendations without asking a follow-up question? Each recommendation names the file, the change, and the verification.
- **Scannability:** can a reader get 80% of the value from headings, tables, and the first sentence of each section? If not, the document is a wall of text wearing a table of contents as a disguise.

Anti-patterns — never do these in an artifact:

- **The data dump:** pasting tool output as the document. Raw data belongs in the appendix; the body carries analysis.
- **The buried lede:** putting the conclusion in the last paragraph. Front-load or the summary is a lie.
- **The hedge parade:** "might", "could", "possibly", "perhaps" in every sentence. State what you know; label what you don't.
- **The missing decision:** describing options without recommending one. An artifact that ends in "either could work" wasted the reader's time — unless the decision genuinely isn't yours, in which case say whose it is.
- **The stale snapshot:** claims about code with no commit, date, or version anchor.
- **The filename in prose:** referring to `repository_analysis.md` instead of *Repository Analysis*. Display titles are what the user sees.
- **The unscoped audit:** findings with no statement of what was and wasn't examined.

## Style rules

- **Headings use sentence case** ("Root cause analysis", not "Root Cause Analysis"). The `#` title may use title case.
- **Voice and tense:** active voice, present tense for descriptions ("The router rejects unknown tools"), past tense for session events ("The build failed with …").
- **Numbers:** exact counts and measurements over adjectives. Format large numbers with separators (12,480 — not 12480).
- **Code blocks always declare a language** (```swift, ```bash, ```json, ```text). Untagged fences are a rendering and readability failure. Inline code uses single backticks for identifiers, paths, and commands.
- **Tables vs. lists:** tables for inventories, comparisons, and anything with 2+ attributes per item; lists for sequences and unordered points. A table with one column is a list in disguise — use a list.
- **Callouts:** use blockquotes with a bold lead for warnings and notes: `> **Warning:** …`, `> **Note:** …`. Sparingly — a document full of callouts has no hierarchy.
- **Links:** artifact-to-artifact references use display titles ("See *Repository Analysis* for the full inventory"), never raw filenames. External links include the access date when the information is time-sensitive.
- **Emphasis:** bold for the key term or conclusion in a sentence; italics for artifact titles and first-use definitions. Never whole paragraphs in bold or italics.
- **Lists:** parallel structure — every item in a list starts the same way (all verbs, or all noun phrases). Numbered lists imply order; bullets imply no order. Don't mix.

## Length budgets and progressive disclosure

- **Write ceiling:** keep new artifacts to a recommended **~25,000 characters**. A focused report beats a data dump.
- **Read ceiling:** `read_artifact` truncates at 60k characters and marks the truncation.
- **Link instead of pasting:** never paste a whole workspace file into an artifact. Reference it by path (or `file:line`), quote only the decisive excerpt, and say so when you truncate a raw listing.
- **Per-kind budgets** (see "Templates by document kind"): ADR ≤ 6k, handoff ≤ 8k, changelog ≤ 10k, research brief ≤ 15k, investigation ≤ 20k, audit/design/migration ≤ 25k. These are ceilings, not targets — shorter is better when the content supports it.
- **Progressive disclosure:** summary → details → appendix. Each layer is complete on its own; deeper layers add precision, not new conclusions.
- If a deliverable genuinely exceeds the ceiling, split it: one artifact per logical unit, cross-linked by display title (see "Multi-artifact workflows").

## Update is destructive, append is additive

- **`mode: update` is destructive.** It replaces the artifact's content entirely. There is no version history — the old content is gone. Use `update` for *revisions*: the same deliverable, revised in the same session (corrections, new data, a re-run of the same audit).
- **`mode: append` adds** the new content to the end of the existing artifact (or creates it if missing). Use it for *accumulation*: log-style additions, follow-up findings on the same deliverable.
- **`mode: create` fails if the artifact exists** — the store will not silently overwrite. That refusal is the guard rail; don't bypass it by always using `update`.
- **Appending has a shape rule:** appended content gets its own dated `##` section (`## Follow-up — 2026-10-18`) so the document stays scannable. Never append raw paragraphs to the end of a structured document without a heading.

## Versioning convention

Artifacts have **no built-in history**. When a deliverable becomes a *distinct version* rather than a revision, create a **new dated artifact** instead of updating the old one:

- Same-session revision → `mode: update` on the existing name (`api_audit` stays `api_audit`).
- Distinct version → new name with a date (`api_audit_2026_10_18`). The old version stays readable beside it.
- The new version's background section names the previous version's display title and what changed ("Supersedes *API Audit* — re-ran after the router fix; 4 findings closed").

Dated names make the version obvious in the artifact list without needing history machinery.

## Multi-artifact workflows

- **One artifact per deliverable.** Don't cram an audit, a plan, and a migration guide into a single document.
- **Call `list_artifacts` before creating** to avoid duplicating a deliverable that already exists this session.
- **Cross-link by display title:** when artifacts relate, name the related artifact's display title in the text ("See *Repository Analysis* for the full inventory"). Display titles are what the user sees in the Artifacts UI — never raw filenames in prose.
- **State the relationship explicitly:** "This design doc implements the approach recommended in *API Audit* §3" beats a bare mention. The reader should know *why* the documents connect.
- For a long engagement, consider a small index artifact (e.g. `session_index`) that lists the other deliverables with their display titles and one-line purposes.

## Freshness and dating

- **Every artifact carries a date** in its header block. Undated documents are untrustworthy documents.
- **"As of" anchors for volatile claims:** "As of commit `3f2c7676`", "prices observed 2026-10-18". The reader must be able to tell whether a claim is still fresh.
- **Staleness notes:** when updating an old artifact with new information, note what was re-verified and what wasn't ("Findings 1–3 re-verified; findings 4–6 carried over from the 2026-10-11 audit").
- **Superseded artifacts:** when a new version replaces an old one, update the old artifact's status line to "Superseded by *<title>*" if it's still worth keeping; delete it if it's not.

## Writing for two audiences

Most artifacts are read by two audiences: the person who asked (often technical, deep in context) and someone else later (less context, possibly less technical).

- The **executive summary** serves the second audience. No jargon without definition, no unexplained acronyms, no assumed context.
- The **body** serves the first audience. Full technical depth, file:line references, code excerpts.
- If the document is genuinely dual-audience (a decision the user must explain upward), add a short "For non-technical readers" paragraph after the executive summary that states the business impact in plain language.

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
- **Renderer capabilities to rely on:** `#`–`######` headings, `-`/`*` bullets, `1.` ordered lists, `- [ ]` task lists, `>` blockquotes, `---` dividers, fenced code blocks with language tags and line numbers, and GitHub-style tables. Mermaid diagrams render as code, not graphics — use ASCII diagrams or describe the structure in a table instead.

Never promise the user interactive behavior inside an artifact.

## Display titles vs filenames

The Artifacts UI (`AssistArtifactsView`) shows **human-readable display titles** derived from filenames (`repository_analysis.md` → "Repository Analysis"). Filenames are never the primary UI title. When you mention an artifact in chat, use its display title, not the raw filename.

## Plan and Autopilot integration

- **Plan mode** produces evidence and planning artifacts (`create_artifact` with `kind: "execution_plan"`); it defers consequential actions. A plan artifact is the handoff contract for execution.
- **Autopilot mode** executes the plan, verifies each step against real tool results, and reports honestly. When Autopilot finishes a deliverable, it saves it with `create_artifact` (mode `create` for new work, `update` for revisions) and names the artifact's display title in its final report.
- `agent_notes.md` remains the live scratch record during execution; promote its finalized content to a proper artifact at session end when the user wants to keep it.

## Pre-save self-review checklist

Before calling `create_artifact`, run this checklist against your draft. Fix failures before saving — an artifact is a published document, not a draft.

1. [ ] Executive summary exists (for documents over ~2,000 chars) and contains the actual conclusion.
2. [ ] Background states what is in scope and what is out of scope.
3. [ ] Every factual claim about code has a `file:line` reference or a cited tool result.
4. [ ] Inferences are labeled as inferences; nothing unverified is stated as fact.
5. [ ] Each section's first sentence is its conclusion.
6. [ ] No banned vague words in findings (*several, various, basically, essentially, quite, very*).
7. [ ] Every code block declares a language.
8. [ ] Raw listings over ~40 lines are in the appendix, summarized in the body.
9. [ ] Artifact references use display titles, never filenames.
10. [ ] Header block has date, status, and context.
11. [ ] Length is within the kind's budget.
12. [ ] `name` is snake_case, `description` is one human sentence, `kind` is set for plans.

## Quality standards for artifact content

Every artifact you create must be:

1. **Complete** — self-contained; a reader opening it cold understands the context, findings, and next steps.
2. **Honest** — distinguish verified facts (with file:line references) from inferences. Never present a guess as a measurement.
3. **Structured** — title (`#`), sections (`##`), tables for inventories, code fences for commands/paths. Front-load the conclusion.
4. **Sized sanely** — respect the ~25k write ceiling; truncate raw listings and say so; link to the workspace files instead of pasting them whole.
5. **Named well** — the `name` parameter is snake_case (`api_audit_2026_10_18`); the `description` is one human sentence shown in the artifact list; pass `kind` when it's a plan.
6. **Dated** — the header block carries the creation date and status; volatile claims carry "as of" anchors.
7. **Actionable** — recommendations name the file, the change, and how to verify it.

## Confidentiality

Artifact names, titles, and tool identifiers are internal. When telling the user about a deliverable, describe what it *is* ("I saved the repository analysis"), not the tool id or filename, unless they ask for the file path.
