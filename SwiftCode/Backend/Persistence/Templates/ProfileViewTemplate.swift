import Foundation

public struct ProfileViewTemplate: ProjectScaffoldTemplate {
    public let name = "Profile View"
    public let description = "A premium user dashboard with user bio, avatar editor, preferences tabs, and stats indicators."
    public let icon = "person.crop.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct ProfileApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 16) {\n            Image(systemName: \"person.circle.fill\").font(.system(size: 72))\n            Text(\"Developer User\").font(.title2.bold())\n            Text(\"macOS Systems Engineer\").foregroundStyle(.secondary)\n        }\n        .padding()\n    }\n}")
    ]
}
