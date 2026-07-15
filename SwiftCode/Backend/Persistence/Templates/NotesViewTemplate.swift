import Foundation

public struct NotesViewTemplate: ProjectScaffoldTemplate {
    public let name = "Notes View"
    public let description = "A modern notes app workspace with category lists, title search, and full rich-text note editor views."
    public let icon = "note.text"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct NotesApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var notes = [\"Idea 1\", \"Shopping List\", \"SwiftCode Review\"]\n    var body: some View {\n        NavigationSplitView {\n            List(notes, id: \\.self) { note in\n                Text(note)\n            }\n        } detail: {\n            Text(\"Select a note\")\n        }\n    }\n}")
    ]
}
