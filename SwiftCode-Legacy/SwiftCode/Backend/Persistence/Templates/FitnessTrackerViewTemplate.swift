import Foundation

public struct FitnessTrackerViewTemplate: ProjectScaffoldTemplate {
    public let name = "Fitness Tracker"
    public let description = "A sports monitoring suite tracking workout metrics, step counters, and visual activity rings."
    public let icon = "figure.run"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct FitnessApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(alignment: .leading, spacing: 20) {\n            Text(\"Activity\").font(.largeTitle.bold())\n            HStack {\n                Label(\"10,420 Steps\", systemImage: \"shoeprints.fill\")\n                Spacer()\n                Label(\"420 kcal\", systemImage: \"flame.fill\")\n            }\n            .font(.headline)\n        }\n        .padding()\n    }\n}")
    ]
}
