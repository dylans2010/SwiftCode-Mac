# @swiftcode/sdk

The real TypeScript SDK for writing SwiftCode extensions. This package
implements the IPC client and the full developer-facing extension context —
not just the types — over the versioned NDJSON stdio protocol defined in
`Docs/Intro-to-SDK.md` §10.4.

## Install

This package is workspace-local (it is not published to npm). Generated
extensions depend on it via the repository's workspace wiring.

```sh
npm install        # devDependencies: typescript, @types/node
npm run build      # tsc -> dist/
```

## Usage

Minimal extension entry point (`src/index.ts`):

```typescript
import {
  createStdioConnection,
  createContext,
  type SwiftCodeContext,
  type SwiftCodeExtension,
} from "@swiftcode/sdk";

const connection = createStdioConnection(); // process.stdin / process.stdout
const { context } = createContext(connection, {
  id: "com.example.repository-build-extension",
  name: "Repository Build Extension",
  version: "0.1.0",
});

const extension: SwiftCodeExtension = {
  id: "com.example.repository-build-extension",

  async activate(context: SwiftCodeContext): Promise<void> {
    context.commands.register({
      id: "inspect-repository",
      title: "Inspect Repository",
      execute: async () => {
        const status = await context.sourceControl.getStatus();
        context.log.info("Repository status retrieved", {
          isRepository: status.isRepository,
        });
        return status;
      },
    });

    context.commands.register({
      id: "run-build",
      title: "Build Current Project",
      execute: async () => {
        const handle = await context.build.run({ target: "MyApp" });
        for await (const event of handle.output) {
          context.log.info(`[build:${event.kind}] ${event.text}`);
        }
        return await handle.wait();
      },
    });
  },

  async deactivate(): Promise<void> {
    context.subscriptions.disposeAll();
  },
};

export default extension;

// The runtime drives activation; wire it up in your real entry point:
await extension.activate(context);
```

## API surface

- `createStdioConnection(stdin?, stdout?)` — NDJSON IPC connection to the
  SwiftCode host. Requests correlate by `requestId` with a 60 s timeout;
  `ok: false` responses throw `SDKError` (typed `code`/`message`/
  `correlationId`). Malformed inbound frames are ignored with a stderr
  diagnostic and never crash the connection.
- `createContext(connection, extensionInfo)` — builds the real
  `SwiftCodeContext`: `project`, `sourceControl`, `build`, `cloudModel`,
  `terminalSandbox`, `commands`, `events`, `log`, `ui`, `subscriptions`,
  plus `getCommandHandler(id)` for the runtime's `commands.execute`
  dispatch.
- `SDKError` — typed error for host rejections and IPC failures.
- Snippet library — `SNIPPETS`, `searchSnippets(query)`,
  `getSnippet(id)` from `./snippets.js` (see below).

### Method coverage (matches the Swift host dispatcher)

| Context API | IPC method | Payload |
|---|---|---|
| `sourceControl.getStatus()` | `sourceControl.getStatus` | `{}` |
| `sourceControl.getDiff(options?)` | `sourceControl.getDiff` | `{options?}` |
| `build.run(request)` | `build.run` | `{target, configuration?, destination?}` → `{handleId}` |
| `handle.wait()` | `build.wait` | `{handleId}` → `BuildResult` |
| `handle.cancel()` | `build.cancel` | `{handleId}` |
| `commands.register(def)` | `commands.register` | `{id, title}` |
| disposable from `register` | `commands.unregister` | `{commandID}` |
| `cloudModel.complete(request)` | `cloudModel.complete` | `{prompt, history?, systemPrompt?, modelIdentifier?}` → `{response}` |
| `terminalSandbox.run(request)` | `terminalSandbox.run` | `{command, args, workingDirectory?, timeout?}` → `TerminalSandboxResult` |
| `ui.openView(viewId)` | `ui.openView` | `{viewId}` — `viewId` is the view's own capability ID (e.g. `"sandbox.view"`); the host answers with a null payload |
| `log.debug/info/warn/error` | `log.*` | `{message, correlationId?}` (fire-and-forget) |

`project.getCurrent()` is sent as `project.getCurrent`; the current host
dispatcher does not implement it yet, so it rejects with a typed error
until the method lands in a later host phase. It never fabricates a
project.

`BuildHandle.output` is an async iterator fed by `build.output` host
events; it is safe to consume concurrently with `wait()`. Events that
arrive before the handle exists (the host forwards them detached from the
run request) are stashed by the context router and replayed in order.

## Snippet library

`src/snippets.ts` is a preset, searchable library of working TypeScript
snippets against the real SDK API — one snippet per capability that has a
TypeScript context API (16 snippets: virtualization console, database
explorer, cloud model, sandboxed commands, CI workflows, source control,
builds, simulator, live preview, UI builder, SF symbols, docs, dictionary,
device connect, command registration, project metadata). Every snippet's
`code` is a self-contained example that typechecks against the built
package (verified by `tests/snippets.test.mjs`); each snippet's
`capabilityId` is the exact wire ID the extension manifest must request
(`SDKCapabilityID` in
`SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`).

- `searchSnippets(query)` — case-insensitive search across id, title,
  description, capabilityId, tags, and code. A blank query returns every
  snippet.
- `getSnippet(id)` — returns one snippet by id, or `undefined`.

The Studio snippet browser reads the light manifest
`snippets.json` at the package root (`id`, `title`, `description`,
`capabilityId`, `tags` — no code). It is **generated**, not hand-written:

```sh
npm run build            # tsc, then regenerates snippets.json
npm run build:snippets   # regenerate snippets.json from dist/ only
```

The generator is `scripts/build-snippets.mjs`. Regenerate after editing
`src/snippets.ts`; `tests/snippets.test.mjs` fails when the checked-in
`snippets.json` is out of sync.

## Security notes

- Assist is deliberately absent from `SwiftCodeContext` (spec §9). There
  is no way to reach it through this package.
- Command IDs are validated client-side against the host rule
  (`^[a-z][a-z0-9-]{0,63}$`); titles are capped at 128 characters.
- `build.execute` is not a shell: only `target`, `configuration`, and
  `destination` are sent; the host pins `/usr/bin/xcodebuild`.
