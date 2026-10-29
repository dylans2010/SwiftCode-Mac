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
public final class NativeSettingsWindowController: NSWindowController, NSWindowDelegate {
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

        window.minSize = NSSize(width: 880, height: 480)
        window.maxSize = NSSize(width: 10000, height: 10000)
        window.setContentSize(NSSize(width: NativeSettingsLayout.width, height: NativeSettingsLayout.height))
        window.setFrameAutosaveName("NativeSafariSettingsWindow")
        window.title = SettingsCategory.general.title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed]

        // Explicitly ensure standard window buttons are enabled and not hidden
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isEnabled = true

        super.init(window: window)
        window.delegate = self

        // No NSToolbar: the centered in-content tab bar in
        // NativeSettingsContainerView shows every category at once.
        window.toolbar = nil

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

    // MARK: - Category UI Updating

    private func updateCategoryUI() {
        guard let window = self.window else { return }

        // Centered window title displaying the selected category name
        window.title = selectedCategory.title

        // Do not reset window.setContentSize to fixed dimensions here to preserve user resizing (this window never enters fullscreen)
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
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.collectionBehavior = [.managed]
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isEnabled = true

        if !window.isVisible {
            let settingsWidth = NativeSettingsLayout.width
            let settingsHeight = NativeSettingsLayout.height

            let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0 != window && !($0 is NSPanel) })
            if let main = mainWindow {
                let mainFrame = main.frame
                let originX = mainFrame.origin.x + (mainFrame.width - settingsWidth) / 2.0
                let originY = mainFrame.origin.y + (mainFrame.height - settingsHeight) / 2.0
                let targetFrame = NSRect(x: originX, y: originY, width: settingsWidth, height: settingsHeight)
                window.setFrame(targetFrame, display: true)
            } else {
                window.setContentSize(NSSize(width: settingsWidth, height: settingsHeight))
                window.center()
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeWindow() {
        guard let window = self.window, window.isVisible else { return }
        window.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing the settings window hides it and never terminates or closes the main app window
        sender.orderOut(nil)
        return false
    }
}
