# Extensions platform — SwiftCode Extensions v2 onto SwiftCode

> Spec for Wave 11 Slice A (spec + audit). Behaviour and formats only:
> inputs, outputs, invariants, file grammars, key names, wire protocols,
> observed behaviour. No implementation code in this file except the
> public API signatures in §10, which are the contract the implementation
> slice codes against.
>
> Sources read live for this spec (Legacy read-only, main `d51a8f0d`;
> destination read-only, main `a0f64b74`):
> `SwiftCode/Backend/Extensions v2/` (23 files),
> `SwiftCode/SDK/Sources/ExtensionKit/` (5 files),
> `SwiftCode/SDK/Host/ExtensionRegistry/` (3 files) +
> `SwiftCode/SDK/Host/SDKExtensionManager.swift`,
> `SwiftCode/Backend/Assist/Tools/UseExtensionTool.swift`,
> `SwiftCode/Services/ExtensionManager.swift`,
> `SwiftCode/Services/PluginManager.swift`,
> `SwiftCode/Features/AdvancedTools/Views/ExtensionMarketplaceView.swift`,
> `Docs/Extensions-v2.md`, plus supporting reads of
> `SwiftCode/SDK/Contracts/Manifest/SDKManifest.swift`,
> `SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`,
> `SwiftCode/SDK/Runtime/Isolation/SDKNodeLauncher.swift`,
> `SwiftCode/SDK/Runtime/IPC/SDKIPCTransport.swift`,
> `SwiftCode/SDK/Runtime/Lifecycle/SDKRuntimeSession.swift`,
> `SwiftCode/SDK/Host/CapabilityBroker/Grants/SDKGrantStore.swift`,
> `SwiftCode/SDK/Examples/RepositoryBuildExtension/swiftcode.json` and its
> `schemas/swiftcode-extension-v1.schema.json`.
> Destination references: `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Terminal.swift`
> (`use_extension` registration and handler),
> `swiftcode/Sources/SwiftCodeSubprocess/Subprocess.swift`,
> `swiftcode/Sources/SwiftCodeSubprocess/StreamingSubprocess.swift`,
> `swiftcode/Package.swift` (SwiftCodeGitHub target model),
> `swiftcode/Sources/SwiftCodeLanguage/LSPClient.swift`,
> `specs/ide/assist-approval-model.md`.
>
> Evidence levels used in §12: **5** — read verbatim from Legacy source
> in this pass; **4** — consistent across two or more Legacy sources;
> **3** — single Legacy source, no corroboration; **2** — plausible
> inference from source, not directly observed; **1** — unverified,
> needs a Mac check.

## 1. Overview + scope

### 1.1 What the Extensions v2 platform is in Legacy

Legacy ships **three overlapping extension systems** plus one
compatibility adapter. They must not be conflated; the SwiftCode port
takes exactly one of them as its host, and treats the others as
history.

| # | System | Where it lives | Status in Legacy | SwiftCode disposition |
|---|---|---|---|---|
| A | **Extensions v2** (the platform) | `SwiftCode/Backend/Extensions v2/` (23 files) | The live platform: VS Code extensions from Open VSX run out-of-process in Node; native Swift plugins run in-process; Xcode-shaped source-editor commands run against buffers | **Port** as the new `SwiftCodeExtensions` SwiftPM target (§10) |
| B | **SDK extension host** (`swiftcode.json`) | `SwiftCode/SDK/` — `Sources/ExtensionKit/`, `Host/ExtensionRegistry/`, `Host/SDKExtensionManager.swift`, `Contracts/`, `Runtime/` | A second, parallel host for TypeScript extensions built against `@swiftcode/sdk`, with its own manifest, capability registry, grant store, Node launcher, IPC envelope, and crash/quarantine policy | **Adapt, narrowly**: its `swiftcode.json` manifest + validators + package validator are the stricter spec for *native SwiftCode* extensions; its runtime (adapter.js, event envelope) is **not** ported — one host, one wire protocol (§4, §12) |
| C | **Legacy v1 ExtensionManager** (`extension.json`) | `SwiftCode/Services/ExtensionManager.swift` + `SwiftCode/Views/Settings/Extension Management/` (28 demo views) | Pre-v2 system: scans `~/Documents/Extensions/`, seeds 25 built-in view-backed "extensions" whose entry point is a SwiftUI view file name; `downloadExtension` only flips in-memory flags — no network, no host, no execution | **Drop**. Superseded by v2. The 28 demo views are explicitly out of this wave (§11) |
| D | **Legacy PluginManager** (`plugin.json`) | `SwiftCode/Services/PluginManager.swift` | Scans `~/Documents/Plugins/` for `plugin.json` manifests; no execution engine at all (install = file copy, compatibility check is an iOS-version stub) | **Drop** |
| E | **Xcode compatibility adapter** | `SwiftCode/Backend/Extensions v2/XcodeCompatibility/` | Value types modelling XcodeKit's source-editor shapes plus a registry of reusable command logic; XcodeKit binaries explicitly cannot run here | **Port** as part of A (§7.4) |

System A is the only one with a real execution path. Its three
extension kinds are distinct ecosystems, not labels (§3.1):

1. **VS Code extensions** — real `.vsix` packages from Open VSX,
   executed by a genuine out-of-process Node.js host that intercepts
   `require('vscode')` with a shim.
2. **SwiftCode-native plugins** — Swift types conforming to a plugin
   protocol, compiled into the app, running in-process.
3. **Xcode source-editor commands** — reusable command logic written
   against XcodeKit-shaped value types, run against a caller-supplied
   text buffer. XcodeKit extension *binaries* never run here.

### 1.2 What it is in SwiftCode

A new SwiftPM library target **`SwiftCodeExtensions`** (modelled on the
`SwiftCodeGitHub` target added in Wave 10: a plain `.target` with a
`.library` product and a matching `SwiftCodeExtensionsTests` test target;
see §10.6 for the exact `Package.swift` shape). It owns:

- the extension model, identity, state machine, and storage;
- both manifest parsers and both validators (VS Code `package.json`
  and SwiftCode `swiftcode.json`);
- the Open VSX registry client and the VSIX install pipeline;
- the out-of-process Node host (spawned through SwiftCode's existing
  subprocess facilities — **no new process runner**);
- the capability/permission model and grant store;
- the Assist bridge (extension commands become MCP tools) and the
  `use_extension` implementation that replaces the honestly-failing
  handler in `swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Terminal.swift`;
- the editor/workspace bridges, the language-client surface, and the
  Xcode-command adapter.

SwiftCode already has pieces Legacy lacked or duplicated; the port reuses
them instead of porting Legacy's copy (§8):

- `SwiftCodeLanguage.LSPClient` — a real LSP client (Content-Length
  framing, sourcekit-lsp first) — replaces `ExtV2LanguageClient`.
- `SwiftCodeSubprocess.run` / `StreamingSubprocess.lines` — the process
  primitives the host runner must use.
- `SwiftCodeMCP` + `specs/ide/assist-approval-model.md`
  (`commit()` / `call.approve()`) — the single approval gate; no
  second gate is designed here (§5.4).
- `SwiftCodeCompletion` — completion providers; extension completion
  registration consults it rather than owning a parallel registry.

UI placement (per `Docs/Extensions-v2.md` and the task brief):
Extensions belongs on the **editor toolbar beside Assist**, not in the
workspace sidebar. Legacy moved it there in the 2026-10-29 batch for
exactly the reason that matters here: the sidebar column squeezed its
`NavigationSplitView`, and the manager's first-access disk IO froze
the app. The SwiftCode UI is a later slice; this spec only fixes the
placement rule and the async-load rule (`ensureReady()` semantics,
§3.3).

### 1.3 Non-goals of this spec

This spec does not design a remote marketplace beyond Open VSX, does
not design a signed-bundle loader for third-party native code, does
not design webview/terminal/debug contributions, and does not change
SwiftCode's Assist registry, session loop, or provider system. Extension
tools register into the existing MCP tool catalogue only.

## 2. Manifest schema

Legacy has **two manifest formats**. Both are ported, and they are
not interchangeable. The table below is the whole story in one place;
the subsections give the field-level rules.

| | VS Code manifest | SwiftCode manifest |
|---|---|---|
| File | `package.json` at `<install>/extension/package.json` | `swiftcode.json` at package root |
| Parser | `ExtV2ManifestParser` | `ExtensionValidator` (lenient) / `SDKManifestValidator` (strict) — see §2.3 |
| Identity | `publisher` + `name` → id `publisher.name` | `id`, reverse-DNS, e.g. `com.example.my-extension` |
| Version | semver, parsed by `ExtV2Version` (lenient) | semver, strictness differs by validator (§2.3) |
| Entry point | `main` (JS, relative) | `runtime.entrypoint` (default `dist/index.js`) |
| Engine req. | `engines.vscode` | `runtime.minimumSwiftCodeVersion` + `sdk.versionRange` |
| Capabilities | 12 `ExtV2Capability` values, granted at runtime (§5) | 35 SDK capability IDs, each with a `reason` (§5) |
| Contributions | `contributes.commands`, `contributes.views`, `contributes.configuration` | `contributes.commands` only |

### 2.1 VS Code manifest (`package.json`) — as `ExtV2ManifestParser` implements it

Decoding is deliberately tolerant: unknown keys are ignored; every
known key is optional **except the identity triple**. A manifest that
fails validation is reported, never loaded with invented defaults for
its identity.

Required (missing or empty → `ExtV2Error.manifest` with a specific
reason):

- `name`: non-empty string.
- `publisher`: non-empty string.
- `version`: present and parseable by `ExtV2Version` (see §2.1.1).

Optional, with Legacy defaults:

| Key | Type | Default | Notes |
|---|---|---|---|
| `displayName` | string | `name` | Falls back to `name` in the derived metadata. |
| `description` | string | `""` | |
| `engines.vscode` | string | absent → compatibility fails (§2.1.2) | Only the `vscode` key of `engines` is read. |
| `main` | string | absent (no entry point) | Must not be absolute and must not contain a `..` segment, else manifest error. An empty-after-trim `main` is rejected at install time (§6.3). |
| `browser` | string | absent | Accepted but never executed; its only effect is in the compatibility check (§2.1.2). |
| `activationEvents` | `[string]` | `[]` | Parsed and stored; **no activation-event dispatch is implemented** — activation is explicit (UI / Assist / `activate()`), never event-driven. |
| `extensionDependencies` | `[string]` | `[]` | Ids are `publisher.name` strings. |
| `extensionPack` | `[string]` | `[]` | Treated identically to `extensionDependencies`; `allDependencies` = dependencies + pack. |
| `categories` | `[string]` | `[]` | Copied to metadata verbatim. |
| `contributes.commands` | `[{command, title, category?}]` | `[]` | `command` and `title` required by decoding; `category` optional. |
| `contributes.views` | `{ <container>: [{id, name, when?}] }` | `[]` | Views are flattened across containers; the container key is discarded. |
| `contributes.configuration.properties` | `{ <key>: {type?, default?, description?} }` | `{}` | `default` decodes as an arbitrary JSON value. Configuration values are never read back by the host shim (`getConfiguration().get(key, fallback)` always returns `fallback`). |
| anything else | — | ignored | Unknown keys are ignored. |

Derived values:

- `identity.id` = `"<publisher>.<name>"`. Identity parsing splits
  on the **first** `.`; both parts must be non-empty, else nil.
- `metadata.kind` is always `.vscode`; `metadata.engineRequirement`
  = `engines.vscode`.
- `declaredAPIs`: `["commands"]` if any command is contributed,
  plus `["TreeDataProvider"]` if any view is contributed. This list
  is used **only** for the compatibility report — never a claim of
  support.

#### 2.1.1 `ExtV2Version` (semver value object)

- Parses by: trim whitespace, strip a leading `v`, strip everything
  from the first `-` (pre-release/build suffixes are discarded for
  comparison; the original string is kept for display).
- Splits the core on `.`; `major` is required (must parse as `Int`),
  `minor`/`patch` default to `0` when absent or unparseable
  (e.g. `"1.80"` → 1.80.0; `"1.80.x"` → major 1, minor 80, patch 0 —
  the `x` parses as 0 via the `Int(...) ?? 0` fallback).
- Comparison is lexicographic on (major, minor, patch).
- `satisfies(engineRequirement:)` accepts: `"*"`, `"x"`, or empty →
  true; `">=1.80.0"` → host >= floor; `"^1.80.0"` → same major **and**
  host >= base (note: Legacy caret is same-major, not npm's `0.x`
  caret rule); `"1.80.x"` / `"1.80.*"` → major equal and, when a
  minor is given, minor equal; anything else → exact equality.
  Anything unparseable is a failure, never a silent pass.

#### 2.1.2 Compatibility evaluation (`ExtV2Compatibility.evaluate`)

Pure function, manifest in → report out. Report fields:
`compatible: Bool`, `reasons: [String]`,
`engineRequirement: String?`, `unsupportedAPIs: [String]`.

Rules, in order:

1. If `engines.vscode` is present and the host engine version
   (**1.85.0**, `ExtV2VSCodeAPI.hostEngineVersion`) does not satisfy
   it → reason `"Requires VS Code engine <req>; SwiftCode's host
   supports 1.85.0."` and `compatible = false`.
2. If `engines.vscode` is **absent** → reason `"Manifest declares no
   engines.vscode requirement, so compatibility cannot be verified."`
   and `compatible = false`. A manifest with no engine requirement
   is always incompatible.
3. If `main` is nil **and** `browser` is nil **and** the manifest
   contributes commands or views → reason `"No main entry point;
   only declarative contributions can run."` and `compatible =
   false`. (Observed quirk: a manifest with commands but no entry
   point is incompatible; a purely declarative manifest — grammars,
   snippets, themes, no commands/views — gets no reason here and can
   be compatible.)
4. For each `declaredAPIs` entry whose matrix level (§9.1) is
   `.unsupported` → collected into `unsupportedAPIs` and one reason
   `"Uses unsupported APIs: <list>."`.

`compatible` is true only when `reasons` is empty.

### 2.2 SwiftCode manifest (`swiftcode.json`) — the v1 schema

Field table (defaults are the `ExtensionManifest` / `SDKManifest`
initialiser defaults; the JSON schema file and the strict validator
disagree on a few points — see §2.3):

```json
{
  "$schema": "./schemas/swiftcode-extension-v1.schema.json",
  "manifestVersion": 1,
  "id": "com.example.my-extension",
  "name": "My Extension",
  "version": "0.1.0",
  "description": "Plain-language description.",
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
    { "id": "workspace.read", "reason": "Read workspace files." }
  ],
  "contributes": {
    "commands": [{ "id": "run-build", "title": "Build Current Project" }]
  },
  "assist": { "requested": false }
}
```

| Key | Required? | Type / default | Rule |
|---|---|---|---|
| `manifestVersion` | yes | integer, must be `1` | Absent → schema failure in the strict validator; the lenient `ExtensionValidator` reports "Unsupported manifestVersion" as an error diagnostic. |
| `id` | yes | string | Reverse-DNS identifier; see §2.3 for the strictness split. |
| `name` | yes | string, non-blank | Max 128 chars (strict validator). |
| `version` | yes | string, semver | Strictness differs by validator (§2.3). Max 32 chars (strict). |
| `description` | no | string, max 1024 chars (strict); schema max 1000 | |
| `type` | yes (strict diagnostics list it as required; decode requires it) | `"extension"` (default) | Strict validator accepts `"extension"` or `"application"`; anything else is an error. `"app"` in the JSON schema is a documentation alias for `"application"`. |
| `runtime.language` | yes | `"typescript"` only | Any other value is an error in both validators. Python is deferred, not supported. |
| `runtime.entrypoint` | yes | default `"dist/index.js"` | Relative path inside the package; absolute or `..` → error; empty segments → error (strict); max 512 chars (strict) / 256 (schema). Must resolve to a real file (package validator, §6.3). |
| `runtime.minimumSwiftCodeVersion` | yes | semver, default `"1.0.0"` | Must be valid semver (strict). |
| `sdk.name` | yes | must be `"@swiftcode/sdk"` | Anything else → incompatible-SDK error. |
| `sdk.versionRange` | yes | semver range, default `"^1.0.0"` (`SDKManifestSDKRef` default is `"1.2.0"`) | Must admit the host SDK 1.x line. Accepted forms (strict validator): exact `1.0.0` / `1.1.0` / `1.2.0`, `^1.x.0`, `~1.x.0`, `>=1.x.0 <2.0.0`. Host SDK version is **1.2.0**. |
| `sdk.protocolVersion` | yes | integer, must be `1` | Host/runtime IPC contract version. |
| `capabilities` | yes (strict diagnostics list it as required; may be empty in the lenient validator) | array of `{id, reason}` | Max 32 entries. Each `id` must be a known capability (§5.2); duplicates rejected (strict). `reason` non-empty (strict: error when blank; lenient: warning when shorter than 8 chars); max 512 chars (strict) / 500 (schema). The JSON schema additionally requires `minItems: 1`. |
| `contributes.commands` | no | array of `{id, title}` | Max 64 commands. Command `id`: lowercase kebab-case starting with a letter, max 64 chars (strict pattern `^[a-z][a-z0-9.-]{0,63}$`); `title` non-blank, max 128 chars. Duplicates rejected (strict). |
| `assist.requested` | no | bool, default `false` | **Descriptive metadata only.** `requested: true` does NOT grant Assist access; denial is enforced at the capability broker, never here. |
| unknown top-level keys | — | preserved by `SDKManifest` in `unknownFields` | The strict validator decodes them into `unknownFields` so visual editing never destroys them; the JSON schema sets `additionalProperties: false` at the top level (see §2.3 disagreement). |

