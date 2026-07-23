import SwiftUI

public struct NSCreateRepositoryView: View {
    @State private var repoName = ""
    @State private var isPrivate = true
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Create Repository", systemImage: "folder.badge.plus")
                .font(.headline)
                .foregroundStyle(.blue)

            TextField("Repository name...", text: $repoName)
                .textFieldStyle(.roundedBorder)

            Toggle("Private Repository", isOn: $isPrivate)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Create on GitHub") {
                successMsg = "Repository '\(repoName)' created successfully."
                repoName = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
