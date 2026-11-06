import Foundation

// MARK: - SDKBuildOutputParser
//
// Ported from Legacy `SwiftCode/SDK/Host/ServiceAdapters/Build/SDKBuildOutputParser.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Pure, no-regex, hand-rolled scanner over xcodebuild output. Case-sensitive.
// Grammars:
//   - Located: `<file>:<line>[:<col>]: error|warning: msg` (right-anchored split)
//   - Plain `error:` / `warning:` lines (`xcodebuild:` prefix stripped)
//   - `ld:` lines are errors (`ld: warning:` is a warning)
//   - `** BUILD FAILED **` counts as one error
//   - `** BUILD SUCCEEDED **` is ignored (success is decided by
//     `didSucceed`, not by the marker alone)
//
// `didSucceed` requires exit code 0 AND the success marker AND zero
// parsed errors — a build that "succeeded" with errors is not a success.

public struct ParsedBuildOutput: Sendable, Equatable {
    /// Capped diagnostics (errors first, then warnings, in order).
    public let diagnostics: [SDKBuildDiagnostic]
    /// Total error count (may exceed `diagnostics.count` when capped).
    public let errorCount: Int
    /// Total warning count.
    public let warningCount: Int

    public init(diagnostics: [SDKBuildDiagnostic], errorCount: Int, warningCount: Int) {
        self.diagnostics = diagnostics
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
}

public enum SDKBuildOutputParser {
    /// Parses `output` into capped diagnostics plus totals.
    public static func parse(_ output: String, maxDiagnostics: Int = 50) -> ParsedBuildOutput {
        var diagnostics: [SDKBuildDiagnostic] = []
        var errorCount = 0
        var warningCount = 0

        func append(file: String?, line: Int?, message: String, isError: Bool) {
            if isError { errorCount += 1 } else { warningCount += 1 }
            guard diagnostics.count < maxDiagnostics else { return }
            diagnostics.append(SDKBuildDiagnostic(file: file, line: line, message: message))
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed == "** BUILD FAILED **" {
                append(file: nil, line: nil, message: "Build failed.", isError: true)
                continue
            }
            if trimmed == "** BUILD SUCCEEDED **" {
                continue
            }

            // `ld:` lines: errors, except `ld: warning:`.
            if trimmed.hasPrefix("ld: warning:") {
                append(file: nil, line: nil, message: String(trimmed.dropFirst("ld: warning:".count)).trimmingCharacters(in: .whitespaces), isError: false)
                continue
            }
            if trimmed.hasPrefix("ld: ") {
                append(file: nil, line: nil, message: String(trimmed.dropFirst("ld: ".count)).trimmingCharacters(in: .whitespaces), isError: true)
                continue
            }

            // Located `<file>:<line>[:<col>]: error|warning: msg`.
            // Right-anchored: split from the right so Windows-style or
            // colon-containing paths do not break the parse.
            if let located = parseLocated(trimmed) {
                append(file: located.file, line: located.line, message: located.message, isError: located.isError)
                continue
            }

            // Plain `error:` / `warning:` (strip an `xcodebuild:` prefix).
            let stripped = trimmed.hasPrefix("xcodebuild:") ? String(trimmed.dropFirst("xcodebuild:".count)).trimmingCharacters(in: .whitespaces) : trimmed
            if stripped.hasPrefix("error:") {
                append(file: nil, line: nil, message: String(stripped.dropFirst("error:".count)).trimmingCharacters(in: .whitespaces), isError: true)
                continue
            }
            if stripped.hasPrefix("warning:") {
                append(file: nil, line: nil, message: String(stripped.dropFirst("warning:".count)).trimmingCharacters(in: .whitespaces), isError: false)
                continue
            }
        }

        return ParsedBuildOutput(diagnostics: diagnostics, errorCount: errorCount, warningCount: warningCount)
    }

    /// Truthful success: exit 0 AND the success marker AND zero errors.
    public static func didSucceed(output: String, exitCode: Int32, parsed: ParsedBuildOutput) -> Bool {
        exitCode == 0
            && output.contains("** BUILD SUCCEEDED **")
            && parsed.errorCount == 0
    }

    // MARK: - Located-line grammar

    private struct Located {
        let file: String
        let line: Int?
        let message: String
        let isError: Bool
    }

    private static func parseLocated(_ line: String) -> Located? {
        // Find ": error:" or ": warning:" from the right.
        let markers: [(String, Bool)] = [(": error:", true), (": warning:", false)]
        for (marker, isError) in markers {
            guard let range = line.range(of: marker, options: .backwards) else { continue }
            let head = String(line[..<range.lowerBound])
            let message = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !message.isEmpty else { continue }
            // Head is `<file>:<line>` or `<file>:<line>:<col>`.
            let parts = head.split(separator: ":", omittingEmptySubsequences: false)
            let file: String
            let lineNumber: Int
            if parts.count >= 3,
               let line = Int(parts[parts.count - 2]),
               Int(parts[parts.count - 1]) != nil {
                // `<file>:<line>:<col>` — drop the last two segments.
                file = parts.dropLast(2).joined(separator: ":")
                lineNumber = line
            } else if parts.count >= 2, let line = Int(parts[parts.count - 1]) {
                // `<file>:<line>` — drop the last segment.
                file = parts.dropLast().joined(separator: ":")
                lineNumber = line
            } else {
                continue
            }
            guard !file.isEmpty else { continue }
            return Located(file: file, line: lineNumber, message: message, isError: isError)
        }
        return nil
    }
}
