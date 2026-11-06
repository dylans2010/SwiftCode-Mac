# Gap closure — miscellaneous

The miscellaneous family of the gap-closure wave: the pieces that did
not belong to any other slice — the StoreKit simulation session, the
SQLite Explorer follow-ups, the capability approval UI, the
Extensions v2 language-client adapter, the persistence stores, the
Canvas/demo-views verdicts, and the native `generate_xcodeproj`
generator.

## 1. StoreKit simulation over AppTestStore

`StoreKitSimulationSession` is rewritten over the repo's own
`StoreKitEngine` (`AppTestStore` / `StoreDevice`). Its public API is
identical, so `StoreKitEditorView` is untouched. Purchases, renewals,
Ask to Buy, refunds, expirations, and simulated errors are real
engine behaviour against the installed `.storekit` configuration.

New API:

- `installConfiguration(_:)` — installs the configuration into the
  engine's store and re-keys the store from the configuration's
  identifier. `StoreKitEditorModel` calls it after each simulation
  init and in `mutate`, so the editor's simulation always runs
  against the configuration being edited.
- `advanceSimulation()` — runs the engine's subscription scheduler up
  to the clock's now (renewals, grace and retry ends, expirations, in
  time order) and refreshes the published state.
- An optional injectable `clock` (a `ManualClock` in tests) moves
  subscription time.

Honest overlays, labelled in code:

- Offline mode is a local gate (the engine has no offline mode);
  purchases are refused before the store is touched while it is on.
- Family-sharing revocation is a session-level overlay (the engine
  has no such API); the records stay in the store, but the session
  shows them revoked and their entitlements inactive.
- Grace period and billing retry report the engine's real resulting
  state instead of relabelling it — the state only changes once a
  renewal actually fails.

Engine quirks are cleaned up (`declinedAskToBuyIsDelivered: false`,
`expireLeavesFailedTransaction: false`), not reference. The old
`storekit_transactions.json` / `storekit_entitlements.json` are no
longer read (favourites still use `storekit_favorites.json`).

Deliberately NOT over `SKTestSession`: it is a macOS-only `NSObject`
test facade that would shadow Apple's StoreKit if depended on.

## 2. SQLite Explorer follow-up — all 8 sections, whole

The model layer lives in `swiftcode/Sources/SwiftCodeIDECore/Model/
Database/` over the existing `SQLiteDatabase`, plus a generic AppKit
sections panel (`SQLiteExplorerSectionsController`: one panel, section
picker + detail text + per-section actions) wired into the explorer
window via a "Sections…" button; `runClicked` now records query
history.

- **Migrations.** The tracking table `_swiftcode_migrations` lives in
  the database itself — a deliberate deviation from Legacy's
  UserDefaults registry, which drifts when the file moves. Down SQL
  is stored so `rollbackLatest()` works from the database alone.
- **Backups.** Timestamped file copies with directory-scan listing —
  a deviation from Legacy's UserDefaults registry. Restore and prune
  included.
- **Import/export.** A real quoted-CSV parser — Legacy's
  `components(separatedBy: ",")` broke on quoted commas — plus
  CSV/JSON/SQL-dump export and type-inferring CSV/JSON import. Empty
  cells import as NULL; blobs export as base64 in JSON and `X'…'`
  hex in SQL.
- **Templates.** Legacy's 2 seeded templates verbatim, with
  provider-generic types mapped to SQLite types.
- **AI assistant.** Legacy's pure-LLM shape with a pluggable
  `llmProvider` closure; it throws honest `.noProvider` with no
  provider attached — never a canned answer — plus deterministic
  local schema analysis and `EXPLAIN QUERY PLAN` explanations,
  labelled local.
- **Performance.** Real PRAGMAs, `integrity_check`, `EXPLAIN QUERY
  PLAN`, unindexed-FK detection, VACUUM. Legacy's simulated
  CPU/memory values are dropped entirely.
- **Logs.** Legacy's `DatabaseHistoryService` port, same 3 seeded
  saved queries verbatim, keys renamed `com.swiftcode.database.*`.
- **Dashboard.** Every number is computed for real; health is a
  checklist (integrity, primary keys, foreign-key indexes), not
  Legacy's hardcoded `"3 Migrations"` / `"100/100"`.

Supabase/Postgres/MySQL are out of scope as planned (SQLite only).

## 3. Capability approval UI

`ExtensionPermissionApprovalCenter` (ask/answer queue via
continuation, one pending request at a time, a second request denied
rather than queued, a `hasPresenter` gate so headless runs deny
immediately instead of hanging) plus the SwiftUI
`ExtensionPermissionApprovalView` (mirrors `SDKApprovalView`;
ungrantable capabilities are shown, never offered) plus the
`promptHandler` wired in `ExtensionManager.init`. It never
auto-grants: the answer flows back through `PermissionManager.
request`, which grants only on an explicit approval.

