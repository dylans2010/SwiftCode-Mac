# Gap closure: Wave 17 follow-ups + remaining view windows + Artboards UI

Slice spec for the gap-closure wave (family 7+8+9). Destination:
SwiftCode-Mac (Ycode base, SwiftPM, main @ `f9f66c05`). Legacy is
read-only at `d51a8f0d`; all Legacy evidence below is Dylan's own code,
direct porting authorised under MIT. Clean-room protocol applies:
implementation reads only `specs/`, public docs, and open-source /
Dylan's-own code.

Status: implemented in this slice unless marked otherwise. No Swift
toolchain exists in this environment — `swift build` / `swift test`
were not run here; Mac build/test is pending on Dylan's Mac throughout.

## 0. What Wave 17 left open (the follow-up list)

Wave 17 (§27 of `specs/ide/sdk-platform.md`) deferred exactly four
things, and left five view windows honestly unavailable:

1. The `/` popup menu + the `useMetaSlashCommands` toggle decision.
2. Settings UI for `metaTurnTimeoutSeconds` and the other-model fields.
3. Router failover in `CodingAssistantModel.send`.
4. Live extension writes (review-policy server + presenter).
5. The five windows: `docs.search` (Wave 19 owns it — NOT this slice),
   `sandbox.view`, `deployConsole.view`, `ci.VisualWF`,
   `virtualization.view`.
6. Artboards UI (Wave 5 left artboards in-memory only; `fix_artboards`
   passes 1–2 not ported).

## 1. Slash-command popup + `useMetaSlashCommands` toggle

### 1.1 Legacy evidence (verified live)

- `AppSettings.useMetaSlashCommands` (`SwiftCode/Models/AppSettings.swift:211`,
  UserDefaults `assist.useMetaSlashCommands`): **default `true`**
  (`?? true` at load, line 622–624).
- `AssistMainView` (`:1270`): typing `/` opened the composer popup in
  `.metaCommand` mode only when `settings.isMetaAssist &&
  settings.useMetaSlashCommands`; otherwise the same `/` fell through
  to skill mode.
- `AssistComposerPopup` (`SwiftCode/Views/Assist/AssistComposerPopup.swift`):
  meta-command rows from `metaCommandManager.searchCommands(query:)`,
  category filter (`All` + sorted categories), ↑↓ wraparound selection,
  Return commits, footer "N commands · Navigate with ↑↓ and Return ↵".
  Committing ran `selectMetaCommand`: `executeCommand` ran, and when
  the result started with `/` it went back into the input; otherwise
  the result was only logged (`logger.info`) — the effect itself had
  already been applied by `executeCommand` in Legacy.
- Settings toggle (`AssistSettingsView.swift:777`): "Use Meta's Slash
  Commands" / "Type \"/\" on Assist to list and run all commands from
  Muse Code."

### 1.2 Decision: the toggle exists, default on

The toggle is implemented with Legacy's default (`true`). It gates
both the popup and the typed-command intercept: when off, `/…` text
is sent to the model as-is (there is no skill popup in Ycode for it
to fall through to, so off means "no slash handling at all", never a
silent reinterpretation).

Shared-file patch (coordinator applies; `AssistantSettings.swift`
is outside this slice's owned set): add the field + lenient decode.

```swift
// AssistantSettings.swift, beside metaReasoningEffort:
/// "Use Meta's Slash Commands" (gap closure: Legacy
/// `AppSettings.useMetaSlashCommands`, UserDefaults
/// `assist.useMetaSlashCommands`, default true). When off, the `/`
/// popup never opens and typed `/…` text is sent to the model
/// as-is instead of being intercepted.
public var useMetaSlashCommands = true
// …and in init(from:):
useMetaSlashCommands = (try? c.decode(Bool.self, forKey: .useMetaSlashCommands)) ?? d.useMetaSlashCommands
```

### 1.3 Palette state (pure, `YcodeAssistant`)

`SlashCommandPaletteState` (`MetaSlashCommandManager.swift`): owns
the query, the filtered list from the manager's existing
`searchCommands` (verified live: filters name/title/description/
category, strips a leading `/`, empty query returns everything),
and the selected index with wraparound ↑↓ exactly as Legacy's
`selectNextItem` / `selectPreviousItem`. `selected` is nil when the
list is empty. `update(query:)` re-filters and clamps the selection
to 0. Terminal skills join the list only after the capture runs;
the popup triggers the same once-only capture the intercept uses
(`CodingAssistantModel.ensureSlashCommandsCaptured()`, public,
wrapping the existing private `refreshMetaSlashCommands()`).

### 1.4 Popup UI (`YcodeUI/Assistant/SlashCommandPopup.swift`)

`SlashCommandPopupController`: an `NSPopover` anchored to the
composer text view, containing an `NSTableView` (command name,
title, description, category), a footer count line, and — when the
selected command `requiresArguments` — an argument field with the
argument's name/placeholder (Legacy's `onRequestCommandArguments`
prompt, inlined). Keyboard: ↑↓ move, Return commits, Escape
dismisses (the popover's `onCancel` path, same as the composer's
existing `ComposerTextView.onCancel`).

Commit behaviour (mirrors Legacy's `selectMetaCommand` through the
already-tested intercept instead of duplicating effect application):
the controller returns the full command text (`/name` + ` argument`
when one was entered). The composer inserts it and:

- effect commands (`/effort`, `/model`, `/clear`, `/login` — i.e.
  anything whose `executeCommand` returns a non-`.insertText`
  effect) are **sent immediately**, so the model's existing
  `handleMetaSlashCommand` intercept applies the effect and posts
  the result;
- anything else is **left in the input for editing**, exactly as
  Legacy put a `/…` result back into the composer.

Wiring patch (coordinator applies; `ConversationView.swift` is
outside this slice's owned set): the composer observes its text —
when the last whitespace-delimited token starts with `/` and the
provider is Meta and the toggle is on, the popup opens with that
token's query; text changes update the query; ↑↓/Return/Escape are
offered to the popup first when it is visible; committing calls the
controller's `onCommit`. See the exact patch in the slice report.

### 1.5 Intercept gating

`CodingAssistantModel.handleMetaSlashCommand` now returns
`.notACommand` unless `settings.useMetaSlashCommands` is on (in
addition to the existing Meta-provider + known-command checks).
The gate lives in the model (owned file), so the toggle is honoured
even for text pasted or sent programmatically, not only for popup
commits.

## 2. Settings UI for the Meta fields

`CodingAssistantSettingsPane` (owned) gains, under the existing
"Assist with Meta" heading:

- Toggle "Use Meta's Slash Commands" (+ Legacy's subtitle), bound
  to `settings.useMetaSlashCommands`.
- Number field "Meta turn timeout (seconds):" bound to
  `settings.metaTurnTimeoutSeconds` (0 disables the timeout; empty
  restores the 300s default). Note: "0 disables the timeout. The
  Muse host is stopped outright when a turn exceeds it; a timed-out
  turn fails over only when 'Automatically switch models on failure'
  is on (see Model Routing)."
- New heading "Meta Other Models": toggles
  `metaUseOtherModels` ("Use Other Models with Meta SDK") and
  `metaUseCloudModelWithMeta` ("Use SwiftCode Cloud Model with Meta
  SDK"), fields `metaSelectedOtherModelID` ("Selected other model:")
  and `metaSelectedOtherModelProvider` ("Selected other model
  provider:"). Note: "When either toggle is on, a Meta turn runs
  through the local other-models proxy instead of Meta's own models.
  A proxy start failure fails the turn honestly — it is never
  silently run on Meta's own models."
- The stale "Assist with Meta" note ("running turns needs the Muse
  Code bridge, which is not ported yet") is corrected: the bridge,
  proxy auto-start, and execute-turn timeout all landed in
  Waves 16–17.

Field defaults (verified live in `AssistantSettings.swift`):
`metaTurnTimeoutSeconds` 300, `metaUseOtherModels` false,
`metaUseCloudModelWithMeta` false, `metaSelectedOtherModelID` "",
`metaSelectedOtherModelProvider` "".

## 3. Router failover in `CodingAssistantModel.send`

### 3.1 The gap (verified live)

`send` built one provider and one request; the `catch` after the
stream called `finish(id, error:)` and stopped. A timed-out or
failed turn never retried, even with `automaticallySwitchModels`
(default true, Legacy `assistAutomaticallySwitchModels`). The
router itself was ready: `AssistModelRouter.handleTurnFailure`
classifies the error (`.timeout` matches "timed out"/"timeout" —
the Meta timeout error `MuseCodeCLIError.turnTimeout` deliberately
says "timed out"), quarantines the failed model, returns nil when
auto-switch is off or no candidate remains, and otherwise returns
the next model + a continuation prompt carrying the partial output
forward. `eligibleCandidates` + `selectNextModel` + the
`useProviderModelsOnly` rule already existed (Wave 15).

### 3.2 Wiring (`CodingAssistantModel`, owned)

- The model owns one router: `public let modelRouter =
  AssistModelRouter()` (an actor; quarantine + `failoverHistory`
  persist across turns, as Legacy's singleton did).
- The turn task's send is a retry loop, max **2 failovers**
  (3 attempts). On a send error that is not a cancellation:
  - auto-switch off → finish with the error, exactly as before;
  - auto-switch on → build the eligible candidates from the
    surveyed `availability` (same construction the proxy block
    already uses), call `modelRouter.handleTurnFailure` with the
    failed model, the error, the partial text streamed so far,
    and `automaticallySwitchModels: settings.automaticallySwitchModels`;
  - nil → finish with the original error;
  - a next model → append an activity line ("Switched to X after Y
    failed (class)"), update the conversation's recorded model,
    rebuild the provider for the next model's kind
    (`services.provider(next.provider, prefs:)`; Meta keeps its
    injected `knownToolIDs`; a non-Meta failover stops a running
    other-models proxy), re-attach agent mode when the new
    provider is attachable (the old attachment is cleaned up
    first), and resend with the continuation prompt + the original
    request. The partial text stays in the transcript; the
    continuation prompt carries it forward, so work is not
    repeated.
- CLI-agent turns (`model == nil`) do not fail over: there is no
  failed model to exclude, and the old behaviour (report the
  error) is kept. Recorded, not silently widened.
- Other-model mode pins the model: while the proxy is on, failover
  is skipped and the original error stands (the proxy's catalog
  serves exactly one model; substituting another behind it would
  misroute the turn, and the Muse host would only report the new
  model as unknown). The turn fails honestly instead.
- Never silently substitutes when auto-switch is off — the
  Wave 15 rule, now enforced at the only place a turn is sent.

## 4. Live extension writes

### 4.1 The gap (verified live)

Wave 17 Slice B: extension reads run live against the window's
published server (`YcodeSDKToolServerRegistry.current`), but the
published server's policy is read-only, so every extension write
is refused with `readOnlyMessage`. The grant check (`MCPServer.run`
+ `MCPToolCaller`) and the runner (`YcodeSDKToolRunner`) were
already in place; what was missing was a review-policy server with
a presenter for extension changes — there is no conversation to
propose into, unlike agent mode.

### 4.2 Review-policy server (`WorkspaceWindowController+AgentMode`, owned)

`mcpHost` now sets the published server's policy to `.review`
with a closure that asks the extension-change presenter:

```swift
h.server.writePolicy = .review { [weak presenter] change in
    await presenter?.review(change) ?? false
}
```

The presenter lives in `AgentModeHolder`
(`extensionChangePresenter`), so one presenter serves the window.
No bypass: a granted write still asks exactly as a host write
would, and an ungranted tool never reaches the approval UI (the
grant check in `MCPServer.run` runs first — unchanged).

The base server is not served anywhere else in the IDE (agent
mode builds its own per-request server copy with its own review
policy; the CLI builds its own server), so the policy change only
affects extension tool calls. Verified by grep over
`mcpHost.server` uses.

### 4.3 Presenter (`YcodeUI/Assistant/ExtensionChangeReviewPresenter.swift`)

`ExtensionChangeReviewPresenter` (`@MainActor`): `review(_ change:
MCPChange) async -> Bool`.

- The sheet is an `NSAlert` on the key/main window: "Extension
  “<extensionID>” wants to change a file" (or "…wants to make a
  change" for non-file changes), informative text = the change's
  summary + relative path + a short original→proposed excerpt.
  Buttons: Accept / Reject. Closing the sheet rejects.
- No window to ask in (no visible window) → **refuse** (`false`).
  Never auto-allow, never queue silently.
- Test seam: `reviewer: ((MCPChange) async -> Bool)?` — when set,
  it answers instead of showing UI (the same pattern as
  `AgentModeHolder.permissionResponder`).
- The change the presenter sees already carries the caller's
  identity (`MCPServer.run` stamps it via `settingCaller`), so the
  sheet always names the extension.

### 4.4 What this unblocks, honestly

`YcodeSDKToolRunner` → published server → `.review` → presenter
sheet → user decision → write or `rejectedMessage`. Reads are
unchanged. The full composed path (backend → runner → live server
with seeded grants) is still covered in pieces, not end-to-end in
a test (no in-process seam exists for seeding live grants into
`SDKAssistService.shared` — Wave 17's note stands); Mac
verification of the composed path is pending.

No change to `MCPServer.swift` was needed: the write policy,
caller identity, and grant check already existed. The file was
reviewed, not modified.

## 5. Deploy console (`deployConsole.view`)

### 5.1 Legacy evidence (verified live)

- `DeploymentsView.swift` (213 lines): platform picker (Netlify /
  Vercel / GitHub Pages), custom-domain toggle, `startDeployment()`,
  Deploy button disabled without a token, result URL + "Open In
  Browser", deployment logs.
- Tokens from `APIKeyManager` (`.netlify`, `.vercel`, `.gitHub`);
  `DeploymentKeychainManager` stores `netlify_api_token` /
  `vercel_api_token` in the keychain.
- **Netlify/Vercel deploy is not a provider API upload in Legacy**:
  both managers only push the project to GitHub
  (`GitHubService.pushProject`, commit "Netlify Deployment: …" /
  "Vercel Deployment Sync: …") and return a dashboard URL
  (`https://app.netlify.com` / `https://vercel.com/dashboard`, or
  `https://<custom-domain>`). The provider's GitHub integration
  does the build. The token Legacy passed is the GitHub token in
  practice (the provider token is never sent to any provider API).
- **GitHub Pages is a real API flow in Legacy**
  (`GitHubPagesManager`): push → `GET /repos/{o}/{r}/pages` →
  `POST /repos/{o}/{r}/pages` (`build_type: workflow`, source
  `main` `/`) when not enabled → ensure `.github/workflows/pages.yml`
  exists via the contents API → poll `GET
  /repos/{o}/{r}/pages/deployments` (60 × 10s) → return `html_url`.
- Framework detection (`DeploymentTargets.detectFramework`): Next.js
  (`next.config.js/mjs`, build `npm run build`, output `.next`),
  Vite (`vite.config.js/ts`, `dist`), Nuxt (`nuxt.config.js/ts`,
  `.output/public`), Astro (`astro.config.mjs`, `dist`), Node.js
  (`package.json`, `dist`), else Static (no build, `.`).

### 5.2 Port (`YcodeUI/Deploy/`)

`DeploymentService` (no key shipped; tokens live in the secret
store; no token → honest failure before anything runs):

- Providers: `.netlify`, `.vercel`, `.githubPages` (same three,
  same raw values as Legacy's `DeploymentPlatform`).
- Token accounts (shared-file patch, coordinator applies —
  `SecretAccount` in `YcodeAssistant/SecretStore.swift` is outside
  this slice's owned set):
  `netlifyToken = "netlify.api-key"`,
  `vercelToken = "vercel.api-key"`. GitHub Pages reuses the
  existing `githubToken` account (Wave 10).
- **Netlify/Vercel**: the token is validated against the real
  provider API first (`GET https://api.netlify.com/api/v1/user`,
  `GET https://api.vercel.com/v2/user`, Bearer token; non-200 =
  invalid token, fail honestly). Then, Legacy-faithfully: parse
  `owner/repo` from the workspace's git remote, push the current
  branch with the git CLI (credential seeded via `git credential
  approve` on stdin from the stored GitHub token — the Wave 10
  pattern, never in argv/URL/log), and return the dashboard URL
  (or `https://<custom-domain>`). The window states plainly that
  the provider builds from the GitHub integration — no fake site
  URL is ever returned. This is a real provider client (token
  validation is a live provider call) over Legacy's real flow.
- **GitHub Pages**: real API calls through an injectable
  `URLSession` (stubbed in tests, never live): push → get Pages
  info → enable when absent → ensure `pages.yml` (contents API:
  GET for the SHA, PUT base64 content; the workflow is generated
  from the detected framework, ported from Legacy's
  `generateBuildSteps`) → poll deployments (12 × 5s; `succeeded`
  → return `html_url` or the custom domain; `failed`/`cancelled`/
  timeout → honest failure). The contents-API write is why this
  lives in the service's own adapter rather than `YcodeGitHub`
  (whose client has no contents write — see the patch below).
- Framework detection is ported verbatim from Legacy (same files,
  same outputs).
- `DeploymentResult`: success + url, or failure + message; every
  step logs through the caller's log handler, as Legacy did.

`DeploymentWindowController` (manager + window, 1100×700,
autosave `YcodeDeploymentWindow`): platform segmented picker,
custom-domain toggle + field, per-provider token status ("Stored"
 / "Not stored") + secure token field with Save (writes the secret
store; the token is never displayed back), Deploy button (disabled
while deploying or without a token), log view, result URL + Open
In Browser, error line. Follows the `SQLiteExplorerWindowManager`
pattern (shared manager, raise-or-create).

### 5.3 `YcodeGitHub` patch (coordinator applies — that target is owned by another slice)

Deliver the needed client endpoints as a patch description (the
service's own adapter covers the calls until it lands):

```swift
// GitHubClient.swift — workflow runs (CI dashboard):
public func listWorkflowRuns(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubWorkflowRun]  // GET /repos/{o}/{r}/actions/runs
public func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [GitHubWorkflowJob]        // GET /repos/{o}/{r}/actions/runs/{id}/jobs
public func rerunWorkflow(owner: String, repo: String, runID: Int) async throws                                  // POST /repos/{o}/{r}/actions/runs/{id}/rerun
public func listWorkflows(owner: String, repo: String) async throws -> [GitHubWorkflow]                          // GET /repos/{o}/{r}/actions/workflows
// …and Pages (deploy console):
public func getPagesInfo(owner: String, repo: String) async throws -> GitHubPagesInfo                             // GET /repos/{o}/{r}/pages
public func enablePages(owner: String, repo: String) async throws                                               // POST /repos/{o}/{r}/pages {build_type: workflow, source: {branch: main, path: /}}
public func listPagesDeployments(owner: String, repo: String) async throws -> [GitHubPagesDeployment]            // GET /repos/{o}/{r}/pages/deployments
public func getFileSHA(owner: String, repo: String, path: String, branch: String) async throws -> String?       // GET /repos/{o}/{r}/contents/{path}?ref={branch}
public func putFile(owner: String, repo: String, path: String, branch: String, message: String, content: Data, sha: String?) async throws // PUT /repos/{o}/{r}/contents/{path}
```

Models mirror the GitHub REST shapes (`GitHubModels.swift`
style, `convertFromSnakeCase` decoding): run (id, name, status,
conclusion, head_branch, head_sha, event, created_at, html_url),
job (id, name, status, conclusion, steps), workflow (id, name,
path, state), Pages info (url, status, html_url), Pages deployment
(id, status).

## 6. CI dashboard (`ci.VisualWF`)

### 6.1 Legacy evidence (verified live)

Two different things share the name in Legacy — the distinction
matters:

- `SDKCIWorkflowViewOpener` opens `WorkflowDashboardView`, the
  **local-automation** surface ("SwiftCode Workflows":
  Apple-Shortcuts-style local shell pipelines via
  `WorkflowManager`: `loadWorkflows` / `saveWorkflows` /
  `createWorkflow` / `deleteWorkflow` / `duplicateWorkflow` /
  `toggleFavorite` / `resolveVariables` / `runWorkflow` /
  `executeIndividualStep` / `cancelExecution`). Ycode has no
  workflow/automation concept; porting that engine is a separate
  subsystem and is **not** this slice (recorded in §9).
- The **real GitHub Actions** surface is `WorkflowRunsView` /
  `ActionsView`: run jobs + steps, console logs
  (`listWorkflowJobs`, `getJobLogs`), artifacts
  (`listWorkflowArtifacts`, `downloadArtifact`), re-run
  (`POST /repos/{owner}/{repo}/actions/runs/{run.id}/rerun`).
  **This** is what the task asked for ("the MINIMAL real one
  against the GitHub Actions API") and what this slice builds.

### 6.2 Port (`YcodeUI/CI/`)

`GitHubActionsService`: a thin adapter over `URLSession`
(injectable; stubbed in tests) with the stored GitHub token
(`SecretAccount.githubToken`) as the Bearer token. No token →
reads still work for public repos at GitHub's unauthenticated
rate limit (same rule as `GitHubClient`); writes (re-run) fail
honestly with "missing token". Calls: list runs, list jobs for a
run, job logs (`GET /repos/{o}/{r}/actions/jobs/{id}/logs`,
following the redirect GitHub returns), list workflows, re-run.
Decoding is `convertFromSnakeCase` + ISO-8601 dates. Every call
is a real GitHub REST call; nothing is fabricated, and the
dashboard shows an empty state — never fake runs — when the repo
has none.

`CIWindowController` (manager + window, 1100×700, autosave
`YcodeCIWindow`): owner/repo fields (defaulted from the
workspace's git remote, editable, persisted in UserDefaults
`com.ycode.ci.repository`), Refresh, runs table (name, branch,
status, conclusion, event, age), jobs + steps list for the
selected run, Logs button (fetches the selected job's logs into
the log view), Re-run button (POST rerun, then refresh). Follows
the `SQLiteExplorerWindowManager` pattern.

The `YcodeGitHub` endpoints for this live in the §5.3 patch
description; the service's own adapter is used until it lands.

## 7. Virtualization console (`virtualization.view`)

### 7.1 Legacy evidence (verified live)

- `SDKVirtualizationViewOpener` → `VirtualizationWindowManager.
  showWindow(for: project)` — "Virtualization Console" `NSWindow`
  (1100×750), `VirtualizationSplitViewController`, toolbar
  start/stop/restart + VM creation wizard.
- Engine: `SCVirtualizationEngine.instantiateRealVirtualMachine`
  returns a `VZVirtualMachine` — **Apple Virtualization.framework**,
  macOS-only. `VirtualMachine` model: name, osType (Ubuntu/Debian/
  Fedora/Alpine), version, status, cpuCores, memoryMB, storageGB,
  macAddress, ipAddress, uptime, createdDate, imagePath,
  sharedFolders, portForwardings, snapshots, bootCount, etc.
  Managers: snapshots, backups, images, monitoring, network,
  shared folders.

### 7.2 What Ycode's engine actually exposes (verified live)

`YcodeHypervisor` is a **Linux KVM** engine, consumed only by
`ycode-simd` internals: `Hypervisor.isAvailable`,
`VirtualMachine(ramGPA:ramSize:)` (a bare KVM VM with RAM only),
`makeVCPU`, memory slots, `close()`. There is no named-VM model,
no guest-kernel loading, no disk image handling, no display, no
VZ wrapper — and on macOS (Dylan's Mac) KVM does not exist at all,
so `isAvailable` is false there. A console that claimed to boot
Legacy-style VMs over this engine would be fake.

### 7.3 Port (`YcodeUI/Virtualization/`)

`VirtualMachineRegistry`: a persisted registry of VM definitions
(ported subset of Legacy's `VirtualMachine`: id, name, osType,
version, status, cpuCores, memoryMB, storageGB, imagePath,
createdDate, bootCount), JSON in Application Support
`Ycode/VirtualMachines/registry.json`. Create / duplicate / delete
/ rename; image paths are validated to exist. The registry is real
state, not a mock list.

`VirtualMachineHostProbe`: the honest engine surface. `probe()`
reports `Hypervisor.isAvailable` and attempts a real KVM
allocation (`VirtualMachine(ramSize:)` + `makeVCPU` per
requested core, then `close()`), returning the outcome or the real
`KVMError`. On macOS this fails honestly with the engine's own
error, and the window says so.

`VirtualizationWindowController` (manager + window, 1100×750,
autosave `YcodeVirtualizationWindow`): VM list sidebar, detail
pane (config, image, boot count, status), host-capability line,
Create wizard (name, OS, CPU, RAM, disk image picker), Allocate /
Release buttons, Probe Host button. **Allocate / Release — not
Start / Stop**: Allocate reserves a real KVM VM (RAM + vCPUs) and
holds it while "allocated"; Release closes it. The window states
plainly that no guest kernel is loaded and no display exists, so
this is not a boot. Guest boot (a VZ wrapper on macOS, or a
kernel+disk boot path on KVM) is the missing runtime — recorded
in §9, not faked here.

Package wiring (coordinator applies): add `"YcodeHypervisor"` to
the `YcodeUI` target dependencies in `ycode/Package.swift`.
(`YcodeUI` does not depend on it today.)

## 8. Sandboxed terminal (`sandbox.view`)

### 8.1 Legacy evidence (verified live)

Legacy's terminal is **not** a PTY shell (`TerminalView.swift`):
`TerminalSession.runCommand` runs each entered command as a fresh
`Process` with `/bin/zsh -c <cmd>`, piping stdout/stderr, working
directory `/` by default, profiles `zsh`/`bash`. No `pty`/`PTY`,
no stdin writes. Tabs, themes, and SSH sessions surround that
core.

### 8.2 The security decision (recorded, not dodged)

Shipping an extension-openable unsandboxed shell under the name
`sandbox` would be a lie and a hole. Decision implemented here:

- **No shell, ever.** Commands run as argv (`/usr/bin/env` +
  argv), never through `/bin/zsh -c` — shell metacharacters
  (`; & | < > \` $() ` + backticks) are rejected before execution,
  so there is no shell-injection path by construction.
- **Allowlist, deny-by-default.** The first token must be in the
  policy's allowlist (read-oriented commands: `ls pwd echo date
  uname whoami cat head tail wc grep find du df git swift xcrun`
  + an editable user list). `git` is restricted to read-only
  subcommands (`status log diff branch remote rev-parse show
  ls-files`).
- **Workspace confinement.** The working directory must resolve
  inside the workspace root; anything else is refused.
- **Scrubbed environment.** Only `PATH=/usr/bin:/bin:/usr/local/bin`,
  `HOME`, `LANG`, `TMPDIR` are passed through.
- **No stdin, bounded output, timeout.** stdin is the null device;
  output is capped (1 MB / 10,000 lines); a 60s timeout terminates
  the process.
- **User-opened only.** The window opens from the IDE, never from
  an SDK view or an MCP tool. `use_terminal` remains the extension
  path, with its own terminal-approval allow-list.

What this is **not**: a macOS Seatbelt sandbox. `YcodeSubprocess`
enforces no sandboxing at all (verified live — zero
`sandbox`/`seatbelt` hits in its sources), and this runner adds
in-process confinement, not a kernel profile. A true Seatbelt
profile via `sandbox-exec` is the follow-up decision for Dylan:
it would further restrict file/network access but needs a profile
he approves, since it changes what legitimate commands can do.
Until then the window is labelled honestly as a workspace-confined
command runner, and the `sandbox.view` SDK ID stays unavailable
to extensions.

### 8.3 Port (`YcodeUI/Terminal/`)

`SandboxedCommandRunner`: `SandboxPolicy` (allowlist, git
subcommands, timeout, output cap) + `run(commandLine:workingDirectory:policy:)`
— tokenises with quote awareness, validates, executes with
streaming output (stdout/stderr lines with kinds), timeout kill,
and returns exit status + `timedOut`. Errors are `SandboxError`
(`notAllowed`, `metacharacters`, `outsideWorkspace`, `timedOut`,
`launchFailed`) — never a fake success.

`SandboxTerminalWindowController` (manager + window, 900×600,
autosave `YcodeSandboxTerminalWindow`): command field + Run/Stop,
monospaced output view (command / output / error / info lines, as
Legacy's `TerminalLine`), cwd label, policy note ("Workspace-confined
— no shell, allowlisted commands only"), session log. One session
per window; tabs/SSH are Legacy scope, not this slice.

## 9. Artboards UI

### 9.1 Legacy evidence (verified live)

- There **is** a file format in Legacy: `VisualUIDocument.save(to:)`
  / `load(from:)` JSON-encode the `VisualUIScene` (pretty-printed).
  The scene holds `artboards: [VisualUIArtboard]`,
  `activeArtboardID`, `currentFramework`, `zoomScale`, `panOffset`.
  An artboard holds `name`, `deviceFrame`, `rootNode:
  VisualComponentNode`, `customSwiftUISource`, `appearance`
  ("Light"/"Dark"/"System"), `isPortrait`, `dynamicTypeSize`,
  `previewScale`, `showSafeAreas`. A node holds `type:
  VisualComponentType` (57 cases, see §9.2), `name`, `children`,
  `properties: [String: String]`, `isLocked`, `isHidden`.
  Undo/redo are JSON snapshots of the scene (`checkpoint()`).
- Wave 5's port kept the in-memory record only (`ArtboardRecord`:
  id, name, deviceFrame, source, appearance, portrait, root type/
  name, child count, `lastCompileError`) and the tools
  (`artboard_create/get/list/update/delete/compile/run_app`,
  `fix_artboards`). `fix_artboards` ported passes 3 (source repair:
  inject `import SwiftUI`, append `#Preview`) and 4 (recompile the
  active artboard) for real; pass 1 (simulator/destination audit)
  is audit-only; pass 2 (DerivedData clean) was report-only.
- The Visual UI Builder itself (`VisualUIBuilderWindowController`,
  `VisualUICanvasView`, `VisualUIInspector`, `VisualUIComponentLibrary`,
  `VisualUIPreviewPanel`, `VisualUIRenderer`) is a full builder;
  this slice ports its **core**: artboard list, component tree,
  inspector, source editor, preview render, persistence, fix —
  not the animations/bindings/assets/AI panels (recorded in §9).

### 9.2 Format (`YcodeMCP/YcodeTools+Artboards.swift`, owned)

New public, Codable model in the owned tools file (the MCP host and
the UI share one store — YcodeUI already depends on YcodeMCP):

- `ArtboardComponentType`: Legacy's `VisualComponentType`, all 57
  cases with the same raw values + `systemIcon` (SF Symbol names,
  ported verbatim). `CaseIterable`.
- `ArtboardComponentNode`: id, type, name, children, properties,
  isLocked, isHidden — Legacy's `VisualComponentNode` shape, as a
  struct (value semantics suit the store; `duplicated()` ports
  Legacy's copy with fresh ids).
- `ArtboardRecord` becomes `Codable` + `public`, gains `rootNode:
  ArtboardComponentNode`; `rootType` / `rootName` / `childCount`
  stay as computed properties so existing tool code is untouched.
  `lastCompileError` is runtime-only (`CodingKeys` excludes it —
  a stale compile error must never be reloaded as fact).
- `ArtboardDocument`: `{ version: 1, artboards, activeArtboardID,
  framework, zoomScale, panOffsetX, panOffsetY }`, JSON
  pretty-printed — Legacy's `save` shape. File extension
  **`.ycode-artboard`**.
- `ArtboardStore`: file URL per workspace — Application Support
  `Ycode/Artboards/<sha256(workspace path)[:12]>.ycode-artboard`
  (the same hashing scheme as
  `CodingAssistantModel.archiveURL(forWorkspace:)`); `load` /
  `save` (atomic write); host-extension `ensureArtboardsLoaded`
  / `saveArtboards` called from the artboard tool handlers
  (create/update/delete/fix pass 3) so the tools and the window
  share one persisted truth. A missing file loads as empty (a
  fresh document, like Legacy's); a corrupt file fails honestly
  instead of silently resetting.
- `fix_artboards` pass 2 is now real for previews: when the scope
  includes previews, the preview-render cache
  (`XDG_CACHE_HOME ?? ~/.cache` + `ycode/preview-render` — the
  exact directory `PreviewRenderRunner` writes) is deleted and the
  action is recorded. For `full_app` scope the action still points
  at the `clean` tool (Ycode has no DerivedData). Pass 1 stays
  audit-only (no destination to realign, no simulator booted by
  the tool itself).

### 9.3 Window (`YcodeUI/Artboards/ArtboardWindowController.swift`)

`ArtboardWindowManager` (shared, raise-or-create; takes the
workspace folder) + `ArtboardWindowController` (1200×750, autosave
`YcodeArtboardsWindow`):

- Sidebar: artboard list (name + device frame), New / Duplicate /
  Delete, active artboard.
- Canvas: the rendered preview PNG (see §9.4) or "No preview yet —
  Render Preview".
- Tree: the root node + children (outline), Add Component (menu of
  `ArtboardComponentType`), Delete Node, rename, lock/hide toggles.
- Inspector: selected node's name + properties (key/value text
  fields, `textValue` / `sfSymbolName` / `padding` / `cornerRadius`
  as in Legacy's property keys) + artboard settings (device frame,
  appearance, portrait).
- Source: monospaced editor for `customSwiftUISource` + Render
  Preview + Fix (runs the `fix_artboards` tool through the
  window's MCP server when one is supplied; otherwise disabled
  with the reason). Save is automatic on change (debounced) to the
  `.ycode-artboard` file; Open… loads one.
- Undo/redo: JSON-scene snapshots, ported from Legacy's
  `checkpoint()` (undo stack of encoded scenes).

### 9.4 Live preview session

No second preview engine is built. Rendering reuses
`YcodePreviews.PreviewRenderRunner` exactly as
`artboard_compile` already does (write the source to a temp file,
render the `#Preview`, show the PNG). The editor-area live canvas
(`showLivePreview` / `setCanvasShown`) is the project's canvas,
not the artboard's, so the artboard window renders on demand and
says so — "Render Preview" is a real render, not a live session
claim. A continuously-live artboard session (re-render on every
keystroke against a persistent preview host) is follow-up scope.

## 10. View-host wiring (patch, coordinator applies)

`YcodeSDKViewHost.swift` is outside this slice's owned set. The
patch adds four surface actions + routes four IDs, and shrinks
`unavailableReasons` from 5 entries to 1 (`docs.search` — Wave 19):

```swift
// SDKViewSurfaceActions (protocol, @MainActor):
func showDeployConsole(workspaceFolder: URL) throws
func showCIDashboard(workspaceFolder: URL) throws
func showVirtualizationConsole() throws
func showSandboxTerminal(workspaceFolder: URL) throws
// WorkspaceSDKViewSurfaceActions: each resolves the key workspace
// window for the folder (deploy/CI/sandbox are project-anchored,
// virtualization is not) and calls the matching manager:
//   DeploymentWindowManager.shared.showWindow(workspaceFolder:)
//   CIWindowManager.shared.showWindow(workspaceFolder:)
//   VirtualizationWindowManager.shared.showWindow()
//   SandboxTerminalWindowManager.shared.showWindow(workspaceFolder:)
// YcodeSDKViewHost.open: route "deployConsole.view", "ci.VisualWF",
// "virtualization.view", "sandbox.view" to the new actions; remove
// those four keys from unavailableReasons. "docs.search" stays.
// Artboards has no SDK view ID (Legacy's 12 IDs cover
// uibuilder.open for Interface Builder, not the builder); the
// Artboards window opens from its manager directly — no host
// patch for it.
```

## 11. Tests

- `YcodeAssistantTests/SlashMenuGapTests.swift`: palette state
  (filtering, leading `/`, empty query, wraparound, empty list),
  `searchCommands` behaviour, `useMetaSlashCommands` default true
  (needs the §1.2 patch), Meta settings defaults, router
  `handleTurnFailure` (auto-switch off → nil; timeout fails over;
  quota excludes the whole provider; no candidates → nil).
- `YcodeMCPTests/LiveExtensionWriteGapTests.swift`: granted write
  asks with the caller attached (ask sees `caller.extensionID`),
  accept writes, reject writes nothing, ungranted write refused
  before any ask, read-only policy refuses extension writes,
  host calls unchanged.
- `YcodeUITests/Wave17FollowUpGapTests.swift`: settings pane
  controls round-trip (slash toggle, timeout, other-model fields);
  extension presenter with an injected reviewer (accept/reject,
  no-window refuse); deploy service with a stub `URLSession`
  (Netlify/Vercel token validation, Pages enable + poll, no-token
  failure, framework detection); CI adapter with a stub session
  (runs/jobs/logs/rerun decoding, empty runs); VM registry
  save/load round-trip + probe result shape; sandboxed runner
  (allowlist refusal, metacharacter rejection, cwd confinement,
  env scrub, timeout kill, `git` subcommand restriction);
  artboard document encode/decode + store save/load round-trip.

All tests use fixtures / stub transports / throwaway directories.
Never live network, never real credentials, never the keychain
(`MemorySecretStore`).

## 12. Honestly unavailable / still pending

- `docs.search`: Wave 19 owns it. Not touched.
- Legacy's **local-automation** workflow engine (`WorkflowManager`
  + `WorkflowDashboardView`): not ported. The CI dashboard built
  here is the GitHub Actions surface, per the task. A local
  workflow engine is a separate subsystem decision.
- Legacy Virtualization's VZ guest boot, display, snapshots,
  networking, shared folders, monitoring: not ported. The console
  manages definitions + a real KVM allocation probe; boot/display
  need a VZ wrapper (macOS) or a kernel-boot path (KVM).
- Legacy Terminal's tabs, themes, SSH sessions, and PTY: not
  ported. The sandbox window is one workspace-confined session;
  there is intentionally no PTY (Legacy had none either).
- Legacy Visual UI Builder's animations, bindings, assets, AI
  assistant, templates, export panels: not ported — the window
  is the builder's core (list/tree/inspector/source/preview/save).
- A continuously-live artboard preview session: renders are
  on-demand through `PreviewRenderRunner`.
- The composed live-extension-write path end-to-end (backend →
  runner → live server with seeded grants): covered in pieces,
  not as one test (no seam for seeding live grants).
- Mac `swift build` / `swift test` for everything in this slice,
  and live runs (deploy against a real repo, CI against a real
  repo, VM probe on a KVM host, artboard render on macOS).
- Dylan must supply, for live use (nothing is shipped): a Netlify
  token and/or Vercel token (stored in Settings from the Deploy
  window), a GitHub PAT (already the Wave 10 prerequisite) for
  Pages/CI, and a linked GitHub repo for the workspace being
  deployed.

## Evidence

Every claim in this spec comes from one of two sources, both
permitted by the clean-room protocol (Legacy is Dylan's own code;
direct porting under MIT was authorised by him):

- **Legacy source, read directly** (Dylan's own code, not Apple
  code): `AppSettings.useMetaSlashCommands` default and load;
  `AssistMainView` `/` trigger; `AssistComposerPopup` rows,
  filtering, selection; `AssistSettingsView` toggle text;
  `DeploymentsView` / `DeploymentTargets` / `NetlifyManager` /
  `VercelManager` / `GitHubPagesManager` (deploy flows, endpoints,
  framework detection); `SDKCIWorkflowViewOpener` /
  `WorkflowDashboardView` / `WorkflowManager` (local automation)
  vs `WorkflowRunsView` (GitHub Actions jobs/logs/artifacts/
  re-run); `SDKVirtualizationViewOpener` / `SCVirtualizationEngine`
  (VZ engine) / `VirtualMachine` model; `TerminalView`
  (`TerminalSession` = `Process` + `/bin/zsh -c`, no PTY);
  `VisualUIScene` / `VisualUIDocument` (JSON scene format,
  component types, undo snapshots); `AssistFixArtboardsTool`
  (passes 1–4).
- **Destination source, read directly** (Ycode's own code):
  `MetaSlashCommandManager.searchCommands` / `executeCommand`;
  `AssistantSettings` field names and defaults;
  `AssistModelRouter.handleTurnFailure` / `classify` /
  `eligibleCandidates`; `CodingAssistantModel.send` /
  `handleMetaSlashCommand`; `MCPServer.run` grant check + review
  policy; `YcodeSDKToolRunner` + `YcodeSDKToolServerRegistry`;
  `YcodeGitHub/GitHubClient` endpoint list (no workflow-runs or
  Pages endpoints); `YcodeHypervisor` (KVM-only API surface);
  `YcodeSubprocess` (no sandboxing); `YcodePreviews.
  PreviewRenderRunner` (headless render + cache directory);
  `YcodeTools+Artboards` (in-memory records, fix passes 3–4).

No reference Xcode copy, Ghidra output, simulator IPSW, or
`research/dirty/` material was opened or used. No Apple code or
code-shaped text enters this spec or the implementation.
