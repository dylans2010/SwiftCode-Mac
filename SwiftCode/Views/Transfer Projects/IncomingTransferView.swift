import SwiftUI

struct IncomingTransferView: View {
    @StateObject private var transferManager = ProjectTransferManager.shared

    var body: some View {
        if let session = transferManager.incomingSession {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.projectName)
                    .font(.headline)
                Text("From: \(session.sender.displayName)")
                    .font(.subheadline)
                Text("Preset: \(session.permission.preset.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reject", role: .destructive) { transferManager.respondToIncoming(accept: false) }
                    Button("Accept") { transferManager.respondToIncoming(accept: true) }
                }
            }
        }
    }
}
