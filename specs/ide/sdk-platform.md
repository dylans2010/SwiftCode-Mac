# SDK platform — Legacy SwiftCode/SDK onto Ycode

> Spec for Wave 14 (SDK platform). Behaviour and formats only: inputs,
> outputs, invariants, file grammars, key names, wire protocols, observed
> behaviour. No implementation code in this file except the public API
> signatures in §17, which are the contract the implementation codes
> against.
>
> Sources read live for this spec (Legacy read-only, main `d51a8f0d`;
> destination main `20146d32` at wave start):
> `SwiftCode/SDK/` in full — `Contracts/` (Capability, Errors, Manifest
> incl. `swiftcode-extension-v1.schema.json`, Protocol ×8),
> `Host/` (APIKeys ×6, Assist ×3, CapabilityBroker, ExtensionRegistry,
> PublicAPI, Security, ServiceAdapters, ViewOpener ×6, Bootstrap,
> Installer, Manager, ScopesIDLists), `Runtime/` (Diagnostics ×3, IPC ×2,
> Isolation, Lifecycle), `Internal/` (DirectServiceAccess,
> SDKConfigStore), `Sources/` (7 kits + CLI + 5 Tools mains, mirroring
> `SDK/Package.swift`), `Studio/` (CodeEditor 10 + Views 16),
> `Templates/Standalone-Swift/`, `Tests/` (SDKTestRunner + SDKTests),
> `TypeScript/` (package, cli, runtime-adapter, templates),
> `Documentation/` (11 files), `Examples/RepositoryBuildExtension/`,
> `Scripts/` (4 `.sh` real + 11 `.py` filler). `SDK/Distribution/` was
> inventoried but never read as source: it is generated output with
> synthetic filler (see §15).
> Destination references: `ycode/Sources/YcodeExtensions/`
> (Capabilities, SwiftCodeManifest + validator, PermissionManager,
> ExtensionManager, HostManager), `ycode/Sources/YcodeAssistant/`
> (SecretStore, SCCloudProvider, SHA256), `ycode/Sources/YcodeBuild/`
> (XcodebuildEngine), `ycode/Sources/YcodeSubprocess/`,
> `ycode/Package.swift` (YcodeGitHub/YcodeExtensions/YcodeCloud/
> YcodePaywall target model), `specs/ide/extensions-platform.md`,
> `specs/ide/storekit-paywall.md` (§9 SDKEntitlement deferral),
> `specs/ide/assist-approval-model.md`.
>
> Evidence levels used in §18: **5** — read verbatim from Legacy source
> in this pass; **4** — consistent across two or more Legacy sources;
> **3** — single Legacy source, no corroboration; **2** — plausible
> inference from source, not directly observed; **1** — unverified,
> needs a Mac check.

## 1. Overview

The SDK platform is how third-party code extends the IDE: a versioned
contract (manifest + capability registry + IPC wire protocol), a host
that brokers capabilities, stores developer API keys, audits every
decision, and runs extensions out-of-process (Node) or in-process
(Swift), plus a TypeScript SDK package, a `swiftcode` CLI, and a Studio
UI for building extensions. Ycode keeps its own Assist system as host —
there is no parallel registry, no transplanted session loop, no
Autopilot, and no bypass of the MCP write-approval gate.

Destination layout (Wave 14):

```
ycode/Sources/YcodeSDK/          new SwiftPM target `YcodeSDK`
  Contracts/  SDKError, IPC envelope, version negotiation, project /
              build / cloud-model / security / source-control /
              terminal wire contracts
  Kits/       DiagnosticsKit, WorkspaceKit, ProjectKit, BuildKit,
              SourceControlKit, ExtensionKit, SwiftCodeSDK, CLI, Tools
  Host/       APIKeys, Assist, CapabilityBroker, ExtensionRegistry,
              Security, ServiceAdapters, ViewOpener, SDKBootstrap,
              SDKInstaller, ScopesIDLists
  Runtime/    Diagnostics (log redaction, user/developer loggers,
              os_log shim), IPC dispatcher
  Internal/   DEBUG-only DirectServiceAccess, SDKConfigStore
  Assist/     Audit (SDKAuditLog), Authorization (SDKAssistGate)
  Resources/  SwiftCodeSDK.json
ycode/Sources/YcodeSDKStudio/    new SwiftPM target `YcodeSDKStudio`
  SDKStudioModels.swift, SDKStudioEditorModels.swift (Studio models)
ycode/Sources/ycode-ide/SDKStudio/  Studio SwiftUI views (11 sections)
ycode/Tests/YcodeSDKTests/       XCTest suites + manifest fixture
sdk/                             repo-root TypeScript SDK
  package/    @swiftcode/sdk (src, tests, scripts, snippets.json)
  cli/        swiftcode CLI (swiftcode.mjs + commands/)
  runtime-adapter/  @swiftcode/runtime-adapter (package shell only)
  templates/  extension-typescript, project-typescript, standalone-swift
  Contracts/Manifest/  swiftcode-extension-v1.schema.json + ExampleManifests
  scripts/    build-sdk.sh, assemble-sdk.sh, package-sdk.sh, verify-sdk.sh
  docs/       the 11 Documentation/*.md files, verbatim
```

Dependency graph (one direction only — no cycles):

```
ycode-ide ──► YcodeSDKStudio ──► YcodeSDK ──► YcodeExtensions
     │              │               ├─► YcodeSubprocess
     │              │               ├─► YcodeAssistant (SHA256, SCCloud)
     │              │               ├─► YcodeBuild (XcodebuildEngine)
     │              │               └─► Crypto (swift-crypto: HMAC/SHA-256)
     │              └─► YcodeExtensions (PermissionManager, manifest)
     └─► YcodeExtensions, YcodeSDK (direct view use)
```

`YcodeSDKStudio` exists as its own target because the Studio models
need `YcodeSDK` (SDKVersion, ProjectInspector) and `YcodeExtensions`
(PermissionManager, SwiftCodeManifestValidator) at once; putting them
in `YcodeExtensions` would have made `YcodeExtensions` depend on
`YcodeSDK`, which already depends on `YcodeExtensions` — a SwiftPM
dependency cycle. The Studio slice's original advice (add `YcodeSDK`
to `YcodeExtensions`) was wrong on this point; the coordinator split
the target instead.

## 2. Contracts

