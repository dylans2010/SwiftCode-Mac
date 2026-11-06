// ExtV2Manager.swift
//
// Legacy-name aliases for the rebuilt Extensions v2 manager.
//
// Legacy `SwiftCode/Backend/Extensions v2/Core/ExtV2Manager.swift` was NOT
// ported verbatim: its behaviour already lives in the rebuilt
// `ExtensionManager` (same target, same shape — singleton, @MainActor,
// installed/search/updates/contributions/settings, `ensureReady()`).
// The two behaviours Audit A flagged as missing from the rebuild are
// already there: `registerAssistCommands` is called from
// `ExtensionManager.activate` and defined at `ExtensionManager:366`,
// and the private `upsert` helper's behaviour exists inline in
// `install`/`setEnabled` via `persistInstalled()`.
// Porting the Legacy class as well would duplicate the manager and
// reference ~28 `ExtV2*` types that do not exist in this target.
//
// So the Legacy names resolve to the rebuilt types. The view layer
// (`SwiftCodeUI/Extensions/ExtensionViewModels.swift`,
// `swiftcode-ide/Extension*View.swift`) uses `ExtV2Manager.shared`,
// `ExtV2InstalledExtension`, and `ExtV2ExtensionMetadata`; those now
// resolve here. `ExtV2Contribution` is intentionally NOT aliased:
// it already exists as its own struct in `ExtV2VSCodeAPI.swift`, and
// `ExtensionContribution` is the canonical contribution type —
// `ExtV2RunViewModel.State.ready` carries `ExtensionContribution`.

import Foundation

/// The Extensions v2 lifecycle owner. See the file header: this is the
/// rebuilt `ExtensionManager`, kept under its Legacy name for the view
/// layer. ObservableObject so `@ObservedObject` views keep working.
public typealias ExtV2Manager = ExtensionManager

/// An installed extension record. See the file header.
public typealias ExtV2InstalledExtension = InstalledExtension

/// The user-visible lifecycle state. Legacy `ExtV2State` is the production
/// `ExtensionState` (same 10 cases, same `displayName` — verified in
/// `Models.swift:46`). Used by `ExtensionSidebarRow` (ported from Legacy
/// `Views/Extensions v2/`).
public typealias ExtV2State = ExtensionState

/// Extension metadata (registry record). See the file header.
public typealias ExtV2ExtensionMetadata = ExtensionMetadata

/// Extension identity (`publisher.name`). Legacy `ExtV2Identity` is the
/// production `ExtensionIdentity` (same fields, same init — verified in
/// `Models.swift:6`).
public typealias ExtV2Identity = ExtensionIdentity

/// Capability vocabulary. Legacy `ExtV2Capability` is the production
/// `ExtensionCapability` (same 12 cases, same `displayName` — verified in
/// `Capabilities.swift:5`).
public typealias ExtV2Capability = ExtensionCapability

/// JSON value vocabulary. Legacy `ExtV2JSONValue` is the production
/// `JSONValue` (same seven cases, same decode order — verified in
/// `JSONValue.swift:9`).
public typealias ExtV2JSONValue = JSONValue
