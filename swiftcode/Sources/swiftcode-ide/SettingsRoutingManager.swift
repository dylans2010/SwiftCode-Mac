// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Settings/SettingsRoutingManager.swift
//
// Verbatim apart from this header and the added imports below. All four
// production APIs it calls were verified to match Legacy's calls exactly:
//   - `NativeSettingsWindowController.shared.showWindow(category:)`,
//     `.showWindow()`, `.closeWindow()`, `.isWindowOpen`
//     (`swiftcode-ide/NativeSettingsWindowController.swift`)
//   - `SettingsWindowManager.shared.showSettings()`, `.focusIfVisible()`,
//     `.closeSettings()`, `.isSettingsOpen` (`SwiftCodeUI/App/SettingsView.swift`)
//   - `AppSettings.shared.useNewSettingsWindow`, which posts the
//     `"UseNewSettingsWindowDidChange"` notification this manager observes
//     (`SwiftCodeAssistant/AppSettings.swift:632`)
// Audit-A's claim that `SettingsLayout.swift` covers this type is wrong:
// that file is pure geometry constants with no routing. No API adaptation
// was needed; nothing was renamed.

import SwiftUI
import AppKit
import SwiftCodeAssistant
import SwiftCodeUI

// MARK: - Settings Routing Manager

@MainActor
public final class SettingsRoutingManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsRoutingManager()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUseNewSettingsWindowDidChange(_:)),
            name: NSNotification.Name("UseNewSettingsWindowDidChange"),
            object: nil
        )
    }

    public func showSettings(category: String? = nil) {
        if AppSettings.shared.useNewSettingsWindow {
            NativeSettingsWindowController.shared.showWindow(category: category)
        } else {
            if !SettingsWindowManager.shared.focusIfVisible() {
                SettingsWindowManager.shared.showSettings()
            }
        }
    }

    @objc private func handleUseNewSettingsWindowDidChange(_ notification: Notification) {
        let useNew: Bool
        if let boolVal = notification.object as? Bool {
            useNew = boolVal
        } else {
            useNew = AppSettings.shared.useNewSettingsWindow
        }

        let isLegacyOpen = SettingsWindowManager.shared.isSettingsOpen
        let isNativeOpen = NativeSettingsWindowController.shared.isWindowOpen

        // Only transition if the user toggled the preference and the active window does not match the chosen experience
        if useNew {
            if isLegacyOpen && !isNativeOpen {
                SettingsWindowManager.shared.closeSettings()
                NativeSettingsWindowController.shared.showWindow()
            }
        } else {
            if isNativeOpen && !isLegacyOpen {
                NativeSettingsWindowController.shared.closeWindow()
                SettingsWindowManager.shared.showSettings()
            }
        }
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        // Handle window close if SettingsRoutingManager is attached as a delegate
    }
}
