import AppKit
import SwiftUI

@MainActor
public final class VirtualizationWindowManager: NSObject, NSWindowDelegate {
    public static let shared = VirtualizationWindowManager()
    private var windowController: VirtualizationWindowController?

    public func showWindow(for project: Project) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = VirtualizationWindowController()
        wc.window?.delegate = self
        self.windowController = wc
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

@MainActor
public final class VirtualizationWindowController: NSWindowController {

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Virtualization Console"
        window.minSize = NSSize(width: 1050, height: 700)
        window.setFrameAutosaveName("VirtualizationMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let splitVC = VirtualizationSplitViewController()
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "VirtualizationToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
    }
}

extension VirtualizationWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .startVM:
            item.label = "Start VM"
            item.paletteLabel = "Start VM"
            item.toolTip = "Start the selected virtual machine"
            item.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(startSelectedVM(_:))

        case .stopVM:
            item.label = "Stop VM"
            item.paletteLabel = "Stop"
            item.toolTip = "Stop/shutdown the selected virtual machine"
            item.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(stopSelectedVM(_:))

        case .restartVM:
            item.label = "Restart"
            item.paletteLabel = "Restart"
            item.toolTip = "Restart the selected virtual machine"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(restartSelectedVM(_:))

        case .createWizard:
            item.label = "New Environment"
            item.paletteLabel = "New Environment"
            item.toolTip = "Open VM wizard to create a new development environment"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(openCreationWizard(_:))

        default:
            return nil
        }
        return item
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.createWizard, .flexibleSpace, .startVM, .stopVM, .restartVM]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.createWizard, .startVM, .stopVM, .restartVM, .flexibleSpace, .space]
    }
}

extension NSToolbarItem.Identifier {
    public static let startVM = NSToolbarItem.Identifier("startVM")
    public static let stopVM = NSToolbarItem.Identifier("stopVM")
    public static let restartVM = NSToolbarItem.Identifier("restartVM")
    public static let createWizard = NSToolbarItem.Identifier("createWizard")
}

extension VirtualizationWindowController {
    @objc private func startSelectedVM(_ sender: Any?) {
        guard let vmID = VirtualizationStateStore.shared.selectedVMID else { return }
        Task {
            let controller = SCVirtualizationEngine.shared.createController(for: vmID)
            await controller.start()
        }
    }

    @objc private func stopSelectedVM(_ sender: Any?) {
        guard let vmID = VirtualizationStateStore.shared.selectedVMID else { return }
        Task {
            let controller = SCVirtualizationEngine.shared.createController(for: vmID)
            await controller.stop()
        }
    }

    @objc private func restartSelectedVM(_ sender: Any?) {
        guard let vmID = VirtualizationStateStore.shared.selectedVMID else { return }
        Task {
            let controller = SCVirtualizationEngine.shared.createController(for: vmID)
            await controller.restart()
        }
    }

    @objc private func openCreationWizard(_ sender: Any?) {
        VirtualizationStateStore.shared.showCreateWizard = true
    }
}
