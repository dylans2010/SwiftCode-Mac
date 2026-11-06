// BuildLogLineParser.swift
// SwiftCodeAssistant
//
// RECONSTRUCTED (not a Legacy port): `BuildLogLineParser` is referenced by
// three Legacy files (`AgentTerminalService.swift:205`,
// `AssistVerificationPipeline.swift:528`, `ViewModels/BuildViewModel.swift:22`)
// and by the ported `AgentTerminalService` / `AssistVerificationPipeline` in
// this target — but it is defined NOWHERE in SwiftCode-Legacy or on main.
// This implementation is written from the call-site contract
// (`BuildLogLineParser.shared.parse(line) -> BuildDiagnostic?`) and the
// xcodebuild log format the callers already parse elsewhere in the tree
// (see `BuildOutputAccumulator` in `AssistBuildProjectTool.swift`, which
// matches the same `file:line:col: error|warning: message` shape).
// It parses one log line; non-diagnostic lines return nil.
//
// DEPENDENCY NOTE: the returned `BuildDiagnostic` lives in `SwiftCodeBuild`
// (`swiftcode/Sources/SwiftCodeBuild/BuildDiagnostic.swift`). `SwiftCodeAssistant`
// cannot see it until `SwiftCodeBuild` is added to its dependencies in
// `swiftcode/Package.swift` (target `SwiftCodeAssistant`, currently only
// `["SwiftCodeSubprocess"]`). No cycle: `SwiftCodeBuild` depends on
// `SwiftCodeProject` / `SwiftCodePlist` / `SwiftCodeWorkspace` /
// `SwiftCodeSubprocess`, not on `SwiftCodeAssistant`. Until that dep lands,
// this file, `AgentTerminalService.swift` and `AssistVerificationPipeline.swift`
// cannot compile in this target.

import SwiftCodeBuild
import Foundation

/// Parses xcodebuild-style diagnostic lines (`path:line:col: error|warning|note: message`)
/// into `BuildDiagnostic` values. Lines that are not diagnostics return nil.
public final class BuildLogLineParser: Sendable {
    public static let shared = BuildLogLineParser()

    private init() {}

    public func parse(_ line: String) -> BuildDiagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // file:line:col: severity: message
        if let diag = parseWithColumn(trimmed) { return diag }
        // file:line: severity: message (no column)
        if let diag = parseWithoutColumn(trimmed) { return diag }
        return nil
    }

    private func parseWithColumn(_ line: String) -> BuildDiagnostic? {
        // Split on ":" — the file path itself may contain ":" only on
        // Windows-style paths, which do not occur in xcodebuild output.
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
