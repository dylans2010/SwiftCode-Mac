import SwiftUI

struct GitFileRowView: View {
    let file: GitFileStatus

    var body: some View {
        HStack {
            Text(file.status.rawValue)
                .font(.monospacedSystemFont(ofSize: 11, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 20)
            Text(file.path.lastPathComponent)
            Spacer()
        }
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
