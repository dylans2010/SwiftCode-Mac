import SwiftUI

@MainActor
struct GitFileRowView: View {
    let file: GitFileStatus

    var body: some View {
        HStack(spacing: 8) {
            Text(file.status.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.path.lastPathComponent)
                    .font(.body.bold())
                Text(file.path.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .sourceControlEmbedded()
    }

    private var statusColor: Color {
        switch file.status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .conflicted: return .purple
        default: return .secondary
        }
    }
}
