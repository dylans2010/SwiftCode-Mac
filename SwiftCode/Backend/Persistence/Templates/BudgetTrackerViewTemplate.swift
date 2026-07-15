import Foundation

public struct BudgetTrackerViewTemplate: ProjectScaffoldTemplate {
    public let name = "Budget Tracker"
    public let description = "A cashbook manager plotting monthly transactions, balance logs, and saving goals."
    public let icon = "dollarsign.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct BudgetApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 16) {\n            Text(\"Current Balance\").font(.headline)\n            Text(\"$5,240.00\").font(.system(size: 40, weight: .bold))\n        }\n        .padding()\n    }\n}")
    ]
}
