import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()

        // Apply registered app icon variant to Dock
        _ = AppIconManager.shared

        // Install bundled custom alert sounds into ~/Library/Sounds/
        _ = SoundInstaller.shared.installSoundsIfNeeded()

        // Start Google Cloud SDK (Python) and Meta Assist (TypeScript) background lifecycle monitoring automatically
        Task { @MainActor in
            GoogleCloudSDKLifecycleManager.shared.startMonitoring()
            try? await GoogleCloudSDKLifecycleManager.shared.startEngine()

            MetaAssistLifecycleManager.shared.startMonitoring()
            try? await MetaAssistLifecycleManager.shared.startEngine()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        LoggingTool.info("SwiftCode terminating cleanly.")
        Task { @MainActor in
            await GoogleCloudSDKLifecycleManager.shared.stopEngine()
            await MetaAssistLifecycleManager.shared.stopEngine()
        }
    }

    private func setupDefaultPreferences() {
        if UserDefaults.standard.object(forKey: "EditorFontSize") == nil {
            UserDefaults.standard.set(13.0, forKey: "EditorFontSize")
        }
    }
}
