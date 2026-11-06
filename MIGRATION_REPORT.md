# Migration report — SwiftCode-Legacy → SwiftCode-Mac

Status: **in progress**. This report is updated as work proceeds. It records
what was retrieved, what was migrated, what was verified, and what remains.
It does not claim completion that has not been demonstrated.

## 1. Source of truth

| Item | Value |
|---|---|
| Legacy repository | `dylans2010/SwiftCode-Legacy` |
| Default branch | `main` |
| Source commit | `d51a8f0df1e60aa3b5065fed6ab30c9ba5e6d8ef` |
| Commit date | 2026-10-31T07:54:07Z |
| Tracked blobs | 11,838 |
| Trees (directories) | 1,706 |
| Total bytes | 486,413,304 |

The complete repository was retrieved through the GitHub REST API by
`scripts/fetch_legacy.py` in the external migration workspace
(`~/SwiftCode-Legacy-Migration`, outside both repositories). The script
discovers the default branch, records the commit SHA, walks the recursive Git
tree (expanding truncated subtrees), downloads every blob through GitHub's raw
endpoint (Contents API fallback, LFS media host for pointers), retries
transient failures, and records a SHA-256 per file. Result: **11,838 files,
0 retrieval failures**. The machine-readable manifest is
`manifests/legacy-source-manifest.json`; the inventory is
`manifests/legacy-inventory.{json,tsv}`.

The migration workspace is temporary infrastructure and is **not** part of
either repository.

## 2. Destination

The destination is the Swift package in `swiftcode/` (plus `frameworks/`,
`composer/`, `packaging/`). It is a SwiftPM workspace, not an `.xcodeproj`
project; the Xcode-project requirements in the migration brief are satisfied
by the package manifest and the `swiftcode-ide` / `SwiftCodeApp` products.

## 3. Parity ledger

`MIGRATION_FEATURE_PARITY.md` is the per-file ledger (11,832 rows). Its
disposition counts are:

| Disposition | Rows |
|---|---|
| EXTERNAL_OR_UNAVAILABLE | 5,127 |
| GENERATED_REPRODUCIBLY | 2,484 |
| MIGRATE_AND_ADAPT | 2,113 |
| PRESERVE_LICENSE_OR_ATTRIBUTION | 820 |
| RESOURCE_MIGRATION | 715 |
| REVIEW_REQUIRED | 522 |
| TEST_MIGRATION | 34 |
| PROJECT_CONFIGURATION_MIGRATION | 10 |
| OBSOLETE_WITH_EVIDENCE | 7 |

Status counts before this session: 2,409 IMPLEMENTED, 492 SUPERSEDED,
8,931 NOT STARTED, 0 VERIFIED.

## 4. Work completed in this session

### 4.1 Build restoration (macOS, Xcode 27.3, Swift 6.4.2)

The destination did not compile. The following real defects were found and
fixed (all are source-level, no behaviour was removed):

- `swiftcode/Package.swift`: the local StoreKit package identity is `storekit`
  (directory name), but product references used `swiftcode-storekit`; the
  manifest could not resolve. Fixed to `storekit`.
- `SwiftCodeSubprocess/BinaryManager.swift`: dangling `#endif` (syntax error).
- `SwiftCodeGitHub`: duplicate `GitHubRelease` / `GitHubReleaseAsset` from two
  migration waves; consolidated into one model (keeping Legacy's `assets`).
- `SwiftCodePaywall/PaywallDebugViews.swift`: `Section("…") { } footer:` is not
  a valid SwiftUI overload; rewritten to `header:`/`footer:`.
- `SwiftCodeDeviceModel/DeviceConnectProcessRunner.swift`: non-Sendable
  closure captured by a `@Sendable` termination handler; boxed the pipe handles.
- `SwiftCodeAssistant`: duplicate `OpenCodeModelID` / `HermesModelID`;
  `Self` in default arguments; `try?` optional flattening; static-member calls;
  `withTimeout` missing `Sendable`; `Task.sleep` label.
- `SwiftCodeExtensions`: `NSLock` used across `await`; `@MainActor` static
  command registry called from a nonisolated closure; missing
  `ExtensionCapability.riskLevel`/`isGrantable`; designated initializer
  delegating with `self.init`.
- `SwiftCodeGoogleAuth`: `UInt8.random(in: .min... .max)`; `NSObject`
  inheritance for `ASWebAuthenticationPresentationContextProviding`;
  `try?` optional flattening; static `formBody` call.
- `SwiftCodeCloud`: `@MainActor` static key read from a nonisolated actor init.
- `SwiftCodeDarwinKernel`: same `UInt8.random` range defect.
- `SwiftCodeSDK`: missing `Equatable` on `SDKBuildDiagnostic`, `SDKError`,
  `SDKSecurityStoredValue`; actor conformance to a synchronous protocol
  requirement (`stream` made `async`); `any Error` shadowing; `await` in a
  synchronous function; region-isolation capture in `verify`.
- `SwiftCodeIDECore`: stray `count: 57` in a literal; duplicate `StackFrame`
  (IDECore vs SwiftCodeDebug) shadowing the DAP model; duplicate
  `FileTemplate` (enum vs struct); duplicate `DebugSession`/`DebugVariable`;
  missing `import SwiftCodeDebug` / `import SwiftCodeAssistant`; optional
  `self` member access; mutating-async call on an actor-isolated property;
  non-`@Sendable` template closure; non-public `id` on a public `Identifiable`.
- `SwiftCodeXcodebuild`: `AlertSoundPlayer` (a UI type) referenced from the
  build layer; replaced with a one-way `BuildAlertSoundHook` that
  `SwiftCodeUI` installs at launch, preserving the sound behaviour.

### 4.2 Rebranding

Genuine branding remnants were fixed: the copyright line in
`ProductIdentity.swift` and `packaging/macos/Info.plist.in`, the WeatherKit
fixture attribution, and the Flatpak metainfo developer name. The stable
Flatpak application ID `io.github.MarcoDotIO.Ycode` is retained deliberately
(changing it would break existing installs and updates); see
`REBRANDING_AUDIT.md`.

## 5. Remaining work (honest)

The reconciliation of the 285 `MIGRATE_AND_ADAPT` / `NOT STARTED` rows
(`reports/ma-reconciliation.md` in the workspace) found:

- 9 already present under a different destination name,
- 28 partially present,
- **248 genuinely missing** (concentrated in the Legacy Assist
  `Subagents`/`Frameworks`/`Reverse`/`Google Cloud SDK` families, plus
  `CodexBridgeManager`, `GitHubService`, and a few build/UI files).

These are real, unimplemented capabilities. They are **not** marked VERIFIED.
The ledger still records them as NOT STARTED. Closing them is the next body of
work; each must be ported with its real behaviour, registered, reachable, and
tested before its status changes.

## 6. Verification

See `FINAL_VERIFICATION_REPORT.md` for the current build/test evidence. A
feature is only marked VERIFIED when it compiles, is reachable, and its
behaviour is exercised.
