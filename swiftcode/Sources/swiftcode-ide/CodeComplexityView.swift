import Foundation
import SwiftUI

// Code complexity, adapted from Legacy's
// `SwiftCode/Views/AI/ComplexityAnalyzerView.swift`. The destination has
// no complexity surface (no cyclomatic-complexity tool or view), so this
// is a real one: it scans the Swift files under a directory and, per
// file, counts lines, functions, and branching constructs
// (`if`/`guard`/`for`/`while`/`switch`/`case`/`catch`/`&&`/`||`/`?:`)
// for a cyclomatic-complexity estimate, plus the maximum brace-nesting
// depth. Results are computed from the actual file contents, sorted
// worst-first, and the scan runs off the main actor.

/// One file's measured complexity.
struct ComplexityFileResult: Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var lines: Int
    var functions: Int
    var complexity: Int
    var maxNestingDepth: Int

    var fileName: String { url.lastPathComponent }
}

/// Scans a directory tree of Swift files and ranks them by complexity.
struct CodeComplexityView: View {
    /// The directory to scan, or `nil` to show the empty state.
    var directory: URL?

    @Environment(\.colorScheme) private var scheme
    @State private var results: [ComplexityFileResult] = []
    @State private var sortAscending = false
    @State private var isScanning = false
    @State private var scannedFileCount = 0
    @State private var errorMessage: String?

    private var sortedResults: [ComplexityFileResult] {
        results.sorted {
            sortAscending ? $0.complexity < $1.complexity : $0.complexity > $1.complexity
        }
    }

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Code Complexity").font(ShellFonts.rowBold)
                Spacer()
                if isScanning {
                    ProgressView().controlSize(.small)
                }
                if scannedFileCount > 0 {
                    Text(verbatim: "\(scannedFileCount) files")
                        .font(ShellFonts.small)
                        .foregroundStyle(c.secondaryLabel)
                }
                Picker("Order", selection: $sortAscending) {
                    Text("Worst first").tag(false)
                    Text("Simplest first").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Button("Scan") { scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(directory == nil || isScanning)
            }
            .padding(10)
            if let error = errorMessage {
                Text(verbatim: error)
                    .font(ShellFonts.small)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Hairline(color: c.separator)
            if results.isEmpty {
                ContentUnavailableView(
                    "No results yet",
                    systemImage: "chart.bar",
                    description: Text(directory == nil
                        ? "Open a project to scan its Swift files for complexity."
                        : "Press Scan to measure cyclomatic complexity, function counts and nesting depth for every Swift file under \(directory!.path).")
                )
            } else {
                List(sortedResults) { result in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: result.fileName).font(ShellFonts.rowBold)
                            Text(verbatim: result.url.deletingLastPathComponent().path)
                                .font(ShellFonts.mini)
                                .foregroundStyle(c.tertiaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        metric(value: result.complexity, label: "complexity", colors: c)
                        metric(value: result.functions, label: "funcs", colors: c)
                        metric(value: result.maxNestingDepth, label: "depth", colors: c)
                        metric(value: result.lines, label: "lines", colors: c)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { scan() }
    }

    private func metric(value: Int, label: String, colors c: ShellColors) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(value)").font(ShellFonts.rowBold)
            Text(verbatim: label).font(ShellFonts.mini).foregroundStyle(c.tertiaryLabel)
        }
        .frame(minWidth: 52)
    }

    private func scan() {
        guard let directory else { return }
        isScanning = true
        errorMessage = nil
        Task {
            let scanned = await CodeComplexityScanner.scan(directory: directory)
            results = scanned.results
            scannedFileCount = scanned.fileCount
            isScanning = false
        }
    }
}

/// The file scanner behind `CodeComplexityView`. Pure Foundation so the
/// measurement can be reasoned about without a Swift parser: comments
/// and string literals are stripped before counting, so a `if` inside a
/// comment or a string does not inflate the score.
enum CodeComplexityScanner {
    static func scan(directory: URL) async -> (results: [ComplexityFileResult], fileCount: Int) {
        await Task.detached(priority: .userInitiated) {
            var results: [ComplexityFileResult] = []
            var count = 0
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return (results, count) }
            // Materialize the enumeration before iterating: a
            // DirectoryEnumerator cannot be iterated from an async context.
            let urls = enumerator.compactMap { $0 as? URL }
            for url in urls {
                guard url.pathExtension == "swift" else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                count += 1
                results.append(measure(url: url, source: text))
            }
            return (results, count)
        }.value
    }

    static func measure(url: URL, source: String) -> ComplexityFileResult {
        let stripped = stripCommentsAndStrings(source)
        let lines = source.components(separatedBy: .newlines).count
        let functions = countMatches(of: #"\bfunc\s+[A-Za-z_]"#, in: stripped)
        var complexity = 1
        for pattern in [#"\bif\b"#, #"\bguard\b"#, #"\bfor\b"#, #"\bwhile\b"#,
                        #"\bswitch\b"#, #"\bcase\b"#, #"\bcatch\b"#,
                        #"&&"#, #"\|\|"#, #"\?\:"#] {
            complexity += countMatches(of: pattern, in: stripped)
        }
        var depth = 0
        var maxDepth = 0
        for scalar in stripped.unicodeScalars {
            if scalar == "{" {
                depth += 1
                maxDepth = max(maxDepth, depth)
            } else if scalar == "}" {
                depth = max(0, depth - 1)
            }
        }
        return ComplexityFileResult(
            url: url, lines: lines, functions: functions,
            complexity: complexity, maxNestingDepth: maxDepth)
    }

    private static func countMatches(of pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Removes `//` and `/* */` comments and `"…"` string literals
    /// (keeping newlines so line counts stay aligned).
    static func stripCommentsAndStrings(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        var index = source.startIndex
        while index < source.endIndex {
            let ch = source[index]
            if ch == "/" {
                let next = source.index(after: index)
                if next < source.endIndex && source[next] == "/" {
                    while index < source.endIndex && source[index] != "\n" {
                        index = source.index(after: index)
                    }
                    continue
                }
                if next < source.endIndex && source[next] == "*" {
                    index = source.index(after: next)
                    while index < source.endIndex {
                        if source[index] == "*" {
                            let after = source.index(after: index)
                            if after < source.endIndex && source[after] == "/" {
                                index = source.index(after: after)
                                break
                            }
                        }
                        if source[index] == "\n" { out.append("\n") }
                        index = source.index(after: index)
                    }
                    continue
                }
            }
            if ch == "\"" {
                index = source.index(after: index)
                while index < source.endIndex {
                    if source[index] == "\\" {
                        index = source.index(after: index)
                        if index < source.endIndex { index = source.index(after: index) }
                        continue
                    }
                    if source[index] == "\"" {
                        index = source.index(after: index)
                        break
                    }
                    if source[index] == "\n" { out.append("\n") }
                    index = source.index(after: index)
                }
                continue
            }
            out.append(ch)
            index = source.index(after: index)
        }
        return out
    }
}
