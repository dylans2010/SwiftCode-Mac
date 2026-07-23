import SwiftUI

public struct NSCloneView: View {
    @State private var cloneURL = ""
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Clone", systemImage: "plus.square.on.square")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Clone a repository into your workspace.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Repository URL...", text: $cloneURL)
                .textFieldStyle(.roundedBorder)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Clone Repository") {
                successMsg = "Clone sequence initiated."
                cloneURL = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
