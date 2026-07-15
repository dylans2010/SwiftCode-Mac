import Foundation

public struct TaskBoardViewTemplate: ProjectScaffoldTemplate {
    public let name = "Task Board"
    public let description = "A Kanban timeline manager with lanes, drag handles, and priority chips."
    public let icon = "columns.3"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct BoardApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        HStack(spacing: 16) {\n            VStack(alignment: .leading) {\n                Text(\"To Do\").font(.headline)\n                Text(\"Task A\").padding().background(Color.secondary.opacity(0.1)).cornerRadius(8)\n            }\n            VStack(alignment: .leading) {\n                Text(\"In Progress\").font(.headline)\n                Text(\"Task B\").padding().background(Color.secondary.opacity(0.1)).cornerRadius(8)\n            }\n        }\n        .padding()\n    }\n}")
    ]
}
