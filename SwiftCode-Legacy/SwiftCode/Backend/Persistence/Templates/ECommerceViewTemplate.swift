import Foundation

public struct ECommerceViewTemplate: ProjectScaffoldTemplate {
    public let name = "E-Commerce View"
    public let description = "A product listing and showcase catalog with product detail cards and shopping cart actions."
    public let icon = "cart"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct ECommerceApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        ScrollView {\n            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {\n                ForEach(1...6, id: \\.self) { i in\n                    VStack(alignment: .leading, spacing: 8) {\n                        Image(systemName: \"tag\").font(.largeTitle)\n                        Text(\"Product \\(i)\").font(.headline)\n                        Text(\"$99.99\").font(.subheadline).foregroundStyle(.secondary)\n                    }\n                    .padding()\n                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}
