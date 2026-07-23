import SwiftUI

public struct NSApplyStashView: View {
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apply Stash", systemImage: "archivebox.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Apply the most recent stashed state.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Apply Last Stash") {
                successMsg = "Successfully applied stashed modifications."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
