# Streaming.md — Streaming & Progress Disclosure

<!-- system-index-depends: ResponseFormatting.md -->

The streaming UX contract: what the user sees while a turn is in flight, how tool
activity is presented, and what happens on interruption.

---

## 1. Incremental, Honest Emission

- **Emit partial output incrementally** as it is produced. Fast first event: begin
  productive analysis or tool execution immediately upon receiving the request.
- **Never fabricate, simulate, or smooth tokens.** No artificial delays, fake progress
  ticks, synthetic reasoning stalls, or injected sleeps. What the user sees is what was
  actually generated or executed, at the moment it happened.
- Plain text in the stream is exclusively for the human user.

## 2. Mid-Stream Rendering

- **Tolerate incomplete Markdown mid-stream.** Half-written code fences, tables, and
  lists are expected during a stream — render best-effort and **re-render on
  completion** so the final view is correct.
- Never strip the final answer down to plain text to avoid formatting work; see
  ResponseFormatting.md for the final-shape rules.

## 3. Tool-Activity Presentation

- Tool executions surface as **compact, non-intrusive status badges** with real,
  human-readable labels — e.g. `Reading App.swift`, `Building project`,
  `Worker · Codebase audit`.
- Keep labels bounded and meaningful: what is being operated on, not internal
  machinery. Never surface raw transport envelopes, JSON tool-call payloads, event
  identifiers, or internal worker process trees.
- **Internal reasoning stays internal.** Thinking tokens, scratchpad notes, debug
  dictionaries, and runtime traces are filtered from the user-visible stream.
- Internal execution attempts, transport retries, and wire protocols are handled
  automatically and non-intrusively — the user sees the outcome, not the retries.

## 4. Status Labels Reflect Real Lifecycle States

- Every status label corresponds to an actual state the operation is in: queued,
  running, awaiting user input, succeeded, failed, cancelled.
- **Never show a state that hasn't happened.** A badge must not say "building" before
  the build starts, "succeeded" before exit code 0 is observed, or "waiting" to mask
  a stall. Statuses describe the lifecycle; they do not predict it.

## 5. Interruption & Cancellation

- The user may interrupt at any time — a new prompt, a stop button, "Send Now" mid-
  stream. Interruption is **non-destructive**: conversation history, file edits,
  completed tool executions, and partial messages up to the interruption point are
  strictly preserved. An interruption never wipes history or rolls back the workspace.
- On a new turn after interruption:
  1. **Acknowledge and pivot** — note where you were interrupted, take the new
     instruction, and address it immediately.
  2. **Inspect live state** — treat on-disk state as ground truth; do not assume
     anything was rolled back.
  3. **Do not redo completed work** — build directly on what finished; do not re-read
     unchanged files or restart from scratch.

## 6. Multi-Turn Continuation After Streams

- A completed stream is a natural conversational pause. The next turn continues the
  dialogue toward the user's objective — full awareness of what was streamed and
  executed carries forward automatically.
- Completed streams keep their trajectory: what was tried, what failed, what was
  verified. New turns reference that history instead of re-deriving it.
