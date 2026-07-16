import Foundation

public struct AssistCodeMutationEngine: AssistTool {
    public let id = "code_mutation_engine"
    public let name = "Controlled Mutation Engine"
    public let description = "Applies safe, minimal source mutations scoped to a symbol or an exact range."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, !path.isEmpty else { return .failure("Missing path") }
        guard let replacement = input["replacement"] as? String else { return .failure("Missing replacement") }
        guard context.permissions.isPathAllowed(path) else { return .failure("Path not allowed: \(path)") }

        let original = try context.fileSystem.readFile(at: path)
        var updated = original

        if let symbol = input["symbol"] as? String, !symbol.isEmpty {
            if let range = symbolBodyRange(for: symbol, in: original) {
                updated.replaceSubrange(range, with: replacement)
            } else {
                return .failure("Unable to locate symbol body for: \(symbol)")
            }
        } else if let target = input["target"] as? String, !target.isEmpty {
            guard updated.contains(target) else { return .failure("Target text not found") }
            updated = updated.replacingOccurrences(of: target, with: replacement)
        } else {
            return .failure("Provide either symbol or target")
        }

        if updated == original { return .failure("No mutation produced") }
        try context.fileSystem.writeFile(at: path, content: updated)
        return .success("Applied minimal mutation to \(path)", data: ["bytes_before": "\(original.count)", "bytes_after": "\(updated.count)"])
    }

    private func symbolBodyRange(for symbol: String, in content: String) -> Range<String.Index>? {
        guard let symbolRange = content.range(of: symbol) else { return nil }
        guard let braceStart = content[symbolRange.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = braceStart
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return symbolRange.lowerBound..<content.index(after: idx)
                }
            }
            idx = content.index(after: idx)
        }
        return nil
    }
}
