import YcodeBuild
import Foundation

public final class BuildLogLineParser: Sendable {
    public static let shared = BuildLogLineParser()

    private init() {}

    public func parse(_ line: String) -> BuildDiagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let diag = parseWithColumn(trimmed) { return diag }
        if let diag = parseWithoutColumn(trimmed) { return diag }
        return nil
    }

    private func parseWithColumn(_ line: String) -> BuildDiagnostic? {
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return nil }
        let filePath = String(parts[0])
        guard let lineNo = Int(parts[1]), let colNo = Int(parts[2]) else { return nil }
        let severityText = parts[3].trimmingCharacters(in: .whitespaces)
        guard let severity = BuildDiagnostic.Severity(rawValue: severityText) else { return nil }
        let message = parts[4...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return nil }
        return BuildDiagnostic(severity: severity, filePath: filePath, line: lineNo, column: colNo, message: message)
    }

    private func parseWithoutColumn(_ line: String) -> BuildDiagnostic? {
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let filePath = String(parts[0])
        guard let lineNo = Int(parts[1]) else { return nil }
        let severityText = parts[2].trimmingCharacters(in: .whitespaces)
        guard let severity = BuildDiagnostic.Severity(rawValue: severityText) else { return nil }
        let message = parts[3...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return nil }
        return BuildDiagnostic(severity: severity, filePath: filePath, line: lineNo, column: 0, message: message)
    }
}
