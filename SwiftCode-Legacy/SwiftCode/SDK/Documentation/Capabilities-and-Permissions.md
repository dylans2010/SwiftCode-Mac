# Capabilities and Permissions

**Status:** Phase 2 contract, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §8 · **ADR:** `SDK-Architecture.md` §§5, 7, 9, 11

## The capability registry (fixed for Phase 1+)

`SDKCapabilityID` (`Contracts/Capability/SDKCapability.swift`) is a fixed
registry. Raw values are wire-stable and used in manifests, grant records, and
IPC messages — they are never renamed. Additive cases require a minor SDK
version bump and a `Compatibility.md` entry. `SDKCapabilityRegistry.info(for:)`
uses an exhaustive switch, so adding an ID without its user-facing info fails
to compile.

| ID | Title | Risk | What it allows / does not allow |
|---|---|---|---|
| `project.read` | Project metadata | low | Safe metadata about the active project. Does NOT grant file contents or mutation |
| `workspace.read` | Workspace file reading | medium | Read files inside the approved workspace scope. Does NOT grant access outside the workspace |
| `workspace.write` | Workspace file writing | high | Create/modify files via the host's constrained file API. Does NOT grant arbitrary filesystem access |
| `source-control.read` | Source control reading | low | Status, diffs, branch, approved history. Strictly read-only — never stage/commit/push |
| `source-control.write` | Source control changes | high | Only host-supported source-control mutations. Does NOT grant arbitrary Git commands |
| `build.execute` | Build execution | high | Builds through SwiftCode's managed build service. Does NOT grant arbitrary shell/process execution |
| `task.execute` | Host task execution | high | Only approved host task types. Does NOT grant general process execution |
| `network.request` | Network requests | high | Constrained by host policy (destinations, limits). Does NOT grant arbitrary sockets or credential theft |
| `ui.contribute` | UI contributions | medium | Register host-rendered contributions (commands). Does NOT grant native code injection |
| `credentials.use` | Credential use | high | Narrowly scoped, host-mediated credential use. The extension never sees the raw secret |
| `assist.invoke` | Assist invocation | restricted | **Never grantable in this release.** Any request → typed `ASSIST_DENIED` + audit event |
| `db.ExploreView` | Database Explorer | medium | Open the Database Explorer window for project databases. Does NOT grant arbitrary SQL outside the explorer or direct database-connection access |
| `ci.VisualWF` | CI / visual workflow | medium | Open the CI / visual workflow views. Does NOT grant triggering pipeline runs or editing workflow definitions |
| `sandbox.view` | Virtualization console | high | Open the Virtualization console and view VM state. Does NOT grant VM lifecycle actions outside the console's own controls |
| `use.SwiftCodeModel` | SwiftCode Cloud Model | high | Invoke the SwiftCode Cloud Model through the host under host-enforced quota. Does NOT grant direct model-endpoint access, quota bypass, or use of other cloud models |
| `terminal.sandbox` | Sandboxed command execution | high | Run sandboxed shell commands through host-mediated execution — NOT a view. Does NOT grant a terminal surface, unsandboxed shell access, or files outside the sandbox |
| `simulator.view` | Simulator workspace | medium | Open the Simulator workspace. Does NOT grant creating, deleting, or retyping simulators outside the workspace |
| `preview.live` | Live SwiftUI preview | medium | Render live SwiftUI previews. Does NOT grant editing source files through previews or unrestricted build execution beyond preview compilation |
| `uibuilder.open` | Visual UI Builder | medium | Open the Visual UI Builder. Does NOT grant applying UI changes to the project outside the builder's own flow |
| `symbols.browse` | SF Symbol picker | low | Browse and pick SF Symbols. Does NOT grant any system modification, network access, or file access |
| `docs.search` | Documentation browser | low | Search and read documentation. Does NOT grant network access beyond the doc browser or any file mutation |
| `dictionary.open` | Coding dictionary | low | Open the coding dictionary reference. Does NOT grant network access beyond the dictionary or any project modification |
| `deviceconnect.open` | Device Connect | medium | Open the Device Connect surface for paired devices. Does NOT grant device pairing authorization or destructive device operations outside the console's own controls |

