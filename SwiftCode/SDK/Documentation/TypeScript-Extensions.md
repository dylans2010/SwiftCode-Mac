# TypeScript Extensions

**Status:** Phase 5 contract, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §§6, 11–13 · **ADR:** `SDK-Architecture.md` §3

TypeScript extensions run **out-of-process** in a `node` child process
(see `Runtime-and-Security.md`) and talk to the SwiftCode host over a stdio
NDJSON channel. This document covers the developer contract they write
against.

## The `@swiftcode/sdk` package

`TypeScript/package/` (`src/`) is the real SDK — IPC client plus the full
developer-facing context, not just types. It is workspace-local (not
published to npm); generated extensions depend on it via a `file:` URL.
Build: `npm run build` (`tsc -p tsconfig.json`) → `dist/`.
Node tests: `TypeScript/package/tests/` (`context.test.mjs`, `ipc.test.mjs`).

Public entry point `src/index.ts` exports:

- **IPC:** `createStdioConnection`, `SDKError`, `SDK_PROTOCOL_VERSION` (= 1),
  `REQUEST_TIMEOUT_MS` (= 60 000); types `HostConnection`, `HostEvent`,
  `HostEventListener`.
- **Context:** `createContext`; type `CreatedContext` (with
  `getCommandHandler(id)` for the runtime adapter).
- **Types:** `SwiftCodeExtension`, `SwiftCodeContext`, `ExtensionInfo`,
  `ProjectAPI`, `ProjectInfo`, `SourceControlAPI`, `RepositoryStatus`,
  `FileChangeSummary`, `FileChangeStatus`, `DiffOptions`, `FileDiff`,
  `RepositoryDiff`, `BuildAPI`, `BuildRequest`, `BuildHandle`,
  `BuildOutputEvent`, `BuildResult`, `BuildDiagnostic`, `BuildStatus`,
  `CommandAPI`, `CommandDefinition`, `EventAPI`, `EventListener`,
  `Disposable`, `DisposableStore`, `Logger`, `SDKErrorShape`.

## The context API (`createContext`)

`createContext(connection, extensionInfo)` returns `{ context,
getCommandHandler }`. The context handed to `activate()` is
`SwiftCodeContext`:

- `extension: ExtensionInfo` — `{ id, name, version }`, resolved by the
  runtime adapter (CLI overrides > manifest > module default export).
- `project.getCurrent(): Promise<ProjectInfo | null>` — currently open
  project (`{ id, name, rootPath, isOpen }`), or `null` when none is open.
  **Not yet served by the host:** the request is sent as
  `project.getCurrent` and the host dispatcher answers with a typed error
  (`IPC_MALFORMED`: "Unknown method") until the method lands in a later host
  phase. It never fabricates a project — a failed request surfaces as an
  `SDKError`.
- `sourceControl.getStatus(): Promise<RepositoryStatus>` — `{ isRepository,
  branchName?, ahead, behind, stagedCount, unstagedCount, untrackedCount,
  files: FileChangeSummary[] }`. When `isRepository` is false, counts are 0
  and `files` is empty; `files` may be host-capped but counts reflect true
  totals.
- `sourceControl.getDiff(options?: DiffOptions): Promise<RepositoryDiff>` —
  `DiffOptions = { maxBytes? (default 262144), includeUntracked? (default
  true), paths? }`; result `{ files: FileDiff[], truncated, totalBytes,
  byteLimit }` — always bounded, with truncation metadata describing exactly
  how much was withheld.
- `build.run(request: BuildRequest): Promise<BuildHandle>` —
  `BuildRequest = { target, configuration?, destination? }`. Resolves to a
  stable `BuildHandle` only after the host service accepts the request.
  The client **rejects blank targets** locally (`INVALID_ARGUMENT`); see the
  known gap below. Host sends `build.output` / `build.finished` events
  correlated to the handle; events arriving before the handle exists are
  stashed and replayed in order, so no output is lost.
- `BuildHandle` — `{ id, output: AsyncIterable<BuildOutputEvent>,
  wait(): Promise<BuildResult>, cancel(): Promise<void> }`.
  `BuildOutputEvent = { kind: "stdout"|"stderr"|"status", text, timestamp }`
  (Unix seconds). `BuildResult = { status:
  "running"|"succeeded"|"failed"|"cancelled"|"timedOut", exitCode?,
  durationSeconds, errorCount, warningCount, diagnostics:
  BuildDiagnostic[], correlationId }`. The terminal state reflects the real
  build service's result — never "succeeded" merely because a process was
  launched. `output` iterators and `wait()` may be consumed concurrently.
- `commands.register(definition: CommandDefinition): Disposable` —
  `{ id, title, execute(payload?) }`. The client validates locally: ID must
  match `^[a-z][a-z0-9-]{0,63}$`, title non-blank and ≤128 chars, no
  duplicate IDs. Registration is synchronous from the extension's view; the
  host request is fire-and-forget (a host rejection lands in the developer
  log). `dispose()` unregisters locally and sends `commands.unregister`
  (best-effort). The host removes all registrations on deactivation.
