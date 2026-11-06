import Foundation

public struct AssistDocStringGeneratorTool: AssistTool {
    public let id = "docstring_generator"
    public let name = "DocC Documentation Generator"
    public let description = "Generates Apple DocC compliant documentation comments (///) with Parameters, Returns, and Throws tags for Swift declarations."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generate DocC compliant documentation comments for a Swift declaration.",
            properties: [
                "declaration": JSONSchema(type: "string", description: "The Swift function, type, or protocol declaration header."),
                "summary": JSONSchema(type: "string", description: "Brief single-line summary of what the declaration does.")
            ],
            required: ["declaration"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let declaration = input["declaration"] as? String else {
            return .failure("Missing required parameter: declaration")
        }

        let summary = (input["summary"] as? String) ?? "Performs operations associated with this declaration."
        var docLines: [String] = []

        docLines.append("/// \(summary)")
        docLines.append("///")

        // Parse parameters from (arg1: Type, arg2: Type)
        if let openParen = declaration.firstIndex(of: "("),
           let closeParen = declaration.lastIndex(of: ")"),
           openParen < closeParen {
            let paramSection = String(declaration[declaration.index(after: openParen)..<closeParen])
            let params = paramSection.components(separatedBy: ",")
            for param in params {
                let parts = param.components(separatedBy: ":")
                if parts.count >= 2 {
                    let namePart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanName = namePart.components(separatedBy: " ").last ?? namePart
                    if !cleanName.isEmpty && cleanName != "_" {
                        let typePart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        docLines.append("/// - Parameter \(cleanName): The \(typePart) value supplied for processing.")
                    }
                }
            }
        }

        if declaration.contains("throws") {
            docLines.append("/// - Throws: An error if processing or I/O fails during execution.")
        }

        if declaration.contains("->") {
            let returnType = declaration.components(separatedBy: "->").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Result"
            docLines.append("/// - Returns: A `\(returnType)` instance representing the computed outcome.")
        }

        let result = docLines.joined(separator: "\n") + "\n" + declaration
        return .success("Generated DocC Documentation:\n\n```swift\n\(result)\n```")
    }
}
