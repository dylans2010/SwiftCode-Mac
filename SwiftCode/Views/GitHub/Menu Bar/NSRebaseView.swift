import SwiftUI

public struct NSRebaseView: View {
    @State private var upstreamBranch = "main"
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Rebase", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .foregroundStyle(.purple)

            Text("Rebase current branch onto upstream.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Upstream branch...", text: $upstreamBranch)
                .textFieldStyle(.roundedBorder)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Start Rebase") {
                successMsg = "Successfully rebased onto '\(upstreamBranch)'."
                upstreamBranch = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(upstreamBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
