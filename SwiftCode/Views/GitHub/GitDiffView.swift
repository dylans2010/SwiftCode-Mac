import SwiftUI

struct GitDiffView: View {
    let hunks: [GitDiffHunk]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    Text(hunk.header)
                        .font(.monospacedSystemFont(ofSize: 11, weight: .bold))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))

                    ForEach(hunk.lines, id: \.self) { line in
                        Text(line)
                            .font(.monospacedSystemFont(ofSize: 11, weight: .regular))
                            .foregroundStyle(lineColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(lineBackgroundColor(line))
                    }
                }
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .primary
    }

    private func lineBackgroundColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.1) }
        if line.hasPrefix("-") { return .red.opacity(0.1) }
        return .clear
    }
}
