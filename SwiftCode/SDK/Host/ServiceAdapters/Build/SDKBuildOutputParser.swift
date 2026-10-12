import Foundation

// MARK: - SDKBuildOutputParser
//
// Pure, dependency-free parser for xcodebuild-style build output
// (spec §11.3: truthful terminal state, actionable failure information).
// Performs no I/O: it scans the supplied output string only. The build
// service owns process management; this parser owns interpretation.
//
// Strict-concurrency safe by construction: a caseless enum, no stored
// state, value types only, static functions only.

public enum SDKBuildOutputParser {

    // MARK: - ParsedBuildOutput

    public struct ParsedBuildOutput: Sendable {
        /// Structured error diagnostics in emission order, capped at
        /// `maxDiagnostics`. Never assumed complete when output exceeds the
        /// cap — see `errorCount` for the authoritative total.
        public let errors: [SDKBuildDiagnostic]
        /// Total warning lines found. Warnings are counted but deliberately
        /// NOT stored: real builds emit hundreds of low-signal warnings,
        /// and the storage cap exists to bound the result payload. Error
        /// diagnostics carry the actionable failure info the spec demands;
        /// the count preserves the warning signal without the volume.
        public let warningCount: Int
        /// Total error lines found, INCLUDING lines beyond the
        /// `maxDiagnostics` storage cap. Counting never stops at the cap —
        /// this is the number the build service reports on `SDKBuildResult`
        /// and the number `didSucceed(exitCode:output:errorCount:)`
        /// consults.
        public let errorCount: Int
    }

    // MARK: - Line grammars
    //
    // No regular expressions are used anywhere in this file. Each line is
    // classified by a hand-rolled scanner (see `classifyLine(_:)`), which is
    // strictly O(line length) with zero backtracking: every substring search
    // advances monotonically, so pathological inputs cannot blow up.
    //
    // The grammars handled, with their regex equivalents for reference:
    //
    //   Located error/warning:
    //     regex:  ^(.*?):(\d+):(?:\d+:)?\s*(error|warning):\s*(.*)$
    //     e.g.   /path/File.swift:42:10: error: cannot find 'foo' in scope
    //            /path/File.swift:42: warning: result of call is unused
    //     One deliberate deviation from the lazy-left regex: the file/line
    //     split is anchored from the RIGHT (the LAST ":<line>[:<column>]"
    //     segment wins), which is more correct for paths that themselves
    //     contain ':'. On ordinary xcodebuild output the two agree.
    //
    //   Plain error/warning (no location):
    //     regex:  ^\s*(?:xcodebuild:\s*)?(error|warning):\s*(.*)$
    //             | ^\s*\S[^:]*:\s*(error|warning):\s*(.*)$
    //     e.g.   error: Build input file cannot be found: 'x'
    //            clang: error: linker command failed with exit code 1
    //            xcodebuild: error: The workspace 'X' does not exist.
    //     The "xcodebuild:" tool prefix is stripped so bootstrap failures
    //     read cleanly; the diagnostic keeps file nil, line nil.
    //
    //   Linker error:
    //     regex:  ^\s*ld:\s*(.*)$
    //     e.g.   ld: library 'Foo' not found
    //     Raw `ld:` lines carry no "error:" token of their own, but they
    //     always accompany a failed link, so they are errors (file nil).
    //     An `ld: warning: ...` line is classified as a warning, not an
    //     error.
    //
    //   Build marker:
    //     line == "** BUILD FAILED **"  -> error diagnostic, file nil.
    //     line == "** BUILD SUCCEEDED **" -> ignored (not a diagnostic).
    //
    // Matching is case-sensitive: xcodebuild emits lowercase "error:" and
    // "warning:". Lines matching none of the above (notes, progress,
    // "The following build commands failed:" context) are ignored.

    // MARK: - parse

    /// Scans `output` line by line and returns structured diagnostics.
    ///
    /// - Parameters:
    ///   - output: Full captured build output (stdout + stderr merged, or
    ///     either stream; line endings of any kind are accepted).
    ///   - maxDiagnostics: Cap on the number of error diagnostics STORED in
    ///     `ParsedBuildOutput.errors`. Zero or negative stores nothing.
    ///     `errorCount` and `warningCount` always reflect the true totals.
    public static func parse(_ output: String, maxDiagnostics: Int = 50) -> ParsedBuildOutput {
        var errors: [SDKBuildDiagnostic] = []
        var warningCount = 0
        var errorCount = 0

        if maxDiagnostics > 0 {
            // Bound the upfront reservation so a huge cap stays the
            // caller's choice, not an allocation surprise.
            errors.reserveCapacity(min(maxDiagnostics, 256))
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            switch classifyLine(line) {
            case .error(let diagnostic):
                // Count every error line, even past the storage cap.
                errorCount += 1
                if errors.count < maxDiagnostics {
                    errors.append(diagnostic)
                }
            case .warning:
                warningCount += 1
            case .ignored:
                break
            }
        }

        return ParsedBuildOutput(errors: errors, warningCount: warningCount, errorCount: errorCount)
    }

