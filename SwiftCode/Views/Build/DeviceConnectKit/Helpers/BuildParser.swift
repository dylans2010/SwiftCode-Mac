import Foundation

public struct BuildParser {
    public struct ParsedIssue: Sendable {
        public let filePath: String?
        public let line: Int?
        public let message: String
        public let isError: Bool
    }

    public static func parseXcodebuildOutput(_ text: String) -> (errors: [ParsedIssue], warnings: [ParsedIssue]) {
        var errors: [ParsedIssue] = []
        var warnings: [ParsedIssue] = []

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(": error:") {
                if let issue = parseDiagnosticLine(line, isError: true) {
                    errors.append(issue)
                }
            } else if line.contains(": warning:") {
                if let issue = parseDiagnosticLine(line, isError: false) {
                    warnings.append(issue)
                }
            }
        }

        return (errors, warnings)
    }

    private static func parseDiagnosticLine(_ line: String, isError: Bool) -> ParsedIssue? {
        let parts = line.components(separatedBy: isError ? ": error:" : ": warning:")
        guard parts.count >= 2 else { return nil }

        let fileAndCoords = parts[0].trimmingCharacters(in: .whitespaces)
        let message = parts[1].trimmingCharacters(in: .whitespaces)

        let subParts = fileAndCoords.components(separatedBy: ":")
        if subParts.count >= 2 {
            let path = subParts[0]
            let lineNum = Int(subParts[1])
            return ParsedIssue(filePath: path, line: lineNum, message: message, isError: isError)
        }

        return ParsedIssue(filePath: nil, line: nil, message: message, isError: isError)
    }
}
