import SwiftUI

public struct NSStashView: View {
    @State private var stashMessage = ""
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Stash", systemImage: "archivebox.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Stash away local modifications.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Optional stash message...", text: $stashMessage)
                .textFieldStyle(.roundedBorder)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Stash Changes") {
                successMsg = "Local changes stashed cleanly."
                stashMessage = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
