import Foundation

public struct MarkdownEditorViewTemplate: ProjectScaffoldTemplate {
    public let name = "Markdown Editor"
    public let description = "A markdown document space with side-by-side editing text fields and live rendering html templates."
    public let icon = "doc.plaintext"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MarkdownApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var text = \"# Hello World\\nStart writing...\"\n    var body: some View {\n        HStack {\n            TextEditor(text: $text)\n            Divider()\n            VStack(alignment: .leading) {\n                Text(\"Preview\").font(.headline)\n                Text(text)\n            }\n            .frame(maxWidth: .infinity, alignment: .topLeading)\n        }\n        .padding()\n    }\n}")
    ]
}
