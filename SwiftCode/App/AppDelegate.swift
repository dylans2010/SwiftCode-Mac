import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()

        // Apply registered app icon variant to Dock
        _ = AppIconManager.shared

        // Install bundled custom alert sounds into ~/Library/Sounds/
        _ = SoundInstaller.shared.installSoundsIfNeeded()

        // Antigravity runtime: keep it alive while Google Cloud Assist is the
        // active system (auto-restart on crash) and pre-warm the bridge so the
        // first message does not pay Python start-up, SDK import and harness start.
        Task { @MainActor in
            GoogleCloudSDKLifecycleManager.shared.startMonitoring()
            let agentModeEnabled = UserDefaults.standard.bool(forKey: "com.swiftcode.assist.mode")
            if AppSettings.shared.isGoogleCloudAssist || agentModeEnabled {
                GoogleCloudSDKRuntime.shared.prewarm()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        LoggingTool.info("SwiftCode terminating cleanly.")
        // Stop the Antigravity bridge (and its harness children) so no Python
        // process outlives the app. The bridge also exits on its own when its
        // parent PID disappears, covering crashes and force quits.
        MainActor.assumeIsolated {
            GoogleCloudSDKLifecycleManager.shared.stopMonitoring()
            GoogleCloudSDKRuntime.shared.terminateForAppExit()
        }
    }

    private func setupDefaultPreferences() {
        if UserDefaults.standard.object(forKey: "EditorFontSize") == nil {
            UserDefaults.standard.set(13.0, forKey: "EditorFontSize")
        }
    }
}
