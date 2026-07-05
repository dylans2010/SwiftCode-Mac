import SwiftUI

struct ProjectDependencyGraphView: View {
    @EnvironmentObject private var projectManager: ProjectManager

    @State private var isGenerating = false
    @State private var graphOutput = ""
    @State private var dependencyRows: [(String, [String])] = []

    var body: some View {
        AdvancedToolScreen(title: "Dependency Graph") {
            AdvancedToolCard(title: "Swift Import Graph", subtitle: "Parsed from imports, rendered through Graphviz when available") {
                HStack {
                    Button("Generate Graph") { generateGraph() }
                        .buttonStyle(.borderedProminent)
                    if isGenerating { ProgressView() }
                }

                if !dependencyRows.isEmpty {
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
            }
        }
        .onAppear(perform: generateGraph)
    }

    private func generateGraph() {
        guard let project = projectManager.activeProject else { return }
        isGenerating = true

        Task {
            let rows = collectDependencies(from: project)
            let dot = makeDOT(rows)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-dependencies-\(UUID().uuidString).svg")

            let message: String
            do {
                let result = try await BinaryManager.shared.generateDependencyGraph(dotSource: dot, outputPath: outputURL.path)
                if result.isSuccess {
                    message = "Graphviz output generated at: \(outputURL.path)"
                } else {
                    message = "Graphviz failed, showing DOT source.\n\n\(dot)"
                }
            } catch {
                message = "Graphviz unavailable, showing DOT source.\n\n\(dot)"
            }

            await MainActor.run {
                dependencyRows = rows
                graphOutput = message
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
