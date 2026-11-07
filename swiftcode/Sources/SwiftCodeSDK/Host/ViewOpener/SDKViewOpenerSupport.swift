import Foundation

public protocol SDKActiveWorkspaceProviding: Sendable {
    func activeProjectRoot() async -> URL?
}

public final class SDKActiveWorkspaceRegistry: @unchecked Sendable {
    public static let shared = SDKActiveWorkspaceRegistry()

    public var provider: (any SDKActiveWorkspaceProviding)?

    private init() {}
}

@MainActor
public enum SDKActiveProjectResolver {
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

@MainActor
public final class SDKHostedWindow<Content: View> {
    private var window: NSWindow?

    public init() {}

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
