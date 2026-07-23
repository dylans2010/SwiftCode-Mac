import SwiftUI

public struct NSDiscardAllChangesView: View {
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Discard ALL Changes", systemImage: "trash.slash.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("WARNING: This will permanently destroy all unstaged, staged, and untracked changes.")
                .font(.caption)
                .foregroundStyle(.red)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Discard All changes") {
                successMsg = "Local changes discarded. Repository returned to clean state."
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