`grantableInCurrentRelease` is `true` for all 22 except `assist.invoke`.
Risk tier drives the approval UX (low-risk capabilities default on in the
approval sheet; medium/high default off) and the Developer API Key scope
requirements.

## Two ID naming conventions

The registry carries two historical conventions (documented in
`SDKCapability.swift`'s enum-header note; both spellings are valid,
**case-sensitive wire IDs** — match them verbatim, never normalize or
re-case them):

- **Phase 1 IDs:** kebab-case `domain.action` (e.g. `"source-control.read"`).
- **Platform-capability IDs:** `<area>.<View>` camel/Pascal form (e.g.
  `"db.ExploreView"`), used by the SDK 1.2.0 platform capabilities.

## Gaps, not omissions

- ~~`deployConsole.view` does **not** exist. There is no deployment-console
  surface anywhere in the codebase, so no capability ID was minted for one.
  Requesting it is an unknown capability, not a pending feature.~~
  **Correction (2026-10-12):** the audit was wrong — `DeploymentsView`
  (`SwiftCode/Views/Deployments/DeploymentsView.swift`) is real, so
  `deployConsole.view` now exists and opens it. The struck paragraph above
  is kept for history.

## Grant records

`SDKGrantRecord` (`Host/CapabilityBroker/Grants/SDKGrantStore.swift`) is the
persisted permission grant, per spec §8.2. Fields: record UUID, extension ID,
SHA-256 `packageDigest` of the installed package **at grant time**, package
version, capability ID, scope (project root path), grant timestamp, granting
principal (`grantedBy`, e.g. `"user-approval"`), optional `expiresAt`, the
`revokedAt` tombstone, `policyVersion` (currently 1), and correlation metadata.

Storage: host-owned, actor-guarded JSON array at
`~/Library/Application Support/SwiftCode/SDKGrants.json`, mode `0600`,
written atomically (temp file + rename) with sorted keys. Grant records carry
no secrets — only identities, digests, scopes, and timestamps — so they are
NOT stored via `KeychainService` (whose UserDefaults base64 fallback is a
secret-leak vector). A corrupt store file is moved aside to
`SDKGrants.json.corrupt-<timestamp>` and the store starts empty — never a
crash, and a failed load degrades to "no grants" (deny-by-default), never
"all grants".

A grant is **active** only when `revokedAt == nil` and `expiresAt` is nil or in
the future.

## The approval flow

A manifest is a request: every capability the extension declares must still be
approved by the user. `SDKApprovalView`
(`Host/CapabilityBroker/Approval/SDKApprovalView.swift`) is the approval sheet:

- Shows the extension identity and one row per **requested** capability with
  plain-language effects (driven by the registry's `description`,
  `grantsSummary`, `doesNotGrant` fields). The manifest `reason` is the
  justification shown for each row.
- Toggles default **ON only for low-risk capabilities** and OFF for everything
  else. There is no "allow everything" default. Restricted capabilities cannot
  be toggled on and are labeled "Not available in this release". Per spec
  §8.3, the host never prompts for capabilities the extension did not request.
- The user may approve a **subset**. The broker stores only the explicitly
  approved set via `SDKGrantStore.recordGrants(_:)`; denial returns a typed
  permission error.
- `permissionRequested`, `permissionGranted`, and `permissionDenied` events are
  recorded in the audit log.

The broker wires the view's `onApprove`/`onDeny` callbacks to the grant store
and the activation path. Approval UI lives in SwiftCode Studio's Extensions
surface (`SDK/Studio/`), where `SDKGrantManagerView` also lets the user inspect
and revoke an extension's grants — including revoked tombstones, so the view
doubles as an audit trail.

## The broker choke point

`SDKCapabilityBroker.authorize(_:for:)` is **the single authorization choke
point** for the SDK. Every privileged host operation calls it on **every**
call, before touching the underlying service — the adapters
(`SDKSourceControlAdapter.getStatus`/`getDiff` authorize `.sourceControlRead`;
`SDKBuildService.run` authorizes `.buildExecute`). Enforcement order, with no
short-circuits:

