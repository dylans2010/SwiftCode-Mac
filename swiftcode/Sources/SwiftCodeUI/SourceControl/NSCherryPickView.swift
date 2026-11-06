import SwiftCodeIDECore
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/NSCherryPickView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// Commit-picker dialog for cherry-picking.
///
/// Legacy listed REMOTE GitHub commits (`GitHubService` / `APIKeyManager`)
/// and executed through `GitMenuBarCommandExecutor`. This port lists the
/// LOCAL history via `GitRepository.log(limit:)` — the commits that can
/// actually be cherry-picked into this checkout — with "Load more"
/// pagination, a SHA field, and Apply running the real
/// `GitRepository.cherryPick(_:)`.
///
/// Hook: present from the source-control navigator / history view. If a
/// cherry-pick conflicts, route through
/// `SourceControlCoordinator.cherryPick(_:)` instead, which runs the
/// conflict editor (`integrate` path); this dialog reports the failure and
/// leaves the working tree for the coordinator to reconcile.
@MainActor
public struct NSCherryPickView: View {
    public var repository: GitRepository
    @Environment(\.dismiss) private var dismiss

    @State private var commits: [GitRepository.Commit] = []
    @State private var selectedHash = ""
    @State private var limit = 50
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var didApply = false

    public init(repository: GitRepository) {
        self.repository = repository
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cherry-Pick Commit", systemImage: "arrow.down.to.line.compound")
                .font(.headline)

            Text("Pick a commit from this repository's history to apply on the current branch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Commit SHA", text: $selectedHash)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            List(commits, id: \.hash, selection: Binding(
                get: { selectedHash.isEmpty ? nil : selectedHash },
                set: { selectedHash = $0 ?? "" }
            )) { commit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.subject)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("\(commit.shortHash) · \(commit.authorName) · \(commit.date, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220)

            HStack {
                Button("Load more") {
                    limit += 50
                    loadCommits()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                Text("\(commits.count) commits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if didApply {
                Label("Cherry-picked \(selectedHash).", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Apply") {
                    Task { await applyCherryPick() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedHash.isEmpty || isApplying)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .onAppear { loadCommits() }
    }

    private func loadCommits() {
        commits = repository.log(limit: limit)
    }

    private func applyCherryPick() async {
        isApplying = true
        errorMessage = nil
        didApply = false
        defer { isApplying = false }
        do {
            try await Task.detached {
                try self.repository.cherryPick(self.selectedHash)
            }.value
            didApply = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
