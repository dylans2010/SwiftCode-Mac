import SwiftUI

struct ErrorDiagnosticsView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var logs = ""

    private var diagnostics: [BuildDiagnostic] {
        logs.split(separator: "\n").compactMap { BuildDiagnostic(line: String($0)) }
    }

    var body: some View {
        AdvancedToolScreen(title: "Error Diagnostics") {
            AdvancedToolCard(title: "Error Log Input") {
                TextField("Paste compile/runtime errors", text: $logs, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            AdvancedToolCard(title: "Parsed Diagnostics", subtitle: "Click an item to open the corresponding file") {
                ForEach(diagnostics) { item in
                    Button {
                        if let node = projectManager.activeProject?.files.flatMapDeep().first(where: { $0.path.contains(item.file) }) {
                            projectManager.openFile(node)
                        }
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

private struct BuildDiagnostic: Identifiable {
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

private extension Array where Element == FileNode {
    func flatMapDeep() -> [FileNode] {
        flatMap { node in
            node.isDirectory ? [node] + node.children.flatMapDeep() : [node]
        }
    }
}
