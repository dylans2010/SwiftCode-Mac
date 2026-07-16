import Foundation

public struct AssistSymbolSearchTool: AssistTool {
    public let id = "search_symbol"
    public let name = "Symbol Search"
    public let description = "Searches for symbols (classes, methods, variables) within the project."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let symbol = input["symbol"] as? String else {
            return .failure("Missing required parameter: symbol")
        }

        let escaped = NSRegularExpression.escapedPattern(for: symbol)
        // Improved Swift declaration regex patterns
        let patterns = [
            "\\b(class|struct|enum|protocol|actor|typealias|extension)\\s+\(escaped)\\b",
            "\\bfunc\\s+\(escaped)\\s*[\\(<]",
            "\\b(var|let)\\s+\(escaped)\\s*[:=]",
            "\\bcase\\s+\(escaped)\\b"
        ]

        var allMatches: [String] = []
        for pattern in patterns {
            do {
                let found = try AssistSearchFunctions.searchText(in: context.workspaceRoot, pattern: pattern, isRegex: true)
                for (url, matches) in found {
                    let rel = AssistToolingSupport.relativePath(for: url, workspaceRoot: context.workspaceRoot)
                    allMatches.append(contentsOf: matches.map { "\(rel):\($0)" })
                }
            } catch {
                await context.logger.error("Regex search failed for pattern \(pattern): \(error.localizedDescription)")
            }
        }

        let deduped = Array(Set(allMatches)).sorted()
        return .success("Symbol search completed for '\(symbol)'", data: ["results": deduped.joined(separator: "\n")])
    }
}
