import SwiftUI

public struct NSCherryPickView: View {
    @State private var commitSHA = ""
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Cherry Pick", systemImage: "arrow.triangle.pull")
                .font(.headline)
                .foregroundStyle(.purple)

            Text("Apply change introduced by existing commit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Commit SHA (e.g. d6f3e12)...", text: $commitSHA)
                .textFieldStyle(.roundedBorder)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Apply Commit") {
                successMsg = "Cherry-picked commit: \(commitSHA)"
                commitSHA = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(commitSHA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
