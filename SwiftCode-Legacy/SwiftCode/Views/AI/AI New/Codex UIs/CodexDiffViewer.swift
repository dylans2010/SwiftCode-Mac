import SwiftUI

struct CodexDiffViewer: View {
    @StateObject private var workspace = CodexWorkspaceStore.shared
    @State private var isSideBySide = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Diff Viewer", systemImage: "square.split.2x1")
                    .font(.headline)
                Spacer()
                Picker("Layout", selection: $isSideBySide) {
                    Text("Side by Side").tag(true)
                    Text("Inline").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            if workspace.renderedOutput.isEmpty {
                ContentUnavailableView("No Generated Output", systemImage: "doc.text.magnifyingglass", description: Text("Generate code to compare the latest result against the prior version."))
            } else if isSideBySide {
                HStack(alignment: .top, spacing: 12) {
                    diffColumn(title: "Previous", content: workspace.previousOutput.ifEmpty("No prior output yet."), tint: .secondary)
                    diffColumn(title: "Latest", content: workspace.renderedOutput, tint: .accentColor)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(diffRows.indices, id: \.self) { index in
                            let row = diffRows[index]
                            HStack(alignment: .top, spacing: 10) {
                                Text(row.prefix)
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .foregroundStyle(row.color)
                                    .frame(width: 16)
                                Text(row.line)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(row.color.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var diffRows: [(prefix: String, line: String, color: Color)] {
        let oldLines = workspace.previousOutput.components(separatedBy: .newlines)
        let newLines = workspace.renderedOutput.components(separatedBy: .newlines)
        let maxCount = max(oldLines.count, newLines.count)

        return (0..<maxCount).map { index in
            let oldLine = index < oldLines.count ? oldLines[index] : ""
            let newLine = index < newLines.count ? newLines[index] : ""
            if oldLine == newLine {
                return (" ", newLine, .secondary)
            } else if oldLine.isEmpty {
                return ("+", newLine, .green)
            } else if newLine.isEmpty {
                return ("-", oldLine, .red)
            } else {
                return ("~", "\(oldLine) → \(newLine)", .orange)
            }
        }
    }

    private func diffColumn(title: String, content: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            ScrollView {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