Worked example: `SwiftCode/SDK/Examples/RepositoryBuildExtension/swiftcode.json`
(`com.example.repository-build-extension`, 6 capabilities,
7 commands) is the canonical valid v1 manifest.

### 2.3 Validator disagreements — read them before coding either validator

There are **two** `swiftcode.json` validators, and they disagree.
The SwiftCode port must implement the **strict** one
(`SDKManifestValidator`) as the install-time gate and keep the
lenient one (`ExtensionValidator`) only as the documented behaviour
of the SDK-side `extension-validator` executable concept, if at all.
Do not merge them silently; the table is the decision record.

| Rule | `ExtensionValidator` (lenient, `SDK/Sources/ExtensionKit/`) | `SDKManifestValidator` (strict, `SDK/Host/ExtensionRegistry/`) | SwiftCode decision |
|---|---|---|---|
| Manifest size cap | none | 64 KiB (`maxManifestBytes`); over → `resourceLimitExceeded` | Strict. |
| Missing `manifestVersion` | error diagnostic "Unsupported manifestVersion" (only when present and != 1; absent is **not** flagged — the field decodes with default 1) | schema failure: missing → error; non-integer → error; != 1 → `manifestUnsupportedVersion` | Strict. |
| `id` shape | error only if empty or contains a space | must match `^[a-z0-9]+(\.[a-z0-9-]+)+$` (lowercase reverse-DNS), max 128 chars | Strict. |
| `version` shape | error unless exactly 3 dot-separated numeric parts (`"1.0"` fails; `"1.0.0-beta"` fails because `Int("0-beta")` is nil) | `^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$` — prerelease suffix allowed; max 32 chars | Strict (prerelease allowed). |
| `type` | not checked | must be `"extension"` or `"application"` | Strict. |
| `runtime.language` | not checked (only entrypoint) | must be `"typescript"` | Strict. |
| `runtime.entrypoint` | error if absolute or contains `..`; warning (not error) if the file does not exist on disk when a package root is given | blank → error; > 512 chars → error; absolute → `pathTraversal`; `..` segment → `pathTraversal`; empty segment → error | Strict. |
| `sdk.versionRange` | not checked (only `protocolVersion != 1`) | whitelist: exact/`^`/`~` 1.0.0–1.2.0 or `>=1.x.0 <2.0.0`; host SDK is 1.2.0 | Strict. |
| Capability id | error if not in `ExtensionCapabilityID` (35 ids, §5.2) | error if not in `supportedCapabilities` = `SDKCapabilityRegistry.all` (35 ids) ∪ `ScopesIDLists.all` (6 `use.Security.*` method scopes) | Strict (41 ids). |
| Capability reason | **warning** if shorter than 8 chars | **error** if blank; error if longer than 512 chars | Strict. |
| Duplicate capability / command ids | not checked | error | Strict. |
| Command id pattern | not checked | `^[a-z][a-z0-9.-]{0,63}$` (lowercase, starts with a letter, dots allowed) | Strict. Note the JSON schema says `^[a-z0-9-]+$` (no dots, no leading-letter rule) — the schema and the strict validator disagree; the validator governs. |
| `description` max length | not checked | 1024 chars | Strict. (Schema says 1000.) |
| `entrypoint` max length | not checked | 512 chars | Strict. (Schema says 256.) |
| `capabilities` max count | not checked | 32 | Strict. (Schema agrees: `maxItems: 32`.) |
| `commands` max count | not checked | 64 | Strict. (Schema agrees: `maxItems: 64`.) |
| Unknown top-level keys | N/A (decode fails on type mismatch; unknown keys ignored by `JSONDecoder` by default) | preserved in `unknownFields` | Strict. (Schema says `additionalProperties: false` — the schema and the validator disagree; the validator governs.) |
| Missing required keys | `validateFile` returns `manifestNotFound` when the file is absent; field absence is handled by decode defaults, not errors | `validateWithDiagnostics` lists missing keys (`manifestVersion`, `id`, `name`, `version`, `type`, `runtime`, `sdk`, `capabilities`) as errors | Strict. |
| Diagnostic shape | `[Diagnostic]` from `DiagnosticsKit` (`code`, `severity`, `message`, `remediation`, optional `location`) | `validate(data:)` throws `SDKError`; `validateWithDiagnostics(data:projectRoot:grantedCapabilities:)` returns `[SDKManifestDiagnostic]` (`severity`, `field`, `message`, `suggestion`, `line?`) with line numbers located by text search | Port the strict diagnostic shape; `Diagnostic` (DiagnosticsKit) is not ported. |
| `validateWithDiagnostics` extra checks | — | also checks entrypoint file existence against `projectRoot` and capability authorisation against `grantedCapabilities` when supplied | Port as specified; the `grantedCapabilities` check is diagnostic-only, never a grant. |

Also note: `ExtensionManifest` (ExtensionKit) and `SDKManifest`
(Contracts) describe the same file with different defaults
(`sdk.versionRange` `"^1.0.0"` vs `"1.2.0"`; `type` default
`"extension"` in both; `assist` default `requested: false` in both).
The SwiftCode model uses one struct with the strict validator's
expectations and the `"^1.0.0"` range default (the documented
authoring default).

### 2.4 Package format — which file is which

- **VS Code extension**: a `.vsix` file — a ZIP archive whose payload
  lives under `extension/` (so the manifest is at
  `extension/package.json` inside the archive). See §6.3 for the
  full install validation.
- **SwiftCode extension**: a `.swiftcode-extension` file — a ZIP
  archive produced by `ExtensionPackager.package` with
  `/usr/bin/zip -r -q -9 <id>-<version>.swiftcode-extension
  swiftcode.json package.json dist README.md` (fallback when that
  fails: zip `.` excluding `*.git*` and `*node_modules*`), plus a
  SHA-256 hex digest and file count in `ExtensionPackageInfo`.
  **Caution**: the packager's `fileCount` is hardcoded to `1`
  regardless of archive contents (observed in source) — do not trust
  it; count entries from the archive. The `.swiftcode-extension`
  format is specified here for completeness; the SwiftCode install path
  in this wave is the VSIX path (§6.3), and a
  `.swiftcode-extension` install path is a later slice.
- **Legacy v1**: `extension.json` (Services `ExtensionManager`) and
  `plugin.json` (PluginManager) — dropped, §1.1.

## 3. Extension model + lifecycle

### 3.1 Identity

- **VS Code / v2 identity**: `ExtV2Identity(publisher, name)`,
  string form `"<publisher>.<name>"`. It is the lookup key everywhere
  (UI, storage, host, Assist); display names are never keys. Parsing
  splits on the **first** `.`; both parts must be non-empty.
- **SwiftCode identity**: reverse-DNS `id` (e.g.
  `com.example.my-extension`), used as the install-directory name.
- **Native plugin identity**: a plugin's manifest `id` (e.g.
  `sample.workspace-lister`) is namespaced to
  `"swiftcode.<id>"` when it appears as an installed-extension record
  (e.g. `swiftcode.sample.workspace-lister`).
- **Assist tool identity**: `extv2.<extension-id>.<command>` with
  every character that is not a letter, digit, or `.` replaced by
  `_` (§7.1).

### 3.2 States

`ExtV2State` (v2 platform; the authoritative lifecycle enum):

| State | Meaning | How an extension gets there |
|---|---|---|
| `notInstalled` | No record | Default / after uninstall. |
| `installed` | Record exists, not yet evaluated | Initial record state at install (`ExtV2InstalledExtension` defaults to `.installed`). |
| `disabled` | Record exists, `isEnabled == false` | `setEnabled(false)`; also the stored state when disabled. |
| `enabled` | Installed, enabled, compatible, deps satisfied, not running | `refreshInstalled()` evaluation (§3.3). |
| `incompatible` | Installed but compatibility report failed | `refreshInstalled()` re-evaluates the installed manifest on every refresh; install also records it. |
| `missingDependencies` | A declared dependency is not installed or not enabled | `refreshInstalled()` via `ExtV2DependencyResolver.missingDependencies`. |
| `activationFailed` | Declared but never set by any code path observed | **UNVERIFIED** — no assignment to `.activationFailed` was found in the v2 files read; activation failures surface as thrown errors and a `.crashed`/stopped host instead. Do not invent transitions into it. |
| `running` | Host process alive | `hostManager.isRunning` is true during `refreshInstalled()`; `activate()` sets it after a successful activation. |
| `crashed` | Host process exited unexpectedly | The state name exists; the manager does **not** write `.crashed` into the installed record on host exit (the host is removed from the running map and the diagnostics service logs the crash; the next `refreshInstalled()` re-derives state from disk/manifest, which will typically yield `.enabled`). The SDK host instead quarantines (§3.4). |
| `unavailable` | Installed directory is missing on disk | `refreshInstalled()` when `installPath` does not exist. |

The SDK host has its own, richer state machine
(`SDKRuntimeState`: `discovered → validated → awaitingPermission →
ready → starting → active → stopping → stopped`, plus failure states
`failedValidation`, `failedVersion`, `permissionDenied`,
`launchFailed`, `activationFailed`, `crashed`, `timedOut`,
`terminated`). The SwiftCode port uses the v2 `ExtV2State` enum as the
user-visible state and the SDK machine only as a reference for the
host lifecycle inside §10; it does not port both state machines as
user-visible states.

### 3.3 Lifecycle (v2 manager) — the authoritative sequence

`ExtV2Manager` is `@MainActor`, a singleton, the single lifecycle
owner. Invariants:

- Exactly one manager, one installed-records file, one host manager.
  Views never keep their own copy of install state; after every
  mutation they re-read from the manager.
- `init` does **no IO** (no directory creation, no manifest parsing)
  so opening Extensions cannot freeze the app. `ensureReady()` does
  the disk work (create directories, clean stale staging, off the
  main actor) and then `refreshInstalled()`; calls after the first
  load are no-ops; `isReady` flips only after the first load.
- A broken extension can never prevent launch: `refreshInstalled()`
  tolerates missing directories and malformed records by marking
  them `.unavailable` instead of throwing.

`refreshInstalled()` evaluation order per record (first match wins):

1. Install directory missing → `.unavailable`,
   `lastError = "Installed directory is missing."`.
2. `isEnabled == false` → `.disabled`.
3. Any declared dependency missing or disabled →
   `.missingDependencies`, `lastError = "Missing dependencies: …"`.
4. Host running → `.running`.
5. Re-parse `<install>/extension/package.json`; compatibility report
   decides `.enabled` vs `.incompatible` (with `lastError` = joined
   reasons). **If the manifest cannot be parsed, the record is
   `.enabled`** (lenient fallback — observed; do not "fix" it
   silently in the port without recording a deviation).
6. Records are published sorted by `metadata.displayName`.

Operations:

- **install(metadata)** — resolve download URL → download VSIX to
  `staging/<id>-<UUID>.vsix` → `packageService.install` (atomic,
  §6.3) → record with `isEnabled: true`,
  `capabilities: []` (note: install does **not** populate
  capabilities from the manifest; grants are requested at runtime),
  state from the compatibility report → `refreshInstalled()`.
  Concurrent install of the same id is a no-op (guarded by
  `installingIDs`). Cancellation deletes the downloaded file and any
  staging dir; the previous installation is never touched on failure.
- **uninstall(id)** — deactivate host → remove contributions → revoke
  all grants → `packageService.uninstall` (removes install dir and
  backup; idempotent) → remove record → persist.
- **setEnabled(id, enabled)** — disabling deactivates the host first;
  then persist + `refreshInstalled()`. Enabling does not auto-activate.
- **activate(id)** — guards, in order: installed, enabled,
  not-incompatible; then by kind (§7). VS Code: host activation,
  contribution stored, state `.running`, Assist commands registered.
  Native: contribution from the native registry. Xcode-command:
  returns a synthetic contribution listing **all** registered Xcode
  command identifiers (not per-extension) plus the note
  `"Xcode-compatible commands run against a source buffer; see the
  Xcode Compatibility section."`.
- **deactivate(id)** — host deactivate + contributions removed +
  `refreshInstalled()`.
- **executeCommand(id, command, args)** — native handlers first; else
  ownership check (`hostManager.ownerOfCommand` — a command belonging
  to another extension is rejected); else host execution. Returns the
  result's string value or `""`.
- **checkUpdates()** — VS Code-kind records only; compares registry
  `details()` version against the installed version with `ExtV2Version`
  ordering; failures are warnings per extension, never fatal.
- **search(query)** — debounced via task cancellation (a superseded
  keystroke is not an error); empty query clears results; paginated
  with `loadMoreSearchResults()` (offset accumulates).
- **registerSamplePlugin()** — registers `ExtV2SamplePlugin` and
  upserts an installed record with `installPath: ""`,
  `state: .enabled`, capabilities from the manifest.

### 3.4 SDK host lifecycle (reference — not ported as a second manager)

`SDKExtensionManager` (actor, singleton) discovers packages by
scanning its root, validates each manifest, and launches enabled,
valid, non-quarantined extensions via `startAll()` (returns
`SDKExtensionLaunchSummary{started, skipped[(id, reason)],
failed[(id, reason)]}` — invalid packages are **returned** with a
validation error, never silently dropped).

- **Tamper check**: on launch, the package SHA-256 digest is compared
  with the digest recorded in `.host-state.json`. A mismatch revokes
  **all** capability grants for that extension and quarantines it
  (stays stopped until the user re-enables it, which clears the
  quarantine and resets the crash budget). If revocation itself
  fails, the error is recorded and grants are treated as untrusted
  until reinstall — never claimed as revoked.
- **Crash policy**: `maxCrashRestarts = 3`. On unexpected exit, the
  handle is removed, contributions unregistered, and the extension is
  relaunched after exponential backoff 2s, 4s, 8s … capped at 30s
  (re-checking enabled/quarantined before relaunch). At the budget,
  it is quarantined with reason `"It crashed <n> times and was
  quarantined to protect stability. Last exit code: <code>."`.
- **Stop budget**: deactivation is raced against a 10s stop timeout;
  the process is then terminated.
- **Session states**: `discovered → validated → awaitingPermission →
  ready → starting → active`, with `awaitingPermission` entered
  explicitly — v1 has no launch-time consent gate beyond the enabled
  toggle and per-capability approval; the extension runs with **no
  granted capabilities** until the user approves each one.
