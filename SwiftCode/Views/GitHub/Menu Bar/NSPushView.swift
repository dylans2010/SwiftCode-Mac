import SwiftUI

public struct NSPushView: View {
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Push", systemImage: "arrow.up.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Push local commits to your remote origin.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Push commits") {
                successMsg = "Successfully pushed commits to remote."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