- `events.subscribe(event, listener): Disposable` — subscribes to
  host→extension events (e.g. `"build.output"`, `"build.finished"`,
  `"shutdown"`).
- `log.debug/info/warn/error(message, fields?)` — fire-and-forget by design:
  sent but never awaited, so logging can never stall an extension.
- `subscriptions: DisposableStore` — `add()` / `disposeAll()`; the runtime
  calls `disposeAll()` on deactivation so nothing leaks.

**There is no `assist` object** on the context, and there never will be in
this release (spec §9).

### Known gap: empty build target

The example's `run-build` command documents an "empty-target convention":
`run({ target: "" })` should ask the host to resolve the default scheme.
The **host** service supports this (`SDKBuildService` resolves a blank target
via `AssistXcodeProjectResolver` — first `xcodebuild -list` scheme, else the
project bundle name). But the **current TS client** rejects blank targets
locally with `INVALID_ARGUMENT` before anything reaches the host, so the
convention does not work end-to-end today. Extensions must pass an explicit,
non-blank target until the client is aligned with the host.

## IPC wire format

One JSON object per line, UTF-8, over stdio. Frames (both sides use
`protocolVersion: 1`):

```
request:  {"protocolVersion":1,"type":"request","requestId":"<uuid>","method":"<m>","payload":{...}}
response: {"protocolVersion":1,"type":"response","requestId":"<same>","ok":true,"payload":{...}}
          or {"ok":false,"error":{"code":"...","message":"...","correlationId":"..."}}
event:    {"protocolVersion":1,"type":"event","requestId":"<uuid>","event":"<name>","payload":{...}}
```

- Requests correlate by `requestId`; the client times out after 60 s
  (`IPC_TIMEOUT`). Malformed inbound frames are ignored with a stderr
  diagnostic and never crash the connection; a `protocolVersion != 1` frame
  rejects with `IPC_PROTOCOL_MISMATCH`.
- The wire error shape is `SDKErrorShape` — `{ code, message,
  correlationId }` only. The host's actionable suggestion stays host-side;
  structured diagnostics stay in the developer log. Both are mapped by
  `correlationId` (`ERR-XXXXXX`).
- Method names supported by the host dispatcher today:
  `sourceControl.getStatus`, `sourceControl.getDiff`, `build.run`,
  `build.wait`, `build.cancel`, `commands.register`, `commands.unregister`,
  `log.debug`, `log.info`, `log.warn`, `log.error`. Unknown methods answer
  `IPC_MALFORMED`; malformed payloads for known methods answer
  `INVALID_ARGUMENT`. Extension→host events: `extension.ready`,
  `extension.error`, `extension.activationFailed`,
  `commands.executeResult`.
- stdout is the IPC channel — extension diagnostics go to **stderr**, never
  stdout.

## The runtime adapter (`TypeScript/runtime-adapter/`)

`src/adapter.ts` is what the Swift host spawns (`SDKNodeLauncher`):

```
node dist/adapter.js --entrypoint <path> [--manifest <swiftcode.json>]
                     [--id <id>] [--version <v>] [--name <n>]
```

It loads the entry point's **default export**, which must be
`{ id, activate, deactivate }` (the `SwiftCodeExtension` contract §12.4) —
anything else is a fatal activation-contract failure (stderr + exit 1, never
a silent hang). Identity precedence: CLI overrides > manifest > module value.

Lifecycle (spec §10.5), all in the adapter:

- `activate(context)` runs; on success it sends `extension.ready`
  `{ extensionId, version, protocolVersion }` and awaits host events.
- `commands.execute` events are dispatched to the registered handler via
  `getCommandHandler`; results report back as `commands.executeResult`
  `{ invocationId, ok, result | error }` (unknown commands get
  `UNKNOWN_COMMAND`).
- One bounded teardown path is shared by `shutdown` events, stdin EOF/close,
  and SIGTERM: `deactivate()` gets a 5 s budget, subscriptions are disposed,
  the connection closes, stdout is flushed, exit 0. The process never hangs.
- Activation failure sends `extension.activationFailed`, runs best-effort
  deactivation, exits 1. `uncaughtException`/`unhandledRejection` are fatal
  (exit 1 after a best-effort `extension.error` event).

## Generator and project layout

`TypeScript/cli/create-extension.mjs` generates a real, compilable extension
from `TypeScript/templates/extension-typescript/`:

```
MyExt/
  swiftcode.json          # placeholders substituted; schema copied from Contracts/Manifest/ into schemas/
  schemas/swiftcode-extension-v1.schema.json
  package.json            # name = last DNS label of id, lowercased; @swiftcode/sdk via file: URL; "test": "node --test"
  tsconfig.json           # ES2022, NodeNext, strict, noUncheckedIndexedAccess, declaration, rootDir src, outDir dist
  src/index.ts            # wires createStdioConnection + createContext + adapter entrypoint shape
  src/extension.ts        # activate/deactivate; registers commands; unwinds partial activation
  src/commands/inspect-repository.ts
  src/commands/run-build.ts   # documents the empty-target convention (see known gap above)
  tests/manifest.test.mjs tests/extension.test.mjs
  README.md  .gitignore
```

