import Foundation

public struct SettingsViewTemplate: ProjectScaffoldTemplate {
    public let name = "Settings View"
    public let description = "A standard macOS-style multi-pane preferences interface with toggles, sliders, and picker controls."
    public let icon = "gearshape"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct SettingsApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var notificationsEnabled = true\n    @State private var themeSelection = \"Dark\"\n    var body: some View {\n        Form {\n            Toggle(\"Enable Notifications\", isOn: $notificationsEnabled)\n            Picker(\"Theme\", selection: $themeSelection) {\n                Text(\"Light\").tag(\"Light\")\n                Text(\"Dark\").tag(\"Dark\")\n            }\n        }\n        .padding()\n    }\n}")
    ]
}
