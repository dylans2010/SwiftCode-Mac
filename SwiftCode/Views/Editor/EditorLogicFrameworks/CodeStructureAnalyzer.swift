import Foundation

// MARK: - Code Structure Analyzer
// Uses regex to detect Swift declarations without requiring SwiftSyntax.

struct CodeSymbol: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var kind: SymbolKind
    var lineNumber: Int
    var isPrivate: Bool

    enum SymbolKind: String, CaseIterable {
        case `class`      = "class"
        case `struct`     = "struct"
        case `enum`       = "enum"
        case `protocol`   = "protocol"
        case `extension`  = "extension"
        case function     = "func"
        case variable     = "var"
        case constant     = "let"
        case typeAlias    = "typealias"

        var icon: String {
            switch self {
            case .class:      return "cube.fill"
            case .struct:     return "square.fill"
            case .enum:       return "list.bullet"
            case .protocol:   return "checkmark.seal.fill"
            case .extension:  return "arrow.up.right.square"
            case .function:   return "function"
            case .variable:   return "v.square"
            case .constant:   return "c.square"
            case .typeAlias:  return "t.square"
            }
        }
    }
}

final class CodeStructureAnalyzer {
    static let shared = CodeStructureAnalyzer()
    private init() {}

    // MARK: - Analyze

    func analyze(_ code: String) -> [CodeSymbol] {
        var symbols: [CodeSymbol] = []
        let lines = code.components(separatedBy: "\n")

        let patterns: [(NSRegularExpression, CodeSymbol.SymbolKind)] = buildPatterns()

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isPrivate = trimmed.hasPrefix("private ") || trimmed.hasPrefix("fileprivate ")

            for (regex, kind) in patterns {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = regex.firstMatch(in: trimmed, range: range),
                   match.numberOfRanges > 1,
                   let nameRange = Range(match.range(at: 1), in: trimmed) {
                    let name = String(trimmed[nameRange])
                    let symbol = CodeSymbol(
                        name: name,
                        kind: kind,
                        lineNumber: lineIndex + 1,
                        isPrivate: isPrivate
                    )
                    symbols.append(symbol)
                    break
                }
            }
        }

        return symbols
    }

    // MARK: - Pattern Builder

    private func buildPatterns() -> [(NSRegularExpression, CodeSymbol.SymbolKind)] {
        let defs: [(String, CodeSymbol.SymbolKind)] = [
            (#"(?:^|[\s]+)class\s+([A-Za-z_][A-Za-z0-9_]*)[\s<:{]"#,    .class),
            (#"(?:^|[\s]+)struct\s+([A-Za-z_][A-Za-z0-9_]*)[\s<:{]"#,   .struct),
            (#"(?:^|[\s]+)enum\s+([A-Za-z_][A-Za-z0-9_]*)[\s<:{]"#,     .enum),
            (#"(?:^|[\s]+)protocol\s+([A-Za-z_][A-Za-z0-9_]*)[\s<:{]"#, .protocol),
            (#"(?:^|[\s]+)extension\s+([A-Za-z_][A-Za-z0-9_]*)[\s<:{]"#, .extension),
            (#"(?:^|[\s]+)func\s+([A-Za-z_][A-Za-z0-9_]*)\s*[<(]"#,     .function),
            (#"(?:^|[\s]+)var\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:{]"#,      .variable),
            (#"(?:^|[\s]+)let\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:{=]"#,     .constant),
            (#"(?:^|[\s]+)typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#,   .typeAlias),
        ]
        return defs.compactMap { pattern, kind in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, kind)
        }
    }

    // MARK: - Quick Stats

    func statistics(for code: String) -> CodeStatistics {
        let lines = code.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let commentLines = lines.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("//") || t.hasPrefix("*") || t.hasPrefix("/*")
        }
        let symbols = analyze(code)

        return CodeStatistics(
            totalLines: lines.count,
            nonEmptyLines: nonEmpty.count,
            commentLines: commentLines.count,
            classCount: symbols.filter { $0.kind == .class }.count,
            structCount: symbols.filter { $0.kind == .struct }.count,
            functionCount: symbols.filter { $0.kind == .function }.count,
            variableCount: symbols.filter { $0.kind == .variable || $0.kind == .constant }.count
        )
    }
}

struct CodeStatistics {
    var totalLines: Int
    var nonEmptyLines: Int
    var commentLines: Int
    var classCount: Int
    var structCount: Int
    var functionCount: Int
    var variableCount: Int

    var complexityScore: Int {
        // Simple McCabe-like approximation
        return functionCount * 2 + classCount + structCount
    }
}
