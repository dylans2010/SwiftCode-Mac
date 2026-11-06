import Foundation

public struct SwiftMacroTemplate: ProjectScaffoldTemplate {
    public let name = "Swift Macro"
    public let description = "A template for creating a Swift Macro library."
    public let icon = "wand.and.stars"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyMacro.swift", content: "import SwiftCompilerPlugin\nimport SwiftSyntax\nimport SwiftSyntaxMacros\n\npublic struct MyMacro: ExpressionMacro {\n    public static func expansion(\n        of node: some FreestandingMacroExpansionSyntax,\n        in context: some MacroExpansionContext\n    ) -> ExprSyntax {\n        return \"\\\"Hello Macro\\\"\"\n    }\n}"),
        TemplateFile(path: "Plugin.swift", content: "import SwiftCompilerPlugin\nimport SwiftSyntaxMacros\n\n@main\nstruct MyMacroPlugin: CompilerPlugin {\n    let providingMacros: [Macro.Type] = [MyMacro.self]\n}")
    ]
}