1. `assist.invoke` → always deny (`ASSIST_DENIED` + audit), before any
   grant-store lookup, so no grant, scope, or identity state can ever satisfy
   it.
2. Active-grant lookup in `SDKGrantStore`, classified precisely: no record →
   `PERMISSION_DENIED`; newest record revoked → `PERMISSION_REVOKED`; newest
   record expired → `PERMISSION_EXPIRED`; active but project-filtered →
   `PERMISSION_DENIED` ("outside the approved project").
3. Scope check: normalized grant project root vs. normalized caller root.
   Mismatch → `PERMISSION_DENIED`.
4. Package-digest binding: `grant.packageDigest != caller.packageDigest` →
   `PERMISSION_DENIED` ("extension was updated; re-approval required").
   Reinstalls and content changes never silently inherit grants (spec §8.7).

Success returns `Void` — authorization is a gate, not a token. Nothing is
returned that the extension could cache or replay; callers re-authorize on
every privileged request.

The dispatcher deliberately does **not** pre-authorize (a second gate would be
a second place for policy to drift): the adapters are the authorization choke
point. Documented exceptions: `commands.register` is authorized at the
dispatcher (`.uiContribute`) because the registry is a plain store;
`build.wait`/`build.cancel` rely on handle possession (unguessable UUID
handles, never exposed); `commands.unregister` is ownership-enforced by the
registry; `log.*` is the extension's own diagnostics channel (not a privileged
host operation).

`SDKCallerIdentity` (extension ID + package digest + project root) is built
**only by host-owned code** from the host-created runtime session. UI hiding,
manifest claims, and TypeScript type signatures are not security controls; no
identity field is ever read from an IPC payload.

## Revocation semantics

- `revoke(extensionID:capability:)` / `revokeAll(for:)` stamp `revokedAt` and
  **keep the record** — revocation is a tombstone, never a delete, so it stays
  auditable. Both are idempotent.
- Revocation takes effect at the broker's **next check** — there is no cached
  verdict to outlive it.
- `pruneExpired()` removes only records expired for more than 30 days;
  revoked tombstones are kept regardless of age (audit-relevant).
- An updated extension (changed package digest) does not inherit old grants:
  the broker's digest binding denies with `PERMISSION_DENIED` until the user
  re-approves.

## Audit events

`SDKAuditLog` (`Assist/Audit/SDKAuditLog.swift`) is a durable, append-only,
tamper-resistant host security log: one JSON object per line (sorted keys,
ISO-8601 dates) in `~/Library/Application Support/SwiftCode/SDKAudit.jsonl`,
directory mode `0700`, file mode `0600` re-enforced on every open. Extensions
cannot read or modify it (the TypeScript SDK has no binding; the API surface
is append and tail-read only — no rewrite, truncate, or delete). The log is
never rotated or truncated by the type; retention is a host-administration
decision. Recording is best-effort and never throws outward — a logging
failure is emitted via os_log (`com.swiftcode.sdk` / `sdk-audit`), never
confused with "nothing happened". Detail fields must never contain secrets.

Fixed event taxonomy (`SDKAuditEventType` — additive cases require a minor SDK
bump):

- Permissions: `permissionRequested`, `permissionGranted`,
  `permissionDenied`, `permissionRevoked`
- Assist gate: `assistDenied` (fires on every denied attempt, broker and IPC)
- Developer API keys: `apiKeyCreated`, `apiKeyRevoked`,
  `apiKeyScopeFailure`, `apiKeyAuthFailure` (a rotation is recorded as a
  created+revoked pair sharing one correlation ID)
- Extension lifecycle: `extensionInstalled`, `extensionUpdated`,
  `extensionDisabled`, `extensionUninstalled`
- Runtime: `runtimeTerminated`

Studio's Logs viewer (`SDKStudioLogsView`) has an audit-log pane reading the
tail of this file.

## The Developer API key system

