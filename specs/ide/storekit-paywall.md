# StoreKit editor, paywall, and entitlement runtime

Spec for Wave 13 of the SwiftCode Legacy → Mac migration. Legacy is
Dylan's own SwiftCode codebase (main `d51a8f0d`); direct porting was
authorised by Dylan under MIT, spec-first where it costs nothing.
Destination is the SwiftCode base (main `8d369050`).

This spec covers three related but distinct Legacy surfaces:

1. **The IDE's own paywall** — `StoreKitManager` / `EntitlementManager`
   plus `PaywallView`: the SwiftCode Pro in-app purchase flow.
2. **The StoreKit configuration editor** — a standalone `.storekit`
   file editor with a local purchase simulator (`Views/Utilities/StoreKit/`,
   13 files, 4,661 lines).
3. **The entitlements editor** — a UI-only editor for `.entitlements`
   plists (`Core/Editor/EntitlementsEditorManager.swift`,
   `Views/Editor/EntitlementsEditorCatalog.swift`,
   `Views/Editor/EntitlementsEditorView.swift`).

`SDKEntitlement.swift` (developer API-key entitlements) is explicitly
**out of scope** here — see §9. It belongs to the later SDK-platform wave.

## 0. Reading guide

- "Legacy" means a file under `SwiftCode/` in
  `~/workspace/repos/SwiftCode-Legacy` @ `d51a8f0d`, read directly for
  this spec. Line counts are raw `wc -l`.
- "Destination" means `~/workspace/repos/SwiftCode-Mac` @ `8d369050`.
- Product IDs, key names, and type names below are quoted exactly as
  they appear in source. Where Legacy and the destination disagree on
  a format detail, the destination's clean-room spec
  (`specs/frameworks/storekit/configuration-file.md`, levels 2–3) wins
  and the difference is called out as an ADAPT item.

## 1. Product catalog — IDs are configuration, not data

### 1.1 The three Pro product IDs (verified live)

`SwiftCode/Backend/Store/StoreKitManager.swift:12-16` (98 lines):

```swift
private let productIdentifiers = [
    "swiftcode.pro.monthly",
    "swiftcode.pro.yearly",
    "swiftcode.pro.lifetime"
]
```

### 1.2 How they are resolved at runtime

The IDs are **purely local constants**. Nothing in Legacy fetches a
product-ID list from App Store Connect, from a server, or from a
`.storekit` file. Resolution works like this:

1. `StoreKitManager.init` starts a detached `Transaction.updates`
   listener and a `Task` that calls `loadProducts()` then
   `updateCustomerProductStatus()`.
2. `loadProducts()` calls Apple's StoreKit 2
   `Product.products(for: productIdentifiers)` — the **name, price,
   description, and display price come from App Store Connect** at
   that point. Products are sorted ascending by `price`.
   On failure it only `print("Failed to load products: \(error)")`
   and leaves `products` empty; the paywall then shows its loading
   state with a manual "Refresh Products" button (§5).
3. There is no local fallback catalog for the paywall itself. (The
   StoreKit *editor's* default workspace, §6.3, is a different thing:
   sample products with different IDs —
   `com.swiftcode.premium_unlock`, `com.swiftcode.credits_pack`,
   `com.swiftcode.pro_monthly` — and is never used by the paywall.)

Consequences for the implementation slices:

- The IDs must stay **configuration**: a constant list in the new
  runtime target, not hardcoded inside a view, so a future App Store
  Connect change is a one-line edit. Do not invent a fetch endpoint
  for the ID list — none exists in Legacy.
- Whether `swiftcode.pro.monthly` / `swiftcode.pro.yearly` /
  `swiftcode.pro.lifetime` actually exist in App Store Connect for
  this app **cannot be verified from source**. The IDE is currently
  distributed outside the App Store (GitHub releases + Flatpak per
  `docs/RELEASING.md`); until Dylan confirms the products exist in
  App Store Connect and the app is App Store-distributed, the
  purchase flow is untestable end-to-end. Recorded as an honest gap
  (§10).
- The paywall distinguishes the three products only by what App Store
  Connect returns (`displayName`, `description`, `displayPrice`).
  Legacy never inspects product type: monthly/yearly are treated as
  subscriptions and lifetime as a non-consumable only implicitly, by
  whatever App Store Connect says. The entitlement check (§3) does
  not distinguish them at all — any one of the three grants Pro.

### 1.3 No server side

There is **no server-side receipt validation anywhere in scope**:
`grep` for `verifyReceipt`, `appstoreconnect`, `sharedSecret`,
`appStoreReceiptURL` over `Backend/Store/`, `Views/Paywall/`, and
`Views/Utilities/StoreKit/` returns nothing except a simulator
profile *description* mentioning JWS validation. Verification is
entirely local, via StoreKit 2's `VerificationResult` (§4). There is
no endpoint to port, and none may be invented.

## 2. Entitlement model

### 2.1 Runtime model (the IDE's own Pro status)

`SwiftCode/Backend/Store/EntitlementManager.swift` (22 lines):

- `EntitlementManager.shared`, `@Published private(set) var isProUser: Bool = false`.
- `updateProStatus(isPro:)` sets `isProUser = isPro || FeatureFlags.shared.bypass_paywall`
  on the main queue.
- `proAccess` is the same OR. (`proAccess` has no callers in Legacy;
  `isProUser` is the live gate.)

`StoreKitManager` is the only writer of Pro status from purchases:
`updateCustomerProductStatus()` iterates `Transaction.currentEntitlements`,
keeps only `.verified` transactions (see §4), collects their
`productID`s into `purchasedProductIDs`, and calls
`EntitlementManager.shared.updateProStatus(isPro: !purchasedIDs.isEmpty)`.

So the entitlement model is a single boolean: **Pro iff at least one
verified current entitlement exists for any of the three product IDs,
OR the `bypass_paywall` developer flag is on**. There is no per-feature
entitlement, no expiry modelling (a lapsed subscription simply drops
out of `currentEntitlements`), no persistence of Pro status itself
(it is recomputed from transactions on every launch), and no
distinction between monthly / yearly / lifetime.

### 2.2 The `bypass_paywall` flag

`SwiftCode/Backend/Developer/FeatureFlags.swift:6-10,42`:

- `@Published var bypass_paywall: Bool`, persisted in UserDefaults
  under the key `"bypass_paywall"`, toggled in the developer
  Feature Flags view (`Views/Developer/FeatureFlags/FeatureFlagsView.swift:9`,
  toggle labelled "Bypass Paywall").
- Setting it re-runs `updateProStatus(isPro: isProUser)`, so the flag
  takes effect immediately.

The flag is a **developer escape hatch, not a product feature**. The
destination must keep it behind the same developer-only surface and
must never expose it in the paywall or Settings Pro section.

### 2.3 Relation to the destination's existing entitlement types

Do not confuse the three entitlement concepts:

| Concept | Lives in | Meaning |
|---|---|---|
| Pro entitlement (this spec) | New runtime target (§8) | Whether the user bought SwiftCode Pro |
| App entitlements plist values | `SwiftCodeSigning.EntitlementValue` / `Entitlements` (`swiftcode/Sources/SwiftCodeSigning/EntitlementValue.swift`) | One value of a project's `.entitlements` plist; `EntitlementPolicy` decides whether a provisioning profile allows it |
| SDK developer-key entitlements | `SDKEntitlement.swift` | Key-bound grants for third-party SDK use — §9, deferred |

The entitlements *editor* (§7) edits plist values of the second kind;
it has nothing to do with Pro status. The implementation slices must
not merge these types.

## 3. Entitlement gating logic (what Pro actually gates)

Verified by grep over all Legacy Swift sources for `isProUser`,
`proAccess`, `bypass_paywall`, `EntitlementManager.shared`, and
`StoreKitManager.shared`:

- **The only production gate is the Settings Pro section.**
  `Views/Settings/GeneralSettingsView.swift:1880-1896`
  (`proSection`): if `entitlementManager.isProUser`, show
  "SwiftCode Pro Member!" + "Active"; otherwise show an
  "Upgrade to Pro" button that presents `PaywallView` as a sheet.
- **The six features listed on the paywall are not gated anywhere.**
  `PaywallView.features` lists "AI Documentation Insights",
  "Deployments (Netlify, Vercel, GitHub Pages)", "Advanced Debug
  Tools", "Extension Marketplace", "Binary Tool Integrations",
  "CI Builds" — but no file other than `GeneralSettingsView`,
  the debug views, and the store backend itself reads `isProUser`.
  The paywall is therefore currently a promise, not an enforcement
  mechanism. The destination must port this honestly: port the
  paywall and the boolean, and record the ungated features as a
  known gap (§10) rather than inventing gates Dylan never built.
- **Entry points that present the paywall:** only two —
  `GeneralSettingsView` (sheet, §3) and `PaywallDebugView`
  ("Force Show Paywall", §8). Nothing presents it automatically on
  launch, on feature use, or after a trial period. There is no
  trial, no usage counter, and no "Pro required" alert anywhere.
- **The StoreKit editor** is opened from the file navigator's bottom
  bar (`Views/Sidebar/FileNavigatorSidebarView.swift:280`):
  a receipt-icon button with help text
  "Open StoreKit Configuration Workspace" calling
  `StoreKitWindowManager.shared.showWindow()` (no file). It is not
  gated on Pro status.

## 4. Purchase / restore flows (StoreKit 2, Apple framework)

All from `StoreKitManager.swift`, `AppStore.swift` (34 lines),
`EntitlementManager.swift`:

- **Load:** `loadProducts()` → `Product.products(for:)` → sort by
  price ascending. Failure: log only, empty list.
- **Purchase:** `purchase(_ product:)` → `product.purchase()`:
  - `.success(let verification)` → `checkVerified` (throws
    `StoreKitError.notEntitled` on `.unverified`, returns the value
    on `.verified`) → `updateCustomerProductStatus()` →
    `transaction.finish()`.
  - `.userCancelled`, `.pending`, `@unknown default` → do nothing
    (no UI feedback at all — no spinner, no error, no success
    message; the paywall's only feedback is the Pro state changing).
  - A thrown error from `product.purchase()` propagates to the
    caller; `PaywallView` calls it with `try?`, so purchase errors
    are swallowed silently (§5).
- **Transaction observation:** a detached `Task` loops
  `Transaction.updates`; each result is verified, then
  `updateCustomerProductStatus()` runs and the transaction is
  finished. Unverified updates are logged and not finished.
- **Restore:** `restorePurchases()` → `AppStore.sync()` (Legacy's
  own `AppStore` enum, which forwards to `StoreKit.AppStore.sync()`)
  → `updateCustomerProductStatus()`. Errors propagate; the paywall
  calls it with `try?`.
- **Manage subscriptions:** `AppStore.showManageSubscriptions()` —
  on iOS/tvOS it presents `StoreKit.AppStore.showManageSubscriptions(in:)`
  in the first window scene; on macOS it opens
  `https://apps.apple.com/account/subscriptions` in the browser.
  **No caller exists in Legacy** (grep: zero call sites). Port the
  function, but do not invent a UI entry point for it; note it as
  available-but-unwired (§10).
- **Verification:** local JWS verification only, via StoreKit 2's
  `VerificationResult`. `.unverified` is treated as "not entitled"
  (`StoreKitError.notEntitled`, a single-case enum). There is no
  custom JWS parsing, no certificate pinning, and no server check
  in the purchase path.

### 4.1 Which StoreKit the destination uses

On macOS the runtime must use **Apple's StoreKit 2** (the
`StoreKitManager` port), exactly as Legacy does. The destination's
own `frameworks/storekit` `StoreKit` product is the *local test
store* counterpart (it carries Apple's module name so
`import StoreKit` source compiles on Linux); it must **not** be
wired into the IDE's own purchase flow. The editor's simulator
(§6.6) is the place that talks to the local engine — see §8.

