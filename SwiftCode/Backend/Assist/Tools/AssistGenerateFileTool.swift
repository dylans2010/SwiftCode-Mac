import Foundation

public struct AssistGenerateFileTool: AssistTool {
    public let id = "code_generate"
    public let name = "Generate File"
    public let description = "Generates a new file with boilerplate or specific logic."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates a new file from a built-in template. Refuses to overwrite existing files.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative target path. Must not already exist."),
                "template": JSONSchema(type: "string", description: "One of: swift_struct, swift_class, swiftui_view, test (case-insensitive)."),
                "module": JSONSchema(type: "string", description: "Module name used only by the test template for @testable import. Defaults to the user's project name.")
            ],
            required: ["path", "template"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        guard let template = input["template"] as? String else {
            return .failure("Missing required parameter: template")
        }

        if context.fileSystem.exists(at: path) {
            return .failure("Target file already exists: \(path)")
        }

        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let defaultModule = AssistXcodeProjectResolver.locate(in: context.workspaceRoot)?.name ?? "App"
        var resolvedInput = input
        if (resolvedInput["module"] as? String)?.isEmpty != false {
            resolvedInput["module"] = defaultModule
        }
        // Unknown templates are a failure, never a success that writes a
        // comment-only file.
        guard let rendered = renderTemplate(template: template, fileName: fileName, input: resolvedInput) else {
            return .failure("Unknown template '\(template)': expected swift_struct, swift_class, swiftui_view, or test.")
        }

        do {
            try context.fileSystem.writeFile(at: path, content: rendered)
            return .success("Generated file \(path) using template '\(template)'", data: ["path": path])
        } catch {
            return .failure("Failed generating file \(path): \(error.localizedDescription)")
        }
    }

    private func renderTemplate(template: String, fileName: String, input: [String: Any]) -> String? {
        let moduleName = (input["module"] as? String) ?? "App"
        switch template.lowercased() {
        case "swift_struct":
            return "import Foundation\n\npublic struct \(fileName) {\n    public init() {}\n}\n"
        case "swift_class":
            return "import Foundation\n\npublic final class \(fileName) {\n    public init() {}\n}\n"
        case "swiftui_view":
            return "import SwiftUI\n\nstruct \(fileName): View {\n    var body: some View {\n        Text(\"\(fileName)\")\n    }\n}\n\n#Preview {\n    \(fileName)()\n}\n"
        case "test":
            // Honest scaffold: fails until a real assertion replaces it,
            // instead of a vacuous XCTAssertTrue(true) counted as a test.
            return "import XCTest\n@testable import \(moduleName)\n\nfinal class \(fileName): XCTestCase {\n    func testExample() {\n        XCTFail(\"Not implemented: replace with a real assertion for \(fileName).\")\n    }\n}\n"
        default:
            return nil
        }
    }
}