    // MARK: - didSucceed

    /// Honest terminal-state check, mirroring the semantics used by the
    /// app's AssistVerificationPipeline: a build counts as succeeded only
    /// when ALL of these hold —
    ///   1. the process exited 0,
    ///   2. the output contains the "** BUILD SUCCEEDED **" marker, and
    ///   3. the parser found zero error lines.
    ///
    /// A zero exit code WITHOUT the success marker (truncated output,
    /// killed pipe, wrapper swallowed the tail) is NOT success. Parsed
    /// errors alongside exit 0 (xcodebuild occasionally exits 0 while
    /// still printing diagnostics) are NOT success either.
    public static func didSucceed(exitCode: Int32, output: String, errorCount: Int) -> Bool {
        exitCode == 0 && output.contains("** BUILD SUCCEEDED **") && errorCount == 0
    }

    // MARK: - Line classification (private)

    private enum LineClass {
        case error(SDKBuildDiagnostic)
        case warning
        case ignored
    }

    private static func classifyLine(_ line: String) -> LineClass {
        // Terminal markers first: they contain neither "error:" nor
        // "warning:", so this is just an explicit, cheap short-circuit.
        if line == "** BUILD FAILED **" {
            return .error(SDKBuildDiagnostic(message: line))
        }
        if line == "** BUILD SUCCEEDED **" {
            return .ignored
        }

        // Error family (located first, so "/p/f.swift:1: error: m" keeps
        // its location instead of falling through to the plain rule).
        if let diagnostic = locatedDiagnostic(line, marker: "error") {
            return .error(diagnostic)
        }
        if let message = plainMessage(line, marker: "error") {
            return .error(SDKBuildDiagnostic(message: message))
        }
        if line.hasPrefix("ld:"), plainMessage(line, marker: "warning") == nil {
            // Raw linker error with no "error:" token of its own.
            return .error(SDKBuildDiagnostic(message: line))
        }

        // Warning family: counted only, never stored (see ParsedBuildOutput).
        if locatedDiagnostic(line, marker: "warning") != nil {
            return .warning
        }
        if plainMessage(line, marker: "warning") != nil {
            return .warning
        }

        return .ignored
    }

    /// Parses `<file>:<line>[:<column>]: <marker>: <message>`.
    ///
    /// The marker token is ": error:" / ": warning:" (literal, first
    /// occurrence). The file/line split is anchored from the right: the
    /// head must end in ":<digits>" (the line number) with an optional
    /// second ":<digits>" (the column) before it. Anything else — e.g.
    /// "clang: error: ..." where the head has no trailing number — is not
    /// a located diagnostic and returns nil.
    private static func locatedDiagnostic(_ line: String, marker: String) -> SDKBuildDiagnostic? {
        guard let markerRange = line.range(of: ": \(marker):") else { return nil }

        var head = String(line[..<markerRange.lowerBound])
        let message = String(line[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        guard let lineNumber = stripTrailingNumberSegment(&head) else { return nil }
        _ = stripTrailingNumberSegment(&head) // Optional column; discarded.

        let file = head.trimmingCharacters(in: .whitespaces)
        guard !file.isEmpty else { return nil }

        return SDKBuildDiagnostic(file: file, line: lineNumber, message: message)
    }

    /// Parses `error: <message>` / `warning: <message>` with no location:
    /// either the line starts with the marker itself, or it contains
    /// "<something>: <marker>:" (tool-prefixed, e.g. "clang: error:",
    /// "xcodebuild: error:"). The tool prefix is dropped; the returned
    /// message is the text after the marker token.
    private static func plainMessage(_ line: String, marker: String) -> String? {
        if line.hasPrefix(marker + ":") {
            return String(line.dropFirst(marker.count + 1))
                .trimmingCharacters(in: .whitespaces)
        }
        guard let markerRange = line.range(of: ": \(marker):") else { return nil }
        return String(line[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Removes a trailing ":<digits>" segment from `text` in place and
    /// returns the number, or nil when the tail is not a bare number.
    /// Single scan from the end — no backtracking.
    private static func stripTrailingNumberSegment(_ text: inout String) -> Int? {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let tail = text[text.index(after: colon)...]
        guard !tail.isEmpty, tail.allSatisfy(\.isWholeNumber), let value = Int(tail) else {
            return nil
        }
        text = String(text[..<colon])
        return value
    }
}
