import Foundation
import SwiftUI
import SwiftCodeIDECore

/// Advanced Tools views (Legacy `SwiftCode/Features/AdvancedTools/Views/`,
/// Dylan's own code, ported under MIT), rebuilt in SwiftCode style: default
/// accent, no Legacy orange, no liquid-glass modifiers. Every view takes
/// its inputs explicitly (a workspace root URL and/or a file URL) instead
/// of reading Legacy's `ProjectSessionStore`, which does not exist here.
/// The host wires these views to the open workspace; see the wiring list.
/// Tree-sitter is omitted from the refactoring view (no tree-sitter in the
/// destination) and Graphviz is never auto-installed (Legacy installed it
/// via Homebrew without asking; this port reports it missing with a remedy).

// MARK: - Shared screen/card/pill (Legacy AdvancedToolsSharedDesignSystem)

struct AdvancedToolScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(20)
            }
            .navigationTitle(title)
        }
    }
}

struct AdvancedToolCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Subprocess helper

enum AdvancedToolRunner {
    static func path(for name: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin")
            .split(separator: ":").map(String.init)
        for dir in paths {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Runs a tool synchronously; call from a detached task, never the main actor.
    static func run(_ path: String, args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - Code intelligence

struct CodeIntelligenceView: View {
    var fileContent: String
    @State private var completions: [String] = []
    @State private var symbols: [String] = []
    @State private var docs: [String: String] = [:]

    private func refresh() {
        let engine = CodeIntelligenceEngine.shared
        engine.index(content: fileContent)
        completions = engine.completions
        symbols = engine.symbols
        docs = Dictionary(uniqueKeysWithValues: symbols.map { ($0, engine.quickDoc(for: $0)) })
    }

    var body: some View {
        AdvancedToolScreen(title: "Code Intelligence") {
            AdvancedToolCard(title: "Realtime Index") {
                HStack {
                    Button("Refresh Intelligence") { refresh() }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    MetricPill(label: "Suggestions", value: "\(completions.count)").frame(maxWidth: 180)
                }
            }
            AdvancedToolCard(title: "Autocomplete Suggestions") {
                ForEach(completions, id: \.self) { Text("• \($0)") }
            }
            AdvancedToolCard(title: "Detected Symbols") {
                ForEach(symbols, id: \.self) { symbol in
                    VStack(alignment: .leading) {
                        Text(symbol).font(.callout.monospaced())
                        Text(docs[symbol] ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { refresh() }
    }
}

// MARK: - Symbol index

struct SymbolIndexView: View {
    var rootURL: URL?
    @State private var query = ""
    @State private var symbols: [IndexedSymbol] = []

    private var filtered: [IndexedSymbol] {
        guard !query.isEmpty else { return symbols }
        return symbols.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        AdvancedToolScreen(title: "Symbol Index") {
            AdvancedToolCard(title: "Search Symbols") {
                TextField("Search Symbol", text: $query).textFieldStyle(.roundedBorder)
            }
            AdvancedToolCard(title: "Indexed Symbols") {
                ForEach(filtered) { symbol in
                    VStack(alignment: .leading) {
                        Text("\(symbol.kind): \(symbol.name)").font(.callout.monospaced())
                        Text("\(symbol.file):\(symbol.line)").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .onAppear {
            let engine = SymbolIndexingEngine.shared
            engine.index(rootURL: rootURL)
            symbols = engine.symbols
        }
    }
}

// MARK: - Code metrics

struct CodeMetricsDashboardView: View {
    var rootURL: URL?
    @State private var fileCount = 0
    @State private var totalLOC = 0
    @State private var swiftFileCount = 0
    @State private var languageBreakdown = ""
    @State private var lintSummary = "Run SwiftLint to gather diagnostics."
    @State private var isLinting = false

    private func complexityLabel() -> String {
        if totalLOC > 10_000 || swiftFileCount > 120 { return "High" }
        if totalLOC > 3_000 || swiftFileCount > 40 { return "Moderate" }
        return "Low"
    }

    var body: some View {
        AdvancedToolScreen(title: "Code Metrics") {
            HStack(spacing: 12) {
                MetricPill(label: "Files", value: "\(fileCount)")
                MetricPill(label: "LOC", value: "\(totalLOC)")
                MetricPill(label: "Complexity", value: complexityLabel())
            }
            AdvancedToolCard(title: "Architecture Signals") {
                Text("Language Breakdown: \(languageBreakdown)")
            }
            AdvancedToolCard(title: "SwiftLint Diagnostics") {
                HStack {
                    Button("Run SwiftLint") { runSwiftLint() }.buttonStyle(.borderedProminent)
                    if isLinting { ProgressView() }
                }
                Text(lintSummary).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { computeMetrics() }
    }

    private func computeMetrics() {
        guard let rootURL else { return }
        Task.detached {
            var files = 0
            var loc = 0
            var swift = 0
            var groups: [String: Int] = [:]
            let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let fileURL = enumerator?.nextObject() as? URL {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                files += 1
                let ext = fileURL.pathExtension.isEmpty ? "other" : fileURL.pathExtension
                groups[ext, default: 0] += 1
                if ext == "swift" { swift += 1 }
                if let text = try? String(contentsOf: fileURL) {
                    loc += text.split(separator: "\n", omittingEmptySubsequences: false).count
                }
            }
            let breakdown = groups.sorted { $0.value > $1.value }.prefix(4)
                .map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            await MainActor.run {
                fileCount = files
                totalLOC = loc
                swiftFileCount = swift
                languageBreakdown = breakdown
            }
        }
    }

    private func runSwiftLint() {
        guard let rootURL else {
            lintSummary = "Open a workspace before running SwiftLint."
            return
        }
        guard let swiftlint = AdvancedToolRunner.path(for: "swiftlint") else {
            lintSummary = "SwiftLint is not installed (no `swiftlint` on PATH). Install it with: brew install swiftlint"
            return
        }
        isLinting = true
        Task.detached {
            let result = AdvancedToolRunner.run(swiftlint, args: ["lint", "--path", rootURL.path])
            await MainActor.run {
                lintSummary = result.output.isEmpty ? "SwiftLint completed with no output." : result.output
                isLinting = false
            }
        }
    }
}

// MARK: - Code refactoring

struct CodeRefactoringView: View {
    var fileURL: URL?
    var onContentChanged: ((String) -> Void)? = nil
    @State private var originalContent = ""
    @State private var fromText = ""
    @State private var toText = ""
    @State private var preview = ""
    @State private var status = ""

    var body: some View {
        AdvancedToolScreen(title: "Code Refactoring") {
            AdvancedToolCard(title: "Global Rename") {
                TextField("Old Symbol", text: $fromText).textFieldStyle(.roundedBorder)
                TextField("New Symbol", text: $toText).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Preview Rename") {
                        preview = originalContent.replacingOccurrences(of: fromText, with: toText)
                    }
                    Button("Apply Rename") { apply(content: preview) }
                }
                .buttonStyle(.bordered)
            }
            AdvancedToolCard(title: "Transformations") {
                HStack {
                    Button("Extract to Function") {
                        preview = originalContent + "\n\nfunc extractedFunction() {\n    // Extracted code\n}"
                    }
                    Button("To async/await") {
                        preview = originalContent.replacingOccurrences(of: "completion:", with: "async")
                    }
                    Button("Run SwiftFormat") { runFormatter() }
                }
                .buttonStyle(.bordered)
            }
            AdvancedToolCard(title: "Preview") {
                ScrollView { Text(preview).frame(maxWidth: .infinity, alignment: .leading).font(.caption.monospaced()) }
                    .frame(minHeight: 180)
                Button("Confirm All Changes") { apply(content: preview) }.buttonStyle(.borderedProminent)
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if let fileURL, let content = try? String(contentsOf: fileURL) {
                originalContent = content
                preview = content
            }
        }
    }

    private func apply(content: String) {
        guard let fileURL, !content.isEmpty else { return }
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            originalContent = content
            status = "Saved to \(fileURL.lastPathComponent)."
            onContentChanged?(content)
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    private func runFormatter() {
        guard let swiftformat = AdvancedToolRunner.path(for: "swiftformat") else {
            preview = originalContent.replacingOccurrences(of: "\t", with: "    ")
            status = "swiftformat is not installed; tabs were expanded to spaces instead."
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-format-\(UUID().uuidString).swift")
        do {
            try originalContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            preview = originalContent
            return
        }
        Task.detached {
            _ = AdvancedToolRunner.run(swiftformat, args: [tempURL.path])
            let updated = (try? String(contentsOf: tempURL)) ?? originalContent
            await MainActor.run { preview = updated }
        }
    }
}

// MARK: - Crash log analyzer

private struct CrashAnalysis {
    let failingFunction: String
    let likelyCause: String
    let fileHints: [String]

    static func parse(log: String) -> Self {
        let lines = log.split(separator: "\n").map(String.init)
        let frame = lines.first(where: { $0.contains(" 0 ") || $0.localizedCaseInsensitiveContains("fatal error") || $0.localizedCaseInsensitiveContains("terminating app") }) ?? "Unknown function"
        let reason = lines.first(where: { $0.localizedCaseInsensitiveContains("reason:") || $0.localizedCaseInsensitiveContains("fatal error") }) ?? "Cause not found in log."
        let fileRefs = lines.filter { $0.contains(".swift") }.prefix(8)
        return .init(failingFunction: frame, likelyCause: reason, fileHints: Array(fileRefs))
    }
}

struct CrashLogAnalyzerView: View {
    @State private var crashLog = ""
    private var parsed: CrashAnalysis { CrashAnalysis.parse(log: crashLog) }

    var body: some View {
        AdvancedToolScreen(title: "Crash Log Analyzer") {
            AdvancedToolCard(title: "Crash Input") {
                TextField("Paste crash log", text: $crashLog, axis: .vertical).textFieldStyle(.roundedBorder)
            }
            AdvancedToolCard(title: "Failing Function") { Text(parsed.failingFunction) }
            AdvancedToolCard(title: "Likely Cause") { Text(parsed.likelyCause) }
            AdvancedToolCard(title: "Relevant Locations") { Text(parsed.fileHints.joined(separator: "\n")) }
        }
    }
}

// MARK: - Error diagnostics

private struct DiagnosticLogEntry: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    let message: String
    let explanation: String

    init?(line: String) {
        let parts = line.split(separator: ":")
        guard parts.count >= 3, let lineNo = Int(parts[1]) else { return nil }
        file = String(parts[0])
        self.line = lineNo
        message = parts.dropFirst(2).joined(separator: ":")
        let lower = message.lowercased()
        if lower.contains("cannot find") {
            explanation = "Undefined symbol or missing import. Check symbol spelling and module imports."
        } else if lower.contains("cannot convert") || lower.contains("type") {
            explanation = "Type mismatch. Verify argument and return types around this line."
        } else if lower.contains("no such module") {
            explanation = "Module is missing from package dependencies or build settings."
        } else {
            explanation = "Compiler/runtime reported this issue. Inspect surrounding code and recent edits."
        }
    }
}

struct ErrorDiagnosticsView: View {
    var onOpenFile: ((String, Int) -> Void)? = nil
    @State private var logs = ""

    private var diagnostics: [DiagnosticLogEntry] {
        logs.split(separator: "\n").compactMap { DiagnosticLogEntry(line: String($0)) }
    }

    var body: some View {
        AdvancedToolScreen(title: "Error Diagnostics") {
            AdvancedToolCard(title: "Error Log Input") {
                TextField("Paste compile/runtime errors", text: $logs, axis: .vertical).textFieldStyle(.roundedBorder)
            }
            AdvancedToolCard(title: "Parsed Diagnostics", subtitle: "Select an item to open the corresponding file") {
                ForEach(diagnostics) { item in
                    Button {
                        onOpenFile?(item.file, item.line)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(item.file):\(item.line)").font(.headline)
                            Text(item.message).font(.subheadline)
                            Text(item.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

// MARK: - Dependency graph

struct ProjectDependencyGraphView: View {
    var rootURL: URL?
    @State private var isGenerating = false
    @State private var graphOutput = ""
    @State private var generatedSVGPath: String?
    @State private var dependencyRows: [(String, [String])] = []
    @State private var showDOTSource = false
    @State private var lastDOT = ""

    var body: some View {
        AdvancedToolScreen(title: "Dependency Graph") {
            AdvancedToolCard(title: "Swift Import Graph", subtitle: "Parsed from imports, rendered through Graphviz") {
                HStack {
                    Button("Generate Graph") { generateGraph() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating)
                    Toggle("DOT source", isOn: $showDOTSource).font(.caption).controlSize(.small)
                    if isGenerating { ProgressView() }
                    Spacer()
                    if let svgPath = generatedSVGPath {
                        Text(svgPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if !dependencyRows.isEmpty {
                    Divider()
                    ForEach(dependencyRows, id: \.0) { file, imports in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(file).font(.headline)
                            Text(imports.isEmpty ? "No imports" : imports.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
                if !graphOutput.isEmpty {
                    Text(graphOutput).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                if showDOTSource, !lastDOT.isEmpty {
                    Divider()
                    DisclosureGroup("DOT Source") {
                        ScrollView([.horizontal, .vertical]) {
                            Text(lastDOT).font(.caption.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }
        }
        .onAppear {
            if AdvancedToolRunner.path(for: "dot") == nil {
                graphOutput = "Graphviz is not available (no `dot` on PATH). Install it with: brew install graphviz. The import list and DOT source below still work without it."
            }
        }
    }

    private func generateGraph() {
        guard let rootURL else {
            graphOutput = "Open a workspace before generating a graph."
            return
        }
        isGenerating = true
        Task {
            let rows = collectDependencies(from: rootURL)
            let dot = makeDOT(rows)
            var message: String
            var svgPath: String?
            if let dotBin = AdvancedToolRunner.path(for: "dot") {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swiftcode-dependencies-\(UUID().uuidString).svg")
                let dotURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swiftcode-dependencies-\(UUID().uuidString).dot")
                try? dot.write(to: dotURL, atomically: true, encoding: .utf8)
                let result = AdvancedToolRunner.run(dotBin, args: ["-Tsvg", dotURL.path, "-o", outputURL.path])
                if result.status == 0 {
                    svgPath = outputURL.path
                    message = "Graph rendered successfully:\n\(outputURL.path)"
                } else {
                    message = "Graphviz render failed\(result.output.isEmpty ? "" : ": \(result.output)"). Enable DOT source above to inspect the graph definition."
                }
            } else {
                message = "Graphviz is not available (no `dot` on PATH). Install it with: brew install graphviz. The import list and DOT source below were still generated."
            }
            await MainActor.run {
                dependencyRows = rows
                lastDOT = dot
                graphOutput = message
                generatedSVGPath = svgPath
                isGenerating = false
            }
        }
    }

    private func collectDependencies(from rootURL: URL) -> [(String, [String])] {
        var rows: [(String, [String])] = []
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let imports = ((try? String(contentsOf: fileURL)) ?? "")
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("import ") else { return nil }
                    return String(trimmed.dropFirst(7))
                }
            rows.append((fileURL.lastPathComponent, imports))
        }
        return rows.sorted { $0.0 < $1.0 }
    }

    private func makeDOT(_ rows: [(String, [String])]) -> String {
        var lines = ["digraph SwiftDependencies {", "rankdir=LR;"]
        for (file, imports) in rows {
            let escapedFile = file.replacingOccurrences(of: "\"", with: "")
            if imports.isEmpty {
                lines.append("\"\(escapedFile)\";")
            } else {
                for module in imports {
                    let escapedModule = module.replacingOccurrences(of: "\"", with: "")
                    lines.append("\"\(escapedFile)\" -> \"\(escapedModule)\";")
                }
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
