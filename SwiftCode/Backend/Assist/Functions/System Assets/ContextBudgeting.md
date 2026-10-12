# Context Budgeting

SystemIndex makes the whole instruction corpus *accessible*; the context
budget decides what is *supplied*. Never attach every indexed document to a
request. Rank first, then select under the model's real constraints.

## Budget order of preservation

When the budget is constrained, preserve in this order and record what was
omitted:

1. **Mandatory safeguards** — `Safeguards.md` is never dropped. If safeguards
   cannot be supplied, the request fails closed with a descriptive error.
2. **Essential baseline** — `Identity.md`.
3. **Most relevant task-specific sections** — by SystemIndex ranking.
4. **Their declared dependencies** — resolved transitively, deduplicated.
5. **Lower-relevance sections** — omitted first.

Reserve capacity for conversation context, tool schemas and tool results,
and the model's own response. Instruction text must never starve the
conversation or the tools of room to work.

## Ranking before selection

- Rank all candidate chunks (lexical signals: title/filename/heading matches,
  keyword and phrase overlap, section relevance, source priority, declared
  dependencies, task category, execution stage, already-retrieved state).
- Deduplicate overlapping chunks and repeated instructions before counting
  budget. A rule stated in two documents is supplied once, from the most
  specific document.
- Prefer complete small sections over fragments of large ones; never split a
  rule from its conditions or safeguards to save space.

## Token accounting

- Use a supported tokenizer when one is available for the selected model.
- Otherwise use a documented conservative estimate of **~4 characters per
  token**, and label it as an estimate wherever it is surfaced.
- Keep tokenization provider-specific and outside the index: the canonical
  index stores text and structure; each adapter applies its own budget math
  to the same retrieved chunks.
- Do not assume providers share message formats, system-role semantics, or
  context-window behavior. Adapt the *assembly*, never the canonical text.

## Recording and honesty

- Request-scoped retrieval metadata records which sections were selected,
  their relevance scores, and their estimated token cost.
- If budget pressure omits anything significant, record the omission.
- Never claim the model received instructions that were excluded.
- Never silently drop a safety or authorization requirement because of a
  context limit.

## Baseline sizing guidance

`Identity.md` and `Safeguards.md` are deliberately kept small enough to be
baseline on every request. Task-dependent documents stay focused so that a
typical retrieval — baseline plus two to four ranked sections with
dependencies — fits comfortably alongside conversation and tools. If a
document grows too large to retrieve usefully, split it along its logical
boundaries rather than letting the budget silently truncate it.
