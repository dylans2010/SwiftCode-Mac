# Extension Manifest (`swiftcode.json`)

**Status:** Phase 1 contract, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §7 · **ADR:** `SDK-Architecture.md` §§1, 10

Every SwiftCode extension declares itself in a `swiftcode.json` manifest at the
package root. The manifest is a **request to the host, not an authorization
token**: declaring a capability never grants it — each capability still requires
an explicit user grant via the capability broker (see
`Capabilities-and-Permissions.md`).

## The schema (single source of truth)

The canonical schema is
`SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json`
(JSON Schema draft 2020-12). It is intentionally strict:

- `additionalProperties: false` at the top level and on capability and command
  objects. Forward compatibility is handled by new schema versions
  (`manifestVersion` 2 = a new file), never by silently accepting extra fields.
- Constraints the schema draft cannot express — duplicate capability/command
  IDs, entrypoint file existence, package-level checks — live in the validators
  below, not in the schema.

The `"$schema"` field points at the schema this manifest was authored against.
In a packaged extension it MUST resolve to the schema file shipped **inside the
package** (e.g. `"./schemas/swiftcode-extension-v1.schema.json"`) or a verified
official URL. A relative pointer that escapes the package root or names a
missing file is rejected at install time (CLI) per spec §7.1.

## Field reference (manifestVersion 1)

| Field | Type | Required | Bounds / rules |
|---|---|---|---|
| `manifestVersion` | integer | yes | const `1`. Other values → `MANIFEST_UNSUPPORTED_VERSION` |
| `id` | string | yes | Reverse-DNS, ≤128 chars. Host install validation requires lowercase (`^[a-z0-9]+(\.[a-z0-9-]+)+$`, e.g. `com.example.my-ext`); it becomes the install-directory name and the identity bound to the runtime session |
| `name` | string | yes | Non-blank, ≤128 chars |
| `version` | string | yes | Full semver, ≤32 chars at host validation (schema allows ≤64) |
| `description` | string | no | ≤1000 chars (host semantic limit is 1024) |
| `type` | string | yes | enum `"extension"` / `"app"` — the package kind. Both ship in the identical `.swiftcode-extension` format (same layout, digest, install directory); see `Package-Format.md` §5 |
| `runtime.language` | string | yes | `"typescript"` only — Python is deferred (ADR §12) |
| `runtime.entrypoint` | string | yes | Relative path to the built JS entry file, e.g. `"dist/index.js"`. Must not be absolute, must not contain `..` or empty segments (schema regex + host lexical checks); existence inside the package is checked by the package validator |
| `runtime.minimumSwiftCodeVersion` | string | yes | Semver floor of the host SwiftCode version the extension needs, e.g. `"1.0.0"`. Well-formedness is validated; the actual comparison is covered in `Compatibility.md` |
| `sdk.name` | string | yes | const `"@swiftcode/sdk"` |
| `sdk.versionRange` | string | yes | npm-style range the extension builds against, e.g. `"^1.0.0"`. Host-accepted forms: exact `1.0.0`, `^1.0.0`, `~1.0.0`, or `>=1.0.0 <2.0.0`. Anything else → `INCOMPATIBLE_SDK_VERSION` |
| `sdk.protocolVersion` | integer | yes | const `1`. A different value → `INCOMPATIBLE_SDK_VERSION` at manifest validation and `IPC_PROTOCOL_MISMATCH` on the wire |
| `capabilities[]` | array | yes | 1–32 entries, each `{id, reason}` |
| `capabilities[].id` | string | yes | One of the fixed registry IDs (see below). Unknown IDs → `UNKNOWN_CAPABILITY`, never silently reinterpreted |
| `capabilities[].reason` | string | yes | Non-blank, ≤500 chars — the plain-language justification shown in the grant approval UI |
| `contributes.commands[]` | array | no | 1–64 entries, each `{id, title}`; the only UI contribution model in this release |
| `contributes.commands[].id` | string | yes | `^[a-z0-9-]+$`, ≤64 chars, unique within the manifest |
| `contributes.commands[].title` | string | yes | Non-blank, ≤128 chars |
| `assist.requested` | boolean | no | Defaults to `false` when absent. **Descriptive metadata only** — see below |

## The three validation layers

Validation runs at different points, and they are not identical. From fastest
(local) to authoritative (install time):

1. **CLI `swiftcode validate`** (`TypeScript/cli/commands/validate.mjs`,
   reusable as `validateExtension(dir)`). Mirrors the JSON schema structurally:
   required fields, types, length bounds, `manifestVersion === 1`, reverse-DNS
   `id`, semver `version`, `runtime.language === "typescript"`,
   `sdk.name === "@swiftcode/sdk"`, `sdk.protocolVersion === 1`, capability IDs
   from the v1 registry **and unique** (duplicates rejected here), command IDs
   unique and kebab-case, `assist.requested` boolean. Package checks: entrypoint
   relative with no `..`, entrypoint file exists under the package root, no
   symlink escapes the root, no `.env` files or `node_modules` content shipped
   (`.env` = warning; packager excludes them). Exit 0 prints `valid`; exit 1
   lists **every** problem found. This is the fast local check — a "valid"
   result means the manifest is well-formed, not that the host will accept it.
