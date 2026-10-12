# __EXTENSION_NAME__

A SwiftCode TypeScript extension built with `@swiftcode/sdk`.

- **Capabilities:** `source-control.read`, `build.execute`
- **Commands:** `inspect-repository` (Inspect Repository), `run-build` (Build Current Project)
- **Assist:** not requested and not used (unavailable to extensions).

## Prerequisites

- Node.js 20+
- The SwiftCode host runtime (`swiftcode` CLI) — install/validate and dev
  commands below become available with the CLI phase of the SDK.

## Workflow

```sh
npm install     # install deps; @swiftcode/sdk resolves from the local SDK package
npm run build   # compile src/ → dist/ (must succeed before activation)
npm run typecheck  # strict type check without emitting
npm test        # run the manifest + extension test suites
```

`dist/index.js` is the runtime entrypoint declared in `swiftcode.json`
(`runtime.entrypoint`). The host activates the extension from the built
output — never from `src/` directly.

## Commands (arrive with the CLI phase)

The following scripts are part of the SDK CLI story; they are available
once the `swiftcode` CLI ships:

```sh
npx swiftcode validate   # validate swiftcode.json + package contents against the schema
npx swiftcode dev        # run the extension in development mode against a local host
npx swiftcode package    # package the extension for installation (spec §17)
```

Until the CLI lands, `validate` is covered by `npm test` (the manifest
suite checks capabilities, Assist posture, commands, and the entrypoint
against the shipped schema) and packaging/installation is not yet
implemented — do not invent a package format.

## Manifest

`swiftcode.json` declares the extension identity, capabilities, contributed
commands, and the SDK/protocol versions it was built against. The schema
pointer `$schema` resolves to `schemas/swiftcode-extension-v1.schema.json`,
which the generator copies into every generated project from
`SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json` —
a single source of truth, never a dead URL.

## Build targets

The `run-build` command calls `build.run({ target: "" })` with an empty
target: the host resolves the default scheme/build target of the currently
open SwiftCode project. The extension never hardcodes a target name that
might not exist in the user's project.
