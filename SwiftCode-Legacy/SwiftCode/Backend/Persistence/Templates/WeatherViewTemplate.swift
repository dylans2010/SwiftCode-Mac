import Foundation

public struct WeatherViewTemplate: ProjectScaffoldTemplate {
    public let name = "Weather View"
    public let description = "A detailed dashboard displaying current conditions, hourly forecasts, and 10-day trends."
    public let icon = "cloud.sun"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct WeatherApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 20) {\n            Text(\"San Francisco\").font(.largeTitle)\n            Text(\"68°\").font(.system(size: 80, weight: .thin))\n            Text(\"Partly Cloudy\").font(.headline).foregroundStyle(.secondary)\n        }\n        .padding()\n    }\n}")
    ]
}
