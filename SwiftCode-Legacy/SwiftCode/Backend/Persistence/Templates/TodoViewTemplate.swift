import Foundation

public struct TodoViewTemplate: ProjectScaffoldTemplate {
    public let name = "Todo View"
    public let description = "A checklist with category categorization, smart completion states, and progress bar trackers."
    public let icon = "checklist"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct TodoApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var items = [\"Code Swift 6\", \"Ship features\", \"Drink water\"]\n    var body: some View {\n        List(items, id: \\.self) { item in\n            Label(item, systemImage: \"circle\")\n        }\n        .navigationTitle(\"To-do List\")\n    }\n}")
    ]
}
