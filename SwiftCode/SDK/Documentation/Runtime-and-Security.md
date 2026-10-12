# Runtime and Security

**Status:** Phases 3–4 contracts, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §§4, 8, 9, 10, 16, 17 · **ADR:** `SDK-Architecture.md` §§3, 4, 5, 9, 12

## Out-of-process node runtime

Extensions never run in-process. `SDKNodeLauncher`
(`Runtime/Isolation/SDKNodeLauncher.swift`) spawns one `node` child process
per extension with dedicated stdio pipes (the runtime-adapter, see
`TypeScript-Extensions.md`). The launch is argument-vector based — `[node,
entrypoint.path]` — no shell, so there is no shell-quoting or shell-injection
surface at this layer. `launch()` returns immediately after spawning; waiting
for exit is async via `SDKLaunchedRuntime.waitForExit()` (a
`terminationHandler` + `CheckedContinuation`, no polling, no blocked
thread). A hung or crashed extension cannot block the host UI or the main
thread.

The child inherits the host process environment as-is. No secrets cross this
boundary: `SDKNodeLauncher` documents that secrets never pass through launch
— credentials are mediated by host services behind the capability broker, and
extensions only ever receive host-mediated results.

## Node resolution and the missing-runtime path

SwiftCode does not bundle Node.js, does not assume one is installed, and
**never downloads or executes a runtime binary silently** (spec §4.2).
`resolveNodeURL()` inspects the filesystem only, in this order:

1. `SWIFTCODE_NODE_PATH` — when set to a non-blank value it MUST name an
   existing executable file (tilde expanded); otherwise
   `RUNTIME_UNAVAILABLE` names the configured value. An explicit override is
   never silently ignored in favor of another binary.
2. Well-known locations: `/opt/homebrew/bin/node` (Apple Silicon),
   `/usr/local/bin/node` (Intel/manual), `/usr/bin/node`.
3. Each `PATH` component + `/node` (empty components skipped).

A candidate counts only when it exists, is not a directory, and is
executable. When nothing is found, launch fails with a typed
`RUNTIME_UNAVAILABLE` error carrying actionable guidance (install Node.js 20
or later from nodejs.org / Homebrew, or set `SWIFTCODE_NODE_PATH`). The
missing-runtime path is a first-class, tested outcome — never a crash, hang,
or silent download. The launch also rejects a non-file entrypoint with
`RUNTIME_LAUNCH_FAILED` before spawning.

## stdio NDJSON IPC

`SDKIPCTransport` (`Runtime/IPC/`) is the host-side transport: an actor
(serialized reads and writes, never on `@MainActor`) over the child process's
pipes — host→extension on the child's stdin, extension→host on the child's
stdout. One envelope per line (`\n` = 0x0A), UTF-8 JSON; `SDKIPCCodec`
guarantees encoded frames contain no literal newlines, so a line boundary is
always a frame boundary.

- **1 MiB frame bound** (`SDKIPCCodec.maxMessageBytes = 1_048_576`), enforced
  *during* accumulation — an oversized frame throws
  `RESOURCE_LIMIT_EXCEEDED` the moment the bound is exceeded, never after
  buffering the whole frame. After an oversized frame the transport marks
  itself desynchronized (stream position unknown) and refuses further reads
  until replaced.
- Clean EOF → `RUNTIME_CRASH`; EOF with a partial frame → `IPC_MALFORMED`.
- `SDKIPCDispatcher` owns the request pipeline per session: peek
  `protocolVersion` (≠ 1 → `IPC_PROTOCOL_MISMATCH`) → envelope type must be
  `.request` (→ `IPC_MALFORMED`) → **Assist deny-list first, before any
  routing or payload decoding** → session-bound caller identity built from
  the host-created session (never from the payload) → route with a **60 s
  per-request timeout** (→ `IPC_TIMEOUT`) → encode the
  `ok`/`ok: false` response. The timeout uses a detached watchdog + an
  exactly-once latch, so a non-cooperative operation (e.g. `build.wait` on a
  long build) still errors at 60 s — the build keeps running detached and the
  extension can poll again.
- Unknown methods answer `IPC_MALFORMED`; malformed payloads for known
  methods answer `INVALID_ARGUMENT`. `dispatch()` never throws outward.

The driver that moves sessions through launch → IPC → teardown (the host
coordinator) arrives in a later phase: `SDKRuntimeSession` is pure lifecycle
bookkeeping today (see below), and the transport/dispatcher/session are wired
together by that driver.

## Lifecycle states

`SDKRuntimeSession` (`Runtime/Lifecycle/`) is a strict, actor-guarded state
machine (spec §10.5). Forward flow is strictly linear:

```
discovered → validated → awaitingPermission → ready → starting → active
  → stopping → stopped
```

