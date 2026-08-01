import SwiftUI

struct GistsView: View {
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var showCreateSheet = false
    @State private var selectedGist: GistResponse?
    @State private var starredGistIDs: Set<String> = []

    var filteredGists: [GistResponse] {
        if searchQuery.isEmpty {
            return gistService.gists
        }
        return gistService.gists.filter {
            ($0.description ?? "").localizedCaseInsensitiveContains(searchQuery) ||
            $0.files.keys.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Gists Workspace", systemImage: "doc.on.doc.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            Text("Manage, view, and edit your GitHub Gists, all synchronized from your GitHub account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Search & Actions Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Search & Actions")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)

                            HStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search gists...", text: $searchQuery)
                                        .textFieldStyle(.plain)
                                }
                                .padding(6)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                                Button {
                                    showCreateSheet = true
                                } label: {
                                    Label("New Gist", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)

                                Button {
                                    Task { try? await gistService.fetchGists() }
                                } label: {
                                    Label("Reload", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Gists List Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Your Gists", systemImage: "doc.text")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            if gistService.isLoading && gistService.gists.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView("Loading Gists...")
                                        .padding()
                                    Spacer()
                                }
                            } else if filteredGists.isEmpty {
                                HStack {
                                    Spacer()
                                    ContentUnavailableView(
                                        "No Gists Found",
                                        systemImage: "doc.on.doc",
                                        description: Text("Create your first gist to get started.")
                                    )
                                    .padding()
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(filteredGists) { gist in
                                        Button {
                                            selectedGist = gist
                                        } label: {
                                            HStack {
                                                GistRowView(gist: gist, isStarred: starredGistIDs.contains(gist.id))
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(10)
                                            .background(Color.secondary.opacity(0.04))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("Delete", role: .destructive) {
                                                Task { try? await gistService.deleteGist(id: gist.id) }
                                            }
                                            Button(starredGistIDs.contains(gist.id) ? "Unstar" : "Star") {
                                                toggleStar(gist)
                                            }
                                        }
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
            .navigationTitle("Gists")
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateGistView()
                .environmentObject(gistService)
        }
        .sheet(item: $selectedGist) { gist in
            GistDetailView(gistId: gist.id)
                .environmentObject(gistService)
        }
        .task {
            if gistService.gists.isEmpty {
                _ = try? await gistService.fetchGists()
            }
        }
    }

    private func toggleStar(_ gist: GistResponse) {
        Task {
            do {
                if starredGistIDs.contains(gist.id) {
                    try await gistService.unstarGist(id: gist.id)
                    starredGistIDs.remove(gist.id)
                } else {
                    try await gistService.starGist(id: gist.id)
                    starredGistIDs.insert(gist.id)
                }
            } catch {
                print("Failed to toggle star: \(error)")
            }
        }
    }
}
