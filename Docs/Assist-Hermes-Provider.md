# Hermes Agent as a SwiftCode Assist Provider

Hermes Agent (Nous Research) is a selectable Assist provider in
SwiftCode, alongside OpenCode and OpenRouter. SwiftCode is the host:
it owns the session, the system prompt, the transcript, and the tool
panel. Hermes owns only the agent loop inside one run.

## Runtime interface (verified, not assumed)

Hermes Agent is a Python CLI (`hermes`), not a Swift library and not
a JS SDK, so there is no SDK bridge to host. SwiftCode launches the
real executable as a child process through Hermes' documented
programmatic interface (CLI reference in the Hermes Agent repo,
`website/docs/reference/cli-commands.md`):

```
hermes --in <workspace> chat --oneshot --query-file <file>
       --format stream-json --source tool
       [--provider <provider>] [--model <model>]
       [--toolsets <csv>] [--max-turns <n>]
```

Every flag above was verified against the argument parser in the
Hermes source itself (`hermes_cli/_parser.py`: `--in` is accepted
both before and after the subcommand; the `chat` parser defines
`--oneshot`, `--query-file`, `--format` with `stream-json`,
`--source` ("Use 'tool' for third-party integrations"),
`-m/--model`, `--provider`, `-t/--toolsets`, and `--max-turns`).

Stream-json stdout lines:

| Event | Fields SwiftCode uses |
|---|---|
| `system` | init: `model`, `session_id` (observed only) |
| `text` | streamed assistant delta |
| `tool_use` | `name`, `input` (object or string) |
| `tool_result` | `name`, `output` (capped at 5000 chars by Hermes), `duration_ms`, `is_error` |
| `result` | terminal record: `session_id`, `exit_code`, `text` (the whole reply), `tokens`, `error` |

Diagnostics stay on stderr and are kept as a capped, redacted tail
for error reporting. Exit codes for `chat` one-shot runs: 0
completed, 1 failed / partial / iteration budget / never ran, 2
usage or gateway-client error (including an unreadable or empty
query file), 130 interrupted. The terminal `result` record's
`exit_code` is authoritative and is what SwiftCode judges the run
by; no other exit code is assumed. (An earlier draft of this doc
listed 75 as a transient-provider code — that code does not appear
in the Hermes CLI source and has been removed; the separate `-z`
table of 0/1/2/130 does not apply to `chat` runs.)

### Interfaces deliberately not used

- `hermes -z`: prints final text only (no tool events) and sets
  `HERMES_YOLO_MODE=1` internally (`hermes_cli/oneshot.py`).
  SwiftCode must never silently auto-approve, so `-z` is never used.
- `hermes acp`: a real editor protocol, but a full ACP JSON-RPC
  host (permission callbacks, session lifecycle, gateway viewer
  semantics) is a larger, riskier surface for no capability gain
  over stream-json, and ACP likewise cannot inject SwiftCode's
  system prompt.
- `@hermes/plugin-sdk`: the Hermes Desktop plugin SDK. It extends
  Hermes Desktop's UI; it is not an agent-execution interface and is
  never imported, built, or modified here.

## Where Hermes integrates

| Concern | Location |
|---|---|
| Model identity (`hermes:<spec>`) | `SwiftCode/Backend/Assist/HermesProvider.swift` (`HermesModelID`) |
| Persisted config (executable, toolsets, max turns) | `HermesProvider.swift` (`HermesConfiguration`, keys `hermes.*`) |
| Child-process launch, stream-json parsing, cancellation | `HermesProvider.swift` (`HermesProvider`, `HermesStreamParser`) |
| Session seam (prompt, event publication, final text) | `SwiftCode/Backend/Assist/HermesSessionRunner.swift` |
| Provider selection + routing | `AssistModelProvider.hermes`, `AssistProviderConfiguration.provider(for:)` |
| Agent-mode branch | `AssistAgentSession.swift` Hermes branch (before the SDK branch and legacy validation) |
| Tool panel | `SwiftCode/Views/Assist/HermesToolsUIView.swift` (provider `hermes`, source `.hermes`) |
| Settings | `AssistSettingsView.swift` Hermes section (after SDK Providers) |
| Tests | `SwiftCode/Backend/Assist/HermesProviderTests.swift`, wired into `AssistRuntimeTestSuite` |
| Project membership | `SwiftCode.xcodeproj/project.pbxproj` (4 new files, app target Sources) |