Failure states (`failedValidation`, `failedVersion`, `permissionDenied`,
`launchFailed`, `activationFailed`, `crashed`, `timedOut`, `terminated`) are
reachable from **any** state; terminal states (`stopped`, `crashed`,
`timedOut`, `terminated`, plus all failure states) never return to a forward
state. Illegal transitions throw `ACTIVATION_FAILED` naming the pair.
History is append-only — failures append, never mutate. Terminal entry
audit-records once (`runtimeTerminated`, no secrets).

- **Bounded restarts:** `maxCrashRestarts = 3`; `canRestart` becomes false
  after three crashes — no infinite crash/restart loop. A re-launch uses a
  NEW session (fresh `.discovered` history), never a backward transition.
- **Deactivation** runs the owner-supplied `onDeactivate` hook exactly once
  (commands disposed, subscriptions cleared, build handles and streams
  released), then moves to `.stopped`. Bounded-time app shutdown (timeout →
  `.timedOut`) is the driver's job.
- `requestStop()` is legal from `.active`/`.starting` and idempotent.

## Resource limits and honest non-goals

Enforced, real limits:

| Bound | Value | Enforced by |
|---|---|---|
| IPC frame size | 1 MiB | transport, during accumulation |
| Per-request wall clock | 60 s | dispatcher watchdog |
| TS client request timeout | 60 s | `createStdioConnection` |
| Manifest size | 64 KB | `SDKManifestValidator` |
| Package entries | 10,000 | `SDKPackageValidator` |
| Package total size | 100 MB | `SDKPackageValidator` |
| Capability requests | 32 | manifest validator |
| Commands contributed/registered | 64 | manifest validator + command registry |
| Grant `reason` / command title | 500 / 128 chars | validators |
| API key secret input | 4,096 chars | `SDKAPIKeyCodec` (DoS bound) |
| Extension `deactivate()` budget | 5 s | runtime adapter teardown |
| Developer log file | 10 MB, then rotated | `SDKDeveloperLogger` |
| Log read chunk / pipe I/O | 65 536-byte syscalls | transport framing |

Honest non-goals (stated in the code so they are not misread as guarantees):

- **No hard CPU or memory caps** on the child process — there is no supported
  per-child resource-cap API usable from this layer. Enforcement lives at
  higher layers: per-request timeouts, message-size bounds, build/output
  caps.
- **No OS sandboxing.** The app is unsandboxed; extension isolation is the
  **process boundary plus broker enforcement**, not OS sandboxing. Nothing in
  this document claims a sandbox.
- No per-child sandbox API, no bundled Node.js, no silent runtime downloads.

## Permission enforcement at every call

Authorization lives at the capability broker and is invoked on every
privileged call (`Capabilities-and-Permissions.md`):

- `SDKSourceControlAdapter.getStatus`/`getDiff` authorize
  `.sourceControlRead` on every call; `SDKBuildService.run` authorizes
  `.buildExecute`. The adapter is the only layer that may touch app
  singletons, and the broker call precedes that touch.
- The IPC dispatcher binds caller identity from the host-created
  `SDKRuntimeSessionInfo` (validated manifest ID + package digest) — an
  extension-supplied identity field is never trusted (§10.4). A forged
  identity in a payload cannot escalate because no identity field is read
  from the payload anywhere in the dispatcher.
- Build handles minted by an authorized `build.run` are unguessable UUIDs in
  a per-session map; possession of a live handle is the authorization for
  `build.wait`/`build.cancel` on that handle.
- UI hiding, manifest capability claims, and TypeScript type signatures are
  NOT security controls; the broker check on the receiving side is.

Until the runtime driver lands (Phase 4 follow-up), the "registered and
currently active" check from spec §8.4 is not yet wired — the broker trusts
`SDKCallerIdentity` passed by host-owned code paths only, and every call site
of `authorize` MUST be host code (adapters, host API façade, dispatcher).
Extension-supplied identity is never accepted at the IPC boundary.

## Assist isolation: what's enforced, what's future work

**Enforced today (the real guarantee):**

- `assist.invoke` is deny-by-default in the broker — checked **first**,
  before the grant store, so no grant, scope, or identity state can ever
  satisfy it. Any request → typed `ASSIST_DENIED` + audit event.
- No `assist` object exists in the TypeScript `SwiftCodeContext`; there is no
  general-purpose bridge to `AssistManager`, `AssistAPIRouter`, or
  `LLMService`.
- `SDKAssistGate.check` runs on **every inbound IPC method name** before
  routing or payload decoding: case-insensitive substring deny-list
  (`"assist"`, `"llm."`, `"agent_runner"`, `"chat"`, `"sendMessage"`).
  Any match → `ASSIST_DENIED` + audit event with the method in the detail.
