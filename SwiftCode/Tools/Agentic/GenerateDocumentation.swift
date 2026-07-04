import Foundation

public struct GenerateDocumentationTool {
    public static let identifier = "generate_documentation"

    public func run(code: String) async throws -> String {
        return "/// Documentation for the provided code"
    }
}
