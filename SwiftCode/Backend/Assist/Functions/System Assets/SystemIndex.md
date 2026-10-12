# SystemIndex — Indexing and Retrieval Service Contract

SystemIndex is the authoritative runtime indexing and retrieval service for
the Markdown resources in `System Assets/`. It is a **runtime instruction
retrieval system, not model training**: documents are indexed locally,
relevant sections are retrieved per request, and instructions reach the model
only through its normal request context.

## Responsibilities

1. Discover every eligible `.md` file under the bundled `System Assets/`
   resources, including nested directories. No hardcoded filename list —
   new files become discoverable automatically.
2. Parse documents: stable document ID, relative source path, title, heading
   hierarchy, sections, chunks, content hash, and declared dependencies.
3. Split long documents into meaningful retrieval chunks along logical
   boundaries (headings, procedures with prerequisites, instruction lists,
   code examples with explanations). Preserve heading context and source
   metadata in every chunk. Never split a rule from its conditions or
   safeguards. Prefer structural chunking over fixed-length slicing.
4. Build a searchable lexical index (exact filename/title/heading lookup,
   keyword and phrase search, normalized text matching, relevance ranking,
   source filtering, deduplication, content-hash comparison).
   Semantic retrieval may be layered on later only if a local embedding
   capability genuinely exists — never a mandatory remote embedding service.
5. Persist the index locally (versioned JSON or equivalent, in an
   application-controlled location, separate from the source Markdown).
   Include a schema version and per-document content hashes. Validate before
   use; write atomically; recover from corruption by rebuilding from the
   bundled Markdown.
6. On startup: load the last valid index, validate schema and resource
   manifest, detect added/changed/removed documents, reindex only affected
   documents, persist safely, and publish an accurate readiness state.
   Never reparse the whole corpus because a view appeared; never force a
   full rebuild for an unchanged resource set.
7. Expose a provider-independent retrieval API returning structured,
   source-aware results: document ID, relative path, title, section heading,
   original instruction text, relevance score, retrieval reason, content
   hash. The request assembler decides what fits the budget.
8. Report indexing and retrieval failures explicitly. A retrieval failure
   must not silently bypass safeguards — if instructions cannot be retrieved,
   the request proceeds only with baseline safeguards or fails closed with a
   descriptive error.

## Dependency convention

A document may declare related documents near its top:

```html
<!-- system-index-depends: Safeguards.md, CallTool.md -->
```

SystemIndex resolves these transitively at retrieval time, deduplicates
chunks, and prevents circular or unbounded expansion. `AgentSystemAsset.md`
is the human-readable navigation structure; SystemIndex performs the actual
search and dependency resolution.

## Request-scoped retrieval metadata

The runtime tracks, per request/session: which documents and chunks were
retrieved, why, and how much context they consume. This lets later agentic
iterations avoid re-injecting the same instructions while recognizing when
*new* instructions are needed (e.g. a coding discussion that turns into a
destructive file operation retrieves `FileOperations.md` and safeguards
before authorizing it). Retrieval state is isolated per conversation; clearing
a conversation clears its retrieval metadata but never the shared index.

## Context budgeting

Retrieval is separate from injection. SystemIndex ranks; the request
assembler selects under the model's context constraints per
`ContextBudgeting.md`: mandatory safeguards first, then baseline identity,
then ranked task-specific sections and their dependencies. Token estimates
use a supported tokenizer when available, otherwise a documented conservative
estimate (~4 characters per token), labeled as an estimate. Indexing and
retrieval stay provider-independent; each adapter applies its own budget
rules to the same canonical index.

## Availability across the lifecycle

The same shared retrieval interface serves every supported model path —
Antigravity SDK models, Google models on the Antigravity account flow,
direct Gemini API models, OpenAI-compatible APIs, Claude/external providers,
local models, and custom endpoints — at initial preparation, tool-call
generation, tool authorization, follow-up iterations, fallback, and error
recovery. Every model gets access to the same knowledge; no model receives
the whole corpus on any request.

## Failure semantics

- Missing or malformed resources: explicit error, never silent.
- Corrupted cache: rebuild from bundled resources, never treat the index as
  the only copy of the instructions.
- Index not ready: retrieval reports unavailable; the runtime distinguishes
  "no results" from "index failure" and does not confuse the two.
- Bundled resources missing at runtime (packaging defect): explicit,
  actionable diagnostic — the Xcode build must bundle every eligible
  `.md` file and preserve the directory structure.
