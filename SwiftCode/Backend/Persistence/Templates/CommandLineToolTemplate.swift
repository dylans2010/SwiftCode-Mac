import Foundation

public struct CommandLineToolTemplate: ProjectTemplate {
    public let name = "Command Line Tool"
    public let description = "A template for a command-line utility."
    public let icon = "terminal"
    public let files: [TemplateFile] = [
        TemplateFile(path: "main.swift", content: "import Foundation\n\nprint(\"Hello, World!\")")
    ]
}
