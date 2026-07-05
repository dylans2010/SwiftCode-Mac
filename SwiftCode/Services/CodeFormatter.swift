import Foundation

final class CodeFormatter {
    static let shared = CodeFormatter()
    private init() {}

    func format(_ source: String, fileExtension: String = "swift") -> String {
        switch fileExtension.lowercased() {
        case "json":
            return formatJSON(source)
        case "swift":
            return formatSwift(source)
        default:
            return formatGeneric(source)
        }
    }

    // MARK: - Swift Formatting

    private func formatSwift(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")

        lines = lines.map { normalizeWhitespace($0) }

        lines = normalizeBlankLines(lines)

        lines = reindentSwift(lines)

        lines = alignTrailingBraces(lines)

        lines = formatOperatorSpacing(lines)

        lines = formatColonSpacing(lines)

        lines = formatCommaSpacing(lines)

        lines = normalizeImports(lines)

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Formatting

    private func formatJSON(_ source: String) -> String {
        guard let data = source.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return source
        }
        return result
    }

    // MARK: - Generic Formatting

    private func formatGeneric(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        lines = lines.map { normalizeWhitespace($0) }
        lines = normalizeBlankLines(lines)
        return lines.joined(separator: "\n")
    }

    // MARK: - Whitespace Normalization

    private func normalizeWhitespace(_ line: String) -> String {
        let trailing = line.replacingOccurrences(
            of: "\\s+$",
            with: "",
            options: .regularExpression
        )

        var result = ""
        var leadingDone = false
        for ch in trailing {
            if !leadingDone {
                if ch == "\t" {
                    result += "    "
                } else if ch == " " {
                    result += " "
                } else {
                    leadingDone = true
                    result.append(ch)
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private func normalizeBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var consecutiveBlank = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                consecutiveBlank += 1
                if consecutiveBlank <= 2 {
                    result.append("")
                }
            } else {
                consecutiveBlank = 0
                result.append(line)
            }
        }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        if !result.isEmpty {
            result.append("")
        }
        return result
    }

    // MARK: - Swift Re-indentation

    private func reindentSwift(_ lines: [String]) -> [String] {
        let indentUnit = "    "
        var indentLevel = 0
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                result.append("")
                continue
            }

            if trimmed.hasPrefix("}") || trimmed.hasPrefix(")") || trimmed.hasPrefix("]") {
                indentLevel = max(0, indentLevel - 1)
            }

            if trimmed.hasPrefix("case ") || trimmed.hasPrefix("default:") {
                let caseIndent = max(0, indentLevel)
                let indent = String(repeating: indentUnit, count: caseIndent)
                result.append(indent + trimmed)
            } else {
                let indent = String(repeating: indentUnit, count: indentLevel)
                result.append(indent + trimmed)
            }

            let openCount = trimmed.filter { $0 == "{" || $0 == "(" || $0 == "[" }.count
            let closeCount = trimmed.filter { $0 == "}" || $0 == ")" || $0 == "]" }.count
            let netOpen = openCount - closeCount

            if trimmed.hasPrefix("}") || trimmed.hasPrefix(")") || trimmed.hasPrefix("]") {
                indentLevel += max(0, netOpen)
            } else {
                if netOpen > 0 {
                    indentLevel += netOpen
                } else if netOpen < 0 {
                    indentLevel = max(0, indentLevel + netOpen)
                }
            }
        }

        return result
    }

    private func alignTrailingBraces(_ lines: [String]) -> [String] {
        lines
    }

    // MARK: - Operator Spacing

    private func formatOperatorSpacing(_ lines: [String]) -> [String] {
        lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                return line
            }
            if trimmed.contains("\"") {
                return line
            }

            var result = line
            let ops = ["==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "->"]
            for op in ops {
                let padded = " \(op) "
                result = result.replacingOccurrences(of: "  \(op)  ", with: padded)
                result = result.replacingOccurrences(of: "  \(op) ", with: padded)
                result = result.replacingOccurrences(of: " \(op)  ", with: padded)
            }
            return result
        }
    }

    // MARK: - Colon Spacing

    private func formatColonSpacing(_ lines: [String]) -> [String] {
        lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") {
                return line
            }
            return line
        }
    }

    // MARK: - Comma Spacing

    private func formatCommaSpacing(_ lines: [String]) -> [String] {
        lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") {
                return line
            }
            if trimmed.contains("\"") {
                return line
            }

            var result = line
            result = result.replacingOccurrences(
                of: ",([^ \\n])",
                with: ", $1",
                options: .regularExpression
            )
            return result
        }
    }

    // MARK: - Import Organization

    private func normalizeImports(_ lines: [String]) -> [String] {
        var importLines: [String] = []
        var importIndices: [Int] = []
        var firstImportIndex: Int?

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                importLines.append(trimmed)
                importIndices.append(i)
                if firstImportIndex == nil { firstImportIndex = i }
            }
        }

        guard importLines.count > 1, let startIdx = firstImportIndex else { return lines }

        let sorted = importLines.sorted()

        var result = lines
        for (offset, idx) in importIndices.enumerated() {
            if offset < sorted.count {
                result[idx] = sorted[offset]
            }
        }

        return result
    }
}
