import SwiftUI
import AppKit

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
