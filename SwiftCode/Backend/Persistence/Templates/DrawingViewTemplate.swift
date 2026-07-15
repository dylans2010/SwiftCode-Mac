import Foundation

public struct DrawingViewTemplate: ProjectScaffoldTemplate {
    public let name = "Drawing View"
    public let description = "A canvas template with drawing pencils, brush sliders, and a full color palette palette selection."
    public let icon = "scribble"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct DrawingApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"Drawing Canvas\").font(.headline).padding()\n            Spacer()\n            Image(systemName: \"pencil.and.outline\").font(.system(size: 64))\n            Spacer()\n        }\n    }\n}")
    ]
}
