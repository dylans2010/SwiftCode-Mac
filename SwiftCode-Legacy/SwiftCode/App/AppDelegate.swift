import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var lastClosedWindowWasAuxiliaryOrSettings = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()

        AppUpdateService.shared.start()

        if UserDefaults.standard.bool(forKey: "com.swiftcode.sdk.studio.isOpen") {
            SDKStudioWindowManager.shared.openStudio()
        }

        _ = SoundInstaller.shared.installSoundsIfNeeded()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.handleWindowWillClose(window)
        }

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
        if lastClosedWindowWasAuxiliaryOrSettings {
            lastClosedWindowWasAuxiliaryOrSettings = false
            return false
        }

        if NativeSettingsWindowController.shared.isWindowOpen || SettingsWindowManager.shared.isSettingsOpen {
            return false
        }

        let remainingMainWindows = sender.windows.filter { window in
            guard window.isVisible else { return false }
            return !isSettingsOrAuxiliaryWindow(window)
        }

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
