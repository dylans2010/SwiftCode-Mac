# swiftcode CLI

Developer CLI for the SwiftCode SDK platform (spec §13). One runtime
dependency (`archiver`, used by `package`) — Node.js 18+ only. Command
modules live in `commands/` and follow the contract in
[`commands/CONTRACT.md`](commands/CONTRACT.md).

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

### build — compile an extension project (tsc / xcodebuild)

```sh
swiftcode build [dir] [--json] [--project <path>] [--scheme <name>]
```

Compiler-like build with live output:

- **TypeScript** (`tsconfig.json` present): runs `tsc -p tsconfig.json`,
  resolved as `<dir>/node_modules/.bin/tsc`, then a PATH `tsc`, then
  `npx --no-install tsc` (never a silent download). No compiler anywhere
  → honest `COMPILER_NOT_FOUND` failure naming every location checked.
- **Swift** (`*.xcodeproj` / `*.xcworkspace` / `Package.swift` / `*.swift`
  sources): runs `xcodebuild` (Release; `--project`/`--scheme` select the
  target, defaulting to the single project and its first scheme). When
  `xcodebuild` is absent the command fails with `XCODEBUILD_UNAVAILABLE`
  instead of faking a build — Swift builds require macOS with Xcode.

Exit 0 when the compiler exits 0; exit 1 carries the real compiler
diagnostic. In `--json` mode the compiler output is captured in
`data.output` so stdout stays parseable.

### package — build and package an extension/app (deterministic)

```sh
swiftcode package [dir] [--out <dir>] [--json]
```

1. Validates first (`validate`); any failure aborts with exit 1 and no
   package is produced.
2. Requires `node_modules/` in the project dir (`npm install` first).
3. Builds `dist/` with the shared TypeScript build (same resolution as
   `swiftcode build`) when it is missing.
4. Stages `swiftcode.json`, `dist/**`, `schemas/**`, `README.md`,
   `package.json` — never `node_modules/`, `.env` files,
   `*.tsbuildinfo`, or version-control droppings.
5. Computes the canonical content digest (SHA-256 over the canonicalized
   staged contents) and embeds it as `swiftcode-digest.json`, so
   `swiftcode install` rejects tampered packages with a typed
   `DIGEST_MISMATCH` error.
6. The archive is deterministic: entries sorted by name, fixed mtime
   (`2000-01-01T00:00:00Z`), fixed mode, fixed compression level —
   packaging the same tree twice yields byte-identical output.
7. Writes `<id-slug>-<version>.swiftcode-extension` to `--out`
   (default `<dir>/dist-package/`), then prints the path, its sha256
   digest, and the content digest — only after the archive closes
   successfully.

Full format specification (fields, digest algorithm + canonicalization
rules, extension vs. app handling, error taxonomy):
`SwiftCode/SDK/Documentation/Package-Format.md`.

### dev — local development loop

```sh
swiftcode dev [dir]
```

`[dir]` defaults to the current directory. Requires `swiftcode.json` +
`package.json` + `tsconfig.json` there, runs an initial cycle, then watches
`src/` (recursively) plus the three config files (300 ms debounce). Each
cycle, in order with timestamped phase labels: `[compile]` (`tsc -p
tsconfig.json` — errors stop the cycle, the watcher stays alive),
`[manifest]` + `[package]` (manifest + package validation, mirroring the
`validate` checks), `[tests]` (`node --test tests/*.test.mjs` when `tests/`
exists). A failed phase stops the rest of that cycle but never the watcher.

No host attachment in v1: dev rebuilds, revalidates, and retests on change —
it never activates an extension. Run against the live host from SwiftCode
Studio. SIGINT/SIGTERM shut down cleanly (exit 0).

### install — install a packaged extension/app (digest-verified)

```sh
swiftcode install <file.swiftcode-extension> [--update] [--json]
```

Installs extensions **and** apps — both use the identical
`.swiftcode-extension` format (the manifest `type` field selects the kind);
both land in the controlled extensions directory
(`~/Library/Application Support/SwiftCode/Extensions/<id>/<version>/`,
or `$SWIFTCODE_EXTENSIONS_DIR`).

Before touching the controlled directory, in order:

1. Extracts to a private temp dir (zip traversal / unsafe symlinks /
   encrypted / zip64 entries rejected).
2. Verifies the embedded `swiftcode-digest.json` integrity record: the
   canonical digest recomputed over the extracted tree must equal the
   embedded `contentDigest`. Any post-packaging modification fails here
   with a typed `DIGEST_MISMATCH` error — never silently.
3. Validates the staged tree with the canonical `validate` checks
   (manifest schema, entrypoint, symlinks) — schema violations fail with
   typed `MANIFEST_INVALID` (full problem list in `--json`
   `data.error.details.problems`).
4. Checks the digest record describes the same id/version/kind as the
   manifest (`DIGEST_IDENTITY_MISMATCH`).

Then: already installed without `--update` → `ALREADY_INSTALLED`;
`--update` backs up, replaces, re-validates the installed tree, and rolls
back on any failure. Writes `.sdk-install.json` (exact host record
fields, atomic, mode 0600). "Installed"/"Updated" plus the requested
capabilities print only after full verification — and the CLI never
grants capabilities; approval happens in SwiftCode Studio.

Typed errors (also as `--json` `data.error.code`): `DIGEST_RECORD_MISSING`,
`DIGEST_RECORD_MALFORMED`, `DIGEST_MISMATCH`, `DIGEST_IDENTITY_MISMATCH`,
`MANIFEST_INVALID`, `MANIFEST_UNREADABLE`, `ARCHIVE_UNREADABLE`,
`ARCHIVE_UNSAFE_ENTRY`, `ALREADY_INSTALLED`. See `Package-Format.md` §7
for the full taxonomy.

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
