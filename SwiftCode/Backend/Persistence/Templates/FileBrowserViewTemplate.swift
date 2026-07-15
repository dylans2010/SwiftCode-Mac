import Foundation

public struct FileBrowserViewTemplate: ProjectScaffoldTemplate {
    public let name = "File Browser"
    public let description = "A Finder-like storage directory navigator displaying file lists and path history links."
    public let icon = "folder.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct FileApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        List {\n            Label(\"Documents\", systemImage: \"folder\")\n            Label(\"Downloads\", systemImage: \"folder\")\n            Label(\"project.json\", systemImage: \"doc.text\")\n        }\n    }\n}")
    ]
}
