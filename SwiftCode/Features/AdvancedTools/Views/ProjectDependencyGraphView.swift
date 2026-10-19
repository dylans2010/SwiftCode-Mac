import SwiftUI
import AppKit

struct ProjectDependencyGraphView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var isGenerating = false
    @State private var graphvizPhase: GraphvizPhase = .checking
    @State private var graphOutput = ""
    @State private var generatedSVGPath: String? = nil
    @State private var dependencyRows: [(String, [String])] = []
    @State private var showDOTSource = false
    @State private var lastDOT = ""

    private enum GraphvizPhase: Equatable {
        case checking
        case installing
        case ready
        case unavailable(remedy: String)
    }

    var body: some View {
        AdvancedToolScreen(title: "Dependency Graph") {
            AdvancedToolCard(title: "Swift Import Graph", subtitle: "Parsed from imports, rendered through Graphviz") {
                graphvizStatusRow

                HStack {
                    Button("Generate Graph") { generateGraph() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || graphvizPhase == .checking || graphvizPhase == .installing)
                    if isGenerating { ProgressView() }
                    Spacer()
                    if let svgPath = generatedSVGPath {
                        Button {
                            NSWorkspace.shared.selectFile(svgPath, inFileViewerRootedAtPath: (svgPath as NSString).deletingLastPathComponent)
                        } label: {
                            Label("Reveal SVG", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !dependencyRows.isEmpty {
                    Divider()
                    ForEach(dependencyRows, id: \.0) { file, imports in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(file).font(.headline)
                            Text(imports.isEmpty ? "No imports" : imports.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }

                if !graphOutput.isEmpty {
                    Text(graphOutput)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                if showDOTSource, !lastDOT.isEmpty {
                    Divider()
                    DisclosureGroup("DOT Source") {
                        ScrollView([.horizontal, .vertical]) {
                            Text(lastDOT)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }
        }
        .onAppear {
            Task { await ensureGraphviz() }
        }
    }

    // MARK: - Graphviz status

    @ViewBuilder
    private var graphvizStatusRow: some View {
        HStack(spacing: 8) {
            switch graphvizPhase {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking for Graphviz…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing Graphviz via Homebrew…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Graphviz available — graphs render to SVG")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("DOT source", isOn: $showDOTSource)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .controlSize(.small)
            case .unavailable(let remedy):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Graphviz is not available")
                        .font(.caption.bold())
                    Text(remedy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Retry") {
                    Task { await ensureGraphviz() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Toggle("DOT source", isOn: $showDOTSource)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func ensureGraphviz() async {
        await MainActor.run { graphvizPhase = .checking }
        let outcome = await BinaryManager.shared.ensureGraphvizAvailable()
        await MainActor.run {
            switch outcome {
            case .available, .installedNow:
                graphvizPhase = .ready
                if case .installedNow = outcome {
                    graphOutput = "Graphviz was installed via Homebrew and is now ready."
                }
                generateGraph()
            case .brewMissing:
                graphvizPhase = .unavailable(remedy: "Homebrew was not found, so automatic install is unavailable. Install Homebrew from https://brew.sh, then run: brew install graphviz")
            case .installFailed(let detail):
                graphvizPhase = .unavailable(remedy: "Automatic install failed. Run manually: brew install graphviz\n\n\(detail)")
            }
        }
    }

    // MARK: - Graph generation

    private func generateGraph() {
        guard let project = sessionStore.activeProject else { return }
        isGenerating = true

        Task {
            let rows = collectDependencies(from: project)
            let dot = makeDOT(rows)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-dependencies-\(UUID().uuidString).svg")

            var message: String
            var svgPath: String? = nil
            do {
                let result = try await BinaryManager.shared.generateDependencyGraph(dotSource: dot, outputPath: outputURL.path)
                if result.isSuccess {
                    svgPath = outputURL.path
                    message = "Graph rendered successfully:\n\(outputURL.path)"
                } else {
                    let detail = result.mergedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = "Graphviz render failed\(detail.isEmpty ? "" : ": \(detail)").\nEnable “DOT source” above to inspect the graph definition."
                }
            } catch {
                message = "Graphviz became unavailable (\(error.localizedDescription)). Enable “DOT source” above to inspect the graph definition."
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

    private func collectDependencies(from project: Project) -> [(String, [String])] {
        let files = project.files.flatMapDeep(includeDirectories: false).filter { $0.name.hasSuffix(".swift") }
        return files.map { node in
            let url = project.directoryURL.appendingPathComponent(node.path)
            let imports = ((try? String(contentsOf: url)) ?? "")
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("import ") else { return nil }
                    return String(trimmed.dropFirst(7))
                }
            return (node.name, imports)
        }
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
