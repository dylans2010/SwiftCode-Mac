# Compatibility

**Status:** Phase 1 contract, implemented · **Branch:** `feature/swiftcode-sdk` · **Date:** 2026-10-12
**Spec:** `Docs/Intro-to-SDK.md` §18 · **ADR:** `SDK-Architecture.md` §10

There are **five version concepts** in the SDK. They are deliberately not
interchangeable (spec §18): SDK package version, protocol version, and API
version are checked independently, and `manifestVersion` and the host floor
are checked on their own paths.

## The five version concepts

| # | Concept | Current value | Declared by | Governed by |
|---|---|---|---|---|
| 1 | **SDK package version** | `1.0.0` | Host (`SwiftCodeSDK.json` `sdkVersion`) | `SDKCompatibility.check` against the manifest's `sdk.versionRange` |
| 2 | **Manifest schema generation** | `manifestVersion` `1` | Extension (`swiftcode.json`) | `SDKManifestValidator` (and the JSON schema); new generations are new schema files |
| 3 | **Host/runtime IPC protocol version** | `1` | Extension (`sdk.protocolVersion`); host (`SwiftCodeSDK.json` `protocolVersion`) | Must match **exactly** — protocol versions are never range-negotiated |
| 4 | **Internal API version** | `2026.1` | Host (`SwiftCodeSDK.json` `apiVersion`) | Informational only: surfaced for diagnostics, **not** used in the compatibility decision |
| 5 | **Host floor** | extension-declared `runtime.minimumSwiftCodeVersion` (e.g. `"1.0.0"`); host-declared `minimumHostVersion` `"1.0.0"` | Extension + `SwiftCodeSDK.json` | Manifest well-formedness today; host-side comparison with the runtime driver (later phase) |

## `SwiftCodeSDK.json` — canonical version metadata

`SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json` is the canonical
host version metadata, managed by internal developers:

```json
{
  "sdkVersion": "1.0.0",
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
answers whether a named public API appears in `deprecatedAPIs` (empty in
1.0.0).

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
