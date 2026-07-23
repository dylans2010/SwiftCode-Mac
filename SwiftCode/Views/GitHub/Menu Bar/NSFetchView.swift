import SwiftUI

public struct NSFetchView: View {
    @State private var prune = true
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Fetch", systemImage: "arrow.down.and.line.horizontal.and.arrow.up")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Download references from remote without merging.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Prune stale remote branches (--prune)", isOn: $prune)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Fetch References") {
                successMsg = "References fetched successfully."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