Selection is a stored model id, exactly like OpenCode: the Hermes
Settings section's model field writes `hermes:<spec>` to
`selectedAssistModelID` and sets `assist.selectedProvider` to
`Hermes`. The model id remains the routing source of truth for a
running session. `AssistSDKSessionRunner.applicableKind` explicitly
returns nil for Hermes ids, so the OpenRouter persisted-provider
fallback (which would otherwise claim any `/`-containing id) can
never steal a Hermes run. `AssistLLMService` fails closed for
`.hermes`, as it does for `.openCode`, so a Hermes model can never
be silently sent to OpenRouter with an OpenRouter credential.

## Configuration ownership

- **Model selection.** The user-selected spec is honoured verbatim:
  `hermes:openrouter:anthropic/claude-sonnet-4-6` passes
  `--provider openrouter --model anthropic/claude-sonnet-4-6`;
  `hermes:gpt-5.5` passes `--model gpt-5.5` only, with no provider
  invented. A model is never displayed as selected while Hermes
  runs a different one: an invalid id fails before launch.
- **System prompt.** SwiftCode's assembled prompt (fresh baseline
  plus per-task retrieved System Asset instructions, built by the
  shared `AssistSDKSessionRunner.buildSystemPrompt` helper — one
  prompt construction, not one per provider) is delivered as the
  first part of the query file, followed by the task. Hermes has no
  `--system-prompt` flag, so this is user-turn delivery, not a
  Hermes system prompt, and Hermes' own SOUL.md / workspace rules
  still apply on top. SwiftCode never writes to `~/.hermes/SOUL.md`,
  `config.yaml`, or `.env` to force its prompt in. The Settings
  text states this limit.
- **System Assets.** Assets reach Hermes only through that same
  assembled prompt (retrieved instructions are part of it). There
  is no separate Hermes asset directory and no hardcoded asset
  content in the provider.
- **Native tools.** Not supported by this runtime interface, stated
  plainly rather than faked: stream-json is observational for tools
  (Hermes reports the tools it executes; there is no documented
  callback for SwiftCode to execute its registry tools inside a
  Hermes run). The provider sends no SwiftCode tool schemas, and no
  SwiftCode tool is ever marked available in a Hermes run.
  SwiftCode native tools remain available on every other provider.
- **Hermes-native tools.** Hermes tools are the only tool system a
  Hermes run has — there is no SwiftCode/combined mode to offer,
  because combined execution would require the external-tool
  callback Hermes does not expose. The optional Toolsets setting
  narrows which Hermes toolsets a run may use (for example to
  remove terminal / code execution); blank means Hermes defaults.
- **Context.** The run's working directory is the Assist workspace
  root (`--in` plus the process working directory). No repository
  is dumped into the prompt; project context arrives through the
  system prompt and the task, as on other providers.
- **History / sessions.** Each task is a fresh one-shot; SwiftCode
  never passes `--resume`, so Hermes session state is never
  silently carried across SwiftCode tasks. The SwiftCode transcript
  is the conversation record.

## Approvals and security

A single-query (`-q`) Hermes run has no user at a terminal to answer
an approval prompt, so Hermes' own `approvals.single_query_mode`
applies — its default is `deny` (a dangerous command is blocked and
the agent must find another way). SwiftCode never passes `--yolo`
and never sets `HERMES_YOLO_MODE` / `HERMES_ACCEPT_HOOKS`. Hermes is
launched with a controlled environment (PATH/HOME/TMPDIR only), so a
stray `HERMES_*` variable in the parent environment can never change
that. Hermes tools therefore run under Hermes' own approval policy,
never under SwiftCode's tool permissions — the Settings text says
so, and users should only run Hermes in workspaces they trust.

Secrets: Hermes credentials live in Hermes' own `~/.hermes/.env`
and `config.yaml`. SwiftCode stores no Hermes key, never passes
`--api-key` / `--base-url`, and redacts tool arguments/results and
stderr tails through `SDKToolEvent.redact` before they reach the UI
or an error string. The prompt travels in a temp query file outside
the workspace (deleted on every exit path), never in argv, so it
cannot leak into a process listing; `--query-file` also passes the
body verbatim (no shell interpretation of quotes, `$()`, or
backticks). The child process is launched directly (no shell), with
no shell interpolation anywhere.