## 5. Paywall UI behaviour

`SwiftCode/Views/Paywall/PaywallView.swift` (143 lines), SwiftUI:

- Presented as a sheet (from Settings and from the debug view).
  `NavigationStack` + `ScrollView`, title "SwiftCode Pro", toolbar
  "Done" button dismisses.
- **Header:** crown icon (orange, 60pt), "Unlock Your Potential",
  "Upgrade to SwiftCode Pro and get access to powerful features
  designed for professional developers."
- **Features section:** the six hardcoded strings from §3, each with
  an orange checkmark, in a liquid-glass card. The list is static
  text — it is not derived from products, entitlements, or App Store
  Connect.
- **Products section:**
  - While `storeManager.products` is empty: spinner + "Loading
    Products..." + a "Refresh Products" button that re-runs
    `loadProducts()`. It also re-triggers load `onAppear`. Note the
    ambiguity this preserves: an empty list means "still loading"
    *or* "load failed" *or* "no products configured" — Legacy does
    not distinguish them, and neither must the port (but the port
    should surface a load error if the runtime can report one; see
    §10).
  - Otherwise one bordered-prominent orange button per product:
    `displayName` (headline), `description` (caption, secondary),
    `displayPrice` (headline, trailing). Tap → `try? await
    storeManager.purchase(product)` — errors swallowed, no
    in-progress state, no confirmation.
- **Restore:** "Restore Purchases" button (subheadline, secondary)
  → `try? await storeManager.restorePurchases()`, no feedback.
- **Styling debt to drop by design:** orange accent, crown, and the
  liquid-glass card are Legacy styling. Per the migration prompt
  (§8 rebrand / Mac-style UI), the destination paywall is rebuilt
  in Mac style: SwiftCode's blue accent (`ShellColors.accent`,
  `52/120/246`), sentence-case section titles, no orange, no
  capitalised headers. Content (title, subtitle, six features,
  product rows, restore) is preserved.
- **Preview:** `#Preview { PaywallView() }` — port as a SwiftUI
  preview only if the destination shell keeps previews for this view.

## 6. StoreKit editor behaviour

A standalone `.storekit` configuration editor. It is **not** part of
the workspace window: it opens in its own window(s), edits one
`.storekit` JSON file at a time, and its simulator is a local mock
that never touches Apple's StoreKit.

### 6.1 Window, layout, toolbar

`Windows/StoreKitWindowController.swift` (173 lines),
`Windows/StoreKitWindowManager.swift` (43 lines),
`Workspace/StoreKitSplitViewController.swift` (212 lines):

- `StoreKitWindowManager.shared.showWindow(for:)` — one window per
  file URL (re-focuses an existing window for the same file);
  `closeAllWindows()`; windows are removed from the list on close.
- Window: 1250×850, min 1050×750, `fullSizeContentView`, title
  "StoreKit Workspace - Xcode Grade Editor" (no file) or
  "StoreKit - <filename>"; per-file frame autosave name
  `StoreKitWorkspace_<filename>` / `StoreKitWorkspace_Default`;
  fullscreen-primary, managed.
- Toolbar (customisable, autosaved, icon-only): toggle left sidebar,
  Open, Save, flexible space, Undo, Redo, flexible space, toggle
  right inspector. Undo/redo go through the session (§6.2).
  Open uses `NSOpenPanel` accepting `.json` and `.storekit`;
  Save delegates to the session (§6.4).
- Three-pane split: left sidebar 230–320 (collapsible), center
  editor min 550, right inspector 250–320 (collapsible). Collapse
  state persists in UserDefaults
  (`com.swiftcode.storekit.leftSidebarCollapsed`,
  `com.swiftcode.storekit.rightInspectorCollapsed`).
- Center top bar: breadcrumb "StoreKit Workspace / <section>",
  file name (or an "In-Memory Temporary Config" badge when
  unsaved), and a live validation badge — "N Issues" (orange) or
  "No Issues" (green) — computed by re-running validation on every
  render.

Destination note: rebuild this as a Mac-style editor window on the
SwiftCode pattern (AppKit window controller in `SwiftCodeUI`, portable
session model in the new target, SwiftUI views in `swiftcode-ide` /
`SwiftCodeIDEShell` view model). The Legacy title string
"Xcode Grade Editor" / "Xcode Grade IDE Suite" (sidebar subtitle)
must be dropped — it names Apple's product; the destination uses
its own naming.

### 6.2 Session and undo

`Managers/StoreKitWorkspaceManager.swift` (239 lines):

- `StoreKitWorkspaceSession` (`@Observable`, `@MainActor`,
  `Identifiable`): `activeConfig: StoreKitConfig`,
  `activeURL: URL?`, `selectedSection: String = "Dashboard"`,
  undo/redo stacks of whole-config snapshots (cap 50, redo cleared
  on new edit). `pushToUndoStack()` must be called by editors before
  mutating; undo/redo log to the simulation service.
- `StoreKitWorkspaceManager.shared`: the shared `activeConfig` mirror
  (sessions write through to it via `didSet`) and a recents list
  (max 10, UserDefaults key `com.swiftcode.storekit.recents`).
- `loadDefaultWorkspace()` builds the sample config (§6.3).
  `loadDocument(from:)` parses via `StoreKitParser` and clears
  undo/redo; on parse failure it logs only — the previous config
  stays live and the user gets no alert (preserve the behaviour,
  but the port should surface the error; §10).
- `saveDocument()` with no URL opens an `NSSavePanel` (`.json` /
  `.storekit`, default name `Configuration.storekit`);
  `saveDocument(to:)` encodes atomically and records the recent.
- `loadTemplate(name:)` — five templates (§6.5), each pushing an
  undo snapshot first.

### 6.3 The `.storekit` file model

`Models/StoreKitModels.swift` (587 lines) — `StoreKitConfig`:

```swift
StoreKitConfig { identifier: String (= UUID string by default)
                 settings: SKSettings
                 products: [SKProduct]
                 subscriptionGroups: [SKSubscriptionGroup]
                 nonRenewingSubscriptions: [SKNonRenewingSubscription]
                 version: [Int] (= [4, 0]) }
```

- `SKSettings`: `billingGracePeriodEnabled`, `billingRetryEnabled`,
  `failTransactionsEnabled` (all default false),
  `storeKitError: String?`, `locale` (default `"en_US"`),
  `storefront` (default `"USA"`), `timeRate` (default `"none"`).
  Coding keys strip the leading underscore (`_billingGracePeriodEnabled`
  ↔ `billingGracePeriodEnabled`).
- `SKProduct` (consumable / non-consumable): `productID`,
  `referenceName`, `type` (`"Consumable"` / `"NonConsumable"`),
  `localizations: [SKLocalization]`, `price: Double` (default 0.99),
  `familySharing`, plus `index: Int?`, `availability` (`"all"` /
  `"none"`), `images: [String]` — **but the custom decoder drops
  `index`, `availability`, and `images`** (sets `nil` / `"all"` /
  `[]`), so a round-trip through Legacy's parser silently loses
  them. The port must not reproduce that loss.
- `SKSubscriptionGroup`: `id` (UUID string by default),
  `referenceName` (exposed as `groupName`), `localizations`,
  `subscriptions: [SKSubscription]`.
- `SKSubscription` (auto-renewable): `productID`, `referenceName`,
  `type` default `"AutoRenewableSubscription"`, `localizations`,
  `price` (default 9.99), `familySharing`,
  `subscriptionGroupID: String`, `subscriptionPeriod` (default
  `"P1M"`), `index`, `availability`, `introductoryOffers`,
  `promotionalOffers`, `winBackOffers`, `offerCodes`.
- Offers: `SKIntroductoryOffer` (`numberOfPeriods`, `paymentMode`
  `"payAsYouGo"` / `"payUpFront"` / `"freeTrial"`, `price`,
  `subscriptionPeriod`); `SKPromotionalOffer` (`offerID`,
  `referenceName`, `paymentMode`, `price`, `numberOfPeriods`,
  `subscriptionPeriod`); `SKWinBackOffer` (same shape);
  `SKOfferCode` (`code`, `referenceName`, `customerEligibility`
  `"new"` / `"existing"` / `"all"`, `expirationDate: String?`
  `"YYYY-MM-DD"`).
- `SKLocalization`: `locale`, `displayName`, `description`.
- `SKStorefront`: `code` (`"USA"` etc.), `name`, `region`,
  `currency`, `isAvailable`.
- Simulator-only models (never in the file): `SKTransaction`
  (`purchaseState` `"purchased"` / `"failed"` / `"pending"` /
  `"refunded"` / `"revoked"`, `ownershipType`, `isSubscription`,
  `expirationDate`, `originalTransactionID`, `storefront`,
  `subscriptionCycleState` `"Purchase"` / `"Renewal"` /
  `"GracePeriod"` / `"BillingRetry"` / `"Expired"` / `"Refunded"`),
  `SKEntitlement` (`productID`, `isSubscription`, `purchaseDate`,
  `expirationDate`, `isActive`), `SKAsset`, `SKSimulatorProfile`
  (`isOffline`, `isAskToBuy`, `simulateNetworkError`,
  `failJWSVerification`), `SKActivityEvent` (category
  `"Purchase"` / `"Refund"` / `"Validation"` / `"Import"` /
  `"Export"` / `"Simulation"`), `SKVersionRevision`
  (timestamp, reason, whole-config snapshot), `SKSmartFilter`
  (`minPrice`, `maxPrice`, `productType`).

**Format mismatches vs the destination's canonical model
(`StoreKitConfiguration.StoreConfiguration`) — ADAPT, do not copy
Legacy's shapes:**

