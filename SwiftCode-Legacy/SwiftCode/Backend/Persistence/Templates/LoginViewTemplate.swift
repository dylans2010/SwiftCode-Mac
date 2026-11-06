import Foundation

public struct LoginViewTemplate: ProjectScaffoldTemplate {
    public let name = "Login View"
    public let description = "A polished user authentication template with email/password fields, validation, and social login options."
    public let icon = "lock.shield"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct LoginApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var email = \"\"\n    @State private var password = \"\"\n    var body: some View {\n        VStack(spacing: 20) {\n            Image(systemName: \"person.circle.fill\").font(.system(size: 80)).foregroundStyle(.blue)\n            TextField(\"Email\", text: $email).textFieldStyle(.roundedBorder)\n            SecureField(\"Password\", text: $password).textFieldStyle(.roundedBorder)\n            Button(\"Sign In\") {}.buttonStyle(.borderedProminent).controlSize(.large)\n        }\n        .padding(40)\n        .frame(width: 320)\n    }\n}")
    ]
}
