import Foundation

public struct DashboardViewTemplate: ProjectScaffoldTemplate {
    public let name = "Dashboard View"
    public let description = "A high-density dashboard with stat cards, metrics charts, and recent activity feeds."
    public let icon = "chart.layout.gauge"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct DashboardApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        ScrollView {\n            VStack(spacing: 20) {\n                Text(\"My Dashboard\").font(.largeTitle.bold())\n                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {\n                    ForEach(0..<4) { i in\n                        VStack(alignment: .leading) {\n                            Text(\"Metric \\(i+1)\").font(.caption).foregroundStyle(.secondary)\n                            Text(\"\\(100 * (i+1))\").font(.title.bold())\n                        }\n                        .padding()\n                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))\n                    }\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}
