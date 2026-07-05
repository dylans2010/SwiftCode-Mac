import SwiftUI

struct CodeChangesView: View {
    @ObservedObject private var patchEngine = CodePatchEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Code Changes")
                .font(.headline)

            if patchEngine.pendingPatches.isEmpty {
                Text("No Changes Suggested")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(patchEngine.pendingPatches) { patch in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.caption)
                            Text((patch.filePath as NSString).lastPathComponent)
                                .font(.subheadline.bold())
                            Spacer()

                            Button("Reject") {
                                patchEngine.rejectPatch(patch)
                            }
                            .font(.caption)
                            .foregroundColor(.red)

                            Button("Apply") {
                                try? patchEngine.applyPatch(patch)
                            }
                            .font(.caption.bold())
                            .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            let lines = patch.diff.components(separatedBy: .newlines).filter { !$0.isEmpty }
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(lineColor(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .background(lineBackground(line))
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .primary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.1) }
        if line.hasPrefix("-") { return .red.opacity(0.1) }
        return .clear
    }
}
