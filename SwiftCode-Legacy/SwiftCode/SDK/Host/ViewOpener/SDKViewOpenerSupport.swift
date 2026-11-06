import AppKit
import Foundation
import SwiftUI

// MARK: - SDKViewOpenerSupport
//
// Shared plumbing for the SDK host's view openers
// (SwiftCode/SDK/Host/ViewOpener/). Internal to the SwiftCode module;
// the public surface is the per-capability opener structs
// (SDKCIWorkflowViewOpener, SDKVirtualizationViewOpener,
// SDKLivePreviewViewOpener), each carrying its `SDKCapabilityID` so a
// registry (e.g. the sibling `SDKViewOpener.register(viewID:opener:)`)
// can wire them without knowing opener internals.

// MARK: - SDKActiveProjectResolver

/// Resolves the host app's active project for view openers that need a
/// `Project` value (e.g. `VirtualizationWindowManager.showWindow(for:)`).
///
/// This is deliberately NOT the per-extension project scoping used by the
/// service adapters (`SDKCallerIdentity.projectRootPath`, which is the
/// extension's authorized root). View openers surface host UI, so they
/// resolve the same way the app's own UI does: `ProjectSessionStore.shared`
/// — the exact resolution the app's "Virtualization" menu command uses
/// (SwiftCode/App/AppCommands.swift: `activeProject`, falling back to
/// `projects.first`).
@MainActor
enum SDKActiveProjectResolver {
    /// The currently active project, or the first open project as fallback.
    /// - Throws: `SDKError` with code `.projectNotOpen` (`PROJECT_NOT_OPEN`)
    ///   when SwiftCode has no project open. This is the existing typed
    ///   project-missing error from the fixed SDK error taxonomy
    ///   (SDKErrorCode, ADR §8) — no new code was invented.
    static func resolve() throws -> Project {
        if let active = ProjectSessionStore.shared.activeProject {
            return active
        }
        if let first = ProjectSessionStore.shared.projects.first {
            return first
        }
        throw SDKError(
            code: .projectNotOpen,
            message: "No project is open in SwiftCode.",
            suggestion: "Open a project in SwiftCode and try again."
        )
    }
}

// MARK: - SDKHostedWindow

/// Minimal single-window owner for SDK-opened SwiftUI surfaces.
///
/// Mirrors the established project pattern (`SDKStudioWindowManager`,
/// `VisualUIBuilderWindowManager`, `DatabaseExplorerWindowManager`): one
/// `NSWindow` hosting content through `NSHostingController`, raised with
/// `makeKeyAndOrderFront`, `windowWillClose` clearing the reference so a
/// later open creates a fresh window. Used instead of the app's
/// `WorkspaceView` sheet mechanism because that mechanism is driven by the
/// app's internal `WorkspaceSheet` enum, which SDK code cannot extend
/// without modifying non-SDK app files.
@MainActor
final class SDKHostedWindow<Content: View>: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// Shows the window, creating it on first use. Re-opens bring the
    /// existing window forward and re-host the supplied root view.
    func show(
        rootView: Content,
        title: String,
        size: NSSize,
        autosaveName: String,
        minSize: NSSize? = nil
    ) {
        if let window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        if let minSize { window.minSize = minSize }
        window.setFrameAutosaveName(autosaveName)
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the window if it is open.
    func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