`ycode/Sources/YcodeSDK/Contracts/` — verbatim ports of Legacy's
contract files (Dylan's own code; direct port authorised under MIT).
The contract types are the wire truth; the Host slice adapts to their
shapes (see §2.1).

| File | Contents |
|---|---|
| `SDKError.swift` | Fixed taxonomy, 42 codes; `SDKError` + `SDKErrorCode.userFacingTitle` |
| `SDKIPCEnvelope.swift` | `SDKMessageType`, request/response/event envelopes, `SDKErrorPayload`, `SDKIPCCodec` (protocol v1, 1 MiB cap, NDJSON, sorted-keys compact JSON) |
| `SDKVersionNegotiation.swift` | `SDKVersions`, `SDKCompatibility.check` (protocol must match exactly; range `^`/`~`/`>=`/exact), internal `SDKVersionRange` + `SemanticVersion` |
| `SDKProjectInfo.swift` | Safe-metadata-only project contract |
| `SDKBuildContracts.swift` | `SDKBuildRequest` (allow-list: target/configuration/destination only — no env/settings/executable), output events, diagnostics, `SDKBuildStatus`/`SDKBuildResult` |
| `SDKCloudModelContracts.swift` | `cloudModel.complete` request/history. Endpoint, credentials, quota stay host-side |
| `SDKSecurityContracts.swift` | `security.*` wire types. Invariant: no type carries secret bytes in either direction; `securityID`/`valueID` are metadata only |
| `SDKSourceControlContracts.swift` | `SDKRepositoryStatus`/`SDKFileChangeSummary`/`SDKDiffOptions` (tolerant decode, defaults `maxBytes` 262144, `includeUntracked` true)/`SDKFileDiff`/`SDKRepositoryDiff`. Paths repo-relative, never absolute |
| `SDKTerminalContracts.swift` | `SDKSandboxRunRequest` (allow-list: command/args/workingDirectory/timeout; no shell/env/stdin) + `SDKSandboxedResult` (byte-bounded, truncation metadata) |

Already ported elsewhere, not duplicated: `Contracts/Capability/
SDKCapability.swift` → `YcodeExtensions/Capabilities.swift`
(`SDKCapabilityID`, 35 ids); `Contracts/Manifest/SDKManifest.swift` →
`YcodeExtensions/SwiftCodeManifest.swift` (`SwiftCodeManifest`);
`Contracts/Manifest/ExampleManifests/repository-build-extension.
swiftcode.json` → test fixture
(`ycode/Tests/YcodeSDKTests/Fixtures/…`, validated by
`YcodeSDKTests.testExampleManifestFixtureValidates`) and a verbatim copy
at `sdk/Contracts/Manifest/ExampleManifests/` for the assemble script.

### 2.1 Contract shape differences (Legacy vs ported)

The ported contracts are the wire contract; the Host slice adapts to
them. Differences from Legacy's shapes: `SDKBuildResult.exitCode` is
`Int?` (was `Int32?`); `SDKFileChangeSummary.isStaged` (was `staged`);
`SDKRepositoryStatus` gained `branchName`/`ahead`/`behind`/counts;
`SDKFileChangeStatus` has `conflicted`, no `typeChanged`/`unknown`;
`SDKSecurityUseOperation` is a struct `{kind, request}` (was an enum);
`SDKSecurityHTTPRequest.body` is a plain `String?` (not base64);
`SDKSecurityAddedValue.created` (was `existed`);
`SDKSecurityHasValue.hasValue` (no valueID);
`SDKSecurityValueList.values` holds `[SDKSecurityStoredValue]`.

## 3. Manifest schema

- The manifest type everywhere is `SwiftCodeManifest`
  (YcodeExtensions). Legacy's `ExtensionManifest` is not re-ported.
- The strict validator is the install-time gate:
  `YcodeExtensions.SwiftCodeManifestValidator` (`validate(data:)`,
  `validateWithDiagnostics(data:projectRoot:grantedCapabilities:)`),
  64 KiB cap, host SDK version `"1.2.0"`. Legacy's lenient
  `ExtensionValidator` was deliberately **not** reimplemented
  (extensions-platform.md §2.3).
- `SDKManifestValidator` (`Kits/ExtensionKit/
  ManifestValidatorAdapter.swift`) is the thin bridge that preserves
  the kit-level call shape (`validate(data:packageRoot:)`,
  `validateFile(at:)`, `validateAndDecode(data:)`) returning SDK
  `[Diagnostic]`. Severity mapping: error→`.error`,
  warning→`.warning`, info→`.note`; code by field
  (`manifest`→`.manifestInvalidJSON`,
  `manifestVersion`→`.manifestInvalidVersion`, `capabilities`
  error→`.manifestUnauthorizedCapability`, other
  errors→`.manifestMissingRequiredField`,
  warnings→`.manifestInvalidCapabilityReason`); message verbatim,
  suggestion→remediation, line→location when a package root is known;
  field kept in `metadata["field"]`.
- The schema file lives at `sdk/Contracts/Manifest/
  swiftcode-extension-v1.schema.json` (copied verbatim from Legacy
  `SwiftCode/SDK/Contracts/Manifest/` in Wave 14). It is the file the
  `swiftcode create` generator and `dev` command resolve: the
  generator (`sdk/cli/create-extension.mjs`) looks one level up from
  `sdk/cli`, `dev` (`sdk/cli/commands/dev.mjs`) two levels up from
  `sdk/cli/commands`, and `assemble-sdk.sh` §4 copies from
  `$SDK_ROOT/Contracts/Manifest/`. `validate` works without the file
  (embedded schema mirror); `dev` degrades to a warning without it;
  `install` requires the `$schema` pointer to resolve inside the
  package (generated projects ship the schema copy).
- **Two versions, both real, different quantities — not a conflict.**
  `SDKVersion.current` = 1.0.0 is the SDK *package* version (what the
  installer checks and Studio displays). The manifest validator's host
  SDK = 1.2.0 is the version a manifest's `versionRange` is admitted
  against. Studio follows 1.0.0 for SDK-version display and install
  expectations; the validator keeps 1.2.0 untouched.

## 4. Capability model

- The fixed registry is 35 capability IDs (`SDKCapabilityID` in
  YcodeExtensions). The requestable *scope* list is 32 entries
  (`ScopesIDLists.all` in YcodeSDK, mirrored in TypeScript as
  `SCOPES_ID_LIST`): 12 view scopes, 20 API scopes. `use.Security`
  and `assist.main` are umbrella/entitlement surfaces, not separately
  requestable scopes.
- The Legacy-faithful info table lives in `SDKCapabilityRegistry`
  (titles, descriptions, grants/does-not-grant lines, risk,
  `grantableInCurrentRelease`). Privileged = high-risk
  (`SDKCapabilityRegistry.isPrivileged`). Restricted is not
  "privileged" — it is deny-by-default.
- **Grantability decision (coordinator, Wave 14).** Two grantability
  rules exist and they deliberately differ. YcodeExtensions'
  `SDKCapabilityID.isGrantable` is false only for `assistInvoke` —
  that is the generic Extensions-v2 rule. The SDK host's
  `grantableInCurrentRelease` is stricter: `assistUI`,
  `assistHeadless`, `assistMainView`, and the `security.*` method
  scopes are NOT grantable in this release (entitlement-only /
  method scopes under the single `use.Security` grant). The Legacy
  table is the authority for SDK-host decisions; do not "fix" one to
  match the other without a coordinator decision.
- The broker (`SDKCapabilityBroker`) delegates the grant store to
  YcodeExtensions' `PermissionManager` + `grants.json` (0600). There
  is no second grant store. A capability is granted only when ALL of
  its mapped v2 capabilities are granted
  (`ExtensionCapability.v2Capabilities(for:)`), conservative
  deny-by-default. `SDKAssistService.createSession` snapshots the same
  way for `allowedToolIDs` (never extended afterwards).
- **Flat-store deviation.** `grants.json` carries no per-grant expiry,
  revocation timestamp, or per-project scope, so Legacy's precise
  `PERMISSION_REVOKED` / `PERMISSION_EXPIRED` / scoped-elsewhere
  classifications collapse to `PERMISSION_DENIED` here. Revocation
  still takes effect on the next call (the grant is gone); expiry is
  enforced at the key level, not the grant level. Per-project scope is
  NOT enforceable by the flat store — the broker checks only that the
  caller has a non-empty, non-root project root. Digest binding is
  kept: the caller's package digest must match the digest recorded at
  install (`SDKExtensionRegistry`), or re-approval is required.
- Approval UX (`SDKApprovalView`, SwiftUI, gated on
  `canImport(SwiftUI)`): subset approval, toggles default ON only for
  low-risk + grantable capabilities, ungrantable rows labeled "Not
  available in this release", build-execute note, only-approved note.
  The view performs no navigation/persistence. Legacy used the app's
  `liquidGlass` modifier; YcodeSDK has none, so rows use a plain
  background fill. The broker stores only the explicitly approved set.
  The Wave 2 MCP approval gate (`MCPWritePolicy` / `approve`) stays
  the gate for tool execution; the SDK approval view governs
  capability grants, not tool calls.

## 5. Key management (incl. HMAC)

- Secret format (unchanged): `<prefix>_<base64url(payloadJSON)>
  .<base64url(sig)>`, payload `{id, prefix, iat}`, HMAC-SHA256 over
  the payload's base64url bytes with the host device key, base64url
  RFC 4648 §5 without padding, constant-time comparison
  (`HMAC<SHA256>.isValidAuthenticationCode`). All failures →
  `.apiKeyInvalid`; the secret is never in an error.
- Crypto: Legacy used CryptoKit; YcodeSDK uses swift-crypto `Crypto`
  (same API for these uses). Device key: `SymmetricKey(size: .bits256)`
  (portable) instead of `SecRandomCopyBytes`.
- Device key (32 bytes, account `sdk.device-key`) is created once and
  never silently regenerated — a corrupt device key fails closed with
  `.serviceUnavailable`.
- Key metadata (`sdk.apikey.<uuid>`, JSON ISO-8601) is the only thing
  persisted; secrets are returned once and never stored. `verify`
  re-reads metadata every call, updates `lastUsedAt`, and rate-limits:
  10 failures/60s per bucket (bucket = UNVERIFIED presented key ID,
  or `"unparseable"`), then a 5-minute lockout, max 1024 buckets.
- **Storage seam — `SDKSecretStoring`:** YcodeAssistant's `SecretStore`
  protocol has no enumeration, which `list()` /
  `accountNames(withPrefix:)` require, so YcodeSDK defines its own
  protocol. macOS backend is the Security framework directly (service
  `com.swiftcode.sdk`, `WhenUnlockedThisDeviceOnly`, no UserDefaults
  fallback, no cache); Linux backend is a file store (0700 dir, 0600
  files, atomic writes) at `~/.config/ycode/sdk-secrets`,
  deliberately separate from the assistant's
  `~/.config/ycode/secrets`.
- **KeychainSDK vault:** namespace
  `com.swiftcode.sdk.security.<securityID>.<valueID>` is the account
  inside the SDK secret store (Legacy used the Security framework
  directly with service prefix `com.swiftcode.sdk.security` — the
  full namespaced string is preserved as the account). Values are a
  JSON envelope `{data base64, label, created, modified}`.
  `readValue` is INTERNAL (host-only, for `useValue` injection).
- **Flag — application records store the presented secret:**
  Legacy's `SDKAssistApplication.Field.apiKey` holds the presented
  secret, and this port keeps that (the store encrypts it at rest via
  Keychain). A future revision should store only the key ID. Do not
  "fix" silently — it changes the approval flow.
- Session presentation: `SWIFTCODE_API_KEY` env var, trimmed, blank →
  nil. The secret is toxic: verify it, then drop it.
- Entitlements: `SDKEntitlement` (Wave 13 deferral, now ported) —
  `developerAIAssist` / `developerAIAllowsCloud` read only from the
  verified key record; manifest self-assertion never counts. See §7.

## 6. Grant store

See §4. The live grant store is `PermissionManager` + `grants.json`.
`SDKCapabilityBroker` delegates to it. The Studio grant manager
(`SDKStudioGrantStore`) synthesises records from live grants only via
`SDKPermissionManagerGrantStore`; revoked records disappear instead of
persisting as audit evidence, and `extensionName(for:)` returns nil.
Grant tombstones / package digests / extension display names need a
grant-record store (or tombstone support in `PermissionManager`) —
Wave 15 (§16).

## 7. Assist gate

- Deny-by-default. `SDKAssistGate.check` runs FIRST in the dispatcher,
  before routing or decoding. `assist.invoke` is the entitled route
  (exempt from the deny-list); everything Assist-shaped (`assist`,
  `llm.`, `agent_runner`, `chat`, `sendMessage`, case-insensitive
  substring) is denied with the VERBATIM message and audited. The
  cloud-model denial message is PROPOSED — Dylan finalizes the
  wording.
- Entitlement reads ONLY the verified key record
  (`developerAIAssist` / `developerAIAllowsCloud`); manifest
  self-assertion never counts.
- **Backend boundary:** `SDKAssistService.send` / `sendStreaming` /
  `executeTool` require a real backend. None is attached: they throw
  `.serviceUnavailable` and NEVER fabricate responses, deltas, or tool
  results (`sendStreaming` yields `.started` then `.failed`). The
  `SDKAssistBackend` protocol is the seam a future attachment must
  implement — it receives only the extension's own session content,
  never the user's host conversation. The audited Legacy candidates
  (`AssistManager`, agent sessions, `LLMService`) were rejected as
  attachment points because they would leak user conversation/keys.
- **Honest boundary:** the real Assist choke points (host session loop,
  LLM service) have no extension caller identity in this release, so
  this gate guards the SDK IPC surface only. Wiring caller identity
  into the host Assist stack is future work.
- `SDKAssistUIOpener`: `assist.main` opens the host's real Assist main
  view for entitled callers; unregistered view → `.serviceUnavailable`.
  (Legacy's `AppCommands` quirk — posting `"agent"`, which matched no
  sidebar raw value and silently no-op'd — was deliberately NOT copied.)

## 8. Audit log

- Append-only JSON-lines, `~/Library/Application Support/SwiftCode/
  SDKAudit.jsonl` (Linux: `~/.config/ycode/sdk-audit.jsonl`). Dir 0700,
  file 0600 re-enforced; single `FileHandle` seeked to end; `record()`
  never throws (failures go to the OS log). Detail strings contain
  identifiers only — never secrets. Undecodable lines on read are a
  tamper signal.
- Event taxonomy is Legacy's fixed set (permission/assist/cloud/key/
  entitlement/extension/runtime/security events).
- Developer log (`SDKDeveloperLogger`):
  `~/.swiftcode/logs/developer-sdk.log`, rotation at 10 MB retaining
  `.1`/`.2`, redacted payloads, `fetchEntries(correlationId:)` scans
  `.2`/`.1`/current oldest-first.
- User log (`SDKUserLogger`): ring buffer max 200, sanitized messages.
- `SDKLogRedaction` redacts secrets before any log line is written;
  `SDKOSLog` forwards to `os.Logger` on Apple platforms and to stderr
  elsewhere (no Ycode file uses `import os` — Linux-incompatible).
  Messages passed to it must already be redacted.

## 9. Runtime protocol (NDJSON IPC + dispatcher)

- Wire: NDJSON over stdio, protocol version 1 (`SDK_PROTOCOL_VERSION`
  = 1); stdout is the IPC channel only, diagnostics go to stderr.
  `SDKIPCCodec` enforces a 1 MiB message cap, sorted-keys compact
  JSON, single-line messages.
- `SDKIPCDispatcher` (one per `SDKRuntimeSessionInfo`): peek → gate →
  re-verify session key every request → caller identity from the
  SESSION, never the payload → route inside a 60s timeout (detached
  watchdog; the operation keeps running detached on timeout).
  `dispatch` never throws — failures become `ok: false` +
  `SDKErrorPayload`.
- **Transport stays dropped:** `SDKIPCTransport` is dropped by design
  (v2 `ExtensionRPC` is the one wire protocol). The dispatcher takes
  `Data` in / returns `Data` out; the caller owns the transport and
  installs `eventSink` for unsolicited events (build output, Assist
  stream deltas). With no sink, events are dropped.
- **Dropped types, minimal replacements:** `SDKRuntimeSession`'s state
  machine stays dropped — `SDKRuntimeSessionInfo` is a plain value
  (extensionID, packageDigest, projectRootPath, presentedAPIKey).
  `SDKCommandRegistry` stays dropped — the dispatcher keeps a
  per-session command table (Legacy validation: 64-cap, kebab-case,
  ownership; unregister of unknown ID is a silent no-op) and execution
  routing stays the v2 host/MCP job. `SDKCommandDefinition` is defined
  here as the wire type.
- **Node runtime.** The Swift host's `SDKNodeLauncher` spawns one
  adapter process per extension with piped stdio (v2 `HostManager`
  covers the launcher; `SDKNodeLauncher` itself was not re-ported).
  The TypeScript runtime adapter (`@swiftcode/runtime-adapter`,
  `dist/adapter.js`) is the process the host spawns — see §13.2.
- Extension → host events: `extension.ready { extensionId, version,
  protocolVersion: 1 }`, `extension.activationFailed`,
  `extension.error`, `commands.executeResult { invocationId, ok,
  result | error: { code, message, correlationId } }`. Unknown command
  → `UNKNOWN_COMMAND`.
- Host → extension events: `commands.execute { commandId,
  invocationId, payload }`, `shutdown {}`.
- Exit codes: 0 clean teardown (host `shutdown`, stdin EOF/close,
  SIGTERM → best-effort `deactivate()`, 5 s budget); 1 startup/
  contract failure, `activate()` throw, or uncaught exception/
  rejection.

## 10. Service adapters

- **Build (`SDKBuildService` + `SDKBuildOutputParser`):** delegates
  process execution to YcodeBuild's `XcodebuildEngine`
  (`BuildRequest` / `BuildOperation`), never a raw `Process`. Keeps
  Legacy semantics: allow-list request (Debug/Release only,
  destination ≤256 no NUL, default `platform=macOS`), cwd = caller
  project root, one build per extension, limits (20,000 events, 4 MiB
  retained output, 50 result diagnostics, 1800s timeout), truthful
  terminal state via `didSucceed` (exit 0 AND `** BUILD SUCCEEDED **`
  AND zero errors). **Deviations:** YcodeBuild's default command is
  `["/usr/bin/xcrun", "xcodebuild"]` vs Legacy's pinned
  `/usr/bin/xcodebuild`. Legacy located the project via the app's
  `AssistXcodeProjectResolver` and resolved the scheme with
  `xcodebuild -list`; neither seam exists — the container is resolved
  from the project root (`.xcworkspace` > `.xcodeproj` >
  `Package.swift`) and the requested target is used as the scheme.
- **BuildKit overlap (coordinator note).** The same target also holds
  `Kits/BuildKit/BuildService` + `BuildDiagnosticsParser` (kit-level
  swift/npm builds via `YcodeSubprocess`). Both are Legacy-faithful
  and both stay: the kit builds Swift packages / npm projects
  directly; the host adapter builds Xcode projects through
  `XcodebuildEngine` and is the one the dispatcher routes
  `build.execute` to. `BuildService` has no `xcodebuild` path —
  Legacy had none either.
- **Cloud model (`SDKCloudModelAdapter`):** delegates to YcodeAssistant's
  `SCCloudProvider` (`AssistantProvider.send`) + `SCCloudRateLimiter`
  pre-check. Never a parallel client. Unconfigured cloud reports
  honestly as `.serviceUnavailable`; quota maps to
  `.resourceLimitExceeded`; server messages are sanitized/truncated.
- **Source control (`SDKSourceControlAdapter`):** reads only, git run
  directly via `Process` with timeouts (30s status / 60s diff),
  byte-bounded diffs (default 256 KiB, truncation flags, never
  `.outputTooLarge`), non-repo status returns the empty shape,
  non-repo diff throws `.notARepository`.
  **Improvement over Legacy:** Legacy routed through the app's
  `GitService`, whose hunk parser dropped `diff --git` headers and
  lost the first file header (positional `git diff --name-only`
  fallback, `"unknown"` paths on mismatch). Parsing raw `git diff`
  output removes that quirk, and the diff path filter is honored
  (Legacy rejected any non-empty filter). `includeUntracked` is
  accepted but unsupported (same as Legacy).
- **Terminal (`SDKSandboxedTerminal`):** the ONLY process-execution
  path. No shell ever. Allow-list of 27 executables (notably NO
  sh/bash/zsh/env), approved directories, bare-name regex, absolute
  paths symlink-resolved into approved dirs, cwd confined to the
  project root, sanitized fixed environment, stdin `/dev/null`,
  256 KiB/stream caps with drain-past-cap capture, 4 concurrent runs
  per extension, timeout SIGTERM → 2s grace → SIGKILL, timeout throws
  `.requestTimeout` (never a fabricated exit code).
- **Internal (DEBUG-only):** `DirectServiceAccess` — pinned
  `/usr/bin/xcodebuild` preserved; Legacy's in-process `GitService`
  does not exist in Ycode, so the file exposes the git executable URL
  instead. `SDKConfigStore` — loads `SwiftCodeSDK.json` from
  `Bundle.module` with a `Bundle.main` fallback; `isDeprecated(api:in:)`
  answers deprecation. The JSON ships as a YcodeSDK resource
  (`.copy("Resources/SwiftCodeSDK.json")` in Package.swift).

## 11. Extension registry + installer

- `SDKExtensionRegistry` tracks `swiftcode.json` packages by
  id/version under `~/Library/Application Support/SwiftCode/
  Extensions/<id>/<version>/` (Linux: `~/.config/ycode/
  sdk-extensions`), with canonical SHA-256 digests (swift-crypto),
  strict validator delegation, 0600 records, and re-validation on
  every load.
- **Registry-root decision (coordinator, Wave 14).** The SDK registry
  root stays distinct from the v2 `ExtensionsV2/` root — it tracks
  `swiftcode.json` packages, which the v2 manager does not manage.
  Unification would conflate two package formats under one root;
  it is not done.
- `SDKBootstrap` starts the host without Legacy's
  `SDKExtensionManager.startAll` (dropped by design — v2
  `ExtensionManager` owns lifecycle).
- `SDKInstaller` is the real npm installer (idempotent: an
  already-`.ok` prefix short-circuits without spawning npm; version
  mismatch / corrupt installs are repaired). Pinned package
  `@swiftcode/sdk`, expected version 1.0.0, default prefix
  `~/.swiftcode/sdk`. No bundled tarball ships in-repo; the bundled
  fallback honestly reports unavailable when absent.
- Studio wires the installer through `SDKStudioInstallerHost`
  (adapter over `SDKInstaller`); see §14.

## 12. View openers

- Registry ported fully (`SDKViewOpener`): last-wins registration, no
  unregister, unregistered → `.serviceUnavailable`, no authorization
  in the registry (the dispatcher authorizes).
- **Missing seam (honest):** YcodeUI has window controllers but NO
  matching seams for the 12 SDK views under Legacy names, and no
  `ToolbarActionManager` / `toolbarToolActivated` equivalent. The
  opener logic is ported; the windows are behind a new seam:
  `SDKViewHost` protocol (one method, dispatched by view ID) +
  `SDKViewHostRegistry` (installed by YcodeUI at startup). With no
  host installed, opens throw `.serviceUnavailable` naming the missing
  seam. Legacy's window managers and notification bridges are NOT
  re-ported. `SDKHostedWindow` (macOS-only generic NSWindow host) is
  available for openers that own their window.
- Sibling openers: CI (`ci.VisualWF`) and virtualization require a
  project (via injectable `SDKActiveWorkspaceProviding`; no provider →
  `.projectNotOpen`); live preview needs none. The CI dashboard is the
  LOCAL-automation surface, not a GitHub Actions inspector.
- **Adaptation:** Legacy's `ViewOpener` was a synchronous closure; the
  Ycode opener is `async throws` because window presentation may await
  the workspace.

## 13. TypeScript package, CLI, runtime adapter, templates, scripts, docs

### 13.1 `@swiftcode/sdk` (`sdk/package/`, v1.0.0)

`package.json`: `"name": "@swiftcode/sdk"`, `"type": "module"`,
`"main": "dist/index.js"`, `"types": "dist/index.d.ts"`,
`"files": ["dist"]`. Scripts: `build` = `tsc -p tsconfig.json &&
npm run build:snippets`, `build:snippets` = `node
scripts/build-snippets.mjs`, `test` = `node --test "tests/*.test.mjs"`.
Dev deps: `typescript 7.0.2`, `@types/node 26.6.5`. `tsconfig.json`:
strict, `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`,
`NodeNext`, `ES2022`, `rootDir src`, `outDir dist`.

Entry point `src/index.ts` re-exports (all verbatim from Legacy):
`types.ts` (737 lines — the full `SwiftCodeContext` type surface,
`SDKAssistAccessError` / `ASSIST_ACCESS_DENIED_MESSAGE`,
`SDKCloudModelAccessError` / `CLOUD_MODEL_ACCESS_DENIED_MESSAGE`),
`ipc.ts` (306 lines — `SDKError`, `SDK_PROTOCOL_VERSION = 1`,
`REQUEST_TIMEOUT_MS = 60_000`, `createStdioConnection`),
`context.ts` (744 lines — `createContext(connection)` implementing
the full `SwiftCodeContext` the Swift host's `SDKIPCDispatcher`
routes), `snippets.ts` (622 lines — `SNIPPETS`, `searchSnippets`,
`getSnippet`; every snippet is runnable TS against the real SDK API,
each declaring its exact capability wire ID), `security.ts` (388
lines — `createSecurityAPI` and the `security*` functions; the
Keychain-vault surface never sees raw secret values beyond the
controlled API), `assist.ts` (269 lines), `assistUI.ts` (71 lines —
`ASSIST_VIEW_ID = "assist.main"`), and `ScopesIDLists.ts` (see below).

`src/ScopesIDLists.ts` is **generated, not hand-written**: it is
regenerated from the Swift host table
(`ycode/Sources/YcodeSDK/Host/ScopesIDLists.swift`) by
`~/SwiftCode-Migration-Workspace/scripts/generate-scopes-ts.py`
(32 entries: 12 views, 20 api; `capabilityId` equals the wire id for
every entry). The two files are kept in sync by
`tests/scopes-sync.test.mjs`, which parses BOTH files and fails on any
ID, kind, ipcMethod, or viewId drift. Do not hand-edit the generated
file — change the Swift host table and re-run the generator. (Wave 14
resolved the TS slice's blocker B1 this way; the Legacy TS file's
longer descriptions and interleaved order were superseded by the
ported Swift table, which is the destination's host truth.)

Tests (`sdk/package/tests/`, 11 files, `node --test`):
`assist-variants`, `cli-roundtrip`, `cloudmodel`, `context`, `ipc`,
`scopes-sync`, `security-exfiltration`, `security`, `snippets`,
`terminal`, `ui`. Nine need only `npm install` + `npm run build` on
Dylan's Mac; `cli-roundtrip` and `scopes-sync` need the Wave 15
adaptations in §16 first.

### 13.2 Runtime adapter (`sdk/runtime-adapter/`)

**Source dropped by design** (ledger IMPLEMENTED): `src/adapter.ts`
is not ported and `dist/adapter.js` is absent from the checkout. What
was ported: `.gitignore`, `README.md`, `package.json`, `tsconfig.json`
— verbatim. The ported `README.md` **is the adapter's protocol spec**
and is retained verbatim for the rewrite (Wave 15): CLI `node
dist/adapter.js --entrypoint <path> [--manifest <swiftcode.json>]
[--id] [--version] [--name]`; entry module's default export must be
`{ id, activate, deactivate }` or stderr + exit 1; NDJSON over stdio,
protocol version 1; stdout is the IPC channel only; extension → host
events `extension.ready` / `extension.activationFailed` /
`extension.error` / `commands.executeResult`; host → extension events
`commands.execute` / `shutdown`; exit 0 clean teardown (5 s
deactivate budget), 1 on startup/contract failure.

### 13.3 `swiftcode` CLI (`sdk/cli/`, package `swiftcode-cli`, private)

`package.json`: `"bin": {"swiftcode": "./swiftcode.mjs"}`,
`"type": "module"`, dependency `archiver 8.0.0`. Dispatcher
`swiftcode.mjs` (274 lines): auto-discovers `commands/<name>.mjs`
(any `*.mjs` except `_`-prefixed helpers), hand-rolled arg parser,
global `--json` / `--help`, exit codes 0 success · 1 operational
failure · 2 usage error. Command contract in
`commands/CONTRACT.md`: `export const definition = { name,
description, usage }` (name must equal the file base name) +
`export async function run(args, ctx)` with `ctx = { log, error }`;
`--json` mode suppresses `ctx.log` so stdout stays parseable JSON.

| Command | Description |
|---|---|
| `build` | Compile an extension project (`tsc` for TS, `xcodebuild` for Swift) with live output. Honest xcodebuild-absent path (no fake success). |
| `create` | Scaffold a new SwiftCode extension or standalone project (wraps `create-extension.mjs`). |
| `dev` | Local dev loop: `tsc` → manifest+package validation → `node --test`; watches `src/` + config files. v1 has NO host attachment. |
| `enable` / `disable` | Enable/disable an installed extension; both re-export `_set-enabled.mjs`. |
| `install` | Install a `.swiftcode-extension` into the controlled directory `~/Library/Application Support/SwiftCode/Extensions` (overridable via `SWIFTCODE_EXTENSIONS_DIR` for tests). Verifies digest + schema before touching the directory. |
| `list` | List installed extensions (id, version, enabled, digest). |
| `package` | Build + package into a deterministic `.swiftcode-extension` archive with an embedded digest record. |
| `uninstall` | Remove one version, or every version with `--all`. |
| `validate` | Validate `swiftcode.json` + package contents. Carries an **embedded schema mirror** (patterns + `CAPABILITY_IDS` = 35 SDK ids + 6 `use.Security.*` scopes), so it works without the schema file. |

`create-extension.mjs` (155 lines) generates a real, compilable TS
extension from `../templates/extension-typescript` and ships the real
manifest schema into the generated project's `schemas/`. It fails hard
if the schema file is missing — the schema now lives at
`sdk/Contracts/Manifest/` (§3), so `create` works.

### 13.4 Templates (`sdk/templates/`)

All templates use `__PLACEHOLDER__` tokens substituted by the
generators/CLI; tokens are preserved verbatim.

- **extension-typescript/** — TS extension scaffold. `src/index.ts`
  exports `{ id: "__EXTENSION_ID__", activate, deactivate }`;
  `src/extension.ts` registers `inspect-repository` + `run-build`
  commands with dispose-on-deactivate (partial-activation unwind).
  `swiftcode.json` (minified, 748 bytes): manifest v1, `runtime.
  entrypoint dist/index.js`, `language typescript`, `sdk { name
  @swiftcode/sdk, protocolVersion 1, versionRange ^1.0.0 }`,
  capabilities `source-control.read` + `build.execute`, contributes
  the two commands, `$schema ./schemas/swiftcode-extension-v1.schema.json`.
  `package.json` deps `@swiftcode/sdk: __SDK_FILE_URL__`.
  Tests: `extension.test.mjs`, `manifest.test.mjs`.
- **project-typescript/** — standalone TS project. `src/index.ts`
  exports `greeting()` / `main()`; no extension sandbox restrictions.
- **standalone-swift/** (from Legacy `Templates/Standalone-Swift/`) —
  macOS SwiftUI app scaffold (`App.swift`, `ContentView.swift`,
  `template.json`, `README.md`, `.gitignore`).

### 13.5 Scripts pipeline (`sdk/scripts/`, adapted)

Legacy `SwiftCode/SDK/Scripts/` pipeline: `build-sdk.sh` →
`assemble-sdk.sh` → `verify-sdk.sh` → `package-sdk.sh`. Adaptations
(path updates only, no new steps; every change is commented in the
scripts): `SDK_ROOT` is now `sdk/`; new `SWIFT_PACKAGE_DIR =
$REPO_ROOT/ycode` (Swift build outputs from `ycode/.build/release`);
`assemble-sdk.sh` TypeScript copy paths updated
(`$SDK_ROOT/TypeScript/*` → `$SDK_ROOT/package|cli|runtime-adapter|
templates`); `assemble-sdk.sh` §6 (`populate-distribution.py`)
removed — filler generator, dropped (see §15); the 200 MB size gates
in `assemble-sdk.sh` §8 and `verify-sdk.sh` §3 are now report-only
(they were only passable via the dropped synthetic filler; real SDK
content is far smaller); `verify-sdk.sh` §1 no longer requires
`manifests/components.json` (it was written by the dropped
`populate-distribution.py`); `package-sdk.sh` verify call updated to
`$SDK_ROOT/scripts/verify-sdk.sh`. The pipeline's Swift steps need the
Swift SDK binaries in `ycode/.build/release` (Wave 14 wires the
targets; the binaries exist once Dylan builds on his Mac).

### 13.6 Documentation (`sdk/docs/`)

The 11 `Documentation/*.md` files, verbatim: Assist-Access,
Capabilities-and-Permissions, Compatibility, Extension-Manifest,
Package-Format, Platform-Capabilities, Release-Readiness,
Runtime-and-Security, SDK-Architecture, Security-Keychain,
TypeScript-Extensions. Internal cross-references still use Legacy
paths (`SwiftCode/SDK/...`) — a later docs pass should remap them to
`sdk/...` in one place (Wave 15). `sdk/docs/Release-Readiness.md`
references `Distribution/bundle-sdk.sh` and
`Distribution/verify-bundle.mjs`, which are distribution scripts
outside this wave's scope.

## 14. Studio UI

Eleven sections, verbatim from Legacy `SDKStudioSection` (raw values
are the display names): Projects, Code Editor, Manifest Editor,
Extensions, API Keys, Security, Logs, Installed, Assist Access, SDK &
Downloads, Ship & Export — same SF Symbols. Root view `SDKStudioView`
(NavigationSplitView + shared `SDKCodeEditorState`, "Install SDK"
toolbar button, first-launch installer sheet, resource-error alert)
preserves Legacy's section routing, including `openProjectInEditor`
(opens `swiftcode.json` / `src/index.ts` / `App.swift` /
`ContentView.swift` / `README.md`, then prefers `src/index.ts` or
`ContentView.swift` for the code editor and `swiftcode.json` for the
manifest editor). Studio models live in `YcodeSDKStudio` (§1);
views live in `ycode/Sources/ycode-ide/SDKStudio/`.

### 14.1 Wizard / installer flow

Projects view: three creation cards + recent projects (UserDefaults key
`com.swiftcode.sdk.studio.recentProjects`, max 20, filtered to existing
paths) + open-existing (validated by `YcodeSDK.ProjectInspector`).

Wizards (`SDKStudioWizardConfig`, field-for-field from Legacy):
- New Extension — id, name, version (default `0.1.0`), description,
  outDir, sdkPackage. Banner notes the scaffold declares
  `source-control.read` + `build.execute` and the manifest editor covers
  the canonical capabilities.
- New TypeScript Project — name, slug, version, description, outDir.
- New Swift Project — name, bundleId, outDir.
Validators mirror `create-extension.mjs` (reverse-DNS id, semver, npm
slug, Swift type name, description ≤ 1000 chars, target directory
empty-or-absent, sdkPackage must contain a `package.json` naming
`@swiftcode/sdk`). `SDKStudioScaffold.create` writes the real scaffold
files (extension: `swiftcode.json` with the two starter capabilities,
`package.json` with a `file:` dep when an sdkPackage is given,
`tsconfig.json`, `src/index.ts`, `README.md`; TS project:
`package.json` / `tsconfig.json` / `src/index.ts` / `README.md`;
Swift: `App.swift` / `ContentView.swift` / `README.md` /
`.gitignore`). Refuses a non-empty target and any template path
escaping the target (containment anchor, Legacy rule verbatim).

Installer: `SDKStudioFirstLaunchChoice` (installed / declined /
remindLater, `shouldPrompt(sdkInstalled:)` — true only while nothing
is recorded and the SDK is not installed) and
`SDKFirstLaunchInstallerView` (prompt → installing → succeeded/failed,
live log lines, Remind Me Later / Decline). **S-1 wired in Wave 14:**
the install runs through `SDKStudioInstallerHost`, the adapter over
the Host slice's real `SDKInstaller` (§11); the
`SDKStudioInstallerUnavailable` placeholder remains only for tests.

### 14.2 Grant manager + API keys UI

Grants: `SDKStudioGrantStore` protocol (`grants(for:)` /
`extensionName(for:)` / `revoke` / `revokeAll`) +
`SDKStudioGrantRecord` (Legacy `SDKGrantRecord` shape: package
digest/version, capability, scope, granted-by/at, expiry, revoked
tombstone, policy version). **S-2 open (Wave 15):** the default
adapter (`SDKPermissionManagerGrantStore`) synthesises records from
live grants only (SDK ids mapped back through
`ExtensionCapability.v2Capabilities(for:)`); revocation is real and
immediate, but revoked records disappear instead of persisting as
audit evidence, and `extensionName(for:)` returns nil. The grant
manager view says this in the UI. Pre-authorization from the manifest
editor grants through the real `PermissionManager.grant` (the seam has
no grant operation by design — no second grant path was invented).

API keys: `SDKStudioAPIKeyStore` protocol (`createKey` returning
metadata + the secret shown exactly once, `list`, `revoke`) +
`SDKStudioAPIKey` / `SDKStudioAPIKeyScope` (v1 scopes `apps:create`,
`apps:publish`, `capabilities:request`; `sc_dev_live_` /
`sc_dev_test_` prefixes; `isRevoked` / `isExpired`). **S-3 wired in
Wave 14:** the API Keys view defaults to `SDKHostAPIKeyStore`, the
adapter over the Host slice's real `SDKAPIKeyStore` (§5). No in-memory
key store was provided — one that forgets keys on restart would
silently break verification.

Security manager / secure-prompt entry (`SDKStudioSecurityStore` seam,
per-app `use.Security` values, add/delete/delete-all): **S-4 open
(Wave 15):** no `use.Security` store exists in Ycode yet — the Host
slice's `SDKSecurityService` has per-app operations but no
list-all-apps enumeration, so Studio cannot list the apps to manage.
The view reports the gap instead of writing secrets to UserDefaults
or plain files.

Assist access form: full validated form
(`SDKStudioAssistAccessApplication`, same fields and validation as
Legacy); **S-5 open (Wave 15):** submission belongs to the Host
slice's `SDKAssistApplicationStore`, but the form as ported has no
SDK-variant picker (UI vs headless — `SDKAssistSDKVariant`) and no API
key secret — `SDKAssistApplication.Field` requires both `apiKey` (the
presented secret) and `sdkVariant`. The form validates and shows a
summary, and states submission is unavailable rather than faking an
approval. Wave 15 must add a variant picker + an API-key picker (the
secret must come from the key-creation flow, never typed into the
form) before submission can be wired.

### 14.3 Logs

Three panes, as Legacy: User (`SDKStudioUserLogger`, sanitized
in-memory entries, correlation-ID search, cap 500); Developer
(Ycode's real `DiagnosticsService` — search, clear, per-extension
counts); Audit — **G-1 wired in Wave 14:** the pane reads the durable
`SDKAuditLog` via `recentEvents(limit: 200)` (§8).

### 14.4 Manifest inspector / editor

One `SDKManifestEditorView` (visual + raw JSON, identity/runtime/SDK
sections, capability toggles with reasons, search + category filter
over all 35 canonical capabilities, contributed commands add/remove,
malformed-JSON banner with raw fallback, dirty tracking, save) and
`SDKManifestInspectorView` (read-first: identity, capabilities with
risk badges + restricted/unknown markers, commands, diagnostics, raw
JSON tab, edit mode hands off to the editor). Edits go through
Ycode's `SwiftCodeManifest` (unknown keys preserved in
`unknownFields`) and validation is Ycode's strict
`SwiftCodeManifestValidator` — the install gate (§3). Capability
categories: All / Enabled Only / Project / Source Control / Build / UI
& Views / Security & AI (same membership rules as Legacy). Risk
colours: low green, medium blue, high orange, other red.

### 14.5 Code editor

Ported model/state (in `YcodeSDKStudio`, testable, no SwiftUI):
`SDKCodeLanguage` (6 cases, conservative inference → `.plaintext`),
`SDKToken`/`SDKTokenKind`/`SDKSyntaxHighlighter` + compact single-pass
`SDKKeywordHighlighter` (keywords, strings, `//` + nested `/* */`
comments, numbers, capitalized type names; UTF-16 ranges,
non-overlapping), `SDKConsoleStream`/`SDKConsoleEntry` (4 KiB/entry
cap), `SDKCodeDocument`/`SDKCodeEditorTab` (value types,
`withText`/`saved`), `SDKCodeFileNode` (lazy children, files never
carry children, skips hidden + `node_modules`, directories-first),
`SDKCodeEditorError` / `SDKCodeNavigationTarget` /
`SDKEditorDiagnostic`, `SDKCodeEditorState` (`@Observable`, tabs,
project-root persistence, console cap 5,000 oldest-first, diagnostics
dedup, external-modification tracking with clean-auto-reload /
dirty-flag, snippet insertion, `addCapabilityToManifest` editing
`swiftcode.json` in place, save-all, navigation targets),
`SDKCodeFindCoordinator` + `SDKCodeFindableEditor` (literal substring
search, case-insensitive fold, UTF-16 ranges, wrap-around, "N of M"
summary), `SDKBuildRunRequest`/`SDKBuildRunKind`,
`SDKCodeBuildRunner` (actor: `validateProject` via the strict
validator; `run` executes real `xcodebuild` / `npm run build` /
`node <entry>` processes streaming stdout/stderr into the console;
cancel by taskID — SIGTERM then SIGKILL after 3 s),
`SDKSnippet`/`SDKSnippetStore` (one synthesized snippet per canonical
capability, optional `snippets.json` override with Legacy's fill-gaps
rule, category filters, TS/Swift/manifest variants).

Already-served (NOT re-ported), with Ycode locations:
- Full editor buffer/document/undo/disk-change model: `YcodeEditorKit`
  `EditorDocument` / `EditorBuffer`.
- Full lexers / token model: `YcodeSyntax` `SyntaxLanguage` /
  `SyntaxToken` / `SwiftClassifier` / `SwiftLineLexer` / `CFamilyLexer`.
  Note `SyntaxLanguage` has no TypeScript/JavaScript case — the Studio
  highlighter covers those two, which is why the compact adapter exists.
- Editor UI (Canvas painter, gutter, completions, find bar):
  `ycode-ide` `SourceEditorView` / `SourceEditorController`.
- Manifest validation (install gate): `YcodeExtensions`
  `SwiftCodeManifestValidator`.
- Extension lifecycle / registry: `YcodeExtensions`
  `ExtensionManager`, `ExtensionStorage`, `DiagnosticsService`.
- Grants: `YcodeExtensions` `PermissionManager`.
- Secrets: `YcodeAssistant` `SecretStore` protocol (assistant keys
  only — not a substitute for the SDK API-key store).

Deviation D-1 — window manager: Legacy `SDKStudioWindowManager` owns
an `NSWindow` via `NSHostingController`. `ycode-ide` views are pure
SwiftUI (no AppKit in this target — none of its views import AppKit),
so `SDKStudioWindowManager` here is section persistence + presentation
state only, using Legacy's exact UserDefaults keys
(`com.swiftcode.sdk.studio.lastSection`,
`com.swiftcode.sdk.studio.isOpen`). The macOS AppKit shell
(YcodeUI/YcodeApp) must host `SDKStudioView` in its own window and
drive it through `openStudio(section:)` / `closeStudio()`.

Deviation D-2 — file panels: Legacy uses `NSOpenPanel`/`NSSavePanel`/
`NSWorkspace` in Projects, editor, installer, and Ship & Export. This
target has no file panels, so directory/project/destination selection
is a path text field with the same validation Legacy's panel flow
applied (target must be empty or nonexistent; project must contain a
recognisable project file). The AppKit shell can replace the path
fields with panels.

Deviation D-3 — editor hosting: the full Canvas editor
(`SourceEditorView`) needs a `WorkspaceShellModel` session, which the
Studio pane does not own. The Studio pane therefore edits through the
Studio buffer (`SDKCodeDocument`, as Legacy did) in a plain
`TextEditor`, with Ycode machinery around it (find coordinator wired
to the live tab text, highlighting tokens available via
`SDKKeywordHighlighter`, save/disk-change via the state, build/run via
the runner). Embedding the Canvas editor is follow-up work (needs a
`WorkspaceShellModel` for the project root). Known gap: find
Next/Previous compute real matches and the bar reports them, but the
`TextEditor` surface cannot move the caret to a match (needs the
AppKit editor view); the find adapter's `selectFindRange` is a
documented no-op. Go-to-Line is an inline row under the toolbar (not
an alert — OpenViews' `AlertCard` does not promise an editable
`TextField` in alert actions). The snippet library has a Copy button
using the existing `ShellPasteboard.copy(_:)` (copy code only, never
description/metadata, mirroring Legacy's
`SDKSnippetStore.copyCode`); the console view's copy-to-pasteboard was
dropped (no AppKit in this target).

Deviation D-4 — Legacy's managed-build path (`SDKBuildHandle`, host
build service) is not ported; the runner executes local processes
only. The Host slice owns the managed-build seam.

Deviation D-5 — Legacy's `SDKKeywordHighlighter` (919 lines,
per-language keyword tables + Swift/TS string-frame scanning) is
reimplemented as a compact scanner, not line-for-line; the token
contract and its tests are preserved. Legacy's per-scope TS snippet
calls (`ScopesIDLists`) are not reproduced — generated snippets are
starter code (import + capability request shape); the TypeScript
package's exact calls belong to the Host/TS slice.

**Not ported:** `SDKExampleManager` — blocker: Legacy launches the
bundled example project from `SwiftCodeSDK/Examples/
RepositoryBuildExtension`; Ycode has no bundled example project.
Needs a decision on where the example lives (Wave 15).

### 14.6 Ship & Export

`SDKShipExportView` — real `tar` export; no SDK CLI dependency.

## 15. What regenerates vs what is hand-written

| Artifact | Status |
|---|---|
| `sdk/package/dist/` (tsc output incl. `dist/index.js`, `.d.ts`, `.js.map`) | **Regenerated** by `npm run build`. Never copied, never checked in (`.gitignore`: `dist/`). |
| `sdk/package/snippets.json` | **Checked-in build product, regenerated** by `npm run build:snippets` (`scripts/build-snippets.mjs` reads compiled `dist/snippets.js` and writes the manifest). `tests/snippets.test.mjs` fails if the checked-in manifest drifts from the compiled library. Ported verbatim (387 lines). |
| `sdk/package/dist-tests/`, `sdk/cli/dist-package/`, `sdk/runtime-adapter/dist/`, template `dist/` | **Regenerated** build output (`.gitignore`d). |
| `sdk/*/package-lock.json` | **Dropped — regenerate** via `npm install` on Dylan's Mac. |
| `sdk/Distribution/` (assembled SDK) | **Regenerated** by `sdk/scripts/assemble-sdk.sh` (build output, not source). |
| `SwiftCodeSDK-1.0.0.zip/.tar.gz`, `checksums.txt` | **Regenerated** by `sdk/scripts/package-sdk.sh`. |
| `sdk/package/src/ScopesIDLists.ts` | **Regenerated** from the Swift host table by `generate-scopes-ts.py` (§13.1). Never hand-edited. |
| Everything else in `sdk/` (`src/*.ts`, `*.mjs`, `*.md`, `*.json` configs, `*.swift` templates, `*.sh`) | **Hand-written source**, ported verbatim except the `.sh` adaptations in §13.5 and the two schema-path edits in §3. |
| `sdk/runtime-adapter/src/adapter.ts` | **Dropped by design**; must be **rewritten** from the ported README spec (§13.2), not regenerated from anything. Wave 15. |
| `SDK/Distribution/` (Legacy, ~905k lines) | **Generated, never copied.** Its `Scripts/*.py` (11 files) are synthetic filler: 10 hardcode `dest = "/Users/dylan/Downloads/SwiftCode-Debug/…/Distribution/SwiftCodeSDK"` and loop-write stub guides/docs/fixtures for the sole purpose of inflating `Distribution/` past the 200 MB gates. They were dropped, never re-run; the gates are report-only (§13.5). |

## 16. CLI + SDK tools (Swift executables)

Six executable products, each a thin wrapper over a YcodeSDK entry
point (top-level `main.swift`, repo convention — cf.
`ycodebuild-cli`):

| Product | Target | Entry point | Legacy source |
|---|---|---|---|
| `swiftcode-sdk` | `YcodeSDKCLI` | `SwiftCodeSDKCLI.run(arguments:) async -> Int32` | `Sources/CLI/main.swift` — 9 commands (doctor/init/validate/build/test/inspect/package/verify/docs), same help text and output. No `@main`, no `exit()`: returns exit codes; the executable wraps it. |
| `project-generator` | `YcodeSDKProjectGenerator` | `ProjectGeneratorMain.run(arguments:) -> Int32` | `Sources/Tools/ProjectGenerator/main.swift` |
| `project-inspector` | `YcodeSDKProjectInspector` | `ProjectInspectorMain.run(arguments:) -> Int32` | `Sources/Tools/ProjectInspector/main.swift` — pretty-printed sorted-keys JSON |
| `extension-validator` | `YcodeSDKExtensionValidator` | `ExtensionValidatorMain.run(arguments:) -> Int32` | `Sources/Tools/ExtensionValidator/main.swift`, via `SDKManifestValidator` |
| `diagnostics` | `YcodeSDKDiagnostics` | `DiagnosticsToolMain.run(arguments:) -> Int32` | `Sources/Tools/DiagnosticsTool/main.swift` |
| `documentation-indexer` | `YcodeSDKDocumentationIndexer` | `DocumentationIndexerMain.run(arguments:) -> Int32` | `Sources/Tools/DocumentationIndexer/main.swift` — prints the Markdown inventory only (Legacy wrote no index file either) |

No `sdk-test-runner` product: Legacy's `Tests/SDKTestRunner` +
`SDKTests` is a hand-rolled `print`-and-`exit(1)` runner, superseded
by XCTest (`ycode/Tests/YcodeSDKTests/`).

## 17. Public API signatures (contract for the implementation)

```swift
// Contracts
public struct SDKError: Error, Sendable { public let code: SDKErrorCode; public let message: String; public let suggestion: String?; public let diagnostics: [String: String] }
public enum SDKIPCCodec { public static func decodeEnvelopeType(_ data: Data) throws -> SDKMessageType; public static func encodeRequest(_ request: SDKIPCRequest) throws -> Data; public static func encodeResponse(_ response: SDKIPCResponse) throws -> Data; public static func encodeEvent(_ event: SDKIPCEvent) throws -> Data }
public enum SDKCompatibility { public static func check(protocolVersion: Int, versionRange: String) -> Bool }

// Keys
public actor SDKAPIKeyStore { public static let shared: SDKAPIKeyStore; public func createKey(label: String, scopes: Set<SDKAPIKeyScope>, isLive: Bool, expiresAt: Date? = nil) throws -> (key: SDKAPIKey, secret: String); public func list() -> [SDKAPIKey]; public func revoke(id: UUID) async; public func verify(secret: String) async throws -> SDKAPIKey }
public protocol SDKSecretStoring: Sendable { func read(account: String) throws -> Data?; func write(_ data: Data, account: String) throws; func delete(account: String) throws; func accountNames(withPrefix prefix: String) throws -> [String] }

// Broker / gate / audit
public final class SDKCapabilityBroker { public func authorize(caller: SDKCallerIdentity, capability: SDKCapabilityID) async -> SDKCapabilityDecision }
public enum SDKAssistGate { public static func check(command: String, caller: SDKCallerIdentity) async throws }
public actor SDKAuditLog { public static let shared: SDKAuditLog; public func record(_ type: SDKAuditEventType, detail: String?) async; public func recentEvents(limit: Int) -> [SDKAuditEvent] }

// Dispatcher
public final class SDKIPCDispatcher { public init(session: SDKRuntimeSessionInfo); public func dispatch(_ data: Data) async -> Data; public var eventSink: ((Data) -> Void)? }

// Registry / installer
public final class SDKExtensionRegistry { public static let shared: SDKExtensionRegistry; public func installedExtensions() -> [SDKInstalledExtension] }
public enum SDKInstaller { public static func inspect(prefix: URL? = nil, expectedVersion: String = expectedVersion) -> Inspection; public static func install(options: InstallOptions = InstallOptions(), onLine: @escaping @Sendable (LogLine) -> Void = { _ in }) async -> InstallResult }

// Kits
public enum SwiftCodeSDKCLI { public static func run(arguments: [String]) async -> Int32 }
public struct SDKVersion { public static let current: SDKVersion }
public enum SDKDoctor { public static func diagnose(sdkRoot: URL?) -> [Diagnostic] }
```

## 18. What was NOT ported, honestly unavailable

| Piece | Exact blocker |
|---|---|
| 12 view windows (`SDKViewHost`) | No YcodeUI seam exists under Legacy names (no `DatabaseExplorerWindowManager` etc., no `ToolbarActionManager`). Opener logic ported; windows delegate to the new `SDKViewHost` protocol — YcodeUI must implement it. Until then opens throw `.serviceUnavailable` naming the missing seam. |
| Assist backend (`SDKAssistBackend`) | No attachment point exists that wouldn't leak user conversation/keys (`AssistManager` / agent sessions / `LLMService` audited and rejected). `send` / `sendStreaming` / `executeTool` throw `.serviceUnavailable`, never fabricate. |
| Real Assist choke points | Host session loop / LLM service have no extension caller identity — the gate guards the IPC surface only. |
| Build scheme discovery | No `AssistXcodeProjectResolver` / `xcodebuild -list` seam — container resolved from project root, target used as scheme. |
| Installer bundled fallback | No tarball ships in-repo; falls back honestly when absent. |
| Runtime adapter `adapter.ts` | Dropped by design; rewrite from the ported README spec (§13.2). Wave 15. |
| `cli-roundtrip` + `scopes-sync` tests | Ported verbatim but cannot pass yet: Legacy-shaped path math (repo root 5 levels up from `tests/`, `SwiftCode/SDK/TypeScript/...` trees) + need the adapter rewrite (B2) and the schema (B3, now resolved). Adapt in Wave 15. |
| Grant tombstones / digests / names (S-2) | `PermissionManager` (`grants.json`) keeps no tombstones, digests, or display names. Needs a grant-record store or tombstone support. Wave 15. |
| `use.Security` store listing (S-4) | `SDKSecurityService` has per-app operations but no list-all-apps enumeration. Needs a host enumeration API. Wave 15. |
| Assist application submission (S-5) | The Studio form has no SDK-variant picker and no API key secret; `SDKAssistApplication.Field` requires both. Wave 15 must add a variant picker + API-key picker first. |
| `SDKExampleManager` | No bundled example project in Ycode. Needs a decision on where the example lives. Wave 15. |
| Managed-build `SDKBuildHandle` | Studio code editor's xcodebuild path; the runner executes local processes only (D-4). |
| Canvas editor embedding (D-3) | Needs a `WorkspaceShellModel` for the project root; find caret-move is a documented no-op until then. |

## 19. Known Legacy defects, ported faithfully (not silently fixed)

1. `SourceControlService` ahead/behind: parses real counts (Legacy wrote literal `1`).
2. `ExtensionPackager.fileCount`: real count (Legacy hardcoded `1`).
3. `SwiftCodeSDKCLI` `test`: Legacy appends `["test", "--disable-sandbox"]` *after* `swift build …` args, producing `swift build … test --disable-sandbox`, which `swift build` rejects. Ported as-is; the fix is `swift test …` (or a `BuildService.test` entry point) in the build slice.
4. `ProjectGenerator` `xcodeProject`/`macosApp`: generates a SwiftPM executable template with SwiftUI source, not a real `.xcodeproj`. Legacy behaviour; real `.xcodeproj` generation belongs to the project-model slice (`YcodeProject` pbxproj writer).
5. `ProjectInspector` `.xcodeproj` detection is name-only; no pbxproj parsing.
6. `SourceControlService.getStatus` collapses `A`/`D`/`R`/`C` porcelain codes to `.modified` (Legacy behaviour; only `??` → `.untracked` is distinguished).
7. `BuildService` has no timeout/cancellation: Legacy blocked on `waitUntilExit()`; `Subprocess.run` is likewise synchronous. The `SDKBuildContracts` timeout/cancel semantics live with the host dispatcher.
8. `SDKAssistApplication.Field.apiKey` stores the presented secret (§5 flag).

## 20. Name collisions (faithful names kept; consumers must qualify)

| Type in YcodeSDK | Collides with |
|---|---|
| `Diagnostic` | `YcodeBuild.Diagnostic`, `YcodeAssetCatalog` (AssetCompiler), `YcodeStrings` (StringCatalogCompiler) |
| `BuildResult` | `YcodeBuild.BuildResult` |
| `Workspace` | `YcodeWorkspace.Workspace` |
| `ProjectGenerator` | `YcodeIDECore` (NewProject `ProjectGenerator`) |

No collision exists for `SDKError`, `SDKVersion`, `WorkspacePath`,
`SafeFileAccess`, `DiagnosticEngine`, `ExtensionPackager`,
`SwiftCodeSDKCoordinator`, `SDKDoctor`, `SourceControlService`,
`Toolchain`, `ProjectMetadata`, `GitStatus`, or the contract types.

## 21. Coordinator decisions (Wave 14)

1. **Scopes list (B1):** regenerated from the Swift host table
   (§13.1) instead of copying Legacy's TS file — the ported Swift
   table is the destination's host truth; the Legacy TS file's order
   and descriptions had already drifted from it.
2. **Schema home (B3):** `sdk/Contracts/Manifest/` — mirrors Legacy's
   `SDK/Contracts/Manifest/` inside the destination SDK root, and is
   the single path all three consumers resolve (generator, `dev`,
   assemble script).
3. **Grantability:** Legacy table is the authority for SDK-host
   decisions; `isGrantable` stays the generic v2 rule (§4).
4. **Registry roots:** distinct (`SwiftCode/Extensions` for
   `swiftcode.json` packages vs `ExtensionsV2/` for v2 manifests) (§11).
5. **Versions:** 1.0.0 (package) vs 1.2.0 (host SDK) are different
   quantities; both kept (§3).
6. **BuildKit overlap:** both the kit-level and host-adapter build
   services stay; the dispatcher routes `build.execute` to the host
   adapter (§10).
7. **Studio target split:** `YcodeSDKStudio` created to avoid the
   `YcodeExtensions` ↔ `YcodeSDK` dependency cycle (§1).
8. **Seams wired by the coordinator:** S-1 (installer), S-3 (API
   keys), G-1 (audit log). S-2, S-4, S-5 stay open for Wave 15 with
   the exact blockers in §18.
9. **Secret storage flag:** `SDKAssistApplication` keeps Legacy's
   presented-secret storage; a key-ID-only revision is flagged, not
   silently applied (§5).

## 22. Tests

`ycode/Tests/YcodeSDKTests/` (XCTest, no live network, no real
credentials, test-only keys, in-memory stores):

- `YcodeSDKTests.swift` — error taxonomy/titles/Codable; IPC envelope
  round-trips, oversize/malformed rejection, NDJSON single-line
  property; version negotiation incl. `^0.x` pinning; tolerant
  decoding of `SDKDiffOptions` / `SDKSandboxRunRequest` (incl.
  wrong-type rejection); security contracts carry no secret bytes;
  cloud-model + build contract round-trips; `SDKRepositoryStatus`
  empty shape; `DiagnosticEngine` counts/formatters;
  `WorkspacePath.isWithin` traversal cases; `SafeFileAccess`
  read/write/traversal denial; `Workspace.discoverProjects`;
  `BuildDiagnosticsParser` Swift + TS lines; `ProjectInspector`
  (missing → throws; package; extension precedence);
  `ProjectValidator`; `ProjectGenerator` Swift-package round-trip;
  example-manifest fixture validates clean via the adapter; invalid
  JSON rejected; live-git `SourceControlService` against the Ycode
  repo itself (branch/log) + non-repo throws; `Toolchain` shape;
  `SDKDoctor` shape; `SDKVersion`/`SDKConfiguration`; CLI
  help/version/unknown/validate + fixture validate; tool mains
  (validator, indexer, doctor-exit-code-matches-doctor-verdict).
- `SDKAPIKeyTests.swift`, `SDKCapabilityTests.swift`,
  `SDKManifestValidationTests.swift`, `SDKRedactionTests.swift`,
  `SDKBuildParserTests.swift`, `SDKTerminalValidationTests.swift`,
  `SDKSecurityValidationTests.swift`, `SDKIPCDispatcherTests.swift`,
  `SDKInstallerTests.swift` — API keys/HMAC (test-only keys,
  in-memory store), capability registry + broker, manifest validation
  via the existing validator, redaction, build parser, terminal
  validation, security validation, IPC dispatcher, installer
  inspection.
- `SDKStudioTests.swift` — Studio-owned tests only: language
  inference, highlighter (token kinds, non-overlap, nested block
  comment, plaintext empty), document/tab/file-node invariants, editor
  state (tabs, save-all, console 4 KiB/5,000 caps, external
  modification clean-reload vs dirty-flag, diagnostics dedup,
  navigation, snippet insert, manifest capability add), find
  coordinator (wrap-around, case sensitivity, summary text, text-change
  recompute), snippet store (35 built-ins, filters, variants),
  build-runner validation (no-manifest warning, invalid manifest
  errors), first-launch choice, installer-unavailable seam, wizard
  validators, scaffold creation for all three wizards (+ non-empty-target
  refusal), recent projects, grant-store adapter (grant → revoke →
  revokeAll), API-key model, Assist-access validation, user logger.

Not covered (needs Mac / live tools): actual `BuildService.build`
execution (no Swift toolchain in this environment),
`ExtensionPackager.package` end-to-end (needs `zip` + a real
extension dir), `SDKDoctor` healthy-path verdict
(environment-dependent by design), `swift build` / `swift test`
themselves — Mac build/test pending on Dylan's Mac throughout.

## Evidence

- **5** — Contracts tables (§2), manifest validator behaviour (§3),
  capability registry + grantability (§4), HMAC secret format and
  storage seams (§5), audit-log paths and rotation (§8), dispatcher
  ordering and timeout (§9), adapter allow-lists and limits (§10),
  registry root and installer idempotence (§11), view-opener registry
  semantics (§12), TS package/CLI/template/script contents (§13),
  Studio sections, wizards, and seams (§14), regenerates table (§15),
  CLI entry points (§16), defect list (§19): read verbatim from
  Legacy source in this pass and verified against the ported code.
- **4** — The 32-scope / 35-capability counts (§4, §13.1): consistent
  across the Swift host table, the TS list, the validator's
  `CAPABILITY_IDS`, and the snippet store.
- **3** — The `SDKAssistApplication` secret-storage flag (§5) and the
  `SDKAssistGate` cloud-denial wording being proposed (§7): single
  Legacy source each, no corroboration beyond the port.
- **2** — The `YcodeSDKStudio` cycle analysis (§1, §21.7): inferred
  from the two slices' import graphs; a SwiftPM load on Dylan's Mac
  will confirm the wiring (the cycle would fail package load).
- **1** — Everything in this spec that depends on compilation:
  `swift build` / `swift test` were never run in this environment (no
  Swift toolchain). Mac build/test pending on Dylan's Mac. The
  `sdk/package` `npm install && npm run build && npm test` run is
  likewise pending on Dylan's Mac (blocked only by that install, not
  by a code blocker, since B1/B3 resolved in Wave 14).
