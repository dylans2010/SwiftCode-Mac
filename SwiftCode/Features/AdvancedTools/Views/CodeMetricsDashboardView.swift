import SwiftUI

struct CodeMetricsDashboardView: View {
    @EnvironmentObject private var projectManager: ProjectManager

    @State private var lintSummary = "Run SwiftLint to gather diagnostics."
    @State private var isLinting = false

    private var files: [FileNode] { projectManager.activeProject?.files.flatMapDeep(includeDirectories: false) ?? [] }
    private var swiftFiles: [FileNode] { files.filter { $0.name.hasSuffix(".swift") } }

    private var totalLOC: Int {
        guard let project = projectManager.activeProject else { return 0 }
        return files.reduce(0) { result, node in
            let url = project.directoryURL.appendingPathComponent(node.path)
            let text = (try? String(contentsOf: url)) ?? ""
            return result + text.split(separator: "\n", omittingEmptySubsequences: false).count
        }
    }

    var body: some View {
        AdvancedToolScreen(title: "Code Metrics") {
            HStack(spacing: 12) {
                MetricPill(label: "Files", value: "\(files.count)")
                MetricPill(label: "LOC", value: "\(totalLOC)")
                MetricPill(label: "Complexity", value: complexityLabel())
            }

            AdvancedToolCard(title: "Architecture Signals") {
                Text("Language Breakdown: \(languageBreakdown())")
                Text("Most Modified: \(projectManager.modifiedFilePaths.prefix(3).joined(separator: ", "))")
                    .foregroundStyle(.secondary)
            }

            AdvancedToolCard(title: "SwiftLint Diagnostics") {
                HStack {
                    Button("Run SwiftLint") { runSwiftLint() }
                        .buttonStyle(.borderedProminent)
                    if isLinting { ProgressView() }
                }
                Text(lintSummary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func runSwiftLint() {
        guard let project = projectManager.activeProject else { return }
        isLinting = true
        Task {
            do {
                let lint = try await BinaryManager.shared.runSwiftLint(at: project.directoryURL.path)
                let output = lint.mergedOutput
                await MainActor.run {
                    lintSummary = output.isEmpty ? "SwiftLint completed with no output." : output
                    isLinting = false
                }
            } catch {
                await MainActor.run {
                    lintSummary = "SwiftLint unavailable: \(error.localizedDescription)"
                    isLinting = false
                }
            }
        }
    }

    private func languageBreakdown() -> String {
        let groups = Dictionary(grouping: files, by: { $0.fileExtension.isEmpty ? "other" : $0.fileExtension })
        return groups.sorted(by: { $0.value.count > $1.value.count }).prefix(4).map { "\($0.key): \($0.value.count)" }.joined(separator: ", ")
    }

    private func complexityLabel() -> String {
        if totalLOC > 10_000 || swiftFiles.count > 120 { return "High" }
        if totalLOC > 3_000 || swiftFiles.count > 40 { return "Moderate" }
        return "Low"
    }
}

private extension Array where Element == FileNode {
    func flatMapDeep(includeDirectories: Bool) -> [FileNode] {
        flatMap { node in
            if node.isDirectory {
                return (includeDirectories ? [node] : []) + node.children.flatMapDeep(includeDirectories: includeDirectories)
            }
            return [node]
        }
    }
}