| Legacy | Destination (`StoreKitConfiguration`) / canonical file | Action |
|---|---|---|
| `version: [Int]` `[4, 0]` | `Version { major, minor }` object | Map to the object form |
| `identifier` = UUID string | `identifier`: 8 uppercase hex digits (`5C0DE001`) | Generate/preserve 8-hex on new files; preserve whatever a loaded file has |
| `price: Double` | `displayPrice: String` decimal (`"0.99"`), never converted; JWS price = ×1000 | Store the string; parse/format at the UI edge |
| `type` `"AutoRenewableSubscription"` | `type` `"RecurringSubscription"` | Map on read/write |
| `subscriptionGroupID` = group *name* | group `id` is a digit string; `subscriptionGroupID` references it | Map group identity to the digit-string id; Legacy's name-keyed linking is the bug the validator's `fixMismatchGroup` papers over |
| `SKSubscriptionGroup.id` = UUID | group `id`: digit string | Same as above |
| `timeRate: String` (`"none"` / `"Monthly"` / `"Weekly"`) | `Settings.timeRate: Int?` | Map string ↔ int via `SKTestSession.TimeRate` |
| `storeKitError: String?` | `storeKitErrors: [JSONValue]?` | Map single ↔ array |
| `settings` lacks `askToBuyEnabled`, `billingIssuesEnabled`, `renewalBillingIssuesEnabled`, `disableDialogs` | `Settings` has all four | Add; the simulator already models Ask to Buy and billing issues separately (§6.6) |
| `SKProduct` decoder drops `index`/`availability`/`images` | `ConfiguredProduct` keeps `extra: [String: JSONValue]` for unknown keys | Preserve unknown keys via `extra`; never drop fields on decode |
| `SKOfferCode` (`code`, `customerEligibility`, `expirationDate`) | code offers per `configuration-file.md` §5.2 | Verify field mapping in the implementation slice; structure was not fully observable in Legacy |
| `winBackOffers` fully modelled in Legacy | `winbackOffers: [JSONValue]?` — structure unobserved in the destination spec (open question 5) | Carry Legacy's shape through `extra`/JSONValue; do not claim Xcode compatibility for win-back offers |
| No `appPolicies`, no `internalID` anywhere | `appPolicies`, `ConfiguredProduct.internalID` (digit string, becomes product JSON `id`) | Add on write where the canonical format requires it; preserve on read |
| Encoder: `JSONEncoder` pretty-printed, sorted keys | Canonical text form: two-space indent, `"key" : value` (spaces both sides of colon), sorted keys, empty array as `[` + blank line + `]` | Use `StoreKitConfigurationFile` / `JSONWriter` from `StoreKitConfiguration`, not `JSONEncoder` |
| No `isSynchronized` handling | `StoreConfiguration.isSynchronized` (keys `_applicationInternalID`, `_developerTeamID`, `_lastSynchronizedDate`); a synchronized file is read-only in the editor | Preserve those keys on edit; treat a synchronized file as read-only |

The destination reuse is therefore: **the editor edits
`StoreKitConfiguration.StoreConfiguration` (via
`StoreKitConfigurationFile`), not Legacy's `StoreKitConfig`.**
Legacy's model file is the behaviour reference for field lists and
defaults; its wire shapes are not.

### 6.4 Read / write

`Parsers/StoreKitParser.swift` (24 lines),
`Encoders/StoreKitEncoder.swift` (26 lines):

- Parse: `JSONDecoder` → `StoreKitConfig`, from `Data`, `URL`, or
  `String`. Invalid UTF-8 → `NSError` domain
  `StoreKitParserError` code -1.
- Encode: `JSONEncoder`, `.prettyPrinted, .sortedKeys`, to `Data`,
  `String`, or atomically to `URL`. UTF-8 conversion failure →
  `NSError` domain `StoreKitEncoderError` code -1.

Destination replacement: `StoreKitConfigurationFile.init(contentsOf:)`
/ `init(data:)` and `.write(to:)` / `.data()` (see §8.1). The
Legacy parser/encoder files themselves are DROP (superseded by the
framework), but their *contract* (parse from data/URL/string, atomic
write, typed errors) is the behaviour to preserve.

### 6.5 Editor sections (center pane)

`Editors/StoreKitEditors.swift` (2,060 lines, 22 views) routed by
`StoreKitCenterWorkspaceView` on `session.selectedSection`
(`Workspace/StoreKitSplitViewController.swift`).
`Sidebar/StoreKitSidebarView.swift` (202 lines) lists 25 items in
5 groups (WORKSPACE, PRODUCTS, MANAGEMENT, TESTING & UTILITIES,
ADVANCED) plus a FAVORITES section when products are pinned and a
recents menu. The sidebar shows live badges: validation issue count
on "Health & Validation", transaction count on "Transactions".
Section names are stringly typed; the destination must replace them
with an enum.

| # | View (Legacy) | Section(s) | Behaviour |
|---|---|---|---|
| 1 | `StoreKitDashboardView` | Dashboard | Health-score metric cards (health %, product count, group count, issue count), per-type catalog counts, quick actions (Add Product / Simulator / Validate), recent activity feed (latest 4 `SKActivityEvent`s) |
| 2 | `StoreKitExplorerView` | Explorer | Finder-like browser: active environment directories, saved simulator profiles with "Apply Profile" |
| 3 | `StoreKitProductsView` (+ `StoreKitProductEditingSheet`) | Products, Consumables, Non Consumables, Auto Renewables, Non Renewables | Spreadsheet table of products (ID, reference name, type, price); filter by type; add (by type), edit sheet (ID, reference name, price, family sharing), duplicate (`<id>_copy`, `<name> Copy`), delete, pin to favorites; bulk rename (suffix `_pro`), bulk duplicate, bulk generate localization, bulk delete; AI generator sheet (§6.5a) |
| 4 | `SmartProductGeneratorSheet` | (sheet) | See §6.5a |
| 5 | `SubscriptionTimelineView` | Subscription Timeline | Lifecycle timeline per subscription; buttons: Simulate Grace Period, Simulate Billing Retry, Simulate Auto-Renewal, Force Expiration |
| 6 | `StoreKitDiagnosticsView` | Diagnostics, Validation | Issue list from `StoreKitValidationService` with severity/category/message and a "Fix Issue" button per fixable issue (§6.7); "All Diagnostics Passed!" empty state |
| 7 | `StoreKitStorefrontEditorView` | Storefronts | Table of 6 hardcoded storefronts (USA/USD, CAN/CAD, FRA/EUR, GBR/GBP, JPN/JPY, AUS/AUD) with an availability toggle per row. **Local-only list, not persisted into the config** — the config's `settings.storefront` is a single string; the editor's table edits nothing on disk |
| 8 | `StoreKitLocalizationEditorView` | Localization | Per-product localization matrix; "Add Language" appends a locale entry (see §6.5b) |
| 9 | `StoreKitAssetEditorView` | Assets | Asset table (file name, sandbox path, size, type); `scanMockAssets()` fills it with **two hardcoded fake rows** (`premium_promotional_art.png` 1.2 MB, `pro_upgrade_screenshot.png` 840 KB, paths under `/home/<user>/project/assets/`) — it scans nothing. DROP the fake scan; the port either scans the real project or shows an honest empty state |
| 10 | `StoreKitOfferEditorView` | Offers | Per-subscription intro offers (add/remove) and promo offers (add/remove with offer ID); win-back offers and offer codes have model fields but **no editor UI** |
| 11 | `StoreKitCompareView` | Compare View | Side-by-side counts vs a hardcoded baseline (2 products, 1 group, version 4.0) with computed "Added: N custom non-consumables" lines. The baseline is a constant, not a loaded file — it compares against nothing real |
| 12 | `StoreKitVersionHistoryView` | Version History | Revision list with "Restore Revision" (replaces `activeConfig`); revisions are **seeded on appear with two fake entries** ("Automatic auto-save backup." = current config, "Initial clean file initialization." = empty config) — no snapshot is ever captured on edit or save. The port must capture real snapshots or drop the view |
| 13 | `StoreKitSearchCenterView` | Search Center | Text search across products (reference name / product ID) |
| 14 | `StoreKitCommandPaletteView` | Command Palette | Filterable list of 5 commands (Create New Product, Run Static Plist Validation, Reset StoreKit Sandbox Simulator, Save Configuration Plist to Disk, Verify Capabilities Entitlements). **Rows are not wired to any action** — selecting one does nothing |
| 15 | `StoreKitSettingsView` | Settings | Toggles bound to `activeConfig.settings`: billing grace period, billing retry, simulate purchase failures; locale picker (en_US / fr_FR / ja_JP) |
| 16 | `StoreKitLogsView` | Logs, (right half of Purchase Simulator) | Timestamped log stream (cap 300, newest first) with "Clear Console" |
| 17 | `StoreKitRawSourceEditorView` | Raw Source | `TextEditor` over the encoded JSON; "Save Raw Edits" re-parses via `StoreKitParser` and replaces the config on success, logs on failure |
| 18 | `StoreKitTemplateGalleryView` | Templates | Cards for the 5 templates (§6.5c) with "Apply Template" |
| 19 | `StoreKitTransactionExplorerView` | Transactions | Table of simulated transactions (date, state, product); per-row "Refund" button (→ `triggerRefund`) |
| 20 | `StoreKitSubscriptionGroupEditorView` | Subscription Groups | Group list with add/remove group and add/remove subscription (verified by structure; detail read at outline level) |
| 21 | `StoreKitPurchaseSimulatorView` | Purchase Simulator | See §6.6 |

#### 6.5a AI product generator

