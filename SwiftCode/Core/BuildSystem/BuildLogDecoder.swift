import Foundation

// MARK: - Decoded Log Entry

struct DecodedLogEntry: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let timestamp: String?
    let category: LogEntryCategory
    let message: String
    let rawLine: String

    enum LogEntryCategory: String, CaseIterable {
        case error = "Error"
        case warning = "Warning"
        case compileStep = "Compile"
        case info = "Info"
        case debug = "Debug"

        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .compileStep: return "hammer.fill"
            case .info: return "info.circle.fill"
            case .debug: return "ant.fill"
            }
        }

        var colorName: String {
            switch self {
            case .error: return "red"
            case .warning: return "yellow"
            case .compileStep: return "blue"
            case .info: return "green"
            case .debug: return "gray"
            }
        }
    }
}

// MARK: - Decoded Build Log

struct DecodedBuildLog {
    let entries: [DecodedLogEntry]
    let errorCount: Int
    let warningCount: Int
    let compileStepCount: Int

    var errors: [DecodedLogEntry] {
        entries.filter { $0.category == .error }
    }

    var warnings: [DecodedLogEntry] {
        entries.filter { $0.category == .warning }
    }

    var compileSteps: [DecodedLogEntry] {
        entries.filter { $0.category == .compileStep }
    }

    var hasFailures: Bool { errorCount > 0 }
}

// MARK: - Build Log Decoder

/// Parses raw GitHub Actions log output into structured log entries.
///
/// Responsibilities:
/// - Splitting log lines
/// - Detecting warnings
/// - Detecting errors
/// - Detecting compile steps
/// - Extracting timestamps
final class BuildLogDecoder {
    static let shared = BuildLogDecoder()
    private init() {}

    // MARK: - Timestamp Pattern

    /// Matches ISO-8601 style timestamps commonly found in GitHub Actions logs:
    /// e.g. "2024-01-15T12:34:56.1234567Z" or "2024-01-15T12:34:56Z"
    private static let timestampPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?\s+"#

    // MARK: - Error Patterns

    private static let errorPatterns: [String] = [
        "error:",
        "Error:",
        "ERROR:",
        "fatal error:",
        "FATAL:",
        "❌",
        "failed with exit code",
        "Process completed with exit code 1",
        "compilation error",
        "linker error",
        "Build Failed",
        "FAILED",
        "error: build failed"
    ]

    // MARK: - Warning Patterns

    private static let warningPatterns: [String] = [
        "warning:",
        "Warning:",
        "WARNING:",
        "⚠️",
        "deprecation warning",
        "deprecated"
    ]

    // MARK: - Compile Step Patterns

    private static let compilePatterns: [String] = [
        "Compiling",
        "Linking",
        "Build step",
        "xcodebuild",
        "swift build",
        "SwiftCompile",
        "CompileSwift",
        "CompileC",
        "Ld ",
        "CodeSign",
        "ProcessInfoPlistFile",
        "CopySwiftLibs",
        "PhaseScriptExecution",
        "Run custom shell script",
        "actions/checkout",
        "actions/setup",
        "Run ",
        "##[group]"
    ]

    // MARK: - Decode

    /// Parse raw log text into a structured `DecodedBuildLog`.
    func decode(_ rawLog: String) -> DecodedBuildLog {
        let lines = rawLog.components(separatedBy: .newlines)
        var entries: [DecodedLogEntry] = []
        var errorCount = 0
        var warningCount = 0
        var compileStepCount = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let timestamp = extractTimestamp(from: trimmed)
            let message = removeTimestamp(from: trimmed)
            let category = classify(message)

            switch category {
            case .error: errorCount += 1
            case .warning: warningCount += 1
            case .compileStep: compileStepCount += 1
            default: break
            }

            entries.append(DecodedLogEntry(
                lineNumber: index + 1,
                timestamp: timestamp,
                category: category,
                message: message,
                rawLine: line
            ))
        }

        return DecodedBuildLog(
            entries: entries,
            errorCount: errorCount,
            warningCount: warningCount,
            compileStepCount: compileStepCount
        )
    }

    // MARK: - Summarize for AI

    /// Creates a concise summary of decoded logs suitable for AI analysis.
    func summarizeForAI(_ decodedLog: DecodedBuildLog) -> String {
        var summary = "Build Log Summary:\n"
        summary += "- Total lines: \(decodedLog.entries.count)\n"
        summary += "- Errors: \(decodedLog.errorCount)\n"
        summary += "- Warnings: \(decodedLog.warningCount)\n"
        summary += "- Compile steps: \(decodedLog.compileStepCount)\n\n"

        if !decodedLog.errors.isEmpty {
            summary += "Errors found:\n"
            for error in decodedLog.errors.prefix(20) {
                summary += "  Line \(error.lineNumber): \(error.message)\n"
            }
            summary += "\n"
        }

        if !decodedLog.warnings.isEmpty {
            summary += "Warnings found:\n"
            for warning in decodedLog.warnings.prefix(10) {
                summary += "  Line \(warning.lineNumber): \(warning.message)\n"
            }
        }

        return summary
    }

    // MARK: - Private Helpers

    private func extractTimestamp(from line: String) -> String? {
        guard let range = line.range(of: Self.timestampPattern, options: .regularExpression) else {
            return nil
        }
        return String(line[range]).trimmingCharacters(in: .whitespaces)
    }

    private func removeTimestamp(from line: String) -> String {
        guard let range = line.range(of: Self.timestampPattern, options: .regularExpression) else {
            return line
        }
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func classify(_ message: String) -> DecodedLogEntry.LogEntryCategory {
        let lowercased = message.lowercased()

        for pattern in Self.errorPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return .error
            }
        }

        for pattern in Self.warningPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return .warning
            }
        }

        for pattern in Self.compilePatterns {
            if message.contains(pattern) {
                return .compileStep
            }
        }

        return .info
    }
}
