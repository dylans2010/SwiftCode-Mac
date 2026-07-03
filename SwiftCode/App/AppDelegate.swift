import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingTool.info("SwiftCode launched.")
        setupDefaultPreferences()
    }

    private func setupDefaultPreferences() {
        if UserDefaults.standard.object(forKey: "EditorFontSize") == nil {
            UserDefaults.standard.set(13.0, forKey: "EditorFontSize")
        }
    }
}
