// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/Legacy/GitFileRowView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Adaptation: GitFileStatus.path is String in the destination model (URL in Legacy): lastPathComponent via URL(fileURLWithPath:).
import SwiftUI
import SwiftCodeSDK

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
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                    .font(.body.bold())
                Text(file.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .liquidGlass(style: .subtle, cornerRadius: 6)
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
