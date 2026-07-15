import Foundation

public struct NewsReaderViewTemplate: ProjectScaffoldTemplate {
    public let name = "News Reader"
    public let description = "A stylized publication magazine featuring article rows, bookmark selectors, and fluid readers."
    public let icon = "newspaper"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct NewsApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        List {\n            ForEach(1...3, id: \\.self) { i in\n                VStack(alignment: .leading, spacing: 6) {\n                    Text(\"Breaking News Article \\(i)\").font(.headline)\n                    Text(\"This is a preview of the news article content.\").font(.subheadline).foregroundStyle(.secondary)\n                }\n                .padding(.vertical, 4)\n            }\n        }\n    }\n}")
    ]
}
