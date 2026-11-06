import Foundation

// MARK: - SDKViewOpener
//
// Ported from Legacy `SwiftCode/SDK/Host/ViewOpener/SDKViewOpener.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The view-opener registry: extensions open host views by ID through
// `ui.openView`, and the registry maps IDs to host-provided openers.
// The registry performs NO authorization — the IPC dispatcher
// authorizes the view's own capability before calling `open`.
//
// ADAPTATION: Legacy's `ViewOpener` was a synchronous closure. The
// Ycode host seam is asynchronous (window presentation may await the
// workspace), so the opener is `async throws` here.

/// An opener for one host view. Runs on the main actor (it presents UI).
public typealias ViewOpener = @MainActor @Sendable () async throws -> Void

public actor SDKViewOpener {
    public static let shared = SDKViewOpener()

    private var openers: [String: ViewOpener] = [:]

    private init() {}

    /// Registers an opener for `viewID`. Last registration wins; there
    /// is no unregister — views stay openable for the host's lifetime.
    public func register(viewID: String, opener: @escaping ViewOpener) {
        openers[viewID] = opener
    }

    public func isRegistered(viewID: String) -> Bool {
        openers[viewID] != nil
    }

    /// Opens a registered view. Unregistered → `.serviceUnavailable`.
    /// The opener's own typed error propagates unchanged.
    public func open(viewID: String) async throws {
        guard let opener = openers[viewID] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The view “\(viewID)” is not available.",
                suggestion: "The host has not registered an opener for this view."
            )
        }
        try await opener()
    }
}

// MARK: - SDKViewHost
//
// The YcodeUI seam every view opener delegates to. YcodeUI installs its
// implementation at startup; until then every open throws
// `.serviceUnavailable` naming the missing seam — honestly, never a
// fake window.
//
// Legacy's built-in openers drove Legacy app window managers
// (`DatabaseExplorerWindowManager`, …) and toolbar-notification
// bridges (`ToolbarActionManager`, `com.swiftcode.toolbarToolActivated`)
// that do not exist in Ycode. Those managers are NOT re-ported here:
// the opener logic (view ID → host open call, project requirement)
// is ported, and the actual window is the host's job behind this seam.

/// The host UI's side of view opening. One method, dispatched by view
/// ID — the host owns the mapping from SDK view IDs to its windows.
public protocol SDKViewHost: Sendable {
    func open(viewID: String) async throws
}

/// Holds the installed host UI seam (or none).
public final class SDKViewHostRegistry: @unchecked Sendable {
    public static let shared = SDKViewHostRegistry()

    /// Installed by YcodeUI at startup. `nil` until then.
    public var host: (any SDKViewHost)?

    private init() {}

    /// Opens `viewID` through the installed host, or throws
    /// `.serviceUnavailable` naming the missing seam.
    public func open(viewID: String) async throws {
        guard let host else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The view “\(viewID)” is not available.",
                suggestion: "The host UI has not installed a view host for this view yet."
            )
        }
        try await host.open(viewID: viewID)
    }

    /// Opens the Assist main view through the installed host.
    public func openAssistMainView() async throws {
        try await open(viewID: SDKAssistUIOpener.assistMainViewID)
    }
}
