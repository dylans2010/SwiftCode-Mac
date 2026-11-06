import Foundation

public struct AudioPlayerViewTemplate: ProjectScaffoldTemplate {
    public let name = "Audio Player"
    public let description = "A slick music and podcast deck with play/pause controls, seek timelines, and album artwork."
    public let icon = "play.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct AudioApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 24) {\n            Image(systemName: \"music.note\").font(.system(size: 80)).padding(40).background(Color.orange.opacity(0.1)).cornerRadius(20)\n            Text(\"Now Playing\").font(.headline)\n            HStack(spacing: 32) {\n                Image(systemName: \"backward.fill\")\n                Image(systemName: \"play.fill\").font(.largeTitle)\n                Image(systemName: \"forward.fill\")\n            }\n        }\n        .padding()\n    }\n}")
    ]
}
