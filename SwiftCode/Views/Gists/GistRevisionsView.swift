import SwiftUI

struct GistRevisionsView: View {
    let gistId: String
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss
    @State private var revisions: [GistRevision] = []
    @State private var isLoading = false
    @State private var selectedRevision: GistRevision?

    var body: some View {
        VStack(spacing: 0) {
            // Header Card
            HStack {
                Label("Revision History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Browse and view changes for past revisions of this gist.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Revisions List Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Versions", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            if isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView("Fetching revisions...")
                                        .padding()
                                    Spacer()
                                }
                            } else if revisions.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No revisions found")
                                        .foregroundStyle(.secondary)
                                        .padding()
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(revisions) { revision in
                                        Button {
                                            selectedRevision = revision
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text(revision.version.prefix(7))
                                                        .font(.system(.subheadline, design: .monospaced))
                                                        .fontWeight(.bold)
                                                        .foregroundStyle(.primary)

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
                                            .padding(12)
                                            .background(Color.secondary.opacity(0.04))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
        }
        .frame(width: 550, height: 600)
        .sheet(item: $selectedRevision) { revision in
            GistDiffView(gistId: gistId, revision: revision)
                .environmentObject(gistService)
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
