import Foundation

public struct CalendarViewTemplate: ProjectScaffoldTemplate {
    public let name = "Calendar View"
    public let description = "A calendar grid showing dates, monthly views, events timeline, and planner slots."
    public let icon = "calendar"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct CalendarApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"October 2026\").font(.title.bold())\n            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {\n                ForEach(1...31, id: \\.self) { day in\n                    Text(\"\\(day)\")\n                        .frame(width: 32, height: 32)\n                        .background(day == 15 ? Color.orange : Color.clear)\n                        .foregroundColor(day == 15 ? .white : .primary)\n                        .clipShape(Circle())\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}
