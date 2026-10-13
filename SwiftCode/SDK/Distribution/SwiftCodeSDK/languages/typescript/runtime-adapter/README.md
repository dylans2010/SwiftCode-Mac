# @swiftcode/runtime-adapter

Node runtime adapter that hosts TypeScript SwiftCode extensions as an
out-of-process runtime (Docs/Intro-to-SDK.md §10 runtime responsibilities,
§12.4 entry point contract).

This is what the Swift host's `SDKNodeLauncher` spawns — one process per
extension:

```sh
node dist/adapter.js --entrypoint <path> [--manifest <swiftcode.json>]
                     [--id <id>] [--version <v>] [--name <n>]
```

It loads the extension's declared entry module, builds a real SDK context
over the stdio NDJSON channel (`createStdioConnection` + `createContext`
from `@swiftcode/sdk`), activates the extension, then dispatches
`commands.execute` host events to the extension's registered command
handlers and reports `commands.executeResult` events back.

## Command line

| Flag           | Required | Description                                                        |
|----------------|----------|--------------------------------------------------------------------|
| `--entrypoint` | yes      | Path (absolute or cwd-relative) to the entry module. Its **default export** must be `{ id, activate, deactivate }` with function-valued `activate`/`deactivate` (§12.4). Anything else → stderr + exit 1 (activation contract failure, never a silent hang). |
| `--manifest`   | no       | Path to `swiftcode.json`. Loaded with `JSON.parse`; on any read/parse failure → stderr + exit 1. Supplies `id`/`name`/`version`. |
| `--id`         | no       | Identity override. Precedence: flag > manifest > module `id`.       |
| `--name`       | no       | Display-name override. Precedence: flag > manifest > module `id`.   |
| `--version`    | no       | Version override. Precedence: flag > manifest > `"0.0.0"`.         |
| `--help`/`-h`  | no       | Prints usage, exits 0.                                             |

Unknown flags or a flag missing its value → stderr + exit 1.

## Protocol

NDJSON over stdio, one JSON object per line, protocol version 1
(`@swiftcode/sdk` `SDK_PROTOCOL_VERSION`). stdout is the IPC channel —
**the adapter never writes diagnostics to stdout**; those go to stderr.

### Extension → host (events, via `connection.sendEvent`)

| Event                     | Payload                                                        | When                                  |
|---------------------------|----------------------------------------------------------------|---------------------------------------|
| `extension.ready`         | `{ extensionId, version, protocolVersion: 1 }`                  | `activate()` resolved.                |
| `extension.activationFailed` | `{ extensionId, message }`                                  | `activate()` threw (best effort), before exit 1. |
| `extension.error`         | `{ extensionId, message, detail }`                              | `uncaughtException` / `unhandledRejection` (best effort), before exit 1. |
| `commands.executeResult`  | `{ invocationId, ok: true, result }` or `{ invocationId, ok: false, error: { code, message, correlationId } }` | Answer to a `commands.execute` dispatch. Unknown command → `code: "UNKNOWN_COMMAND"`. Handler throw → `code: err.code ?? "COMMAND_FAILED"`. |

The extension itself also issues **requests** through the SDK context
(`sourceControl.getStatus`, `build.run`, `log.info`, …); those are answered
by the host's dispatcher with `type: "response"` frames correlated by
`requestId`.

### Host → extension (events the adapter handles)

| Event              | Payload                                          | Behavior |
|--------------------|--------------------------------------------------|----------|
| `commands.execute` | `{ commandId, invocationId, payload }`           | Looks up the handler registered via `context.commands.register`; missing → `commands.executeResult` with `UNKNOWN_COMMAND`. Found → `await handler(payload)`; success → `ok: true` with `result`, throw → `ok: false` with `{ code, message, correlationId }`. |
| `shutdown`         | `{}`                                             | Runs the shared teardown path, then exit 0. |

`build.output` / `build.finished` events are routed internally by the SDK
context to their live build handles (never dropped, even if they arrive
before `build.run` resolves).

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Clean teardown: host `shutdown`, stdin EOF/close, or SIGTERM → best-effort `deactivate()` (5 s budget), subscriptions disposed, connection closed. |
| `1`  | Startup/contract failure (bad argv, unreadable/invalid manifest, unimportable entrypoint, entry-point contract violation), `activate()` threw (after best-effort `deactivation` + `extension.activationFailed`), or `uncaughtException`/`unhandledRejection` (after best-effort `extension.error`). |

Activation failure triggers best-effort deactivation and cleanup per
§10.5. stdout is flushed (bounded, 1 s) before every fatal exit so the
`extension.activationFailed` / `extension.error` event is not truncated.

## How the Swift host launches it

`SDKNodeLauncher` spawns one adapter process per extension with piped
stdio, passing `--entrypoint` (the validated manifest `runtime.entrypoint`
resolved inside the installed package) and `--manifest` (the package's
`swiftcode.json`). The host:

1. Reads NDJSON frames from the child's stdout; routes `type: "event"`
   frames (`extension.ready`, `commands.executeResult`, …) to its
   dispatcher and `type: "request"` frames to the service methods.
2. Sends `commands.execute` events when the user invokes a contributed
   command, and `shutdown` when the extension is stopped.
3. Treats child exit 0 as clean stop; non-zero exit or a signal as a
   runtime crash (§10.5 failure states), marking the extension failed and
   removing its contributions.

The adapter never receives unrestricted internal service objects, raw
secret values, or unrestricted host filesystem access — it only sees the
controlled `SwiftCodeContext` (§10.3).

## Build & verify

```sh
npm install
npm run build    # tsc -p tsconfig.json → dist/adapter.js
npm run typecheck
```

Requires Node ≥ 18 (uses `node:crypto`, `node:url`, `node:fs/promises`).
Developed against Node 24.
