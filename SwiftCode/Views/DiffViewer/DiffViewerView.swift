import SwiftUI

struct DiffViewerView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var originalContent = ""
    @State private var modifiedContent = ""
    @State private var diffLines: [DiffLine] = []

    struct DiffLine: Identifiable {
        let id = UUID()
        let lineNumber: Int
        let text: String
        let type: DiffType

        enum DiffType {
            case unchanged
            case added
            case removed
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if diffLines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("No Changes To Display")
                            .foregroundStyle(.secondary)
                        Text("Edits to the current file will appear here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diffLines) { line in
                                HStack(spacing: 4) {
                                    Text("\(line.lineNumber)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .trailing)

                                    Text(prefixForType(line.type))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(colorForType(line.type))
                                        .frame(width: 14)

                                    Text(line.text)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(backgroundForType(line.type))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Diff Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { computeDiff() }
        }
    }

    private func prefixForType(_ type: DiffLine.DiffType) -> String {
        switch type {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private func colorForType(_ type: DiffLine.DiffType) -> Color {
        switch type {
        case .unchanged: return .secondary
        case .added: return .green
        case .removed: return .red
        }
    }

    private func backgroundForType(_ type: DiffLine.DiffType) -> Color {
        switch type {
        case .unchanged: return .clear
        case .added: return .green.opacity(0.1)
        case .removed: return .red.opacity(0.1)
        }
    }

    private func computeDiff() {
        guard let project = projectManager.activeProject,
              let node = projectManager.activeFileNode else { return }

        let fileURL = project.directoryURL.appendingPathComponent(node.path)
        let diskContent = (try? String(contentsOf: fileURL.standardizedFileURL, encoding: .utf8)) ?? ""
        let editorContent = projectManager.activeFileContent

        originalContent = diskContent
        modifiedContent = editorContent

        let origLines = diskContent.components(separatedBy: "\n")
        let modLines = editorContent.components(separatedBy: "\n")

        var result: [DiffLine] = []
        let maxLines = max(origLines.count, modLines.count)

        for i in 0..<maxLines {
            let origLine = i < origLines.count ? origLines[i] : nil
            let modLine = i < modLines.count ? modLines[i] : nil

            if origLine == modLine {
                result.append(DiffLine(lineNumber: i + 1, text: origLine ?? "", type: .unchanged))
            } else {
                if let orig = origLine {
                    result.append(DiffLine(lineNumber: i + 1, text: orig, type: .removed))
                }
                if let mod = modLine {
                    result.append(DiffLine(lineNumber: i + 1, text: mod, type: .added))
                }
            }
        }

        diffLines = result
    }
}
