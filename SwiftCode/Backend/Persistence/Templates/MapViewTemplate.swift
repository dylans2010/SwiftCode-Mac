import Foundation

public struct MapViewTemplate: ProjectScaffoldTemplate {
    public let name = "Map View"
    public let description = "A MapKit template highlighting locations, custom pin selectors, and route search forms."
    public let icon = "map"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MapApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\nimport MapKit\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"Interactive Map\").font(.headline).padding()\n            Map()\n                .frame(maxWidth: .infinity, maxHeight: .infinity)\n        }\n    }\n}")
    ]
}
