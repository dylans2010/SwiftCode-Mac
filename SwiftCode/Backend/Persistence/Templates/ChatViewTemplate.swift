import Foundation

public struct ChatViewTemplate: ProjectScaffoldTemplate {
    public let name = "Chat View"
    public let description = "An interactive messaging UI with conversational message bubbles, dynamic input bar, and auto-scroll."
    public let icon = "message"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct ChatApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var text = \"\"\n    var body: some View {\n        VStack {\n            ScrollView {\n                VStack(alignment: .leading, spacing: 12) {\n                    Text(\"Hey, how is it going?\").padding().background(Color.blue.opacity(0.1)).cornerRadius(10)\n                    Text(\"Everything is great, working on SwiftCode!\").padding().background(Color.gray.opacity(0.1)).cornerRadius(10)\n                }\n                .padding()\n            }\n            HStack {\n                TextField(\"Message\", text: $text).textFieldStyle(.roundedBorder)\n                Button(\"Send\") {}\n            }\n            .padding()\n        }\n    }\n}")
    ]
}