`SDKAPIKeyStore` (actor, `Host/APIKeys/`) is the host-side authority for
developer API keys (spec §8.2.1, ADR §11). Keys are created in
Studio → Settings → Developer API Keys, and required for app
creation/publishing and privileged capability access.

- **Format:** `sc_dev_live_…` / `sc_dev_test_…` secrets are
  `<prefix>_<base64url(payload)>.<base64url(signature)>` where
  `payload = {"id", "prefix", "iat"}` (canonical JSON, sorted keys) and the
  signature is `HMAC-SHA256(payloadB64, deviceKey)`.
- **The secret is never stored.** Verification is HMAC against a 32-byte
  device key (`SecRandomCopyBytes`, Keychain-backed at `sdk.device-key`) —
  there is no secret hash in storage to steal. Only key **metadata**
  (`SDKAPIKey`: id, prefix, label, scopes, timestamps) is persisted as JSON in
  `SDKKeychain` under `sdk.apikey.<uuid>`. The secret is returned from
  `createKey` exactly once and is toxic: never logged, never interpolated into
  an `SDKError`, never written to disk.
- **`verify(secret:)` is the authorization boundary.** Every call:
  HMAC-verifies the secret, loads fresh metadata, rejects revoked keys, and
  updates `lastUsedAt`. Unknown/malformed/forged secrets all map to one
  indistinguishable `API_KEY_INVALID`; revoked keys → `API_KEY_REVOKED`.
  Keychain failures fail closed (`SERVICE_UNAVAILABLE`).
- **Scopes:** `apps:create` (required to create/publish apps),
  `apps:publish` (publish/release), `capabilities:request` (privileged
  capabilities — network, custom builds, credential use, platform
  publishing). `requireScope(_:for:)` throws `API_KEY_SCOPE_INSUFFICIENT`.
  Keys support an optional `expiresAt` (nil = never expires); revocation
  remains the primary lifecycle control, and both revocation and expiry
  take effect immediately — the dispatcher re-verifies the session's key
  on every request.
- **Storage (`SDKKeychain`):** purpose-built wrapper — secrets live only in
  the Keychain (`kSecClassGenericPassword`, service `com.swiftcode.sdk`),
  with **no UserDefaults fallback** (the app's general `KeychainService`
  duplicates secrets base64-encoded into UserDefaults, which is why SDK keys
  never go through it), **no in-memory cache** (every read hits the Keychain),
  accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no iCloud
  sync. Keychain failures surface as `SERVICE_UNAVAILABLE`, never by
  degrading to a weaker store.
- **Delivery (secret handoff):** the secret is shown exactly once at
  creation (Studio) and never persisted by the host. To present it, the
  developer exports `SWIFTCODE_API_KEY` in the host process's environment;
  the host coordinator binds it to the extension session
  (`SDKRuntimeSessionInfo.presentedAPIKey`, in-memory only) via
  `SDKAPIKeySessionAuth.presentedKeyFromEnvironment()`. The extension
  process never sees the secret and no file-based config store exists by
  design. Lost secret = revoke + generate a new key.
- **Consumption:** `SDKIPCDispatcher` verifies the session's presented key
  on every request (fail closed: `API_KEY_INVALID` / `API_KEY_REVOKED` /
  `API_KEY_RATE_LIMITED`), attaches the verified metadata to
  `SDKCallerIdentity.apiKey`, and the broker enforces `capabilities:request`
  for privileged capabilities (high-risk: workspace/source-control writes,
  builds, task execution, network, credential use) — at both grant
  issuance (`SDKGrantStore.recordGrants(authorizedByAPIKey:)`) and
  authorization (`SDKCapabilityBroker.authorize`), each emitting
  `apiKeyScopeFailure` on denial. Sessions presenting no key authorize
  purely through user grants, as before.
- **Brute-force protection:** `verify(secret:)` is in-memory rate limited —
  at most 10 failed verifications per 60 seconds per presented key ID, then
  a 5-minute lockout (`API_KEY_RATE_LIMITED`). Only invalid-secret failures
  count; success clears the bucket.
