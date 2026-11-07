import YcodeIDECore
import SwiftUI

@MainActor
public struct NSPushOptionsView: View {
    public var repository: GitRepository
    @Environment(\.dismiss) private var dismiss

    @State private var setUpstream = false
    @State private var pushAllBranches = false
    @State private var isPushing = false
    @State private var errorMessage: String?
    @State private var didPush = false

    public init(repository: GitRepository) {
        self.repository = repository
    }

    private var currentBranch: String { repository.currentBranch() ?? "HEAD" }
    private var remoteName: String {
        (try? repository.remotes().first?.name) ?? "origin"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Push Options", systemImage: "arrow.up.to.line")
                .font(.headline)

            Toggle("Set upstream for \(currentBranch)", isOn: $setUpstream)
            Toggle("Push all branches", isOn: $pushAllBranches)

            Text(pushAllBranches
                 ? "Pushes every local branch to \(remoteName)."
                 : "Pushes \(currentBranch) to \(remoteName).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if didPush {
                Label("Push complete.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Apply & Push") {
                    Task { await applyAndPush() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPushing)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func applyAndPush() async {
        isPushing = true
        errorMessage = nil
        didPush = false
        defer { isPushing = false }
        do {
            try await Task.detached {
                if self.pushAllBranches {
                    try self.repository.pushAll(remote: self.remoteName)
                } else {
                    try self.repository.push(remote: self.remoteName, branch: self.currentBranch,
                                           setUpstream: self.setUpstream)
                }
            }.value
            didPush = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
