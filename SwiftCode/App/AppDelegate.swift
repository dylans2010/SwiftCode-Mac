import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()

        // Setup native Git Controls Menu Bar Status Item
        MenuBarManager.shared.setupMenuBar()

        // Apply registered app icon variant to Dock
        _ = AppIconManager.shared

        // Install bundled custom alert sounds into ~/Library/Sounds/
        _ = SoundInstaller.shared.installSoundsIfNeeded()
    }

    private func setupDefaultPreferences() {
        if UserDefaults.standard.object(forKey: "EditorFontSize") == nil {
            UserDefaults.standard.set(13.0, forKey: "EditorFontSize")
        }
    }
}