The generated manifest requests exactly `source-control.read` +
`build.execute` with the §7.1 reasons, declares the `inspect-repository` /
`run-build` commands, and sets `"assist": {"requested": false}`.

`TypeScript/templates/project-typescript/` is the **standalone** project
template (spec §14): user-owned code with no extension sandbox — `src/index.ts`
hello world plus `tests/hello.test.mjs`. A third, uncommitted template
`SDK/Templates/Standalone-Swift/` (token contract `__APP_NAME__`,
`__BUNDLE_ID__`, `__ORGANIZATION__`) exists in the working tree for the Studio
projects wizard.

## The CLI workflows (`TypeScript/cli/`)

Command modules live in `commands/` and follow `commands/CONTRACT.md` (export
`definition` + `run(args, ctx)`; `UsageError` → exit 2, `Error` → exit 1,
never `process.exit()` inside a module; `--json` keeps stdout parseable).
One runtime dependency: `archiver` (used by `package`).

- **`swiftcode create --type extension --language typescript --id
  <reverse-dns> --name <name> --outDir <dir>`** — shells out to the real
  generator; verifies the output dir is real and non-empty before reporting
  success. `--type project` copies the standalone template instead. Honest
  boundaries (exit 1, not stubs): `--type project --language swift` →
  "created in SwiftCode Studio" (Studio arrives in Phase 7);
  `--type extension --language python` → not supported (spec §3.2).
- **`swiftcode validate [dir]`** — fast local manifest + package check (see
  `Extension-Manifest.md`). Exit 0 prints `valid`; exit 1 lists every problem.
- **`swiftcode dev [dir]`** — local dev loop: resolves the dir (default cwd),
  requires `swiftcode.json` + `package.json` + `tsconfig.json`, runs an
  initial cycle, then watches `src/` (recursive) plus the three config files
  (300 ms debounce). Each cycle, in order: `[compile]` `tsc -p tsconfig.json`,
  `[manifest]`+`[package]` validation, `[tests]` `node --test
  tests/*.test.mjs`. A failed phase stops that cycle but never the watcher.
  **No host attachment in v1** — dev rebuilds, revalidates, and retests; it
  never activates an extension. Run against the live host from SwiftCode
  Studio. SIGINT/SIGTERM shut down cleanly (exit 0).
- **`swiftcode package [dir] [--out <dir>]`** — validates first (any failure
  aborts, no package produced); requires `node_modules/`; builds `dist/` with
  `npx tsc -p tsconfig.json` (`--no-install`, never a silent download) when
  missing; zips `swiftcode.json`, `dist/**`, `schemas/**`, `README.md`,
  `package.json` — never `node_modules/`, `.env` files, `*.tsbuildinfo`, or
  version-control droppings. The archive is deterministic: entries sorted by
  name, fixed mtime (`2000-01-01T00:00:00Z`), fixed mode (0644), fixed deflate
  level. Writes `<id-slug>-<version>.swiftcode-extension` and prints the path
  plus sha256 **only after the archive closes successfully**.
- **`swiftcode install <file.swiftcode-extension> [--update]`** — extracts to
  a private temp dir (zip only; traversal and unsafe-symlink entries
  rejected); validates the staged tree with the canonical `validateExtension`
  **before** touching the controlled directory; computes the canonical digest;
  moves into `<root>/<id>/<version>/` (refuses without `--update` when the
  version exists; `--update` backs up, re-validates the installed tree, and
  rolls back on any failure); writes `.sdk-install.json` atomically, mode
  0600. Nothing is reported as installed until fully verified. The CLI never
  grants capabilities — approval happens in Studio.
- **`swiftcode list [--json]`** — scans the controlled directory the way
  `SDKExtensionRegistry.scan()` does (manifest re-validated, fail closed;
  malformed entries skipped with a stderr warning). Human table: id /
  version / enabled / 12-char digest; `--json` returns full records.
- **`swiftcode enable|disable <id>`** — flips the `enabled` flag in
  `.sdk-install.json`. **Uninstall:** `swiftcode uninstall <id> (--version
  <v> | --all)` — non-interactive by design; removes the version tree and the
  now-empty parent id dir. The CLI removes files only — deactivating a
  running extension (stopping its process, clearing runtime state) is the
  host's job.

## The example extension

`SDK/Examples/RepositoryBuildExtension/` is a real generated extension
(requesting only `source-control.read` + `build.execute`,
`"assist": {"requested": false}`) — npm-installed, compiled, tests passing.
It is the living reference for the template, the context API, and the
`swiftcode validate` / `package` flow.
