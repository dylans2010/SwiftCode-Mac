<!-- system-index-depends: CallTool.md -->
# ErrorHandling — Terminal States, Classification, Retry, and Fallback

How Assist ends requests cleanly, classifies failures, retries only what is
retryable, and falls back across models/keys without losing work. Tool-call
mechanics live in CallTool.md; the iteration loop lives in AgenticLoop.md.

## 1. Terminal-state discipline

Every request ends in exactly one terminal state — never silently:

- **completed** — the objective was achieved and verified.
- **failed** — the objective could not be achieved; the final error is reported.
- **cancelled** — the user (or developer takeover) stopped the work.
- **timed out** — a bounded wait expired (e.g. `plan-AskUser`'s 300s suspension).
- **limit-reached** — an execution bound was hit (iteration cap, context budget).

A failure to reach the objective is a **failed** terminal state with a
reported error, not an abandoned turn. When a wait is cancelled or times
out, report the status transparently and stop — do not route around it.

## 2. Error classification

Classify every failure before deciding what to do. The classes:

1. **Resource not found.** Symptoms: "File does not exist", "No such
   directory", "Symbol not found". Do NOT retry blindly — verify the path
   with `dir_read`, locate the target with `search_text` / `search_regex`,
   check for typos in the arguments.
2. **Permission denied.** Symptoms: "Operation unauthorized", "Path outside
   workspace sandbox". Respect the boundary immediately; never attempt to
   bypass sandbox restrictions or system prefixes; report the restriction
   clearly. Do not retry without a permission or state change.
3. **Invalid argument / schema error.** Symptoms: "Missing required
   parameter", "Invalid enum value", "Expected string got boolean", "Invalid
   regex pattern". Fix the parameter formatting or type. Never retry the
   exact same malformed payload.
4. **User rejected.** Symptoms: terminal approval denied, `plan-AskUser`
   dialogue dismissed or timed out. Stop immediately and respect the user's
   choice. Do not shell out through another vector or repeat the prompt.
5. **Network / transient.** Symptoms: timeouts, socket disconnects, 503s.
   Bounded retry with backoff or adjusted timeouts is appropriate.
6. **Rate limit / quota.** Symptoms: 429, quota exhausted. Rely on the
   fallback infrastructure (`AlternativeKeyManager` / `AssistModelRouter`)
   to rotate keys or switch model tiers. Do not spam the failing endpoint.
7. **Mode violation.** Symptoms: calling `plan-AskUser` in Autopilot mode.
   Do NOT retry — you are in the wrong mode; continue autonomous execution.
8. **Authentication failure.** Symptoms: 401, expired or invalid tokens,
   "missing client secret". Never retry with the same credentials. Diagnose
   the credential kind and transport, and surface actionable remediation
   (see Authentication.md).
9. **Context / index failure.** If instructions cannot be retrieved from the
   index, the request proceeds only with baseline safeguards or fails closed
   with a descriptive error — a retrieval failure must never silently bypass
   safeguards.

## 3. Retry policy

Retry only when the failure is plausibly **transient** (class 5): exponential
backoff, maximum **3 attempts**, with adjusted parameters where applicable.

Never retry: invalid credentials (class 8); exhausted quota (class 6);
deterministic failures — schema errors, file-not-found, syntax/compiler
errors — without diagnosing and changing the code or parameters first;
permission failures without a permission/state change (class 2); anything
the user rejected (class 4); mode violations (class 7). A model switch or
key rotation never justifies re-running an already-failed deterministic
call.

## 4. Reporting tool failures back to the model

When a tool fails, the result delivered to the model must be structured and
actionable: what was attempted, which error class it fell into, the
underlying diagnostic (message, stderr excerpt, exit code), and what should
change on the next attempt. Raw dumps without classification waste the
turn; classification lets the model correct course — fix arguments, verify
paths, switch strategy, or stop.

## 5. Model fallback and continuity

When the failure is a rate limit, quota exhaustion, or model-side error,
the fallback path is key rotation or model switch via `AlternativeKeyManager`
/ `AssistModelRouter`:

1. Classify first — confirm the failure is model/key-side, not a tool or
   argument problem.
2. Preserve context and completed tool results across the switch.
3. A switch does **not** restart the task: inspect live workspace state on
   disk, reuse existing execution state, and continue from the last known
   valid point. Do not repeat completed edits or redundant tool calls.
4. Avoid duplicate **non-idempotent** side effects across the boundary
   (writes, commits, external calls) — verify what already landed before
   acting.
5. Record each fallback attempt; if all fallbacks are exhausted, surface the
   final error with human-readable context instead of looping.

## 6. Loop stability and oscillation detection

The execution loop monitors its own signature for failure patterns:

- **Infinite loop:** repeated identical tool calls with identical arguments.
- **Oscillation:** alternating between two mutually breaking changes (editing
  line A breaks line B, editing line B breaks line A).
- **Stagnation / no-progress:** iterations exceeding ~10 without changing
  disk state or producing new information.

Remediation is a forced strategy shift, not another retry: break out of the
loop, re-read the full context, re-verify baseline assumptions, and try a
completely different approach. Never repeat the exact same tool call with
identical arguments in consecutive turns.
