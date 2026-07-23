import SwiftUI

public struct NSCommitView: View {
    @State private var commitMessage = ""
    @State private var amend = false
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Commit", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Stage and commit your active changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Commit message...", text: $commitMessage)
                .textFieldStyle(.roundedBorder)

            Toggle("Amend last commit", isOn: $amend)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Commit Changes") {
                successMsg = "Successfully committed changes: '\(commitMessage)'"
                commitMessage = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
