# Contexts.md — Conversation Lifecycle & Context Management

How Assist owns the session transcript, persists durable memory, retrieves prior context,
snapshots environment state, and defines what "reset" means.

---

## 1. Session Transcript Ownership

- The transcript is the authoritative record of the conversation. Never rewrite, summarize
  away, or re-present earlier turns as new work.
- On-disk state is the authoritative record of the workspace. When the two disagree,
  the disk wins — inspect it rather than assuming prior tool effects were rolled back.
- Never leak retrieval metadata (cache keys, snapshot IDs, graph node counts) into the
  user-facing conversation; it belongs in tool channels, not chat.

## 2. Durable Memory Conventions

- Persist **durable facts**: design decisions, identifiers, project state, user-stated
  preferences. Store once with a stable, unique key; a store under an existing key
  overwrites the old value — use that deliberately, not accidentally.
- **Retrieve before recomputing.** Before searching the disk again or asking the user
  again, check whether the fact is already stored. If a key lookup fails, the fact was
  never stored — do not retry the same key; establish the fact fresh.
- Memory writes are scoped to facts worth keeping across turns, not execution debris
  (exit codes, intermediate paths, one-off tool outputs).
- Memory stores are lighter-weight than the full memory graph for simple key/value
  context; choose the mechanism that fits the payload, not a bigger one by default.

## 3. Memory Clearing — Strict Limits

- Memory is wiped **only** on explicit user instruction to forget. It is never used as
  general cleanup, a reset mechanism, or speculative hygiene.
- Clearing is irreversible: all stored memory entries in the graph are deleted and are
  not recoverable. If the user's instruction is ambiguous, confirm what they want
  cleared before acting — never guess.

## 4. Context Snapshots

- Snapshot current environment state (open buffers, workspace layout, editor context)
  when a session may need to resume later or hand off between workers.
- Each snapshot call stores a new payload and returns its identifier; snapshots are
  append-only reference points, not rollbacks.
- Resume from a snapshot by loading it and then re-verifying against live disk state —
  a snapshot describes the past, not the present.

## 5. Retrieving Prior Context

- To find prior work in the codebase, prefer the most precise discovery tool first:
  - `search_symbol` — locating declarations (classes, structs, functions) by name.
  - `search_text` — literal references and call sites; not for patterns or symbols.
  - `search_regex` — pattern-based searches (signatures, annotations); fix invalid
    pattern syntax rather than retrying blindly.
  - `dependency_graph` — module/import/architecture relationships across Swift files.
- Look up stored memory and snapshots before expensive re-derivation.
- Carry forward the session trajectory: what was tried, what failed, and what was
  already verified.

## 6. Session Reset Semantics

Clearing a conversation is **narrow and well-defined**:

- **Cleared:** transient execution state (in-flight tasks, partial drafts, queued turns)
  and request-scoped retrieval metadata (per-request search/snapshot bookkeeping).
- **Never cleared:** the shared SystemIndex cache, persisted memory entries, context
  snapshots, on-disk changes, or shipped assets.

A reset ends the current line of thinking — it does not erase the shared foundation
another turn may still need.

## 7. Multi-Turn Continuation

- Build directly on completed work: do not redo setup, re-read unchanged files, or
  restart a plan because a new turn began.
- After any pause or reset, inspect the live workspace state first, then continue from
  the last valid checkpoint without repeating completed steps.
- Treat a resumed conversation as a natural pause in an ongoing dialogue, not a new
  session.
