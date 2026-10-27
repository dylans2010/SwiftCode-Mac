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

    public var selectedCategory: SettingsCategory = .general {
        didSet {
            updateContent()
        }
    }

    public var isWindowOpen: Bool {
        window?.isVisible == true
    }

    public init() {
        let contentRect = NSRect(x: 100, y: 100, width: 820, height: 640)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: 760, height: 520)
        window.setFrameAutosaveName("NativeSafariSettingsWindow")
        window.title = SettingsCategory.general.title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed]

        super.init(window: window)
        window.delegate = self

        setupToolbar(for: window)
        updateContent()
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
    }

    // MARK: - Content Updating

    private func updateContent() {
        guard let window = self.window else { return }

        // Centered window title displaying the selected category name
        window.title = selectedCategory.title

        // Update toolbar selection highlight to match category
        if window.toolbar?.selectedItemIdentifier != selectedCategory.toolbarIdentifier {
            window.toolbar?.selectedItemIdentifier = selectedCategory.toolbarIdentifier
        }

        // Host the SwiftUI content view wrapped in StylingBootstrap
        let containerView = NativeSettingsContainerView(selectedCategory: selectedCategory)
            .environmentObject(AppSettings.shared)

        let hostingController = NSHostingController(
            rootView: StylingBootstrap.configureEnvironment(containerView)
        )
        hostingController.sizingOptions = []
        hostingController.view.autoresizingMask = [.width, .height]
        window.contentViewController = hostingController
    }

    // MARK: - Public Window Management Methods

    public func showWindow(category: String? = nil) {
        if let categoryString = category,
           let matchedCategory = SettingsCategory.allCases.first(where: {
               $0.rawValue.caseInsensitiveCompare(categoryString) == .orderedSame ||
               $0.title.caseInsensitiveCompare(categoryString) == .orderedSame
           }) {
            self.selectedCategory = matchedCategory
        }

        guard let window = self.window else { return }

        if !window.isVisible {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeWindow() {
        window?.performClose(nil)
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
        true
    }
}
