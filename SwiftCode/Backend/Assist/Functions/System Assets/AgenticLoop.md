<!-- system-index-depends: CallTool.md, ErrorHandling.md -->
# AgenticLoop — The Agent Iteration Lifecycle & Subagent Policy

The mechanics of one Assist run: how a request becomes a plan, tool calls, results, and a final answer — who owns each stage, and the rules that keep the loop stable. Tool-call mechanics live in `CallTool.md`; planning the work lives in `ExecutionPlans.md`; failures live in `ErrorHandling.md`.

---

## 1. The Lifecycle

One request flows through these stages, iterating the middle until the objective is done:

```text
submit
 → assemble context (session transcript, memory, project context)
 → retrieve instructions (system prompt + AGENTS.md + workspace state)
 → select model / provider
 → authenticate
 → build the request (schemas for the active toolkit only)
 → invoke the model
 → stream the response
 → detect tool calls vs. final answer
 → authorize / validate each tool call
 → execute
 → normalize the result
 → deliver the result back to the model
 → iterate
 → detect the final answer
 → update session state
```

Streaming is for the user; structured tool-call payloads are for the runtime. Never leak raw tool envelopes into user-visible output.

---

## 2. Ownership: Antigravity Runs the Loop, SwiftCode Owns the Environment

In Antigravity sessions the division is strict:

- **Antigravity (agent framework & model runtime)** owns model execution and the LLM inference loop, agentic reasoning, planning and turn management, dynamic tool selection and argument generation, subagent/worker orchestration, context handling, and output streaming (text, thoughts, tool calls, results).
- **SwiftCode (native application environment)** owns the native Swift tool implementations, local tool permissions (`AssistPermissionsManager`) and user approval workflows, system prompts and repository rules, the native UI, session/transcript/workspace state, worker visual presentation, and end-to-end cancellation and developer takeover.

The agent never crosses this boundary: it does not reimplement SwiftCode's tools, and SwiftCode never second-guesses the model's reasoning — it validates and executes.

---

## 3. The Bridge

At session start SwiftCode serializes JSON schemas for all registered Swift tools from `AssistToolRegistry.shared.getToolSchemas()`, and Antigravity registers them as executable functions inside its agent loop. When Antigravity decides to execute a tool it emits a `tool.execute` JSON-RPC request over the IPC socket; SwiftCode validates the arguments, checks permissions, executes the Swift tool asynchronously, and returns structured results; Antigravity continues its iterative reasoning turn.

Runtime events (`agent.progress`, `tool.started`, `tool.completed`, `tool.failed`, `worker.started`, `worker.completed`) are translated at the IPC boundary into native models: streaming Markdown is parsed incrementally, tool execution appears as compact activity items, and worker events update `WorkerRuntimeState` / `WorkerEventBus`.

---

## 4. Multi-Iteration Rules

- Every iteration must make progress: new information, a workspace mutation, or a verified result. Iterations that change nothing are a stop signal, not a strategy.
- Ground before mutating: inspect project structure, target configurations, and existing source before modifying. Never assume an API exists without re-reading the relevant declarations.
- A tool succeeding does not mean the objective is accomplished. Verification requires re-reading modified files, compiling with the real toolchain, and confirming zero diagnostics — never claim success without execution evidence.
- Direct action over conversation: do not output apologies, filler, or promises of future work ("I will now write this file") — call the tool immediately.

---

## 5. Final-Answer Detection

The loop ends when the model produces a final answer instead of a tool call: the objective is achieved and verified, or a terminal state from `ErrorHandling.md` (failed / cancelled / timed out / limit-reached) has been reached. In native JSON-protocol sessions the agent signals completion with `finalResponse` describing achievements and files modified. Do not emit a final answer while required verification is still outstanding, and do not keep iterating once the answer is complete.

---

## 6. Execution Limits & Stagnation Protocol

The loop is bounded against runaway execution:
- Identical tool calls with identical arguments are never repeated in consecutive turns.
- Oscillation between mutually breaking changes forces an immediate strategy shift.
- ~10 iterations without disk-state change or new information is stagnation — break out, re-read the full context, re-verify baseline assumptions, and try a completely different approach.
- Transient retries are capped (see `ErrorHandling.md` §3); a model/key fallback continues the same task from the last valid point, never restarts it.

---

## 7. State Awareness & Result Reuse Across Iterations

Maintain continuous awareness of the active task across every iteration:
- files inspected and read;
- files modified, created, or deleted;
- tools executed and their outcomes;
- successful results versus failed attempts;
- workers created and their returned results;
- active model and provider state;
- test and build outcomes.

Tool results are authoritative ground truth — do not re-verify unchanged state. The runtime caches read results and invalidates them on any mutation; treat a cached success as current unless a write tool ran after it. Do not repeat completed work unless the workspace state changed or verification is genuinely required.

---

## 8. Worker & Subagent Delegation Policy (`use_workers`)

Workers are an optional capability. The existence of `use_workers` / `start_subagent` does **not** imply a worker should be created — default to 0 workers and direct execution.

**Do NOT spawn workers for:**
- greetings, simple questions, or explanations;
- single-file reads, inspections, or edits;
- simple text/regex searches;
- typos, import updates, or small symbol renames;
- single build or test runs;
- straightforward tool calls the primary agent can perform directly.

**Workers may be justified for:**
- auditing entire large codebases across independent domains;
- investigating multiple independent, non-overlapping subsystems simultaneously;
- multi-domain migrations requiring parallel isolated research;
- high-volume independent file processing where workstreams do not intersect.

Every worker task needs a clear objective, an explicit non-overlapping scope, an expected output, and bounded responsibility (`use_workers` task descriptions are capped at 500 characters; `targetFiles` must be disjoint across workers in a batch). Workers execute real mutations through the full tool suite — this is the highest-risk planning tool, so keep the count to the genuinely independent workstreams and no more. In Cloud sessions, `start_subagent` dispatches an isolated subagent with its own conversation context that reports results back on completion.
