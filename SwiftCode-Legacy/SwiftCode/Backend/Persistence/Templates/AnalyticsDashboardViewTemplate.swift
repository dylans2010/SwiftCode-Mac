import Foundation

public struct AnalyticsDashboardViewTemplate: ProjectScaffoldTemplate {
    public let name = "Analytics Dashboard"
    public let description = "A detailed business analytics console with activity logs, filters, and charts."
    public let icon = "chart.bar.xaxis"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct AnalyticsApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"Sales Analytics\").font(.title.bold())\n            Image(systemName: \"chart.bar.fill\").font(.system(size: 100)).foregroundStyle(.orange)\n        }\n        .padding()\n    }\n}")
    ]
}
