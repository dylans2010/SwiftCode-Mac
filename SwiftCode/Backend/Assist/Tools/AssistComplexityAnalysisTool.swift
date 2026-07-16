import Foundation

public struct AssistComplexityAnalysisTool: AssistTool {
    public let id = "complexity_analysis"
    public let name = "Complexity Analysis"
    public let description = "Analyzes the cyclomatic complexity of code."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            let controlFlowKeywords = ["if ", "for ", "while ", "switch ", "case ", "guard ", "catch "]
            var complexity = 1

            for keyword in controlFlowKeywords {
                let count = content.components(separatedBy: keyword).count - 1
                complexity += count
            }

            let rating = complexity > 20 ? "High" : (complexity > 10 ? "Medium" : "Low")
            return .success("Complexity analysis for \(path): \(rating) (Cyclomatic approximation: \(complexity))", data: ["score": "\(complexity)", "rating": rating])
        } catch {
            return .failure("Failed to analyze complexity for \(path): \(error.localizedDescription)")
        }
    }
}