Cancellation terminates only the child process SwiftCode started
(SIGTERM, a 2-second grace wait, then SIGKILL), marks the run's
non-terminal tool rows cancelled in the store, and does not
re-report the cancellation as a failure. Each run owns one process
and one temp query file; repeated runs leak neither. Cancellation
caveat: modern `hermes chat` is a gateway client
(`hermes_cli/gateway_chat.py`), and its own interrupt path says
"Detached; accepted work continues at the gateway." No CLI command
was found to cancel a gateway turn from outside, so SwiftCode's
cancel guarantees the local CLI process dies and SwiftCode stops
observing/reporting the run — it cannot guarantee a gateway turn
that was already accepted stops executing. Treat a cancelled Hermes
run as "SwiftCode stopped watching", not "Hermes stopped working",
until a gateway-side cancel (e.g. via ACP `session/cancel`) is
implemented. This is the one place the first report overstated
cancellation, and it is corrected here.

## Known limitations (honest list)

1. SwiftCode's prompt is delivered as user-turn text, not as a
   Hermes system prompt, and Hermes' own SOUL.md / workspace rules
   still apply. If those contradict SwiftCode's instructions, Hermes
   — not SwiftCode — resolves the conflict.
2. SwiftCode native tools cannot execute inside Hermes runs.
3. Hermes tool events carry no call id on the wire; SwiftCode
   synthesises per-run ids (`hermes-<run>-<name>-<n>`) to pair
   `tool_use` with `tool_result` and to keep runs in one session
   from merging. Tool duration is reported only when Hermes sends
   it; output is capped at 5000 chars by Hermes itself.
4. Multi-turn Hermes session continuity is not preserved: every
   SwiftCode task is a fresh one-shot.
5. Hermes model discovery is not implemented: SwiftCode cannot list
   Hermes' configured models (they live in Hermes' own config), so
   the user types the model spec in Settings. A typo fails before
   launch with the invalid-id error, never with a substituted model.
6. Hermes must be installed and authenticated outside SwiftCode
   (`hermes setup`, `hermes model` in a terminal). SwiftCode never
   downloads or executes a remote install script.
7. Cancellation is local-only (see above): killing the CLI detaches
   from the gateway; no gateway-side cancel is implemented yet. A
   future ACP-based provider could close this gap with
   `session/cancel`, and could also expose SwiftCode tools to Hermes
   via ACP `session/new` `mcpServers` — both are documented Hermes
   capabilities, neither is claimed by this CLI implementation.

## Verification status

- **Unit/in-app tests (offline, deterministic):** model-id
  parsing, provider/model split, provider selection + SDK guard,
  configuration round-trip, exact argument construction (including
  the bare-model case and the absence of `--yolo` / `--api-key` /
  prompt text in argv), stream-json parsing for every documented
  event type, malformed-line handling, prompt delivery, and
  executable resolution against a real temp directory. Wired into
  `AssistRuntimeTestSuite` as `HermesProviderTests`.
- **Not verified here (no macOS/Xcode in this environment, no
  Hermes install, no Hermes credentials):** Xcode build, the
  in-app test suite run, Settings installation check against a
  real `hermes` binary, and a real end-to-end Hermes task (for
  example: select `hermes:openrouter:<model>` in Settings, ask it
  to inspect a test workspace and summarise a file, and confirm a
  `read_file` tool event reaches the Hermes tool panel). These are
  listed as pending on Dylan's Mac in the final report, not claimed
  as passed.
- **Regression scope:** the only shared-surface changes are
  additive: a new `AssistModelProvider` case (with fail-closed
  LLMService handling), a new `SDKToolSource` case (with the
  OR/OC view label switches updated), a Hermes guard in
  `applicableKind`, a shared prompt helper extracted from
  `AssistSDKSessionRunner.run` with behaviour preserved, and the
  Hermes branch + cancel handling in `AssistAgentSession`. No
  OpenCode, OpenRouter, Foundation Models, or other provider logic
  was refactored.
