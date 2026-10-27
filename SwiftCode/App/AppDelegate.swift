import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var lastClosedWindowWasAuxiliaryOrSettings = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()

        // Start the single update service (Sparkle 2). This only starts
        // Sparkle's scheduled cycle; it never blocks launch. A startup
        // failure is logged and surfaced in Settings by the service.
        AppUpdateService.shared.start()

        // Restore Studio window if it was left open in previous session
        if UserDefaults.standard.bool(forKey: "com.swiftcode.sdk.studio.isOpen") {
            SDKStudioWindowManager.shared.openStudio()
        }

        // Install bundled custom alert sounds into ~/Library/Sounds/
        _ = SoundInstaller.shared.installSoundsIfNeeded()

        // Track closing windows to prevent closing settings or auxiliary windows from terminating the app
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.handleWindowWillClose(window)
        }

        // Start Google Cloud SDK (Python) and Meta Assist (TypeScript) background lifecycle monitoring automatically
        Task { @MainActor in
            GoogleCloudSDKLifecycleManager.shared.startMonitoring()
            try? await GoogleCloudSDKLifecycleManager.shared.startEngine()

            MetaAssistLifecycleManager.shared.startMonitoring()
            try? await MetaAssistLifecycleManager.shared.startEngine()
        }
    }

    private func handleWindowWillClose(_ window: NSWindow) {
        lastClosedWindowWasAuxiliaryOrSettings = isSettingsOrAuxiliaryWindow(window)
    }

    private func isSettingsOrAuxiliaryWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window == NativeSettingsWindowController.shared.window { return true }
        if window.frameAutosaveName == "NativeSafariSettingsWindow" || window.frameAutosaveName == "SettingsMainWindow" {
            return true
        }
        let title = window.title
        if title == "Preferences" || SettingsCategory.allCases.contains(where: { $0.title == title }) {
            return true
        }
        if title.contains("Documentation") || title.contains("Simulator") || title.contains("Operations") || title.contains("Virtual Machine") {
            return true
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the Settings window or auxiliary window must NOT terminate the app
        if lastClosedWindowWasAuxiliaryOrSettings {
            lastClosedWindowWasAuxiliaryOrSettings = false
            return false
        }

        // If settings window is currently visible, do not terminate
        if NativeSettingsWindowController.shared.isWindowOpen || SettingsWindowManager.shared.isSettingsOpen {
            return false
        }

        // Check if there are any remaining visible workspace or welcome windows
        let remainingMainWindows = sender.windows.filter { window in
            guard window.isVisible else { return false }
            return !isSettingsOrAuxiliaryWindow(window)
        }

        // Only terminate if all actual workspace/welcome windows are closed
        return remainingMainWindows.isEmpty
    }

    func applicationWillTerminate(_ notification: Notification) {
        LoggingTool.info("SwiftCode terminating cleanly.")
        UserDefaults.standard.synchronize()
        Task { @MainActor in
            await GoogleCloudSDKLifecycleManager.shared.stopEngine()
            await MetaAssistLifecycleManager.shared.stopEngine()
        }
    }

    private func setupDefaultPreferences() {
        if UserDefaults.standard.object(forKey: "EditorFontSize") == nil {
            UserDefaults.standard.set(13.0, forKey: "EditorFontSize")
        }
        UserDefaults.standard.synchronize()
    }
}
