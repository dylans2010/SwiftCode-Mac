import SwiftUI

struct GitDiffView: View {
    let hunks: [GitDiffHunk]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("File Change Diff Viewer", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                }

                if hunks.isEmpty {
                    ContentUnavailableView(
                        "No Changes Detected",
                        systemImage: "doc.text",
                        description: Text("There are no staged or unstaged diffs to view.")
                    )
                    .frame(height: 150)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(hunks) { hunk in
                                Text(hunk.header)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.12))

                                ForEach(hunk.lines, id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(lineColor(line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(lineBackgroundColor(line))
                                }
                            }
                        }
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(6)
                    }
                    .frame(maxHeight: 400)
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .white.opacity(0.85)
    }

    private func lineBackgroundColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.1) }
        if line.hasPrefix("-") { return .red.opacity(0.1) }
        return .clear
    }
}
