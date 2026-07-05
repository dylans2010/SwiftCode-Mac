import SwiftUI

// MARK: - Complexity Analyzer View

struct ComplexityAnalyzerView: View {
    @EnvironmentObject private var projectManager: ProjectManager

    @State private var fileResults: [FileComplexityResult] = []
    @State private var isAnalyzing = false
    @State private var selectedSort: SortOption = .complexity
    @State private var selectedFile: FileComplexityResult?

    enum SortOption: String, CaseIterable {
        case complexity = "Complexity"
        case lines      = "Lines"
        case functions  = "Functions"
        case name       = "Name"
    }

    struct FileComplexityResult: Identifiable {
        let id = UUID()
        var fileName: String
        var filePath: String
        var statistics: CodeStatistics
        var symbols: [CodeSymbol]

        var complexityLabel: String {
            let score = statistics.complexityScore
            if score > 50 { return "Very High" }
            if score > 30 { return "High" }
            if score > 15 { return "Medium" }
            return "Low"
        }

        var complexityColor: String {
            let score = statistics.complexityScore
            if score > 50 { return "red" }
            if score > 30 { return "orange" }
            if score > 15 { return "yellow" }
            return "green"
        }
    }

    private static let maxComplexityGaugeScore: CGFloat = 50

    private var sortedResults: [FileComplexityResult] {
        switch selectedSort {
        case .complexity: return fileResults.sorted { $0.statistics.complexityScore > $1.statistics.complexityScore }
        case .lines:      return fileResults.sorted { $0.statistics.totalLines > $1.statistics.totalLines }
        case .functions:  return fileResults.sorted { $0.statistics.functionCount > $1.statistics.functionCount }
        case .name:       return fileResults.sorted { $0.fileName < $1.fileName }
        }
    }

    private var projectScore: Int {
        guard !fileResults.isEmpty else { return 0 }
        return fileResults.reduce(0) { $0 + $1.statistics.complexityScore } / fileResults.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.06, blue: 0.12), Color(red: 0.10, green: 0.08, blue: 0.14)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !fileResults.isEmpty {
                        summaryBanner
                        Divider().opacity(0.3)
                        sortBar
                        Divider().opacity(0.3)
                    }
                    if isAnalyzing {
                        analyzingView
                    } else if fileResults.isEmpty {
                        emptyView
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Complexity Analyzer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await analyzeProject() }
                    } label: {
                        Label("Analyze", systemImage: "chart.xyaxis.line")
                            .foregroundStyle(.purple)
                    }
                    .disabled(isAnalyzing || projectManager.activeProject == nil)
                }
            }
            .sheet(item: $selectedFile) { result in
                fileDetailSheet(result)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary Banner

    private var summaryBanner: some View {
        HStack(spacing: 20) {
            summaryCell(label: "Files", value: "\(fileResults.count)", color: .cyan)
            summaryCell(label: "Avg Score", value: "\(projectScore)", color: projectScoreColor)
            summaryCell(label: "Functions", value: "\(fileResults.reduce(0) { $0 + $1.statistics.functionCount })", color: .blue)
            summaryCell(label: "Total Lines", value: "\(fileResults.reduce(0) { $0 + $1.statistics.totalLines })", color: .purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func summaryCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var projectScoreColor: Color {
        if projectScore > 30 { return .red }
        if projectScore > 15 { return .orange }
        return .green
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortOption.allCases, id: \.rawValue) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedSort == option ? Color.purple.opacity(0.35) : Color.white.opacity(0.07), in: Capsule())
                            .foregroundStyle(selectedSort == option ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedResults) { result in
                    fileRow(result)
                        .onTapGesture { selectedFile = result }
                }
            }
            .padding(16)
        }
    }

    private func fileRow(_ result: FileComplexityResult) -> some View {
        HStack(spacing: 12) {
            // Complexity gauge
            ZStack {
                Circle()
                    .stroke(complexityColor(result).opacity(0.25), lineWidth: 4)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: min(CGFloat(result.statistics.complexityScore) / Self.maxComplexityGaugeScore, 1.0))
                    .stroke(complexityColor(result), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text("\(result.statistics.complexityScore)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(complexityColor(result))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(result.fileName)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    statLabel("\(result.statistics.totalLines) lines", color: .secondary)
                    statLabel("\(result.statistics.functionCount) funcs", color: .blue)
                    statLabel(result.complexityLabel, color: complexityColor(result))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(complexityColor(result).opacity(0.2), lineWidth: 1)
        )
    }

    private func statLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
    }

    // MARK: - Empty / Analyzing

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 52))
                .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Complexity Analyzer")
                .font(.title2.bold()).foregroundStyle(.white)
            Text("Scan your project to detect code complexity, function counts, and maintainability scores for every Swift file.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if projectManager.activeProject != nil {
                Button { Task { await analyzeProject() } } label: {
                    Label("Analyze Project", systemImage: "chart.xyaxis.line")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var analyzingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5).tint(.purple)
            Text("Analyzing files…").font(.headline).foregroundStyle(.white)
            Text("Scanning for complexity metrics").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - File Detail Sheet

    private func fileDetailSheet(_ result: FileComplexityResult) -> some View {
        NavigationStack {
            List {
                Section("Metrics") {
                    metricRow("Total Lines",   "\(result.statistics.totalLines)")
                    metricRow("Non-Empty",     "\(result.statistics.nonEmptyLines)")
                    metricRow("Comment Lines", "\(result.statistics.commentLines)")
                    metricRow("Functions",     "\(result.statistics.functionCount)")
                    metricRow("Classes",       "\(result.statistics.classCount)")
                    metricRow("Structs",       "\(result.statistics.structCount)")
                    metricRow("Complexity",    "\(result.statistics.complexityScore) (\(result.complexityLabel))")
                }

                Section("Symbols (\(result.symbols.count))") {
                    ForEach(result.symbols.prefix(50)) { symbol in
                        HStack {
                            Image(systemName: symbol.kind.icon)
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                            Text(symbol.name)
                                .font(.callout)
                            Spacer()
                            Text("L\(symbol.lineNumber)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(result.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selectedFile = nil }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary).bold()
        }
        .font(.callout)
    }

    // MARK: - Analysis Logic

    private func analyzeProject() async {
        guard let project = projectManager.activeProject else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        var results: [FileComplexityResult] = []
        let swiftFiles = collectSwiftFiles(from: project.files, projectURL: project.directoryURL)

        for (node, url) in swiftFiles {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let stats = CodeStructureAnalyzer.shared.statistics(for: content)
            let symbols = CodeStructureAnalyzer.shared.analyze(content)
            results.append(FileComplexityResult(
                fileName: node.name,
                filePath: node.path,
                statistics: stats,
                symbols: symbols
            ))
        }

        fileResults = results
    }

    private func collectSwiftFiles(from nodes: [FileNode], projectURL: URL) -> [(FileNode, URL)] {
        var result: [(FileNode, URL)] = []
        for node in nodes {
            if node.isDirectory {
                result.append(contentsOf: collectSwiftFiles(from: node.children, projectURL: projectURL))
            } else if node.name.hasSuffix(".swift") {
                result.append((node, projectURL.appendingPathComponent(node.path)))
            }
        }
        return result
    }

    // MARK: - Color Helpers

    private func complexityColor(_ result: FileComplexityResult) -> Color {
        switch result.complexityLabel {
        case "Very High": return .red
        case "High":      return .orange
        case "Medium":    return .yellow
        default:          return .green
        }
    }
}
