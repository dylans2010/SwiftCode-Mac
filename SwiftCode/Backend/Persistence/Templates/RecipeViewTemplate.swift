import Foundation

public struct RecipeViewTemplate: ProjectScaffoldTemplate {
    public let name = "Recipe App"
    public let description = "A kitchen assistant listing culinary instructions, cooking times, and step-by-step guidance."
    public let icon = "fork.knife"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct RecipeApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(alignment: .leading, spacing: 12) {\n            Text(\"Spaghetti Carbonara\").font(.largeTitle.bold())\n            Text(\"Prep: 15 mins | Cook: 10 mins\").font(.subheadline).foregroundStyle(.secondary)\n        }\n        .padding()\n    }\n}")
    ]
}
