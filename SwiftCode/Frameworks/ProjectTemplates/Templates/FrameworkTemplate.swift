import Foundation

public struct FrameworkTemplate: ProjectTemplate {
    public let name = "Framework"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyFramework.swift", content: "import Foundation\n\npublic class MyFramework {\n    public init() {}\n}")
    ]
}
