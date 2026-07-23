import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()

        // Setup native Git Controls Menu Bar Status Item
        MenuBarManager.shared.setupMenuBar()
    }

    private func setupDefaultPreferences() {
        if UserDefaults.standard.object(forKey: "EditorFontSize") == nil {
            UserDefaults.standard.set(13.0, forKey: "EditorFontSize")
        }
    }
}
