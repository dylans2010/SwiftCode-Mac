import SwiftUI

public struct NSCreatePRView: View {
    @State private var prTitle = ""
    @State private var targetBranch = "main"
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Create Pull Request", systemImage: "arrow.up.right.square.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            TextField("PR Title...", text: $prTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Base Branch (e.g. main)...", text: $targetBranch)
                .textFieldStyle(.roundedBorder)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Publish Pull Request") {
                successMsg = "Pull request '\(prTitle)' submitted successfully."
                prTitle = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(prTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
