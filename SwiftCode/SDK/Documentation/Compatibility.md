# Compatibility

**Status:** Phase 1 contract, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §18 · **ADR:** `SDK-Architecture.md` §10

> **Released:** the `use.Security` capability family (below) shipped with
> the 1.2.0 SDK package bump, per the registry's additive-case convention
> ("Additive cases require a minor SDK version bump and a
> `Compatibility.md` entry"). Nothing below renames, removes, or re-scopes
> any existing ID.

There are **five version concepts** in the SDK. They are deliberately not
interchangeable (spec §18): SDK package version, protocol version, and API
version are checked independently, and `manifestVersion` and the host floor
are checked on their own paths.

## The five version concepts

| # | Concept | Current value | Declared by | Governed by |
|---|---|---|---|---|
| 1 | **SDK package version** | `1.2.0` | Host (`SwiftCodeSDK.json` `sdkVersion`) | `SDKCompatibility.check` against the manifest's `sdk.versionRange` |
| 2 | **Manifest schema generation** | `manifestVersion` `1` | Extension (`swiftcode.json`) | `SDKManifestValidator` (and the JSON schema); new generations are new schema files |
| 3 | **Host/runtime IPC protocol version** | `1` | Extension (`sdk.protocolVersion`); host (`SwiftCodeSDK.json` `protocolVersion`) | Must match **exactly** — protocol versions are never range-negotiated |
| 4 | **Internal API version** | `2026.1` | Host (`SwiftCodeSDK.json` `apiVersion`) | Informational only: surfaced for diagnostics, **not** used in the compatibility decision |
| 5 | **Host floor** | extension-declared `runtime.minimumSwiftCodeVersion` (e.g. `"1.0.0"`); host-declared `minimumHostVersion` `"1.0.0"` | Extension + `SwiftCodeSDK.json` | Manifest well-formedness today; host-side comparison with the runtime driver (later phase) |

## `SwiftCodeSDK.json` — canonical version metadata

`SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json` is the canonical
host version metadata, managed by internal developers:

```json
{
  "sdkVersion": "1.2.0",
  "apiVersion": "2026.1",
  "minimumHostVersion": "1.0.0",
  "protocolVersion": 1,
  "releaseNotes": [ "Initial SwiftCode SDK 1.0.0 release.", ... ],
  "updateTimestamp": "2026-10-12T18:53:04Z",
  "deprecatedAPIs": []
}
```

The DEBUG-only `SDKConfigStore` (`#if DEBUG`, stripped from release builds)
loads it from the app bundle. User projects' SDK bindings sync from it on
launch: non-breaking updates propagate automatically; breaking updates
require an explicit Studio prompt (ADR §10). `SDKConfigStore.isDeprecated`
answers whether a named public API appears in `deprecatedAPIs` (empty since
1.0.0, still empty in 1.2.0).

## SDK 1.1.0 — additive release (2026-10-12)

Bumped per the capability-registry convention (`SDKCapability.swift`
enum-header note): additive registry cases require a minor version bump and
a `Compatibility.md` entry. **Nothing was renamed, removed, or
re-scoped** — a 1.0.0 extension runs unchanged against the 1.1.0 host.

- **12 new capability IDs:** `db.ExploreView`, `ci.VisualWF`,
  `sandbox.view`, `use.SwiftCodeModel`, `terminal.sandbox`,
  `simulator.view`, `preview.live`, `uibuilder.open`, `symbols.browse`,
  `docs.search`, `dictionary.open`, `deviceconnect.open`. The 11 original
  Phase 1 IDs are unchanged. New IDs use the `<area>.<View>` camel/Pascal
  convention; existing IDs are untouched.
- **New IPC routes:** `ui.openView`, `cloudModel.complete`,
  `terminalSandbox.run` (all added; no existing route changed or removed).
- **New TypeScript exports** (`@swiftcode/sdk`): the `ScopesIDLists.ts`
  module (`SCOPES_ID_LIST`, `SCOPES_BY_ID`, synced 1:1 with the host's
  `ScopesIDLists` table — drift fails
  `TypeScript/package/tests/scopes-sync.test.mjs`), the `snippets.ts`
  module (`SNIPPETS`), and the `UIAPI`, `CloudModelAPI`,
  `TerminalSandboxAPI` interfaces (all re-exported from `index.ts`).
  Protocol version stays `1`; the IPC wire format is unchanged.

## SDK 1.2.0 — additive release (2026-10-12)

Bumped per the capability-registry convention (`SDKCapability.swift`
enum-header note): additive registry cases require a minor version bump and
a `Compatibility.md` entry. **Nothing was renamed, removed, or
re-scoped** — a 1.1.0 extension runs unchanged against the 1.2.0 host.

- **New umbrella capability:** `use.Security` ("Use Security (Keychain)",
  high risk) — host-mediated Keychain secret storage and use. The
  extension never sees plaintext: secrets are entered by the user into the
  host's secure prompt (`SDKSensitiveValuePrompt` /
  `EnterSecuritySDKView`) and used only through host-performed operations.
