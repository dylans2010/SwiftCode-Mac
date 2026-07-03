import Foundation

public struct CommandLineToolTemplate: ProjectTemplate {
    public let name = "Command Line Tool"
    public let files: [TemplateFile] = [
        TemplateFile(path: "main.swift", content: "import Foundation\n\nprint(\"Hello, World!\")")
    ]
}
