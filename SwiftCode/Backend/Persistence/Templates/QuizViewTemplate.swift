import Foundation

public struct QuizViewTemplate: ProjectScaffoldTemplate {
    public let name = "Quiz App"
    public let description = "A learning quiz card space displaying question cards, selectable choices, and final score decks."
    public let icon = "questionmark.bubble"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct QuizApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 20) {\n            Text(\"Question 1 of 10\").font(.caption)\n            Text(\"What is the latest Swift version?\").font(.title2.bold())\n            Button(\"Swift 5\") {}.buttonStyle(.bordered).frame(maxWidth: .infinity)\n            Button(\"Swift 6\") {}.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)\n        }\n        .padding()\n    }\n}")
    ]
}