`SmartProductGeneratorSheet` prompts `LLMService.shared.generateResponse`
with "Convert this developer request for a StoreKit product into a
single JSON representing an SKProduct…" and decodes the reply as
`SKProduct`. On decode failure it falls back to a synthesized product
(`com.app.<first 14 chars of prompt, spaces → _>`, type
`NonConsumable`, price 4.99, placeholder description "AI Synthesized
description placeholder."). The destination equivalent is the
SwiftCodeAssistant provider selected in settings (Wave 9 providers), not
Legacy's `LLMService`. The fallback synthesiser is legitimate
behaviour to keep, labelled as a fallback. This is the only place the
StoreKit editor touches an LLM; nothing else in the editor is AI.

#### 6.5b Localization editor detail

`addLocale(to:)` appends a locale entry to the product; the
destination must preserve the matrix (all products × their
localizations) and the "no localizations" empty states. Legacy's
diagnostics treat a missing `en_US` entry as a warning with a
generate-localization fix (§6.7).

#### 6.5c Templates

`loadTemplate(name:)` in the session, five templates, all with
`com.app.*` placeholder IDs (never the real `swiftcode.pro.*` IDs):

- "Premium Unlock" — one non-consumable, $29.99.
- "Pro Version" — one group, monthly $9.99 + yearly $79.99, each
  with a free-trial intro offer.
- "Consumables / Tips" — two consumables, $0.99 / $4.99.
- "Streaming Service" — one group, two tiers, $5.99 / $14.99.
- "Mixed Catalog" — non-consumable + consumable + VIP group
  (monthly $12.99, free trial) + 3-month non-renewing pass $9.99.

Templates replace products/groups/non-renewing subscriptions wholesale
(after an undo snapshot). The default workspace (§6.3) is a sixth,
separate starter config, not one of the five templates.

### 6.6 Purchase simulator

`Services/StoreKitSimulationService.swift` (352 lines),
`StoreKitPurchaseSimulatorView`:

- **State:** in-memory `transactions: [SKTransaction]`,
  `entitlements: [SKEntitlement]`, `activeLogs: [String]` (cap 300),
  `activityEvents: [SKActivityEvent]`, `favoriteProducts` /
  `favoriteGroups`, `customFilters: [SKSmartFilter]` (one default:
  "Premium Offers Only", min $9.99, auto-renewable), four
  built-in profiles (§6.6a), `selectedProfileID`, toggles
  `isOfflineMode`, `isAskToBuyEnabled`,
  `shouldSimulateNetworkFailure`, `shouldFailVerification`.
- **Persistence:** transactions, entitlements, and favorites are
  JSON-persisted to the Caches directory
  (`storekit_transactions.json`, `storekit_entitlements.json`,
  `storekit_favorites.json`) and restored on launch; stale files
  are cleared with a log line. Logs, activity, profiles, and
  filters are not persisted.
- **Purchase:** `executePurchase(productID:referenceName:price:isSubscription:duration:storefront:)` —
  in order: offline → log "Purchase Blocked" (no transaction);
  network failure → blocked; JWS failure → "Purchase Verification
  Failed"; Ask to Buy → a `pending` transaction (no entitlement);
  otherwise a `purchased` transaction with expiry
  P1W = 7d / P1M = 30d / P1Y = 365d (default 30d) for subscriptions,
  no expiry otherwise, plus an entitlement. Every outcome logs an
  activity event.
- **Ask to Buy:** `approvePendingTransaction(id:)` flips pending →
  purchased and grants the entitlement (30-day expiry);
  `declinePendingTransaction(id:)` flips pending → failed.
- **Lifecycle:** `triggerRefund` (purchased → refunded, cycle
  "Refunded", entitlement revoked), `triggerRevocation` (→ revoked,
  entitlement revoked), `simulateExpiration` (entitlement inactive,
  expiry now, cycle "Expired"), `simulateGracePeriod` (cycle
  "GracePeriod", log mentions a 16-day grace period),
  `simulateBillingRetry` (cycle "BillingRetry"),
  `simulateRenewal` (entitlement active, expiry +30d, cycle
  "Renewal"). Note: renewal always adds 30 days regardless of the
  product's period — a Legacy simplification to preserve or fix
  deliberately, not silently.
- **Reset:** `resetSimulator()` clears transactions, entitlements,
  logs, activity, favorites, and persists the empty state.
- **Logging:** `log(_:)` prepends `[HH:mm:ss.SSS]`; `logActivity`
  creates an `SKActivityEvent` and logs it. `os.Logger`
  subsystem `com.swiftcode.storekit`, category `SimulatorService`
  (editors use category `Editors`).

#### 6.6a Simulator profiles

Four built-ins: "SaaS Premium Subscriber" (plain active subscriber),
"Child Sandbox Account" (Ask to Buy on), "Offline Airplane Mode"
(offline on), "JWS Cryptographic Failure" (fail verification on).
`applyProfile` copies the four flags; `saveCustomProfile(name:desc:)`
appends a profile built from the current toggles (not persisted).

#### 6.6b Destination mapping for the simulator

This is where the destination's engine is genuinely reusable, and
where the mapping must be explicit:

- Legacy's hand-rolled mock (`SKTransaction` string states,
  30-day expiries, no JWS at all — the "fail JWS" toggle only
  changes a log line) is **superseded** by
  `StoreKitEngine.AppTestStore` + `StoreKitTest.SKTestSession`,
  which produce real signed JWS transactions
  (`StoreKitSigning.JWS`, `Receipt`), real subscription scheduling
  (`advance()`, `nextEventDate()`, `expireSubscription`,
  `forceRenewal`, `disableAutoRenew`), refunds
  (`refundTransaction`), and simulated errors
  (`setSimulatedError(_:for:)`).
- The implementation slices must map each Legacy simulator action
  to the engine call (e.g. Legacy `executePurchase` →
  `AppTestStore.buyProduct` / `SKTestSession.buyProduct`;
  Legacy `triggerRefund` → `refundTransaction`;
  Legacy `simulateExpiration` → `expireSubscription`;
  Legacy `simulateRenewal` → `forceRenewal`;
  Legacy offline/network/JWS toggles → `SettingsOverrides` /
  `setSimulatedError`). Where no engine equivalent exists, the spec
  requires an honest gap note, not a re-implementation of the mock.
- The simulator's persisted state (Caches JSON) maps to the
  engine's own store; the Legacy file names must not be treated as
  a format to preserve.

### 6.7 Validation

`Services/StoreKitValidationService.swift` (334 lines):

- `ValidationIssue { severity, category, message, objectID, fixType? }`;
  severity `error` / `warning` / `suggestion` / `optimization`;
  category `schema` / `identifier` / `localization` / `relationship` /
  `configuration` / `capability`; fix types
  `generateMissingLocalization`, `fixNegativePrice`,
  `fixEmptyIdentifier`, `fixDuplicateIdentifier`, `fixMismatchGroup`,
  `installSandboxCapability`, `installIAPCapability`.
- `calculateHealthScore`: 100 − 15/error − 8/warning − 3/suggestion
  − 1/optimization, clamped 0–100.
- `validate(config:)` checks, in order:
  1. Capabilities: missing IAP capability / missing App Sandbox
     warnings — **but `checkIAPCapabilityEnabled()` and
     `checkAppSandboxConfigured()` both unconditionally return
     `true`**, so these warnings can never fire. The checks are
     stubs. The port must either implement them for real (against
     the open project's entitlements / capabilities, via the
     destination's project model) or drop the warnings and say so.
  2. Products: empty ID (error), duplicate ID (error), empty /
     duplicate reference name (warning), negative price (error),
     no localizations (warning), empty display name (error),
     empty description (warning).
  3. Non-renewing subscriptions: same ID / price / localization
     checks.
  4. Groups: empty group name (error), empty group (suggestion),
     per subscription: empty / duplicate ID (error), group-ID
     mismatch vs the containing group's name (error — this is the
     Legacy name-keyed linking from §6.3), non-standard period
     (warning; valid: P1W, P1M, P2M, P3M, P6M, P1Y), negative
     intro-offer price (error), empty / duplicate promo offer ID
     (error).
- `applyFix` (in `StoreKitDiagnosticsView`, `StoreKitEditors.swift:881`):
  generate-missing-localization writes an `en_US` entry from the
  reference name with description "Default generated description."
  (**products only** — subscriptions and non-renewing subscriptions
  with the same issue are not fixed); negative price → 0.99
  (products only); empty ID → `com.app.product_<6 hex>` (products
  only); duplicate ID → append `_unique` (products only);
  group mismatch → re-align `subscriptionGroupID` to the group name.
  **The two capability fixes do nothing**: they fall into
  `default:`, which only logs "Capability Checked". Every fix pushes
  an undo snapshot first and logs an activity event.
- Destination mapping: the *rules* port onto
  `StoreKitConfiguration.validate()` (see §8.1) extended with the
  Legacy-specific rules above; the *fixes* port as config mutations
  with undo snapshots, with the products-only limitation either
  fixed (apply to all product kinds) or explicitly documented.
  The health score formula ports as-is.

### 6.8 Protocols file — mostly empty shells

`Protocols/StoreKitProtocols.swift` (128 lines) declares 15
`@MainActor` manager singletons (`StoreKitDocumentManager`,
`StoreKitProductManager`, `StoreKitSubscriptionManager`,
`StoreKitOfferManager`, `StoreKitSimulatorManager`,
`StoreKitValidationManager`, `StoreKitTemplateManager`,
`StoreKitImportManager`, `StoreKitExportManager`,
`StoreKitLocalizationManager`, `StoreKitStorefrontManager`,
`StoreKitAssetManager`, `StoreKitLogManager`,
`StoreKitSearchManager`) and 7 `Sendable` service singletons
(`StoreKitParserService`, `StoreKitEncoderService`,
`StoreKitDecoderService`, `StoreKitDocumentService`,
`StoreKitLoggingService`, `StoreKitImportExportService`,
`StoreKitGenerationService`). Only three have any behaviour
(`StoreKitDocumentManager.activeDocument()`,
`StoreKitProductManager.fetchProducts()`,
`StoreKitSubscriptionManager.fetchGroups()` — all trivial
delegations to `StoreKitWorkspaceManager.shared.activeConfig`).
**Disposition: DROP.** Do not port 22 empty singletons; the
destination's session/service types (§8) are the real seams.

## 7. Entitlements editor behaviour

`Core/Editor/EntitlementsEditorManager.swift` (725 lines),
`Views/Editor/EntitlementsEditorCatalog.swift` (1,374 lines),
`Views/Editor/EntitlementsEditorView.swift` (1,625 lines).
Opened for `.entitlements` files from `Views/EditorView.swift:173`
and `Views/Utilities/XcodeProjTabs.swift:818`.

### 7.1 Manager — file I/O, validation, raw XML

`EntitlementsEditorManager(fileURL:)`:

- `readEntitlements() throws -> [String: Any]` — reads the file as a
  property list (`PropertyListSerialization`); missing file returns
  `[:]` (the view treats that as "create" — see §7.3).
- `writeEntitlements(_:) throws` — sorts keys recursively
  (`sortDictionary`) and writes XML plist, atomic. The sort is
  part of the file's observable behaviour (diffs stay clean).
- `validate(_:) -> EntitlementValidationResult` and
  `crossEntitlementIssues(_:) -> EntitlementValidationResult` —
  cross-key rules: sandbox on/off vs network client, app groups
  entries, keychain groups, `aps-environment` must be
  `development` / `production`, iCloud containers require
  `com.apple.developer.icloud-services`, associated-domains entries
  must start with `applinks:` / `webcredentials:` /
  `activitycontinuation:` / `appclips:`, default-data-protection
  must be a known value, and more (read at outline level;
  implementation slice to transcribe the rule list from lines
  473–705). Errors vs warnings are distinguished in the result
  (`isValid` = no errors).
- `generateRawXML(_:) -> String` — the sorted XML text for the raw
  view.
- Models: `EntitlementPlatform` (macOS / iOS / tvOS / watchOS /
  visionOS), `EntitlementCategory` (App Sandbox, Network &
  Security, Hardware & Media, Storage & Files, System Extensions
  & Drivers, Apple Capabilities), `EntitlementValueType`
  (boolean / string / array / dictionary),
  `EntitlementMetadata` (display name, raw key, category,
  description, supported platforms, minimum OS, default value,
  value type, validation rules, search keywords, recommended usage,
  SF symbol, display-color hex), `Entitlement` (metadata +
  current value + isEnabled), `EntitlementValidationResult`,
  `EntitlementWarning`, `EntitlementError`, `EntitlementChange`
  (raw key, old/new value, timestamp).
