import AppKit
import SwiftCodeIDECore

/// The toolbar's Extensions button + popover (spec
/// `extensions-platform.md` §1.2): Extensions sits on the editor
/// toolbar beside Assist (the editor-modes segment), not in the
/// workspace sidebar.
final class ExtensionsPanelHolder: NSObject, NSPopoverDelegate {
    var controller: ExtensionsPanelViewController?
    var popover: NSPopover?

    func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            controller = nil
            popover = nil
        }
    }
}

extension WorkspaceWindowController {
    /// The open Extensions panel, if any (tests drive it).
    public var extensionsPanel: ExtensionsPanelViewController? { extensionsPanelHolder.controller }

    /// The toolbar's Extensions button: toggles the Extensions popover
    /// anchored to the button (same shape as the New Conversation
    /// prompt in `WorkspaceWindowController+CodingAssistant.swift`).
    @objc public func toggleExtensionsPanel(_ sender: Any?) {
        if let p = extensionsPanelHolder.popover { p.close(); return }
        let c = ExtensionsPanelViewController()
        _ = c.view
        extensionsPanelHolder.controller = c
        guard window?.isVisible == true,
              let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.extensionsID }) else { return }
        let p = NSPopover()
        p.contentViewController = c
        p.contentSize = ExtensionsPanelViewController.size
        p.behavior = .transient
        p.delegate = extensionsPanelHolder
        extensionsPanelHolder.popover = p
        p.show(relativeTo: item)
    }
}