Verified: `promptHandler` was never set anywhere before, in the
destination or in Legacy.

The AppKit presenter is `ExtensionsPanelViewController`: it sets
`hasPresenter = true`, observes
`pendingRequestDidChangeNotification`, and asks with an Allow/Deny
sheet on the panel's window. Closing the sheet without answering
denies (the center's `dismissPending` path).

## 4. Extensions v2 language-client adapter

`ExtV2LanguageClient` is a thin actor over `LSPClient` /
`ProcessTransport`, with Legacy's API shape (`ServerInfo`, `start` /
`shutdown` / `restart`, `didOpen` / `didChange` / `didClose`,
`completion -> [String]` labels, `hover -> String?`). There is no
second JSON-RPC stack. PATH resolution is done in-process (Legacy
shelled out to `/usr/bin/which`); a missing executable fails honestly
with `.executableNotFound` before any process starts. `start` runs
`initialize`, so a server that exits immediately (for example
`/usr/bin/false`) fails at start, not on the first completion.

Documented deviations: `languageId` is accepted but `LSPClient`
derives the language from the extension; diagnostics are not drained
here (`LanguageService` already consumes that stream).

## 5. Persistence stores

`ProjectRegistryStore` (actor, Legacy's `ProjectRegistry.json`
format, `ProjectRegistryEntry` + `ProjectKind` verbatim, under
Application Support `SwiftCode`) and `NewFileComment` (pure
`generateHeader` with Legacy's `{filename}` / `{projectname}` /
`{username}` / `{date}` placeholders, `M/d/yy`).

Decision recorded in code: **no new IDE SQLite layer** — Legacy had
none either (raw `sqlite3` in exactly 2 files; everything else
UserDefaults/JSON), so UserDefaults + JSON matches Legacy in kind.

`RecentProjects.note(_:)` records each open in the registry
(kind, last-opened time, source-control flag) in a `Task`; a registry
failure must never break Open Recent itself. The kind is derived
from the container: `.xcodeproj` / `.xcworkspace` → `.xcodeProject`,
a directory containing `Package.swift` → `.swiftPackage`, anything
else → `.folder`.

The `NewFileComment` call-site wiring is still open: the new-file
template flow should call `NewFileComment.generateHeader` — no call
site was identified in the owned set, so no patch is offered; the
pure function is ready for the template owner.

## 6. Canvas and the 28 Settings demo views — verified, no code

- **Canvas: honestly unavailable.** Still no seam: the closed
  `StructuredEditor` 4-case enum in `WorkspaceShellModel`, no
  VisualUIBuilder document/canvas model in the destination, two
  shells, and the SDK view host is window-only.
- **Demo views: DROP.** 26 of 28 are demo-only (32–69 lines, local
  `@State`, no persistence or backend, entry points of Legacy's
  hardcoded fake built-in extensions). The 2 exceptions
  (`CreateExtensionView`, `EditExtensionView`, 330/380 lines) are
  real management UI but still DROP — superseded by the SDK Studio
  manifest editor.

## 7. Native `generate_xcodeproj` generator

The `generate_xcodeproj` tool used to fail honestly without xcodegen.
It now uses SwiftCode's native generator
(`XcodeGenNativeGenerator` in `SwiftCodeMCP`): a YAML-subset parser,
a typed spec parser, and a PBXProj builder that mirrors the
destination's `IOSAppTemplate.makeProject` object layout, so the
generated project opens in Xcode like a real XcodeGen project.

- **Spec.** `name` (required), `options` (bundleIdPrefix,
  deploymentTarget, developmentLanguage, xcodeVersion,
  createIntermediateGroups), `settings` (base + per-config maps),
  `targets` (type, platform, sources, settings, dependencies, info
  path-or-properties, entitlements, configFiles, pre/post build
  scripts, scheme, transitivelyLinkDependencies, per-target
  deploymentTarget), `packages` (remote only), `schemes`, top-level
  and per-target `configFiles`.
