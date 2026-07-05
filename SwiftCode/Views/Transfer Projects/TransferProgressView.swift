import SwiftUI

struct TransferProgressView: View {
    @StateObject private var transferManager = ProjectTransferManager.shared

    var body: some View {
        ForEach(transferManager.sessions) { session in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.projectName)
                    Spacer()
                    Text(session.state.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: session.progress)
                Text("\(session.bytesTransferred) / \(session.totalBytes) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
