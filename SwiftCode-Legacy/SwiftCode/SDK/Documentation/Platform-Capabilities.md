# Platform Capabilities

**Status:** Phase 2 contract, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §§8.1, 10.4 · **ADR:** `SDK-Architecture.md` §§5, 7, 9, 11

SDK 1.1.0 introduced the **platform capabilities**; SDK 1.2.0 completes the
set at 14 capability IDs with `deployConsole.view` and `virtualization.view`,
and re-targets `sandbox.view` to the real `TerminalView` sheet. These let an
extension open host-owned platform surfaces (`ui.openView`), call the
SwiftCode Cloud Model (`cloudModel.complete`), or run sandboxed commands
(`terminalSandbox.run`). Every platform capability must be declared in the
extension manifest and approved by the user, exactly like the Phase 1 IDs
(see `Capabilities-and-Permissions.md`).

## Opening a platform view

```ts
await context.ui.openView("sandbox.view");
```

- The `viewId` **is** the capability ID (e.g. `"db.ExploreView"`,
  `"ci.VisualWF"`, `"sandbox.view"`, `"simulator.view"`, `"preview.live"`,
  `"uibuilder.open"`, `"symbols.browse"`, `"docs.search"`,
  `"dictionary.open"`, `"deviceconnect.open"`) — match it verbatim.
- On the wire this is the `ui.openView` IPC route
  (`Host/ViewOpener/SDKViewOpener.swift` via `SDKIPCDispatcher`).
- The dispatcher authorizes **that exact grant** at the capability broker
  *before* the opener runs: the view is gated by precisely the grant the
  manifest declared. `PERMISSION_DENIED` if the grant is missing.
- An unknown `viewId` is rejected with a typed `UNKNOWN_CAPABILITY` error —
  never a silent no-op. `deployConsole.view` opens the real Deployments
  console (`SwiftCode/Views/Deployments/DeploymentsView.swift`) via the
  toolbar-notification bridge.
- The 12 `view` entries delegate to `SDKViewOpener`'s real registered
  openers (`SDKViewOpenerBuiltIns.swift`) — nothing is a stub.

Code samples for common views (including a `context.ui.openView(...)`
example) ship in the `@swiftcode/sdk` `snippets.ts` module (`SNIPPETS`,
exported from `index.ts`).

## The `use.SwiftCodeModel` flow

```ts
const text = await context.cloudModel.complete({
  prompt: "Summarize the working-tree diff.",
  history: [],            // optional conversation history
  systemPrompt: "...",    // optional, prepended by the host
  modelIdentifier: "...", // optional; omit for the host default
});
```

- Wire route: `cloudModel.complete` (`SDKIPCDispatcher` →
  `SDKCloudModelService`), authorized per-call at the broker under the
  `use.SwiftCodeModel` grant.
- **Host-mediated, end to end.** The extension never sees the endpoint URL,
  the device fingerprint, the user's quota state, or any credentials —
  `CloudModelRequest` carries only the prompt content. The host enforces the
  user's quota on **every** call (10 requests per rolling 24h at launch).
- Quota exhaustion surfaces as a typed `RESOURCE_LIMIT_EXCEEDED` error, not
  a fabricated response. Capability missing → `PERMISSION_DENIED`.
- This capability does NOT grant access to any other cloud model or to the
  raw endpoint.

## `terminal.sandbox` security rules

```ts
const result = await context.terminalSandbox.run({
  command: "git", args: ["status"],
  workingDirectory: ".", timeout: 30000,
});
```

`terminal.sandbox` is **sandboxed command execution, not a terminal UI**
(`Host/ServiceAdapters/Terminal/SDKSandboxedTerminal.swift`). It is
deliberately distinct from `sandbox.view`, which opens SwiftCode's real
`TerminalView` — a full unsandboxed `/bin/zsh` shell. That is why
`sandbox.view` stays a **HIGH-RISK** capability requiring explicit user
approval: opening it gives the user a complete interactive shell, not a
sandbox. All rules below are enforced **host-side, on every call**:

1. **Per-call broker authorization** — `.terminalSandbox` is authorized
   *first*, before any validation or process work. A revoked/expired grant
   fails the next call; there is no cached or ambient authorization.
2. **No shell, ever.** `command` takes two forms, both validated before use:
   a bare name must match `^[A-Za-z0-9._-]{1,64}$` (no `/`, no whitespace)
   **and** be a member of the host allow-list (`allowedExecutableNames`); it
   is resolved by searching `approvedExecutableDirectories` in fixed order
   and taking the first regular executable file. The ambient `PATH` is never
   consulted.
3. **Confinement:** the working directory is confined to the project scope,
   the environment is sanitized, output is byte-capped, and a hard timeout
   bounds every run — one `Process` per call.
4. This capability does NOT grant opening a terminal surface, unsandboxed
   shell access, or files outside the sandbox.

## API keys for privileged capabilities

All **high-risk** capabilities (network requests, custom builds, credential
use, workspace/source-control writes, task execution, and the platform
capabilities `use.SwiftCodeModel` and `terminal.sandbox`) are *privileged*
for the Developer API Key system (spec §8.2.1; `SDKCapabilityRegistry.isPrivileged`):

- A session presenting a developer API key (`SWIFTCODE_API_KEY` in the host
  process's environment, bound to the runtime session) additionally requires
  the key to carry the **`capabilities:request`** scope — enforced at grant
  issuance (`SDKGrantStore.recordGrants(authorizedByAPIKey:)`) and again at
  every broker authorization (`SDKCapabilityBroker.authorize`), each
  emitting `apiKeyScopeFailure` on denial.
- A session presenting **no key** authorizes purely through user grants, as
  in 1.0.0. The scope rule never loosens or bypasses the grant check.
