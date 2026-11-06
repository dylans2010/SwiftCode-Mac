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
(`SDKCapabilityID`, 34 ids); `Contracts/Manifest/SDKManifest.swift` →
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

- The fixed registry is 34 capability IDs (`SDKCapabilityID` in
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
- **Flag — application records store the key ID only (corrected
  in Wave 16, §26.1.3):** the Wave 14 spec claimed Legacy's
  `SDKAssistApplication.Field.apiKey` held the presented secret. Wrong
  — verified live in Wave 16, Legacy's flat `SDKAssistApplication`
  stores `apiKeyID: UUID` and its submit looks the key up by ID. The
  secret field was a Wave 14 port deviation, not Legacy behaviour.
  Wave 16 revised it to key-ID-only (`Field.apiKeyID: UUID`;
  `submit(_:apiKeySecret:)` verifies the presented secret by HMAC +
  liveness, requires the verified key's ID to match the field, then
  drops the secret; legacy secret records migrate by unverified ID
  extraction and re-encode ID-only).
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
- **View host implemented (Wave 16, Slice C, §26.3).** `YcodeSDKViewHost`
  (YcodeUI) implements `SDKViewHost` behind the injectable
  `SDKViewSurfaceActions` protocol and is installed at startup by
  `YcodeSDKInstaller` (with the active-workspace provider and the
  Assist backend attachment; `SDKBootstrap` runs from the same
  installer). 5 of the 12 views open on real Ycode surfaces:
  `deviceconnect.open` → Device Hub (Devices),
  `simulator.view` → Device Hub (Simulators), `uibuilder.open` →
  Interface Builder editor on the project's first `.storyboard`/
  `.xib`, `symbols.browse` → Library panel (Symbols tab),
  `preview.live` → preview canvas; `assist.main` → Coding
  Assistant pane on the same seam. 7 are honestly unavailable
  (`YcodeSDKViewHost.unavailableReasons`): `db.ExploreView` (no
  SQLite browser), `docs.search` (no DocC browser),
  `dictionary.open` (no term data — Legacy's was LLM-generated),
  `sandbox.view` (no integrated terminal), `deployConsole.view`
  (no deployments console), `ci.VisualWF` (no workflow dashboard),
  `virtualization.view` (no console UI for the hypervisor engine).
  All open through the key workspace window; with none open they
  throw `.serviceUnavailable`. The macOS live-preview surface is
  the editor canvas, not `PreviewOpenViewsHost` (the Linux payload
  host).
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
`terminal`, `ui`. All 11 pass under `node --test` (112/112, Wave 15,
§24) after `npm install` + `npm run build` in `sdk/package`.

### 13.2 Runtime adapter (`sdk/runtime-adapter/`)

**Rewritten in Wave 15 from the README spec (§24)** — `src/adapter.ts`
now exists, `npm run build` emits `dist/adapter.js`, and the adapter is
verified live against the protocol (ready / command dispatch /
UNKNOWN_COMMAND / handler-error codes / activation failure / shutdown /
stdin-EOF teardown). The ported `README.md` **is the adapter's protocol
spec**; the rewrite codes against it plus the `@swiftcode/sdk` API
(`createStdioConnection` + `createContext`, §13.1). CLI `node
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
| `validate` | Validate `swiftcode.json` + package contents. Carries an **embedded schema mirror** (patterns + `CAPABILITY_IDS` = 26 SDK ids + 6 `use.Security.*` scopes (32 entries)), so it works without the schema file. |

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
TypeScript-Extensions. Internal cross-references were remapped to
destination paths in Wave 15 (§24); `grep -rn "SwiftCode/SDK/" sdk/`
returns 0. `sdk/docs/Release-Readiness.md` now runs the destination
pipeline (`sdk/scripts/package-sdk.sh` / `sdk/scripts/verify-sdk.sh`);
the Legacy `Distribution/bundle-sdk.sh` / `verify-bundle.mjs` scripts
were never ported (see §15).

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
tombstone, policy version). **S-2 wired in Wave 15 (Slice B):** the
default adapter (`SDKPermissionManagerGrantStore`) now merges live
grants (synthesised from `PermissionManager`, SDK ids mapped back
through `ExtensionCapability.v2Capabilities(for:)`) with the revoked
tombstones kept in the Host slice's `SDKGrantStore` (§6) — revoked
records stay visible with their revocation time, extension name (via
`SDKExtensionRegistry`), and package digest; `revoke`/`revokeAll`
stamp tombstones (best-effort — the live revoke already happened).
The broker still consults the flat `PermissionManager` for live
authorization; precise `PERMISSION_REVOKED` classification via the
record store is follow-up work. Pre-authorization from the manifest
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
per-app `use.Security` values, add/delete/delete-all): **S-4 wired in
Wave 15 (Slice B):** the Host slice's `SDKSecurityService` gained the
host-only `listAllApps()` enumeration (§10) — metadata only (value
IDs, labels, creation times; secret values are never returned) — and
both views default to `SDKHostSecurityStore`, the adapter over it. A
nil store still shows the seam as unavailable instead of writing
secrets to UserDefaults or plain files.

Assist access form: full validated form
(`SDKStudioAssistAccessApplication`, same fields and validation as
Legacy); **S-5 wired in Wave 15 (Slice B):** the form now has the
SDK-variant picker (radio group over the real
`SDKAssistSDKVariant` — `assistSDK.UI` with UI / `assistSDK`
headless, Legacy's verbatim details) and an API-key `SecureField`.
The secret is held in memory only for the submit call, verified
against the Keychain-backed key store, and cleared afterwards — never
a stored property on the model, never persisted by the form.
Submission goes to the Host slice's `SDKAssistApplicationStore`
(`application.submit(apiKeySecret:)`); on success the form shows the
pending status + application id, on error the `SDKError` message.
Approval stays a separate host action — the form never approves.

### 14.3 Logs

Three panes, as Legacy: User (`SDKStudioUserLogger`, sanitized
in-memory entries, correlation-ID search, cap 500); Developer
(Ycode's real `DiagnosticsService` — search, clear, per-extension
counts); Audit — **G-1 wired in Wave 14:** the pane reads the durable
`SDKAuditLog` via `recentEvents(limit: 200)` (§8).

### 14.4 Manifest inspector / editor

One `SDKManifestEditorView` (visual + raw JSON, identity/runtime/SDK
sections, capability toggles with reasons, search + category filter
over all 34 canonical capabilities, contributed commands add/remove,
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
the runner). **Canvas embedding verdict (Wave 15, Slice B): the seam
does not exist as an embeddable unit — left honestly-unavailable.**
The pieces exist (`WorkspaceSession(model:)`,
`WorkspaceShellModel(session:)`, `SourceEditorController(document:)`,
`SourceEditorView(controller:model:palette:preferences:)` in
`ycode-ide`, which already depends on `YcodeIDEShell`), but three
things are missing: (1) no lightweight `WorkspaceSession` /
`WorkspaceModel` for a plain directory root (`WorkspaceModel.init(url:)`
loads a real `.xcodeproj` / `.xcworkspace` / Package; Studio edits
bare extension dirs with only `swiftcode.json`); (2) no
`EditorDocument` bridge from Studio's `SDKCodeDocument` value types
(YcodeEditorKit's disk-backed `EditorDocument` / `EditorBuffer` vs the
Studio tab/document model with its save/disk-change/snippet logic);
(3) `WorkspaceShellModel` is the whole workspace window's model (find
bar, issues, source control, debug, language-server lifecycle) — no
hosted-controller lifecycle for a side pane. Find Next/Previous
compute real matches and the bar reports them, but the `TextEditor`
surface cannot move the caret to a match (needs the AppKit editor
view); the find adapter's `selectFindRange` is a documented no-op.
Go-to-Line is an inline row under the toolbar (not an alert —
OpenViews' `AlertCard` does not promise an editable `TextField` in
alert actions). The snippet library has a Copy button using the
existing `ShellPasteboard.copy(_:)` (copy code only, never
description/metadata, mirroring Legacy's
`SDKSnippetStore.copyCode`); the console view's copy-to-pasteboard was
dropped (no AppKit in this target).

Deviation D-4 — Legacy's managed-build path (`SDKBuildHandle`, host
build service) is **wired in Wave 15 (Slice B):** the runner's
`.xcodebuildSwift` kind now goes through
`SDKBuildService.shared.run(caller:request:)` with the host identity
`studio.editor` (digest SHA-256 of `"swiftcode.sdk.studio.editor"` =
`f4a6727600315b3f0074a3aa515bc73a4ce6f37f5055e97d8f9aecceead8a927`,
embedded as a constant — this target has no Crypto dependency and
`Package.swift` must not be edited), streams `handle.events` into the
console, `await handle.wait()`, appends result diagnostics to editor
state, and cancels via the handle. The service authorizes
`build.execute` for `studio.editor` through the broker exactly as for
an extension — with no grant it fails honestly with
`.permissionDenied` + a diagnostic telling the user to approve it via
the Studio grant manager; the host identity is NOT auto-granted. A
blank scheme fails honestly (Ycode has no scheme-resolver seam; same
gap as §18 build-scheme discovery). Other kinds still run local
processes (npm / node) as before.

Deviation D-5 — Legacy's `SDKKeywordHighlighter` (919 lines,
per-language keyword tables + Swift/TS string-frame scanning) is
reimplemented as a compact scanner, not line-for-line; the token
contract and its tests are preserved. Legacy's per-scope TS snippet
calls (`ScopesIDLists`) are not reproduced — generated snippets are
starter code (import + capability request shape); the TypeScript
package's exact calls belong to the Host/TS slice.

**`SDKExampleManager` — resolved in Wave 15 (Slice B):** Legacy's
concrete example (`SwiftCode/SDK/Examples/RepositoryBuildExtension`,
7 commands) is already ledger-IMPLEMENTED as spec reference material
(extensions-platform.md §2.2) and is NOT re-copied as a bundled
project. Instead `SDKExampleManager` resolves the real minimal
extension project from `sdk/templates/extension-typescript` and
instantiates it with the example identity verbatim from Legacy's
manifest (id `com.example.repository-build-extension`, name
"Repository Build Extension", version `0.1.0`, slug
`repository-build-extension`): `prepareExampleProject()` copies +
instantiates on first use into the managed projects directory
(macOS `~/Library/Application Support/SwiftCode/Projects/
RepositoryBuildExtension`, Linux `~/.config/ycode/projects/
RepositoryBuildExtension`), reuses the copy afterwards, repairs a
missing manifest from the template, and validates (strict manifest
validation, id must equal the example id, `package.json` +
`src/index.ts` must exist). The Projects view has an "SDK Example"
entry that prepares it, records it in recents, and opens it in the
code editor. Opening in the workspace is the app shell's job — Ycode
has no `ProjectSessionStore`, so Legacy's open-in-workspace steps are
not reproduced.

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
| `sdk/runtime-adapter/src/adapter.ts` | **Rewritten in Wave 15** from the ported README spec (§13.2, §24). `dist/adapter.js` is regenerated by `npm run build`, never checked in. |
| `SDK/Distribution/` (Legacy, ~905k lines) | **Generated, never copied.** Its `Scripts/*.py` (11 files) are synthetic filler: 10 hardcode `dest = "/Users/<user>/Downloads/SwiftCode-Debug/…/Distribution/SwiftCodeSDK"` and loop-write stub guides/docs/fixtures for the sole purpose of inflating `Distribution/` past the 200 MB gates. They were dropped, never re-run; the gates are report-only (§13.5). |

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
public actor SDKAPIKeyStore { public static let shared: SDKAPIKeyStore; public func createKey(label: String, scopes: Set<SDKAPIKeyScope>, isLive: Bool, expiresAt: Date? = nil) throws -> (key: SDKAPIKey, secret: String); public func list() -> [SDKAPIKey]; public func revoke(id: UUID) async; public func verify(secret: String) async throws -> SDKAPIKey; public func grantEntitlement(_ entitlement: SDKEntitlement, to key: SDKAPIKey) async throws; public func revokeEntitlement(_ entitlement: SDKEntitlement, from key: SDKAPIKey) async throws -> Int }
public protocol SDKSecretStoring: Sendable { func read(account: String) throws -> Data?; func write(_ data: Data, account: String) throws; func delete(account: String) throws; func accountNames(withPrefix prefix: String) throws -> [String] }

// Grant records (S-2, Wave 15 Slice B)
public actor SDKGrantStore { public static let shared: SDKGrantStore; public init(storeURL: URL = SDKGrantStore.defaultStoreURL()); public func activeGrant(extensionID: String, capability: SDKCapabilityID, projectRootPath: String) -> SDKGrantRecord?; public func grants(for extensionID: String) -> [SDKGrantRecord]; public func recordGrants(_ records: [SDKGrantRecord], authorizedByAPIKey apiKey: SDKAPIKey? = nil) async throws; public func revoke(extensionID: String, capability: SDKCapabilityID) throws; public func revokeAll(for extensionID: String) throws; public func recordRevocation(extensionID: String, capability: SDKCapabilityID, packageDigest: String, packageVersion: String, grantedBy: String = "user-approval") throws; public func pruneExpired() throws }

// Security listing (S-4, Wave 15 Slice B)
public actor SDKSecurityService { public func listAllApps() async throws -> [SDKSecurityAppSummary] } // host-only; metadata only, never secret values
public struct SDKSecurityAppSummary { public let securityID: String; public let extensionID: String?; public let values: [SDKSecurityStoredValue] }

// Example manager (Wave 15 Slice B)
public enum SDKExampleManager { public static let exampleID: String; public static func prepareExampleProject(templateURL: URL? = nil, projectsDirectory: URL? = nil) throws -> URL }

// Assist application (S-5, Wave 15 Slice B)
public enum SDKAssistSDKVariant: CaseIterable { case assistSDKUI; case assistSDK; public var displayLabel: String; public var detail: String }
public struct SDKAssistApplication { public static let minimumUsageDescriptionLength: Int } // 40

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
| 12 view windows (`SDKViewHost`) | Implemented in Wave 16 Slice C (§26.3): 5 open on real Ycode surfaces, 7 honestly unavailable with per-window reasons (`YcodeSDKViewHost.unavailableReasons`). A SQLite explorer, DocC browser, coding dictionary, terminal, deployments console, CI dashboard, and VM console remain unbuilt subsystems, not seam gaps. |
| Assist backend (`SDKAssistBackend`) | Attached in Wave 16 Slice C (§26.3) for `send` / `sendStreaming` only (`SDKAssistHostBackend` over the host's text-completion providers; agent providers refused; no key or host conversation crosses the boundary). `executeTool` is still unattached — no grant-enforcing tool runner exists yet. |
| Real Assist choke points | Host session loop / LLM service have no extension caller identity — the gate guards the IPC surface only. |
| Build scheme discovery | Wired in Wave 16 Slice D (§26.4): `XcodeSchemeDiscovery` (`xcodebuild -list -json` → `.xcscheme` files via Ycode's `Scheme.discover` → container-name fallback, reason recorded at every step), wired into `SDKBuildService.run`. |
| Installer bundled fallback | Final decision in Wave 16 Slice D (§26.4): stays absent. A genuine tarball can be produced (`npm pack --dry-run`: 52.8 kB, 29 files), but shipping it needs `Package.swift` resource wiring plus a checked-in binary blob — coordinator decision, not shipped. `SDKInstaller.bundledFallbackStatus()` reports `.absent(reason:)` honestly. |
| Runtime adapter `adapter.ts` | Rewritten in Wave 15 from the README spec (§24). `dist/adapter.js` builds; live smoke tests pass. |
| `cli-roundtrip` + `scopes-sync` tests | Adapted to destination paths in Wave 15 (§24); both pass (13/13 and 4/4; full package suite 112/112). |
| Grant tombstones / digests / names (S-2) | Wired in Wave 15 (Slice B, §25): `SDKGrantStore` in YcodeSDK (tombstones, digests, 30-day prune, `capabilities:request` issuance gate) + Studio adapter merge + grant-manager revoked history. |
| `use.Security` store listing (S-4) | Wired in Wave 15 (Slice B, §25): host-only `SDKSecurityService.listAllApps()` (metadata only) + `SDKHostSecurityStore` default in both security views. |
| Assist application submission (S-5) | Wired in Wave 15 (Slice B, §25): variant picker over real `SDKAssistSDKVariant` + in-memory-only `SecureField` secret + `submit(apiKeySecret:)` against the existing approval flow. |
| `SDKExampleManager` | Wired in Wave 15 (Slice B, §25): template-based (`sdk/templates/extension-typescript`) with Legacy's example identity verbatim; no bundled copy. |
| Managed-build `SDKBuildHandle` | Wired in Wave 15 (Slice B, §25): Studio runner's `.xcodebuildSwift` kind goes through `SDKBuildService`; fails honestly with `.permissionDenied` when ungranted, never fakes a build. |
| Canvas editor embedding (D-3) | Verdict in Wave 15 (Slice B, §25): the seam does not exist as an embeddable unit — no lightweight `WorkspaceSession` for a plain directory root, no `EditorDocument` bridge from `SDKCodeDocument`, no hosted-controller lifecycle in `WorkspaceShellModel`. Left honestly-unavailable; find caret-move stays a documented no-op. |

## 19. Known Legacy defects, ported faithfully (not silently fixed)

1. `SourceControlService` ahead/behind: parses real counts (Legacy wrote literal `1`).
2. `ExtensionPackager.fileCount`: real count (Legacy hardcoded `1`).
3. `SwiftCodeSDKCLI` `test`: Legacy appends `["test", "--disable-sandbox"]` *after* `swift build …` args, producing `swift build … test --disable-sandbox`, which `swift build` rejects. Ported as-is; the fix is `swift test …` (or a `BuildService.test` entry point) in the build slice.
4. `ProjectGenerator` `xcodeProject`/`macosApp`: generates a SwiftPM executable template with SwiftUI source, not a real `.xcodeproj`. Legacy behaviour; real `.xcodeproj` generation belongs to the project-model slice (`YcodeProject` pbxproj writer).
5. `ProjectInspector` `.xcodeproj` detection is name-only; no pbxproj parsing.
6. `SourceControlService.getStatus` collapses `A`/`D`/`R`/`C` porcelain codes to `.modified` (Legacy behaviour; only `??` → `.untracked` is distinguished).
7. `BuildService` has no timeout/cancellation: Legacy blocked on `waitUntilExit()`; `Subprocess.run` is likewise synchronous. The `SDKBuildContracts` timeout/cancel semantics live with the host dispatcher.
8. `SDKAssistApplication.Field.apiKey` — REMOVED from this list in Wave 16: it was never a Legacy defect. Legacy stored `apiKeyID: UUID`; the secret field was a Wave 14 port deviation, corrected to key-ID-only in §26.1.3.
9. `SDKAssistGate.check` deny-list contains mixed-case `"sendMessage"`
    matched against a lowercased method, so it never matches (Legacy
    defect, ported faithfully in Wave 14; the exemption itself is
    case-insensitive since Wave 15 Slice B, so `ASSIST.INVOKE` passes
    like Legacy).

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
9. **Secret storage flag — resolved in Wave 16 (§26.1.3):** the Wave 14 claim that Legacy stored the presented secret was wrong (Legacy stored `apiKeyID: UUID`); the port now stores the key ID only (§5).
10. **Wave 15 (Slice B) — S-2 home:** the grant-record store lives in
    `YcodeSDK` (`SDKGrantStore`), NOT as tombstone support in
    `PermissionManager` — the item allowed either, and
    `PermissionManager` lives in `YcodeExtensions` outside the slice's
    editable dirs. The Studio adapter bridges the flat live store +
    the record store. The broker still authorizes from the flat store.
11. **Wave 15 (Slice B) — S-5 secret:** the API key secret is a
    `SecureField` held in memory only for the submit call and cleared
    afterwards — never a stored property on the model, never
    persisted by the form. Verified against the Keychain-backed key
    store at submit.
12. **Wave 15 (Slice B) — ExampleManager:** template-based, not a
    re-copy of Legacy's concrete 7-command example (already spec
    reference material). The example identity (id/name/version/
    description/slug) is verbatim from Legacy's manifest.
13. **Wave 15 (Slice B) — managed build:** the `studio.editor` host
    identity is NOT auto-granted; `build.execute` goes through the
    broker exactly as for an extension. No second grant path.
14. **Wave 15 (Slice B) — Canvas:** embedding left
    honestly-unavailable; the seam does not exist as an embeddable
    unit (§14.5 D-3). No code change was made for it beyond spec text.

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
- `SDKAssistApplicationTests.swift`, `SDKAssistEnforcementTests.swift`
  (Wave 15 Slice B, §25) — ports of Legacy's Assist application +
  enforcement suites, adapted to Ycode shapes (§25.2/§25.3): field
  validation (throwing, 40-char minimum, conditional descriptions,
  email), submit rejection (unknown extension → `.invalidArgument`,
  unknown key → `.apiKeyInvalid`), approve → entitlements
  (third-party models grant both, otherwise Assist only), deny →
  no grant, single-shot decide; entitlement round-trip
  (grant/revoke idempotent, revoked key → `.apiKeyRevoked`),
  verbatim denial messages pinned as literals at every entry point
  (createSession/send/sendStreaming `.failed`/executeTool/UI opener),
  forged-manifest claim never grants, gate exempts exactly
  `assist.invoke` (case-insensitive), cloud gate
  (`.cloudModelDenied` verbatim without allows-cloud, authorized
  with), revoke-closes-sessions (count returned, next call denied).
  Real shared stores + real secret-store I/O, like Legacy's
  real-Keychain tests; test keys labeled `SDKTest-assist-…` /
  `SDKTest-enforcement-…`, revoked in tearDown; application records
  have no delete API and remain as inert test data under the fixed
  test extension IDs.
- `SDKGrantStoreTests.swift`, `SDKSecurityListingTests.swift`
  (Wave 15 Slice B, §25) — grant store on injected temp URLs
  (record/lookup, scope mismatch, tombstone on revoke/revokeAll/
  `recordRevocation`, 30-day prune keeping tombstones,
  `capabilities:request` issuance gate fail-closed, corrupt-file
  moved aside); security listing on the real secret store with a
  test-only namespace (grouping by namespaced Security ID, metadata
  only — the secret marker never appears in the encoded summaries,
  empty namespace not invented, delete-all removes it from the
  listing).
- `SDKStudioTests.swift` — Studio-owned tests only: language
  inference, highlighter (token kinds, non-overlap, nested block
  comment, plaintext empty), document/tab/file-node invariants, editor
  state (tabs, save-all, console 4 KiB/5,000 caps, external
  modification clean-reload vs dirty-flag, diagnostics dedup,
  navigation, snippet insert, manifest capability add), find
  coordinator (wrap-around, case sensitivity, summary text, text-change
  recompute), snippet store (34 built-ins, filters, variants),
  build-runner validation (no-manifest warning, invalid manifest
  errors), **managed-build honest failure (Wave 15 Slice B, §25):
  `run(.xcodebuildSwift)` with no grant for `studio.editor` appends a
  `PERMISSION_DENIED` diagnostic — engine-independent, since
  authorization runs first**, first-launch choice,
  installer-unavailable seam, wizard validators, scaffold creation for
  all three wizards (+ non-empty-target refusal), recent projects,
  grant-store adapter (**Wave 15 Slice B: revoked grants stay as
  tombstones with revocation time; tombstone carries the extension
  name + package digest; injected temp record store**), API-key model,
  Assist-access validation, **Assist mapping (Wave 15 Slice B:
  `sdkVariant` default `.assistSDKUI`, 40-char boundary, `makeField`
  third-party splitting)**, **ExampleManager (Wave 15 Slice B:
  prepare from the repo template, manifest id check, second call
  reuses the copy)**, user logger.

Not covered (needs Mac / live tools): actual `BuildService.build`
execution (no Swift toolchain in this environment),
`ExtensionPackager.package` end-to-end (needs `zip` + a real
extension dir), `SDKDoctor` healthy-path verdict
(environment-dependent by design), `swift build` / `swift test`
themselves — Mac build/test pending on Dylan's Mac throughout.

## 23. Wave 15 — SDK provider paths / router / selection (Slice D)

Sources read live for this section (Legacy read-only, main
`d51a8f0d`; destination main `faf89bd8` at wave start):
`SwiftCode/Backend/Assist/AssistModels.swift`,
`AssistProviderConfiguration.swift`, `AssistModelRouter.swift`,
`AssistModelManager.swift`, `AssistModelEligibilityPolicy.swift`,
`AgentModelAdapter.swift`, `HermesProvider.swift`
(`HermesModelID` only), `SCCloudModel.swift`
(`SCCloudConfiguration` constants only),
`SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaAssistProvider.swift`,
`MuseCodeCLIHelper.swift` (discovery + credential files only),
`SwiftCode/SDK/Contracts/Protocol/SDKCloudModelContracts.swift`,
`SDK/Host/ServiceAdapters/CloudModel/SDKCloudModelAdapter.swift`,
`SwiftCode/Views/Settings/GeneralSettingsView.swift:1880-1896`
(`proSection`, for the paywall half — see storekit-paywall.md
§12). Destination: `ycode/Sources/YcodeAssistant/` (host),
`ycode/Sources/YcodeSDK/` (already-ported cloud contracts /
adapter), `ycode/Sources/YcodePaywall/` (entitlement rule).

### 23.1 What landed

`ycode/Sources/YcodeAssistant/AssistModelRouting.swift` (new)
ports Legacy's selection rules faithfully onto Ycode's Assist
host. It sends nothing itself: it picks a provider + model and
the host's `AssistantProvider.send` does the work. No LLM call,
no network call, no credential access in the file.

| Legacy piece | Destination |
|---|---|
| `ModelCapabilities` (11 flags + `standardCloud` / `advancedReasoning` / `localFoundation` presets) | `ModelCapabilities` (verbatim) |
| `ModelSpecification` + `specification(for:)` (name-based catalog) | `AssistModelSpecification.specification(for:)` — provider mapped onto `ProviderKind` (see §23.2) |
| `AgentModelContextBudget` (reserve 4096, `maxInput = max(1024, window − 4096)`, `text.count / 4` estimate) | `AgentModelContextBudget` (verbatim) |
| `contextBudget(for:)`, `normalizePrompt` | Same names on `AssistModelSpecification` |
| `AssistModelEligibilityPolicy` (free-only: ID must contain "free", case-insensitive) + `AssistModelEligibilityError` | Verbatim |
| `OpenCodeModelID` (`opencode:<provider>/<model>`) | Verbatim |
| `HermesModelID` (`hermes:<spec>`, provider/model split) | Verbatim |
| `OpenCodeConfiguration` (server URL, agent name, `managedServerEnabled`, `swiftcodeAgentDefinition` verbatim, loopback-only managed startup, port) | Verbatim shape; storage bridged to `AssistantSettings` (see §23.3) |
| `AssistModelRouter.resolveDefaultModel` (cloud short-circuit → discovered match → AFM synthetic → spec synthesis) | `AssistModelRouter.resolveDefaultModel` (static) |
| `eligibleCandidates` (agentic + tool-calling + configured + credentials + not quarantined; provider-models-only excludes custom; cloud appended after the agentic filter) | `eligibleCandidates` (actor method) |
| `rankModels` (preferred → fewest failures → priority → subagents → context window) | `rankModels` (static; actor `ranked` uses live counts) |
| `classify` / `isQuotaOrRateLimit` / `markRateLimited` (60s) / `markAuthenticationFailed` (600s) / `markModelUnavailable` (120s + count) / `markModelHealthy` / `clearAllQuarantines` / `isModelQuarantined` | Verbatim rules; classification is text-only (see §23.2) |
| `buildContinuationPrompt`, failover `handleTurnFailure` (record → auto-switch-off returns nil → exclude failed, whole provider on quota/auth → next ranked + handoff + `ModelFailoverEvent`) | Verbatim; returns `(nextModel, continuationPrompt)` only (no SDK config — see §23.4) |
| `isUserProvidedModel` / `isUserProvidedSelectedModelID` | Verbatim (cloud/hermes/opencode excluded) |
| `AssistProviderSelection.provider(for:)` (prefix-first routing) | `AssistantBackends.providerKind(forModelID:)` + `provider(forModelID:)` through the existing `provider(_:)` dispatch — no second dispatcher |
| `AssistModelManager.selectedModelID` resolution | Covered by `resolveDefaultModel` + `settings.model(for:)`; `customModelID` persisted as `AssistantSettings.customModelID` |

### 23.2 Adaptations (host has no Antigravity SDK)

- **Provider mapping.** Legacy's `AssistModelProvider`
  (openAI, anthropic, gemini, mistral, meta, kimi, openRouter,
  openCode, hermes, codex) becomes Ycode's `ProviderKind`.
  Vendors Ycode has no direct provider for (Anthropic, Gemini,
  Mistral, Kimi, DeepSeek, the Meta vendor API) map to
  `.openRouter`, the host that can serve those models — the
  same fallback Legacy's own `llmProvider` mapping used for
  meta/kimi. `codex` → `.codex`, `ollama`/`lmstudio` →
  `.ollama`, Apple/Foundation → `.foundationModels`. Two
  prefix branches are Ycode additions: `hermes:` → `.hermes`
  (Legacy had no `hermes:` branch — a Hermes id fell through
  to the OpenRouter default, which its own fail-closed guards
  then had to catch) and `swiftcode-cloud:` → `.scCloud`
  (Legacy routed cloud ids through a separate router
  short-circuit).
- **Routing strategy.** `AssistRoutingStrategy`:
  `.providerDefault` (Legacy `"default"`) and `.appModels`
  (Legacy `"app_models"`). Legacy's `"default"` / `"rotation"`
  restricted selection to the Antigravity SDK's live model
  catalog (`"rotation"` additionally rotated Gemini API keys).
  Ycode has no such catalog and no key-rotation system, so
  both collapse to the discovered set; `"rotation"` (and any
  unknown value) decodes to `.providerDefault`. The strategy
  is still persisted, because the distinction matters again
  if a catalog ever exists.
- **Failure classification is text-only.** Legacy also
  matched `NSURLErrorDomain` codes; this portable target
  does not import FoundationNetworking, and the text checks
  ("timed out", "network", "cannot connect") cover the same
  cases.
- **Legacy's faithful quirks kept:** `classify` never
  returns `.rateLimited` / `.unsupportedCapability` /
  `.malformedResponse` (rate limits classify as
  `.quotaExhausted`; anything unmatched falls through to
  `.internalAntigravityFailure`). The adapter's Apple
  Foundation context window (8,192) disagrees with the
  router's AFM synthetic model (16,000); both values are
  preserved in their own paths — a Mac check should settle
  which is real.
- **No `@MainActor` singleton, no `@Observable`.** Legacy's
  router was `AssistModelRouter.shared` with SwiftUI state.
  Here it is an actor the host owns; the pure rules are
  `static` so tests can call them without an instance.

### 23.3 Provider configuration (persisted in Ycode's settings store)

`AssistantSettings` (`ycode/Sources/YcodeAssistant/AssistantSettings.swift`,
persisted as JSON under `Ycode.codingAssistant` via
`Preferences.codingAssistant` — the settings store; no new
store was invented) gains, all with Legacy's defaults:

| Field | Legacy source | Default |
|---|---|---|
| `routingStrategy: AssistRoutingStrategy` | `assistModelRoutingStrategy` | `.providerDefault` |
| `automaticallySwitchModels: Bool` | `assistAutomaticallySwitchModels` | `true` |
| `useProviderModelsOnly: Bool` | `assistUseProviderModels` | `false` |
| `onlyUseFreeModels: Bool` | `onlyUseFreeModels` | `false` |
| `useSwiftCodeCloudModel: Bool` | `useSwiftCodeCloudModel` | `false` |
| `openCodeAgentName: String` | `OpenCodeConfiguration.agentName` | `"swiftcode"` |
| `customModelID: String` | `AssistModelManager.customModelID` / `AppSettings.customModel` | `""` |

`OpenCodeConfiguration` reads/writes through
`init(settings:)` / `apply(to:)` instead of Legacy's
UserDefaults keys (`opencode.serverURL`,
`opencode.agentName`, `opencode.managedServerEnabled` —
recorded in the type's documentation only). No secret is
persisted here: OpenCode model credentials live in OpenCode's
own configuration, the SCCloud fingerprint stays in the
secret store, and API keys stay in `SecretStore`.

Settings UI (`ycode/Sources/YcodeUI/App/CodingAssistantSettingsPane.swift`,
same pane Wave 9's provider fields live in): a "Model
Routing" section (strategy pop-up + the four toggles above
with Legacy's help text), an "Agent name" field under
OpenCode, and an "Assist with Meta" section showing the
`muse` binary's status like the Hermes section does.

### 23.4 MetaAssistProvider — what it is, what is not ported

**Verified live:** `MetaAssistProvider` is NOT Meta's vendor
API. It is "Assist with Meta", powered by the **Muse Code
SDK/CLI** (`muse` binary) through an MSP (JSON-RPC) host
bridge (`MuseCodeMSPBridge`: `initialize` / `model/list` /
turns). Legacy's vendor-API provider (`AssistModelProvider.meta`,
endpoint `https://api.meta.ai/v1/chat/completions`, marked
"// Example" in source) is a different, unused thing; no Meta
vendor provider is invented in Ycode.

Ported (`ycode/Sources/YcodeAssistant/MetaAssistProvider.swift`,
new `ProviderKind.metaAssist`, wired into
`AssistantBackends.provider(_:)`): the identity
(`meta_assist`, "Assist with Meta", default model
`muse-wonder-1.0`), the fallback catalog (three models,
context 1,007,997, output 128,000, reasoning variants),
availability through the `muse` binary + credential files
(`~/.config/muse/auth.json`, `~/.muse/auth.json` —
existence only, never read), and discovery of the binary in
PATH, the usual folders, plus Legacy's extra `~/.muse/bin/muse`.

**Not ported:** the MSP bridge itself
(`MuseCodeMSPBridge`), `MetaAssistLifecycleManager`,
`MetaSlashCommandManager`, `MuseOtherModelsBridge`, the turn
executor (`executeTurn` with streaming text/thinking deltas,
tool normalization against Legacy's `AssistManager`
registry, turn tracker), and `normalizeToolName`. Those are
a whole JSON-RPC host session, not a provider adapter. Until
a later wave ports the bridge, `send` throws
`AssistantError.unsupported` naming it — it never fabricates
a reply and never reroutes the turn to another provider.
Availability reports `.ready` with the fallback catalog when
the CLI is installed and signed in (Legacy's own
`discoverModels` gate), which is the established wave
pattern for a registered-but-blocked capability; the
`send` failure names the prerequisite.

### 23.5 SDKCloud contracts — already ported, not duplicated

`SDKCloudModelContracts.swift` (52 lines: history entry +
`cloudModel.complete` request) and
`SDKCloudModelAdapter.swift` (234 lines) were already ported
in Wave 14 (`ycode/Sources/YcodeSDK/Contracts/SDKCloudModelContracts.swift`,
`Host/ServiceAdapters/CloudModel/SDKCloudModelAdapter.swift`)
and are **not** re-ported here. Verified: the adapter
authorizes `.useSwiftCodeModel`, validates the bounds, runs
the `SCCloudRateLimiter` pre-check, and completes through
YcodeAssistant's `SCCloudProvider` via `AssistantProvider` —
never a parallel client. Unconfigured cloud maps to
`.serviceUnavailable`. The only Wave 15 addition on this
seam is `SCCloudProvider.isCloudModelID(_:)` (Legacy
`SCCloudConfiguration.isCloudModelID`) and
`displayNameFallback` ("SwiftCode Cloud Model"), which the
router needs; the contract/adapter files are untouched.

### 23.6 What was NOT ported, honestly unavailable

| Piece | Exact blocker |
|---|---|
| `buildSDKConfiguration` / `selectModelForSDK` | Wired in Wave 16 Slice D (§26.4): `SDKSessionConfiguration` + `AssistModelRouter.selectModelForSDK` on `ChatRequest` + the chosen `ProviderKind`, with Legacy's execution-mode rules. Fields only a live Antigravity session consumes were not carried over (documented in the file header). |
| Gemini key rotation on failover | Wired in Wave 16 Slice D (§26.4): `GeminiKeyRotationManager` ports `AlternativeKeyManager` verbatim (fewest-failures-then-circular, 60s cooldown); raw keys in `SecretStore`, metadata-only envelope. |
| Google OAuth auth mode | No `GoogleAccountAuthService` in Ycode (separate GoogleAccount slice). No OAuth token path exists in the router. |
| Antigravity SDK catalog (`sdkDefaultModelIDs`, `createSyntheticSDKModel`) | Wired in Wave 16 Slice D (§26.4): 9 seed models verbatim, `agy models` fetch, synthetic candidates marked `isSynthetic`. No Python fallback (Legacy's vendored Google Cloud SDK python was never copied). |
| Muse Code MSP bridge + Meta turn execution | Wired in Wave 16 Slice B (§26.2): `MuseCodeMSPBridge` (NDJSON JSON-RPC), lifecycle manager, 36 slash commands, turn executor, `normalizeToolName` against the injected MCP catalogue. `send` no longer throws for a missing bridge. |
| `AssistModelDiscoveryService` (1,185 lines) | Wired in Wave 16 Slice D (§26.4): `AssistModelDiscovery` actor (Gemini / Anthropic / OpenAI / Mistral / Qwen legs, 300s cache, failing leg contributes nothing), feeding the router via `candidates(from:)` — no parallel registry. |
| `AgentModelAdapter.queryModel` / `extractJSON` / `OfflineFallbackManager` | Bound to Legacy's `LLMService` session loop and its offline-fallback provider; the host session loop is out of scope for this slice. |
| `AssistModelManager` singleton | `ObservableObject` + `OfflineFallbackManager` health. Its selection state is covered by `AssistantSettings` + the router. |
| `MetaAssistProvider.normalizeToolName` | Wired in Wave 16 Slice B (§26.2): Legacy prefix-strip + synonym rules verbatim, then lookup in the injected MCP catalogue (`knownToolIDs`, wired by the coordinator in §26.5); unmapped names return `.passthrough` and are recorded. |

### 23.7 Tests

`ycode/Tests/YcodeAssistantTests/AssistModelRoutingTests.swift`
(swift-testing, fixtures only — no live network, no real API
keys): specification prefix/branch mapping, prompt
normalization, context budget, free-only eligibility,
`OpenCodeModelID` / `HermesModelID` parse round-trips and
rejections, `OpenCodeConfiguration` settings round-trip +
loopback/port + agent-definition text, ranking order
(preferred / failures / priority / subagents / context),
eligibility filtering (agentic, configured, quarantine,
provider-models-only, cloud append), `resolveDefaultModel`
(cloud short-circuit, discovered match, AFM synthetic, spec
synthesis), `selectNextModel`, failure classification +
quarantine lifecycle (60s / 600s / 120s durations via
`isModelQuarantined` + `markModelHealthy` /
`clearAllQuarantines`), failover (auto-switch off → nil but
still recorded; on → next model + handoff text; quota
excludes the whole provider; exhaustion → nil),
continuation-prompt text, user-provided model detection,
`providerKind(forModelID:)` / `provider(forModelID:)`
dispatch, `AssistantSettings` routing defaults + Codable
round-trip + unknown `"rotation"` strategy decoding to
`.providerDefault` + missing-keys defaults, and
`MetaAssistProvider` availability (absent binary →
`.notInstalled`, installed without credentials →
`.signedOut`, installed with a fixture auth file →
`.ready` with the three catalog models) + `send` throwing
`.unsupported` naming the MSP bridge. `swift build` /
`swift test` pending on Dylan's Mac (no Swift toolchain in
this environment).

## 24. Wave 15 — Slice A: runtime adapter, test adaptation, docs remap (B2/B4/B5/B7)

Environment: Node v24.22.1, npm 10.9.4. `npm install` was run in
`sdk/package`, `sdk/cli`, `sdk/runtime-adapter` (TypeScript 7.0.2,
`archiver` for the CLI); `node_modules/` are gitignored build inputs
and the regenerated `package-lock.json` files were removed again after
the runs (Wave 14 decision: lockfiles regenerate on Dylan's Mac, not
checked in). No Swift toolchain was used or needed for this slice; no
commit, no push.

### 23.1 B2 — `sdk/runtime-adapter/src/adapter.ts` (new, 300 lines)

Rewritten from the ported README spec (§13.2), coding against the
ported `@swiftcode/sdk` API only — no earlier adapter implementation
was read. Behaviour, verified live with a throwaway fixture extension
(`/tmp` smoke harness, not committed):

- Arg parsing: `--entrypoint` (required), `--manifest`, `--id`,
  `--version`, `--name`, `--help`/`-h` (usage, exit 0). Unknown flag,
  flag missing its value, positional arg, or missing `--entrypoint` →
  stderr + exit 1.
- Manifest: `JSON.parse`; any read/parse failure → stderr + exit 1.
- Identity precedence exactly per README: id flag > manifest > module
  id; name flag > manifest > module id; version flag > manifest >
  `"0.0.0"`. Entry default export must be `{ id, activate, deactivate }`
  with function-valued `activate`/`deactivate`, else stderr + exit 1.
- `createStdioConnection()` + `createContext(connection, { id, name,
  version })`; `activate()` resolving sends `extension.ready {
  extensionId, version, protocolVersion: 1 }`. `activate()` throwing
  sends best-effort `extension.activationFailed { extensionId, message }`,
  then best-effort deactivate + dispose + close, stdout flushed
  (bounded 1 s), stderr `error: activation failed: …`, exit 1.
- `commands.execute { commandId, invocationId, payload }` dispatches
  through `CreatedContext.getCommandHandler`. Missing handler →
  `commands.executeResult { invocationId, ok: false, error: {
  code: "UNKNOWN_COMMAND", … } }`. Handler success → `{ invocationId,
  ok: true, result }`; handler throw → `ok: false` with `code:
  err.code ?? "COMMAND_FAILED"`. `shutdown {}` runs the shared
  teardown and exits 0. stdin EOF/close and SIGTERM also run it (exit
  0). `uncaughtException`/`unhandledRejection` send best-effort
  `extension.error`, then teardown, exit 1. Teardown is
  best-effort `deactivate()` (5 s budget) → `subscriptions.disposeAll()`
  → `connection.close()` → bounded stdout flush → `process.exit(code)`.
  `build.output` / `build.finished` are routed internally by the SDK
  context, never by the adapter.

README gaps found while writing (decisions, not inventions — each is
marked `DECISION` in the source):

1. `commands.executeResult` error shape fixes `{ code, message,
   correlationId }` but never says what `correlationId` is. The adapter
   uses the thrown error's own `correlationId` when it carries one
   (`SDKError` does), else the `invocationId` — the only correlation
   the host can match the result against.
2. `extension.error` shape fixes `{ extensionId, message, detail }`
   but not `detail`'s content. The adapter sends the error stack when
   one exists, else the message.
3. No source supplies an id at all (no flag, no manifest id, no module
   id). An `extension.ready` frame needs an `extensionId`, so this is
   a contract failure (stderr + exit 1), not a silent default.
4. A handler returning `undefined` sends `result: null` so the success
   frame always carries the key.
5. A malformed `commands.execute` event (missing `commandId` or
   `invocationId`) is diagnosed to stderr and ignored — no result
   frame can be addressed without an `invocationId`.
6. The README never specifies an "active" stderr line. The Legacy
   adapter printed `active; awaiting host events`; the rewrite does
   NOT emit that string (it is not in the spec). `cli-roundtrip` was
   adapted to wait on the spec'd stdout `extension.ready` event
   instead (§24.2). SIGTERM is the only signal handled (the README
   names no other); stdin EOF/close are the other clean triggers.

### 23.2 B4 — `sdk/package/tests/cli-roundtrip.test.mjs` (adapted, 13/13 pass)

- Repo root is 3 levels up from `tests/` (was 5); trees are `sdk/cli`,
  `sdk/runtime-adapter/dist/adapter.js`, `sdk/package/dist/index.js`;
  the run-dir `@swiftcode/sdk` symlink points at `sdk/package`.
- Activation wait changed from the Legacy stderr string (see §24.1.6)
  to polling stdout for `"event":"extension.ready"`.
- No test expectation was weakened: determinism (10× byte-identical),
  both `DIGEST_MISMATCH` tampers, `DIGEST_RECORD_MISSING`,
  `MANIFEST_INVALID`, honest xcodebuild-absent and missing-compiler
  paths all still assert exactly as ported.

### 23.3 B5 — `sdk/package/tests/scopes-sync.test.mjs` (adapted, 4/4 pass)

Destination shapes differ from Legacy's in three ways, all verified
live from the Swift files:

- `ScopesIDLists.swift` entries are single-line literals in fixed
  field order, and `ipcMethod`/`viewId` may be omitted entirely
  (default nil) — 3 of 32 entries omit `ipcMethod`. The entry regex
  now matches that shape with both fields optional.
- Capability raw values now come from
  `ycode/Sources/YcodeExtensions/Capabilities.swift` (same
  `case <name> = "<raw>"` shape; the case map still validates every
  entry's capability case and raw value).
- `SDKViewOpenerBuiltIns.swift` registers string-literal view IDs
  (`register(viewID: "db.ExploreView")`, 9 direct) plus three sibling
  `SDK<Area>ViewOpener.register()` calls; each sibling's wire ID is
  read from its `static let viewID = "…"` line. The IDs are already
  wire IDs, so no enum-case mapping is needed; each is still checked
  against the known `SDKCapabilityID` raw values.

Generator bug fixed in the same pass (workspace-side, not the
destination repo): `~/SwiftCode-Migration-Workspace/scripts/
generate-scopes-ts.py` line 132 emitted `capabilityId: "…",,` (double
comma) for all 12 view entries, so `src/ScopesIDLists.ts` did not
parse and `npm run build` failed with TS1136/TS1005 across lines
234–336. Fixed to emit the comma only as the `viewId` separator and
re-ran the generator: 32 entries (12 views, 20 api), `tsc --noEmit`
clean, `dist/index.js` loads, `SCOPES_ID_LIST.length === 32`. The
regenerated file also drops the trailing comma on the 20 api entries
(valid TS, generator output — do not hand-edit; re-run the generator).

### 23.4 B7 — docs remap (44 files modified + `adapter.ts` new)

Every `SwiftCode/SDK/...` cross-reference under `sdk/` is remapped to
a destination path, and every `Docs/Intro-to-SDK.md` citation is
remapped to `specs/ide/sdk-platform.md`. Verification (run live):
`grep -rn "SwiftCode/SDK/" sdk/` → 0 matches;
`grep -rn "Docs/Intro-to-SDK" sdk/` → 0 matches
(`node_modules/` and `dist/` build output excluded — regenerated).

Mapping used (mechanical, then hand-fixed where it would mislead):

- `SwiftCode/SDK/TypeScript/{package,cli,runtime-adapter}` →
  `sdk/{package,cli,runtime-adapter}`; `SwiftCode/SDK/Contracts/
  Manifest/` → `sdk/Contracts/Manifest/`; `…/Contracts/Capability/
  SDKCapability.swift` → `ycode/Sources/YcodeExtensions/Capabilities.swift`;
  `…/Contracts/Protocol/` → `ycode/Sources/YcodeSDK/Contracts/`;
  `…/Documentation/` → `sdk/docs/`; `…/Host/…` →
  `ycode/Sources/YcodeSDK/Host/…`; `…/Studio/…` →
  `ycode/Sources/ycode-ide/SDKStudio/` (directory — the Legacy
  `AssistAccessFormView.swift` file has no single-file destination);
  `…/Internal/SDKConfigStore/SwiftCodeSDK.json` →
  `ycode/Sources/YcodeSDK/Resources/SwiftCodeSDK.json`;
  `…/Internal/` → `ycode/Sources/YcodeSDK/Internal/`; `…/Testing/` →
  `ycode/Tests/YcodeSDKTests/`; `…/Package.swift` → `ycode/Package.swift`.
- `Docs/Intro-to-SDK.md §N` citations → `specs/ide/sdk-platform.md`
  with the Legacy section number dropped: the two specs do not share
  numbering, so carrying the number over would be false precision.
  Where Wave 15 itself wrote the citation against the real spec
  (§13.2 adapter, §13 round-trip, §18 Assist suites, §9/§13.1 adapter
  README), the real section number is kept.
- Deliberate exceptions (kept, not stale): the runtime filenames
  `SwiftCode/SDKGrants.json` / `SwiftCode/SDKAudit.jsonl` in
  `sdk/docs/` (Legacy filenames, no `/` after `SDK` — they are not
  `SwiftCode/SDK/...` paths). Note the destination grant store is
  `PermissionManager` + `grants.json` (§4/§6), not `SDKGrants.json` —
  the docs still describe the Legacy filename. Bare `spec §N`
  shorthand in CLI/src comments (e.g. `spec §17`, `spec §7.2`) is
  Legacy section numbering carried over from the ported files; it was
  left untouched rather than re-numbered by guesswork.
- `sdk/Contracts/Manifest/swiftcode-extension-v1.schema.json`: only
  its top-level `description` text changed (the two doc citations
  inside it); the schema itself is byte-identical otherwise — JSON
  still parses.
- `sdk/docs/Release-Readiness.md`: the repeatable-checks block now
  runs the destination pipeline (`sdk/package`, `sdk/cli`,
  `sdk/runtime-adapter`, `sdk/scripts/package-sdk.sh`,
  `sdk/scripts/verify-sdk.sh`); the Legacy `Distribution/bundle-sdk.sh`
  / `verify-bundle.mjs` invocations were replaced, not remapped —
  those scripts were never ported (§15). `npm pack --pack-destination`
  corrected to `../Distribution` (from `sdk/package`, the assemble
  output is `sdk/Distribution`).
- `sdk/docs/Assist-Access.md` §9: the Swift test bullet now states
  the `SDKAssistApplicationTests` / `SDKAssistEnforcementTests` suites
  were NOT ported as suites (§18) instead of naming Legacy paths.
- `sdk/docs/SDK-Architecture.md`: the Legacy tree diagram is labelled
  as the Legacy layout with the destination layout pointed at §1; the
  `agent_notes.md` convention is marked Legacy-only with no destination
  equivalent. Legacy app-internal references (`SwiftCode/Backend/…`,
  `SwiftCode.xcodeproj`, `SwiftCode/Resources/Google Cloud SDK/…`) were
  NOT remapped — they are not `SwiftCode/SDK/...` references and
  remapping them would require knowing their destination equivalents.

### 23.5 Evidence (all run live in this slice)

- `sdk/package`: `npm run build` clean (`tsc --noEmit` clean;
  `build:snippets` reproduces the checked-in `snippets.json`
  byte-identically, 27 snippets).
- `sdk/runtime-adapter`: `npm run build` + `npm run typecheck` clean;
  `dist/adapter.js` (14,156 bytes) `node --check` clean.
- `node --test "tests/*.test.mjs"` in `sdk/package`: **112 tests,
  112 pass, 0 fail** (24 suites, ~9.2 s). Individually:
  `scopes-sync` 4/4, `cli-roundtrip` 13/13.
- Adapter hand smoke tests (throwaway fixture, `/tmp`, not committed):
  `--help` exit 0; unknown flag / missing `--entrypoint` / unreadable
  manifest → stderr + exit 1; stdin EOF → `extension.ready {
  extensionId, version, protocolVersion: 1 }` then exit 0;
  `commands.execute` success → `ok: true` with the handler result,
  unknown command → `UNKNOWN_COMMAND`, throwing handler →
  its `code` preserved; `shutdown` → exit 0; `activate()` throwing →
  `extension.activationFailed` + exit 1.
- `node --check` passes on every `.mjs` touched; `bash -n` passes on
  all 4 `.sh` files; the schema JSON and `runtime-adapter/package.json`
  parse. No TODO/FIXME introduced; no secrets in any new/changed file
  (secret-pattern grep over the slice's files returns nothing).
- Legacy repo untouched (clean at `d51a8f0d`); destination on main at
  `faf89bd8` with this slice's changes uncommitted. Concurrent
  sibling-wave work present in the same checkout
  (`ycode/Sources/YcodeAssistant/*`, `YcodeGoogleAuth`,
  `YcodePaywall/ProSettingsSection.swift` + tests) was not touched.

### 23.6 Count discrepancy found (flagged, not fixed — coordinator's call)

The Wave 14 spec says "35 capability IDs" (§4, §13.1, §13.3, §14.4,
§21) and "35 SDK ids + 6 `use.Security.*` scopes = 41" for the
validator mirror. Verified live, all three counts disagree:

- `SDKCapabilityID` (`ycode/Sources/YcodeExtensions/Capabilities.swift`)
  has **34** cases — and Legacy's `SDKCapability.swift` has exactly
  the same 34 (its 38 `case … = "…"` lines include 4 risk-level raw
  values from another enum). The port is faithful; the "35" is a spec
  error, not a port defect.
- `validate.mjs`'s `CAPABILITY_IDS` mirror has **32** entries (the
  schema enum: 26 SDK ids + 6 method scopes). The 34 enum cases =
  32 − 6 method scopes + `assist.ui`/`assist.headless`/`assist.main` +
  5 `security.*` method ids.
- The 32-entry scopes list is unaffected (12 views + 20 api) and
  `scopes-sync` passes against both sides.

No file was changed for this: deciding the canonical count (and
whether `validate` should admit `assist.ui`/`assist.headless`/
`assist.main` and the 5 `security.*` method ids) belongs to the
coordinator, since it changes validation behaviour.

**Coordinator decision (Wave 15):** the canonical Swift count is
**34** — verified live, `SDKCapabilityID` has exactly 34 cases in
both Legacy and the destination with identical sets, so the port is
faithful and the Wave 14 spec's "35" was a spec error (corrected in
§4, §5, §13.5, §14.4, §21, §22, and here; `builtInSnippets()` maps
over `allCases`, so the snippet store's 34 built-ins follow from the
same count). `validate.mjs` keeps its 32-entry `CAPABILITY_IDS`
mirror unchanged this wave: its vocabulary differs by design — it
admits the 6 `use.Security.*` method scopes and does not admit
`assist.ui` / `assist.headless` / `assist.main` or the 5 `security.*`
method ids (`security.addValue`, `security.hasValue`,
`security.listValueIDs`, `security.deleteValue`,
`security.useValue`). Admitting them changes what manifests
validate, so that decision moves to Wave 16 with the exact IDs named
here; `scopes-sync` pins the current mapping and passes.

**Coordinator decision (Wave 16, §26.1.1):** the 32-entry mirror IS the
canonical manifest vocabulary — the 8 excluded ids are non-manifest by
Legacy's own registry design (the 3 `assist.*` ids are entitlement-only;
the 5 `security.*` method ids are enforced under the single
`use.Security` grant, never granted separately), and no manifest in the
wild declares any of them. The mirror is unchanged; `scopes-sync` now
pins it with 3 new tests (115/115 pass). Recorded, not fixed: the host
validator's `supportedCapabilities` admits the 8 but NOT the 6
`use.Security.*` method scopes, while schema + `validate.mjs` admit the
6 but not the 8; and the destination has no ported Swift host manifest
validator yet.

### 23.7 What is still pending (not this slice)

- Mac `swift build` / `swift test` for the SDK targets (no Swift
  toolchain in this environment) — unchanged from Wave 14.
- The `sdk-test-runner` / Swift-side `.sh` pipeline steps (B6) —
  unchanged; the TS copy/assemble steps are unaffected by this slice.
- Template smoke tests for `sdk/templates/standalone-swift` (SwiftUI
  scaffold, needs Xcode) and `sdk/templates/project-typescript`
  (not exercised here; `cli-roundtrip` covers the generated
  extension-typescript template end to end).
- The `spec §N` shorthand and `SwiftCode/SDKGrants.json` filename
  drifts noted in §24.4, and the §24.6 count discrepancy.

## 25. Wave 15 — Slice B: SDK host remainder (S-2/S-4/S-5/ExampleManager/tests/managed build/Canvas)

Sources read live for this section (Legacy read-only, main
`d51a8f0d`; destination main `faf89bd8` at wave start):
`SwiftCode/SDK/Host/CapabilityBroker/Grants/SDKGrantStore.swift`,
`SwiftCode/SDK/Host/Security/SDKSecurityService.swift`,
`SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift`,
`SDKAssistApplicationTests.swift`, `SDKAssistEnforcementTests.swift`,
`SwiftCode/SDK/Studio/Views/SDKExampleManager.swift`,
`SwiftCode/SDK/Studio/CodeEditor/SDKCodeBuildRunner.swift`,
`SwiftCode/SDK/Studio/Views/AssistAccessFormView.swift`,
`SDKSecurityManagerView.swift`, `SDKGrantManagerView.swift`,
plus the destination's `ycode/Sources/YcodeSDK/` (Wave 14 host),
`YcodeExtensions/Capabilities.swift` (`PermissionManager`),
`ycode-ide` (`WorkspaceShellModel`, `SourceEditorView`),
`sdk/templates/extension-typescript/`, and the Wave 14 drafts.

### 23.1 S-2 — grant tombstones / digests / extension names

Legacy's `SDKGrantStore` (actor, `SDKGrants.json`, 0600, sorted-keys
pretty JSON) is ported faithfully into `YcodeSDK/Host/
CapabilityBroker/Grants/SDKGrantStore.swift`: `SDKGrantScope`
(standardized project-root path; empty path = no project scope, never
authorizes), `SDKGrantRecord` (id, extensionID, packageDigest,
packageVersion, capability, scope, grantedAt, grantedBy, expiresAt,
revokedAt tombstone, policyVersion; `isActive`, `revoked()`), lazy
load, atomic persist, corrupt file moved aside to
`SDKGrants.json.corrupt-<timestamp>` and starts empty, `activeGrant`,
`grants(for:)` oldest-first including tombstones, `recordGrants(_:
authorizedByAPIKey:)` with the `capabilities:request` scope gate for
privileged capabilities (fail closed — nothing persisted on denial),
`revoke`/`revokeAll` stamping tombstones, `pruneExpired` (30-day rule,
tombstones kept). Adaptations: Linux path
`~/.config/ycode/sdk-grants.json` (macOS `~/Library/Application
Support/SwiftCode/SDKGrants.json`); Ycode audit call
`record(.apiKeyScopeFailure, extensionID:detail:correlationId:)`;
Ycode `SDKError` init. **Ycode addition:** `recordRevocation` —
appends a tombstone for a flat-only grant (grantedAt == revokedAt ==
now, empty scope), because the flat store has no prior record to
stamp. Decision (§21.10): the store lives in YcodeSDK, NOT as
tombstone support in `PermissionManager` — the item allowed either,
and `PermissionManager` lives in `YcodeExtensions` outside the
slice's editable dirs. The Studio adapter
(`SDKPermissionManagerGrantStore`, optional `grantRecords:`) merges
live synthesized records with the record store's tombstones; `revoke`
revokes live + stamps (best-effort — the live revoke already
happened); `extensionName(for:)` resolves via
`SDKExtensionRegistry.shared.installedExtension(id:)?.name`. The
broker still consults the flat `PermissionManager` for live
authorization; precise `PERMISSION_REVOKED` classification via the
record store is follow-up work.

Host changes that S-2's enforcement needed: `grantEntitlement` is now
`async throws` (was sync) and throws `.apiKeyRevoked` for a revoked
key (was `.apiKeyInvalid` — Legacy behaviour); idempotent
early-return if already present; audit via direct `await` (no `Task`).
`revokeEntitlement` is now `async throws -> Int` (was sync, Void):
closes in-flight Assist sessions via the hook and returns the count
closed; audit detail includes `closedSessions N`. `revoke(id:)` now
uses `_ = await ...closeSessions(forKeyID:)`.
`SDKAssistService.closeSessions(forKeyID:)` /
`closeSessions(forExtensionID:)` now return `Int` (only
previously-open sessions counted). `SDKAssistGate.check` now
lowercases the method BEFORE the exemption test, so `ASSIST.INVOKE`
passes like Legacy. Known defect NOT fixed (faithful to Legacy, §19.9):
the deny-list contains mixed-case `"sendMessage"` matched against a
lowercased input, so it never matches.

### 23.2 S-4 — `use.Security` store listing

`KeychainSDK.Envelope` gains an optional `securityID` field
(namespaced Security ID), written by `addValue`, decoded with
`decodeIfPresent` (back-compat for old envelopes). `SDKSecurityService`
gains host-only `listAllApps() async throws -> [SDKSecurityAppSummary]`
(never reachable from extension IPC; extensions use per-namespace
`listValueIDs`): enumerates vault accounts via
`accountNames(withPrefix: "com.swiftcode.sdk.security.")`, groups by
namespaced Security ID from the envelope (exact) with a last-dot-split
fallback for pre-existing envelopes (mis-groups only old values whose
value IDs contain dots), calls `SDKExtensionRegistry.shared.scan()`
first, resolves `extensionID` as the longest installed-extension
prefix, returns metadata only (value IDs/labels/createdAt) — never
secret values. Throws `.serviceUnavailable` if enumeration fails.
`SDKHostSecurityStore` (`SDKStudioSecurityStore` adapter) wires it
into both security views, which now default to it: `listApps()` via
`listAllApps()` (displayName = registry extension name ?? securityID);
`store` is the HOST-side entry (user typed the secret in the Studio
sheet) via `KeychainSDK.addValue` (`promptText` ignored — the
extension-facing prompt path is separate); `deleteValue` /
`deleteAllValues` via `KeychainSDK`.

### 23.3 S-5 — Assist application submission

`SDKAssistSDKVariant` is now `CaseIterable` with `displayLabel`
("assistSDK.UI — with UI" / "assistSDK — headless") and `detail`
(Legacy verbatim); `SDKAssistApplication.minimumUsageDescriptionLength
= 40` and `Field.validate()` uses it (and now also checks extension
ID / display name non-empty, as Legacy's validate does);
`revokeEntitlementsForExtension` updated to `_ = try? await` for the
Int-returning `revokeEntitlement`. The Studio model
(`SDKStudioAssistAccessApplication`) gains `sdkVariant:
SDKAssistSDKVariant = .assistSDKUI` (default matches Legacy's form
default); `validationErrors()` usage-description minimum raised 20 →
40 to match the Host `Field` rule; `makeField(apiKeySecret:)` (secret
is a parameter, never a stored property; comma-separated third-party
models split into `[String]`) and `submit(apiKeySecret:) async throws
-> SDKAssistApplication` (delegates to
`SDKAssistApplicationStore.shared.submit`; approval stays a separate
host action). The form adds a radio-group variant picker
(`displayLabel` + `detail`) and a `SecureField` for the API key secret
with helper text; the secret is held in memory only for the submit
call and cleared afterwards; on success the form shows the pending
status + application id, on error the `SDKError` message. The form's
existing `variant` (New/Existing Application) is a separate
Studio-level enum and is kept.

### 23.4 ExampleManager

Decision (§21.12): Legacy's concrete example
(`SwiftCode/SDK/Examples/RepositoryBuildExtension`, 7 commands) is
already ledger-IMPLEMENTED as spec reference material
(extensions-platform.md §2.2), so it is NOT re-copied as a bundled
project. `SDKExampleManager` resolves the real minimal extension
project from `sdk/templates/extension-typescript` and instantiates it
with the example identity verbatim from Legacy's manifest (id
`com.example.repository-build-extension`, name "Repository Build
Extension", version `0.1.0`, description "Comprehensive demonstration
extension exercising source control, managed builds, project metadata,
workspace file access, network requests, and security vault
capabilities.", slug `repository-build-extension`). Placeholders
substituted: `__EXTENSION_ID__`, `__EXTENSION_NAME__`,
`__EXTENSION_VERSION__`, `__EXTENSION_DESCRIPTION__`, `__ID_SLUG__`,
`__SDK_FILE_URL__` → `"^1.0.0"` (registry range; the managed copy is
self-contained, mirroring the Studio scaffold's no-sdkPackage rule).
`defaultTemplateURL()` candidates: Bundle.main
`SwiftCodeSDK/Templates/extension-typescript`, then walk up from CWD
(max 8 levels) for `sdk/templates/extension-typescript`. Managed copy:
macOS `~/Library/Application Support/SwiftCode/Projects/
RepositoryBuildExtension`, Linux `~/.config/ycode/projects/
RepositoryBuildExtension`. `prepareExampleProject(templateURL:
projectsDirectory:) throws -> URL` copies + instantiates on first use,
reuses the copy afterwards, repairs a missing manifest from the
template, validates (strict `SwiftCodeManifestValidator`, id must
equal the example id, `package.json` + `src/index.ts` must exist).
Returns the managed URL; opening in the workspace is the app shell's
job (Ycode has no `ProjectSessionStore` — Legacy's open-in-workspace
steps are not reproduced). Error enum `SDKExampleError`
(templateNotFound / invalidTemplate / preparationFailed).

### 23.5 Test suites

`SDKAssistApplicationTests.swift` — port of Legacy's suite, adapted:
`SDKAssistApplication.Field` (nested struct; `apiKey` is the presented
secret string, `thirdPartyModels: [String]`, `validate() throws
SDKError` not a field-error dict, no
`SDKAssistApplicationValidationError` / `isValidEmail`);
`SDKAssistApplicationStore.submit(Field)`; approve → entitlements,
deny → no grant, single-shot decide. Shared stores with real I/O
like Legacy (test extension id
`com.swiftcode.sdk.test.assist-app`, version `1.0.0-test`, keys labeled
`SDKTest-assist-…`, tearDown revokes keys + `removeInstallRecord`;
application records have no delete API — leftover inert test data,
as in Legacy). Unknown-extension submit → `.invalidArgument`;
unknown-key submit → `.apiKeyInvalid` (garbage secret string).

`SDKAssistEnforcementTests.swift` — port of Legacy's suite. Verbatim
denial messages pinned as literals ("This app is not allowed to use
Assist because access has not yet been verified. Please check with
the app developer for further information." / cloud variant "This app
is not allowed to use the SwiftCode Cloud Model because access has not
yet been verified. Please check with the app developer for further
information." — PROPOSED wording, Dylan finalizes it; the literal and
`SDKAssistGate.cloudModelDeniedUserMessage` must change together). Adaptations: `SDKAssistService.createSession(
key:extensionID:options:)` (no `caller:` param; no-key case becomes
unentitled-key case — Ycode requires a key); `send(sessionID:key:
extensionID:message:)`, `sendStreaming` returns `AsyncThrowingStream`
(denial arrives as `.failed` event); `executeTool(sessionID:key:
extensionID:call:)`; `closeSession(id:extensionID:)`; `SDKAssistGate.
check` (now case-insensitive exemption — "ASSIST.INVOKE" passes);
`manifestRequestsAssist([SDKCapabilityID])` takes capabilities, not a
manifest (forged-manifest test asserts the gate reports assist from
`[.assistInvoke]` and the boundary denies); `SDKCapabilityBroker.
authorize(.useSwiftCodeModel, for:)` for the cloud gate;
`requireEntitlement(_:on:)` is sync (drop `await`); grant-to-revoked-key
now throws `.apiKeyRevoked`; revoke-closes-sessions uses
`revokeEntitlement` returning the closed count (assert session
`isClosed` via `listSessions(forExtensionID:)`). **Exclusions:**
Ycode `listSessions(forExtensionID:)` and `closeSession` are host-only
(no entitlement check by design), so they are excluded from the
denial matrix — the matrix covers createSession/send/sendStreaming/
executeTool/UI opener.

`SDKGrantStoreTests.swift` / `SDKSecurityListingTests.swift` — see
§22. `SDKStudioTests.swift` additions — see §22.

### 23.6 Managed build

The `SDKBuildHandle` already existed in YcodeSDK
(`SDKBuildService.swift`); Wave 15 wired the Studio runner to it
(§14.5 D-4). `SDKCodeBuildRunner` gains `hostPackageDigest`
(SHA-256 of `"swiftcode.sdk.studio.editor"`, embedded because this
target has no Crypto dep and `Package.swift` must not be edited) and
an `ActiveEntry` enum (`.managedBuild(SDKBuildHandle)` /
`.localProcess(LocalProcessSession)`); `run()` validates first
(TypeScript extensions, or any project with `swiftcode.json` —
Legacy behaviour) and dispatches: `.xcodebuildSwift` → new
`runManagedBuild` (via `SDKBuildService.shared.run(caller:request:)`
with host identity `studio.editor`, streams `handle.events`, `await
handle.wait()`, appends result diagnostics to editor state, terminal
entry); others → extracted `runLocalProcess` (previous body;
`.xcodebuildSwift` case kept unreachable for exhaustiveness); `cancel`
handles both (handle cancel vs SIGTERM then SIGKILL after 3s).
Authorization note: the service authorizes `build.execute` for
`studio.editor` through the broker exactly as for an extension —
with no grant it fails honestly with `.permissionDenied` + a
diagnostic telling the user to approve it via the Studio grant
manager; the host identity is NOT auto-granted. Blank scheme fails
honestly (Ycode has no scheme-resolver seam; same gap as §18
build-scheme discovery).

### 23.7 Canvas editor embedding

**Verdict: the seam does NOT exist as an embeddable unit; left
honestly-unavailable.** Pieces exist (`WorkspaceSession(model:)`,
`WorkspaceShellModel(session:)`, `SourceEditorController(document:)`,
`SourceEditorView(controller:model:palette:preferences:)` in
`ycode-ide`, which already depends on `YcodeIDEShell`), but three
things are missing: (1) no lightweight `WorkspaceSession` /
`WorkspaceModel` for a plain directory root
(`WorkspaceModel.init(url:)` loads a real `.xcodeproj` /
`.xcworkspace` / Package; Studio edits bare extension dirs with only
`swiftcode.json`); (2) no `EditorDocument` bridge from Studio's
`SDKCodeDocument` value types (YcodeEditorKit's disk-backed
`EditorDocument` / `EditorBuffer` vs Studio tab/document model with
its save/disk-change/snippet logic); (3) `WorkspaceShellModel` is the
whole workspace window's model (find bar, issues, source control,
debug, language-server lifecycle) — no hosted-controller lifecycle
for a side pane. Find caret-move stays a documented no-op
(`selectFindRange` in `SDKStudioEditorModels.swift`). No code change
was made for this item beyond this spec text.

### 23.8 What is still pending (not this slice)

- Mac `swift build` / `swift test` for the SDK targets (no Swift
  toolchain in this environment) — unchanged from Wave 14. All new
  and changed files in this slice are statically checked only
  (delimiter balance, no TODO/FIXME, no secrets, `scan-public.py`).
- The broker still consults the flat `PermissionManager` for live
  authorization; precise `PERMISSION_REVOKED` classification via the
  record store is follow-up work (§25.1).
- `SwiftCodeManifest` public init signature was verified live for
  the test seed helpers (`SwiftCodeManifest.swift`).
- The `SDKAssistApplication` presented-secret storage flag (Wave 14
  §5 / §21.9) is RESOLVED in Wave 16 (§26.1.3): the Wave 14 premise
  was wrong (Legacy stored `apiKeyID: UUID`, never the secret); the
  port now stores the key ID only, with proof-of-possession
  verification at submit and a migration that re-encodes ID-only.

## 26. Wave 16 — SDK/Assist remainder (validate.mjs vocabulary · Distribution decision · key-ID-only applications · Muse Code MSP bridge · view host + Assist backend · scheme discovery · model discovery · Antigravity catalog · Gemini rotation · SDK session configuration)

### 26.1 Slice A — validate.mjs capability admission · Distribution regeneration decision · SDKAssistApplication key-ID-only revision

Sources read live for this section (Legacy read-only, main `d51a8f0d`;
destination main `d7cf1872` at wave start): Legacy
`SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`,
`SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json`,
`SwiftCode/SDK/Contracts/Manifest/ExampleManifests/`,
`SwiftCode/SDK/Examples/RepositoryBuildExtension/swiftcode.json`,
`SwiftCode/SDK/TypeScript/cli/commands/validate.mjs`,
`SwiftCode/SDK/Host/ExtensionRegistry/SDKManifestValidator.swift`,
`SwiftCode/SDK/Host/ScopesIDLists.swift`,
`SwiftCode/SDK/TypeScript/package/src/ScopesIDLists.ts`,
`SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift`,
`SwiftCode/SDK/Scripts/{assemble-sdk,build-sdk,package-sdk,verify-sdk}.sh`,
`SwiftCode/SDK/Scripts/populate-distribution.py`,
`SwiftCode/SDK/Scripts/{cross-200mb,reach-gate,expand-to-target,final-gate,reach-threshold,expand-final,cross-gate-now,add-final-delta,add-final-push,add-fixtures}.py`,
`SwiftCode/SDK/Distribution/SwiftCodeSDK/` (measured, never copied);
destination `sdk/cli/commands/validate.mjs`,
`sdk/Contracts/Manifest/swiftcode-extension-v1.schema.json`,
`sdk/Contracts/Manifest/ExampleManifests/`,
`sdk/templates/extension-typescript/swiftcode.json`,
`sdk/package/src/ScopesIDLists.ts`,
`sdk/package/tests/scopes-sync.test.mjs`,
`ycode/Sources/YcodeExtensions/Capabilities.swift`,
`ycode/Sources/YcodeSDK/Host/ScopesIDLists.swift`,
`ycode/Sources/YcodeSDK/Host/CapabilityBroker/SDKCapabilityRegistry.swift`,
`ycode/Sources/YcodeSDK/Host/APIKeys/{SDKAssistApplication,SDKAPIKey,SDKAPIKeyStore}.swift`,
`ycode/Sources/YcodeSDKStudio/SDKStudioModels.swift`,
`ycode/Sources/ycode-ide/SDKStudio/SDKStudioSecurityViews.swift`,
`ycode/Tests/YcodeSDKTests/{SDKAssistApplicationTests,SDKStudioTests}.swift`,
`sdk/scripts/{assemble-sdk,build-sdk,package-sdk,verify-sdk}.sh`.

All three items end DECIDED and implemented (or, for Distribution,
decided with the regeneration path verified and extended). No ledger
row changes state in this slice: the validate decision keeps the
current vocabulary, the Distribution rows stay NOT STARTED by design
(the output tree is never copied), and the Assist revision corrects
already-IMPLEMENTED rows in place.

---

### 26.1.1 validate.mjs capability admission — DECIDED: keep the 32-entry mirror

#### 26.1.1.1 Decision

The 32-entry `CAPABILITY_IDS` mirror in
`sdk/cli/commands/validate.mjs` **is the canonical manifest
vocabulary** for `swiftcode.json` `capabilities[].id`. It is
deliberately NOT the 34-case `SDKCapabilityID` enum, and the 8
excluded enum ids are NOT admitted. The mirror itself is unchanged;
the decision is now recorded in a comment above `CAPABILITY_IDS` in
`validate.mjs` and pinned by three new tests in
`sdk/package/tests/scopes-sync.test.mjs` ("validate.mjs manifest
vocabulary pin").

#### 26.1.1.2 The three vocabularies (verified live)

| Vocabulary | Size | Contents |
|---|---|---|
| `SDKCapabilityID` enum (`Capabilities.swift`, identical 34 cases in Legacy `SDKCapability.swift`) | 34 | All capability ids, including non-manifest ones |
| `ScopesIDLists` (TS + Swift, 32 entries, 12 views + 20 api) | 32 | 32 enum ids: every case EXCEPT `use.Security` and `assist.main` ("umbrella/entitlement surfaces, not separately requestable scopes") |
| Manifest vocabulary: JSON schema enum == `validate.mjs` mirror | 32 | 26 enum ids + the 6 `use.Security.*` method scopes |

The 8 enum ids excluded from the manifest vocabulary, each for a
documented reason:

- **Entitlement-only Assist variants (3)** — `assist.ui`,
  `assist.headless`, `assist.main`: `grantableInCurrentRelease ==
  false` in Legacy `SDKCapabilityInfo` and in the destination
  `SDKCapabilityRegistry` ("unlocked by the key-bound entitlement
  flow, never by a grant"). Admitting them would bless manifests the
  broker must then deny.
- **Security method scopes (5)** — `security.addValue`,
  `security.hasValue`, `security.listValueIDs`,
  `security.deleteValue`, `security.useValue`: "Method scope for the
  `security.*` IPC method, enforced under the single `use.Security`
  grant — not a separately grantable permission"
  (`SDKCapabilityRegistry`). They remain real runtime surface
  (`ScopesIDLists` entries), just not manifest-declarable.

The 6 `use.Security.*` entries in the mirror
(`use.Security.keychain/audit/crypto/securePrompt/redaction/policy`)
are a different, deliberate vocabulary: fine-grained Security-kit
method scopes that Legacy's schema admits. The asymmetry (schema
admits `use.Security.*` but not `security.*`) is Legacy's own design,
not a port drift.

#### 26.1.1.3 Evidence for "keep", not "admit to 40"

1. **Legacy's own schema enum is exactly the same 32 entries**
   (verified live by parsing both JSON files: identical sets), and
   Legacy's `validate.mjs` carries the identical 32-entry mirror.
   The destination mirror is faithful to Legacy, not a drift.
2. **Legacy's own registry says the 8 are non-manifest** (see §26.1.1.2:
   `grantableInCurrentRelease == false` for the Assist variants;
   method-scope enforcement under `use.Security` for the 5
   `security.*` ids).
3. **No manifest in the wild declares any of the 8.** Checked live:
   Legacy `ExampleManifests/repository-build-extension.swiftcode.json`
   (`source-control.read`, `build.execute`), Legacy
   `Examples/RepositoryBuildExtension/swiftcode.json`
   (`source-control.read`, `build.execute`, `project.read`,
   `workspace.read`, `credentials.use`, `network.request`),
   destination `sdk/templates/extension-typescript/swiftcode.json`
   (`source-control.read`, `build.execute`), destination example
   manifest (same two ids). Admitting the 8 would serve no existing
   manifest.
4. **The 40-entry alternative was rejected on purpose**: it would
   change what manifests validate (a manifest declaring `assist.ui`
   would newly pass the fast local check and then be denied at the
   broker), with no wild manifest needing it and against Legacy's
   registry design.

#### 26.1.1.4 Known Legacy divergence, recorded not fixed

The host validator and the schema disagree in opposite directions,
in Legacy itself:

- Legacy `SDKManifestValidator.supportedCapabilities` = registry
  (34 enum ids) ∪ scopes (32) = **the 34 enum ids**. It admits the 8
  excluded ids but NOT the 6 `use.Security.*` method scopes.
- The schema + `validate.mjs` admit the 6 method scopes but NOT the
  8 enum ids.

So a manifest declaring `use.Security.keychain` passes `swiftcode
validate` but fails host install validation with
`UNKNOWN_CAPABILITY`, while a manifest declaring `assist.ui` fails
`validate` but would pass the host's known-id check (and then be
denied at grant time as restricted). `validate.mjs` mirrors the
schema (fast local check); the Swift host remains authoritative at
install time. This divergence is Legacy's, not introduced by the
port, and fixing it would mean changing either the schema or the host
validator's known-id set — out of scope for this slice. (Note: the
destination has no ported Swift host manifest validator yet — no
`SDKManifestValidator` exists under `ycode/Sources/YcodeSDK/`; the
host-side check is a gap for a later wave, not something this slice
creates.)

#### 26.1.1.5 What changed

- `sdk/cli/commands/validate.mjs`: `CAPABILITY_IDS` list unchanged
  (32 entries); the comment above it is now the decision record
  (§26.1.1.1–§26.1.1.4 in short form). The `capabilities.length > 32` cap is
  unchanged and matches the schema `maxItems: 32`.
- `sdk/package/tests/scopes-sync.test.mjs`: new `describe`
  ("validate.mjs manifest vocabulary pin", 3 tests) parsing the
  mirror, the schema enum, and `SDKCapabilityID` cases from disk and
  asserting: mirror == schema enum (32 each, same set); mirror = 26
  enum values + exactly the 6 `use.Security.*` scopes; enum − mirror
  = exactly the 3 entitlement-only `assist.*` ids + the 5
  `security.*` method ids (and that the 5 stay `ScopesIDLists`
  entries). Full node suite: **115/115 pass** (112 baseline + 3 new).

---

### 26.1.2 SDK/Distribution/ regeneration — DECIDED: output tree stays unported; the regeneration path already exists (Wave 14) and is verified + extended here

#### 26.1.2.1 Decision

**The `Distribution/` output tree is never copied and never
regenerated as a tree. Its rows stay NOT STARTED in the ledger.**
What *is* ported — and what this slice verified live and extended —
is the **regeneration pipeline**: `sdk/scripts/{assemble-sdk,
build-sdk,package-sdk,verify-sdk}.sh` (Wave 14), plus a new
`sdk/scripts/smoke-sdk-scripts.sh` smoke check (this slice). The
pipeline assembles a distribution from real artifacts only; the
synthetic filler that inflated Legacy's tree is dropped by design and
must never be re-run.

#### 26.1.2.2 What Legacy's Distribution really is (measured live)

Legacy `SwiftCode/SDK/Distribution/SwiftCodeSDK/` is 201,299,944
bytes / 2,478 files / 575,450 lines. By content:

| Part | Size | Nature |
|---|---|---|
| `languages/python/stubs/` — 46 fake `.pyi` files (46 modules × 1,200 stub functions + stub classes each) | 37.2 MB | Synthetic filler (`populate-distribution.py` §26.1.1) |
| `languages/swift/diagnostics/` — 13 files × 3,500 fake rules | 18.6 MB | Synthetic filler (§26.1.2) |
| `languages/swift/symbols/` — 12 files × 3,000 fake framework symbols | 23.5 MB | Synthetic filler (§26.1.2) |
| `documentation/api/` — 7 files × 1,000 fake components | 6.5 MB | Synthetic filler (§26.1.3) |
| `documentation/offline-index/search-index.json` — 25,000 fake tokens | 5.5 MB | Synthetic filler (§26.1.3) |
| `documentation/tutorials/` | 0.3 MB | Synthetic filler (§26.1.3, small) |
| `tests/fixtures/` — 25 fake fixture extensions | 0.02 MB | Synthetic filler (§4, small) |
| `languages/typescript/` — real TS package/cli/runtime-adapter trees **including 32.7 MB of `node_modules`** (archiver et al.) | 75.0 MB | Real content (copied trees, incl. deps) |
| `languages/python/` remainder, `resources/` (6.8 MB), `bin/` (0.9 MB), `lib/` (4.6 MB), `tools/` (4.3 MB), `templates/`, `extensions/`, `manifests/`, `examples/` | ~17.7 MB + python remainder | Real content (binaries, libs, schemas, templates) |
| Archives `SwiftCodeSDK-1.0.0.{zip,tar.gz,tgz}` + `checksums.txt` | ~70.2 MB (outside the tree above; whole `Distribution/` dir is 271,554,921 bytes) | Build output of the same tree |

Filler subtotal from `populate-distribution.py` alone: **~91.6 MB**
of the 201 MB tree. The filler exists for one reason: the 200 MB
size gates. `assemble-sdk.sh` §8 and `verify-sdk.sh` §26.1.3 both hard-fail
(`exit 1`) when the assembled tree is under 200,000,000 bytes — a
threshold only reachable with filler, since the real content is
~110 MB including `node_modules`.

The other 10 Legacy `Scripts/*.py` files are the same game, not
regeneration: `cross-200mb.py`, `reach-threshold.py`,
`reach-gate.py`, `expand-to-target.py`, `expand-final.py`,
`final-gate.py`, `cross-gate-now.py`, `add-final-delta.py`,
`add-final-push.py`, `add-fixtures.py` generate numbered fake
benchmark/security-policy/guide documents into the tree (e.g.
`cross-200mb.py` writes 120 fake benchmarks + 120 fake security
policies into `documentation/guides/`; its destination path is a
hardcoded absolute path under the author's home directory (`~/Downloads/...`)). None of them
produces anything a user, a build, or a test consumes.

#### 26.1.2.3 What regenerates for real (and what does not)

Real regeneration, via the Wave 14 scripts (verified live by reading
each script against the destination layout):

- `assemble-sdk.sh` (§26.1.1–5, §7): writes `VERSION`/`LICENSE`/`README.md`
  heredocs; copies the Swift release binaries + tools + `.a` /
  `.swiftmodule` libs from `ycode/.build/release` (step 2, needs
  `swift build`); writes the macOS-app / Swift-package template
  heredocs and copies `sdk/templates/` (§26.1.3); copies the manifest
  schema + example manifests from `sdk/Contracts/Manifest/` (§4);
  rsyncs `sdk/package/`, `sdk/cli/`, `sdk/runtime-adapter/` (§5);
  writes the Python runner stub, `swift-format.json`,
  `sdk-defaults.json`, and `SDKManifest.json` (§5/§7).
- `build-sdk.sh`: `swift build -c release` + `sdk-test-runner`.
- `package-sdk.sh`: verify → zip + tar.gz → SHA-256 checksums →
  clean-room extraction test (`--version` + `doctor`).
- `verify-sdk.sh`: required files/tools → CLI `--version`/`doctor`
  from the staging dir → size report → per-directory breakdown.

Does NOT regenerate (dropped by design, do not re-run): everything
in §26.1.2.2's filler rows — `populate-distribution.py` (§6 of Legacy's
assemble, removed in Wave 14) and the 10 threshold-gaming scripts.
The 200 MB gates are report-only in the destination scripts for the
same reason. `manifests/components.json` (written by
`populate-distribution.py`) was removed from `verify-sdk.sh`'s
required-files check in Wave 14.

#### 26.1.2.4 What this slice changed

- **Portability fix (genuine defect in the regeneration path):**
  all three scripts used BSD-only `stat -f '%z'`, which fails on GNU
  stat (it reads `-f` as "filesystem" and treats the format string as
  a path — verified live on this Linux box). Each script now probes
  once (`stat -f '%z'` vs `stat -c '%s'`) into `_STAT_SIZE` and uses
  it at every size call site (`assemble-sdk.sh` §8 total,
  `verify-sdk.sh` §26.1.3 total + §4 per-directory breakdown,
  `package-sdk.sh` zip/tgz sizes). macOS behaviour is unchanged.
- **New smoke check `sdk/scripts/smoke-sdk-scripts.sh`** (96 lines,
  runs with no Swift toolchain and no Legacy output): `bash -n` on
  all five scripts; every `assemble-sdk.sh` source tree exists;
  no filler references in live code (comments stripped first) and no
  BSD-only `stat -f` at call sites; the 200 MB gate is report-only;
  `verify-sdk.sh` and `package-sdk.sh` fail closed on a missing
  distribution (exercised on copies in a temp dir); the size probe
  agrees with `wc -c`; no `sdk/Distribution/` output is committed.
  **Result: SMOKE PASS (8/8 checks)** on this machine.
- No `sdk/Distribution/` directory exists in the destination repo
  (verified: `git ls-files sdk/Distribution` is empty).

#### 26.1.2.5 Still pending (Mac)

- Full `assemble-sdk.sh` end-to-end run on Dylan's Mac (needs
  `swift build` for the `swiftcode-sdk` binary + 5 tools; the
  `swiftcode-sdk` executable product exists in `ycode/Package.swift`,
  the 6 tools' products are the Wave 14 executables).
- `build-sdk.sh`'s test step will fail until the `sdk-test-runner`
  product exists: `ycode/Package.swift:148` notes "no
  `sdk-test-runner`" — creating it is a `Package.swift` change for a
  later wave (this slice may not edit `Package.swift`).
- `assemble-sdk.sh` §5 rsyncs all of `sdk/package/` into the
  distribution, including `node_modules/` (32 MB in Legacy's tree)
  and `tests/` — faithful to Legacy, which did the same
  (`--exclude='.git*'` only), and the CLI plausibly needs its
  `node_modules` at runtime (Legacy's `bundle-sdk.sh` required
  `cli/node_modules/archiver/package.json`). Whether to exclude
  `node_modules`/`tests` from the shipped tree is a follow-up
  decision, not silently changed here.

---

### 26.1.3 SDKAssistApplication presented-secret → key-ID-only — IMPLEMENTED

#### 26.1.3.1 Correction to the spec's premise

Spec §5's flag ("Legacy's `SDKAssistApplication.Field.apiKey` holds
the presented secret") is **wrong about Legacy**. Verified live in
Legacy `SwiftCode/SDK/Host/APIKeys/SDKAssistApplication.swift`:
Legacy's struct is flat and stores **`apiKeyID: UUID`** ("The
developer API key the entitlements are bound to on approval",
"Verified at submit time (key must exist, not be revoked or
expired)"); its `submit` looks the key up by ID in
`SDKAPIKeyStore.list()` — no secret is presented or stored at any
point, and `approve(id:)` grants entitlements by `apiKeyID` alone.
The presented-secret field was a **Wave 14 port deviation**, not
Legacy behaviour: the destination's nested `Field.apiKey: String`
stored the secret the submitter pasted, and the store persisted the
whole `Field` (Keychain-backed, but still the secret at rest, and
recoverable from every stored application record). This revision
restores Legacy's shape and keeps Wave 15's improvement (below).

#### 26.1.3.2 Design (no secret needed at approval time)

Legacy genuinely does **not** require the secret at approval time,
so no re-prompt or alternative flow is needed. The design keeps
Wave 15 Slice B's proof-of-possession at submit (which is strictly
stronger than Legacy's trust-the-caller-naming-a-key-ID) and removes
the persistence:

- `SDKAssistApplication.Field.apiKey: String` →
  **`apiKeyID: UUID`**. The record stores only the key ID.
- `SDKAssistApplicationStore.submit(_:apiKeySecret:)` (new
  signature): validates the field; requires the extension to be
  installed; **verifies the presented secret** via
  `SDKAPIKeyStore.verify` (HMAC + metadata re-read; liveness —
  revoked/expired — enforced there); requires
  `verifiedKey.id == field.apiKeyID`, so an application can never be
  bound to a key its submitter does not hold. The secret is dropped
  after verification; the persisted record carries only the ID.
- `approve(id:)` / `deny(id:)` / `revokeEntitlementsForExtension(_:)`
  now use `application.field.apiKeyID` directly. `keyID(for:)` is
  non-throwing (no unverified extraction from a secret on the
  approval path). Grant calls re-read key metadata and refuse revoked
  keys, so a key revoked between submit and approve fails closed —
  exactly Legacy's "grant first, persist after" behaviour.
- **Studio model** (`SDKStudioAssistAccessApplication`): `makeField`
  now takes `apiKeyID: UUID`; `submit(apiKeySecret:)` extracts the
  (unverified, naming-only) key ID from the presented secret via
  `SDKAPIKeyCodec.extractPresentedKeyID`, rejects a secret naming a
  different key than the model's `keyID` (existing-application
  variant) with `.apiKeyInvalid`, then calls the store. The secret
  stays a parameter only; the view's in-memory `SecureField` is still
  cleared after submit (Wave 15 behaviour, unchanged). The view
  itself needed no signature change.
- **Migration of existing stored applications:** `Field` has custom
  `Codable`: it decodes `apiKeyID` when present, else recovers the ID
  from a pre–Wave 16 legacy `"apiKey"` secret via
  `extractPresentedKeyID` (unverified parse, name only — trusted
  only as a pointer; approval re-reads metadata) and discards the
  secret; it **never writes** the legacy `"apiKey"` key, so a
  migrated record re-encodes with the ID only and the secret leaves
  the store on the next persist. A record with neither a usable ID
  nor a parseable legacy secret fails to decode and is skipped by
  `list()` — the same treatment as any corrupt record today. No
  stored application is silently dropped that was decodable before:
  every Wave 14/15 record carries a parseable secret (it was produced
  by `SDKAPIKeyStore.createKey`).

#### 26.1.3.3 What changed (files)

- `ycode/Sources/YcodeSDK/Host/APIKeys/SDKAssistApplication.swift`
  (+122/−~30): `Field.apiKeyID`, custom `Codable` with legacy
  migration, `submit(_:apiKeySecret:)` with the binding check,
  direct `keyID(for:)`, updated header/field/store comments.
- `ycode/Sources/YcodeSDKStudio/SDKStudioModels.swift`:
  `makeField(apiKeyID:)`, `submit(apiKeySecret:)` with
  extract + `keyID`-mismatch rejection.
- `ycode/Sources/ycode-ide/SDKStudio/SDKStudioSecurityViews.swift`:
  header comment only (store persists only the key ID now).
- `ycode/Tests/YcodeSDKTests/SDKAssistApplicationTests.swift`:
  all constructors/submits moved to the new shape; 3 new tests —
  `testSubmitRejectsSecretForDifferentKey`,
  `testSubmittedRecordStoresKeyIDNotSecret` (encoded record contains
  the key ID, no `sc_dev_` fragment, no `"apiKey"` key),
  `testLegacySecretRecordMigratesToKeyID` (legacy JSON with a
  from-parts fake secret decodes to the right ID and re-encodes
  secret-free). Fake secret assembled from parts (zero signature
  bytes — verifies nowhere), no real key material anywhere.
- `ycode/Tests/YcodeSDKTests/SDKStudioTests.swift`: `makeField`
  call updated to `makeField(apiKeyID:)` + `field.apiKeyID` assertion.

#### 26.1.3.4 Verification status and gaps

- Swift static checks only (no Swift toolchain in this environment):
  delimiter balance verified on all five edited Swift files; no
  TODO/FIXME; no remaining references to the old API
  (`makeField(apiKeySecret:)`, `submit(field)`, `field.apiKey`)
  anywhere under `ycode/Sources` / `ycode/Tests`; `scan-public`
  reports 0 findings in Slice A files.
- **Mac `swift build` / `swift test` pending** (notably
  `SDKAssistApplicationTests` + `SDKStudioTests`): the custom
  `Field.init(from:)`/`encode(to:)` and the new `submit` signature
  are uncompiled here. The memberwise `Field` init is explicit (not
  synthesized), so adding `init(from:)` does not remove it — call
  sites are safe on that point — but compilation is still unverified.
- **Untested branch:** `SDKStudioModels.submit(apiKeySecret:)`'s
  `keyID`-mismatch rejection has no unit test (it needs the shared
  store + install record + real key; store-level
  `testSubmitRejectsSecretForDifferentKey` covers the binding check
  itself). The model's extract-failure path (unparseable secret →
  `.apiKeyInvalid`) is likewise exercised only through the store
  tests, not at the model layer.

---

### 26.1.4 Evidence

- **Item 1:** parsed live — destination + Legacy schema enums
  (identical 32-entry sets), destination + Legacy `validate.mjs`
  mirrors (identical 32), `SDKCapabilityID` case lists in both repos
  (34 each, identical sets), `ScopesIDLists` TS + Swift in both repos
  (32 entries each, identical sets; `cap − scopes` = `use.Security`,
  `assist.main`), Legacy `SDKManifestValidator.supportedCapabilities`
  (registry ∪ scopes), Legacy + destination
  `SDKCapabilityRegistry` grantability comments, wild manifests listed
  in §26.1.1.3 (capability ids enumerated from the JSON files). Test run:
  `npm run build && npm test` in `sdk/package/` → **115/115 pass**
  (112 baseline + 3 new pin tests); `node --check` clean on both
  edited `.mjs` files.
- **Item 2:** measured live — `du -sb` / file counts / `wc -l` over
  Legacy `Distribution/SwiftCodeSDK/` (201,299,944 bytes, 2,478 files,
  575,450 lines); filler subtotals per `populate-distribution.py`
  section (§26.1.1–§4); read all four Legacy SDK scripts + all 11
  `Scripts/*.py` (headers + generation loops); read all four
  destination scripts; `stat -f '%z'` failure reproduced on this
  Linux box (GNU stat treats the format as a path); smoke script run
  → **SMOKE PASS 8/8** (`bash sdk/scripts/smoke-sdk-scripts.sh`).
- **Item 3:** read live — Legacy `SDKAssistApplication.swift`
  (flat struct, `apiKeyID: UUID`, submit-by-ID lookup,
  approve-by-ID grant) vs destination pre-change `Field.apiKey:
  String` + `submit(field)` persisting the secret; destination
  `SDKAPIKeyCodec.extractPresentedKeyID` (unverified parse, documented
  as name-only) and `SDKAPIKeyStore.verify` (HMAC + liveness). Static
  checks only — see §26.1.3.4.
- **Clean-room:** no reference Xcode copy, Ghidra, simulator IPSW,
  `research/dirty/`, or Ghidra project was opened, run, or observed.
  Legacy source is Dylan's own code; direct porting was authorised
  under MIT. Specs + public docs + Legacy (Dylan's own) code only.
- **Incidental findings (not Slice A, not changed):**
  `scan-public` reports 2 findings in
  `ycode/Tests/YcodeGoogleAuthTests/GoogleADCAndAntigravityTests.swift`
  (home-folder fixture paths, lines 99/117) — that file is
  unmodified vs `d7cf1872` (Wave 15), so the findings are
  pre-existing at HEAD, not introduced here. Spec §5's flag
  misattributes the presented-secret field to Legacy (§26.1.3.1) — the
  spec itself was not edited (forbidden to this slice); the correction
  belongs in the spec at §5 / §19 item 8. `ycode/Package.swift:148`
  notes the missing `sdk-test-runner` product (§26.1.2.5).

### 26.1.5 File inventory (destination repo only, uncommitted)

Modified (10 files, `git diff --stat`: 439 insertions, 75 deletions):

- `sdk/cli/commands/validate.mjs` (+30) — decision comment above
  `CAPABILITY_IDS`; list unchanged.
- `sdk/package/tests/scopes-sync.test.mjs` (+126) — "validate.mjs
  manifest vocabulary pin" describe block, 3 tests.
- `sdk/scripts/assemble-sdk.sh` (+11/−) — portable `_STAT_SIZE`
  probe + use at the §8 size call.
- `sdk/scripts/package-sdk.sh` (+12/−) — portable `_STAT_SIZE`
  probe + use at zip/tgz size calls.
- `sdk/scripts/verify-sdk.sh` (+12/−) — portable `_STAT_SIZE`
  probe + use at §26.1.3 total + §4 breakdown.
- `ycode/Sources/YcodeSDK/Host/APIKeys/SDKAssistApplication.swift`
  — `Field.apiKeyID`, custom `Codable` + legacy migration,
  `submit(_:apiKeySecret:)` binding check, direct `keyID(for:)`.
- `ycode/Sources/YcodeSDKStudio/SDKStudioModels.swift` —
  `makeField(apiKeyID:)`, `submit(apiKeySecret:)` extract + mismatch
  rejection.
- `ycode/Sources/ycode-ide/SDKStudio/SDKStudioSecurityViews.swift`
  (+3/−) — header comment only.
- `ycode/Tests/YcodeSDKTests/SDKAssistApplicationTests.swift` —
  new-shape constructors/submits + 3 new tests.
- `ycode/Tests/YcodeSDKTests/SDKStudioTests.swift` —
  `makeField(apiKeyID:)` + `field.apiKeyID` assertion.

Created (1 file, untracked):

- `sdk/scripts/smoke-sdk-scripts.sh` (96 lines, executable) — SDK
  distribution regeneration smoke check (see §26.1.2.4).

Not touched, as instructed: `ycode/Package.swift`, the ledger
(`ledgers/MIGRATION_FEATURE_PARITY.md` — no row changes state),
`specs/ide/sdk-platform.md` (corrections for §5/§19 item 8 and the
§23.6/§24.6 decision are in this draft for the coordinator to fold
in), SwiftCode-Legacy (clean at `d51a8f0d`), SwiftCode-New
(pre-existing working-tree residue untouched by this slice).

Ledger rows: none change state. The validate decision keeps the
current vocabulary; Distribution rows stay NOT STARTED by decision
(§26.1.2.1); the Assist revision corrects already-IMPLEMENTED rows in
place.

### 26.2 Slice B — Muse Code MSP bridge + lifecycle + slash commands + executeTurn + normalizeToolName

> Draft for the coordinator to merge into `specs/ide/sdk-platform.md`
> (suggested: a new §26, plus a one-line update to §23.4's "Not
> ported" paragraph and §23.6's bridge row, which this slice closes
> except for the honestly-unavailable items in §26.2.2.6 below).
> Do NOT edit the ledger from this draft; the coordinator marks rows
> 580–585 (see §26.2.2.8).

Sources read live for this section (Legacy read-only, main
`d51a8f0d`; destination main `d7cf1872` at slice start):
`SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeMSPBridge.swift`
(368 lines), `MetaAssistLifecycleManager.swift` (141),
`MetaSlashCommandManager.swift` (655),
`MuseCodeCLIHelper.swift` (523),
`MuseOtherModelsBridge.swift` (732),
`MetaAssistProvider.swift` (785, `executeTurn` /
`normalizeToolName` / `fetchModels` / `switchModel` /
`unqueueTurn` / `cancelTurn` / `isRateLimitError`).
Destination: `ycode/Sources/YcodeAssistant/` (host; the only
target touched — no `Package.swift` change, no new target),
`ycode/Tests/YcodeAssistantTests/`.
Public corroboration (secondary — Legacy is the source):
Meta's own Muse Code docs say `muse serve` "hosts a session
over stdio using Meta's session protocol" and `muse schema`
exports that wire schema, with `@muse-code/sdk` / `muse-code-sdk`
wrapping it; the CLI's `--help` (v1.4.14) lists `serve`,
`skills`, `mcp`, `auth`, `login`, `logout` among its commands.

### 26.2.1 What landed

`MetaAssistProvider.send` no longer throws
`AssistantError.unsupported` naming the missing bridge. It runs
a real turn through the MSP host, under Ycode's Assist host
only: no parallel registry, no transplanted session loop, no
Autopilot, no bypass of the approval gate. Every file is in the
existing `YcodeAssistant` target (which depends only on
`YcodeSubprocess`); `YcodeMCP` is not imported anywhere in this
slice, so the dependency direction (`YcodeMCP` → `YcodeAssistant`)
is preserved.

| Legacy piece | Destination |
|---|---|
| `MuseCodeMSPBridge` (NDJSON JSON-RPC host session, `Process` + pipes, string request ids, pending continuations, `approval/request` cookbook ack) | `MuseCodeMSPBridge` (actor, `ycode/Sources/YcodeAssistant/MuseCodeMSPBridge.swift`) — `startHost` / `stopHost` / `sendCommand` / `sendNotification` / `sendResponse` / `sendRPCError`, `MuseCodeMSPError` (`MspError`), `MuseCodeCLIError`, `MuseUUIDv7` |
| `MetaAssistLifecycleManager` (start/stop/restart, 5 s health check, 4 s restart throttle, restart count) | `MetaAssistLifecycleManager` (actor, same file name) — `startMonitoring` / `stopMonitoring` / `startEngine` / `stopEngine` / `restartEngine` / `ensureRunning` / `healthCheckOnce` |
| `MetaSlashCommandManager` (36 built-ins, `muse skills list` capture, search, `executeCommand`) | `MetaSlashCommandManager` (struct, same file name) — `builtInCommands` (36, verbatim), `parseSkillsList`, `mergeCapturedSkills`, `captureCommandsFromTerminal`, `searchCommands`, `executeCommand` returning `(text, effect)` |
| `MuseOtherModelsBridge` (model resolution, local proxy, `<think>` splitter, ```tool_call parsing) | `MuseOtherModelsBridge` (same file name) — `availableOtherModels` / `resolveActiveModel` (pure, injected inputs), `MuseThinkingTokenizer`, `MuseToolCallParser`, `MuseLocalProxyServer` on `LoopbackServer` |
| `MetaAssistProvider.executeTurn` (initialize, session start/resume, turn/start, notification routing, turn tracker, rate-limit failover trigger) | `MetaAssistTurnExecutor.executeTurn` (`ycode/Sources/YcodeAssistant/MetaAssistTurnExecutor.swift`) + `MetaTurnNotificationRouter` + `MetaTurnState` |
| `MetaAssistProvider.normalizeToolName` | `MetaToolNameNormalizer.normalize` (same file) — prefix strip + synonym map, resolved against injected Ycode MCP ids |
| `MetaAssistProvider.fetchModels` (`model/list`) | `MetaAssistProvider.fetchModels` (live list, fallback otherwise) + `MetaAssistTurnExecutor.parseModelList` / `parseSessionID` |
| `switchModel` / `unqueueTurn` / `cancelTurn` / `isRateLimitError` | `MetaAssistTurnExecutor` methods (same names, same rules) |
| `MuseCodeCLIError` (5 cases) | Same enum in `MuseCodeMSPBridge.swift` |

### 26.2.2 The wire protocol (verified live from Legacy)

Transport: one `muse serve` child process (argv `serve`, or
`--base-url <url> serve` when the other-models proxy serves the
models), NDJSON over stdin/stdout — one JSON-RPC 2.0 message per
line, `jsonrpc: "2.0"`. Request ids are UUID strings
(Legacy's `sendCommand` used `UUID().uuidString`); session/turn
`commandId`s are UUIDv7. Environment: inherited, with
`/opt/homebrew/bin:/usr/local/bin` appended to `PATH`.
`SIGPIPE` is ignored (`SIG_IGN`, as in `ACPClient`) so a write
to an exited host fails instead of ending Ycode.

Client → host requests (all verified in Legacy's provider):

| Method | Params | Notes |
|---|---|---|
| `initialize` | `clientInfo: {name: "swiftcode", title: "SwiftCode", version: "1.0.0"}` | Once per bridge lifetime; followed by the `initialized` notification |
| `model/list` | `{}` | `result.models[]`: `modelId`, `displayLabel`, `releaseDate`, `description`, `contextLimit` (default 1,000,000), `outputLimit` (default 128,000), `isDefault`, `variants`, `defaultReasoningEffort`; empty/missing → fallback catalog |
| `session/start` | `commandId` (UUIDv7), `workspaceRoot`, `modelId` | Session id read as `result.session.sessionId`, else `session.sessionId`, else top-level `sessionId`, else the command id |
| `session/resume` | `sessionId`, `history: "inline"` | Failure clears the cached session and a fresh `session/start` follows |
| `session/setModel` | `sessionId`, `commandId`, `model: {providerId, modelId}` | Mid-session model switch; default `providerId` is `"openai"` (Legacy's default argument) |
| `turn/start` | `commandId` (UUIDv7), `sessionId`, `reasoningEffort`, `ifBusy: "queue"`, `displayText`, `input: [{type: "text", text}]` | Turn id read from `result.turnId`; on "session is not loaded on this host" (`MspError.kind == "sessionNotLoaded"` or the text) a fresh session is started and the turn retried once |
| `turn/unqueue` | `sessionId`, `commandId`, `turnId` | Reclaims a pending turn |
| `turn/cancel` | `sessionId`, `commandId`, `turnId?` | `already_terminal` (`MspError.reason`) is swallowed |
| `approval/decide` | `sessionId`, `approvalId`, `requirementId`, `choiceId` (`allow_once` / `abort`), `feedback: null` | `requirementId` is `currentRequirementId` or `requirementId` from the request, else `{approvalId, sourceIndex: 0}` |

Host → client. Server requests (id + method): answered by the
bridge — a custom handler's result, else `{}` for
`approval/request` (the Muse SDK Cookbook acknowledgement, "I
am handling this"), else JSON-RPC `-32601 Method not found`.
Notifications: `item/started`, `item/delta`, `item/completed`,
`turn/completed`, `turn/unqueued`, `session/modelChanged`,
`approval/requested`, `approval/resolved`. Responses: an
`error` resumes the pending continuation with
`MuseCodeMSPError` (code, message, `kind` from
`error.data["kind"]`, `data`); a `result` resumes it with the
whole response message (Legacy returned the whole response
dict; callers read `["result"]`).

### 26.2.3 Turn execution (`MetaAssistTurnExecutor.executeTurn`)

1. Preconditions: no located `muse` binary →
   `MuseCodeCLIError.executableNotFound`; no credential file
   and no proxy URL → `AssistantError.notSignedIn` with the
   "run `muse` once in Terminal" hint. Ycode never launches an
   interactive `muse login`.
2. `bridge.startHost` (no-op when already running), then the
   `initialize` + `initialized` handshake once per bridge
   lifetime.
3. Session: resume the cached session for the same workspace
   root, else `session/start`.
4. Turn: `turn/start` with the request's model (default
   `muse-wonder-1.0`), the provider's reasoning effort
   (default `"high"`, from `AssistantSettings.metaReasoningEffort`),
   `ifBusy: "queue"`, and the effective prompt — the host's
   instructions, then the last 12 history turns (excluding a
   duplicate of the current prompt), then `# CURRENT USER
   REQUEST`. See §26.2.2.6 for what Legacy's prompt had that this
   does not.
5. Notification routing (`MetaTurnNotificationRouter`, pure
   over fixtures — see §26.2.2.7):
   - `item/started` (`toolCall` / `userShell`): the tool name
     is normalized (see §26.2.2.4); an `.activity` line names it
     (`name: path|command|query|pattern`, Hermes' style).
   - `item/delta`: `field == "text"` (or no field, or kind
     `agentMessage`) → `.text`; `field` starting with
     `summary` or kind `reasoning` → thinking, accumulated and
     emitted as `.activity("Thinking: …")` once the buffer
     holds a blank line or passes 240 characters (the ACP
     provider's precedent — `ChatEvent` has no thinking case);
     `field == "output"` or a tool kind → tracked on the item
     and reported as tool-progress activity, never dumped into
     chat text (Legacy's own rule).
   - `item/completed` (`toolCall` / `userShell`): `.activity("<name> ✓")`
     with the visible output (or the tracked output) recorded
     on the turn.
   - `turn/completed`: records the turn in `completedTurns`
     and resumes the turn; `turn/unqueued` resumes only when
     its id is this turn's.
   - `session/modelChanged`: recorded in `reportedModelID`
     (the host reads it; settings are not written from here).
   - `approval/requested`: see §26.2.2.5.
   - `approval/resolved`: observed only.
6. The caller (`MetaAssistProvider.send`) yields `.finished`
   after `executeTurn` returns. `send` maps
   `MuseCodeCLIError` to `AssistantError.failed` and never
   fabricates a reply or reroutes the turn.

The executor is an actor with a shared instance
(`MetaAssistTurnExecutor.shared`): a second turn waits for the
first, because the shared bridge carries one notification
handler at a time. Session state (`activeSessionID`,
`activeWorkspaceRoot`, `activeTurnID`, `completedTurns`,
`lastTurnUnmappedToolNames`, `reportedModelID`) lives on the
executor, not on the provider struct — `AssistantBackends`
builds a fresh provider per call, so struct state would not
survive between turns.

### 26.2.4 `normalizeToolName` — against Ycode's MCP tools

`MetaToolNameNormalizer.normalize(_:knownToolIDs:)` ports
Legacy's rules verbatim, then changes the registry lookup:

1. Strip one namespace prefix (`muse.`, `Muse.`, `muse_`,
   `Muse_`, `muse:`, `Muse:`, `muse-`, `Muse-`), first match.
2. Synonyms (Legacy, verbatim): `use_workers` / `useworkers` /
   `workers` / `workflow` / `use_worker` → `use_workers`;
   `plan_askuser` / `planaskuser` / `askuser` / `ask_user` →
   `plan-AskUser` (the hyphenated id is kept — the documented
   intentional exception); `report_to_user` / `reporttouser` /
   `report` → `report_to_user`.
3. Registry: exact, then case-insensitive, against the injected
   `knownToolIDs` — the set of Ycode MCP tool ids. Legacy
   consulted `AssistManager.shared.registry`; that registry does
   not exist in Ycode, and `YcodeAssistant` cannot import
   `YcodeMCP` (the dependency runs the other way), so the set
   is injected: `MetaAssistProvider.knownToolIDs` (default
   empty), threaded through `send` → `executeTurn` → the
   router. The full alias table stays where it belongs —
   `MCPServer.toolAliases`, applied at `tools/call` time —
   except the three aliases this executor can produce on its
   own (`bash` / `sh` / `zsh` → `use_terminal`, Legacy's table,
   Wave 4).
4. No match → the cleaned name, source `.passthrough`, and the
   name is appended to the turn's `unmappedToolNames`
   (deduped, in order; exposed as
   `executor.lastTurnUnmappedToolNames`). Until the host injects
   the live catalogue, every non-synonym name is recorded
   unmapped rather than silently claimed to exist.

Host wiring still open (coordinator): pass the live catalogue
(`Set(server.tools.map(\.name))` plus `MCPServer.toolAliases`
keys) into `AssistantBackends` → `MetaAssistProvider
(knownToolIDs:)` — or through `attaching(_:)` when the
attachment carries it. The provider cannot fetch
`tools/list` itself: it has no MCP endpoint without the host.

### 26.2.5 Approvals — the gate, and what Autopilot did

Legacy decided approvals in the provider and, in Autopilot
mode, approved everything at system level (`isAllowed =
isAutopilot ? true : …`). That is NOT ported. The Ycode rule:

- The bridge still acknowledges the server request
  `approval/request` with `{}` immediately (the cookbook
  acknowledgement — "I am handling this", not a decision).
- The notification `approval/requested` is answered with
  `approval/decide` only after the host's permission UI
  decides: `AgentAttachment.requestPermission` with the
  options `allow_once` ("Allow once") and `abort` ("Abort").
  Only the id `allow_once` ever reaches the host as an allow;
  anything else, including a cancelled prompt, becomes
  `abort`.
- With no attachment (chat mode, or any caller that did not
  attach one), the decision is `abort` — deny by default.

`MetaAssistProvider` conforms to `AgentAttachable` so the IDE
model attaches it in agent mode (the same path as the CLI
agents and ACP). Two consequences the coordinator should
know: (a) the attachment's `proposeChange` / `readFile`
hooks are unused by this provider — the `muse` host edits
files itself and Ycode cannot intercept those edits; (b) the
IDE model appends "Agent mode: Ycode's tools are attached;
each change is a proposal you review" for every attached
provider, which overclaims for Meta (Ycode's MCP server is
not connected to the `muse` host — see §26.2.2.6). That line
should be qualified by the host for `.metaAssist`.

### 26.2.6 What was NOT ported, honestly unavailable

| Piece | Exact blocker |
|---|---|
| Ycode MCP tool execution inside the provider | `YcodeAssistant` cannot depend on `YcodeMCP`. Host tool calls are named and reported as `.activity` only. Connecting Ycode's MCP endpoint to `muse serve` would need a documented CLI mechanism; Legacy passed no MCP configuration to the host, and Meta's public docs describe `muse serve` only as hosting the session protocol. |
| Legacy's SystemIndex turn prompt (`baselinePrompt`, retrieved instructions, full native-tool catalog with JSON schemas) | No `SystemIndexService` in Ycode; the MCP catalog cannot be listed from this target. The turn carries the host's instructions + history + request only. |
| `MuseOtherModelsBridge.executeTurn` as a direct LLM turn | Needs `LLMService.streamChat` + `AssistManager` tool execution, neither of which exists in Ycode. Replaced by the proxy path (§26.2.2.7) + the host router's failover. Its portable pieces survive: `MuseThinkingTokenizer` (`<think>` splitting) and `MuseToolCallParser` (```tool_call parsing, names normalized, execution not included). The Autopilot rule inside it (approvals bypassed entirely) is not recreated anywhere. |
| Rate-limit failover inside the turn (Legacy's catch ran the turn again through the other-models bridge) | Same missing `LLMService` path. `isRateLimitError` is ported verbatim so the host-level router (Wave 15 failover) can fail over across providers instead. |
| `MuseCodeCLIHelper.readAuthInfo` / `getUserEmail` | Reads credential files (access tokens / API keys / email). Ycode checks existence only, never reads. Deliberate, not a gap to close. |
| `MuseCodeCLIHelper.runLoginFlow` / `MetaAccountAuthService` | Interactive browser sign-in (`muse login`, `NSWorkspace.open`). A turn without credentials fails honestly with a sign-in hint; the `/login` slash command returns the `.startLogin` effect for the host. |
| `MuseCodeCLIHelper.ensureMuseConfigHealth` | Rewrites `~/.config/muse/settings.json` (schema version, default model, reasoning efforts). Ycode never rewrites the user's Muse config. |
| `MuseCodeCLIHelper.installCLIViaNPM` | Installs `@muse-code/sdk` globally via npm. Out of scope; the provider reports `.notInstalled` with the install hint. |
| `MuseCodeCLIHelper.MuseAuthConfigFile` | Decodes credential files (see `readAuthInfo` above). Not ported. |
| `MetaAssistLifecycleManager` Combine/`AppSettings`/`ProjectSessionStore` observation | No Combine in this target; the host supplies `workspaceRoot`, the `muse` executable, and `isMetaActive` as closures. |
| Turn timeout / cancellation of a hung turn | Legacy waited indefinitely on `turn/completed` too. `cancelTurn` exists (`turn/cancel`, `already_terminal` swallowed) and `bridge.stopHost()` fails pending requests, but `executeTurn` has no timeout and a cancelled consumer leaks the inner turn task until the host answers. A turn timeout belongs to a later slice. |
| `/clear` and `/login` host effects | The manager returns `.clearSession` / `.startLogin` effects; the host must apply them (clear the conversation / start the Meta login flow). The provider itself applies neither. |
| Legacy `MuseOtherModelsBridge` availability/rate-limit filtering (`isAvailable`, `isCurrentlyRateLimited`) | `AssistCandidateModel` carries no such flags; eligibility/quarantine is the router's `eligibleCandidates`. The bridge filters only on provider (`meta_assist`) and the `muse-` prefix. |

### 26.2.7 The other-models bridge (`MuseOtherModelsBridge`)

What it bridges: the Muse SDK session runs on a third-party /
custom / cloud model instead of Meta's own. Mechanism (Legacy,
verbatim): the MSP host is started with
`--base-url http://127.0.0.1:<port>` pointing at a local
loopback proxy. The proxy serves the resolved other model:

- `/muse-code/models`, `/models`, `/v1/models` — the dynamic
  catalog: one model, Legacy's verbatim entry shape
  (`muse-code` metadata, family `custom-bridge`, release date
  `2026-10-12`, `attachment`/`reasoning`/`tool_call: true`,
  `limit: {context: 128_000, output: 16_384}`,
  `options: {reasoningEffort: "high"}`).
- `/responses`, `/v1/responses`, `/chat/completions` — the
  request body is parsed as `messages[]`, else `input[]`
  (empty → a single `"Hello"` user message), streamed through
  the injected `streamChat` closure as
  `response.output_text.delta` SSE events, then
  `response.completed`. Anything else → 404.

The proxy is rebuilt on Ycode's portable `LoopbackServer`
(BSD sockets, already in this target) instead of Legacy's
`NWListener` (Network framework, Apple-only). Default port is
still 19855 when free, otherwise any free loopback port
(`LoopbackServer` reports the real one). One deliberate
difference: `LoopbackServer` always answers
`Connection: close`, so the proxy does not send Legacy's
`Connection: keep-alive` (a duplicate header would confuse
the host); streaming is unaffected.

Model resolution is pure over injected inputs (no discovery
service, no settings store):

- `availableOtherModels(discovered:customEndpoints:cloudModelIDs:onlyUseFree:)`:
  discovered candidates minus `meta_assist` / `muse-`
  models, plus custom-endpoint models, plus cloud models
  (the default `swiftcode-cloud` id is always listed when no
  cloud model was discovered), then the free-only filter
  (`AssistModelEligibilityPolicy`), then the fallbacks when
  empty — `openrouter/free` when free-only, else Legacy's
  five paid fallbacks (`gpt-4o`, `gpt-4o-mini`,
  `claude-3-7-sonnet-20250219`, `gemini-2.5-pro`,
  `gemini-2.5-flash`).
- `resolveActiveModel(...)` — Legacy's five steps in order:
  (1) the explicitly selected other model (cloud ids resolve
  to `SwiftCode Cloud: <endpoint>`; a custom-endpoint hit to
  `"<name>: <id>"`; otherwise the discovered display name, or
  the router's provider display name via
  `AssistModelSpecification` — Legacy used
  `LLMService.provider(for:)` here); (2) the first custom
  endpoint's first eligible model; (3) the user's overall
  selected model when it is not a Meta model; (4) the first
  agent-compatible discovered model; (5) `openrouter/free` or
  `gpt-4o`.

The `streamChat` closure is injected by whoever starts the
proxy: the host routes the resolved model through Ycode's own
provider dispatch (`AssistantBackends.provider(forModelID:)`),
which is the Ycode equivalent of Legacy's
`LLMService.streamChat`. The bridge never picks a provider
itself. The provider's `proxyBaseURL` is nil until the host
starts a proxy and hands it over — other-model mode is off by
default, and nothing in this slice starts a proxy on its own.

### 26.2.8 Slash commands

All 36 built-ins are ported verbatim (id, name, title,
description, syntax, icon, category, arguments) — see
`MetaSlashCommandManager.builtInCommands`. Count verified
against Legacy: 36 ids, unique, all names `/`-prefixed.
Categories: Model (effort, model), Skills (skills, plugins),
Research (deep-research), Agent (goal, stop, init, subagents,
tasks, workflows), System (rules, voice, feedback, mcp, login,
logout), Session (export, copy, name, resume, fork, clear,
rewind, side, compact, recap, status, usage, questions),
Configuration (settings, keymap, theme, permissions, hud),
General (help).

- `muse skills list` capture: TSV parsing is the pure
  `parseSkillsList(_:)` (name + one more tab field minimum;
  `#` lines and blank names skipped; description from the
  fifth field, else the fourth, else `"Execute <name>
  skill"`; title is the name with `-`/`_` as spaces,
  capitalized; id `skill-<name>`, category `"Meta Skills"`).
  The runner uses a plain `Process` with Legacy's 15-second
  timeout — enforced here by terminating the child (Legacy's
  `runProcess` accepted a timeout but never enforced it).
  Failure, a missing binary, or empty output leaves the
  built-ins untouched, exactly as Legacy silently fell back.
- `searchCommands`: name/title/description/category, leading
  `/` ignored, empty query returns everything.
- `executeCommand` returns `(text, effect)`; the host applies
  the effect. Legacy's wording is kept verbatim for the four
  effect commands (`effort` → `.setReasoningEffort`,
  `model` → `.setModel`, `clear` → `.clearSession`,
  `login` → `.startLogin`); every other command returns its
  full command string as `.insertText`.
- Faithful quirk kept: the built-in `/model` choices list
  `muse-swift-2.0`, which is not in the fallback model catalog.
  Legacy shipped the same mismatch.

### 26.2.9 Lifecycle manager

Actor, shared instance. `startMonitoring(workspaceRoot:executable:isMetaActive:)`
(prewarms once, then the health loop), `stopMonitoring`,
`startEngine` (missing binary → idle, no throw — Legacy's
behaviour), `stopEngine` (sets the intentional-stop flag),
`restartEngine` (Legacy's quirk kept: `stopEngine` sets the
flag, `startEngine` clears it, so a restart never suppresses
the health check), `ensureRunning`, and `healthCheckOnce`
(the loop body as a pure step, so tests can drive it):
restarts only when monitoring, Meta is active, the stop was
not intentional, a binary and workspace are supplied, the
bridge is not running, and the last restart attempt is more
than 4 seconds ago. Numbers are Legacy's verbatim: check
every 5 seconds, at most one auto-restart per 4 seconds,
`restartCount` incremented per attempt.

### 26.2.10 Availability / discovery (consistency with §23.4)

Unchanged gate: binary + credential-file existence only,
never read. `availability()` now goes one step further than
Wave 15: installed + signed in → it asks the bridge for the
live list (`model/list`, 15-second timeout so a hung host
cannot hang the provider survey) and reports `.ready` with
the live models, falling back to the three-model catalog on
any failure. The fallback catalog is unchanged (context
1,007,997, output 128,000, reasoning variants). `send` with a
missing binary throws `.failed` with the install hint; with
no credentials, `.notSignedIn` with the sign-in hint.

`AssistantSettings` gains one field (Wave 16):
`metaReasoningEffort: String = "high"` (Legacy
`AppSettings.metaReasoningEffort`), decoded leniently
(missing key keeps the default), passed to the provider by
`AssistantBackends.provider(.metaAssist)`. No other settings
were added: the model travels in `ChatRequest.model`, and the
other-model toggles live with the host that owns the proxy.

### 26.2.11 File inventory (destination only, uncommitted)

New files (all `ycode/Sources/YcodeAssistant/`, existing
target — no `Package.swift` change, no new target):

| File | Lines | Contents |
|---|---|---|
| `MuseCodeMSPBridge.swift` | 388 | `MuseCodeMSPError`, `MuseCodeCLIError`, `MuseUUIDv7`, `MuseCodeMSPBridge` actor |
| `MetaAssistLifecycleManager.swift` | 165 | `MetaAssistLifecycleManager` actor |
| `MetaSlashCommandManager.swift` | 489 | `MetaCommandArgument`, `MetaSlashCommand`, `MetaSlashCommandEffect`, `MetaSlashCommandManager` |
| `MuseOtherModelsBridge.swift` | 573 | `MuseOtherModel`, `MuseCustomEndpoint`, `MuseOtherModelResolution`, `MuseOtherModelsBridge`, `MuseThinkingTokenizer`, `MuseToolCallParser`, `MuseLocalProxyServer` |
| `MetaAssistTurnExecutor.swift` | 807 | `MetaToolNameSource`, `MetaNormalizedToolName`, `MetaToolNameNormalizer`, `MetaTurnItemState`, `MetaTurnEvent`, `MetaTurnNotificationRouter`, `MetaTurnState`, `MetaAssistTurnExecutor` |

Modified files:

| File | Change |
|---|---|
| `ycode/Sources/YcodeAssistant/MetaAssistProvider.swift` | Header rewritten (bridge ported); `bridgeUnavailableMessage` removed; new init params (`reasoningEffort`, `attachment`, `knownToolIDs`, `proxyBaseURL`, `bridge`, `executor`); `fetchModels` (live `model/list`); `availability()` (live list with 15 s timeout, fallback otherwise); `send` runs a real turn; `AgentAttachable` conformance; private `withTimeout` helper |
| `ycode/Sources/YcodeAssistant/AssistantSettings.swift` | `metaReasoningEffort = "high"` + lenient decode; `provider(.metaAssist)` passes it (note: the same diff hunk region also carries a sibling slice's `alternativeKeysEnabled` — not this slice's) |
| `ycode/Tests/YcodeAssistantTests/AssistModelRoutingTests.swift` | Wave 15 test `sendFailsHonestlyWithoutBridge` renamed to `sendFailsHonestlyWithoutBinary` and updated to the new `.failed` behaviour |

Tests: `ycode/Tests/YcodeAssistantTests/MetaAssistBridgeTests.swift`
(728 lines, swift-testing, `@Suite(.serialized)` — serialized
because the fixture-`muse` tests mutate process-environment
variables the fake host reads).

### 26.2.12 Tests

`MetaAssistBridgeTests` (fixtures only — no live `muse`
binary, no real credentials):

- UUIDv7 shape / version nibble / variant bits / embedded
  timestamp / uniqueness.
- Bridge argv (`serve`, `--base-url <url> serve`) and
  environment (Homebrew paths appended); `startHost` with a
  nonexistent executable throws and leaves `isRunning` false.
- `normalizeToolName`: nil/empty → `system_tool`; prefix
  strip + registry hit (exact and case-insensitive); the three
  synonym rules; `bash` → `use_terminal` alias; an unknown
  name → `.passthrough`; a real MCP name with no injected
  registry → `.passthrough` (recorded, not claimed).
- Notification routing with fixtures: tool start (normalized
  name, described activity, unmapped recorded exactly once),
  tool output delta (tracked, never chat text), text /
  thinking deltas, `turn/completed`, `turn/unqueued` (only
  this turn's id settles), `session/modelChanged`,
  `approval/requested`, `approval/resolved` ignored, unknown
  method ignored.
- `parseModelList` (skips entries without `modelId`,
  defaults, empty → nil), `parseSessionID` (all three shapes
  + fallback), `isRateLimitError` / `isSessionNotLoaded`
  (including the `sessionNotLoaded` kind).
- `buildEffectivePrompt` (instructions + last 12 turns,
  duplicate of the current prompt excluded).
- Slash catalog (36, unique ids, `/`-prefixed names),
  search, `executeCommand` effects (verbatim text for the
  four effect commands; `.insertText` otherwise), skills-list
  TSV parsing (fifth/fourth-field description fallback,
  comment/blank/short lines skipped), merge/replace of
  terminal skills, terminal capture with a stub runner
  (missing binary / throwing runner keeps the catalog).
- Other models: exclusion of Meta models, custom-endpoint
  and cloud append, free-only filter + fallback, the five
  paid fallbacks, all five `resolveActiveModel` steps.
- `MuseThinkingTokenizer` (`<think>` open/close/split,
  cancel stops delivery) and `MuseToolCallParser` (no marker
  → `[]`; one valid block parsed, malformed block skipped).
- Proxy over a real `LoopbackServer`: `/v1/models` catalog
  (verbatim entry shape), `/responses` SSE translation
  (`response.output_text.delta` + `response.completed`),
  unknown path → 404.
- Lifecycle: monitoring flags, intentional-stop suppression,
  restart + throttle (fixture `sleep` binary as the host),
  idle without an executable.
- End to end against a fixture Python `muse` script
  (skipped when `python3` is absent): `availability()` lists
  the live model; `send` streams `"Hello world"` and
  `.finished`; a second turn resumes the session
  (`sess-1`); approval without an attachment is denied
  (`abort` reaches the host); approval with an attachment
  asks the permission UI once (`allow_once` / `abort`
  options) and the decision reaches the host.
- `send` without a binary → `.failed` with the install hint;
  without credentials (binary absent) → `.failed` (binary is
  checked first).

Updated Wave 15 test: `sendFailsHonestlyWithoutBinary`
(see §26.2.2.11). The other Wave 15 Meta tests
(`fallbackCatalog`, `availabilityWithoutBinary`,
`availabilityWithoutCredentials`,
`availabilityReadyWithCredentials`,
`metaAssistIsDispatchedByBackends`) are unchanged and still
pass by construction: the ready-with-credentials test uses a
locator whose binary path does not exist, so `fetchModels`
fails fast and the fallback catalog is reported.

Static checks only (no Swift toolchain in this environment):
delimiter balance 0/0/0 on all 9 touched files; no
TODO/FIXME/`fatalError`; no secret-pattern hits in new files;
`python3 -I .github/scripts/scan-public.py` was not re-run
here (it scans tracked files; these are uncommitted — the
coordinator runs it at integration). `swift build` / `swift
test` and a live `muse` CLI run are pending on Dylan's Mac.

### 26.2.13 Ledger rows completed by this slice

(For the coordinator to mark; this draft does not edit the
ledger.)

| Ledger row | New state |
|---|---|
| `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaAssistLifecycleManager.swift` (line 580) | IMPLEMENTED — `ycode/Sources/YcodeAssistant/MetaAssistLifecycleManager.swift` |
| `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaAssistProvider.swift` (line 581) | IMPLEMENTED — update note: `send` now runs real turns via `MetaAssistTurnExecutor`; `normalizeToolName` ported as `MetaToolNameNormalizer` (MCP ids, injected) |
| `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaSlashCommandManager.swift` (line 582) | IMPLEMENTED — `ycode/Sources/YcodeAssistant/MetaSlashCommandManager.swift` (36 built-ins + capture + search + effects) |
| `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeCLIHelper.swift` (line 583) | IMPLEMENTED (partial, as before) — update note: `MuseCodeCLIError` ported in `MuseCodeMSPBridge.swift`; credential-reading, login flow, config rewrite, and npm install deliberately NOT ported (§26.2.2.6) |
| `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeMSPBridge.swift` (line 584) | IMPLEMENTED — `ycode/Sources/YcodeAssistant/MuseCodeMSPBridge.swift` |
| `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseOtherModelsBridge.swift` (line 585) | IMPLEMENTED — `ycode/Sources/YcodeAssistant/MuseOtherModelsBridge.swift` (resolution + proxy + tokenizer + tool-call parsing; direct-LLM `executeTurn` honestly unavailable, §26.2.2.6) |

Not attempted (out of this slice's scope, still NOT STARTED):
`SwiftCode/Views/Assist/MuseCallsNativeToolsUI.swift` and
`SwiftCode/Views/Assist/MuseSDKToolCall.swift` (lines
10959–10960) — UI for Muse SDK tool calls; a UI slice, not
the bridge slice.

### 26.2.14 Evidence

- Legacy protocol: read live from Legacy @ `d51a8f0d` —
  `MuseCodeMSPBridge.swift` (368 lines),
  `MetaAssistProvider.swift` (785 lines, `executeTurn`
  notification handler, `normalizeToolName`,
  `isRateLimitError`, session/turn methods),
  `MuseOtherModelsBridge.swift` (732 lines, proxy paths,
  catalog JSON, SSE event names, resolution precedence,
  fallbacks), `MetaSlashCommandManager.swift` (655 lines,
  36 built-ins counted by `grep -c 'MetaSlashCommand(id:'`
  = 36, ids verified unique by sort/uniq),
  `MetaAssistLifecycleManager.swift` (141 lines, 5 s / 4 s),
  `MuseCodeCLIHelper.swift` (523 lines, incl. the
  credential-reading and login-flow code deliberately not
  ported).
- Public corroboration (web, 2026-11-06): Meta's Muse Code
  docs — "`muse serve` runs the protocol, and `muse schema`
  prints its JSON schema"; third-party CLI survey
  (2026-11-02) — "`muse serve` hosts a session over stdio
  using Meta's session protocol"; 1.4 changelog — `muse
  serve` gained `--provider`/`--model`, multi-workspace
  roots, plugins through the session protocol. No public
  source documents passing an MCP endpoint into `muse
  serve`; none was invented.
- Destination architecture: `ycode/Sources/YcodeAssistant/`
  (provider protocol, `AgentAttachment`, `JSONRPCMessage` /
  `LineFramer`, `LoopbackServer`, `CLIToolLocator`,
  `AssistantSettings` / `AssistantBackends`,
  `AssistModelSpecification` / `AssistCandidateModel` /
  `AssistModelEligibilityPolicy`, `SCCloudProvider`,
  `MCPServer.toolAliases` in `YcodeMCP` — read, not imported),
  `ycode/Package.swift` (YcodeAssistant depends only on
  `YcodeSubprocess`; YcodeMCP depends on YcodeAssistant —
  the cycle that forbids importing MCP types here),
  `ycode/Sources/YcodeIDECore/Assistant/CodingAssistantModel.swift`
  (attachment happens only for `AgentAttachable` providers,
  in agent mode).
- Verification in this environment (no Swift toolchain):
  delimiter balance 0/0/0 on all 9 touched files; 36
  built-in slash ids verified unique; no TODO/FIXME/
  `fatalError`; no secret-pattern hits; Legacy clean at
  `d51a8f0d`; destination main `d7cf1872`; SwiftCode-New
  untouched (its 3 modified files are pre-existing residue
  from earlier waves). `swift build` / `swift test` were not
  run here and are not claimed.
- Still pending (Mac): `swift build` + `swift test`
  (notably the fixture-`muse` end-to-end tests and the proxy
  SSE test), a live run against a real installed `muse` CLI
  (Dylan's Mac must have the CLI + sign-in), the host wiring
  for `knownToolIDs` (§26.2.2.4) and for the `/effort` /
  `/model` / `/clear` / `/login` slash effects, the host
  qualification of the "Ycode's tools are attached" line for
  Meta (§26.2.2.5), and starting the other-models proxy from the
  host when other-model mode is on (§26.2.2.7).

### 26.3 Slice C — SDK view windows seam + Assist backend attachment

### 26.3.1 What this slice does

What this slice does

Two honest-unavailable items from `specs/ide/sdk-platform.md` §18 are
closed:

1. **The 12 SDK view windows** — `SDKViewHost` is now implemented in
   YcodeUI (`YcodeSDKViewHost`), installed at app startup, and every
   one of the 12 view IDs is accounted for: 5 open on a real Ycode
   surface, 7 throw `.serviceUnavailable` with the exact reason no
   hostable surface exists. No window is faked; no empty placeholder
   is opened and called the window.
2. **The Assist backend attachment** — `SDKAssistService`'s
   `send` / `sendStreaming` are now served by `SDKAssistHostBackend`,
   a narrow adapter over Ycode's own `AssistantProvider.send`
   (`ChatRequest`). It executes through the host's configured provider
   with the extension's granted capabilities only, and the extension
   receives only the turn's results — never the host's conversation
   or credentials. `executeTool` is deliberately NOT attached (§4.3);
   it still throws `.serviceUnavailable` with the exact reason.

### 26.3.2 The 12 view windows — per-window disposition

The 12 view windows — per-window disposition

Legacy evidence (read live from Legacy source, not remembered):
Legacy's 12 openers are `SDKViewOpenerBuiltIns.registerBuiltInOpeners`
(`SwiftCode/SDK/Host/ViewOpener/`): 4 native-window managers
(`DatabaseExplorerWindowManager`, `DocumentationBrowserWindowManager`,
`CodingDictionaryWindowManager`, `VisualUIBuilderWindowManager`) and 5
toolbar-notification bridges (`deviceConnect`, `simulatorMain`,
`sfSymbolsBrowser`, `terminal`, `deployments` via
`ToolbarActionManager.destination(for:)` + `com.swiftcode.toolbarToolActivated`),
plus the 3 sibling openers (CI dashboard, virtualization console, live
preview). Legacy's window managers and notification bridge do not exist
in Ycode and are NOT re-ported; the opener logic was already ported in
Wave 14 and delegates to the `SDKViewHost` seam — this slice supplies
the host side of that seam.

| # | View ID | Legacy window (verified) | Ycode surface | Disposition |
|---|---|---|---|---|
| 1 | `db.ExploreView` | Database Explorer — SQLite browser (`SwiftCode/Views/Utilities/Database/DatabaseExplorerWindowManager.swift`) | None. The only SQLite client in Ycode (`CSQLite`) serves the Health store, not a browsable explorer; no DB UI file exists in YcodeUI/ycode-ide. | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no SQLite database browser." Building a SQLite explorer is a separate subsystem slice, not a host seam. |
| 2 | `docs.search` | Documentation browser — WebKit DocC bookshelf, offline, SQLite-backed (`SwiftCode/Features/AdvancedTools/Views/DocumentationBrowserView.swift`, window title "Documentation - Developer Bookshelf (Offline)") | None. Ycode's `QuickHelpView` is per-symbol help, not a DocC browser; no doc archive exists in Ycode. | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no documentation browser." |
| 3 | `dictionary.open` | Coding dictionary (`SwiftCode/Views/Utilities/CodingDictionaryView.swift`) — definitions are generated per query through `LLMService` ("Failed to parse dictionary response from LLMService"); no bundled term data exists in Legacy (no terms file found). | None. Nothing to port: no data, only an LLM call. | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no coding dictionary." |
| 4 | `uibuilder.open` | Visual UI Builder — standalone window (`VisualUIBuilderWindowManager`) | **Interface Builder editor** (`YcodeUI/Editor/InterfaceBuilderController`, opened via `WorkspaceWindowController.open(path:line:)` which routes `.storyboard`/`.xib` to the IB editor). | **Working (adapted).** The host opens the active project's first `.storyboard`/`.xib` (deterministic by path, build/dependency dirs skipped). Adaptation: Ycode's builder is document-based, not a standalone artboard window; a project with no IB document throws `.serviceUnavailable` naming that, instead of opening an empty builder. |
| 5 | `deviceconnect.open` | Device Connect sheet (toolbar bridge `deviceConnect`) | **Device Hub, Devices section** (`WorkspaceWindowController.presentDevices()` + `DevicesController.show(.devices)`; ⇧⌘2). | **Working.** |
| 6 | `simulator.view` | Simulator workspace sheet (toolbar bridge `simulatorMain`) | **Device Hub, Simulators section** (`presentDevices()` + `show(.simulators)`). Ycode has no separate simulator window — the sim viewer is a separate executable and simulators are hub rows — so the hub is the honest host. | **Working (adapted).** |
| 7 | `symbols.browse` | SF Symbol picker sheet (toolbar bridge `sfSymbolsBrowser`) | **Library panel, Symbols tab** (`WorkspaceWindowController.showLibrary(nil)` + `LibraryController.select(tab: .symbols)`; ⇧⌘L). The panel's Symbols tab is a real symbol browser for source and IB documents. | **Working (adapted).** |
| 8 | `sandbox.view` | Terminal sheet (toolbar bridge `terminal` — Legacy's own comment: "the REAL TerminalView (full interactive shell …). HIGH-RISK: this is not a sandbox"). | None. No terminal emulator exists anywhere in Ycode (no `TerminalView`, no shell surface; the debug console is output-only). | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no integrated terminal." Opening the debug console as a shell would misrepresent it. |
| 9 | `deployConsole.view` | Deployments console sheet (toolbar bridge `deployments` — Netlify / Vercel / GitHub Pages production deployments). | None. `YcodeRelease` is toolchain/release metadata, not deployments; no deployment provider exists in Ycode. | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no deployments console." |
| 10 | `ci.VisualWF` | CI / visual-workflows dashboard in its own window (`SDKCIWorkflowViewOpener`: "Opens the CI / visual-workflows dashboard in its own window"; local-automation surface, not a GitHub Actions inspector). | None. No visual-workflow or CI dashboard exists in Ycode. | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no visual-workflow or CI dashboard." |
| 11 | `virtualization.view` | Virtualization console in its own window (project required). | None as a surface. `YcodeHypervisor` (KVM/VZ engine) exists but has no console UI and is consumed only by `ycode-simd` internals; no hypervisor UI exists in YcodeUI/ycode-ide. | **Honestly unavailable.** `.serviceUnavailable`: "Ycode has no virtualization console." Engine ≠ surface; building a VM console is a separate slice. |
| 12 | `preview.live` | Live preview (no project required). | **Preview canvas in the editor area** (`WorkspaceWindowController.setCanvasShown(true)` + `refreshPreviews()`; `PreviewCanvasController`). Note: the Wave 14 comment naming YcodePreviews' `PreviewOpenViewsHost` as the attachment point is wrong for macOS — that type is the *Linux* OpenViews payload host. macOS live preview is the canvas. | **Working.** Shows the real canvas; with no Swift file focused it shows its genuine "No Previews" empty state (the surface's own honest state, not a placeholder). |

Also served by the same seam (not one of the 12, but the same
`SDKViewHost`): `assist.main` → the Coding Assistant pane
(`WorkspaceWindowController.revealCodingAssistant()`), via the
already-ported `SDKAssistUIOpener`. Working.

Rules the host enforces:
- Every workspace-anchored surface needs the key workspace window
  (`NSApp.keyWindow ?? NSApp.mainWindow`); with none open, opens
  throw `.serviceUnavailable` ("No workspace window is open.") —
  never presenting into the void. On Linux there is no YcodeUI, so
  the seam stays uninstalled and opens keep throwing
  `.serviceUnavailable` exactly as before.
- The unavailable set is a single source of truth:
  `YcodeSDKViewHost.unavailableReasons` (7 entries). The test
  `testAllTwelveViewIDsAreAccountedFor` asserts the working set ∪
  the unavailable set equals `SDKViewOpenerBuiltIns.builtInViewIDs`
  exactly — a 13th ID or a dropped ID fails the test.
- Surface failures propagate unchanged (a `.projectNotOpen` from the
  IB path is not rewritten as `.serviceUnavailable`).

### 26.3.3 Assist backend attachment — what it does

Assist backend attachment — what it does

`SDKAssistHostBackend` (`ycode/Sources/YcodeSDK/Host/Assist/`,
new, YcodeSDK already depends on YcodeAssistant — no new
dependency) conforms to `SDKAssistBackend` and is installed as
`SDKAssistService.shared.backend` at startup by
`YcodeSDKInstaller`. The service's existing checks run first, as
before: verified-key `developerAIAssist` entitlement, session
ownership (`liveSession`), message/history bounds, and the
`allowedToolIDs` snapshot. The backend trusts only what the service
passes it (an already-checked session) and re-derives identity from
nothing.

Per call:
- `complete(session:message:)` — resolves a text-completion provider
  (§4), builds one fresh `ChatRequest` from ONLY the extension's own
  session (§4.1), collects `.text` events, returns the joined text.
- `stream(session:message:)` — same resolution and request; yields
  text deltas, then the final empty-string element per the protocol;
  consumer cancellation cancels the provider request
  (`continuation.onTermination`).
- `executeTool(session:call:)` — NOT attached (§4.3).

The resolver (`YcodeSDKAssistResolver`, YcodeUI) answers which host
provider serves the turn: the session's requested model, when set,
routed through the host's existing `AssistantBackends.providerKind
(forModelID:)`; otherwise the provider the user chose in Settings ▸
Coding Assistant; model = session model, else the user's configured
model for that provider. The provider is built by
`CodingAssistantServices` from host settings + the host secret store.
The resolver runs on the main actor (`CodingAssistantServices` is
`@MainActor`).

### 26.3.4 Security argument (attachment point)

Security argument (attachment point)

#### 26.3.4.1 The request contains only the extension's own content

`ChatRequest` is built from exactly three inputs, all owned by the
extension's session: `instructions` = the session's system prompt
(or the host's fixed `defaultInstructions` when none — host-supplied
text stating the turn has no tools, files, or host conversation),
`messages` = the session's own history plus the new message,
`model` = the resolved model ID. `workingDirectory` is always `nil`.
Nothing else is read: no `Conversation` / `CodingAssistantModel`,
no host transcript, no workspace file, no settings beyond the
provider/model choice. The test
`testCompleteSendsOnlyTheExtensionSession` asserts the built request
equals the session content exactly (instructions, roles, order,
`workingDirectory == nil`).

#### 26.3.4.2 No key or credential ever crosses the boundary

`ChatRequest` has no key field. The provider is constructed inside
`AssistantBackends.provider(_:)`, which reads the host's stored key
from the secret store and holds it opaquely inside the provider; the
backend, the resolver, and the extension never see a key value. The
extension supplies no credential and cannot choose one: a
session-supplied model ID is only ever routed through the host's
`providerKind(forModelID:)` and then through the host's provider
factory. Provider failures are mapped to a generic
`.serviceUnavailable` (provider kind named, message not forwarded),
so host configuration state (e.g. an invalid key) is not reported to
the extension; the underlying failure is logged host-side to
`SDKDeveloperLogger` with identifiers only (provider kind, session
ID, error type — never message content, redacted again by the logger).

#### 26.3.4.3 Caller identity and the deny-by-default gate

Identity is the Wave 15 grant identity, unchanged: the service keys
sessions by `(extensionID, keyID)` — `createSession` snapshots
`allowedToolIDs` from the extension's ACTIVE grants, `liveSession`
rejects another extension's session with `.permissionDenied`, and
key revocation closes the sessions (`SDKAPIKeyStore` revocation hook
→ `closeSessions(forKeyID:)`), so a revoked caller's next turn fails
at the service before the backend is reached. The IPC dispatcher
still runs `SDKAssistGate.check` first and the entitlement check on
`assist.invoke`. The backend adds one local check (`session.isClosed`
→ `.invalidArgument`) so a stale session passed directly still fails.

#### 26.3.4.4 Why only text-completion providers may serve turns

`AssistantProvider.send` is a per-call seam, but not every provider
behind it is a text completion. CLI-agent providers (Claude Code,
Codex, Antigravity), ACP agents, Hermes (one-shot agent CLI that
runs in a directory), OpenCode (agent server — `send` creates a
server session and posts a prompt to it), and Meta Assist (Muse Code
CLI bridge) execute tools on the user's machine outside the
extension's granted set. The backend refuses all seven with
`.serviceUnavailable` (never a silent downgrade); the allowlist is
exactly Ollama, llama.cpp, OpenAI, OpenRouter, Foundation Models,
SwiftCode Cloud. The partition is pinned by
`testProviderKindPartitionCoversAllCases` (allowed ∪ rejected ==
`ProviderKind.allCases`, disjoint), so a future provider kind
cannot slip through unclassified — the test fails until it is placed
on one side. Consequences, stated plainly: an extension turn spends
the host user's configured provider/quota (same as a host Assist
turn — the user granted the `developerAIAssist` entitlement); there
is no per-extension quota, and a turn on an agent-configured host
fails honestly until Dylan configures a text provider. Agent-provider
support is a separate, deliberate decision (it needs a working-
directory/tool sandbox scoped to the extension's grants), not a
follow-up bug.

#### 26.3.4.5 What is NOT attached, and why

- **`executeTool`**: no tool runner reachable from the SDK host
  enforces the extension's granted capabilities. YcodeSDK does not
  depend on YcodeMCP, and the MCP runner's approval gate
  (`MCPWritePolicy` / `approve`) has no extension caller identity.
  Attaching it would let an extension drive host tools outside its
  grant snapshot. It throws `.serviceUnavailable` with that exact
  reason. Attaching it needs (a) a YcodeMCP dependency for YcodeSDK
  or a runner seam, and (b) caller identity plumbed through the MCP
  approval gate — both future work, not a wiring detail.
- **Host conversation**: the Legacy candidates were re-audited and
  remain rejected for the reasons Legacy recorded —
  `AssistManager.sendMessage` drives the user's shared visible
  conversation and returns `Void`; the agent session is
  singleton-owned and executes tools with no caller identity;
  `LLMService` spends the user's keys with no caller identity or
  Assist tool pipeline. Ycode's equivalents are the same shape
  (`CodingAssistantModel` owns the user's conversations; providers
  are per-call and stateless, which is exactly why the per-call
  `send(ChatRequest)` is the safe seam and the session loop is not).
- **`.activity` events** are dropped, never forwarded: they describe
  host-side agent activity (e.g. file reads) and are not the turn's
  result.

### 26.3.5 File inventory (destination repo only, uncommitted)

File inventory (destination repo only, uncommitted)

New:
- `ycode/Sources/YcodeSDK/Host/Assist/SDKAssistHostBackend.swift` (252 lines) — backend adapter + resolver protocol + resolution type.
- `ycode/Sources/YcodeUI/SDK/YcodeSDKViewHost.swift` (274 lines) — `SDKViewSurfaceActions` protocol, `WorkspaceSDKViewSurfaceActions`, `YcodeSDKViewHost`, `YcodeActiveWorkspaceProvider`, `YcodeSDKInstaller`.
- `ycode/Sources/YcodeUI/SDK/YcodeSDKAssistResolver.swift` (58 lines) — host provider resolver.
- `ycode/Tests/YcodeSDKTests/SDKAssistHostBackendTests.swift` (285 lines) — 13 tests.
- `ycode/Tests/YcodeUITests/YcodeSDKViewHostTests.swift` (162 lines) — 7 tests.

Modified:
- `ycode/Sources/YcodeUI/App/AppSupport.swift` (+3 lines) — `AppDelegate.applicationDidFinishLaunching` calls `YcodeSDKInstaller.installIfNeeded()` (after the layout-probe early return).

Not modified (deliberate): `ycode/Package.swift` (coordinator wiring,
§6), the ledger, `specs/ide/sdk-platform.md` (this draft is the
proposed §12/§18 text — see §7). Legacy untouched (clean at
`d51a8f0d`); SwiftCode-New untouched.

### 26.3.6 Package.swift wiring (applied by the coordinator)

No new target. Three one-line dependency additions, applied in
Wave 16 by the coordinator: `"YcodeSDK"` added to the `YcodeUI`
target, `"YcodeAssistant"` added to `YcodeSDKTests`, `"YcodeSDK"`
added to `YcodeUITests` (all in `ycode/Package.swift`).

### 26.3.7 Proposed spec text — applied

The §12/§18 text proposed in the slice draft was applied by the
coordinator as the §12 view-host paragraph and the §18 row
updates below, not pasted here.

### 26.3.8 Tests

Tests

`SDKAssistHostBackendTests` (13 tests, `YcodeSDKTests`; needs the
`YcodeAssistant` test-dep wiring in §6):
- Request construction: `complete` sends exactly the extension's
  session (instructions/roles/order, `workingDirectory == nil`,
  resolved model); default instructions when no system prompt.
- Isolation: two sessions with distinct marker messages — caller A
  receives only A's echo, caller B only B's.
- Streaming: text deltas + final `""`; a scripted `.activity`
  event naming a host file never reaches the output.
- Refusals: provider-kind partition covers all 13 `ProviderKind`
  cases; every agent kind refused and never receives a request;
  no-resolver, provider-not-ready, and closed-session cases throw
  `.serviceUnavailable` / `.invalidArgument`; a provider error is
  mapped to generic `.serviceUnavailable` without its message.
- `executeTool` throws `.serviceUnavailable` ("not attached").

`YcodeSDKViewHostTests` (7 tests, `YcodeUITests`; needs the
`YcodeSDK` test-dep wiring in §6): every working ID routes to
exactly its surface (fake records the call); every unavailable ID
throws `.serviceUnavailable` with its recorded reason and touches
no surface; the 12 IDs are exactly working ∪ unavailable; unknown
IDs throw; a surface failure propagates unchanged; the registry seam
routes through an installed host and throws without one.

### 26.3.9 Still pending

Still pending

- **Mac `swift build` / `swift test`** on Dylan's Mac (no Swift
  toolchain here): `swift test --filter SDKAssistHostBackendTests`,
  `swift test --filter YcodeSDKViewHostTests`, and a full build after
  the §6 wiring. Live verification still needed: open each working
  window from an installed extension (`ui.openView` for the 5 + 
  `assist.main`), confirm the 7 unavailable windows fail with the
  recorded reasons, and run one entitled `assist.invoke` turn
  end-to-end against the user's configured provider.
- **Dylan prerequisites (unchanged):** a configured text-completion
  provider for extension turns (Ollama running, or an OpenAI /
  OpenRouter key in Settings ▸ Coding Assistant; SCCloud needs its
  endpoint URL). Without one, turns fail honestly with
  `.serviceUnavailable` and the provider hint. No new credential is
  needed for this slice — the extension never supplies one.
- **`executeTool` attachment** (§4.5): needs a grant-enforcing tool
  runner — a YcodeMCP seam and caller identity in the MCP approval
  gate. Not a wiring detail; a design slice.
- **Agent-provider turns**: a deliberate product decision, not a
  bug (§4.4). Needs a working-directory/tool sandbox scoped to the
  extension's grants before any agent provider is admitted.
- **Linux**: the view host is macOS-only (YcodeUI); on Linux the
  seam stays uninstalled and view opens keep their previous
  `.serviceUnavailable`. The backend adapter itself is portable
  (YcodeSDK builds on Linux) but has no resolver installed there —
  installing one for the `ycode-ide` shell is follow-up, not part of
  this slice.

### 26.3.10 Evidence

Evidence

Evidence levels per the repo's clean-room protocol (AGENTS.md rule 4):

- **5 — read verbatim from Legacy source (Dylan's own code):** the
  12 view IDs and opener styles (`SwiftCode/SDK/Host/ViewOpener/
  SDKViewOpenerBuiltIns.swift`: 4 window managers, 5 notification
  bridges with exact `toolID` strings, 3 sibling openers); the
  Documentation Browser as a WebKit DocC bookshelf
  (`SwiftCode/Features/AdvancedTools/Views/
  DocumentationBrowserView.swift`); the dictionary as LLM-generated
  with no term data (`SwiftCode/Views/Utilities/
  CodingDictionaryView.swift:1207-1215`); the Deployments sheet
  providers (BuiltIns comment + `SwiftCode/Views/Deployments/
  DeploymentsView.swift`); the CI dashboard as a local-automation
  window (`SwiftCode/SDK/Host/ViewOpener/
  SDKCIWorkflowViewOpener.swift`); the Assist backend boundary and
  the rejected candidates with reasons (`SwiftCode/SDK/Host/Assist/
  SDKAssistService.swift` header); the terminal sheet as a full
  unsandboxed shell (BuiltIns comment). Direct porting authorised
  by Dylan under MIT.
- **5 — read verbatim from destination source:** every Ycode surface
  cited in §26.3.2 and every API used by the new code
  (`WorkspaceWindowController.presentDevices/showDevices/showLibrary/
  setCanvasShown/revealCodingAssistant/open(path:line:)`,
  `DevicesController.show(_:)`, `LibraryController.select(tab:)`,
  `CodingAssistantServices`/`AssistantBackends.provider(_:)`/
  `providerKind(forModelID:)`/`AssistantSettings.model(for:)`,
  `AssistantProvider.send(ChatRequest)`, `ChatEvent` cases,
  `SDKDeveloperLogger.log`, `SDKError`/`SDKAssistGate`/
  `SDKAssistService`/`SDKViewOpenerBuiltIns.builtInViewIDs`,
  `SDKBootstrap`, `AppDelegate.applicationDidFinishLaunching`).
  No Apple binaries, Ghidra, simulator IPSW, or `research/dirty/`
  were opened, run, or observed; no Apple code enters this work.
- **Behaviour verified by inspection only:** surface routing was
  verified by reading the Ycode controllers, not by running the app
  (no Swift toolchain, no Mac here). The "working" verdicts mean
  "a real Ycode surface exists and the host calls its real entry
  point" — visual/UX verification is part of the pending Mac check
  in §10.

### 26.4 Slice D — scheme discovery · model discovery · Antigravity catalog · installer fallback · Gemini key rotation · SDK session configuration

DRAFT for `specs/ide/sdk-platform.md` (§26). Written by Slice D, 2026-11-06.
Do NOT edit the ledger or the spec directly — the coordinator merges this
section. No commit, no push by this slice.

Sources read live for this section (Legacy read-only, main `d51a8f0d`;
destination main `d7cf1872` at wave start):
`SwiftCode/Backend/Assist/Tools/AssistXcodeProjectResolver.swift`,
`SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift`,
`SwiftCode/Backend/Assist/AlternativeKeyManager.swift`,
`SwiftCode/Backend/Assist/AssistModelRouter.swift`
(`sdkDefaultModelIDs`, `selectModelForSDK`, `createSyntheticSDKModel`,
`buildSDKConfiguration`, the key-rotation branch of
`handleTurnFailure`, `resolveAPIKey`, `hasCredentials`),
`SwiftCode/Services/AntigravitySDKModelFetcher.swift`,
`SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKConfiguration.swift`,
`SwiftCode/SDK/Host/SDKInstaller.swift`.
Destination: `ycode/Sources/YcodeAssistant/` (host: `AssistModelRouting.swift`,
`AssistantSettings.swift`, `SecretStore.swift`, `Core.swift`,
`OpenRouterProvider.swift`, `OpenAIProvider.swift`, `HTTP.swift`),
`ycode/Sources/YcodeBuild/` (`XcodebuildEngine.swift`, `SwiftBuildEngine.swift`,
`BuildEngine.swift`), `ycode/Sources/YcodeWorkspace/Scheme.swift`
(`Scheme.discover`), `ycode/Sources/YcodeSDK/Host/SDKInstaller.swift`,
`ycode/Sources/YcodeSDK/Host/ServiceAdapters/Build/SDKBuildService.swift`,
`specs/ide/schemes.md`, `sdk/scripts/package-sdk.sh`,
`sdk/package/package.json` + `dist/`.
Public docs checked live: Anthropic `GET /v1/models`
(`x-api-key` + `anthropic-version: 2023-06-01`, confirmed by web
search 2026-11-06) and Mistral `GET /v1/models` (confirmed the
same way). Gemini `GET /v1beta/models` and DashScope
compatible-mode `GET /v1/models` are taken from Legacy's own
source, which called them in production.

### 26.4.1 What landed

All six carried-over items from §18 / §23.6 are now ported, except
the installer bundled fallback, which is a recorded final decision
to stay absent (§26.4.4.5).

| Legacy piece | Destination |
|---|---|
| `AssistXcodeProjectResolver.resolveScheme` / `firstListedScheme` (`xcodebuild -list -json`, explicit → first listed → bundle name) | `XcodeSchemeDiscovery` (`ycode/Sources/YcodeBuild/XcodeSchemeDiscovery.swift`), wired into `SDKBuildService.run` |
| `AssistModelDiscoveryService` Gemini / Anthropic / OpenAI / Mistral / Qwen legs | `AssistModelDiscoveryService` (`ycode/Sources/YcodeAssistant/AssistModelDiscovery.swift`); OpenRouter stays in `OpenRouterProvider.listModels` (Wave 9) |
| `AntigravitySDKModelFetcher` (seed catalog, `agy models` fetch + parse, derive helpers) + `AssistModelRouter.sdkDefaultModelIDs` / `createSyntheticSDKModel` | `AntigravitySDKCatalog` (`ycode/Sources/YcodeAssistant/AntigravitySDKCatalog.swift`) |
| `AlternativeKeyManager` (import, selection, rate-limit cooldown, failure counting, rotation) | `GeminiKeyRotationManager` (`ycode/Sources/YcodeAssistant/GeminiKeyRotation.swift`) |
| `AssistModelRouter.buildSDKConfiguration` / `selectModelForSDK` | `SDKSessionConfiguration` + `SDKSessionConfigurationBuilder` + `AssistModelRouter.selectModelForSDK` (`ycode/Sources/YcodeAssistant/AssistSDKModelSelection.swift`) |
| Key-rotation branch of `AssistModelRouter.handleTurnFailure` | `AssistModelRouter.handleTurnFailureWithKeyRotation` (same file) |
| Installer bundled fallback | Stays absent — final decision (§26.4.4.5); `SDKInstaller.bundledFallbackStatus()` reports it |

### 26.4.2 Build scheme discovery

`XcodeSchemeDiscovery` (YcodeBuild — it already depends on
YcodeWorkspace and YcodeSubprocess, so no new target and no
`Package.swift` change) composes Ycode's existing machinery in
Legacy's precedence order instead of duplicating it:

1. **Explicit scheme, when it names a scheme this container has.**
   Deliberate deviation from Legacy: Legacy's explicit parameter
   was a user-supplied *scheme*; the callers here pass a *target*
   name, which is often not a scheme. Using it blindly reproduces
   the old bug (the target used as the scheme). An unknown explicit
   name falls through to discovery and is used only as the last
   resort, with the reason recorded.
2. **First scheme from `xcodebuild -list -json`** — run through
   an injectable `XcodebuildListRunner` (default: `/usr/bin/xcodebuild`
   on macOS only; on Linux, or anywhere the tool is absent, the
   runner returns nil). Output parsed exactly like Legacy
   (`{"project": {"schemes": [...]}}` / `{"workspace": {"schemes":
   [...]}}` via `JSONSerialization`); anything unparseable yields
   no schemes, never an error.
3. **First `.xcscheme` file on disk** — `Scheme.discover(in:user:)`
   (shared, then the current user's). Projects read their own
   bundle; workspaces read their own bundle plus every sibling
   `.xcodeproj` in the same directory (the usual layout for
   workspace members). Members referenced from elsewhere are
   covered by the `-list` leg when it can run; the file leg does
   not parse `.xcworkspacedata`.
4. **Explicit name, or the container bundle's base name** (Legacy's
   final fallback), with the exact reason recorded.

`resolveScheme(explicit:container:) -> ResolvedScheme` always
carries `scheme`, `source` (`.explicit` / `.listed` /
`.fileDiscovered` / `.containerName`) and `reason` (set whenever
the answer is a fallback). Discovery never throws and never fails
a build: when `xcodebuild` is absent the file leg still runs.
Packages have no schemes — the target name is used as the scheme,
with that reason recorded.

Wiring: `SDKBuildService.run` resolves the scheme through an
injected `XcodeSchemeDiscovery` (default: the live one) after the
container is resolved and before the `BuildRequest` is built, and
logs the fallback reason via `SDKLog.info` when one exists. The
container half is still resolved from the project root
(`.xcworkspace` > `.xcodeproj` > `Package.swift`); the resolver's
`locate(relativePath:)` and pbxproj introspection (`groupID`,
`sourcesBuildPhaseID`) belong to the MCP project tools, not to this
service, and are not ported here.

Tests: `ycode/Tests/YcodeBuildTests/XcodeSchemeDiscoveryTests.swift`
(13 tests, swift-testing, stub `-list` runner + temporary
`.xcodeproj` / `.xcworkspace` fixtures with minimal `.xcscheme`
files; no real `xcodebuild` is ever run): `-list` JSON parsing
(project / workspace / malformed), file discovery (project,
workspace + siblings with dedup, package empty), precedence
(explicit-when-known, first listed over files, unknown explicit
falling through to listed, file leg when `-list` is unavailable,
container-name fallback with its reason, package target-as-scheme,
container args / name).

### 26.4.3 Model discovery — Gemini / Anthropic / OpenAI / Mistral / Qwen

`AssistModelDiscoveryService` (YcodeAssistant actor; no
`@Observable` / `@MainActor` singleton, no `shared` — the host
owns one per secret store and transport, which is what makes it
testable) ports the five direct-provider legs. OpenRouter stays
where Wave 9 put it (`OpenRouterProvider.listModels`); Apple
Foundation Models, OpenCode, Hermes, Meta and the local servers
stay with the host's `survey()` / `availability()`.

Real list endpoints, nothing invented (Legacy's endpoints,
verbatim, plus the two web-confirmed above):

| Provider | Endpoint | Auth |
|---|---|---|
| Gemini | `GET https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=<key>` | key in query (Legacy's behaviour; the key is never logged) |
| Anthropic | `GET https://api.anthropic.com/v1/models?limit=1000` | `x-api-key`, `anthropic-version: 2023-06-01` |
| OpenAI | `GET https://api.openai.com/v1/models` | `Bearer` |
| Mistral | `GET https://api.mistral.ai/v1/models` | `Bearer` |
| Qwen | `GET https://dashscope.aliyuncs.com/compatible-mode/v1/models` | `Bearer` |

Parsing and filtering are Legacy verbatim per provider: Gemini
only `generateContent` models (an empty method list passes),
`models/` prefix stripped, embedding / aqa / imagen excluded,
context from `inputTokenLimit` (default 1,000,000), flash
priority 10 else 20; Anthropic `data[].id` / `display_name`,
context 200,000, priorities sonnet 15 / haiku 14 / else 25;
OpenAI `data[].id` with Legacy's exclusion list (embedding,
dall-e, tts, whisper, moderation, audio, realtime, text-search /
text-similarity, davinci, babbage, curie), vision on `4o` /
`vision`, context 128,000, mini priority 18 else 12; Mistral
`data[].id` excluding `embed`, vision on `pixtral`, priority 28,
context 128,000; Qwen `data[].id` excluding `embed`, vision on
`vl`, priority 30, context 128,000.

Behaviour, Legacy verbatim in shape:

- Keys come from the `SecretStore` — one canonical account per
  provider (`gemini.api-key`, `anthropic.api-key`, `mistral.api-key`,
  `qwen.api-key`; OpenAI reuses the existing `openai.api-key`).
  Legacy also tried several alternate keychain keys and
  `APIKeyManager`; Ycode keeps one account per provider, so a key
  stored under a Legacy-era name must be re-entered in Settings.
  A provider with no key contributes nothing (except Gemini,
  below) and is not an error.
- The five legs run concurrently in `discoverAllModels`
  (300s cache, `forceRefresh` bypasses it). A failing leg (non-200,
  network error, unparseable body, empty after filtering) contributes
  no models; Gemini records its error in `lastDiscoveryErrors`,
  the other legs fail silently, as in Legacy. Discovery never
  invents a model to fill the gap.
- Gemini with no key, with Google OAuth, or with a failed / empty
  live fetch falls back to the Antigravity catalog (Legacy
  `fallbackAntigravityModels`): catalog models are returned marked
  synthetic, configured/available only when the host reports a
  Google OAuth session (`isGoogleOAuthAuthenticated`, set by the
  host — the sign-in flow is not model fetching). When a Gemini
  key is present but the alternative-keys store also has keys, the
  rotation manager's active key is used as the Gemini key.
- `hiddenProviderNames` / `removedModelIDs` are session state in
  this service (Legacy persisted them in UserDefaults; persisting
  them in `AssistantSettings` is follow-up work). Foundation
  Models can never be removed or hidden, as in Legacy.
- No custom / local endpoint legs and no cloud-catalog leg:
  custom & local endpoints belong to another slice; the cloud
  catalog belongs to the SCCloud work. The host's `survey()`
  covers those sources.

Feeding the router (no parallel registry): `candidates(from:)`
converts discovered models to `AssistCandidateModel`s, and the
host passes those to `AssistModelRouter.eligibleCandidates` /
`resolveDefaultModel`. The host provider mapping follows Wave 15
§23.2: Gemini / Anthropic / Mistral / Qwen route through
`.openRouter`, OpenAI through `.openAI`. Because OpenRouter only
serves models in `provider/model` form, a natively-discovered id
is translated to its OpenRouter id in `modelIdentifier` —
`google/<id>`, `anthropic/<id>`, `mistralai/<id>`, `qwen/<id>`
— while `id` keeps the native id the list endpoint returned.
Callers must send `modelIdentifier`, not `id`, when the provider
is OpenRouter. The translation uses OpenRouter's published
provider slugs; it is a routing translation, not a discovery
claim — the model itself was genuinely listed by its own
provider. Mistral candidates also carry the endpoint URL
`https://api.mistral.ai/v1`, matching what
`AssistCandidateModel.fromSpecification` already does for
Mistral ids. The synthetic marking survives the conversion
(`isSynthetic` on `AssistCandidateModel`, new in this wave).

Transport: `ModelDiscoveryTransport` (`get(url:headers:timeout:)`)
is injectable; the live transport is `HTTP.send` (the same minimal
HTTP the providers use), 8s per request like Legacy. Tests use a
stub transport keyed by host.

Tests: `ycode/Tests/YcodeAssistantTests/AssistModelDiscoveryTests.swift`
(15 tests, swift-testing, stub transport, `MemorySecretStore`,
fake keys assembled from parts): per-provider parsing (all five
legs, including every Legacy exclusion), malformed bodies, a full
concurrent run (5 calls, Legacy order), a failing leg (Gemini 429
→ catalog fallback + recorded error; other legs contribute
nothing), no keys → only the 9-model catalog fallback (synthetic,
unconfigured), OAuth → catalog fallback configured, cache reuse /
force refresh (call counts), Foundation-model removal refusal,
agent-compatible exclusion of unconfigured models, and the
OpenRouter id translation (all five providers) plus synthetic
marking preservation.

### 26.4.4 Antigravity SDK catalog

`AntigravitySDKCatalog` (YcodeAssistant actor) ports
`AntigravitySDKModelFetcher` faithfully:

- `seedModels`: Legacy's 9 entries verbatim (ids, display names,
  thinking levels, context windows, categories). They are Dylan's
  own catalog entries — but they are a *seed*, not a discovery:
  callers must present them as catalog models, never as
  live-listed.
- Live fetch: `agy models` on Legacy's binary candidates in
  order (`~/.gemini/bin/agy`, `~/.local/bin/agy`,
  `/usr/local/bin/agy`, `/opt/homebrew/bin/agy`), run via
  `Subprocess.run` with `PAGER=cat`, `NO_COLOR=1`, `TERM=dumb`.
  `parseAgyModelsOutput` is Legacy verbatim (ANSI stripping,
  braille stripping, "Fetching available models..." removal,
  first token = id, rest = display name). An empty result keeps
  the current list ("Retaining current registry"). The fetched
  list replaces the seed list in memory; `sdkDefaultModelIDs`
  is the live list when non-empty, otherwise the seeds (Legacy
  `AssistModelRouter.sdkDefaultModelIDs`, now owned by the
  catalog).
- `deriveThinkingLevel` / `deriveContextWindow` /
  `deriveCategory` are Legacy verbatim. `getModel(byID:)` checks
  live models, then seeds. `isAntigravityCatalogModel` is
  case-insensitive membership; membership is metadata, not
  authorization — it never implies a credential exists.
- `createSyntheticCandidate(modelID:isConfigured:)` ports
  `createSyntheticSDKModel` onto `AssistCandidateModel`: the
  candidate is marked `isSynthetic` and its `statusDescription`
  names the catalog ("… Thinking · Antigravity catalog
  (synthetic)"). `isConfigured` is the caller's credential
  verdict — the catalog itself never claims a credential exists.
  The provider comes from `AssistModelSpecification.specification(for:)`,
  consistent with §23.2 (Gemini / Claude ids route through
  `.openRouter`, `gpt-oss` through `.openAI`).

Adaptations: no SwiftUI (`iconName` / `thinkingColor` not
ported — callers derive icons from `thinkingLevel` /
`isImageModel` themselves); no `@Observable` / `@Published`
(actor instead); no disk cache (Legacy persisted the fetched
list in UserDefaults — Ycode keeps it in memory only and falls
back to the seed catalog on a fresh launch, exactly as Legacy
did with an empty cache; persisting the cache is follow-up
work, not a behaviour change); **no Python fallback** —
Legacy's `runPythonSDKModelDiscoverySync` ran the vendored
Google Cloud SDK's bundled python3, and that vendored tree is
`EXTERNAL_OR_UNAVAILABLE` in the migration inventory and was
never copied into Ycode, so there is no bundled runtime to run.
Live discovery here is the `agy` binary only.

Tests: `ycode/Tests/YcodeAssistantTests/AntigravitySDKCatalogTests.swift`
(9 tests): seed catalog verbatim (9 ids, categories, context
windows), default-id fallback to seeds, `getModel` seed fallback,
case-insensitive membership, `agy` output parsing (ANSI +
braille), all three derive helpers, synthetic candidate marking
(+ unknown-id derivation, + image-model subagent exclusion).

### 26.4.5 Installer bundled fallback — final decision: stays absent

`SDKInstaller.bundledFallbackStatus()` (new in
`ycode/Sources/YcodeSDK/Host/SDKInstaller.swift`) reports
`.present(url:)` or `.absent(reason:)`; presence is file
existence only — contents are verified by `npm install` +
`inspect` when the fallback is used, not here. In this checkout
it reports `.absent` with the exact reason.

**Decision: the bundled fallback stays absent. No tarball ships
in-repo; none was invented and Legacy's tarball was never copied.**
A genuine distributable CAN be produced from this repo's own
build: `npm pack` in `sdk/package` produces
`swiftcode-sdk-1.0.0.tgz` — verified 2026-11-06 with
`npm pack --dry-run` (no file written): `@swiftcode/sdk`
1.0.0, 52.8 kB, 29 files, shasum
`1a1c24f569db8532ea9a839b27ecea1694c8acfa`, from the checked-in
`dist/` (the package version is 1.0.0, matching
`SDKInstaller.expectedVersion`). What Dylan must supply before
the fallback can exist:

1. Publish that tarball to the `sdk-v1.0.0` branch at
   `SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz` (the
   `downloadURL` — the remote path the installer already probes),
   or
2. Bundle it as a YcodeSDK resource with the `Package.swift`
   resource wiring — a coordinator decision, since a checked-in
   binary blob plus resource wiring was out of scope for this
   slice.

Until then the installer fails honestly when GitHub is
unreachable — it never claims a bundled copy exists. Note
`sdk/scripts/package-sdk.sh` does NOT produce this tarball: it
packages the full assembled SDK (`SwiftCodeSDK-1.0.0.tar.gz`,
including the Swift CLI binary) and its clean-room extraction
test fails until the Swift SDK migration wave lands. The
installer fallback needs the npm package tarball (`npm pack`),
not the assembled-SDK archive.

Test: `testBundledFallbackIsAbsentWithReason` in
`ycode/Tests/YcodeSDKTests/SDKInstallerTests.swift` — asserts
`.absent` with the reason naming `npm pack` and `sdk-v1.0.0`,
and fails loudly (asking to be updated to assert `.present`)
if a tarball is ever bundled.

### 26.4.6 Gemini key rotation

`GeminiKeyRotationManager` (YcodeAssistant actor) ports
`AlternativeKeyManager` faithfully:

- Types verbatim: `AlternativeKeyState`, `AlternativeKeyMetadata`
  (id, masked value, SHA-256 hash, state, last used,
  rate-limited-until, failure / success counts, order index,
  added at), `KeyImportResult`.
- Import rules verbatim: comma / newline / `;` separated,
  surrounding quotes stripped, 20–120 characters with no
  whitespace to be valid, duplicates detected by hash against
  both the batch and the stored keys, an un-storable key counts
  as invalid, first available key becomes active.
- Masking verbatim (`AIza` prefix or first 4 chars + bullets +
  last 4; short keys show only bullets) and hashing verbatim
  (SHA-256 hex — computed with YcodeAssistant's own pure-Swift
  `SHA256` in `Crypto.swift`, so the manager builds on Linux
  without CryptoKit; the digest is the same one CryptoKit
  computed).
- Selection verbatim: fewest failures first, then the shortest
  circular distance from the active key's position; the previous
  active key returns to `.ready`.
- `markRateLimited` (default 60s, minimum 2s, counts a failure),
  `markHealthy` (clears rate-limit / failure state, counts a
  success), `markFailed` (`.invalid` on permanent auth error),
  `rotateNow`, `resetHealth` (leaves `.disabled` / `.invalid`
  alone) — all verbatim.

Storage adaptation (the one structural change): Legacy kept raw
keys in the Keychain and metadata in UserDefaults. Ycode keeps
raw keys in the `SecretStore` (`gemini.alt-key.<uuid>`, Keychain
on macOS, a 0600 file on Linux) and the metadata envelope in the
same store (`gemini.alt-keys.metadata`). The metadata holds only
masked values and SHA-256 hashes — never a raw key — and it is
the manager's index, because `SecretStore` has no enumeration:
if the metadata is deleted, any stored raw keys become
unreachable orphans (they stay in the store until the user
removes them by re-importing, which dedups by hash). New
`SecretAccount` entries: `geminiKey` (`gemini.api-key`, the
primary key used by discovery), `geminiAltKeyPrefix`,
`geminiAltKeysMetadata`, `anthropicKey`, `mistralKey`, `qwenKey`.
No `@Observable` / `@MainActor` singleton and no `shared` — the
host owns one per secret store, which is what makes the manager
testable with `MemorySecretStore`. No `os.Logger` — the manager
is silent; callers log the masked value when they rotate. No
`reorderKeys(from:to:)` with `IndexSet` (an AppKit type):
`reorderKeys(_:)` takes the ordered ids instead.

The failover branch (Legacy `handleTurnFailure`'s rotation
branch) is `AssistModelRouter.handleTurnFailureWithKeyRotation`
(see §26.4.4.7): when rotation is enabled
(`AssistantSettings.alternativeKeysEnabled`, new in this wave —
Legacy `AppSettings.alternativeKeysEnabled`, default false) and
the failure is a rate limit / quota exhaustion, the active key
is marked rate-limited for 60s and the next available key is
selected — the SAME model is retried with the new key, and the
handoff names the rotated key's masked value. Only when no other
key is usable does the turn fall through to the plain
`handleTurnFailure` (next model, or nil when automatic switching
is off). The plain `handleTurnFailure` is unchanged.

Tests: `ycode/Tests/YcodeAssistantTests/GeminiKeyRotationTests.swift`
(11 tests, `MemorySecretStore` only, fake keys assembled from
parts): masking / hashing / validation, import counts (new /
duplicate / invalid), quote / semicolon handling, active-key
return + marking, fewest-failures-then-circular selection,
rate-limit cooldown blocking then `markHealthy` clearing,
permanent-auth-error → `.invalid` (never selected again,
`resetHealth` leaves it alone), `rotateNow` (including the
single-key nil case), metadata persistence across manager
instances sharing a store, removal fallback, reordering.

### 26.4.7 SDK session configuration and model selection

`SDKSessionConfiguration` is the Ycode equivalent of Legacy's
`GoogleCloudSDKConfiguration`: the model id to send, the host
provider that will run the turn (`ChatRequest` + the chosen
`ProviderKind`), the thinking level, `enableSubagents`, the
execution mode (`"antigravity"` for a Google OAuth session,
`"api_key"` for a stored provider key, nil when neither is
available and the turn cannot run), `hasAPIKey` (a boolean —
never the key itself), `isOAuthAuthenticated`, and `baseURL`.
`SDKSessionConfigurationBuilder.build(for:...)` ports
`buildSDKConfiguration`'s execution-mode rules verbatim in
shape: OAuth when the host reports a Google OAuth session and
the model is a Google / catalog model or no direct key exists;
otherwise `"api_key"` when the model is a Google model and key
rotation is enabled; otherwise `"api_key"` when a direct key
exists, `"antigravity"` when only an OAuth token exists, else
nil. The thinking level comes from the catalog's derive rules.

Not carried over (no Antigravity SDK session in Ycode to
consume them): `vertex` / `project` / `location` (Vertex AI),
`skillsPaths` / `workspaces` / `appDataDir` / `saveDir` (the
SDK's on-disk session), `tools` (the SDK's tool table),
`litertModelPath` / `litertBackend`, `serviceTier`,
`maxSubagentDepth` / `allowedSubagents`, `systemInstructions`,
`useSavedModels`, `toolkit`, `downloadIfMissing`,
`enableSpeculativeDecoding`, `activeExecutionMode`. The
`objective` parameter is kept for API parity (Legacy passed it
to `resolveDefault`); it does not change the configuration.

`AssistModelRouter.selectModelForSDK` ports Legacy's selection
verbatim in shape:

- SwiftCode Cloud short-circuit: when the cloud toggle is on and
  the selected id is a cloud id, the cloud model is used under
  every strategy.
- `"default"` / `"rotation"` (both decode to
  `.providerDefault` here; rotation is a failover behaviour, not
  a selection strategy): ONLY models listed in the Antigravity
  catalog (`sdkDefaultModelIDs`), restricted to the ones that are
  configured. An explicit custom / third-party id (contains `/`,
  or mentions ollama / llama / claude / gpt) is honoured as-is;
  otherwise the first configured catalog model wins. When the
  catalog does not know the effective id (stale selection, fetch
  not completed), the discovered-candidate list is consulted
  before falling back to a synthetic catalog record.
- `"app_models"`: the whole discovered-candidate list.
- Anything else: `resolveDefaultModel`.

The method never returns nil: the last resort is a synthetic
catalog record for the effective id, as in Legacy. `candidates`
is the eligible, ranked candidate list (the caller passes
`eligibleCandidates` output).

Tests: `ycode/Tests/YcodeAssistantTests/AssistSDKModelSelectionTests.swift`
(14 tests, fixtures only): configuration building (Gemini model,
thinking levels, OAuth-wins, no-key/no-OAuth → no execution
mode, rotation mode), `selectModelForSDK` (cloud short-circuit,
default-strategy catalog restriction, catalog selection honoured,
explicit third-party id honoured, app-models discovered set +
fallback), rotation-aware failover (rotates the key and retries
the same model with the masked value in the handoff, falls
through to the next model when no other key exists, returns nil
when auto-switch is off and there is nothing to rotate to, does
not rotate for non-rate-limit errors).

### 26.4.8 What is still pending (not this slice)

- Mac `swift build` / `swift test` for everything in this
  slice (no Swift toolchain in this environment) — static
  checks only (§26.4.4.9).
- The `validate.mjs` capability admission, Muse Code MSP bridge
  + lifecycle + slash commands, the 12 SDK view windows seam,
  Assist backend attachment, and the Distribution regeneration
  decision are other slices' work; nothing in this slice touches
  them.
- `hiddenProviderNames` / `removedModelIDs` persistence
  (session state in this slice; `AssistantSettings` is the
  natural home).
- Antigravity catalog disk cache (in-memory only in this slice;
  Legacy persisted it in UserDefaults).
- No Settings UI for the new pieces in this slice: the Gemini /
  Anthropic / Mistral / Qwen key fields, the alternative-keys
  management UI (Legacy `AlternativeKeysView`), and the
  `alternativeKeysEnabled` toggle have no pane yet — the keys
  can be stored programmatically via the `SecretStore`
  accounts, and rotation only runs when the toggle is on.
- Dylan prerequisites, unchanged: a Gemini API key (and
  alternative keys, if he wants rotation), Anthropic / OpenAI /
  Mistral / Qwen API keys for the new discovery legs, a Google
  OAuth session for the catalog-fallback path, and the SDK
  tarball publication described in §26.4.4.5 if he wants a bundled
  installer fallback.

### 26.4.9 File inventory (this slice only)

New files (destination repo only, uncommitted):

- `ycode/Sources/YcodeAssistant/AntigravitySDKCatalog.swift` (344 lines)
- `ycode/Sources/YcodeAssistant/AssistModelDiscovery.swift` (733 lines)
- `ycode/Sources/YcodeAssistant/GeminiKeyRotation.swift` (421 lines)
- `ycode/Sources/YcodeAssistant/AssistSDKModelSelection.swift` (324 lines)
- `ycode/Sources/YcodeBuild/XcodeSchemeDiscovery.swift` (232 lines)
- `ycode/Tests/YcodeAssistantTests/AssistModelDiscoveryTests.swift` (310 lines, 15 tests)
- `ycode/Tests/YcodeAssistantTests/AntigravitySDKCatalogTests.swift` (113 lines, 9 tests)
- `ycode/Tests/YcodeAssistantTests/GeminiKeyRotationTests.swift` (164 lines, 11 tests)
- `ycode/Tests/YcodeAssistantTests/AssistSDKModelSelectionTests.swift` (272 lines, 14 tests)
- `ycode/Tests/YcodeBuildTests/XcodeSchemeDiscoveryTests.swift` (188 lines, 13 tests)

Modified files (destination repo only, uncommitted):

- `ycode/Sources/YcodeAssistant/AssistModelRouting.swift` (+63/−25: `isSynthetic` on `AssistCandidateModel`, header + `handleTurnFailure` doc updates)
- `ycode/Sources/YcodeAssistant/AssistantSettings.swift` (+17: `alternativeKeysEnabled`, default false)
- `ycode/Sources/YcodeAssistant/SecretStore.swift` (+25: `geminiKey`, `anthropicKey`, `mistralKey`, `qwenKey`, `geminiAltKeyPrefix`, `geminiAltKeysMetadata`)
- `ycode/Sources/YcodeSDK/Host/SDKInstaller.swift` (+36: bundled-fallback final-decision comment + `bundledFallbackStatus()`)
- `ycode/Sources/YcodeSDK/Host/ServiceAdapters/Build/SDKBuildService.swift` (+27: `schemeDiscovery` injection + scheme resolution in `run`, deviation comment updated)
- `ycode/Tests/YcodeSDKTests/SDKInstallerTests.swift` (+18: `testBundledFallbackIsAbsentWithReason`)

Not edited (per task constraints): `ycode/Package.swift`, the
ledger (`ledgers/MIGRATION_FEATURE_PARITY.md`), `specs/ide/sdk-platform.md`,
SwiftCode-New, Legacy (read-only).

Ledger rows this slice completes (coordinator to mark):
`SwiftCode/Backend/Assist/AlternativeKeyManager.swift` (NOT STARTED),
`SwiftCode/Services/AntigravitySDKModelFetcher.swift` (NOT STARTED),
`SwiftCode/Backend/Assist/Tools/AssistXcodeProjectResolver.swift`
(NOT STARTED — scheme half only; `locate(relativePath:)` and
pbxproj introspection belong to the MCP project tools),
`SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift`
(IMPLEMENTED with a PARTIAL note — the five direct-provider legs
are now ported; custom/local/cloud legs remain with the host),
`SwiftCode/Backend/Assist/AssistModelRouter.swift` (IMPLEMENTED
with a PARTIAL note — `buildSDKConfiguration` /
`selectModelForSDK`, Gemini key rotation and the Antigravity
catalog are now ported).
`SwiftCode/SDK/Host/SDKInstaller.swift` was already IMPLEMENTED;
this slice adds the final bundled-fallback decision to it.

## Evidence

- Scheme discovery: Legacy `AssistXcodeProjectResolver.swift`
  (read live — `locate`, `resolveScheme`, `firstListedScheme`,
  `xcodebuild -list -json`); Ycode `Scheme.discover`
  (`ycode/Sources/YcodeWorkspace/Scheme.swift`), `Container.schemes`
  (`YcodeXcodebuild/Containers.swift`), `specs/ide/schemes.md`
  (shared vs user scheme file locations). Evidence level 2
  (file formats) + Legacy source (Dylan's own code).
- Model discovery endpoints: Legacy
  `AssistModelDiscoveryService.swift` (read live — all five
  legs, headers, filters, priorities); Anthropic + Mistral
  endpoints additionally confirmed by public web search
  2026-11-06 (Anthropic `GET /v1/models` with `x-api-key` +
  `anthropic-version: 2023-06-01`; Mistral `GET /v1/models`).
  Evidence level 1 (public docs) + Legacy source.
- Antigravity catalog: Legacy
  `AntigravitySDKModelFetcher.swift` (read live — seed models,
  `agy` candidates, parser, derive helpers) + Legacy
  `AssistModelRouter.swift` (`sdkDefaultModelIDs`,
  `createSyntheticSDKModel`). Evidence level 1 (Dylan's own code).
- Key rotation: Legacy `AlternativeKeyManager.swift` (read live
  — import, selection, cooldown, failure counting) + Legacy
  `AssistModelRouter.swift` rotation branch. Evidence level 1.
- SDK configuration: Legacy `AssistModelRouter.swift`
  (`buildSDKConfiguration`, `selectModelForSDK`) + Legacy
  `GoogleCloudSDKConfiguration.swift` (field list). Evidence
  level 1.
- Installer fallback: `sdk/scripts/package-sdk.sh` (read live —
  packages the assembled SDK, not the npm tarball) +
  `npm pack --dry-run` in `sdk/package` (run live 2026-11-06:
  `@swiftcode/sdk` 1.0.0, 52.8 kB, 29 files, shasum
  `1a1c24f569db8532ea9a839b27ecea1694c8acfa`; no file written).
  Evidence level 1 (own build output).
- No Swift toolchain in this environment: `swift build` /
  `swift test` not run; static checks only (§26.4.4.9).

### 26.5 Coordinator reconciliation

- **Package.swift wiring (Slice C):** applied by the coordinator — `"YcodeSDK"` on `YcodeUI`, `"YcodeAssistant"` on `YcodeSDKTests`, `"YcodeSDK"` on `YcodeUITests`. No new target.
- **knownToolIDs host wiring (Slice B):** applied by the coordinator — `CodingAssistantModel.mcpToolIDsProvider` (YcodeIDECore, injectable, nil by default) is set by the macOS shell to the live catalogue (`Set(mcpHost.server.tools.map(\.name))` plus `MCPServer.toolAliases` keys, lazily — creating the host installs all 433 tools, so it happens only on a turn that needs the catalogue) and injected into `MetaAssistProvider.knownToolIDs` in `send()` before the agent-mode attachment, so it survives `attaching(_:)`. The Linux shell (`YcodeIDEShell`) has no YcodeMCP dependency and leaves it unset — names record unmapped there, never claimed. The IDE model's agent-mode activity line is qualified for `.metaAssist` (the Muse host runs its own tools; Ycode's tools are named, not executed, and its file edits are not reviewed as proposals).
- **Scan fix:** the 2 `scan-public` findings Slice A flagged (home-folder fixture paths in `GoogleADCAndAntigravityTests.swift`, pre-existing at `d7cf1872`) were fixed by the coordinator — fixture home changed to `/Users/user/` (same pattern as Wave 15). Scan is 0 findings.
- **No slice conflicts:** `AssistantSettings.swift` carries both new fields (`metaReasoningEffort` from Slice B, `alternativeKeysEnabled` from Slice D) with matching decode + provider wiring; all other slice files are disjoint.
- **Still open (Wave 17):** slash-command host effects (`/effort` / `/model` / `/clear` / `/login` — the manager returns effects, the host must apply them); starting the other-models proxy when other-model mode is on; `executeTool` attachment (needs a grant-enforcing tool runner — a YcodeMCP seam and caller identity in the MCP approval gate); the 7 honestly-unavailable view windows (separate subsystems, not seam gaps); a turn timeout for `executeTurn` (Legacy waited indefinitely too).

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
- **4** — The 32-scope / 34-capability counts (§4, §13.1): consistent
  across the Swift host table, the TS list, the validator's
  `CAPABILITY_IDS`, and the snippet store.
- **3** — The `SDKAssistApplication` secret-storage flag (§5, corrected in
  Wave 16 §26.1.3 — the flag's premise was wrong; Legacy stored the key
  ID, never the secret) and the
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

## Wave 15 evidence (§23–§25)

- **5** — Router selection/ranking/eligibility/failure/quarantine/
  failover rules, the name-based specification branches and
  context windows, the free-only policy, the `opencode:` /
  `hermes:` / `swiftcode-cloud:` identifier schemes, the
  OpenCode configuration + agent definition, the routing
  strategy names and defaults, and the Meta provider's
  identity, fallback catalog, and CLI/credential gating: read
  verbatim from Legacy source in this pass (`AssistModels.swift`,
  `AssistProviderConfiguration.swift`, `AssistModelRouter.swift`,
  `AgentModelAdapter.swift`, `HermesProvider.swift`,
  `SCCloudModel.swift`, `MetaAssistProvider.swift`,
  `MuseCodeCLIHelper.swift`, `AppSettings.swift`) and verified
  against the ported code.
- **5** — SDKCloud contracts + adapter already ported in Wave
  14: verified live in `ycode/Sources/YcodeSDK/` (contracts +
  adapter delegating to `SCCloudProvider`); no file re-ported.
- **3** — The AFM context-window disagreement (adapter 8,192 vs
  router synthetic 16,000): both values read from Legacy source
  in this pass; which is real is unestablished, needs a Mac check.
- **5** — Grant-store behaviour (tombstones, 30-day prune,
  `capabilities:request` issuance gate), security-service
  per-app operations and envelope shape, Assist application
  field rules and approval flow, the concrete example manifest
  identity, the managed-build handle shape, and the Studio
  form/view structure: read verbatim from Legacy source in this
  pass (`SDKGrantStore.swift`, `SDKSecurityService.swift`,
  `SDKAssistApplication.swift`, `SDKAssistApplicationTests.swift`,
  `SDKAssistEnforcementTests.swift`, `SDKExampleManager.swift`,
  `SDKCodeBuildRunner.swift`, `AssistAccessFormView.swift`,
  `SDKSecurityManagerView.swift`, `SDKGrantManagerView.swift`) and
  verified against the ported code.
- **5** — Canvas verdict: the three missing pieces
  (no lightweight `WorkspaceSession` for a plain directory root,
  no `EditorDocument` bridge from `SDKCodeDocument`, no
  hosted-controller lifecycle in `WorkspaceShellModel`) verified
  live against the destination's `ycode-ide` code in this pass.
- **1** — Everything in §25 (Slice B) that depends on compilation:
  `swift build` / `swift test` were never run in this environment
  (no Swift toolchain). Mac build/test pending on Dylan's Mac.

## Wave 16 evidence (§26)

- **5** — `validate.mjs` vocabulary decision (§26.1.1): destination + Legacy
  schema enums identical 32-entry sets, Legacy's `validate.mjs` identical
  32-entry mirror, `SDKCapabilityID` 34 cases in both repos, the 8 excluded
  ids' non-manifest status from Legacy's registry (`grantableInCurrentRelease
  == false` for the `assist.*` ids; the 5 `security.*` method ids enforced
  under the single `use.Security` grant), and the manifest survey (only
  `source-control.read`, `build.execute`, `project.read`, `workspace.read`,
  `credentials.use`, `network.request` appear) — all read live from both
  repos; node suite 115/115 run here.
- **5** — Distribution measurement (§26.1.2): Legacy `Distribution/SwiftCodeSDK/`
  = 201,299,944 bytes / 2,478 files / 575,450 lines; `populate-distribution.py`
  filler ~91.6 MB; the other `Scripts/*.py` files generate fake benchmarks/guides
  to hit the 200 MB gates; the BSD-only `stat -f '%z'` defect reproduced live
  on GNU stat and fixed; smoke script 8/8 run here.
- **5** — Key-ID-only correction (§26.1.3): Legacy's flat `SDKAssistApplication`
  stores `apiKeyID: UUID` and its submit looks the key up by ID — read live
  from Legacy source, contradicting the Wave 14 spec premise.
- **5** — MSP wire protocol, turn execution, lifecycle numbers, 36 slash
  commands, other-models proxy (§26.2): read verbatim from Legacy source
  (`MuseCodeMSPBridge`, `MetaAssistLifecycleManager`,
  `MetaSlashCommandManager`, `MuseOtherModelsBridge`, turn executor);
  `normalizeToolName` rules verbatim, registry lookup re-pointed at the
  injected MCP catalogue.
- **5** — The 12 view IDs and opener styles (§26.3): read verbatim from
  Legacy's `SDKViewOpenerBuiltIns` (4 window managers, 5 notification
  bridges, 3 sibling openers); every Ycode surface cited read verbatim from
  destination source; the Assist backend boundary and rejected candidates
  from Legacy's `SDKAssistService` header.
- **5** — Scheme discovery, model-discovery endpoints/filters/priorities,
  Antigravity seed models + `agy models` behaviour, `AlternativeKeyManager`
  rules, SDK session-configuration shape (§26.4): read verbatim from Legacy
  source; Anthropic and Mistral list endpoints confirmed by web search
  2026-11-06; `npm pack --dry-run` for the installer-fallback decision run
  live (52.8 kB, 29 files, no file written).
- **1** — Everything in §26 that depends on compilation: `swift build` /
  `swift test` were never run in this environment (no Swift toolchain). Mac
  build/test pending on Dylan's Mac, including the `Package.swift` wiring,
  the `mcpToolIDsProvider` injection, and all new test files.