- **Five granular method-scope IDs, pairing 1:1 with the new IPC methods:**
  `security.addValue`, `security.hasValue`, `security.listValueIDs`,
  `security.deleteValue`, `security.useValue`. These are **not separately
  grantable** (`grantableInCurrentRelease: false`): the user grants the
  single `use.Security` capability, and every `security.*` call authorizes
  **only** the umbrella at the broker before any Keychain touch (checking a
  non-grantable ID would deny every call). The granular IDs name the method
  scope in audit events, scope listings, and approval UX — they can never
  appear in a grant.
- **Two new view capability IDs:** `deployConsole.view` (the real
  Deployments console — Netlify / Vercel / GitHub Pages production
  deployments — via the toolbar-notification bridge) and
  `virtualization.view` (the virtualization console, via its sibling
  opener). Both are `kind: "view"` entries in the `ScopesIDLists` pair and
  both have real registered openers (the scopes-sync test enforces this).
- **`sandbox.view` re-targeted:** the built-in view opener for
  `sandbox.view` now bridges to the real `TerminalView` sheet (full
  interactive shell — local shells, SSH nodes, themes) instead of a
  sandboxed terminal surface. HIGH-RISK by nature: opening it gives the
  user a complete unsandboxed shell. The capability ID is unchanged, so
  existing manifests and grants keep working; only the opened surface
  changed.
- **New IPC routes:** `security.addValue`, `security.hasValue`,
  `security.listValueIDs`, `security.deleteValue`, `security.useValue`
  (all added; no existing route changed or removed).
- **New error code:** `USER_CANCELLED` — the user dismissed a
  host-presented prompt (e.g. the secure secret entry sheet); nothing was
  stored, changed, or sent. Flow: `SDKSensitiveValuePrompt` surfaces
  `CancellationError` → `SDKSecurityService.addValue` converts it to
  `SDKError(code: .userCancelled)` → the dispatcher encodes
  `"USER_CANCELLED"` in the error envelope.
- **Uninstall behavior:** uninstalling an extension wipes every Keychain
  item in its Security namespace (`SDKExtensionRegistry.removeInstallRecord`
  → `SDKSecurityService.deleteAllValues`), recorded as
  `securityValuesWipedOnUninstall`. Fail-closed: a Keychain failure aborts
  the uninstall.
- **New audit event types:** `securityValueAdded`, `securityValueUsed`,
  `securityValueDeleted`, `securityValuesWipedOnUninstall`,
  `securityPermissionDenied` — identifiers only, never secrets.
- **New TypeScript exports** (`@swiftcode/sdk`): the `security.ts` client
  (`createSecurityAPI`, `context.security`, the `security*` standalone
  helpers, all re-exported from `index.ts`) and the `SecurityAPI` family of
  types in `types.ts`. Protocol version stays `1`; the IPC wire format is
  unchanged.

## Negotiation rules

