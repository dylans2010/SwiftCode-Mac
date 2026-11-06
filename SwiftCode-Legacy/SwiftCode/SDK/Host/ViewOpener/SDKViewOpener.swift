import Foundation

// MARK: - SDKViewOpener
//
// Host-side registry mapping view capability IDs to the actions that open
// the app's real views (spec Docs/Intro-to-SDK.md §8.1 platform capabilities,
// wired to the IPC method `ui.openView` in `SDKIPCDispatcher`).
//
// ## Design
//
// A plain registration table: `register(viewID:opener:)` installs an open
// action for one capability ID, `open(viewID:)` runs it. This mirrors the
// `SDKCommandRegistry` ownership model — host-owned mutable state behind
// an actor — but the stored values are main-actor actions instead of data,
// because every opener presents UI.
//
// ## Failure contract (never a silent no-op)
//
// `open(viewID:)` throws a typed `SDKError` instead of doing nothing:
//   - valid capability ID, no opener registered → `.serviceUnavailable`
//     (the view is known but not wired in this build);
//   - an opener that cannot present its view (e.g. no project open for a
//     project-scoped view) → the opener's own typed error propagates
//     (e.g. `.projectNotOpen`).
// The `ui.openView` IPC route projects these onto the wire verbatim.
//
// ## Openers run on the main actor
//
// `ViewOpener` is `@MainActor @Sendable () throws -> Void`. The main-actor
// isolation is required — openers touch `NSWindow`/`NotificationCenter` UI
// paths; the `Sendable` bound is required to store the closure in this
// actor. `open(viewID:)` hops to the main actor to invoke it.
//
// NOTE on the sketched signature: the expansion plan sketched a
// non-throwing opener (`@escaping @MainActor () -> Void`). The registry
// keeps the throwing form instead, because the sibling openers
// (`SDKCIWorkflowViewOpener`, `SDKVirtualizationViewOpener`,
// `SDKLivePreviewViewOpener`) are throwing by design — they surface typed
// errors like `.projectNotOpen` — and a non-throwing table would force
// those errors to be swallowed at registration. Registration of a
// non-throwing opener still works unchanged: any `() -> Void` closure
// converts to `() throws -> Void` implicitly.
//
// ## Authorization
//
// This registry performs NO authorization of its own — exactly like
// `SDKCommandRegistry`. The `ui.openView` route in `SDKIPCDispatcher`
// authorizes the view's own capability ID at `SDKCapabilityBroker` BEFORE
// `open(viewID:)` runs (the `commands.register` precedent). Never call
// `open(viewID:)` from a path that bypasses that gate.
//
// ## Registering more openers (for sibling teams)
//
// The table is public and open for extension — register without touching
// this file. Two patterns:
//
// 1. A plain main-actor action:
//
//        await SDKViewOpener.shared.register(viewID: .docsSearch) {
//            DocumentationBrowserWindowManager.shared.showWindow()
//        }
//
// 2. A throwing opener struct (the sibling pattern — carries its own
//    capability ID and typed errors; see SDKViewOpenerSupport.swift):
//
//        await SDKViewOpener.shared.register(
//            viewID: SDKCIWorkflowViewOpener.capabilityID,
//            opener: { try SDKCIWorkflowViewOpener.open() }
//        )
//
// Rules for new openers:
// - Wire only to entry points that exist in the app module TODAY — never
//   invent a view or a notification name. The audited entry points live in
//   `/tmp/sdk-audit-*.md`; re-verify a name against source before using it.
// - For sheet-presented views, post the app's REAL `.toolbarToolActivated`
//   notification with the EXACT `userInfo["toolID"]` string the app's own
//   `MainToolsView` posts for that surface — see `SDKViewOpenerBuiltIns.swift`.
// - Re-registering an ID replaces the previous opener (last write wins);
//   there is no unregister — openers live for the process lifetime.
//
// ## Bootstrap
//
// `registerBuiltInOpeners()` (SDKViewOpenerBuiltIns.swift) installs the
// ten built-in openers. The host MUST call it once at startup — e.g. from
// the SDK runtime launcher before the first extension session, or from the
// app's SDK bootstrap. Until it runs, every `open(viewID:)` throws
// `.serviceUnavailable`: loud and typed, never a silent no-op.

public actor SDKViewOpener {

    public static let shared = SDKViewOpener()

    /// One view-open action. Main-actor isolated (presents UI), `Sendable`
    /// (stored in this actor), throwing (openers surface typed errors such
    /// as `.projectNotOpen` instead of silently doing nothing).
    public typealias ViewOpener = @MainActor @Sendable () throws -> Void

    /// The registration table: view capability ID → open action.
    private var openers: [SDKCapabilityID: ViewOpener] = [:]

    /// Registers (or replaces) the open action for a view capability ID.
    /// Last write wins; registrations live for the process lifetime.
    ///
    /// - Parameters:
    ///   - viewID: The capability ID from the fixed `SDKCapabilityID`
    ///     registry (e.g. `.dbExploreView`). Must match the manifest
    ///     capability the extension was granted — the IPC layer authorizes
    ///     this exact ID at the broker before the opener runs.
    ///   - opener: The main-actor action that presents the view. Must open
    ///     the app's REAL view (or throw a typed `SDKError`); never a
    ///     silent no-op.
    public func register(viewID: SDKCapabilityID, opener: @escaping ViewOpener) {
        openers[viewID] = opener
    }

    /// Whether an opener is currently registered for `viewID`.
    public func isRegistered(viewID: SDKCapabilityID) -> Bool {
        openers[viewID] != nil
    }

    /// Runs the registered opener for `viewID` on the main actor.
    ///
    /// - Throws: `.serviceUnavailable` when no opener is registered for a
    ///   valid capability ID; otherwise rethrows the opener's own typed
    ///   error. Never silently does nothing.
    public func open(viewID: SDKCapabilityID) async throws {
        guard let opener = openers[viewID] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The host has no opener for view \"\(viewID.rawValue)\".",
                suggestion: "The capability is known, but no view opener is registered for it in this build.",
                diagnostics: ["viewId": viewID.rawValue]
            )
        }
        try await MainActor.run {
            try opener()
        }
    }
}
