import SwiftUI

public struct NSMergeView: View {
    @State private var branchToMerge = ""
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Merge", systemImage: "arrow.triangle.merge")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Merge another branch into active HEAD.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Branch name to merge...", text: $branchToMerge)
                .textFieldStyle(.roundedBorder)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Merge Branch") {
                successMsg = "Successfully merged branch '\(branchToMerge)'."
                branchToMerge = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(branchToMerge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
