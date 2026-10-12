# swiftcode CLI

Developer CLI for the SwiftCode SDK platform (spec §13). Zero runtime
dependencies — Node.js 18+ only. Command modules live in `commands/` and
follow the contract in [`commands/CONTRACT.md`](commands/CONTRACT.md).

## Install / run

```sh
cd SwiftCode/SDK/TypeScript/cli
npm install -g .        # exposes the `swiftcode` binary, or:
node swiftcode.mjs <command> [args]
```

## Usage

```
swiftcode <command> [args] [--json] [--help]
```

Global flags:

- `--json` — machine-readable output. Success prints
  `{"ok":true,"command":"<name>","data":…}`; failure prints
  `{"ok":false,"command":"<name>","error":{"code":"USAGE"|"OPERATIONAL","message":"…"}}`.
  Stdout stays parseable JSON; human logs are suppressed.
- `--help` — global help, or per-command help when placed after a command
  (`swiftcode create --help`).

## Commands

### create — scaffold a new extension or standalone project

```sh
# TypeScript extension (real generator; shells out to create-extension.mjs)
swiftcode create --type extension --language typescript \
  --id com.example.my-ext --name "My Ext" --outDir ./MyExt \
  [--description "..."] [--version 0.1.0]

# Standalone TypeScript project (copies templates/project-typescript/)
swiftcode create --type project --language typescript \
  --name "My Tool" --outDir ./MyTool \
  [--description "..."] [--version 0.1.0]
```

Required: `--type` (`extension`|`project`), and for extensions `--id`
(reverse-DNS) + `--name`; both kinds require `--outDir` (must not exist or
must be empty). `--language` defaults to `typescript`. The created path is
verified to exist and be non-empty before success is reported.

Honest boundaries (exit 1, not stubs):

- `create --type project --language swift` → "Swift standalone projects are
  created in SwiftCode Studio" (Studio arrives in Phase 7).
- `create --type extension --language python` → "not supported in this
  release" (spec §3.2 defers Python extension runtime support).

### validate — validate an extension's manifest and package contents

```sh
swiftcode validate [dir] [--json]
```

`[dir]` defaults to the current directory. Checks that `swiftcode.json`
exists and parses, then runs structural validation mirroring the real
manifest schema
(`SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json`):
required fields, types, length bounds, `manifestVersion === 1`,
reverse-DNS `id`, semver `version`, `runtime.language === "typescript"`,
`sdk.name === "@swiftcode/sdk"`, `sdk.protocolVersion === 1`, capability
ids from the v1 registry (unique), command ids unique and kebab-case, and
`assist.requested` boolean. Package checks (spec §7.2): the
`runtime.entrypoint` is relative with no `..` segments, the entrypoint
file exists under the package root, no symlinks escape the package root,
and no `.env` files or `node_modules` content would be shipped (`.env`
files produce warnings, not errors — the packager excludes them).

Exit 0 prints `valid`; exit 1 lists every problem found (never just the
first). This is the fast local check — the Swift host performs the
authoritative strict validation at install time.

### package — build and package an extension (deterministic)

```sh
swiftcode package [dir] [--out <dir>] [--json]
```

1. Validates first (`validate`); any failure aborts with exit 1 and no
   package is produced.
2. Requires `node_modules/` in the extension dir (`npm install` first).
3. Builds `dist/` with `npx tsc -p tsconfig.json` when it is missing.
4. Zips `swiftcode.json`, `dist/**`, `schemas/**`, `README.md`,
   `package.json` — never `node_modules/`, `.env` files,
   `*.tsbuildinfo`, or version-control droppings.
5. The archive is deterministic: entries sorted by name, fixed mtime
   (`2000-01-01T00:00:00Z`), fixed mode, fixed compression level.
6. Writes `<id-slug>-<version>.swiftcode-extension` to `--out`
   (default `<dir>/dist-package/`), then prints the path and its sha256
   digest — only after the archive closes successfully.

### dev — (not yet implemented)

Local development session (watch, recompile, revalidate, restart). Real
implementation only; no stub shipped.

### install — (implemented; docs pending)

Installs a local package (`swiftcode install <file>`); never prints
"installed" until the host confirms that state (spec §13.2).

## Exit codes

| Code | Meaning                                                  |
| ---- | -------------------------------------------------------- |
| 0    | success                                                  |
| 1    | operational failure (bad input data, generator/build/test/package failure, unsupported-but-recognized option) |
| 2    | usage error (unknown command, missing/invalid arguments) |

`--json` never changes the exit code, only the output format.

## Examples

```sh
swiftcode create --type extension --language typescript \
  --id com.acme.build --name "Build Helper" --outDir ./BuildHelper
# → Extension created at /abs/path/BuildHelper   (exit 0)

swiftcode create --type project --language swift --name X --outDir ./X
# → swiftcode create: error: Swift standalone projects are created in SwiftCode Studio   (exit 1)

swiftcode frobnicate
# → swiftcode: error: unknown command "frobnicate"   (exit 2)

swiftcode create --type extension --language typescript --json --id com.a.b --name B --outDir /tmp/b
# → {"ok":true,"command":"create","data":{"type":"extension","language":"typescript","id":"com.a.b","name":"B","path":"/tmp/b"}}
```

## Writing a new command

See [`commands/CONTRACT.md`](commands/CONTRACT.md): export `definition`
(`name`, `description`, `usage`) and `async run(args, ctx)` from
`commands/<name>.mjs`. Throw `UsageError` (from `../errors.mjs`) for bad
arguments (exit 2); throw `Error` for operational failures (exit 1); never
`process.exit()`.
