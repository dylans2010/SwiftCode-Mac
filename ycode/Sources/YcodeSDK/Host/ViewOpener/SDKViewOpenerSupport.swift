import Foundation

// MARK: - SDKViewOpenerSupport
//
// Ported from Legacy `SwiftCode/SDK/Host/ViewOpener/SDKViewOpenerSupport.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Support types for view openers: the active-project resolver (openers
// that need a project) and the generic hosted-window type (openers that
// present their own window).
//
// Legacy resolved the active project from the app's `ProjectSessionStore`;
// Ycode has no such seam, so the resolver delegates to an injectable
// `SDKActiveWorkspaceProviding` (installed by YcodeUI/YcodeWorkspace).
// With no provider installed, project-requiring openers throw
// `.projectNotOpen` — honestly, never a fabricated project.

/// Provides the active workspace's project root for view openers that
/// need a project. Installed by the host UI at startup.
public protocol SDKActiveWorkspaceProviding: Sendable {
    /// The active project's root directory, or `nil` when none is open.
    func activeProjectRoot() async -> URL?
}

/// Holds the installed active-workspace provider (or none).
public final class SDKActiveWorkspaceRegistry: @unchecked Sendable {
    public static let shared = SDKActiveWorkspaceRegistry()

    public var provider: (any SDKActiveWorkspaceProviding)?

    private init() {}
}

/// Resolves the active project for view openers.
@MainActor
public enum SDKActiveProjectResolver {
    /// The active project's root, or `.projectNotOpen` when no project
    /// is open (or no provider is installed).
    public static func activeProjectRoot() async throws -> URL {
        guard let root = await SDKActiveWorkspaceRegistry.shared.provider?.activeProjectRoot() else {
            throw SDKError(code: .projectNotOpen, message: "No project is open.")
        }
        return root
    }
}

#if os(macOS) && canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// A generic hosted window: an `NSWindow` presenting SwiftUI content.
/// Openers that own their window (rather than delegating to the host
/// seam) use this. The window reference is cleared on close.
@MainActor
public final class SDKHostedWindow<Content: View> {
    private var window: NSWindow?

    public init() {}

    /// Shows `content` in a window titled `title`, sized `size`
    /// (with `minSize` as the minimum). Reuses the existing window
    /// when already shown.
    public func show(
        title: String,
        content: Content,
        size: NSSize,
        minSize: NSSize,
        autosaveName: String? = nil
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.setContentSize(size)
        window.minSize = minSize
        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }
        window.delegate = SDKHostedWindowCloseHandler { [weak self] in
            Task { @MainActor in
                self?.window = nil
            }
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    public func close() {
        window?.close()
        window = nil
    }
}

private final class SDKHostedWindowCloseHandler: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
#endif
