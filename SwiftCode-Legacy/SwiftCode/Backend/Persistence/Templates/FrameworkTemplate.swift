import Foundation

public struct FrameworkTemplate: ProjectScaffoldTemplate {
    public let name = "Framework"
    public let description = "A template for a shared framework."
    public let icon = "briefcase"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyFramework.swift", content: "import Foundation\n\npublic class MyFramework {\n    public init() {}\n}")
    ]
}
