import Foundation

public struct BuildLogLineParser: Sendable {
    public static let shared = BuildLogLineParser()

    public func parse(_ line: String) -> BuildDiagnostic? {
        // Example: /path/to/file.swift:10:5: error: message
        let pattern = "^(/.+):(\\d+):(\\d+): (error|warning|note): (.+)$"
        let matches = RegexTool.firstMatch(in: line, pattern: pattern)

        guard matches.count >= 6 else { return nil }

        let filePath = matches[1]
        let line = Int(matches[2]) ?? 0
        let column = Int(matches[3]) ?? 0
        let severityStr = matches[4]
        let message = matches[5]

        let severity: BuildDiagnostic.Severity = {
            switch severityStr {
            case "error": return .error
            case "warning": return .warning
            case "note": return .note
            default: return .warning
            }
        }()

        return BuildDiagnostic(severity: severity, filePath: filePath, line: line, column: column, message: message)
    }
}
