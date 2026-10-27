//
//  NativeSettingsWindowController.swift
//  SwiftCode
//
//  Created by Dylan on 10/27/26.
//

import SwiftUI
import AppKit

// MARK: - Native Safari Settings Window Controller

@MainActor
public final class NativeSettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    public static let shared = NativeSettingsWindowController()

    public var selectedCategory: SettingsCategory {
        get { NativeSettingsState.shared.selectedCategory }
        set {
            NativeSettingsState.shared.selectedCategory = newValue
            updateCategoryUI()
        }
    }

    public var isWindowOpen: Bool {
        window?.isVisible == true
    }

    public init() {
        let contentRect = NSRect(
            x: 100,
            y: 100,
            width: NativeSettingsLayout.width,
            height: NativeSettingsLayout.height
        )
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: NativeSettingsLayout.width, height: NativeSettingsLayout.height)
        window.setContentSize(NSSize(width: NativeSettingsLayout.width, height: NativeSettingsLayout.height))
        window.setFrameAutosaveName("NativeSafariSettingsWindow")
        window.title = SettingsCategory.general.title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference
        window.titlebarSeparatorStyle = .line
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed]

        super.init(window: window)
        window.delegate = self

        setupToolbar(for: window)

        // Single persistent contentViewController hosting NativeSettingsContainerView
        // reacting to NativeSettingsState.shared so the window frame never collapses
        let containerView = NativeSettingsContainerView(state: NativeSettingsState.shared)
            .environmentObject(AppSettings.shared)

        let hostingController = NSHostingController(
            rootView: StylingBootstrap.configureEnvironment(containerView)
        )
        hostingController.sizingOptions = []
        hostingController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: NativeSettingsLayout.width,
            height: NativeSettingsLayout.height
        )
        hostingController.view.autoresizingMask = [.width, .height]
        window.contentViewController = hostingController
        updateCategoryUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Toolbar Setup

    private func setupToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "NativeSafariSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = selectedCategory.toolbarIdentifier
        window.toolbar = toolbar
        window.titlebarSeparatorStyle = .line
        window.titlebarAppearsTransparent = false
    }

    // MARK: - Category UI Updating

    private func updateCategoryUI() {
        guard let window = self.window else { return }

        // Centered window title displaying the selected category name
        window.title = selectedCategory.title

        // Update toolbar selection highlight to match category
        if window.toolbar?.selectedItemIdentifier != selectedCategory.toolbarIdentifier {
            window.toolbar?.selectedItemIdentifier = selectedCategory.toolbarIdentifier
        }

        // Ensure window always preserves the set dimensions
        window.setContentSize(NSSize(width: NativeSettingsLayout.width, height: NativeSettingsLayout.height))
    }

    // MARK: - Public Window Management Methods

    public func showWindow(category: String? = nil) {
        if let categoryString = category,
           let matchedCategory = SettingsCategory.allCases.first(where: {
               $0.rawValue.caseInsensitiveCompare(categoryString) == .orderedSame ||
               $0.title.caseInsensitiveCompare(categoryString) == .orderedSame
           }) {
            self.selectedCategory = matchedCategory
        } else {
            updateCategoryUI()
        }

        guard let window = self.window else { return }

        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: NativeSettingsLayout.width, height: NativeSettingsLayout.height))

        // Find active app root / main window (WelcomeView or WorkspaceHostView)
        let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0 != window && !($0 is NSPanel) })

        if let main = mainWindow {
            if !window.isVisible {
                let mainFrame = main.frame
                let settingsWidth = NativeSettingsLayout.width
                let settingsHeight = NativeSettingsLayout.height
                let originX = mainFrame.origin.x + (mainFrame.width - settingsWidth) / 2.0
                let originY = mainFrame.origin.y + (mainFrame.height - settingsHeight) / 2.0
                let targetFrame = NSRect(x: originX, y: originY, width: settingsWidth, height: settingsHeight)
                window.setFrame(targetFrame, display: true)
            }
            window.order(.above, relativeTo: main.windowNumber)
        } else if !window.isVisible {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeWindow() {
        guard let window = self.window, window.isVisible else { return }
        window.orderOut(nil)
    }

    // MARK: - NSToolbarDelegate

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsCategory.allCases.map { $0.toolbarIdentifier }
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsCategory.allCases.map { $0.toolbarIdentifier }
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsCategory.allCases.map { $0.toolbarIdentifier }
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let category = SettingsCategory.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = category.title
        item.paletteLabel = category.title
        item.toolTip = category.title
        item.image = NSImage(systemSymbolName: category.icon, accessibilityDescription: category.title)
        item.target = self
        item.action = #selector(categoryToolbarItemClicked(_:))
        return item
    }

    @objc private func categoryToolbarItemClicked(_ sender: NSToolbarItem) {
        if let category = SettingsCategory.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) {
            self.selectedCategory = category
        }
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing the settings window hides it and never terminates or closes the main app window
        sender.orderOut(nil)
        return false
    }
}
