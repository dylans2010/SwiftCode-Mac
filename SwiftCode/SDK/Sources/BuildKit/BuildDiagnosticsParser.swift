import Foundation
import DiagnosticsKit

public final class BuildDiagnosticsParser: Sendable {
    public init() {}

    public func parse(output: String) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let lines = output.components(separatedBy: .newlines)

        // Regex for Swift/Clang errors: /path/to/file.swift:10:5: error: message
        let swiftPattern = #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#
        let swiftRegex = try? NSRegularExpression(pattern: swiftPattern)

        // Regex for TypeScript errors: path/to/file.ts(10,5): error TS1234: message
        let tsPattern = #"^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s*TS\d+:\s*(.+)$"#
        let tsRegex = try? NSRegularExpression(pattern: tsPattern)

        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            if let match = swiftRegex?.firstMatch(in: line, options: [], range: fullRange) {
                let file = nsLine.substring(with: match.range(at: 1))
                let lineNum = Int(nsLine.substring(with: match.range(at: 2)))
                let colNum = Int(nsLine.substring(with: match.range(at: 3)))
                let sevStr = nsLine.substring(with: match.range(at: 4)).lowercased()
                let message = nsLine.substring(with: match.range(at: 5))

                let severity: DiagnosticSeverity
                switch sevStr {
                case "error": severity = .error
                case "warning": severity = .warning
                default: severity = .note
                }

                diagnostics.append(Diagnostic(
                    code: severity == .error ? .buildCompilerError : DiagnosticCode("SC-B010"),
                    severity: severity,
                    message: message,
                    location: DiagnosticLocation(filePath: file, line: lineNum, column: colNum)
                ))
            } else if let match = tsRegex?.firstMatch(in: line, options: [], range: fullRange) {
                let file = nsLine.substring(with: match.range(at: 1))
                let lineNum = Int(nsLine.substring(with: match.range(at: 2)))
                let colNum = Int(nsLine.substring(with: match.range(at: 3)))
                let sevStr = nsLine.substring(with: match.range(at: 4)).lowercased()
                let message = nsLine.substring(with: match.range(at: 5))

                let severity: DiagnosticSeverity = sevStr == "error" ? .error : .warning
                diagnostics.append(Diagnostic(
                    code: severity == .error ? .buildCompilerError : DiagnosticCode("SC-B011"),
                    severity: severity,
                    message: message,
                    location: DiagnosticLocation(filePath: file, line: lineNum, column: colNum)
                ))
            }
        }

        return diagnostics
    }
}
