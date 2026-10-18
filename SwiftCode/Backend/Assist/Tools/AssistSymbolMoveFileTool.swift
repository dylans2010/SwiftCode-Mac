import Foundation

public struct AssistSymbolMoveFileTool: AssistTool {
    public let id = "symbol_move_file"
    public let name = "Move Symbol Across Files"
    public let description = "Moves a top-level Swift declaration from a source file to a destination file by extracting its brace-balanced block, removing it from the source, and appending it to the destination. Verifies the symbol is present in the destination and its declaration is gone from the source, restoring both files on verification failure. Brace matching is heuristic and does not parse strings or comments."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Moves one symbol declaration from a source file to a destination file.",
            properties: [
                "symbol": JSONSchema(type: "string", description: "Name of the symbol to move."),
                "sourcePath": JSONSchema(type: "string", description: "Workspace-relative path of the file containing the symbol."),
                "destinationPath": JSONSchema(type: "string", description: "Workspace-relative path of the file receiving the symbol.")
            ],
            required: ["symbol", "sourcePath", "destinationPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let symbol = (input["symbol"] ?? input["symbolName"]) as? String, !symbol.isEmpty else {
            return .failure("Missing required parameter: symbol")
        }
        guard let sourceRaw = (input["sourcePath"] ?? input["source_path"]) as? String, !sourceRaw.isEmpty else {
            return .failure("Missing required parameter: sourcePath")
        }
        guard let destinationRaw = (input["destinationPath"] ?? input["destination_path"]) as? String, !destinationRaw.isEmpty else {
            return .failure("Missing required parameter: destinationPath")
        }
        guard isValidIdentifier(symbol) else {
            return .failure("Invalid symbol '\(symbol)': identifiers may contain only letters, digits, and underscores, and must not start with a digit.")
        }
        guard let sourceURL = resolvePath(sourceRaw, in: context) else {
            return .failure("Invalid sourcePath: path must stay inside the workspace and must not contain '..'.")
        }
        guard let destinationURL = resolvePath(destinationRaw, in: context) else {
            return .failure("Invalid destinationPath: path must stay inside the workspace and must not contain '..'.")
        }
        guard sourceURL.standardized != destinationURL.standardized else {
            return .failure("Refusing move: sourcePath and destinationPath must differ.")
        }
        guard let sourceContent = readFile(sourceURL) else {
            return .failure("Could not read source file at \(relativePath(sourceURL, root: context.workspaceRoot)).")
        }
        guard let destinationContent = readFile(destinationURL) else {
            return .failure("Could not read destination file at \(relativePath(destinationURL, root: context.workspaceRoot)).")
        }

        let declPattern = "\\b(func|class|struct|enum|protocol|actor|var|let|typealias)\\s+" + NSRegularExpression.escapedPattern(for: symbol) + "\\b"
        guard let declRegex = try? NSRegularExpression(pattern: declPattern, options: []) else {
            return .failure("Move failed: could not build a declaration pattern for '\(symbol)'.")
        }
        let destinationRange = NSRange(destinationContent.startIndex..., in: destinationContent)
        if declRegex.firstMatch(in: destinationContent, options: [], range: destinationRange) != nil {
            return .failure("Refusing move: destination already declares '\(symbol)'.")
        }

        let sourceLines = sourceContent.components(separatedBy: "\n")
        var declarationLine: Int? = nil
        var declarationKind = ""
        for (index, line) in sourceLines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if let match = declRegex.firstMatch(in: line, options: [], range: range),
               match.numberOfRanges >= 2, let kindRange = Range(match.range(at: 1), in: line) {
                declarationLine = index
                declarationKind = String(line[kindRange])
                break
            }
        }
        guard let startIndex = declarationLine else {
            return .failure("Symbol '\(symbol)' declaration not found in \(relativePath(sourceURL, root: context.workspaceRoot)).")
        }

        // Extract the brace-balanced block starting at the declaration line.
        var depth = 0
        var sawBrace = false
        var endIndex: Int? = nil
        let limit = min(sourceLines.count, startIndex + 501)
        for index in startIndex..<limit {
            let line = sourceLines[index]
            let opens = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count
            if opens > 0 { sawBrace = true }
            depth += opens - closes
            if sawBrace && depth <= 0 { endIndex = index; break }
            if !sawBrace && index - startIndex >= 20 { break }
        }
        if sawBrace {
            guard let end = endIndex else {
                return .failure("Move failed: declaration block for '\(symbol)' is unbalanced or exceeds 500 lines.")
            }
            endIndex = end
        } else if declarationKind == "var" || declarationKind == "let" || declarationKind == "typealias" {
            endIndex = startIndex
        } else {
            return .failure("Move failed: could not find the opening brace for '\(symbol)' (\(declarationKind)) within 20 lines of its declaration.")
        }
        guard let end = endIndex else {
            return .failure("Move failed: could not determine the declaration block for '\(symbol)'.")
        }

        let blockLines = Array(sourceLines[startIndex...end])
        var remainingLines = sourceLines
        remainingLines.removeSubrange(startIndex...end)
        let newSource = remainingLines.joined(separator: "\n")
        var newDestination = destinationContent
        if !newDestination.isEmpty && !newDestination.hasSuffix("\n") {
            newDestination += "\n"
        }
        newDestination += "\n" + blockLines.joined(separator: "\n") + "\n"

        do {
            try newSource.write(to: sourceURL, atomically: true, encoding: .utf8)
            try newDestination.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            _ = try? sourceContent.write(to: sourceURL, atomically: true, encoding: .utf8)
            _ = try? destinationContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            return .failure("Move failed while writing files: \(error.localizedDescription). Original contents were restored.")
        }

        // Verify: declaration present in destination, declaration gone from source.
        let verifySource = readFile(sourceURL) ?? ""
        let verifyDestination = readFile(destinationURL) ?? ""
        let sourceRange = NSRange(verifySource.startIndex..., in: verifySource)
        let destRange = NSRange(verifyDestination.startIndex..., in: verifyDestination)
        let stillInSource = declRegex.firstMatch(in: verifySource, options: [], range: sourceRange) != nil
        let presentInDestination = declRegex.firstMatch(in: verifyDestination, options: [], range: destRange) != nil
        if stillInSource || !presentInDestination {
            _ = try? sourceContent.write(to: sourceURL, atomically: true, encoding: .utf8)
            _ = try? destinationContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            return .failure("Move verification failed (still in source: \(stillInSource), in destination: \(presentInDestination)). Original contents were restored.")
        }

        let sourceRelative = relativePath(sourceURL, root: context.workspaceRoot)
        let destinationRelative = relativePath(destinationURL, root: context.workspaceRoot)
        return .success(
            "Moved symbol '\(symbol)' (\(declarationKind), \(blockLines.count) line(s)) from \(sourceRelative) to \(destinationRelative).",
            data: [
                "symbol": symbol,
                "kind": declarationKind,
                "sourcePath": sourceRelative,
                "destinationPath": destinationRelative,
                "movedLines": "\(blockLines.count)"
            ],
            filesChanged: [sourceRelative, destinationRelative]
        )
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard let first = value.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first) else { return false }
        return true
    }

    private func resolvePath(_ raw: String?, in context: AssistContext) -> URL? {
        let workspace = context.workspaceRoot.standardized
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("..") { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardized
        } else {
            candidate = workspace.appendingPathComponent(raw).standardized
        }
        if candidate == workspace || candidate.path.hasPrefix(workspace.path + "/") {
            return candidate
        }
        return nil
    }

    private func readFile(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