2. **`SDKManifestValidator`** (Swift, pure — no I/O). Runs at host install
   time. 64 KB size cap first, then JSON parse, manifest-version gate, typed
   decode into `SDKManifest`, then the semantic rules in the table above. Every
   rejection is a typed `SDKError` with a user-safe message and an actionable
   suggestion.
3. **`SDKPackageValidator`** (Swift, filesystem). Runs after the manifest
   validator: `swiftcode.json` must exist at the package root; the entrypoint
   must resolve (through real symlink resolution) to a file inside the
   package; the whole tree is walked — no `node_modules`, no `.env` files, no
   executables (no `.sh`/`.bin`/`.exe`/`.dylib`/`.so`, and no execute-bit
   files), ≤10,000 entries, ≤100 MB total. Any escape → `PATH_TRAVERSAL`.

## Known layer discrepancies (honest, verified against the code)

- The Swift host validator's accepted-capability set does **not** list
  `"assist.invoke"`, while the JSON schema and the CLI validator accept all
  11 IDs. Net behavior is unchanged (Assist is never grantable), but a host
  install-time validation of a manifest declaring `assist.invoke` fails with
  `UNKNOWN_CAPABILITY` — it never reaches the broker's `ASSIST_DENIED` path.
- The schema and CLI allow uppercase letters in extension IDs; the Swift
  host validator requires lowercase-only reverse-DNS. Install-time validation
  is authoritative, so IDs must be lowercase.
- Duplicate capability IDs are rejected by the CLI validator but **not** by
  the Swift manifest validator (the schema comment says the host rejects them;
  the code currently does not). The broker treats a duplicate grant request as
  one capability.
- Unknown top-level fields are rejected by the CLI validator
  (`additionalProperties: false` mirror); Swift's `Codable` decode silently
  ignores them. The authoritative shape contract is the JSON schema.

## Example manifest

The canonical example is
`SwiftCode/SDK/Contracts/Manifest/ExampleManifests/repository-build-extension.swiftcode.json`
(requests only `source-control.read` + `build.execute`, `"assist":
{"requested": false}`):

```json
{
  "$schema": "./schemas/swiftcode-extension-v1.schema.json",
  "manifestVersion": 1,
  "id": "com.example.repository-build-extension",
  "name": "Repository Build Extension",
  "version": "0.1.0",
  "description": "Reads repository status and runs a SwiftCode-managed build.",
  "type": "extension",
  "runtime": {
    "language": "typescript",
    "entrypoint": "dist/index.js",
    "minimumSwiftCodeVersion": "1.0.0"
  },
  "sdk": {
    "name": "@swiftcode/sdk",
    "versionRange": "^1.0.0",
    "protocolVersion": 1
  },
  "capabilities": [
    {"id": "source-control.read", "reason": "Display repository status and diffs."},
    {"id": "build.execute", "reason": "Run builds through SwiftCode's managed build service."}
  ],
  "contributes": {
    "commands": [
      {"id": "inspect-repository", "title": "Inspect Repository"},
      {"id": "run-build", "title": "Build Current Project"}
    ]
  },
  "assist": {"requested": false}
}
```

## The four version fields (and what each one governs)

- **`manifestVersion`** — which manifest schema generation this file follows
  (currently `1`). Unsupported generations are rejected before any field is
  trusted.
- **`sdk.versionRange`** — which `@swiftcode/sdk` package versions the
  extension was built against (e.g. `"^1.0.0"`). Evaluated against the host's
  SDK version; mismatch → `INCOMPATIBLE_SDK_VERSION`.
- **`sdk.protocolVersion`** — which host/runtime IPC wire contract the
  extension speaks (currently `1`). Must equal the host's protocol version
  exactly; wire mismatch → `IPC_PROTOCOL_MISMATCH`.
- **`runtime.minimumSwiftCodeVersion`** — the oldest SwiftCode host version
  the extension requires. Full negotiation rules and the host version facts
  (`SwiftCodeSDK.json`) are in `Compatibility.md`.

## What `"assist": {"requested": ...}` means

It means nothing for authorization. The manifest `assist` block is
**descriptive metadata only** (spec §9.1, ADR §9): `requested: true` declares
interest in a future Assist authorization flow; it does not grant Assist
access. `SDKAssistGate.manifestRequestsAssist(_:)` reads it so the host can
report and explain a refusal with the right context — it never grants
anything. Any actual `assist.invoke` attempt is denied independently by the
capability broker (typed `ASSIST_DENIED` + audit event), and the future Assist
authorization flow is **not implemented** in this release — no dormant bypass
exists. See `Capabilities-and-Permissions.md` and `Runtime-and-Security.md`.
