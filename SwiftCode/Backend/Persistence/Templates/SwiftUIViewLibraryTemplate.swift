import Foundation

public struct SwiftUIViewLibraryTemplate: ProjectTemplate {
    public let name = "SwiftUI View Library"
    public let description = "A library of reusable SwiftUI components."
    public let icon = "macwindow.on.rectangle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyComponent.swift", content: "import SwiftUI\n\npublic struct MyComponent: View {\n    public init() {}\n    public var body: some View {\n        Text(\"Custom Component\")\n    }\n}")
    ]
}
