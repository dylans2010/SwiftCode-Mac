import SwiftUI

struct GistRevisionsView: View {
    let gistId: String
    @EnvironmentObject private var gistService: GitHubGistService
    @State private var revisions: [GistRevision] = []
    @State private var isLoading = false
    @State private var selectedRevision: GistRevision?
    @State private var showDiff = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Fetching revisions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if revisions.isEmpty {
                Text("No revisions found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(revisions) { revision in
                    Button {
                        selectedRevision = revision
                        showDiff = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(revision.version.prefix(7))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.white)

                                Spacer()

                                Text(revision.committedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                if let avatar = revision.user?.avatarUrl, let url = URL(string: avatar) {
                                    AsyncImage(url: url) { image in
                                        image.resizable()
                                    } placeholder: {
                                        Color.gray
                                    }
                                    .frame(width: 16, height: 16)
                                    .clipShape(Circle())
                                }

                                Text(revision.user?.login ?? "anonymous")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let status = revision.changeStatus {
                                    HStack(spacing: 4) {
                                        Text("+\(status.additions ?? 0)")
                                            .foregroundStyle(.green)
                                        Text("-\(status.deletions ?? 0)")
                                            .foregroundStyle(.red)
                                    }
                                    .font(.caption2.weight(.bold))
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Revisions")
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        .sheet(item: $selectedRevision) { revision in
            GistDiffView(gistId: gistId, revision: revision)
        }
        .task {
            await loadRevisions()
        }
    }

    private func loadRevisions() async {
        isLoading = true
        do {
            revisions = try await gistService.fetchRevisions(gistId: gistId)
        } catch {
            print("Failed to load revisions: \(error)")
        }
        isLoading = false
    }
}
