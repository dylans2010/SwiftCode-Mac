# Gap-closure: LLM wiring for MCP tools

Date: 2026-11-06. Family 1 of the gap-closure wave (LLM wiring).
Destination: `swiftcode/Sources/SwiftCodeAssistant/LLMToolCompletion.swift`,
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+AgenticCode.swift`,
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ReviewDocs.swift`.
Patches (coordinator applies): `code_refactor` in
`swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+FileWriting.swift`,
`intel_autofix` in `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Planning.swift`.

## 1. Problem

Eleven registered MCP tools always failed honestly because SwiftCode's MCP
host had no LLM provider wired for them (Waves 2, 6, 8):

| Tool | Legacy file | Legacy behaviour |
|---|---|---|
| `code_refactor` | `SwiftCode/Backend/Assist/Tools/AssistRefactorTool.swift` | LLM (OpenAI + stored key) rewrites the file; writes only the modified code back |
| `code_review` | `SwiftCode/Backend/Assist/Tools/CodeReview.swift` | LLM review of task history + repo changes + build state; JSON verdict, status `task_ready` / `task_failed` |
| `generate_code` | `SwiftCode/Tools/Agentic/GenerateCode.swift` | Canned stub (`// Generated code based on: <prompt>`) — a fake |
| `refactor_code` | `SwiftCode/Tools/Agentic/RefactorCode.swift` | Input unchanged + `// Refactored code` comment — a fake |
| `review_code` | `SwiftCode/Tools/Agentic/ReviewCode.swift` | Canned `Review comments: LGTM!` — a fake |
| `fix_bugs` | `SwiftCode/Tools/Agentic/FixBugs.swift` | Input unchanged + `// Fixed code` comment — a fake |
| `generate_unit_tests` | `SwiftCode/Tools/Agentic/GenerateUnitTests.swift` | Canned empty `XCTestCase` stub — a fake |
| `generate_integration_tests` | `SwiftCode/Tools/Agentic/GenerateIntegrationTests.swift` | Canned empty `XCTestCase` stub — a fake |
| `generate_documentation` | `SwiftCode/Tools/Agentic/GenerateDocumentation.swift` | Canned `/// Documentation for the provided code` — a fake |
| `generate_comments` | `SwiftCode/Tools/Agentic/GenerateComments.swift` | Canned `// Comments for the provided code` — a fake |
| `intel_autofix` | `SwiftCode/Backend/Assist/Tools/AssistAutoFixErrorsTool.swift` | Runs `lint_project`, then an LLM (OpenAI + stored key) rewrites the file |

Meanwhile Wave 9 landed all five Legacy AI providers on the Assist host
(`OpenRouterProvider`, `OpenCodeProvider`, `HermesProvider`,
`FoundationModelsProvider`, `SCCloudProvider`), and Wave 15 landed the
model router (`AssistModelRouting.swift`). The tools stayed unwired.

## 2. Design: one shared service, host dispatch only

New type `LLMToolCompletionService` in
`swiftcode/Sources/SwiftCodeAssistant/LLMToolCompletion.swift`:

- `resolve() -> (kind: ProviderKind, model: String?)` — pure settings
  read, no network, no credentials. Selection follows the Wave 15
  router rules (`AssistModelRouting.swift`):
  1. Provider is SwiftCode Cloud → `.scCloud` with its stored model.
  2. `useSwiftCodeCloudModel` names a cloud model → `.scCloud` with it
     (the router's cloud short-circuit).
  3. A model is stored for the configured provider → routed by its id
     through `AssistantBackends.providerKind(forModelID:)`, so prefixed
     ids (`hermes:`, `opencode:`, `swiftcode-cloud:`) can never be
     misrouted to another provider.
  4. A free-text custom model id (`customModelID`) → routed by its id.
  5. Otherwise the configured provider with no model (provider default).
  - "Only Use Free Models" is enforced here
    (`AssistModelEligibilityPolicy.isEligible`): a barred model throws
    `.ineligibleModel` naming the model and the policy. With no model
    id known (provider default) the policy cannot be checked until the
    provider lists one — that check is not performed.
- `complete(systemPrompt:userText:) async throws -> LLMToolCompletion`
  — one `AssistantProvider.send` through the resolved provider:
  1. `availability()` first, so a missing key / server / endpoint /
     CLI / Apple Intelligence fails with the provider's own recovery
     hint instead of a bare transport error.
  2. `ChatRequest(model:instructions:messages:[user], generation:
     .assistantDefault)` — 4,096 output tokens, the assistant default.
  3. Text events are concatenated; `.truncated` is reported;
     `.activity` events are ignored (these are one-shot calls, not
     agent turns). An empty reply throws `.emptyResponse`.
  4. Every failure is an `LLMToolError` whose description names the
     LLM provider: `.providerUnavailable`, `.providerFailed`,
     `.ineligibleModel`, `.emptyResponse`. Nothing is ever generated
     from canned text.
- `providerOverrides: [ProviderKind: AssistantProvider]` — a
  dictionary (not a closure) so the service stays `Sendable`. The MCP
  accessor fills it from the host's
  `CodingAssistantServices.providerOverride`; tests fill it with stub
  providers. Empty in production.

MCP side (`SwiftCodeMCPHost` extension in `SwiftCodeTools+AgenticCode.swift`):

- `llmToolService()` — the test seam `llmToolTestService` first
  (precedent: `agenticGitTestSecretStore`), otherwise
  `CodingAssistantServices.shared` (Settings' provider + model, the
  secret store, `providerOverride`) via
  `LLMToolCompletionService(backends:services.backends(),
  providerOverrides:…)`. This is the host dispatch — no parallel
  client, no parallel registry, no new settings source.
- `llmToolComplete(systemPrompt:userText:toolName:failureNote:)`
  maps every failure to an `MCPToolError` keeping the words
  "unavailable" and "LLM", so the existing honest-failure tests keep
  passing while unconfigured.
- `llmToolStripFences(_:)` — Legacy's own ```` ```swift ```` / ````
  ```` stripping from `code_refactor` / `intel_autofix`.
- `llmToolCodeOnly(_:toolName:)` — a code-only reply; empty after
  stripping is an honest failure, never an empty file.

No `Package.swift` change is needed: `SwiftCodeAssistant` gains a file
with no new dependency, and `SwiftCodeMCP` already depends on
`SwiftCodeAssistant` and `SwiftCodeIDECore`.

## 3. Per-tool behaviour

### 3.1 Agentic generation tools (`SwiftCodeTools+AgenticCode.swift`)

All eight handlers are now `async` and call `llmToolComplete`. The
system prompts are short and code-only; the user text is the tool's
input verbatim (code / prompt / issue as Legacy's schemas carry it).
Code-returning tools return the reply with fences stripped and nothing
else prepended (the caller may write it to a file):

- `generate_code` — "You are a Swift code generator…" + prompt.
- `refactor_code` — "You are a Swift refactoring engine…" +
  `Instructions: …` + code.
- `review_code` — "You are a senior Swift code reviewer…" + code;
  returns the review prose as-is.
- `fix_bugs` — "You are a Swift debugging engine…" +
  `Issue: …` + code.
- `generate_unit_tests` — XCTest `XCTestCase` subclasses with real
  assertions (Legacy's empty stub replaced by a real request).
- `generate_integration_tests` — XCTest integration tests, end to end
  including collaborators.
- `generate_documentation` — DocC `///` comments with `- Parameter` /
  `- Returns` / `- Throws` tags.
- `generate_comments` — the supplied code with concise comments added;
  the code itself is not changed.

`explain_code` is NOT wired here: Legacy really calls OpenRouter for
it, but its Wave 8 static explanation stands — out of scope for this
slice. (It is now a one-handler change on top of this service.)

### 3.2 `code_review` (`SwiftCodeTools+ReviewDocs.swift`)

Legacy sends the task history, repository changes and build state to
an LLM and requires a JSON verdict. SwiftCode's MCP host has no agent
session (no objective, tool history or plan) and keeps no workspace
snapshots, so there is no task history or change list to send. The
port therefore sends the workspace's Swift sources instead:

- Full file text up to a 24,000-character budget (files in path order);
  remaining files are listed by path only. The prompt states that no
  task history, change list, or build state is available, and instructs
  the reviewer to set `task_failed` when a verdict would need build or
  change evidence it does not have.
- No Swift files in the workspace → honest failure before any LLM call.
- System prompt: a condensed form of Legacy's
  `CodeReviewSystemAsset.md` (141 lines: reviewer persona, review
  dimensions, JSON contract). The full asset is NOT ported here — it
  belongs to the System Assets family. The verdict contract is
  Legacy's verbatim: `status` (`task_ready` | `task_failed`),
  `summary`, `strengths`, `issues`, `recommendedFixes`, `user_see`,
  `confidence`, output as JSON only, no fences, no preamble.
- The reply is parsed by `reviewDocsExtractReviewJSON` (Legacy's
  `CodeReviewTool.extractJSON`: strip one fence pair, first `{` to
  last `}`, parse). A non-JSON reply, or a status other than
  `task_ready` / `task_failed`, is an honest failure — no review is
  recorded.
- Success returns text: `Review completed via <Provider> · <model>.
  Status: <status>. Summary: <summary>` plus strengths, issues,
  recommended fixes, `user_see`, and confidence.

Legacy's hardcoded model fallback queue (`AFM 3 Core Advanced`,
`openai/gpt-4o-mini`, `anthropic/claude-3.5-sonnet`, …) is
deliberately NOT ported: the configured provider answers, or the tool
fails honestly. A failed turn never silently substitutes a model the
user did not choose. Router failover across models is a later wave's
follow-up.

### 3.3 `code_refactor` — patch for `SwiftCodeTools+FileWriting.swift`

(Coordinator applies; file owned by another slice.) The handler
`refactorCode` becomes:

1. Resolve `path` with `resolveFileReadingPath` (session-aware, as the
   neighbouring file tools do) and read it with `text(of:)` so unsaved
   editor text is included.
2. Legacy's prompt verbatim in shape: "You are a refactoring engine.
   Apply the following refactoring action to the code. Return ONLY the
   modified code, no preamble." + `Action: …` + `File: …` + the content.
3. `llmToolComplete(…, toolName: "code_refactor", failureNote:
   "Nothing was changed.")`, strip fences (Legacy's stripping), empty
   → honest failure, nothing changed.
4. Write through `commit()` (approval gate, as all file-writing tools
   do). An unchanged reply still commits (a no-op write) and reports
   that the file was unchanged.

The file header bullet for `code_refactor` is updated the same way.

### 3.4 `intel_autofix` — patch for `SwiftCodeTools+Planning.swift`

(Coordinator applies; file owned by another slice.) Legacy runs
`lint_project` and then asks an LLM to rewrite the file. Both halves
now exist in the destination:

1. Resolve `path` with `resolveFileWritingClampedPath` (Legacy's
   `AssistToolingSupport.resolvePath` clamps — the resolver this
   file's tools already use).
2. Diagnostics come from the existing `terminalTaskLintProject(root:)`
   (`SwiftCodeTools+Terminal.swift`: Legacy's `collectSwiftFindings` — tab
   indentation, lines over 140 characters, trailing whitespace, in
   every Swift file). No lint engine is invented. If the output has no
   `issue(s)` → success text `No lint issues to fix in <path>`, with
   no LLM call.
3. Findings are grouped per file by basename (`Name.swift:line
   message` lines, first 20 as the lint output caps them); each file
   with findings (at most 10) is sent to the LLM with Legacy's prompt
   shape ("Fix the linting issues in this Swift file. Issues: …
   Return ONLY the fixed code." + `File: …` + content), fences are
   stripped, and the result goes through `commit()` per file.
4. A file whose reply is empty or identical is not counted as fixed.
   If every file fails, the tool throws naming the provider and "No
   file was changed."; otherwise it returns a text summary (fixed /
   unchanged / failed files).

Known limitation: findings carry basenames only, so two Swift files
with the same basename in different directories resolve to the first
match. A future lint slice that reports full paths removes it.

## 4. Provider capability notes

- These are plain text completions, which every provider serves; no
  tool has a capability a provider lacks. Foundation Models answers
  on-device (macOS 26+, Apple Intelligence on); on Linux or older
  macOS it reports honestly unavailable. SwiftCode Cloud needs a real
  endpoint URL from Dylan (Wave 9 prerequisite, unchanged). OpenRouter
  needs an API key. OpenCode needs its local server running. Hermes
  needs the Hermes CLI installed and signed in.
- The Meta (`metaAssist`) provider is reachable through the same
  dispatch when Settings names it; no special-casing was added.
- The service performs exactly one provider call per tool call. No
  retry, no fallback model, no router failover — see §3.2.

## 5. Tests

- `swiftcode/Tests/SwiftCodeAssistantTests/LLMWiringGapTests.swift` — the
  service directly, with stub providers (never live network, never
  real credentials): resolution for stored OpenRouter / `hermes:` /
  `opencode:` / `swiftcode-cloud:` ids, custom model id, provider
  default, cloud toggle; free-only eligibility; unconfigured
  OpenRouter (names the key) and unconfigured SwiftCode Cloud (names
  the endpoint); streamed-text collection + truncation; empty response;
  provider failure mapping; an end-to-end Ollama call against a
  loopback server.
- `swiftcode/Tests/SwiftCodeMCPTests/LLMWiringGapTests.swift` — the tools
  through `tools/call` on a Greeter workspace copy, with the host test
  seam set to a stub provider: all eight Agentic tools return the stub
  text; `code_review` returns a stub JSON verdict (success), rejects a
  non-JSON reply and an invalid status; the unconfigured service fails
  honestly with "unavailable" + "LLM" (+ "no LLM provider" /
  "task_ready" for `code_review`). `code_refactor` and `intel_autofix`
  tests are present but `.disabled` — they can only pass once the
  coordinator applies the §3.3/§3.4 patches; enable them then.

## 6. What is still pending / needs Dylan

- Mac `swift build` / `swift test` (no Swift toolchain in this
  environment; static checks only).
- A configured provider before any of these tools can answer for
  real: an OpenRouter API key, a running OpenCode server, a Hermes
  install, Apple Intelligence on macOS 26+, or the SwiftCode Cloud
  endpoint URL (Wave 9 prerequisites, unchanged).
- Router failover across models on a failed turn (Wave 15 follow-up,
  not this slice).
- The full `CodeReviewSystemAsset.md` port (System Assets family).
- Existing tests that assert the old honest failures
  (`SwiftCodeAgenticCodeTests.honestlyFailingToolsNameTheLLMPrerequisite`,
  `SwiftCodeReviewDocsTests.codeReviewFailsHonestlyWithoutLLM`) still pass
  while unconfigured, but will return real output on a machine with a
  working provider — the coordinator/parent should update or scope
  them when the provider is configured.

## Evidence

| Claim | Level | Source |
|---|---|---|
| `code_refactor` Legacy behaviour (OpenAI LLM, prompt shape, fence stripping, write-back) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistRefactorTool.swift`, read directly |
| `code_review` Legacy behaviour (task history + changes + build state, JSON verdict `task_ready`/`task_failed`, hardcoded fallback queue, system prompt from `CodeReviewSystemAsset.md`) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/CodeReview.swift` and `SwiftCode/Backend/Assist/Functions/System Assets/CodeReviewSystemAsset.md` (141 lines), read directly |
| Agentic tools return canned strings in Legacy | 1 | Legacy `SwiftCode/Tools/Agentic/GenerateCode.swift`, `RefactorCode.swift`, `ReviewCode.swift`, `FixBugs.swift`, `GenerateUnitTests.swift`, `GenerateIntegrationTests.swift`, `GenerateDocumentation.swift`, `GenerateComments.swift`, read directly |
| `intel_autofix` Legacy behaviour (runs `lint_project`, OpenAI LLM rewrite, write-back; "No lint issues" when no `issue(s)`) | 1 | Legacy `SwiftCode/Backend/Assist/Tools/AssistAutoFixErrorsTool.swift`, read directly |
| `lint_project` exists in the destination as `terminalTaskLintProject` (tab / >140 chars / trailing whitespace) | 1 | Destination `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Terminal.swift`, read directly |
| Five Wave 9 providers, their `send`/`availability` contracts, and the host dispatch `AssistantBackends.provider(_:)` / `providerKind(forModelID:)` | 1 | Destination `swiftcode/Sources/SwiftCodeAssistant/OpenRouterProvider.swift`, `OpenCodeProvider.swift`, `HermesProvider.swift`, `FoundationModelsProvider.swift`, `SCCloudProvider.swift`, `AssistantSettings.swift`, read directly |
| Router selection rules (prefixed ids, cloud short-circuit, free-only policy, no hardcoded fallback in SwiftCode) | 1 | Destination `swiftcode/Sources/SwiftCodeAssistant/AssistModelRouting.swift`, read directly |
| MCP host has no settings/provider field; `CodingAssistantServices.shared` is the host's assistant entry point with a `providerOverride` test seam | 1 | Destination `swiftcode/Sources/SwiftCodeMCP/SwiftCodeMCPHost.swift`, `swiftcode/Sources/SwiftCodeIDECore/Assistant/CodingAssistantServices.swift`, read directly |
| No Swift toolchain exists in this environment; `swift build` / `swift test` were not run — static checks only | — | Environment fact, recorded by this slice |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