- **Files, in commit order.** Generated `Info.plist` files first,
  then `<Name>.xcodeproj/project.pbxproj`,
  `project.xcworkspace/contents.xcworkspacedata` (reusing the
  host's self-workspace writer), then one `.xcscheme` per scheme in
  `xcshareddata/xcschemes/`.
- **Honest failures only.** Unknown keys that are organisation or
  metadata only land in `ignoredKeys`; build-changing unknowns fail
  honestly and name the key — unknown target type or platform,
  local packages (`path:`), Carthage dependencies, unknown source /
  dependency / script / scheme options, cross-reference failures
  (a target, package, or test target that does not exist), and an
  app target without a `bundleIdPrefix`. The tool error names the
  key and points at a manual xcodegen run as the only way to build
  that spec.
- **No Package.swift change.** The generator and the rewritten
  handler are `SwiftCodeMCP`-internal (the target already depends on
  `SwiftCodeProject` + `SwiftCodeIDECore`).

## 8. Password-reset completion UI

The Appwrite password-reset flow previously had no UI to complete
it: `handleOpenedURL` extracted `userId`/`secret` from the recovery
link and had nowhere to put them. `PasswordResetWindowController`
closes that gap: a window with new-password + confirm secure fields,
Reset (default key) / Cancel, an error label, and a success state.
It completes the reset through the Appwrite client
(`CloudAuthManager.shared.client.updateRecovery(userId:secret:
password:)`), validates locally first (minimum 8 characters, must
match), and is installed once from `AppSupport.
applicationDidFinishLaunching`, which observes
`.appwriteRecoveryLinkReceived` and shows the window for the link's
credentials. Fields are cleared on success, cancel, and close.

## Package.swift wiring needed

- `SwiftCodeIDECore` target: add `.product(name:
  "StoreKitEngine", package: "swiftcode-storekit")` and
  `"SwiftCodeHealthStore"`. Same two on `SwiftCodeIDECoreTests`.
- `SwiftCodeExtensions` target: add `"SwiftCodeLanguage"` and
  `"SwiftCodeDebug"` (LSP adapter; no cycle — `SwiftCodeLanguage`
  deps are `SwiftCodeDebug` + `SwiftCodeSubprocess`).
- `SwiftCodeMCPTests` target: add `"SwiftCodeExtensions"`
  (approval-center + LSP-adapter tests).
- No other target split is required — all new code fits existing
  targets. The generator needs no wiring (see §7).

## Wave 19 slice F follow-up

The gap-closure wave stopped on a time-box with this spec and both
`MiscGapTests.swift` files unwritten, the three held patches
unapplied, the 3 `.disabled` LLM tests un-enabled, the password-reset
UI unbuilt, and the generator not re-implemented. Wave 19 slice F
closed all of them (staged, not yet integrated at the time of
writing):

- The native generator (§7) is implemented (`XcodeGenNativeGenerator.
  swift`, ~2,400 lines) with the handler rewrite, including the
  ref-cache and group-path fixes found during writing.
- Both `MiscGapTests.swift` files are written (generator tests
  through the real tool; StoreKit purchase / Ask to Buy / refund /
  expire / reset / offline / network-failure / no-config on an
  in-memory session with a `ManualClock`; DB models on `:memory:`
  SQLite + temp-file backup round-trip; CSV parser edge cases;
  approval-center allow/deny/no-presenter/second-request;
  LSP adapter missing-executable + `/usr/bin/false` early-exit).
- The three held patches are applied as complete staged files.
  Two corrections to the coordinator's drafts, both recorded in
  `INTEGRATION.md`: the `RecentProjects` draft's anchor omitted the
  live `NotificationCenter` post line and its kind check
  (`lastPathComponent == "Package.swift"`) never fires for a
  directory root — the staged version checks for
  `Package.swift` inside the container; the
  `ExtensionsPanelViewController` draft's anchor omitted the live
  `Task { await viewModel.load(); refreshAll() }` line.
- The 3 `.disabled` LLM tests are enabled (their patches were
  verified applied in the tree).
- The password-reset completion UI (§8) is built.

## Evidence

- The gap-closure coordinator's final report and the misc slice's
  time-boxed wrap-up report, in the coordinator session log
  `/home/hatch/agents/agent-66ec9516-b028-495d-8356-d0c85ef0ff8b/
  sessions/66ec9516-b028-495d-8356-d0c85ef0ff8b.jsonl`
  (extracted searchable copy `/tmp/gap-log-all.txt`, lines
  2247–2420 for the misc slice report; lines 2452, 2474, 2482,
  2489, 2494 for the coordinator's merge). Evidence level 1–2:
  the slice's claims were verified against the live destination
  tree (source reads, API signatures, delimiter balance,
  `scan-public.py` 0 findings) and Dylan's own Legacy code; no
  Apple binary, Ghidra output, or Xcode/Simulator observation was
  used.
- Wave 19 slice F verification (this work): every API named in the
  staged test files was re-read in the post-rebrand tree
  (`swiftcode/`); the staged Swift files pass a Swift-aware
  delimiter-balance check; no Swift toolchain exists in this
  environment, so `swift build` / `swift test` and all live runs
  remain pending on Dylan's Mac. Nothing in this spec is VERIFIED.
