import Foundation

public struct MacOSAppTemplate: ProjectTemplate {
    public let name = "macOS App"
    public let description = "A template for a native SwiftUI-based macOS application."
    public let icon = "desktopcomputer"
    public let files: [TemplateFile] = [
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello, world!\")\n            .padding()\n    }\n}"),
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MyApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}")
    ]
}
