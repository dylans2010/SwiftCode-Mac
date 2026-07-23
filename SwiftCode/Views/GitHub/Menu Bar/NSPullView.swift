import SwiftUI

public struct NSPullView: View {
    @State private var useRebase = false
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Pull", systemImage: "arrow.down.circle.fill")
                .font(.headline)
                .foregroundStyle(.cyan)

            Text("Fetch and integrate remote changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Rebase local commits instead of merge", isOn: $useRebase)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Pull changes") {
                successMsg = "Pulled and merged remote changes."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