- `EntitlementsCatalog.all: [EntitlementMetadata]` — **17 entries**
  (lines 161–420). Four structs are empty stubs and are dropped:
  `EntitlementGroup`, `EntitlementSection`, `EntitlementCapability`,
  `EntitlementAvailability`.

Destination mapping: the manager's plist I/O maps onto
`SwiftCodeSigning.EntitlementValue` / `Entitlements.fromPropertyList`
/ `xmlPropertyList()` (same semantics: plist → typed values → XML,
sorted keys) plus `SwiftCodePlist` where it fits; the metadata catalog
(`EntitlementsCatalog.all`, 17 entries) ports as data. The
validation rules port as pure functions over `Entitlements`.

### 7.2 Catalog — 128 capability definitions

`EntitlementsEditorCatalog.swift`:

- `EntitlementCapabilitySection`: 9 cases — All, Sandbox, Hardened
  ("Hardened Runtime"), Cloud ("iCloud & Push"), Sharing, Personal
  ("Personal Information"), Services ("Apple Services"), Extensions
  ("System & Driver Extensions"), Other — each with a display title
  and an SF symbol.
- `CapabilityPayloadKind`: `none`, `idList(placeholder:)`,
  `fixedValueList(allowed:)`, `choice(options:)`,
  `stringValue(placeholder:)`, `prefixedList(prefixes:placeholder:)`,
  `iCloudComposite`.
- `CapabilityDefinition` (one toggleable capability): name,
  section, payload kind, and the entitlement key(s) it writes.
  Enabling a capability writes the real entitlement key;
  disabling it removes the key from the file. Composite
  capabilities control more than one key (e.g. iCloud).
  A flag marks capabilities Apple only grants through a special
  request.
- `CapabilityCatalog.definitions: [CapabilityDefinition]` — **128
  entries**. Known key constants: `iCloudContainersKey`
  (`com.apple.developer.icloud-container-identifiers`),
  `iCloudServicesKey`, `iCloudKVStoreKey`, `ubiquitousContainersKey`
  (`NSUbiquitousContainers`).

The 128 definitions are data, not logic: port them as a static
table (transcribed from the catalog file) in the new target. The
implementation slice must verify the count (128
`CapabilityDefinition(` occurrences) and transcribe every entry —
a dropped definition silently removes a capability from the editor.

### 7.3 View — UI-only editor over the dict

`EntitlementsEditorView(fileURL:)`:

- Header comment states the contract: "UI-only editor for the
  entitlements plist. Every control reads and writes the
  entitlements dictionary" — i.e. no raw plist editing in the UI.
- State: `entitlementsDict: [String: Any]`, `searchQuery`,
  `selectedFilter: EntitlementCapabilitySection = .all`,
  `selectedKey`, add sheet, inspector sheet, `toolStatus`,
  `isDirty`, `fileModifiedDate`, custom-key state, add-sheet
  search/section. Requires `WorkspaceViewModel` from the
  environment (destination equivalent: the workspace/project
  model that owns the file).
- Missing file → offers creation: writes a default entitlements
  file (template includes
  `com.apple.security.files.user-selected.read-write`) to the
  target URL.
- Capability toggle: `isCapabilityOn(_:)` / `setCapability(_:on:)`
  write/remove the real key(s) and mark dirty.
- Validation is shown live (`manager.validate` +
  `crossEntitlementIssues` over the current dict).
- Save: `saveChanges()` → `manager.writeEntitlements`, clears
  dirty, refreshes `fileModifiedDate`, status message
  "Successfully saved entitlements to disk." / error text.
  Revert re-reads from disk. Dirty state is tracked with an
  "Unsaved" indicator.
- Sub-editors: `EntitlementIDListEditor` (app groups, keychain
  groups, iCloud containers), `FixedValueListEditor`,
  `AssociatedDomainsEditor` (service prefix + host),
  `ICloudCompositeEditor`, `UbiquitousContainersEditor`
  (`NSUbiquitousContainers`), `EntitlementDictionaryEditor`
  (custom dictionary values), `EntitlementRowView` (unmanaged
  keys with type-appropriate inline editors).
- Per the migration's standing rule (project/settings views give
  full control through UI only — no raw editing), the destination
  entitlements editor keeps this UI-only contract: the raw-XML
  view is a read-only display, not an editing surface. (Legacy's
  view already generates raw XML via `generateRawXML`; whether
  Legacy lets the user edit it was not established — the
  implementation slice must check before porting any raw-edit path.)

## 8. Destination integration

### 8.1 Reuse surface (verified live in the destination)

**`frameworks/storekit/Package.swift`** — package `swiftcode-storekit`,
5 library products, each a target of the same name:

| Product | Contents | Key API names |
|---|---|---|
| `StoreKitConfiguration` | `.storekit` file model | `StoreConfiguration` (`identifier`, `version: Version { major, minor }`, `products` / `nonRenewingSubscriptions: [ConfiguredProduct]?`, `subscriptionGroups: [SubscriptionGroup]?`, `settings: Settings?`, `appPolicies`, `appName`, `extra: [String: JSONValue]`, `allProducts`, `isSynchronized`); `ConfiguredProduct` (`type: ProductKind`, `productID`, `referenceName`, `internalID`, `displayPrice: String?`, `familyShareable`, `localizations: [Localization]?`, `subscriptionGroupID`, `groupNumber`, `recurringSubscriptionPeriod`, `introductoryOffer: Offer?`, `adHocOffers`, `codeOffers`, `winbackOffers: [JSONValue]?`); `SubscriptionGroup` (`id`, `name`, `localizations`, `subscriptions`); `Offer` (`internalID`, `offerID`, `referenceName`, `paymentMode: PaymentMode`, `subscriptionPeriod`, `numberOfPeriods`, `displayPrice`, `eligibility`, `isStackable`); `Settings` (`storefront`, `locale`, `timeRate: Int?`, `askToBuyEnabled`, `billingIssuesEnabled`, `renewalBillingIssuesEnabled`, `billingGracePeriodEnabled`, `disableDialogs`, `failTransactionsEnabled`, `storeKitErrors`); `StoreConfigurationFile` (`init(contentsOf:)`, `init(data:)`, `data()`, `write(to:)`); `JSONValue.parse`, `JSONWriter`; `validate() -> [ValidationIssue]`, `isDecimalPrice(_:)` |
| `StoreKitEngine` | Open local store | `Catalog` (`init(_ configuration:)`, `product(_:)`, `group(_:)`, `CatalogProduct` / `CatalogGroup` / `CatalogSubscription` / `CatalogOffer` / `CatalogLocalization`, `ProductType`, `OfferPaymentMode`, `OfferType`, `Storefront`, `PriceFormatter`); `AppTestStore` (`installConfiguration(_:appName:)`, `removeConfiguration`, `installedConfiguration`, `catalog`, `settings: EffectiveSettings`, `overrideSettings` / `updateSettings`, `setSimulatedError(_:for:)`, `advance()`, `nextEventDate()`, `products(for:)`, `isEligibleForIntroOffer`, `purchase(productID:options:) -> PurchaseOutcome`, `buyProduct(productID:options:) -> TransactionRecord`, `finish`, `allTransactions()`, `transactionHistory()`, `unfinishedTransactions()`, `latestTransaction(for:)`, `currentEntitlements()`, `subscriptionStatuses(groupID:)`, `checkAppTransaction()`, `sync()`, `restoreCompletedTransactions()`, `clearTransactions()`, `deleteTransaction`, `refundTransaction`, `expireSubscription`, `forceRenewal`, `disableAutoRenew`) |
| `StoreKitSigning` | P-256 identity, X.509, JWS, receipt | `JWS.sign` / `JWS.decode` / `JWSVerifier.verify`, `SigningIdentity`, `Receipt.build` / `Receipt.payload` / `Receipt.signedData` / `DecodedReceipt`, `ProductJSON.value` / `.data`, `Base64URL` |
| `StoreKit` | Client API over the engine (Apple module name) | `Product.products(for:)`, `Product.purchase(options:) -> PurchaseResult`, `Product.ProductType` (consumable / nonConsumable / nonRenewable / autoRenewable), `Product.SubscriptionPeriod`, `Product.SubscriptionOffer`, `Transaction` (JWS-backed, `currentEntitlement(s)`), `AppStore.sync()`, `AppStore.canMakePayments`, `AppStore.Environment` (production / sandbox / xcode), `AppTransaction.shared` / `.refresh()`, `Storefront.current`, `SwiftCodeStoreKit.shared` (`Runtime`) |
| `StoreKitTest` | Test session | `SKTestSession` (`init(contentsOf:)`, `buyProduct(identifier:options:)`, `setSimulatedError(forAPI:)`, `TimeRate`, `SubscriptionRenewalBehavior`), `SKTestFailures` (LoadProducts, Purchase, Verification, AppStoreSync, SubscriptionStatus, AppTransaction, ManageSubscriptions, OfferCodeRedeem, RefundRequest) |

`frameworks/storekit` pins swift-crypto `exact: "4.5.2"`, which lies
inside the destination `swiftcode` range `"3.0.0"..<"5.0.0"` (pin 4.5.2)
— no version conflict.

**`swiftcode/Sources/SwiftCodeSigning/`** — `EntitlementValue`
(`string` / `bool` / `integer` / `real` / `date` / `data` /
`array` / `dictionary`, `init?(propertyList:)`, `.propertyList`,
`stringValue` / `boolValue` / `arrayValue` / `dictionaryValue` /
`dateValue` / `dataValue` / `strings`), `Entitlements`
(typealias `[String: EntitlementValue]`), `fromPropertyList` /
`xmlPropertyList()` / `overlaid(with:)` on the dictionary,
`EntitlementPolicy` (`derivedKeys`, `isRestricted(_:on:)`,
`pattern(_:matches:)`, `allows(_:_:)`,
`mismatches(_:profile:platform:)`, `restrictedKeys(_:on:)`).
`SwiftCodeSigning` is Foundation-only (shared with `swiftcode-swb`); the
entitlements editor model may depend on it but must not add
toolkit or StoreKit imports to it.

**`swiftcode/Package.swift`** — today there is **no storekit
dependency** (`grep -i storekit` → 0 hits). The precedent for a
`frameworks/` path dependency is the SwiftUI one
(lines ~287–320): a conditional
`if FileManager.default.fileExists(atPath: Context.packageDirectory + "/../frameworks/swiftui/Package.swift")`
guard, then `package.dependencies += [.package(path: "../frameworks/swiftui")]`
plus products/targets appended with `package.products +=` /
`package.targets +=`. The storekit dependency follows the same
shape — but **unconditional on macOS** (the editor and the paywall
runtime are macOS-first; the SwiftUI precedent is Linux-gated
because Linux needs OpenViews, which does not apply here), e.g.:

