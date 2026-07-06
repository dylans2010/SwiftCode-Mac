import Foundation

public struct StaticLibraryTemplate: ProjectScaffoldTemplate {
    public let name = "Static Library"
    public let description = "A template for a static library (.a)."
    public let icon = "building.columns"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Library.swift", content: "import Foundation\n\npublic class MyStaticLibrary {\n    public init() {}\n}")
    ]
}
