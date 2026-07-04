import Foundation

public struct MultiplatformAppTemplate: ProjectTemplate {
    public let name = "Multiplatform App"
    public let description = "A SwiftUI app that runs on macOS, iOS, and visionOS."
    public let icon = "square.on.square"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Shared/ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Multiplatform App\")\n    }\n}"),
        TemplateFile(path: "Shared/App.swift", content: "import SwiftUI\n\n@main\nstruct MultiApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}")
    ]
}
