import Foundation

public struct OnboardingViewTemplate: ProjectScaffoldTemplate {
    public let name = "Onboarding View"
    public let description = "A multi-page step-through splash tutorial sequence with sliding transitions and CTA landing button."
    public let icon = "sparkles"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct OnboardingApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        TabView {\n            VStack(spacing: 20) {\n                Image(systemName: \"macbook.and.iphone\").font(.system(size: 80))\n                Text(\"Welcome\").font(.title.bold())\n                Text(\"Learn how to use SwiftCode efficiently.\")\n            }\n            VStack(spacing: 20) {\n                Image(systemName: \"bolt.fill\").font(.system(size: 80))\n                Text(\"Blazing Fast\").font(.title.bold())\n                Text(\"Engineered for native performance.\")\n            }\n        }\n        .tabViewStyle(.page)\n        .frame(width: 400, height: 300)\n    }\n}")
    ]
}