- **Uninstall**: removes the install record, revokes every grant,
  wipes security values, revokes Assist entitlements, closes Assist
  sessions. (Assist entitlements/sessions are SDK-host concepts;
  the SwiftCode equivalent is unregistering the extension's MCP tools.)

The SwiftCode port takes the **v2 crash policy** (stop after 3
consecutive crashes, manual retry, no restart loop) as the user-facing
rule, and records the SDK's restart-with-backoff + quarantine as a
deviation (§12). It does **not** port both policies.

### 3.5 Storage locations (exact paths)

All paths are relative to the user's home / Application Support
unless stated. These are three different roots in Legacy — the SwiftCode
port unifies on the v2 root (§12).

**v2 platform root** —
`~/Library/Application Support/SwiftCode/ExtensionsV2/`:

| Path | Content |
|---|---|
| `installed.json` | `[ExtV2InstalledExtension]` — the manager's source of truth. Atomic writes (temp file + replace). |
| `grants.json` | `{ "<extension-id>": ["<capability>", …] }` — permission grants (§5). Atomic writes. |
| `settings.json` | `Settings{registryBaseURL, autoUpdate, nodeExecutablePath?, allowPrerelease}`. Defaults: registry `https://open-vsx.org/api`, `autoUpdate: false`, `allowPrerelease: false`. |
| `diagnostics.jsonl` | Append-only JSONL diagnostic entries (§4.5). |
| `staging/` | In-progress installs; never a final location; cleaned at launch (`cleanStaleStaging` removes all entries). |
| `extensions/<publisher.name>/` | One extracted VSIX per installed extension; the committed tree is the whole extracted archive, so the manifest lives at `extensions/<id>/extension/package.json`. |
| `backups/<id>.backup` | Previous version, kept until an update commits; removed on uninstall. |
| `host/extension-host.js` | The embedded Node host script, written (and refreshed when it changes) by `ExtV2HostScript.ensureHostScript`. |

**SDK host roots** (reference only — **not** the SwiftCode layout):

| Path | Content |
|---|---|
| `~/.swiftcode/extensions/<id>/` | `SDKExtensionManager` root: one directory per extension id, `swiftcode.json` at its root, host state in `<root>/.host-state.json` (`{enabled, recordedDigest?, quarantined, quarantineReason?}` per id). |
| `~/Library/Application Support/SwiftCode/Extensions/<id>/<version>/` | `SDKExtensionRegistry` root: versioned install dirs, each with `swiftcode.json` + `.sdk-install.json` (`{id, version, packageDigest, installPath, installedAt, updatedAt, enabled}`). |
| `~/Library/Application Support/SwiftCode/SDKGrants.json` | `SDKGrantStore` — grants persisted as JSON, file mode `0600`; corrupt files are moved aside to `<name>.corrupt-<timestamp>` rather than deleted. |

**Legacy v1 roots** (dropped): `~/Documents/Extensions/<id>/extension.json`
and `~/Documents/Plugins/<id>/plugin.json`; enabled state in
UserDefaults keys `com.swiftcode.extensions.enabled` /
`com.swiftcode.plugins.enabled` (default enabled = true).

**Workspace state**: the v2 manager holds a `workspaceRoot: URL?`
set by the caller (`setWorkspaceRoot`); the workspace bridge is
derived from it and is nil when no workspace is open. Grants,
installs, and settings are **not** per-workspace; they are global to
the user.

## 4. Host runtime

### 4.1 Process model

- **One Node process per VS Code extension.** The process is
  disposable: a crash marks the extension stopped/failed and fails
  pending requests; after `maxConsecutiveHostCrashes = 3` consecutive
  crashes the host is left stopped until the user explicitly retries
  — no restart loops.
- Spawn (v2): `node <root>/host/extension-host.js --extension-entry
  <install>/extension/<main>`, stdin/stdout as NDJSON pipes,
  stderr to the null device. Environment = the host process
  environment **minus** keys starting with `SWIFTCODE_` or `HERMES_`.
  (The SDK launcher instead strips secret-bearing variables by a
  different list and resolves Node via `SWIFTCODE_NODE_PATH` → the
  three well-known paths → `PATH` lookup; see §4.2.)
- All host-manager state is `@MainActor`-isolated in Legacy; the
  reading task hops back to the main actor for every line. The SwiftCode
  port must preserve the invariant that at most one host runs per
  extension id and that a second `activate()` returns the existing
  contribution.
- The implementation must reuse SwiftCode's existing subprocess
  primitives (`SwiftCodeSubprocess`, `StreamingSubprocess`) for spawning
  and line reading — **no new process runner**. Legacy's raw
  `Process` + `Pipe` + `bytes.lines` pattern is the behaviour to
  reproduce, not the code to copy.

### 4.2 Node.js discovery and the absent-Node rule

v2 discovery order (`ExtV2HostManager.nodeExecutable`):

1. `settings.nodeExecutablePath`, when non-empty and executable.
2. `/opt/homebrew/bin/node`
3. `/usr/local/bin/node`
4. `/usr/bin/node`

If none resolves, activation throws
`ExtV2Error.host("Node.js is required to run VS Code extensions and
was not found. Install Node.js or set its path in Extensions >
Settings.")`. There is no fallback, no bundled Node, no silent
no-op. **Node.js is a hard requirement for VS Code extensions.**
Native plugins and Xcode commands do not need Node.

The SDK launcher (`SDKNodeLauncher`) differs: it requires **Node.js
20 or later**, resolves via `SWIFTCODE_NODE_PATH` env override →
well-known paths → each `PATH` component + `/node`, and fails with a
typed `.runtimeUnavailable` error. The SwiftCode port adopts the v2
discovery order (settings path first, then the three well-known
paths) and additionally honours `PATH` lookup as a fallback, and
states the Node 20+ requirement in the activation error text.

### 4.3 Wire protocol — NDJSON JSON-RPC v1

One JSON object per line, both directions, UTF-8, `\n` terminated.
Every message carries `jsonrpc: "2.0"` and `protocolVersion: 1`.

**SwiftCode → host (requests)** — `ExtV2RPCRequest{id, method,
params?}`:

```json
{"jsonrpc": "2.0", "protocolVersion": 1, "id": "<extensionId>:<n>",
 "method": "activate",
 "params": {"extensionId": "<id>", "workspaceRoot": "<path or empty string>"}}
```

Methods SwiftCode sends (`allowedSwiftCodeMethods`):
`activate`, `deactivate`, `executeCommand`, `shutdown`,
`didChangeTextDocument`, `didChangeConfiguration`.

- `activate` params: `{"extensionId", "workspaceRoot"}`.
- `executeCommand` params: `{"command", "args": [...]}`.
- `shutdown` params: absent (request id is the literal `"shutdown"`).
- `didChangeTextDocument` / `didChangeConfiguration` are in the
  allowlist but **no sender was found** in the v2 files read —
  treat them as reserved, not implemented.
- Request ids are `"<extensionId>:<n>"` with a monotonically
  increasing `n` per host manager.

**Host → SwiftCode** — either a response
`{"jsonrpc": "2.0", "id": "…", "result": …}` / `{"…", "error":
{"code": -32000, "message": "…"}}`, or a host-initiated request with
the same request shape and one of the host methods.

Methods the host may send (`allowedHostMethods`, 20):
`host.log`, `host.showMessage`, `host.registerCommand`,
`host.registerTreeData`, `host.setStatusBar`, `host.appendOutput`,
`host.readFile`, `host.writeFile`, `host.applyEdit`,
`host.registerCompletionProvider`, `host.registerHoverProvider`,
`host.registerDefinitionProvider`, `host.registerReferenceProvider`,
`host.registerFormattingProvider`, `host.registerCodeActionProvider`,
`host.publishDiagnostics`, `host.requestPermission`,
`host.getConfiguration`, `host.showQuickPick`, `host.showInputBox`.

**Validation** (`ExtV2RPC.decodeRequest`): a line over
`maxIPCMessageBytes` (1 MiB) is rejected; a `protocolVersion != 1`
is rejected; a method outside the direction's allowlist is rejected.
All three are host faults, logged via diagnostics — never leniently
accepted. Oversize is checked on the raw line byte count.

**Host-initiated request handling** (`ExtV2Manager.handleHostRequest`):
`host.log` → diagnostics; `host.readFile` / `host.writeFile` →
workspace bridge (capability-gated; no workspace open → invalid
request); `host.applyEdit` → read current disk content, parse
`{path, edits: [{range: {start: {line, character}, end: {...}},
newText}]}`, apply via the editor bridge, write back, return `true`;
`host.publishDiagnostics` → provider registry (malformed entries
without a `message` are dropped); `host.registerCompletionProvider` /
`host.registerHoverProvider` → provider registry by language;
`host.requestPermission` → permission manager prompt, returns bool;
`host.showQuickPick` / `host.showInputBox` → **return null** (no
picker UI is attached on the host path; null is an honest "no
selection", logged); every other allowed method → null (accepted,
no action). Unknown-but-allowed methods that need no action return
null rather than an error.

**Recorded wire-protocol disagreement (§12, D-9):** the embedded
host script's `workspace.applyEdit` sends
`{edit: <plain object>}` with no `path` and no `edits` array, while
the Swift handler requires `{path, edits: [...]}`. As written, the
shim's `applyEdit` can never succeed through the Swift handler — it
fails with "Invalid applyEdit request." The port must pick one shape
(the Swift handler's `{path, edits}` shape) and make the shim send
it; the disagreement must not be silently carried over.

**Timeouts**: activation 30s, single command 60s, host-initiated
request answered by the host 30s (hardcoded in the host script),
registry 30s (resource 60s), language-server request 30s. A timeout
fails the pending request with `ExtV2Error.timeout`; the host is
**not** killed on a single timeout (only shut down on activation
failure).

**Shutdown**: best-effort `shutdown` request on stdin, then
`process.terminate()`; never wait on the UI thread for a
misbehaving host. Pending continuations for that extension are
resumed with "Extension host shut down." / "Extension host exited
unexpectedly."

**Crash handling**: process termination (or stdout EOF / read error)
→ host removed from the running map, provider registrations cleared,
pending continuations failed, `consecutiveCrashes[id] += 1`,
diagnostics error logged. Activation is refused while
`consecutiveCrashes >= 3` with the message "Extension host for
'<id>' stopped after repeated crashes. Retry it manually from the
extension's details." A successful activation resets the counter to
0. **UNVERIFIED**: no code path was found that resets the counter
other than a successful activation, and no UI path that performs the
manual retry was found in the files read — the retry is specified as
a manual user action; confirm the exact UI affordance on Mac.

### 4.4 The embedded host script (behaviour, not source)

`ExtV2HostScript.source` is a Node script written to
`<root>/host/extension-host.js` (refreshed when its content differs)
and executed as `node extension-host.js --extension-entry <path>`.
Its behaviour, which the SwiftCode port must reproduce as a bundled
resource (the script is a **resource**, not Swift code — the
implementation slice must ship it as a file in the target's resources
and keep it byte-identical to the spec's behaviour):

- Parses `--extension-entry`; missing → stderr message, exit code 2.
- Intercepts **only** `require('vscode')`; every other `require`
  resolves normally from the extension's own directory /
  `node_modules`.
- The `vscode` shim provides: classes `Position`, `Range`,
  `Selection` (with `anchor`/`active`), `Uri` (`file`/`parse`,
  `scheme`/`path`/`fsPath`), `Diagnostic`, `DiagnosticSeverity`
  (`Error: 0, Warning: 1, Information: 2, Hint: 3`), `TreeItem`,
  `EventEmitter`, `Disposable`; namespaces `commands`
  (`registerCommand`, `executeCommand` over the local table,
  `getCommands`), `window` (message methods record to
  `state.messages` and resolve `undefined`; `createOutputChannel`
  appends to `state.outputLines`; `createStatusBarItem` sets
  `state.statusBar`; `showQuickPick`/`showInputBox` resolve
  `undefined`; `withProgress` **rejects** as unsupported), `workspace`
  (`getConfiguration()` returns an object whose `get(key, fallback)`
  always returns `fallback`, `has()` false, `inspect()` undefined;
  `openTextDocument(path)` reads via `host.readFile`;
  `applyEdit(edit)` sends `host.applyEdit` — see the D-9 shape
  disagreement; `fs.readFile`/`fs.writeFile` via host requests;
  `onDidChangeTextDocument` returns a no-op disposable), `languages`
  (provider registrations record languages or return no-op
  disposables; `createDiagnosticCollection(name).set(uri, diagnostics)`
  records locally **and** sends `host.publishDiagnostics`),
  `extensions.getExtension(id)` (returns the active extension or
  `undefined`), `debug` / `notebooks` / `authentication` — all throw
  the unsupported error. `vscode.version` is the string `'1.85.0'`.
- `unsupported(api)` produces `Error('SwiftCode does not support
  <api> (see Docs/Extensions-v2.md API matrix).')` — a descriptive
  error, never fake success.
- Activation: `require(entryPath)`; if `mod.activate` is a function,
  await it with `context = {subscriptions: [], extensionPath:
  dirname(entryPath)}`; exports are stored (plain-JSON-ified) for
  `getExtension`. Re-activation returns the current contribution
  without re-running `activate`.
- `executeCommand`: looks up the id in the registered-command table;
  unknown → `Error('Command not registered in this host: <id>')`;
  the return value is plain-JSON-ified (`toPlain`: `undefined` →
  `null`, unserialisable → `String(value)`).
- `shutdown`: calls `exports.deactivate()` if present (errors
  swallowed), returns `{ok: true}`.
- Contribution collection (`collectContribution`): commands = all
  registered command ids (`{command: id, title: id}` — title is the
  id, not the manifest title); views = registered tree-provider ids;
  tree items = `provider.getChildren()` results flattened to
  `{id: "<viewId>:<label>", label, description, command}` (a failing
  provider appends an output line, never fails activation);
  `statusBarText`, `outputLines`, `messages`, `completionLanguages`,
  `hoverLanguages`.
- Host-initiated requests from the shim carry ids `host-<n>` and a
  30s timeout; unanswered → rejection.
- Responses to SwiftCode requests are matched by `id`; a line that
  is neither a response (`result`/`error` present) nor a parseable
  request is ignored.
- `uncaughtException` → attempts to send `{id: 'fatal', error:
  {code: -32001, message: 'Host crashed: …'}}`, then `process.exit(1)`.

**The SDK host is different**: `SDKExtensionManager` spawns
`adapter.js` (resolved via `SWIFTCODE_SDK_ADAPTER_PATH` or the
bundled `SwiftCodeSDK/TypeScript/runtime-adapter/dist/adapter.js`,
else typed `.runtimeUnavailable`) with argv
`--entrypoint <entry> --manifest <manifest> …`, and speaks the SDK
event envelope (`ExtensionIPCEnvelope{id, type, target?, payload?,
timestamp}`; NDJSON, 1 MiB frames, `SDKIPCTransport`) with lifecycle
events `extension.ready` / `.activated` / `.deactivated` /
`.failed`. That adapter and envelope are **not** ported; one host,
one wire protocol (the v2 one above).

### 4.5 Diagnostics

`ExtV2DiagnosticsService` (singleton, `@unchecked Sendable`):

- Levels: `info`, `warning`, `error`.
- Entry: `{id: UUID, timestamp: Date, extensionId: String?,
  level, message}`. In-memory ring capped at **2000** entries (oldest
  dropped); every entry is also appended as one JSON line to
  `diagnostics.jsonl` (append failure is printed, never thrown —
  diagnostics must never break the operation they describe).
- `exportReport()` renders `[ISO8601] [level] <id>: <message>` lines.
- Messages only — never secrets or file contents.
- In DEBUG builds, entries are also printed as
  `[ExtV2][<level>] <id>: <message>`.

### 4.6 Resource limits (with the disagreement)

`ExtV2ResourceLimits` declares: max VSIX **200 MB**, max extracted
**1 GB**, max archive entries **10,000**, max IPC message **1 MB**,
host activation timeout **30s**, host command timeout **60s**,
registry timeout **30s**, max consecutive host crashes **3**.

**Disagreement D-1 (§12):** `ExtV2PackageService.Limits` — the
limits actually enforced at install — are **different**: max archive
**64 MB**, max extracted **512 MB**, max entries **20,000**. The
download path enforces the 200 MB figure (`downloadVSIX` rejects
over `maxVSIXBytes`), so a 100 MB VSIX downloads successfully and
is then rejected at install. The SwiftCode port must enforce **one**
set of limits everywhere: the `PackageService` figures (64 MB /
512 MB / 20,000 entries) at both download and install, with the
1 MiB IPC cap and the timeouts above. The SDK package validator's
bounds (100 MB total, 10,000 entries, 255-byte names, symlink depth
40) are a third set, for `swiftcode.json` packages only.

## 5. Capability / permission model

### 5.1 The two capability systems

Legacy has two capability vocabularies. The v2 platform uses the
first; the SDK host uses the second. The SwiftCode port implements the
v2 twelve as the runtime gate and the SDK thirty-five as the
manifest-declared set for SwiftCode-native extensions, with the
mapping in §5.3.

**v2 capabilities** (`ExtV2Capability`, 12, each with a display name):

| Raw value | Display name | Gates |
|---|---|---|
| `workspaceRead` | Read workspace files | `WorkspaceBridge.listFiles/readFile`, sample plugin listing |
| `workspaceWrite` | Write workspace files | `WorkspaceBridge.writeFile`, `host.applyEdit` (via write) |
| `outsideWorkspace` | Access files outside the workspace | Declared; **no bridge call in the v2 files read checks it** — see UNVERIFIED list |
| `network` | Network access | Declared; **no v2 bridge enforces it** (the registry client is host-side, not extension-side) |
| `terminal` | Run terminal commands | Declared; no v2 bridge enforces it |
| `process` | Launch processes | Declared; no v2 bridge enforces it |
| `secrets` | Read stored secrets | Declared; secrets are never passed to hosts (§5.5); the VS Code matrix lists `secrets` as unsupported |
| `sourceControl` | Source-control operations | `WorkspaceBridge.gitStatus` (read-only `git status`) |
| `build` | Build and test execution | Declared; no v2 bridge enforces it |
| `assistTools` | Register Assist tools | `ExtV2AssistBridge.register` — registration is refused without it |
| `projectConfig` | Change project configuration | Declared; no v2 bridge enforces it |
| `webview` | Show webviews | Declared; the contribution model carries `webviewHTML`, rendered only through the restricted `ExtV2RestrictedWebView` |

Enforcement rule (v2): the bridges check grants **on every call**;
revocation takes effect on the next call. A capability declaration
is not a grant, and a prompt is not a sandbox — the boundaries are
process isolation, the IPC allowlist, bridge checks, archive
validation, and resource limits.

**SDK capabilities** (`ExtensionCapabilityID` / `SDKCapabilityID`,
35 ids, verbatim — never normalise or re-case):

`project.read`, `workspace.read`, `workspace.write`,
`source-control.read`, `source-control.write`, `build.execute`,
`task.execute`, `network.request`, `ui.contribute`,
`credentials.use`, `use.Security`, `assist.invoke`, `assist.ui`,
`assist.headless`, `assist.main`, `db.ExploreView`, `ci.VisualWF`,
`sandbox.view`, `virtualization.view`, `deployConsole.view`,
`use.SwiftCodeModel`, `terminal.sandbox`, `simulator.view`,
`preview.live`, `uibuilder.open`, `symbols.browse`, `docs.search`,
`dictionary.open`, `deviceconnect.open`, `security.addValue`,
`security.hasValue`, `security.listValueIDs`,
`security.deleteValue`, `security.useValue`.

Risk levels (from `ExtensionCapabilityID.riskLevel`): `low` —
`project.read`, `source-control.read`, `docs.search`; `medium` —
`workspace.read`, `ui.contribute`, `preview.live`, `symbols.browse`,
`dictionary.open`; `high` — everything else, including all
`security.*` and `credentials.use`. `assist.invoke` is
`isGrantable == false` (restricted deny-by-default); every other id
is grantable. The six `use.Security.*` sub-scopes
(`use.Security.keychain`, `.audit`, `.crypto`, `.securePrompt`,
`.redaction`, `.policy`) are **method scopes enforced under the
single `use.Security` grant, not separately grantable permissions**.

### 5.2 Grant storage + approval UX

**v2 grants** (`ExtV2PermissionManager`):

- Store: `grants.json` — `{extensionId: [capability-rawValue]}`.
  Loaded at init (unparseable → empty, not fatal); every
  `grant`/`revoke`/`revokeAll` persists atomically (snapshot under
  lock, `writeAtomically`).
- Posture: **deny by default**. `isGranted` is false for anything
  not in the store. `check` throws
  `ExtV2Error.permissionDenied(capability)` ("Permission denied:
  <display name>. Grant it in Extensions > Permissions.").
- `request(extensionId, capability, reason)`:
  already-granted → `true` immediately; else if no `promptHandler`
  is installed → **`false`** (a headless call is a denial, not a
  queue); else await the handler and grant on approval.
- `promptHandler` is set by the UI layer; it is the only approval UI
  in the v2 platform. Revocation is immediate for the next call.
- Uninstall revokes all grants for the extension.

**SDK grants** (`SDKGrantStore`, reference): actor-guarded store at
`~/Library/Application Support/SwiftCode/SDKGrants.json`, mode
`0600`, corrupt file moved aside (never deleted). Grants are scoped
to one extension; a package-digest change revokes all of them
(§3.4). The SwiftCode port uses **one** grant store — the v2
`grants.json` — and records the SDK store's `0600` mode as a
requirement to adopt for it (deviation §12).

**Approval UX (SwiftCode)**: the UI slice presents one prompt per
capability request with the extension's declared `reason` (from
`swiftcode.json`) or the caller's reason string (from
`host.requestPermission`). The prompt must show the capability's
display name, the extension id, and the reason — and must offer a
persistent grant, not a one-shot bypass. No prompt may be shown for
a capability the manifest does not declare (VS Code extensions) or
that is not in the known registry (SwiftCode extensions).

### 5.3 Mapping between the two vocabularies (SwiftCode)

When a `swiftcode.json` manifest is installed, its declared SDK
capability ids map to v2 runtime capabilities for enforcement:

| SDK id | v2 capability |
|---|---|
| `workspace.read`, `project.read`, `source-control.read`, `docs.search`, `symbols.browse`, `dictionary.open` | `workspaceRead` |
| `workspace.write`, `source-control.write` | `workspaceWrite` |
| `network.request` | `network` |
| `terminal.sandbox`, `task.execute` | `terminal` + `process` |
| `build.execute` | `build` |
| `credentials.use`, `use.Security`, `security.*` | `secrets` |
| `assist.invoke`, `assist.ui`, `assist.headless`, `assist.main` | `assistTools` |
| `ui.contribute`, `preview.live`, `uibuilder.open`, `simulator.view`, `sandbox.view`, `virtualization.view`, `deployConsole.view`, `db.ExploreView`, `ci.VisualWF`, `deviceconnect.open`, `use.SwiftCodeModel` | `webview` (UI contribution surface; no separate runtime gate in this wave) |

`assist.invoke` maps to `assistTools` but is **not grantable** in the
SDK system; in SwiftCode, an extension that declares `assist.invoke`
still requires an explicit user grant of `assistTools` through the
v2 prompt — the manifest declaration alone never grants it. This
mapping is a SwiftCode decision, not a Legacy behaviour; it is recorded
as a deviation (§12).

### 5.4 The single approval gate (Wave 2) — do not design a second one

Extension execution that writes or runs third-party code goes through
the Wave 2 gate in `specs/ide/assist-approval-model.md`:
`MCPServer.run()` is the single gate; handlers call `commit()` /
`call.approve(change)` before touching disk, and a refusal throws
`MCPToolError(MCPServer.rejectedMessage)` ("The change was rejected
in SwiftCode's review; nothing was written."). The `use_extension`
handler (§7.2) is a write tool (`safeMutation`, `writes: true` in its
existing registration) and must:

- require `confirm: true` for the mutating actions
  (`activate`, `execute`, `run_xcode_command`, `enable`, `disable`)
  — the Legacy rule, kept verbatim;
- **and** call `approve()` (with an `MCPChange` describing the
  change) before performing the action. For `activate`/`execute`
  (running third-party code) the change describes the extension,
  command, and workspace; for `run_xcode_command` the change is the
  file write itself (use `commit()` for the file write, exactly as
  the Wave 2 file tools do); for `enable`/`disable` the change
  describes the state change.
- Read-only actions (`list`, `details`, `list_commands`,
  `list_xcode_commands`, `diagnostics`) and `deactivate` (Legacy
  classifies it read-only — it only stops a host) do **not** call
  `approve()`.

There is no Autopilot mode anywhere in SwiftCode: Legacy's
`AssistPermissionsManager` default (Autopilot bypassing
SwiftCode-level restrictions) is explicitly rejected by the Wave 2
spec and is not ported.

### 5.5 Secrets

Secrets are never passed to extension hosts and never logged
(Legacy v2 rule, kept). The host process environment is stripped of
`SWIFTCODE_`/`HERMES_` variables. The VS Code API matrix lists
`secrets` and `authentication` as unsupported; the host shim throws
for `vscode.authentication`. The SDK's `use.Security` grant governs
host-side secret operations where the extension never sees plaintext;
that host-side vault is **not** in this wave (no secrets in this
wave per the task brief — `SecretStore` is not needed).

## 6. Registry / marketplace

### 6.1 What `ExtV2RegistryClient` actually does (verified live)

It is a real client for the **Open VSX** REST API, default base
`https://open-vsx.org/api` (overridable in settings; an unparseable
URL falls back to the default). No authentication, no API key, no
account. `Accept: application/json`. Request timeout 30s, resource
timeout 60s.

| Operation | Request | Response mapping |
|---|---|---|
| `search(query, offset = 0, pageSize = 20)` | `GET {base}/-/search?query=<q>&size=<n>&offset=<n>` | `{extensions: [{namespace, name, version, displayName?, description?, categories?, license?, homepage?, files: {download?}}], totalSize?}` → `[ExtV2ExtensionMetadata]` (rows missing namespace/name/version are dropped); `total = totalSize ?? results.count`; `hasMore = offset + count < total`. |
| `details(identity)` | `GET {base}/{publisher}/{name}` | Same extension JSON shape → one `ExtV2ExtensionMetadata`. Missing identity fields → registry error. |
| `downloadURL(metadata)` | Prefers `metadata.downloadURL`; else `details()` and its `files.download`; else constructs `{base}/{publisher}/{name}/{version}/file/{publisher}.{name}-{version}.vsix` | Returns a URL; the caller downloads it. |
| `downloadVSIX(from, to)` | `URLSession.download`, streamed to a file | Non-2xx → network error; 404 on `get` → "Extension not found in the registry."; size over 200 MB → package error and the file is deleted (see D-1). Cancellation → `ExtV2Error.cancelled`. |

Errors: non-HTTP response → registry error; HTTP non-2xx (other
than 404) → "Registry request failed with HTTP <code>."; transport
failure → `ExtV2Error.network("Registry request failed: …")`;
unparseable body → registry error with the parse message.
Download counts and ratings are deliberately **not** mapped or
displayed — they are not part of the compatibility contract and must
never be fabricated when a registry does not report them.

**There is no other registry endpoint in Legacy.** No SwiftCode
marketplace endpoint, no listing service, no review/rating service,
no private-registry auth. The marketplace UI is a local view over
this client plus the installed set. If Open VSX is unreachable, the
platform still works fully for already-installed extensions (local
registry only, §6.2).

### 6.2 Local registry (SwiftCode)

Because the only remote is Open VSX, the SwiftCode port specifies a
**local registry first**: the installed set in `installed.json` is
the registry of record for `list`/`details`/`list_commands`/
`diagnostics`. Open VSX search/install is an additive remote. The
implementation must work offline for every operation except
`search` (remote) and `install` from the registry (remote download);
install from a local `.vsix` file must work offline through the
same `packageService.install` path.

### 6.3 Install / uninstall / update flow + package validation

**Install pipeline** (`ExtV2Manager.install` → `ExtV2PackageService.install`):

1. Validate the extension id: non-empty, ≤ 214 chars, only
   alphanumerics plus `._-`, no leading `.`, no `..`.
2. The downloaded file must exist, be a regular file, be non-empty,
   and be ≤ 64 MB (`Limits.maxArchiveBytes`) — else
   `ExtV2Error.package` with a specific reason.
3. Open as a ZIP archive (`ZIPFoundation` in Legacy; SwiftCode must use
   whatever ZIP reading the implementation slice can link — the
   **behaviour** is the contract, not the library). Unreadable →
   package error.
4. Single pass over entries, each validated **before** it is written:
   entry count ≤ 20,000; `__MACOSX/` entries skipped; relative path
   validated (non-empty, ≤ 512 chars, no NUL, not absolute, no
   backslash separator, no `.`/`..` components, no drive-qualified
   `X:` component); symlinks → rejected; other types (not file,
   directory, symlink) → rejected at the switch (only file/directory
   pass); declared uncompressed bytes accumulate and must stay ≤
   512 MB; the destination must stay inside the staging dir after
   standardisation.
5. Post-extraction verification on disk (ZIP headers can lie):
   reject any symlink or special file (not regular file / directory);
   verify the real extracted byte total ≤ 512 MB.
6. Require `extension/` directory and `extension/package.json`
   inside it; parse the manifest; require the manifest identity to
   equal the requested identity exactly; if `main` is declared it
   must be non-empty, safe-relative, and exist in the package.
7. Evaluate compatibility (§2.1.2).
8. Commit with **one directory move**: the previous installation, if
   any, is moved aside to `backups/<id>.backup` first and restored if
   the commit fails; the staged tree (the whole extracted VSIX, not
   only `extension/`) becomes `extensions/<id>/`. Staging is removed
   in all cases (`defer`).
9. The manager records the install with capabilities `[]` and
   re-runs `refreshInstalled()`.

**Never**: extract in place; execute package scripts (there is no
script execution anywhere in the pipeline); install without the
identity check.

**Uninstall**: deactivate, remove contributions, revoke all grants,
remove install dir + backup (idempotent — an already-removed dir is
not an error), remove the record.

**Update**: `checkUpdates()` compares registry versions; the actual
update is a re-`install` of the newer metadata (same atomic pipeline;
the old version is the backup until the commit succeeds). There is no
separate update code path.

**`swiftcode.json` package validation** (`SDKPackageValidator.validatePackage`,
runs **after** the manifest validator):

- Root must be a local directory URL; `swiftcode.json` must exist at
  the root; the entrypoint must resolve (symlinks resolved
  component-by-component, max depth 40, escapes → `pathTraversal`)
  to a real file inside the package.
- Walk: max 10,000 entries, max 100 MB total regular-file bytes,
  max 255 bytes per file name, no NUL in names.
- A set of forbidden executable extensions is declared
  (`sh`, `bin`, `exe`, `dylib`, `so`) — "the v1 runtime is node
  loading a JS entrypoint — no executables of any kind are allowed
  inside a package" — but **UNVERIFIED** whether the walk enforces
  the extension set and the `.env`/`node_modules` exclusions named
  in the file's header comment; the walk code excerpted in this pass
  shows the entry-count, name, and byte-total checks only. The
  implementation slice must confirm the enforcement before claiming
  it, or enforce it per the header and record it as a decision.

**`ExtensionPackager` (SDK authoring side)**: validates with the
lenient validator (any error-severity diagnostic aborts packaging),
zips with `/usr/bin/zip` (see §2.4), returns
`ExtensionPackageInfo{extensionId, version, packagePath, archiveSize,
sha256, fileCount}` — with `fileCount` hardcoded to `1` (do not
trust it). `verify(packagePath:)` unzips to a temp dir and runs
`validateFile` on it. This is authoring tooling, not the install
path; it is specified here so the implementation slice can reuse the
validation rules, not so it can reimplement `/usr/bin/zip`
invocation on Linux.

### 6.4 Dependency resolution

`ExtV2DependencyResolver` is pure (no IO):

- `resolve(requested: [manifests], installedIDs: Set, manifestsByID: [id: manifest])`
  → `{installOrder: [id] (dependencies first, topological),
  missing: [id], cycles: [[id]]}`. `isSatisfied` = no missing and no
  cycles. A dependency is satisfied only by an installed extension
  or one in the same batch — never by assuming the registry will
  provide it later. Cycles are reported as the stack slice plus the
  repeated id; missing ids are de-duplicated in order of first sight.
- `missingDependencies(for: installed, installedByID:)` — every
  declared dependency must be installed **and enabled**; a disabled
  dependency counts as missing.
- The manager calls `missingDependencies` on every refresh; it does
  **not** call `resolve` for install ordering in the code read —
  install is single-extension, and batch ordering is a property of
  the resolver, not of the install path. **UNVERIFIED**: whether any
  caller installs a batch through `resolve` (none was found in the
  v2 files read). The port keeps `resolve` as a pure function and
  does not invent a batch-install flow.

## 7. Assist bridge

### 7.1 How extensions contribute tools

`ExtV2AssistBridge` is the only registration path: validated
descriptors into the **existing** tool registry — there is no
parallel tool system. In SwiftCode that means the MCP tool catalogue
(`SwiftCodeMCP`), not a new registry.

- Descriptor (`ExtV2AssistCapability`): `toolId`, `name`,
  `description`, `parameters: [name: "string" | "number" |
  "boolean"]`, `requiredParameters: [String]`, `extensionId`,
  `command`, `requiredCapabilities: [ExtV2Capability]` (default
  `[]`), `isReadOnly: Bool` (default `true`).
- Tool id: `"extv2." + (extensionId + "." + command)` with every
  non-letter/digit/`.` character replaced by `_`. Stable, unique per
  command, never colliding with built-ins (the registry keeps the
  first registration on a collision and logs it).
- `descriptor(for: command, extensionId:)`: name = command title,
  description = `"Extension command '<command>' from <extensionId>."`,
  parameters empty, required empty, `isReadOnly: true` by default.
  The manager's `registerAssistCommands` passes these defaults, so
  **every extension command registers as a read-only tool with no
  parameters and no required capabilities unless the caller says
  otherwise** — the port must preserve that default and let the
  `use_extension` execute path (which does carry args) be the
  parameterised route.
- `register(descriptor, permissions) -> Bool`: returns `false`
  (and logs a warning) when `.assistTools` is not granted —
  registration is a privileged act, not a default.
- `validate(input:)`: missing required params and wrong primitive
  types (`string`/`number`/`boolean`; `NSNumber` counts as number)
  are caller errors, thrown before any execution. Unknown parameter
  types are ignored (no check).
- Execution (`ExtV2AssistExecution.execute`): validate → re-check
  every `requiredCapabilities` grant → native handlers first
  (existence checked before executing, so a native command's own
  failure propagates instead of falling through) → else host
  `executeCommand` with the host command timeout. Failures return a
  typed tool failure, never silent success. Routing is by command
  ownership: a tool can never execute a command belonging to a
  different extension.
- **Arg-encoding disagreement D-10 (§12):** the Assist-bridge path
  encodes each input entry as the string `"key=value"`
  (`ExtV2JSONValue.string("\(key)=\(value)")`), while the
  `use_extension` execute path sends a single JSON object argument
  (`[.object(args)]`) so the extension receives its named arguments
  intact. The SwiftCode port must use the **object form everywhere**;
  the `key=value` form is a Legacy inconsistency, not a contract.

### 7.2 The `use_extension` contract (full)

Already registered in SwiftCode (`SwiftCodeTools+Terminal.swift`, ~line 224;
handler ~line 606 honestly fails). The implementation slice wires
the handler to `SwiftCodeExtensions`; the contract below is Legacy's,
verified from `UseExtensionTool.swift` (581 lines).

- Tool id `use_extension`, capability `.general`, risk
  `.safeMutation`, required permission `.fileSystem`. In SwiftCode it is
  registered `safeMutation, writes: true`.
- **Actions (11)**: `list`, `details`, `list_commands`,
  `list_xcode_commands`, `activate`, `deactivate`, `execute`,
  `run_xcode_command`, `enable`, `disable`, `diagnostics`.
- **Parameters**: `action` (string, required — the only required
  parameter); `extensionId` (required for every action except `list`
  and `list_xcode_commands`); `command` (for `execute` and
  `run_xcode_command`); `file` (workspace-relative path, for
  `run_xcode_command`); `selection` (object
  `{startLine, startColumn, endLine, endColumn}`, all integers,
  0-based; defaults to the whole file); `args` (string-keyed object,
  for `execute`); `confirm` (boolean); `limit` (integer, list and
  diagnostics only).
- **Confirm rule**: `activate`, `execute`, `run_xcode_command`,
  `enable`, `disable` require `confirm: true`. `deactivate` does
  **not** (Legacy classifies it read-only). Missing confirm →
  `invalidRequest` ("Action '<action>' requires confirm: true.").
  This is in addition to, not instead of, the Wave 2 `approve()`
  gate (§5.4).
- **`limit`**: default 50, clamped to [1, 200]. Non-integer numerics
  are truncated via `NSNumber`/`Double` coercion.
- **Output cap**: 8,000 characters; longer output is truncated with
  `"\n... (truncated)"` appended.
- **Error mapping**: `notInstalled → notFound`;
  `disabled`/`permissionDenied → permissionDenied`;
  `incompatible → unsupportedOperation`;
  `missingDependencies → executionFailed`;
  `invalidRequest → invalidInput`; `timeout → timeout`;
  `cancelled → cancelled`; everything else → `executionFailed`.

Per-action behaviour:

| Action | Behaviour |
|---|---|
| `list` | Refresh installed; return up to `limit` rows `" <id> — <displayName> v<version> [<kind display>, <state display>]"`. Empty: `"No extensions installed. Discover extensions from the Extensions sidebar (Open VSX registry) or register the sample native plugin."` Data: `{action: "list", count}`. |
| `details` | One extension: display name + id, version, kind, state, enabled, description; dependencies with satisfied/missing per dep; granted capabilities (display names, or `"none"`); `lastError` if any; for VS Code kind, re-parse the manifest and append `Compatible: <bool>` + compatibility notes; running contribution commands if any. Data includes `state` (raw value) and `kind` (raw value). Not installed → `notInstalled`. |
| `list_commands` | VS Code: running contribution commands if the host is running (`"(running)"`), else the manifest's `contributes.commands` (`"not running; activate first to execute"`), else "No commands found … manifest could not be read." Native: the plugin manifest's commands (`"native plugin"`). Xcode-command kind: delegates to `list_xcode_commands`. Empty → `"Extension <id> contributes no commands (<note>)."` |
| `list_xcode_commands` | All registered Xcode command identifiers, one per line; empty → `"No Xcode-compatible commands are registered. Only registered source-editor command logic can run; XcodeKit binaries cannot run inside SwiftCode."` |
| `activate` | Set workspace root from context, `manager.activate`. Output `"Activated <id>."` plus commands and output lines when present. Data `{state: "running"}`. |
| `deactivate` | `manager.deactivate`; output `"Deactivated <id>."`. No confirm required. |
| `execute` | Guards: installed, enabled. For VS Code kind, if the host is not running, **activate first** (confirm already given), so one call works end to end. Args sent as one JSON object argument (empty args → no args). Result string or `"(command returned no output)"`. |
| `run_xcode_command` | File must be workspace-relative (absolute or escaping → invalid request). Read the real file; selection defaults to the whole file; selection bounds are validated against the file's lines/columns. Build a source buffer, run the registered command; on throw, the file is untouched. Write back **only when the buffer changed** (atomically); post `ExtV2WorkspaceFileDidChange`; log diagnostics; return a summary with line counts before/after and the new content, `filesChanged: [file]`. No change → `"Command '<cmd>' made no changes to <file>."`, `changed: "false"`. Unknown command → invalid request listing the registered commands. |
| `enable` / `disable` | Guard installed; `setEnabled`; output `"<Enabled/Disabled> <id> (state: <display>)."` |
| `diagnostics` | Last `limit` entries for the extension, `"[ISO8601] [level] message"` per line; empty → `"No diagnostics recorded for <id>."` |

Known limitations (Legacy, kept verbatim in the SwiftCode tool
description): XcodeKit binaries cannot execute; VS Code execution
needs Node.js and an installed, enabled extension; language-provider
contributions (completion, hover) are editor surfaces, not
Assist-callable commands; webview, terminal, and debug contributions
are not rendered or driven through this tool.

### 7.3 Native plugins

`ExtV2NativePlugin` protocol: `static var manifest:
ExtV2NativePluginManifest`, `init()`, `activate(context:) async
throws`, `deactivate() async` (default no-op). Manifest:
`{id, name, version, description, commands: [ExtV2ContributionCommand],
capabilities: [ExtV2Capability]}`; its derived metadata is
`publisher: "swiftcode", name: <id>, kind: .native`.

- `ExtV2NativePluginContext`: manifest, workspace root, optional
  workspace bridge, permissions manager, and a `registerCommand`
  closure. Workspace access through the context is capability-gated
  exactly like a VS Code extension's bridge calls.
- `ExtV2NativePluginRegistry` (singleton, `@MainActor`): `manifests`,
  `register(_:)` (dedupe by manifest; instantiates the plugin),
  `activateAll(workspaceRoot:workspace:permissions:)` (activation
  failure per plugin is logged, never fatal), `executeCommand` via a
  static lock-guarded command table (unknown command →
  invalid request), `contribution(for:)` (commands + output line
  `"Native plugin '<name>' v<version> is active."`).
- **Trust boundary (stated plainly in Legacy, kept):** plugins
  compiled into the app run in-process and are trusted exactly as
  much as the app itself. **Third-party native code is NOT loaded
  in-process**: there is no dynamic bundle loading, because loading
  arbitrary native code in-process would bypass every permission
  check. A future signed-bundle loader must go through the permission
  manager and a review step before it exists. Untrusted code ships as
  a VS Code extension through the out-of-process host.
- Sample plugin (`ExtV2SamplePlugin`): id
  `sample.workspace-lister`, name "Workspace Lister (Sample)",
  version `1.0.0`, capability `[.workspaceRead]`, one command
  `extv2.sample.listWorkspace` ("Sample: List Workspace Files")
  listing up to 50 workspace files (sorted), or "No workspace is
  open." / "Workspace is empty.". Activation registers the command;
  the workspace check happens when the command runs, not at
  activation.

### 7.4 Xcode source-editor commands

Value types modelling XcodeKit's shapes (positions are **0-based
(line, column)**, columns count Swift Characters / grapheme clusters
— an emoji is one column, not two UTF-16 units):

- `ExtV2SourcePosition{line, column}` (Comparable, line-major),
  `ExtV2SourceRange{start, end}` (`isEmpty` when start == end),
  `ExtV2SourceTextBuffer` (lines + selections; `completeBuffer` =
  lines joined with `\n`; `applyEdits` validates **all** ranges
  first — reversed ranges, out-of-bounds lines/columns, overlapping
  ranges are errors — then applies in reverse order; any failure
  leaves the buffer untouched),
  `ExtV2SourceEditorInvocation{buffer, commandIdentifier, uti}`
  (default uti `"public.swift-source"`; `checkCancellation()` is
  cooperative `Task.checkCancellation()`),
  `ExtV2SourceEditorCommand` protocol (`identifier`, `title`,
  `perform(invocation:) async throws`).
- `ExtV2XcodeCommandRegistry` (singleton, lock-guarded):
  `register`, `command(for:)`, `allIdentifiers` (sorted),
  `perform(identifier:, buffer:)` (unknown → invalid request).
- Built-in example and test fixture: `ExtV2SortLinesCommand`,
  identifier `com.swiftcode.xcode.sortLines`, title "Sort Lines":
  sorts the lines covered by the first selection, leaving everything
  else untouched; no selection → no-op (returns successfully).
- The four categories are kept distinct in UI and docs: (1)
  SwiftCode-native extensions, (2) reusable source-editor command
  logic (this adapter), (3) XcodeKit extension binaries — run under
  Xcode only, never here, (4) external developer tools via
  documented interfaces (e.g. SourceKit-LSP).

### 7.5 VS Code API surface (what is and is not supported)

Versioned matrix `ExtV2VSCodeAPI.matrix` (host engine 1.85.0).
The host shim implements the supported surface and **throws a
descriptive error** for the unsupported surface — never fake success.

| Level | APIs |
|---|---|
| Supported | `commands`; `window.showInformationMessage` / `showWarningMessage` / `showErrorMessage`; `window.createOutputChannel`; `window.showQuickPick`; `window.showInputBox`; `workspace.fs`; `workspace.openTextDocument`; `workspace.applyEdit`; `workspace.getConfiguration`; `workspace.onDidChangeTextDocument`; `languages.registerCompletionItemProvider` / `registerHoverProvider` / `registerDefinitionProvider` / `registerReferenceProvider` / `registerRenameProvider` / `registerDocumentFormattingEditProvider` / `registerCodeActionProvider`; `languages.createDiagnosticCollection`; `extensions.getExtension`; `StatusBarItem`; `TreeDataProvider`; `snippets` |
| Partial | `window.withProgress` (shim rejects with unsupported error — the matrix says partial but the shim does not implement progress UI; see §12 D-11); `WebviewViewProvider` (restricted bridge only, §8.2); `tasks`; `terminal` (no full PTY); `SourceControl`; `themes`; `grammars` |
| Unsupported | `debug`; `notebooks`; `testing`; `authentication`; `secrets`; `CustomEditor`; `FileSystemProvider` |

Notes: `showQuickPick`/`showInputBox` are "supported" in the matrix
but the host path returns null (no picker UI attached) — the shim
resolves `undefined`. `registerDefinitionProvider` /
`registerReferenceProvider` / `registerFormattingProvider` /
`registerCodeActionProvider` / `registerRenameProvider` are in the
matrix as supported, but the host script's `languages` shim only
records completion/hover languages and returns no-op disposables for
the rest; the Swift `handleHostRequest` accepts their `host.*`
methods and returns null without recording them. The
provider-registry record therefore covers completion + hover only.
The implementation slice must not claim definition/reference/
formatting/code-action providers are wired until they are.

## 8. Editor / workspace bridges

### 8.1 `ExtV2WorkspaceBridge` — what it exposes

The **only** path by which extension-host code touches the file
system. Capability-gated on every call.

- `resolvedPath(for: relativePath, extensionId:)`: rejects absolute
  paths; resolves symlinks on both the candidate and the root and
  requires the resolved path to equal the root or sit under it
  (`root + "/"` prefix). A workspace-relative path that resolves
  outside the root is rejected even if it looks relative.
- `listFiles(extensionId:)` — requires `workspaceRead`; recursive
  enumeration skipping hidden files, capped at **20,000** entries
  (silently stops, does not error); returns
  `[{relativePath, isDirectory}]`.
- `readFile(relativePath, extensionId:)` — requires `workspaceRead`;
  UTF-8; failure → `ExtV2Error.unknown("Could not read '…': …")`.
- `writeFile(relativePath, content, extensionId:)` — requires
  `workspaceWrite`; creates parent dirs; atomic write; posts
  `ExtV2WorkspaceFileDidChange` (`userInfo: {path, extensionId}`);
  logs diagnostics.
- `gitStatus(extensionId:)` — requires `sourceControl`; runs the real
  `/usr/bin/git -C <root> status --short`; non-zero exit → unknown
  error. Read-only; no other git command is exposed.
- Notifications: `ExtV2WorkspaceFileDidChange`,
  `ExtV2DocumentDidChange` (the latter is declared but **no sender
  was found** in the v2 files read — treat as reserved).

In SwiftCode, the workspace bridge is backed by the open workspace
(`SwiftCodeWorkspace` / the MCP session's workspace root). The
containment rule (symlink-resolved prefix check) is kept verbatim;
it matches the Wave 2 workspace-confinement rule.

### 8.2 `ExtV2EditorBridge` — what it exposes, and its honest limit

Pure text-edit functions over document content (no editor object):

- `ExtV2TextPosition{line, character}`,
  `ExtV2TextRange{start, end}`, `ExtV2TextEdit{range, newText}`,
  `ExtV2DocumentState{relativePath, content, selection: Range<Int>?}`.
- `ExtV2DocumentStore` protocol (`read`/`write` by relative path);
  `ExtV2FileDocumentStore` implements it over the workspace bridge.
- `applyEdits(_:to:)`: lines/characters 0-based; characters count
  Swift Characters (grapheme clusters); edits applied in reverse
  order so earlier ranges stay valid; overlapping edits rejected, not
  merged; out-of-range lines/columns rejected; multi-line replacement
  text is supported (the replaced span is re-split on `\n`).
  Trailing-newline round-trip is preserved by the
  components/join behaviour.
- `offset(for:position, in:content:) -> Int?`: character offset of a
  position, or nil when out of range; used to preserve selections
  across edits.

**Honest limit (Legacy, kept):** v1 edits are file writes plus a
document-changed notification; they do **not** reach into the
editor's undo stack. An extension edit is a file write that the
editor reloads — undo for extension edits lives in the file's own
history, not in the editor's Undo menu. Direct editor integration is
the documented next wiring step, not something v1 pretends to do.
The SwiftCode port keeps this limit and must not claim editor-undo
integration until a later slice wires it to SwiftCode's editor.

**Webviews:** the contribution model carries an optional
`webviewHTML`, rendered only through the restricted `WKWebView`
bridge in Legacy's `ExtensionRunView` (`ExtV2RestrictedWebView`).
No bridge code for that view was in the files read; the SwiftCode port
treats webview contributions as data-only in this wave (accepted in
the contribution model, not rendered).

### 8.3 `ExtV2LanguageClient` — what it exposes, and what SwiftCode has instead

A minimal real LSP client (actor): JSON-RPC over stdio with
**Content-Length framing** (`Content-Length: <n>\r\n\r\n` + body).

- `start(server: ServerInfo{command, arguments, language}, workspaceRoot)`:
  a bare command name is resolved through `PATH` via `/usr/bin/which`;
  a path must be executable. Sends `initialize` with
  `{processId: null, rootUri: <workspaceRoot>, capabilities:
  {textDocument: {completion: {completionItem: {snippetSupport:
  true}}}}}` and then the `initialized` notification. Stores raw
  server capabilities. Missing executable → clear error.
- `didOpen(uri, languageId, version, text)`,
  `didChange(uri, version, text)` (full-text sync — the whole text
  is sent every change), `didClose(uri)`.
- `completion(uri, line, character) -> [String]` — raw completion
  labels only (accepts both `{items: [...]}` and a bare array; items
  without a `label` are dropped; no invented items).
- `hover(uri, line, character) -> String?` — `contents` as a string,
  or `contents.value` from a `MarkupContent` object, else nil.
- `shutdown()` — `shutdown` request then `exit` notification, then
  terminate; `restart(server:workspaceRoot:)` = shutdown + start.
- Request timeout 30s (`$/cancelRequest` is mentioned in the file
  header as the cancellation mechanism, but **no `$/cancelRequest`
  send was found** in the code read — Task cancellation on the Swift
  side is the implemented mechanism).
- Server exit (EOF) fails all pending requests and sets `isRunning`
  false.

**SwiftCode already has this — do not port it.** `SwiftCodeLanguage`
contains a real `LSPClient` (Content-Length framing, sourcekit-lsp
first, `BuildServerLaunch` for sourcekit-lsp + build-server
integration, call-hierarchy support). The SwiftCode port must:

- delete the idea of a second LSP client; extension language
  providers register against `SwiftCodeLanguage.LSPClient` / SwiftCode's
  language services;
- keep only the **provider-registration data** from
  `ExtV2ProviderRegistry` (which extension owns completion/hover for
  which language, and published diagnostics per file) as the
  interface between the host and SwiftCode's editor;
- note that Legacy's `ExtV2LanguageClient` is a *generic* LSP client
  for any server binary, while SwiftCode's is sourcekit-lsp-oriented —
  whether a generic server binary can be attached through SwiftCode's
  client is **UNVERIFIED** and is a question for the implementation
  slice, not a claim in this spec.

### 8.4 Provider registry (`ExtV2ProviderRegistry`)

`@MainActor` singleton; the editor consults it before its own
providers; no host code runs inside the editor process.

- `diagnostics: [relativePath: [ExtV2Diagnostic]]` —
  `publishDiagnostics` **replaces** the whole list for a path
  (cross-extension overwrite: a second extension publishing for the
  same path replaces the first's diagnostics — observed behaviour).
  `ExtV2Diagnostic{relativePath, range, message, severity: String,
  source}`; severity is a free string, default `"Error"` at the
  publish site.
- `completionProviders: [language: extensionId]`,
  `hoverProviders: [language: extensionId]` — last registration wins
  per language (a plain dictionary assignment; no conflict error).
- `clear(for:)` — removes that extension's diagnostics (filtering by
  `source`), completion, and hover entries. Called on deactivate and
  host exit. Note: definition/reference/formatting/code-action
  providers have no registry storage at all.

## 9. Compatibility shims

### 9.1 `ExtV2Compatibility.swift` — versions + API matrix

Covered in §2.1.1–2.1.2 and §7.5. Port in full: `ExtV2Version`,
`ExtV2VSCodeAPI.hostEngineVersion` (1.85.0), the matrix, and
`ExtV2Compatibility.evaluate`. The matrix is the contract the UI and
diagnostics render; adding an API means adding a row **and** an
implementation, never a success-returning stub.

### 9.2 VS Code compatibility (`ExtV2VSCodeAPI.swift` + host script)

Covered in §4.4 and §7.5: the contribution model, the provider
registries, and the explicit unsupported list (`vscode.debug`,
`vscode.notebooks`, `vscode.tests`, `vscode.authentication`,
`vscode.SecretStorage`, `vscode.CustomEditor`,
`vscode.FileSystemProvider`, `vscode.Terminal.createTerminal (full
PTY)`). The Swift side of this file is the contribution + provider
model only; the shim behaviour lives in the host script.

### 9.3 Xcode compatibility (`ExtV2XcodeCompatibility.swift`)

Covered in §7.4. Port in full: buffer, invocation, command protocol,
registry, and the sort-lines example as the test fixture.

### 9.4 Deliberately NOT ported

- **XcodeKit binaries**: packaged, signed, and activated by Xcode;
  they cannot execute inside SwiftCode/SwiftCode. No loader, no
  entitlement bridging, no claim otherwise.
- **Debug / notebooks / testing / authentication / secrets /
  custom editors / filesystem providers / full PTY terminals**:
  the shim throws; the port keeps the throw.
- **Webview rendering, terminal contributions, task contributions**:
  accepted as data where the contribution model carries them, not
  driven or rendered in this wave.
- **Activation events**: parsed, never dispatched.
- **Language-provider wiring beyond completion/hover registration**:
  definition/reference/formatting/code-action/rename providers are
  matrix-"supported" but have no Swift-side registration or editor
  wiring in Legacy; the port does not invent it.
- **The SDK runtime adapter (`adapter.js`) and event envelope**:
  one host, one wire protocol (§4.4).
- **Legacy v1 ExtensionManager / PluginManager and their views**:
  dropped (§1.1).

## 10. PUBLIC API CONTRACT for the new `SwiftCodeExtensions` SwiftPM target

This section is the contract the implementation slice codes against.
It is minimal but complete: every type, case, and function the host,
the MCP tool, and the UI need — and no API the host doesn't need.
Names use the `SwiftCode` prefix in place of Legacy's `ExtV2` prefix
(the `ExtV2` prefix existed to disambiguate from Legacy's own
`ExtensionManager`/`ExtensionManifest`; SwiftCode has no such collision,
and the SwiftCode convention is `SwiftCode<Area>`). Where a Legacy name is
kept for wire compatibility (JSON keys, RPC methods, capability raw
values), it is marked **wire**.

All public API is `Sendable` unless noted. The manager is
`@MainActor`; the host runner and storage are `Sendable`. Errors are
`SwiftCodeExtensionError` (see §10.5); no other error type escapes the
target.

### 10.1 Identity, kind, state, errors

```swift
public struct ExtensionIdentity: Codable, Hashable, Sendable, CustomStringConvertible {
    public let publisher: String
    public let name: String
    public var id: String { "\(publisher).\(name)" }          // wire: "publisher.name"
    public var description: String { id }
    public init(publisher: String, name: String)
    public init?(id: String)   // splits on first "."; nil when either part is empty
}

public enum ExtensionKind: String, Codable, Sendable, CaseIterable {
    case vscode, native, xcodeCommand
    public var displayName: String { "VS Code" / "SwiftCode Native" / "Xcode Command" }
}

public enum ExtensionState: String, Codable, Sendable, CaseIterable {
    case notInstalled, installed, disabled, enabled, incompatible
    case missingDependencies, activationFailed, running, crashed, unavailable
    public var displayName: String
    // activationFailed is declared for wire/source compatibility; no
    // transition into it is specified in this wave (see §3.2).
}

public enum SwiftCodeExtensionError: Error, LocalizedError, Sendable {
    case notInstalled(String)
    case disabled(String)
    case incompatible(String)
    case missingDependencies([String])
    case permissionDenied(ExtensionCapability)
    case registry(String)
    case network(String)
    case package(String)
    case manifest(String)
    case host(String)
    case timeout(String)
    case invalidRequest(String)
    case cancelled
    case unknown(String)
    public var errorDescription: String? { get }
    // Messages match Legacy verbatim, including:
    // notInstalled: "Extension '<id>' is not installed."
    // disabled: "Extension '<id>' is disabled."
    // permissionDenied: "Permission denied: <display name>. Grant it in Extensions > Permissions."
}
```

### 10.2 Model types

```swift
public struct ExtensionMetadata: Codable, Hashable, Sendable, Identifiable {
    public let publisher: String
    public let name: String
    public let version: String
    public let displayName: String
    public let description: String
    public let categories: [String]
    public let kind: ExtensionKind
    public let license: String?
    public let homepage: String?
    public let repository: String?
    public let downloadURL: URL?
    public let engineRequirement: String?
    public var id: String { "\(publisher).\(name)" }
    public var identity: ExtensionIdentity { get }
    public init(publisher: String, name: String, version: String, displayName: String,
                description: String, categories: [String] = [], kind: ExtensionKind = .vscode,
                license: String? = nil, homepage: String? = nil, repository: String? = nil,
                downloadURL: URL? = nil, engineRequirement: String? = nil)
}

public struct InstalledExtension: Codable, Hashable, Sendable, Identifiable {
    public let metadata: ExtensionMetadata
    public var isEnabled: Bool
    public var state: ExtensionState
    public var installPath: String
    public var dependencies: [String]
    public var capabilities: [ExtensionCapability]
    public var lastError: String?
    public var updatedAt: Date
    public var id: String { metadata.id }
    public var identity: ExtensionIdentity { get }
    public init(metadata: ExtensionMetadata, isEnabled: Bool = true,
                state: ExtensionState = .installed, installPath: String,
                dependencies: [String] = [], capabilities: [ExtensionCapability] = [],
                lastError: String? = nil, updatedAt: Date = Date())
}

public struct ExtensionUpdateInfo: Hashable, Sendable, Identifiable {
    public let installed: InstalledExtension
    public let latest: ExtensionMetadata
    public var id: String { installed.id }
}

public struct ExtensionContributionCommand: Codable, Hashable, Sendable {
    public let command: String
    public let title: String
    public init(command: String, title: String)
}

public struct ExtensionContributionView: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String)
}

public struct ExtensionTreeItem: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let command: String?
    public init(id: String, label: String, description: String?, command: String?)
}

public struct ExtensionContribution: Codable, Sendable {
    public let commands: [ExtensionContributionCommand]
    public let views: [ExtensionContributionView]
    public let treeItems: [ExtensionTreeItem]
    public let statusBarText: String?
    public let outputLines: [String]
    public let webviewHTML: String?
    public init(commands: [ExtensionContributionCommand] = [], views: [ExtensionContributionView] = [],
                treeItems: [ExtensionTreeItem] = [], statusBarText: String? = nil,
                outputLines: [String] = [], webviewHTML: String? = nil)
    public static let empty: ExtensionContribution
}
```

### 10.3 Manifests, versions, compatibility

```swift
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let original: String
    public var description: String { original }
    public init?(string: String)   // §2.1.1: trims, strips leading "v", drops "-..." suffix
    public init(major: Int, minor: Int, patch: Int)
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool
    public func satisfies(engineRequirement requirement: String) -> Bool  // §2.1.1
}

public enum ExtensionAPILevel: String, Codable, Sendable {
    case supported, partial, unsupported
    public var displayName: String
}

public enum VSCodeAPI {
    public static let hostEngineVersion: SemanticVersion  // 1.85.0
    public static let matrix: [String: ExtensionAPILevel]  // §7.5, verbatim
    public static func level(for api: String) -> ExtensionAPILevel  // unknown -> .unsupported
    public static let unsupportedAPIs: [String]  // §9.2 list
}

public struct CompatibilityReport: Sendable {
    public let compatible: Bool
    public let reasons: [String]
    public let engineRequirement: String?
    public let unsupportedAPIs: [String]
    public init(compatible: Bool, reasons: [String], engineRequirement: String?, unsupportedAPIs: [String])
}

public enum Compatibility {
    public static func evaluate(manifest: VSCodeManifest) -> CompatibilityReport  // §2.1.2
}

// VS Code package.json model (decoded form; field names are the JSON keys)
public struct VSCodeCommand: Codable, Hashable, Sendable {
    public let command: String
    public let title: String
    public let category: String?
    public init(command: String, title: String, category: String? = nil)
}

public struct VSCodeView: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let when: String?
    public init(id: String, name: String, when: String? = nil)
}

public struct VSCodeManifest: Sendable {
    public let name: String
    public let publisher: String
    public let version: String
    public let displayName: String?
    public let description: String?
    public let enginesVscode: String?
    public let main: String?
    public let browser: String?
    public let activationEvents: [String]
    public let extensionDependencies: [String]
    public let extensionPack: [String]
    public let categories: [String]
    public let contributesCommands: [VSCodeCommand]
    public let contributesViews: [VSCodeView]
    public let configurationProperties: [String: ConfigurationProperty]
    public let declaredAPIs: [String]
    public var identity: ExtensionIdentity { get }
    public var metadata: ExtensionMetadata { get }
    public var allDependencies: [String] { extensionDependencies + extensionPack }
}

public struct ConfigurationProperty: Codable, Hashable, Sendable {
    public let type: String?
    public let defaultValue: JSONValue?   // JSON key "default"
    public let description: String?
}

public enum VSCodeManifestParser {
    public static func parse(data: Data) throws -> VSCodeManifest  // §2.1
    public static func parseFile(at url: URL) throws -> VSCodeManifest
    public static func isUnsafeRelativePath(_ path: String) -> Bool  // absolute or ".." segment
}

// SwiftCode swiftcode.json model (field names are the JSON keys)
public struct SwiftCodeManifest: Codable, Equatable, Hashable, Sendable {
    public var manifestVersion: Int       // 1
    public var id: String                 // reverse-DNS
    public var name: String
    public var version: String            // semver
    public var description: String?
    public var type: String               // "extension" | "application"
    public var runtime: ManifestRuntime   // {language: "typescript", entrypoint, minimumSwiftCodeVersion}
    public var sdk: ManifestSDKRef        // {name: "@swiftcode/sdk", versionRange, protocolVersion: 1}
    public var capabilities: [ManifestCapability]  // {id, reason}
    public var contributes: ManifestContributions? // {commands: [{id, title}]}
    public var assist: ManifestAssist     // {requested: Bool}, default false
    public var unknownFields: [String: JSONValue]  // preserved, never dropped
}

public struct ManifestDiagnostic: Identifiable, Equatable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable { case error, warning, info }
    public let id: String
    public let severity: Severity
    public let field: String
    public let message: String
    public let suggestion: String
    public let line: Int?
}

public enum SwiftCodeManifestValidator {
    // Strict validator (§2.3). Limits: manifest <= 64 KiB; id <= 128 chars,
    // lowercase reverse-DNS; version semver (prerelease allowed), <= 32 chars;
    // entrypoint <= 512 chars, relative, no "..", no empty segments;
    // SDK range whitelist for host SDK 1.2.0; capabilities <= 32, commands <= 64.
    public static var supportedCapabilities: Set<String> { get }  // 35 SDK ids + 6 use.Security.* scopes
    public static func validate(data: Data) throws -> SwiftCodeManifest
    public static func validateWithDiagnostics(data: Data, projectRoot: URL? = nil,
                                               grantedCapabilities: Set<String>? = nil) -> [ManifestDiagnostic]
    public static func isSDKRangeCompatible(_ range: String) -> Bool
}
```

### 10.4 Capabilities, permissions, storage, diagnostics

```swift
public enum ExtensionCapability: String, Codable, Sendable, CaseIterable {
    case workspaceRead, workspaceWrite, outsideWorkspace, network, terminal, process
    case secrets, sourceControl, build, assistTools, projectConfig, webview
    public var displayName: String { get }  // §5.1 table
}

public enum SDKCapabilityID: String, Codable, Sendable, CaseIterable {
    // 35 ids, verbatim raw values (§5.1). Never normalised or re-cased.
    case projectRead = "project.read"
    case workspaceRead = "workspace.read"
    case workspaceWrite = "workspace.write"
    case sourceControlRead = "source-control.read"
    case sourceControlWrite = "source-control.write"
    case buildExecute = "build.execute"
    case taskExecute = "task.execute"
    case networkRequest = "network.request"
    case uiContribute = "ui.contribute"
    case credentialsUse = "credentials.use"
    case useSecurity = "use.Security"
    case assistInvoke = "assist.invoke"
    case assistUI = "assist.ui"
    case assistHeadless = "assist.headless"
    case assistMainView = "assist.main"
    case dbExploreView = "db.ExploreView"
    case ciVisualWF = "ci.VisualWF"
    case sandboxView = "sandbox.view"
    case virtualizationView = "virtualization.view"
    case deployConsoleView = "deployConsole.view"
    case useSwiftCodeModel = "use.SwiftCodeModel"
    case terminalSandbox = "terminal.sandbox"
    case simulatorView = "simulator.view"
    case previewLive = "preview.live"
    case uiBuilderOpen = "uibuilder.open"
    case symbolsBrowse = "symbols.browse"
    case docsSearch = "docs.search"
    case dictionaryOpen = "dictionary.open"
    case deviceConnectOpen = "deviceconnect.open"
    case securityAddValue = "security.addValue"
    case securityHasValue = "security.hasValue"
    case securityListValueIDs = "security.listValueIDs"
    case securityDeleteValue = "security.deleteValue"
    case securityUseValue = "security.useValue"
    public var riskLevel: String { "low" / "medium" / "high" }  // §5.1
    public var isGrantable: Bool { get }  // false only for assistInvoke
}

public struct PermissionRequest: Sendable {
    public let extensionId: String
    public let capability: ExtensionCapability
    public let reason: String
}

public final class PermissionManager: @unchecked Sendable {
    public var promptHandler: (@Sendable (PermissionRequest) async -> Bool)?
    public init(storage: ExtensionStorage = ExtensionStorage())
    public init(grants: [String: Set<ExtensionCapability>])  // test variant; temp-dir storage
    public func isGranted(extensionId: String, capability: ExtensionCapability) -> Bool
    public func grantedCapabilities(for extensionId: String) -> [ExtensionCapability]
    public func check(extensionId: String, capability: ExtensionCapability) throws
    public func request(extensionId: String, capability: ExtensionCapability, reason: String) async -> Bool
    public func grant(extensionId: String, capability: ExtensionCapability)
    public func revoke(extensionId: String, capability: ExtensionCapability)
    public func revokeAll(for extensionId: String)
    // Deny-by-default; no promptHandler -> request returns false.
}

public struct ExtensionSettings: Codable, Sendable {
    public var registryBaseURL: String   // default "https://open-vsx.org/api"
    public var autoUpdate: Bool          // default false
    public var nodeExecutablePath: String?
    public var allowPrerelease: Bool     // default false
    public init(registryBaseURL: String = "https://open-vsx.org/api", autoUpdate: Bool = false,
                nodeExecutablePath: String? = nil, allowPrerelease: Bool = false)
}

public struct ExtensionStorage: Sendable {
    public let root: URL  // default: ~/Library/Application Support/SwiftCode/ExtensionsV2
    public init(root: URL? = nil)
    public var installedFile: URL { root/"installed.json" }
    public var grantsFile: URL { root/"grants.json" }
    public var settingsFile: URL { root/"settings.json" }
    public var diagnosticsFile: URL { root/"diagnostics.jsonl" }
    public var extensionsDirectory: URL { root/"extensions" }
    public var stagingDirectory: URL { root/"staging" }
    public var backupsDirectory: URL { root/"backups" }
    public func ensureDirectories() throws
    public func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws
    public func loadInstalled() -> [InstalledExtension]       // missing/corrupt -> []
    public func saveInstalled(_ installed: [InstalledExtension]) throws
    public func loadSettings() -> ExtensionSettings           // missing/corrupt -> defaults
    public func saveSettings(_ settings: ExtensionSettings) throws
    public func appendDiagnosticsLine(_ line: String)         // never throws
    public func cleanStaleStaging()                           // removes all staging entries
}

public enum DiagnosticLevel: String, Codable, Sendable { case info, warning, error }

public struct DiagnosticEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let extensionId: String?
    public let level: DiagnosticLevel
    public let message: String
}

public final class DiagnosticsService: @unchecked Sendable {
    public static let shared: DiagnosticsService
    public func log(extensionId: String? = nil, level: DiagnosticLevel, message: String)
    public func info(_ message: String, extensionId: String? = nil)
    public func warning(_ message: String, extensionId: String? = nil)
    public func error(_ message: String, extensionId: String? = nil)
    public func allEntries() -> [DiagnosticEntry]            // in-memory cap: 2000, oldest dropped
    public func entries(for extensionId: String) -> [DiagnosticEntry]
    public func clear()
    public func exportReport() -> String  // "[ISO8601] [level] <id>: <message>" per line
}
```

### 10.5 RPC, host, registry, packages, dependencies

```swift
public enum JSONValue: Codable, Hashable, Sendable {
    case null, bool(Bool), int(Int), double(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])
    public var stringValue: String? { get }
    public var intValue: Int? { get }
    public var arrayValue: [JSONValue]? { get }
    public var objectValue: [String: JSONValue]? { get }
    public static func stringDictionary(_ dict: [String: String]) -> JSONValue
}

public struct RPCRequest: Codable, Sendable {
    public static let protocolVersion: Int  // 1
    public let jsonrpc: String              // "2.0"
    public let protocolVersion: Int
    public let id: String
    public let method: String
    public let params: JSONValue?
    public init(id: String, method: String, params: JSONValue? = nil)
}

public struct RPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let result: JSONValue?
    public let error: RPCErrorPayload?
    public init(id: String, result: JSONValue? = nil, error: RPCErrorPayload? = nil)
}

public struct RPCErrorPayload: Codable, Sendable {
    public let code: Int
    public let message: String
}

public enum ExtensionRPC {
    public static let allowedHostMethods: Set<String>       // 20 host.* methods, §4.3
    public static let allowedHostMethodsSwiftCode: Set<String>  // 6 methods, §4.3 (name: allowedSwiftCodeMethods)
    public static func decodeRequest(from line: Data, fromHost: Bool) throws -> RPCRequest
    public static func encodeRequest(_ request: RPCRequest) throws -> Data   // + trailing \n
    public static func encodeResponse(_ response: RPCResponse) throws -> Data
    // decodeRequest rejects: line > 1 MiB, protocolVersion != 1, method not in the
    // direction's allowlist. Error code for host replies: -32000; host fatal: -32001.
}

public enum ResourceLimits {
    public static let maxVSIXBytes: Int            // 64 MiB (unified; see §4.6 / D-1)
    public static let maxExtractedBytes: Int       // 512 MiB (unified)
    public static let maxArchiveEntries: Int       // 20,000 (unified)
    public static let maxIPCMessageBytes: Int      // 1 MiB
    public static let hostActivationTimeout: TimeInterval  // 30s
    public static let hostCommandTimeout: TimeInterval     // 60s
    public static let registryTimeout: TimeInterval        // 30s
    public static let maxConsecutiveHostCrashes: Int       // 3
}

@MainActor
public final class ExtensionHostManager {
    public var storage: ExtensionStorage
    public var permissions: PermissionManager
    public var hostRequestHandler: ((String, RPCRequest) async throws -> JSONValue)?
    public init(storage: ExtensionStorage, permissions: PermissionManager)
    public func nodeExecutable(settings: ExtensionSettings) -> URL?
    // Order: settings.nodeExecutablePath, /opt/homebrew/bin/node,
    // /usr/local/bin/node, /usr/bin/node; then PATH lookup. Nil -> host error (§4.2).
    public func activate(installed: InstalledExtension, workspaceRoot: URL?,
                         settings: ExtensionSettings) async throws -> ExtensionContribution
    public func executeCommand(extensionId: String, command: String,
                               args: [JSONValue] = []) async throws -> JSONValue
    public func ownerOfCommand(_ command: String) -> String?
    public func isRunning(extensionId: String) -> Bool
    public func contribution(for extensionId: String) -> ExtensionContribution?
    public func deactivate(extensionId: String)
    public func shutdownAll()
    // Spawn: node <root>/host/extension-host.js --extension-entry <entry>
    // (host script is a bundled resource; see §4.4). Activation refused while
    // consecutiveCrashes >= 3. Successful activation resets the counter.
}

public enum HostScript {
    public static let source: String  // the Node host script text (bundled resource content)
    public static func hostScriptURL(storage: ExtensionStorage) -> URL  // <root>/host/extension-host.js
    public static func ensureHostScript(storage: ExtensionStorage) throws -> URL
}

public struct SearchPage: Sendable {
    public let results: [ExtensionMetadata]
    public let total: Int
    public let offset: Int
    public let pageSize: Int
    public var hasMore: Bool { offset + results.count < total }
}

public final class RegistryClient: Sendable {
    public init(baseURL: URL)
    public convenience init(settings: ExtensionSettings)
    public func search(query: String, offset: Int = 0, pageSize: Int = 20) async throws -> SearchPage
    public func details(for identity: ExtensionIdentity) async throws -> ExtensionMetadata
    public func downloadURL(for metadata: ExtensionMetadata) async throws -> URL
    public func downloadVSIX(from url: URL, to destination: URL) async throws
    // Endpoints (§6.1): GET {base}/-/search?query&size&offset;
    // GET {base}/{publisher}/{name}; download via files.download else
    // {base}/{publisher}/{name}/{version}/file/{publisher}.{name}-{version}.vsix.
    // No auth. 404 -> "Extension not found in the registry."
}

public struct InstalledPackage: Sendable {
    public let directory: URL
    public let manifest: VSCodeManifest
    public let compatibility: CompatibilityReport
    public init(directory: URL, manifest: VSCodeManifest, compatibility: CompatibilityReport)
}

public struct PackageService: Sendable {
    public enum Limits {
        public static let maxArchiveBytes: Int64     // 64 MiB
        public static let maxExtractedBytes: Int64   // 512 MiB
        public static let maxEntries: Int            // 20,000
        public static let maxRelativePathLength: Int // 512
    }
    public let storage: ExtensionStorage
    public init(storage: ExtensionStorage)
    public func installDirectory(for extensionId: String) -> URL
    public func backupDirectory(for extensionId: String) -> URL
    public func install(vsixURL: URL, identity: ExtensionIdentity) throws -> InstalledPackage  // §6.3
    public func uninstall(extensionId: String) throws  // idempotent
    public static func validate(extensionId: String) throws  // charset/length rules, §6.3
}

public struct DependencyResolution: Sendable {
    public let installOrder: [String]
    public let missing: [String]
    public let cycles: [[String]]
    public var isSatisfied: Bool { missing.isEmpty && cycles.isEmpty }
}

public enum DependencyResolver {
    public static func resolve(requested: [VSCodeManifest], installedIDs: Set<String>,
                               manifestsByID: [String: VSCodeManifest]) -> DependencyResolution
    public static func missingDependencies(for installed: InstalledExtension,
                                           installedByID: [String: InstalledExtension]) -> [String]
}
```

### 10.6 Manager — the public entry points for MCP and UI

```swift
@MainActor
public final class ExtensionManager {
    public static let shared: ExtensionManager
    public let storage: ExtensionStorage
    public let permissions: PermissionManager
    public let hostManager: ExtensionHostManager
    public let packageService: PackageService
    public let diagnostics: DiagnosticsService
    public private(set) var installed: [InstalledExtension]     // sorted by displayName
    public private(set) var searchResults: [ExtensionMetadata]
    public private(set) var searchError: String?
    public private(set) var isSearching: Bool
    public private(set) var installingIDs: Set<String>
    public private(set) var updates: [ExtensionUpdateInfo]
    public private(set) var contributions: [String: ExtensionContribution]
    public private(set) var isReady: Bool
    public var settings: ExtensionSettings
    public var workspaceRoot: URL?
    public var workspaceBridge: WorkspaceBridge? { get }  // nil when no workspace is open
    public init()
    public func ensureReady() async        // first-load disk work; later calls no-op
    public func saveSettings()
    public func setWorkspaceRoot(_ url: URL?)
    public func refreshInstalled()         // §3.3 evaluation order
    public func search(query: String)      // debounced; empty query clears
    public func loadMoreSearchResults()
    public func install(metadata: ExtensionMetadata) async throws
    public func uninstall(extensionId: String) async
    public func setEnabled(extensionId: String, enabled: Bool)
    public func checkUpdates() async       // VS Code-kind records only
    public func activate(extensionId: String) async throws -> ExtensionContribution
    public func deactivate(extensionId: String)
    public func executeCommand(extensionId: String, command: String,
                               args: [JSONValue] = []) async throws -> String
    public func registerSamplePlugin()
}
```

The MCP `use_extension` handler (in `SwiftCodeMCP`, **not** in this
target) calls exactly these entry points plus
`permissions.grantedCapabilities(for:)`,
`diagnostics.entries(for:)`, the Xcode registry (§10.8), and the
native registry (§10.7). It must implement the §7.2 contract
(actions, confirm rule, limit clamping, 8,000-char cap, error
mapping) and the §5.4 `approve()` gate. `use_extension` stays
registered in `SwiftCodeTools+Terminal.swift` with its existing schema;
only the handler body changes from honestly-failing to real.

### 10.7 Native plugins, Assist bridge, providers

```swift
public struct NativePluginManifest: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let commands: [ExtensionContributionCommand]
    public let capabilities: [ExtensionCapability]
    public init(id: String, name: String, version: String, description: String,
                commands: [ExtensionContributionCommand] = [], capabilities: [ExtensionCapability] = [])
    public var metadata: ExtensionMetadata { get }  // publisher "swiftcode", kind .native
}

public struct NativePluginContext: Sendable {
    public let manifest: NativePluginManifest
    public let workspaceRoot: URL?
    public let workspace: WorkspaceBridge?
    public let permissions: PermissionManager
    public let registerCommand: @Sendable (String, @escaping @Sendable ([JSONValue]) async throws -> JSONValue) -> Void
}

public protocol NativePlugin: Sendable {
    static var manifest: NativePluginManifest { get }
    init()
    func activate(context: NativePluginContext) async throws
    func deactivate() async   // default no-op
}

@MainActor
public final class NativePluginRegistry {
    public static let shared: NativePluginRegistry
    public static func registerCommand(_ id: String,
        handler: @escaping @Sendable ([JSONValue]) async throws -> JSONValue)
    public static func handler(for id: String) -> (@Sendable ([JSONValue]) async throws -> JSONValue)?
    public private(set) var manifests: [NativePluginManifest]
    public func register<Plugin: NativePlugin>(_ type: Plugin.Type)
    public func activateAll(workspaceRoot: URL?, workspace: WorkspaceBridge?,
                            permissions: PermissionManager) async
    public func executeCommand(_ command: String, args: [JSONValue] = []) async throws -> JSONValue
    public func contribution(for manifest: NativePluginManifest) -> ExtensionContribution
}

public struct SamplePlugin: NativePlugin {
    // id "sample.workspace-lister", command "extv2.sample.listWorkspace",
    // capability [.workspaceRead]; see §7.3.
    public static let manifest: NativePluginManifest
    public init()
    public func activate(context: NativePluginContext) async throws
}

public struct AssistCapabilityDescriptor: Sendable {
    public let toolId: String
    public let name: String
    public let description: String
    public let parameters: [String: String]   // name -> "string" | "number" | "boolean"
    public let requiredParameters: [String]
    public let extensionId: String
    public let command: String
    public let requiredCapabilities: [ExtensionCapability]
    public let isReadOnly: Bool
    public init(toolId: String, name: String, description: String,
                parameters: [String: String] = [:], requiredParameters: [String] = [],
                extensionId: String, command: String,
                requiredCapabilities: [ExtensionCapability] = [], isReadOnly: Bool = true)
    public func validate(input: [String: Any]) throws
}

public enum AssistBridge {
    public static func toolId(for extensionId: String, command: String) -> String
    // "extv2." + (extensionId + "." + command), non [A-Za-z0-9.] -> "_"
    public static func descriptor(for command: ExtensionContributionCommand, extensionId: String,
                                  requiredCapabilities: [ExtensionCapability] = [],
                                  isReadOnly: Bool = true) -> AssistCapabilityDescriptor
    @MainActor
    public static func register(_ descriptor: AssistCapabilityDescriptor,
                                permissions: PermissionManager) -> Bool
    // False (and a diagnostics warning) when .assistTools is not granted.
}

// Provider registrations the editor consults (completion/hover/diagnostics only)
public struct ExtensionDiagnostic: Codable, Hashable, Sendable {
    public let relativePath: String
    public let range: TextRange
    public let message: String
    public let severity: String
    public let source: String
}

@MainActor
public final class ProviderRegistry {
    public static let shared: ProviderRegistry
    public private(set) var diagnostics: [String: [ExtensionDiagnostic]]
    public private(set) var completionProviders: [String: String]  // language -> extensionId
    public private(set) var hoverProviders: [String: String]
    public func publishDiagnostics(extensionId: String, relativePath: String,
                                   diagnostics: [ExtensionDiagnostic])
    public func registerCompletionProvider(extensionId: String, language: String)
    public func registerHoverProvider(extensionId: String, language: String)
    public func clear(for extensionId: String)
}
```

### 10.8 Text, workspace, Xcode commands

```swift
public struct TextPosition: Codable, Hashable, Sendable {
    public let line: Int
    public let character: Int
    public init(line: Int, character: Int)
}

public struct TextRange: Codable, Hashable, Sendable {
    public let start: TextPosition
    public let end: TextPosition
    public init(start: TextPosition, end: TextPosition)
}

public struct TextEdit: Codable, Hashable, Sendable {
    public let range: TextRange
    public let newText: String
    public init(range: TextRange, newText: String)
}

public struct DocumentState: Sendable {
    public let relativePath: String
    public let content: String
    public let selection: Range<Int>?
}

public protocol DocumentStore: Sendable {
    func read(relativePath: String) throws -> String
    func write(relativePath: String, content: String) throws
}

public struct FileDocumentStore: DocumentStore {
    public init(workspace: WorkspaceBridge, extensionId: String)
    public func read(relativePath: String) throws -> String
    public func write(relativePath: String, content: String) throws
}

public enum EditorBridge {
    // Lines/characters 0-based; characters are Swift Characters (grapheme clusters).
    // Overlapping edits rejected; out-of-range rejected; reverse-order application.
    public static func applyEdits(_ edits: [TextEdit], to content: String) throws -> String
    public static func offset(for position: TextPosition, in content: String) -> Int?
}

public struct WorkspaceFile: Sendable {
    public let relativePath: String
    public let isDirectory: Bool
}

public final class WorkspaceBridge: Sendable {
    public let root: URL
    public init(root: URL, permissions: PermissionManager)
    public func resolvedPath(for relativePath: String, extensionId: String) throws -> URL
    public func listFiles(extensionId: String) throws -> [WorkspaceFile]  // cap 20,000
    public func readFile(relativePath: String, extensionId: String) throws -> String
    public func writeFile(relativePath: String, content: String, extensionId: String) throws
    public func gitStatus(extensionId: String) throws -> String  // /usr/bin/git status --short
}

// Xcode source-editor compatibility
public struct SourcePosition: Codable, Hashable, Sendable, Comparable {
    public let line: Int
    public let column: Int
    public init(line: Int, column: Int)
    public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool
}

public struct SourceRange: Codable, Hashable, Sendable {
    public let start: SourcePosition
    public let end: SourcePosition
    public init(start: SourcePosition, end: SourcePosition)
    public var isEmpty: Bool { start == end }
}

public final class SourceTextBuffer: @unchecked Sendable {
    public var selections: [SourceRange]
    public init(lines: [String], selections: [SourceRange] = [])
    public convenience init(text: String, selections: [SourceRange] = [])
    public var lines: [String] { get }
    public var completeBuffer: String { lines.joined(separator: "\n") }
    public struct Edit: Sendable {
        public let range: SourceRange
        public let newText: String
        public init(range: SourceRange, newText: String)
    }
    public func applyEdits(_ edits: [Edit]) throws  // validate-all-then-apply; atomic
}

public struct SourceEditorInvocation: Sendable {
    public let buffer: SourceTextBuffer
    public let commandIdentifier: String
    public let uti: String   // default "public.swift-source"
    public init(buffer: SourceTextBuffer, commandIdentifier: String, uti: String = "public.swift-source")
    public func checkCancellation() throws
}

public protocol SourceEditorCommand: Sendable {
    var identifier: String { get }
    var title: String { get }
    func perform(invocation: SourceEditorInvocation) async throws
}

public final class XcodeCommandRegistry: @unchecked Sendable {
    public static let shared: XcodeCommandRegistry
    public func register(_ command: any SourceEditorCommand)
    public func command(for identifier: String) -> (any SourceEditorCommand)?
    public var allIdentifiers: [String] { get }  // sorted
    public func perform(identifier: String, buffer: SourceTextBuffer) async throws
}

public struct SortLinesCommand: SourceEditorCommand {
    public let identifier: String  // "com.swiftcode.xcode.sortLines"
    public let title: String       // "Sort Lines"
    public init()
    public func perform(invocation: SourceEditorInvocation) async throws
}
```

### 10.9 What is NOT in the public API (deliberately)

- No `ExtV2LanguageClient` equivalent — use `SwiftCodeLanguage.LSPClient`.
- No SDK event-envelope IPC, no `adapter.js` resolution, no
  `SDKRuntimeSession` state machine as a public type.
- No `ExtensionValidator` (lenient) — only the strict
  `SwiftCodeManifestValidator`.
- No `ExtensionPackager` / `.swiftcode-extension` install API in this
  wave (authoring tooling; validation rules are in §10.3).
- No `ExtV2TestSuite` equivalent as a type — its cases become
  `SwiftCodeExtensionsTests` XCTest cases (§11).
- No UI types in this target. The UI slice owns the toolbar button,
  home/search/installed/details/permissions/settings/diagnostics/
  updates/run views, and the approval prompt handler wiring.
- No secrets API. No Keychain access. No `SecretStore` dependency.

### 10.10 Target wiring (`Package.swift` — the SwiftCodeGitHub model)

Follow the Wave 10 `SwiftCodeGitHub` pattern exactly:

```swift
.library(name: "SwiftCodeExtensions", targets: ["SwiftCodeExtensions"]),
// ...
.target(name: "SwiftCodeExtensions"),   // no third-party dependencies in this wave
.testTarget(name: "SwiftCodeExtensionsTests", dependencies: ["SwiftCodeExtensions"]),
```

- `SwiftCodeMCP` gains `"SwiftCodeExtensions"` in its dependencies (same
  position as `SwiftCodeGitHub` in the `SwiftCodeMCP` target declaration) so
  the `use_extension` handler can call the manager.
- `SwiftCodeUI` gains `"SwiftCodeExtensions"` in its dependencies for the
  toolbar button and Extensions views (later slice).
- The host script (`extension-host.js`) ships as a target resource
  (`.copy("Resources/extension-host.js")` or equivalent); its
  behaviour is §4.4. It must be treated as data: the implementation
  slice writes it from this spec's behaviour, it does not copy
  Legacy's file.
- ZIP reading: Legacy uses ZIPFoundation (a Legacy dependency SwiftCode
  does not have). The implementation slice must choose the mechanism
  (Foundation `Archive` is unavailable on Linux; a minimal ZIP reader
  or a new dependency) and record the choice — this spec does not
  prescribe it, because no SwiftCode ZIP facility was verified in this
  pass. **UNVERIFIED**: whether SwiftCode already has a ZIP reader
  anywhere in `swiftcode/` or `frameworks/`.

## 11. What is NOT in this wave (explicitly)

1. **The 28 `Views/Settings/Extension Management/` demo views**
   (per-extension settings UI for built-in Legacy v1 demos:
   `AIDocGen`, `AIRefactor`, `CodeStats`, `ColorPicker`,
   `CreateExtension`, `DarkProTheme`, `DocCGenerator`,
   `EditExtension`, `ExtensionDemo`, `GitBlame`, `GoSupport`,
   `GruvboxTheme`, `JSONFormatter`, `KotlinSupport`,
   `MarkdownPreview`, `MultiCursor`, `NordTheme`, `PythonSupport`,
   `RegexTester`, `RustSupport`, `SnippetLibrary`,
   `SwiftFormatter`, `SwiftLintRunner`, `SwiftPackageManager`,
   `TodoHighlighter`, `TypeScriptSupport`, `UnitTestGen`,
   `XcodeBuildTool`) — out of scope. They belong to the dropped v1
   system; their settings UI is not ported, and their functionality
   (formatters, linters, themes, language support) is not re-created
   as demo extensions. A SwiftCode-native extensions settings UI is a
   later slice.
2. **`ExtV2TestSuite`** as a file — its 15 cases (version parsing,
   engine requirements, manifest parsing/rejection, compatibility,
   dependency resolution, editor edits incl. emoji/overlap, Xcode
   sort-lines + buffer safety, RPC round-trip/disallowed/oversize,
   permissions deny/grant/revoke, identity + Assist descriptor
   validation, `use_extension` validation, Xcode file round-trip,
   `use_extension` Xcode failures) are ported as **XCTest cases in
   `SwiftCodeExtensionsTests`**, not as an in-app self-test class.
   Registry download, package extraction, and host activation stay
   integration paths verified on Dylan's Mac.
3. **Anything requiring a remote marketplace endpoint that does not
   exist** — there is no SwiftCode marketplace endpoint; Open VSX is
   the only remote, and the local registry is the offline fallback
   (§6.2).
4. **The 11 `Views/Extensions v2/` Legacy views** (home, search,
   installed, details, permissions, settings, diagnostics, updates,
   run, sidebar row, view models) — not ported as code in this wave;
   the SwiftCode UI is rebuilt Mac-style in a later slice per the
   migration brief. Their *behaviour* (what each surface shows and
   which manager calls it makes) is specified in §3–§8 and is the
   input to that slice.
5. **Legacy `ExtensionManager` / `PluginManager` and
   `ExtensionMarketplaceView`** — dropped (§1.1). The marketplace
   view as written renders the v1 manager's flag-flipping list; it
   must not be ported.
6. **SDK runtime**: `adapter.js`, the event envelope,
   `SDKNodeLauncher`, `SDKIPCTransport`, `SDKRuntimeSession`,
   `SDKGrantStore`, the Capability Broker approval UI, the SDK Studio
   views — not ported. Only the `swiftcode.json` manifest shape, the
   strict validators, the package validator rules, and the capability
   id registry are taken from the SDK side.
7. **Webview rendering, terminal/debug/task contributions,
   activation-event dispatch, editor-undo integration, language
   providers beyond completion/hover registration** — specified as
   not-driven (§9.4).
8. **Signed-bundle loading for third-party native code** — explicitly
   out; untrusted code goes through the out-of-process host (§7.3).
9. **`.swiftcode-extension` install path** — specified (§2.4, §6.3)
   but not implemented in this wave; VSIX install is the path.

## 12. Evidence + deviations

### 12.1 Evidence levels for the main claims

| Claim | Level | Basis |
|---|---|---|
| Three kinds (vscode/native/xcodeCommand), states, identity `publisher.name` | 5 | `ExtV2Models.swift` verbatim |
| package.json required/optional keys, defaults, unsafe-`main` rule | 5 | `ExtV2ManifestParser.swift` verbatim |
| Semver parsing + requirement forms | 5 | `ExtV2Compatibility.swift` (`ExtV2Version`) verbatim |
| Host engine 1.85.0; compatibility rules incl. missing-engine → incompatible | 5 | `ExtV2Compatibility.swift` verbatim |
| API matrix rows + levels | 5 | `ExtV2Compatibility.swift` matrix verbatim |
| NDJSON JSON-RPC v1, both allowlists, 1 MiB cap, protocol-version check | 5 | `ExtV2RPC.swift` verbatim |
| One Node process per extension; spawn args; env stripping; crash counter ≥ 3 refusal | 5 | `ExtV2HostManager.swift` verbatim |
| Node discovery order; absent-Node error text | 5 | `ExtV2HostManager.swift` verbatim |
| Host script behaviour (shim surface, contribution collection, timeouts, exit codes) | 5 | `ExtV2HostScript.swift` verbatim (described, not reproduced) |
| Storage layout + file names + atomic writes + stale-staging cleanup | 5 | `ExtV2Storage.swift` verbatim |
| Grants deny-by-default, no-handler → false, atomic `grants.json` | 5 | `ExtV2PermissionManager.swift` verbatim |
| Open VSX endpoints, page size 20, download fallback, 404 text | 5 | `ExtV2RegistryClient.swift` verbatim |
| VSIX install pipeline (caps, path validation, symlink rejection, identity check, atomic commit, backup) | 5 | `ExtV2PackageService.swift` verbatim |
| Manager lifecycle + `refreshInstalled()` order + lenient unparseable-manifest → `.enabled` | 5 | `ExtV2Manager.swift` verbatim |
| Assist bridge tool-id scheme, defaults, `.assistTools` gate, ownership routing | 5 | `ExtV2AssistBridge.swift` verbatim |
| `use_extension` 11 actions, confirm rule, limits, error mapping, per-action behaviour | 5 | `UseExtensionTool.swift` verbatim |
| Native plugin protocol/registry/trust boundary; sample plugin | 5 | `ExtV2NativeSDK.swift`, `ExtV2SamplePlugin.swift` verbatim |
| Xcode buffer/registry/sort-lines | 5 | `ExtV2XcodeCompatibility.swift` verbatim |
| Workspace bridge containment + capability checks + git status | 5 | `ExtV2WorkspaceBridge.swift` verbatim |
| Editor bridge edit semantics + undo limit | 5 | `ExtV2EditorBridge.swift` verbatim |
| LSP client methods, framing, 30s timeout | 5 | `ExtV2LanguageClient.swift` verbatim |
| Diagnostics cap 2000, JSONL append, never-throw | 5 | `ExtV2Diagnostics.swift` verbatim |
| Dependency resolver (topological order, missing, cycles) | 5 | `ExtV2DependencyResolver.swift` verbatim |
| `swiftcode.json` fields + defaults | 5 | `ExtensionManifest.swift`, `SDKManifest.swift` verbatim |
| Strict validator limits + rules | 5 | `SDKManifestValidator.swift` verbatim |
| Lenient validator rules | 5 | `ExtensionValidator.swift` verbatim |
| SDK capability ids (35) + risk levels + `assist.invoke` not grantable | 5 | `ExtensionCapability.swift`, `SDKCapability.swift` verbatim |
| SDK registry roots, `.sdk-install.json`, digest, versioned dirs | 5 | `SDKExtensionRegistry.swift` verbatim |
| SDK manager root `~/.swiftcode/extensions`, `.host-state.json`, tamper quarantine, backoff restarts | 5 | `SDKExtensionManager.swift` verbatim |
| SDK grant store path + 0600 mode | 5 | `SDKGrantStore.swift` verbatim |
| Packager zip invocation, SHA-256, `fileCount: 1` | 5 | `ExtensionPackager.swift` verbatim |
| Package validator bounds (100 MB, 10k, 255, depth 40, executable set declared) | 4 | `SDKPackageValidator.swift` (header + entry point + walk excerpt) |
| Legacy v1 manager: Documents/Extensions, 25 built-ins, flag-only download | 5 | `ExtensionManager.swift` verbatim |
| PluginManager: Documents/Plugins, `plugin.json`, no execution | 5 | `PluginManager.swift` verbatim |
| Marketplace view renders v1 list only | 5 | `ExtensionMarketplaceView.swift` verbatim |
| Extensions on editor toolbar beside Assist, not sidebar | 4 | `Docs/Extensions-v2.md` + task brief (the doc's sidebar history) |
| SwiftCode `use_extension` registered, handler honestly failing | 5 | `SwiftCodeTools+Terminal.swift` lines ~224, ~606 |
| SwiftCode approval gate `commit()`/`approve()`, single gate, no Autopilot | 5 | `specs/ide/assist-approval-model.md` + `MCPServer.swift` (`MCPChange`, `rejectedMessage`) |
| SwiftCode LSP client exists (sourcekit-lsp-oriented) | 4 | `SwiftCodeLanguage/LSPClient.swift`, `BuildServerLaunch.swift` (headers + structure) |
| SwiftCode subprocess primitives for the host runner | 4 | `SwiftCodeSubprocess/Subprocess.swift`, `StreamingSubprocess.swift` (signatures) |
| SwiftCodeGitHub target model for `Package.swift` wiring | 5 | `swiftcode/Package.swift` (product/target/testTarget + `SwiftCodeMCP`/`SwiftCodeUI` deps) |
| `host.applyEdit` shape mismatch between shim and Swift handler | 5 | Compared `ExtV2HostScript.swift` (`{edit}`) vs `ExtV2Manager.swift` (`{path, edits}`) |
| `didChangeTextDocument` / `didChangeConfiguration` have no sender | 3 | Allowlisted in `ExtV2RPC.swift`; no sender found in the v2 files read |
| `ExtV2DocumentDidChange` has no sender | 3 | Declared in `ExtV2WorkspaceBridge.swift`; no sender found in the v2 files read |
| `$/cancelRequest` is not sent by the LSP client | 3 | Mentioned in `ExtV2LanguageClient.swift` header; no send found in its code |
| No UI path found for the manual host-retry after 3 crashes | 2 | `ExtV2HostManager.swift` refuses activation; no retry affordance in the files read |
| Whether SwiftCode has a ZIP reader usable by the package service | 1 | Not checked in this pass — implementation slice must confirm |

### 12.2 Deviations table (Legacy behaviour → SwiftCode port, with reasons)

| # | Legacy behaviour | SwiftCode port | Reason |
|---|---|---|---|
| D-1 | Two VSIX limit sets: `ExtV2ResourceLimits` (200 MB / 1 GB / 10,000 entries) vs `ExtV2PackageService.Limits` (64 MB / 512 MB / 20,000 entries); download allows 200 MB, install rejects > 64 MB | One set everywhere: 64 MB / 512 MB / 20,000 entries (the enforced set) | A download that always fails at install is a bug, not a contract |
| D-2 | Three storage roots: `ExtensionsV2/`, `~/.swiftcode/extensions`, `~/Library/Application Support/SwiftCode/Extensions`; two grant stores (`grants.json`, `SDKGrants.json`) | One root: `~/Library/Application Support/SwiftCode/ExtensionsV2/`; one grant store (`grants.json`), adopting the SDK store's `0600` file mode | One platform, one source of truth; the SDK roots belong to the unported SDK host |
| D-3 | Two extension hosts: v2 Node host (JSON-RPC) + SDK host (adapter.js, event envelope) | One host: the v2 Node host + JSON-RPC wire protocol | Two hosts would double the trust surface and the maintenance; the SDK runtime is a separate platform, not a second host for the same extensions |
| D-4 | Two crash policies: v2 stops after 3 consecutive crashes until manual retry; SDK restarts with 2/4/8s backoff (cap 30s) then quarantines | v2 policy (stop after 3, manual retry) | Simpler, no restart loops, matches the user-visible rule; SDK quarantine-on-tamper is kept as a concept for the digest check if the implementation slice adds it |
| D-5 | Two `swiftcode.json` validators with conflicting strictness | Strict validator (`SDKManifestValidator`) as the install gate | The lenient validator accepts manifests the strict one rejects (uppercase ids, 2-part versions, missing reasons); install-time must be the strict one |
| D-6 | `ExtV2Version` accepts 1- and 2-part versions; strict `swiftcode.json` validator requires full semver | Kept per format: lenient parsing for `package.json` engine checks, strict semver for `swiftcode.json` | The formats have different authors and different contracts; unifying would break VS Code compatibility |
| D-7 | Command-id pattern differs: strict validator `^[a-z][a-z0-9.-]{0,63}$` vs JSON schema `^[a-z0-9-]+$` (no dots) | Validator governs | The validator is executable; the schema is documentation |
| D-8 | `additionalProperties: false` in the JSON schema vs `unknownFields` preservation in `SDKManifest` | Validator governs: unknown fields preserved | Dropping author data on visual edit is data loss; the schema is documentation |
| D-9 | Host shim sends `host.applyEdit` as `{edit}`; Swift handler expects `{path, edits: [...]}` | Shim sends `{path, edits}` (the handler's shape) | The handler's shape carries the path and the edit list the bridge needs; the shim's shape cannot be served |
| D-10 | Assist-bridge path encodes args as `"key=value"` strings; `use_extension` sends one JSON object | Object form everywhere | Named arguments must arrive intact; `key=value` loses types and breaks on `=` in values |
| D-11 | API matrix lists `window.withProgress` as partial, but the shim rejects it as unsupported | Matrix row stays `partial`; shim behaviour (reject with descriptive error) is the contract until a progress UI exists | The matrix is aspirational here; the implemented behaviour is the reject |
| D-12 | `ExtV2Manager.refreshInstalled()`: unparseable installed manifest → `.enabled` (lenient fallback) | Kept as specified in §3.3, flagged for the implementation slice to confirm | Changing it would alter install-state semantics; it is recorded, not silently fixed |
| D-13 | Provider registry: diagnostics replace per path across extensions; completion/hover last-wins per language | Kept as specified in §8.4 | Observed behaviour; changing merge semantics is a product decision for a later slice |
| D-14 | SDK capability ids map to v2 capabilities for enforcement (§5.3) | SwiftCode mapping table | Legacy never maps them (the two systems never meet); the port needs one enforcement point |
| D-15 | Legacy `AssistPermissionsManager` defaults to Autopilot (bypasses restrictions) | Rejected; Wave 2 gate only (§5.4) | Autopilot-by-default was already rejected by the Wave 2 spec |
| D-16 | Legacy `ExtV2Manager` is `@MainActor` + SwiftUI (`ObservableObject`, `@Published`) | `ExtensionManager` is `@MainActor`; the target itself has no SwiftUI dependency — publishing is the UI slice's job (via observation of the manager or a view model in `SwiftCodeUI`) | SwiftPM target must stay UI-free and Linux-buildable where possible; SwiftUI lives in `SwiftCodeUI` |
| D-17 | Legacy names carry the `ExtV2` prefix | SwiftCode names use the `SwiftCode` prefix / plain names (§10) | The prefix existed to disambiguate Legacy's own colliding types; SwiftCode has no such collision |
| D-18 | `ExtV2ResourceLimits` values are described as "security controls, not tuning knobs" | Kept as constants in `ResourceLimits` (§10.5); raising them needs a spec note, not a quiet edit | Same rule, new home |

### 12.3 UNVERIFIED items (do not guess — confirm on Mac)

1. **U-1**: Whether any caller installs a batch through
   `ExtV2DependencyResolver.resolve` (no caller was found in the v2
   files read). The port keeps `resolve` pure and does not invent a
   batch-install flow.
2. **U-2**: Whether `ExtV2State.activationFailed` is ever assigned
   (no assignment was found). No transition into it is specified.
3. **U-3**: Whether the `.crashed` state is ever written into the
   installed record (the host-exit path logs but does not set it).
   The next `refreshInstalled()` re-derives state from disk.
4. **U-4**: Whether `SDKPackageValidator`'s walk enforces the
   declared executable-extension set and the `.env`/`node_modules`
   exclusions named in its header comment (only the count/name/byte
   checks were seen in the excerpt read).
5. **U-5**: What, if anything, enforces the `outsideWorkspace`,
   `network`, `terminal`, `process`, `build`, and `projectConfig`
   v2 capabilities at runtime (no bridge call in the v2 files read
   checks them). They are declared and grantable; their enforcement
   points are unspecified in Legacy.
6. **U-6**: The exact UI affordance for the manual host retry after
   3 consecutive crashes (the manager refuses activation; no retry
   UI was found in the files read).
7. **U-7**: Whether a generic LSP server binary can be attached
   through SwiftCode's `LSPClient` (sourcekit-lsp-oriented) or whether
   the extension language-client surface needs its own minimal
   client after all.
8. **U-8**: Whether SwiftCode already has a ZIP reader usable by the
   package service (no facility was verified in this pass).
9. **U-9**: Whether `ExtensionPackager`'s fallback zip (whole
   directory excluding `*.git*`/`*node_modules*`) is ever exercised,
   and whether `.swiftcode-extension` archives are consumed by any
   install path in Legacy (no consumer was found in the files read).
10. **U-10**: The `use.Security.*` method scopes are enforced under
    the single `use.Security` grant per `SDKCapability.swift`, but no
    host-side vault implementation was in the files read; the
    host-side secret operations are not specified beyond that.
11. **U-11**: `ExtV2Manager` sets `ExtV2AssistExecution.shared.hostManager`
    / `.permissions` in its `init`, and registers the sort-lines
    command in `init` — the exact app-startup wiring that creates the
    manager (and therefore when the sample plugin / Xcode commands
    become available) was not in the files read.
12. **U-12**: `host.getConfiguration` is in the host allowlist and
    the shim implements it as always-fallback; whether any extension
    contribution configuration is ever read back by the Swift side
    (no reader was found) is unverified.
