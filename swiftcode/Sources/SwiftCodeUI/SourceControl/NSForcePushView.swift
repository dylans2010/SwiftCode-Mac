import SwiftCodeIDECore
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/NSForcePushView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// Force-push dialog for the current branch. Legacy drove this through
/// `ProjectSessionStore` + `GitMenuBarCommandExecutor`; this port takes the
/// `GitRepository` directly. The "Use force with lease (Safer)" toggle is
/// real: on → `--force-with-lease`, off → plain `--force`, via the
/// `forceLease` parameter added to `GitRepository.push` for this port
/// (the destination previously only ever used `--force-with-lease`).
///
/// Hook: present from the source-control navigator's push menu / the
/// `SourceControlCoordinator` (its `push(branch:remote:setUpstream:force:forceLease:)`
/// now exposes the same options for menu/MCP callers).
@MainActor
public struct NSForcePushView: View {
    public var repository: GitRepository
    @Environment(\.dismiss) private var dismiss

    @State private var useForceWithLease = true
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
            Label("Force Push", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Force-pushing rewrites history on the remote. Anyone else working on \(currentBranch) will need to re-sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentBranch)
                    .font(.subheadline.monospaced())
            }

            HStack {
                Text("Remote")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(remoteName)
                    .font(.subheadline.monospaced())
            }

            Toggle("Use force with lease (Safer)", isOn: $useForceWithLease)
            Text("Force with lease refuses when the remote moved since your last fetch; plain force overwrites unconditionally.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if didPush {
                Label("Pushed \(currentBranch) to \(remoteName).", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Force Push") {
                    Task { await forcePush() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isPushing)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func forcePush() async {
        isPushing = true
        errorMessage = nil
        didPush = false
        defer { isPushing = false }
        do {
            try await Task.detached {
                try self.repository.push(remote: self.remoteName, branch: self.currentBranch,
                                       force: true, forceLease: self.useForceWithLease)
            }.value
            didPush = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
