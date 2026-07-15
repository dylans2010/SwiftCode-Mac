import Foundation

public struct PhotoGalleryViewTemplate: ProjectScaffoldTemplate {
    public let name = "Photo Gallery"
    public let description = "A full-window photo collection showcase with interactive album list selectors."
    public let icon = "photo.on.rectangle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct PhotoApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        ScrollView {\n            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {\n                ForEach(1...12, id: \\.self) { i in\n                    Image(systemName: \"photo\")\n                        .font(.system(size: 40))\n                        .frame(width: 100, height: 100)\n                        .background(Color.secondary.opacity(0.1))\n                        .cornerRadius(12)\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}