```swift
// As landed in Wave 13 (coordinator reconciliation — the block above
// this note in an earlier draft used the wrong `package:` label
// ("storekit" — the declared package name is "swiftcode-storekit") and
// wrongly listed the package's `StoreKit` product as a dependency,
// which would shadow Apple's real StoreKit framework):
package.dependencies += [.package(path: "../frameworks/storekit")]
package.products += [.library(name: "SwiftCodePaywall", targets: ["SwiftCodePaywall"])]
package.targets += [
    .target(name: "SwiftCodePaywall"), // Apple StoreKit 2 only, no third-party dep
    .testTarget(name: "SwiftCodePaywallTests", dependencies: ["SwiftCodePaywall"]),
]
// StoreKitConfiguration (the .storekit file model) is added as a
// dependency of SwiftCodeIDECore, SwiftCodeUI, swiftcode-ide and SwiftCodeIDECoreTests:
//   .product(name: "StoreKitConfiguration", package: "swiftcode-storekit")
// SwiftCodeSigning is added to SwiftCodeIDECore and SwiftCodeIDECoreTests (the
// entitlements editor model). SwiftCodePaywall is added to SwiftCodeUI's deps
// so the shell can present the paywall.
```

The implementation slices confirm the exact package name for the
`.product(..., package:)` references (`swiftcode-storekit` is the
*package* name in `frameworks/storekit/Package.swift`; the
dependency is referenced by path, so the `package:` label is the
package's declared name). Wire the new target into `SwiftCodeIDECore`
and/or `SwiftCodeUI` / `SwiftCodeIDEShell` as the UI slices require, and
into the `swiftcode` executable target via the existing post-hoc
`package.targets[i].dependencies +=` patch pattern if a CLI
surface is needed. (No CLI surface is specified here.)

### 8.2 Recommended target layout (for the implementation slices)

- **New portable target `SwiftCodePaywall`** (model, no toolkit):
  Pro runtime (`StoreKitManager` / `EntitlementManager` ports,
  Apple StoreKit on macOS), product-ID configuration.
  `.storekit` editor session model (config state, undo, recents,
  templates, validation rules, health score, fixes) and the
  simulator session live in `SwiftCodeIDECore/Model`
  (`StoreKitEditorModel`, `StoreKitSimulationSession`); the
  entitlements editor model (`EntitlementsEditorModel` +
  `EntitlementCapabilityCatalog`, 123 unique definitions) lives
  there too. (An earlier draft of this spec proposed one combined
  `SwiftCodeStoreKit` target; Wave 13 landed the split above instead —
  it keeps the paywall runtime away from the frameworks/storekit
  `StoreKit` module name, which would shadow Apple's StoreKit.)
- **macOS presentation in `SwiftCodeUI`** (AppKit): StoreKit editor
  window controller + split view (following the
  `WorkspaceWindowController+<Area>` extension pattern and the
  Asset Catalog editor precedent: model in a shell target, AppKit
  controller in `SwiftCodeUI`), paywall sheet, entitlements editor
  controller. Entry points: file-navigator receipt button for the
  StoreKit editor; Settings Pro section for the paywall;
  `.entitlements` file opening for the entitlements editor.
- **SwiftUI presentation in `swiftcode-ide` + view model in
  `SwiftCodeIDEShell`** (following the `AssetCatalogEditorView` /
  `AssetCatalogEditorModel` precedent): the same three surfaces
  for the Linux / SwiftUI shell where they apply. The paywall is
  macOS-only in practice (Apple StoreKit); the `.storekit` and
  `.entitlements` editors are portable and should work in both
  shells.
- **Settings:** the Pro section ports into the destination
  Settings (13-pane order; the General pane or a dedicated Pro
  row — implementation slice decides, following
  `SettingsPaneCodingAssistant.swift` as the structural example).
  The developer debug views port into the destination's developer
  surface, not into user-facing Settings.

### 8.3 What the destination already has that this wave must not duplicate

- `.storekit` file model: `StoreKitConfiguration` — reuse, do not
  re-model (§6.3).
- Local store engine + JWS signing: `StoreKitEngine` /
  `StoreKitSigning` — reuse for the simulator (§6.6b).
- Test session: `StoreKitTest.SKTestSession` — reuse; Legacy has
  zero references to `SKTestSession`.
- Entitlement plist values + profile policy: `SwiftCodeSigning` — reuse
  for the entitlements editor (§7.1).
- `.storekit` format truth: `specs/frameworks/storekit/configuration-file.md`
  (levels 2–3) and `specs/frameworks/storekit/ide.md` §3 (reference
  editor description, level 1) — the implementation slices read
  these before writing code.
- Verified absent (so this wave genuinely adds it): no StoreKit
  editor, no paywall, no Pro entitlement, no entitlements editor
  in `SwiftCodeUI` / `SwiftCodeIDEShell` / `swiftcode-ide` (grep for
  `paywall` / `isPro` / `StoreKitEditor` / `.storekit` over the
  destination sources returns only the framework files and
  unrelated hits).

## 9. SDKEntitlement — deferred to the SDK-platform wave (record only)

`SwiftCode/SDK/Host/APIKeys/SDKEntitlement.swift` (72 lines) was
read only to place it. It is **not** part of this wave:

- It is a key-bound entitlement carried by a *developer API key*
  (`SDKAPIKey.entitlements`), not an App Store purchase and not an
  app entitlements plist entry. Scopes describe what a key may do;
  entitlements unlock specific SDK surfaces for third-party apps
  after the Assist access application flow.
- Two v1 entitlements, exact identifiers, do not change:
  `com.SwiftCode.developer-AI-Assist` (unlocks the Assist SDK
  variants) and `com.SwiftCode.developer-AI-Allows-Cloud` (unlocks
  the SwiftCode cloud model for third-party apps).
- Binding rule: stored on the API key record, never in the manifest,
  never self-asserted; granted only via
  `SDKAssistApplicationStore.approve` →
  `SDKAPIKeyStore.grantEntitlement`. The type is intentionally open
  (`init?(rawValue:)` accepts any non-empty string); Codable is the
  bare string.
- It belongs with the SDK platform (capability broker, API keys,
  Assist access application flow), not with StoreKit, the paywall,
  or the entitlements editor. Do not port it in Wave 13.

## 10. Error cases and honest gaps

### 10.1 Error cases (Legacy behaviour → destination behaviour)

| Case | Legacy behaviour | Destination behaviour |
|---|---|---|
| `Product.products(for:)` throws | Log only; paywall shows loading state forever with a manual Refresh button | Same loading state, plus surface the error text (the runtime can report it; Legacy could not distinguish load failure from empty catalog) |
| `product.purchase()` throws | Propagates; paywall swallows with `try?` — silent failure | Surface purchase errors in the paywall (alert / inline message); do not swallow |
| `.userCancelled` / `.pending` | Silent no-op | Silent no-op for cancel; show a "pending approval" state for `.pending` (Ask to Buy) — Legacy showed nothing |
| `.unverified` transaction | `StoreKitError.notEntitled` thrown; update skipped, transaction not finished | Same: never grant Pro on an unverified transaction; log the failure |
| Restore fails (`AppStore.sync()` throws) | Propagates; paywall swallows with `try?` | Surface the error |
| `.storekit` parse failure on open | Log only; previous config stays live, no alert | Show the parse error and keep the previous config (do not open a blank document over the user's file) |
| Raw-source JSON parse failure | Log only; config unchanged | Show the parse error inline in the raw editor |
| Entitlements plist unreadable | `readEntitlements` throws; view shows creation flow for a missing file | Distinguish missing file (offer creation) from corrupt file (show error, do not overwrite) |
| Entitlements write failure | Status message with the error | Same, plus keep the dirty flag set |
| Capability fixes in validation | `installIAPCapability` / `installSandboxCapability` do nothing (fall into `default:` logging "Capability Checked"); the checks themselves always return `true` | Either implement the checks for real against the open project or remove the warnings; never ship a "Fix Issue" button that only logs |
| Subscription renewal in simulator | Always +30 days regardless of period | Map to the engine's real scheduling (`forceRenewal` / `advance()`); do not keep the 30-day simplification silently |

### 10.2 Honest gaps (blockers / unverified items)

1. **Products may not exist in App Store Connect.** The three IDs
   are local constants; no source in either repo proves they are
   configured in App Store Connect, and the IDE is not currently
   App Store-distributed. Blocker: Dylan must confirm the products
   exist (or create them) before the purchase flow can be tested
   end-to-end. No Swift toolchain in this environment either —
   `swift build` / `swift test` and any live purchase test stay
   pending on Dylan's Mac.
2. **The paywall's six features are not gated.** Nothing in Legacy
   enforces them (§3). The port must not invent gates; if Dylan
   wants enforcement, that is a separate product decision.
3. **No trial, no paywall trigger.** The paywall only appears when
   the user opens it from Settings or the debug view. No automatic
   presentation is specified.
4. **`showManageSubscriptions` is unwired.** The function exists;
   no UI calls it. macOS opens the subscriptions web page.
5. **No server-side receipt validation** — by design in Legacy,
   not an omission to fix in this wave. Local JWS verification via
   StoreKit 2 is the whole mechanism.
6. **Simulator is a mock in Legacy; the engine mapping is a
   design task, not a transcription.** Each Legacy simulator action
   needs an explicit `AppTestStore` / `SKTestSession` equivalent
   (§6.6b). The "fail JWS" toggle in Legacy only changes a log
   line; the engine's `setSimulatedError` / `JWS.sign(corruptSignature:)`
   is the real equivalent.
7. **Version history has no real snapshots.** Legacy seeds two fake
   revisions on appear and never captures one. The port must capture
   snapshots on save/edit or drop the view.
8. **Compare view compares against a constant**, not a file.
   Either load a real baseline file or drop the view.
9. **Command palette rows do nothing.** Wire the five commands to
   real actions or drop the palette.
10. **Asset editor scans nothing.** Its two rows are hardcoded
    fakes under `/home/<user>/project/assets/`. Scan the real
    project or show an honest empty state.
11. **Storefront editor edits nothing on disk.** Its six-row table
    is local state; the config only stores one `storefront` string.
    The port must bind the table to the config or drop it.
12. **Win-back offer wire shape unverified.** Legacy models
    `SKWinBackOffer` fully; the destination spec lists win-back
    offers as unobserved (open question 5). Do not claim Xcode
    compatibility for win-back offers.
13. **Offer-code wire shape partially unverified.** Legacy's
    `SKOfferCode` fields (`code`, `customerEligibility`,
    `expirationDate`) need checking against
    `configuration-file.md` §5.2 in the implementation slice.
14. **Entitlements raw-XML editing unverified.** Whether Legacy's
    view allows editing the generated XML (vs display-only) was not
    established in this audit; the implementation slice must check
    before porting any raw-edit path. The standing rule is UI-only.
15. **Entitlements validation rule list transcribed at outline
    level only** (`EntitlementsEditorManager.swift:473-705`).
    The implementation slice transcribes each rule exactly.
16. **Subscription-group editor detail read at outline level.**
    Same instruction as (15) for
    `StoreKitSubscriptionGroupEditorView`.
17. **No `.storekit` sample file exists in Legacy** (repo-wide
    `find -name '*.storekit'` → nothing). The default workspace
    and templates (§6.3, §6.5c) are the only sample configs.
    Fixtures for tests must be authored from
    `specs/frameworks/storekit/configuration-file.md`, not copied
    from Legacy.

## 11. What is live vs honestly unavailable

| Capability | Status in the destination after this wave |
|---|---|
| Pro purchase / restore via Apple StoreKit 2 (macOS) | Live, once products exist in App Store Connect (gap 1) |
| Pro boolean + Settings Pro section + paywall | Live |
| Feature gating behind Pro | Honestly unavailable — never existed in Legacy (gap 2) |
| `.storekit` read / write (canonical format) | Live, via `StoreKitConfiguration` |
| `.storekit` editor (all 21 sections) | Live, minus the dropped/fake pieces in §10.2 (7–11) |
| Local purchase simulation with signed JWS transactions | Live, via `StoreKitEngine` / `StoreKitTest` (replaces the Legacy mock) |
| Validation rules + health score + fixes | Live, minus the stubbed capability checks until implemented for real |
| Entitlements editor (17-entry metadata catalog, 128 capability definitions, validation, save/revert) | Live |
| App Store Connect sync of `.storekit` files (`_applicationInternalID`, etc.) | Honestly unavailable — needs an Apple account; the port must preserve the keys and treat such files as read-only |
| Server-side receipt validation | Honestly unavailable by design — none exists |
| SDK developer-key entitlements | Deferred to the SDK-platform wave (§9) |
| `showManageSubscriptions` UI entry point | Available but unwired (gap 4) |

## 12. Wave 15 — Settings Pro section (Slice D)

Sources read live for this section (Legacy read-only, main
`d51a8f0d`; destination main `faf89bd8` at wave start):
`SwiftCode/Views/Settings/GeneralSettingsView.swift:1880-1896`
(`proSection`), `SwiftCode/Backend/Store/EntitlementManager.swift`,
`SwiftCode/Backend/Developer/FeatureFlags.swift` (the
`bypass_paywall` key). Destination: Wave 13's
`swiftcode/Sources/SwiftCodePaywall/` (`PaywallStore`,
`PaywallEntitlementState`, `PaywallView`, `PaywallBypass`),
`swiftcode/Sources/SwiftCodeUI/App/SettingsPanes.swift`
(`GeneralSettingsPane`), `swiftcode/Sources/swiftcode-ide/SettingsPanes.swift`
(Linux/SwiftUI shell — see §12.3).

### 12.1 What landed

The Settings Pro-section paywall presentation hook — the
follow-up Wave 13 left open — is now wired in the AppKit
Settings (macOS):

- **General pane, "SwiftCode Pro" section**
  (`GeneralSettingsPane.proSection`, at the end of
  `build()`, after "Reset SwiftCode"): the row title is
  `"SwiftCode Pro"` in both states, so the pane's structure
  never depends on entitlement. Pro members see
  "SwiftCode Pro Member!" + "Active" (green); everyone else
  gets an "Upgrade to Pro" button that presents the Wave 13
  `PaywallView` as a sheet (`NSHostingController`). The note
  under the row states the rule honestly: "Pro status comes
  from a verified App Store purchase, or the developer bypass
  flag." SwiftCode style throughout: no orange accent (Legacy's
  `.orange` crown row), sentence case.
- **Refresh, once.** Building the section refreshes
  entitlements and re-reads the bypass flag through
  `PaywallStore` (`refreshEntitlements()` +
  `refreshBypassFlag()`), then rebuilds the pane — guarded
  by a `proSectionRefreshed` flag, because the refresh ends
  in `rebuild()`, which re-runs `build()`, so an unguarded
  refresh would loop forever. A purchase made while the
  paywall sheet is open is picked up when Settings is
  reopened (the store's transaction listener also updates
  the entitlement live; the pane re-reads it on its next
  build).
- **Pure state + SwiftUI view** (`swiftcode/Sources/SwiftCodePaywall/ProSettingsSection.swift`):
  `ProSectionState` derives the section from
  `PaywallEntitlementState` (member title, status text,
  upgrade title, `showsUpgradeButton`) and is covered by
  `swiftcode/Tests/SwiftCodePaywallTests/ProSettingsSectionTests.swift`
  (not-Pro → upgrade; Pro via entitlements / bypass /
  debug override → member + "Active"; debug override off →
  upgrade; any verified entitlement grants Pro — Legacy's
  faithful quirk, preserved). `ProSettingsSection` is the
  same section as a SwiftUI view for SwiftUI hosts: member
  line or upgrade button, paywall sheet, refresh on appear.
  It snapshots the store into `@State` like `PaywallView`
  does (the store is not an `ObservableObject` — this target
  compiles on Linux, where Combine does not exist).
- **No new gate.** The section presents the paywall and
  shows Pro status. No feature is gated here: Legacy gated
  nothing behind Pro either (§3), and no gate is invented.
  The six paywall features remain ungated promises (§10.2
  gap 2, unchanged).

### 12.2 Entry points that present the paywall (updated)

§3 listed two Legacy entry points. In the destination they
are now: the Settings Pro section (AppKit General pane,
this wave) and the developer debug views
(`PaywallDebugViews`, Wave 13). Nothing presents the
paywall automatically on launch, on feature use, or after a
trial period — unchanged from Legacy. There is still no
trial, no usage counter, and no "Pro required" alert.

### 12.3 What is still pending

- **Linux/SwiftUI Settings — WIRED by the Wave 15 coordinator.**
  `"SwiftCodePaywall"` was added to the `swiftcode-ide` executable
  target's dependencies in `swiftcode/Package.swift` (both the Linux
  and macOS branches), and a "SwiftCode Pro" section using the
  already-built `ProSettingsSection` view was added at the end of
  the SwiftUI General pane (`swiftcode/Sources/swiftcode-ide/
  SettingsPanes.swift`). On Linux the section shows the upgrade
  button and a paywall that cannot load products (every StoreKit
  operation fails honestly with
  `PaywallError.storeKitUnavailable`).
- **Mac build/test.** No Swift toolchain in this
  environment: `swift build` / `swift test`, the Settings
  snapshot render (`settings-general.png`), and any live
  purchase test stay pending on Dylan's Mac. The
  `SettingsR33Tests.generalPaneRowsAndDefaults` expectation
  was updated for the two new rows (`"# SwiftCode Pro"`,
  `"SwiftCode Pro"`).
- **Dylan decisions.** Unchanged from §10.2: products must
  exist in App Store Connect before end-to-end purchase
  testing (gap 1); whether the six paywall features should
  ever be gated is a product decision, not a port (gap 2).

## Evidence

Per the destination `AGENTS.md` clean-room protocol (rule 4) and
the migration's Legacy carve-out: Legacy is Dylan's own code and
direct porting was authorised by Dylan under MIT, so this spec was
derived from Legacy source read directly, plus the destination's
own specs and public framework documentation. No reference Xcode
copy, Ghidra, simulator IPSW, `research/dirty/`, or Apple
Xcode/Simulator observation was opened, read, or run. No Legacy
file was edited; no commit or push was made.

| Claim | Evidence |
|---|---|
| Product IDs `swiftcode.pro.monthly` / `swiftcode.pro.yearly` / `swiftcode.pro.lifetime` are local constants; name/price/description come from App Store Connect via `Product.products(for:)` | Legacy `SwiftCode/Backend/Store/StoreKitManager.swift` (98 lines), read directly, level 2 (Dylan's own source) |
| Entitlement = any verified current entitlement OR `bypass_paywall`; only gate is Settings Pro section; six paywall features ungated | `EntitlementManager.swift` (22 lines), `FeatureFlags.swift`, `GeneralSettingsView.swift:1880-1896`, `PaywallView.swift` (143 lines), plus repo-wide grep for `isProUser`/`proAccess`/`bypass_paywall` (8 files), level 2 |
| Purchase / restore / transaction-observation / verification flows; `showManageSubscriptions` has no callers; no server receipt check | `StoreKitManager.swift`, `AppStore.swift` (34 lines); grep for `verifyReceipt`/`appstoreconnect`/`sharedSecret` over the three Store dirs (0 hits), level 2 |
| Paywall UI structure, features list, loading/refresh/restore behaviour | `PaywallView.swift`, read directly, level 2 |
| StoreKit editor window/toolbar/split layout, session/undo/recents/templates | `StoreKitWindowController.swift` (173), `StoreKitWindowManager.swift` (43), `StoreKitSplitViewController.swift` (212), `StoreKitWorkspaceManager.swift` (239), read directly, level 2 |
| `.storekit` model shapes, defaults, decoder field loss, format mismatches | `StoreKitModels.swift` (587), read directly, level 2; mismatches vs `specs/frameworks/storekit/configuration-file.md` (levels 2–3) |
| Parser/encoder contract (JSONDecoder, pretty/sorted, atomic write) | `StoreKitParser.swift` (24), `StoreKitEncoder.swift` (26), level 2 |
| All 21 editor sections and their behaviours (incl. fake asset scan, fake version history, unwired palette, constant baseline compare, local-only storefront table) | `StoreKitEditors.swift` (2,060 lines, 22 views) — full outline + targeted section reads, level 2 |
| Sidebar sections/badges, inspector editing incl. undo push per edit | `StoreKitSidebarView.swift` (202), `StoreKitInspectorView.swift` (281), level 2 |
| Simulator state machine, profiles, persistence files, lifecycle actions, 30-day renewal simplification | `StoreKitSimulationService.swift` (352), level 2 |
| Validation rules, health-score formula, products-only fixes, no-op capability fixes, always-true capability checks | `StoreKitValidationService.swift` (334) + `applyFix` in `StoreKitEditors.swift:881`, level 2 |
| Protocols file is 22 near-empty singletons | `StoreKitProtocols.swift` (128), level 2 |
| Debug views only flip the boolean / present the paywall | `PaywallDebugView.swift` (41), `StoreKitDebugView.swift` (38), level 2 |
| Entitlements manager I/O + validation + raw XML; 17-entry metadata catalog | `EntitlementsEditorManager.swift` (725) — models + method list + validation outline, level 2 |
| 128 capability definitions, 9 sections, payload kinds, toggle-writes-key contract | `EntitlementsEditorCatalog.swift` (1,374) — `grep -c 'CapabilityDefinition('` = 128, level 2 |
| Entitlements view behaviour (UI-only, search/filter, save/revert, dirty, sub-editors, opened from EditorView/XcodeProjTabs) | `EntitlementsEditorView.swift` (1,625) — structure + save/revert + sub-editor list, level 2 |
| `SDKEntitlement` deferred: key-bound, two v1 IDs, application-flow grant only | `SDKEntitlement.swift` (72), read directly, level 2 |
| `frameworks/storekit` products/targets and key API names | `frameworks/storekit/Package.swift` + `grep public` over `Sources/StoreKitConfiguration/`, `Sources/StoreKitEngine/`, `Sources/StoreKit/`, `Sources/StoreKitSigning/`, `Sources/StoreKitTest/`, level 1 (destination's own clean-room source) |
| `SwiftCodeSigning` entitlement value/policy API | `swiftcode/Sources/SwiftCodeSigning/EntitlementPolicy.swift`, `EntitlementValue.swift`, read directly, level 1 |
| No storekit dependency in `swiftcode/Package.swift` today; swiftui path-dependency precedent (lines ~287–320) | `grep -i storekit swiftcode/Package.swift` (0 hits); `sed -n '270,330p' swiftcode/Package.swift`, level 1 |
| No StoreKit editor / paywall / Pro entitlement in the destination | `grep -rniE 'paywall\|isPro\|StoreKitEditor\|\.storekit'` over destination sources/specs (only framework files + unrelated hits), level 1 |
| Canonical `.storekit` format (identifier, version object, `displayPrice` string, `RecurringSubscription`, settings keys, synchronized-file keys) | `specs/frameworks/storekit/configuration-file.md` + `specs/frameworks/storekit/ide.md` §3, levels 2–3 |
| No `.storekit` file exists in Legacy; `SKTestSession` has zero Legacy references | `find -name '*.storekit'` (0 files); `grep -rn SKTestSession` (0 hits), level 2 |

## Implementation inventory

Every in-scope Legacy file → disposition and recommended destination.
"PORT" = port the behaviour (adapted to the destination host system);
"ADAPT" = port with a format/model change noted in §6.3/§7;
"DEFER" = belongs to a later wave; "DROP" = do not port, reason given.
No implementation code, tests, or `Package.swift` edits are part of
this spec slice.

> **Wave 13 reconciliation note (coordinator):** the "Destination"
> column below was corrected after implementation landed. The spec
> originally recommended one combined `SwiftCodeStoreKit` target; the wave
> landed `SwiftCodePaywall` for the Pro runtime and `SwiftCodeIDECore/Model`
> (+ `SwiftCodeUI` controllers + `swiftcode-ide` views) for the editors, and
> the StoreKit window chrome was not reproduced (the SwiftCode workspace
> window hosts the editor instead). The simulation service landed as
> a local port (`StoreKitSimulationSession`), not re-implemented over
> `AppTestStore` / `SKTestSession` as §6.6b recommended — that engine
> mapping is a follow-up. **Wave 15 update:** the Settings
> Pro-section paywall presentation hook is now wired in the
> AppKit Settings (§12) — the macOS General pane's
> "SwiftCode Pro" section presents the paywall; the
> Linux/SwiftUI Settings wiring is still pending (needs a
> `Package.swift` dependency, §12.3).

| Legacy file | Lines | Disposition | Destination file / target (recommended) |
|---|---|---|---|
| `SwiftCode/Backend/Store/StoreKitManager.swift` | 98 | PORT | `SwiftCodePaywall/PaywallStore.swift` (Apple StoreKit 2; product IDs as configuration in `PaywallProductCatalog.swift`) + `PaywallError.swift` |
| `SwiftCode/Backend/Store/EntitlementManager.swift` | 22 | PORT | `SwiftCodePaywall/PaywallEntitlement.swift` (Pro boolean; `bypass_paywall` OR preserved) + `PaywallBypass.swift` |
| `SwiftCode/Backend/Store/AppStore.swift` | 34 | PORT | `SwiftCodePaywall/PaywallAppStore.swift` (`sync()` → Apple `StoreKit.AppStore.sync()`; manage-subscriptions → subscriptions URL on macOS; iOS sheet not ported — no window scene in a library target) |
| `SwiftCode/Views/Utilities/StoreKit/Models/StoreKitModels.swift` | 587 | ADAPT | Model shapes → `StoreKitConfiguration.StoreConfiguration` / `ConfiguredProduct` / `SubscriptionGroup` / `Offer` / `Settings` (framework, already exists — do not re-create). Legacy-only extras → `SwiftCodeIDECore/Model/StoreKitEditorModel.swift` + `StoreKitSimulationSession.swift` as editor/simulator support types |
| `SwiftCode/Views/Utilities/StoreKit/Parsers/StoreKitParser.swift` | 24 | DROP — superseded | `StoreKitConfiguration.StoreConfigurationFile.init(contentsOf:)` / `init(data:)` (framework). Preserve the parse-from-data/URL/string contract, not the code |
| `SwiftCode/Views/Utilities/StoreKit/Encoders/StoreKitEncoder.swift` | 26 | DROP — superseded | `StoreKitConfigurationFile.data()` / `.write(to:)` (framework, canonical `"key" : value` form). Preserve the atomic-write contract, not the `JSONEncoder` output |
| `SwiftCode/Views/Utilities/StoreKit/Protocols/StoreKitProtocols.swift` | 128 | DROP — 22 near-empty singletons | Nothing. Session/service seams live in `SwiftCodePaywall` / `SwiftCodeIDECore` models |
| `SwiftCode/Views/Utilities/StoreKit/Managers/StoreKitWorkspaceManager.swift` | 239 | PORT | `SwiftCodeIDECore/Model/StoreKitEditorModel.swift` (session, 50-deep whole-config undo/redo, recents, 5 templates, default workspace) |
| `SwiftCode/Views/Utilities/StoreKit/Services/StoreKitSimulationService.swift` | 352 | ADAPT | `SwiftCodeIDECore/Model/StoreKitSimulationSession.swift` — DEVIATION: landed as a local port of Legacy's service, NOT re-implemented over `AppTestStore` / `SKTestSession` as §6.6b recommended; engine mapping is a follow-up. Log/activity API, profiles, favorites, filters kept |
| `SwiftCode/Views/Utilities/StoreKit/Services/StoreKitValidationService.swift` | 334 | PORT | Validation inside `SwiftCodeIDECore/Model/StoreKitEditorModel.swift` (rules + health score + fixes). Legacy's always-`true` capability checks are not reproduced (§6.7 — they never fired) |
| `SwiftCode/Views/Utilities/StoreKit/Editors/StoreKitEditors.swift` | 2,060 | PORT (with the §10.2 cuts) | Model `SwiftCodeIDECore/Model/StoreKitEditorModel.swift`; AppKit `SwiftCodeUI/Editor/StoreKitEditorController.swift`; SwiftUI `swiftcode-ide/StoreKitEditorView.swift` (views bind the model directly — no separate SwiftCodeIDEShell view model landed). 21 sections; the fake asset scan, fake version-history seeds, unwired palette actions, constant-baseline compare, and local-only storefront table are dropped as specified; AI generator via SwiftCodeAssistant provider, not `LLMService` |
| `SwiftCode/Views/Utilities/StoreKit/Sidebar/StoreKitSidebarView.swift` | 202 | PORT | Folded into `swiftcode-ide/StoreKitEditorView.swift` + `SwiftCodeUI/Editor/StoreKitEditorController.swift` (no separate sidebar file); section names are an enum; Favorites, recents, live validation badges kept |
| `SwiftCode/Views/Utilities/StoreKit/Inspector/StoreKitInspectorView.swift` | 281 | PORT | Folded into `swiftcode-ide/StoreKitEditorView.swift` + `SwiftCodeUI/Editor/StoreKitEditorController.swift` (no separate inspector file); product picker + identity/pricing/review-metadata sections; edits push undo snapshots; hardcoded fake review notes / mock screenshot rows dropped |
| `SwiftCode/Views/Utilities/StoreKit/Windows/StoreKitWindowController.swift` | 173 | PORT | NOT reproduced — Legacy's standalone StoreKit window chrome has no destination; the SwiftCode workspace window hosts the editor instead |
| `SwiftCode/Views/Utilities/StoreKit/Windows/StoreKitWindowManager.swift` | 43 | PORT | NOT reproduced — same as above; window management is the SwiftCode workspace's |
| `SwiftCode/Views/Utilities/StoreKit/Workspace/StoreKitSplitViewController.swift` | 212 | PORT | NOT reproduced as a standalone split view — the editor lives in the SwiftCode workspace window; the editor view itself carries the sidebar/inspector layout |
| `SwiftCode/Views/Paywall/PaywallView.swift` | 143 | PORT | `SwiftCodePaywall/PaywallView.swift` (SwiftUI, SwiftCode style, no orange/crown/liquid-glass Legacy styling); model `SwiftCodePaywall/PaywallStore.swift`. Presented from the AppKit Settings Pro section (Wave 15, §12) and the debug view — the Linux/SwiftUI Settings hook is NOT yet wired (needs a `Package.swift` dependency, §12.3) |
| `SwiftCode/Views/Developer/PaywallDebug/PaywallDebugView.swift` | 41 | PORT | `SwiftCodePaywall/PaywallDebugViews.swift` (developer surface; grant/revoke + force-show paywall, honestly labelled local-only overrides) |
| `SwiftCode/Views/Developer/StoreKitDebug/StoreKitDebugView.swift` | 38 | PORT | `SwiftCodePaywall/PaywallDebugViews.swift` (4 simulations, honestly labelled local-only overrides — they never create transactions) |
| `SwiftCode/Core/Editor/EntitlementsEditorManager.swift` | 725 | PORT | `SwiftCodeIDECore/Model/EntitlementsEditorModel.swift` (plist I/O via `SwiftCodeSigning.EntitlementValue`, sorted-key XML write, validation + cross-entitlement rules, raw-XML generation); 17-entry manager catalog subsumed (verified). The 4 empty stub structs are dropped |
| `SwiftCode/Views/Editor/EntitlementsEditorCatalog.swift` | 1,374 | PORT | `SwiftCodeIDECore/Model/EntitlementsCatalog.swift` (`EntitlementCapabilityCatalog`, 9 sections, `CapabilityPayloadKind`, 123 unique `CapabilityDefinition`s — 5 duplicate raw keys deduped, first kept) |
| `SwiftCode/Views/Editor/EntitlementsEditorView.swift` | 1,625 | PORT | AppKit `SwiftCodeUI/Editor/EntitlementsEditorController.swift` + SwiftUI `swiftcode-ide/EntitlementsEditorView.swift` (views bind the model directly — no separate SwiftCodeIDEShell view model landed): UI-only `.entitlements` editor (search, section filter, capability toggles writing real keys, sub-editors, save/revert, dirty tracking, live validation). `.entitlements` file-open wiring is a follow-up |
| `SwiftCode/SDK/Host/APIKeys/SDKEntitlement.swift` | 72 | DEFER — SDK-platform wave | Later SDK wave (capability broker / API keys / Assist access application flow). Not StoreKit, not the paywall, not the entitlements editor (§9) |
