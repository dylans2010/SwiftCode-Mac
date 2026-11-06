import Foundation

public struct MenuBarAppTemplate: ProjectScaffoldTemplate {
    public let name = "Menu Bar App"
    public let description = "A macOS application that resides primarily in the menu bar."
    public let icon = "menubar.rectangle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MenuBarApp: App {\n    var body: some Scene {\n        MenuBarExtra(\"My App\", systemImage: \"star\") {\n            Button(\"Quit\") {\n                NSApplication.shared.terminate(nil)\n            }\n        }\n    }\n}")
    ]
}