`SDKCompatibility.check(manifestProtocolVersion:sdkVersionRange:host:)`
(`Contracts/Protocol/SDKVersionNegotiation.swift`) is pure logic — no I/O,
no singletons — so it is directly testable:

1. **Protocol:** `manifestProtocolVersion` must **equal** the host's protocol
   version exactly (currently both `1`). No range semantics, no
   "compatible-with" — a difference is a hard failure.
2. **SDK range:** the manifest's `sdk.versionRange` uses npm-style
   semantics — `^` (compatible: `^1.2.3` := `>=1.2.3 <2.0.0`,
   with `0.x` narrowing: `^0.2.3` := `>=0.2.3 <0.3.0`, `^0.0.3` := `0.0.3`
   exactly), `~` (patch-compatible: `~1.2.3` := `>=1.2.3 <1.3.0`),
   `>=` (minimum), or an exact version. Prerelease/build suffixes are
   ignored for comparison. The host's SDK version (from `SwiftCodeSDK.json`)
   must satisfy the range.
3. **`apiVersion` is not part of the decision** — it is surfaced for
   diagnostics only.
4. **`manifestVersion`** is checked separately by `SDKManifestValidator`
   before compatibility is even considered (see below).
5. **`minimumSwiftCodeVersion`:** today the validator checks that the
   extension's declared floor is well-formed semver; the comparison against
   the actual running host version arrives with the runtime driver in a
   later phase. Until then, an extension can declare a floor the current host
   does not meet without a refusal at install time — document the floor
   honestly and treat it as a contract with the future driver.

The check is not yet wired into a runtime install/launch flow — the driver
arrives later. The manifest validator's whitelist
(exact/`^`/`~` matching 1.0.0, or `>=1.0.0 <2.0.0`) is the check that runs at
install time today.

## Deprecation policy

- The capability registry (`SDKCapabilityID`) and the error taxonomy
  (`SDKErrorCode`) are **fixed**: no renames, no removals. Additive cases
  require a minor SDK version bump and a `Compatibility.md` entry; the
  capability registry's exhaustive switch forces the user-facing info to be
  added with the ID.
- Wire raw values (`"project.read"`, `"PERMISSION_DENIED"`, …) never change.
- Manifest schema generations are additive by new file: `manifestVersion` 2
  means a new `swiftcode-extension-v1`-style schema document, never silent
  extra fields in v1 (`additionalProperties: false`).
- `deprecatedAPIs` in `SwiftCodeSDK.json` is the registry of deprecated
  public APIs (empty in 1.0.0); consumers check
  `SDKConfigStore.isDeprecated(api:in:)`.

## What happens on mismatch — exact error codes

| Condition | Error code | Where |
|---|---|---|
| IPC frame declares `protocolVersion != 1` | `IPC_PROTOCOL_MISMATCH` | dispatcher (and TS client on receive) |
| Manifest `sdk.protocolVersion != 1` | `IPC_PROTOCOL_MISMATCH` | `SDKCompatibility.check` (future driver path) |
| Manifest declares unsupported `manifestVersion` | `MANIFEST_UNSUPPORTED_VERSION` | `SDKManifestValidator` |
| Manifest `sdk.name != "@swiftcode/sdk"` | `INCOMPATIBLE_SDK_VERSION` | `SDKManifestValidator` |
| `sdk.versionRange` malformed | `MANIFEST_INVALID` | `SDKCompatibility.check` |
| Host SDK version does not satisfy `sdk.versionRange` | `INCOMPATIBLE_SDK_VERSION` | `SDKCompatibility.check` / validator whitelist |
| Host's own SDK version metadata malformed | `SERVICE_UNAVAILABLE` | `SDKCompatibility.check` |
| No Node.js runtime found | `RUNTIME_UNAVAILABLE` | `SDKNodeLauncher` |

Every error carries the stable code, a user-safe message, an actionable
suggestion, a correlation ID (`ERR-XXXXXX`), and structured diagnostics for
the developer log. On the IPC wire only `{ code, message, correlationId }`
crosses to the extension.