- The manifest `"assist": {"requested": ...}` is descriptive metadata only —
  it never grants anything, and no dormant bypass is added.
- A manifest declaring the `assist.invoke` capability ID is rejected at
  host install-time validation (`UNKNOWN_CAPABILITY`) — see
  `Extension-Manifest.md`; the net effect is the same deny, surfaced earlier.

**Future work (stated honestly in `SDKAssistGate.swift`):** the host app's
real Assist choke points — `AssistManager.shared.sendMessage`,
`AssistAPIRouter.route`, `LLMService.sendChatRequest`, the Antigravity
bridge Unix socket — do not identify an SDK extension as the caller, so none
can gate per-extension Assist access on their own. Plumbing the calling
extension's identity from the SDK surface into those paths is future work
that must be designed and reviewed as its own feature. Until then, the
enforceable guarantee is exactly the list above: the SDK exposes no Assist
surface, the broker denies the capability, and any attempt at the SDK layer
is denied and audited. Do not read a stronger claim into this release.

## Packaging and install integrity

- **Deterministic package:** `swiftcode package` produces a
  `.swiftcode-extension` zip with entries sorted by name, fixed mtime
  (`2000-01-01T00:00:00Z`), fixed mode (0644), fixed deflate level — the
  archive is byte-reproducible and its sha256 digest is stable. Shippable
  set: `swiftcode.json`, `dist/**`, `schemas/**`, `README.md`,
  `package.json` — never `node_modules/`, `.env` files, `*.tsbuildinfo`, or
  version-control droppings.
- **Canonical package digest:** `SDKExtensionRegistry.computeDigest(of:)`
  hashes every entry in sorted relative-path order (path + kind byte +
  streamed file content / symlink target), excluding the host-written
  `.sdk-install.json`. Independent of where the tree lives on disk.
- **Install root:** `~/Library/Application Support/SwiftCode/Extensions/`
  laid out `<extension-id>/<version>/`. Each version dir holds
  `swiftcode.json` and `.sdk-install.json` (0600, atomic write). The registry
  `scan()` **re-validates every manifest** — a tampered install fails closed;
  the record alone is never trusted, and record id/version must match the
  directory layout.
- **Digest binding:** grants are bound to the package digest at grant time.
  An updated package (changed digest) does not inherit grants — the broker
  denies until the user re-approves (spec §8.7). The CLI `--update` flow
  backs up, re-validates the installed tree, and rolls back on failure.
- **Validation before trust:** install validates the staged tree with the
  canonical validator *before* it touches the controlled directory, and
  reports nothing as installed until fully verified.

## Key and log storage

- **Developer API keys:** secrets never stored; HMAC verification against a
  Keychain-backed 32-byte device key. Only metadata in `SDKKeychain`
  (service `com.swiftcode.sdk`, accounts `sdk.device-key` /
  `sdk.apikey.<uuid>`). The purpose-built wrapper has **no UserDefaults
  fallback**, **no in-memory cache**, accessibility
  `WhenUnlockedThisDeviceOnly`, no iCloud sync. Keychain failures surface as
  `SERVICE_UNAVAILABLE` — never by degrading to a weaker store.
- **Grant store:** `~/Library/Application Support/SwiftCode/SDKGrants.json`,
  mode `0600`, atomic writes.
- **Audit log:** `~/Library/Application Support/SwiftCode/SDKAudit.jsonl`,
  directory `0700`, file `0600` re-enforced on every open. Never rotated or
  truncated by the SDK.
- **Dual logging (spec §16):** user-facing sanitized stream (rendered in the
  Activity Console and Studio notification popovers — no stack traces,
  paths, addresses, or secrets, via `SDKLogRedaction.sanitizeForUser`) and
  the developer verbose stream at `~/.swiftcode/logs/developer-sdk.log`
  (JSON lines, 0600, directory 0700, rotated at 10 MB; secrets redacted via
  `SDKLogRedaction.redactSecrets`). Both sides share the `ERR-XXXXXX`
  correlation ID, which is the only linkage — the wire error to an extension
  carries just `{ code, message, correlationId }`.

## Extension-held secrets (`use.Security`)

The `use.Security` capability — per-app-namespaced, host-mediated
secret storage and use, with the extension never seeing plaintext — is
specified in `Security-Keychain.md`. Its capability IDs, audit event types,
scope-list entries, TypeScript client (`TypeScript/package/src/security.ts`),
and host store (`Host/Security/KeychainSDK.swift`) exist only as
uncommitted working-tree changes; the `security.*` dispatcher routes and
`EnterSecuritySDKView` are still missing. The Key and log storage
guarantees above are the complete implemented-and-committed story for SDK
secrets.
