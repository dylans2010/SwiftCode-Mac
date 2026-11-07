import AppKit
import SwiftCodeIDECore

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
    public var extensionsPanel: ExtensionsPanelViewController? { extensionsPanelHolder.controller }

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
