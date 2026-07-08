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
        NavigationSplitView {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                if gistService.isLoading && gistService.gists.isEmpty {
                    ProgressView()
                } else if filteredGists.isEmpty {
                    ContentUnavailableView("No Gists Found", systemImage: "doc.on.doc", description: Text("Create your first gist to get started."))
                } else {
                    List(filteredGists, selection: $selectedGist) { gist in
                        GistRowView(gist: gist, isStarred: starredGistIDs.contains(gist.id))
                            .tag(gist)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { try await gistService.deleteGist(id: gist.id) }
                                }
                                Button(starredGistIDs.contains(gist.id) ? "Unstar" : "Star") {
                                    toggleStar(gist)
                                }
                            }
                    }
                }
            }
            .navigationTitle("Gists")
            .searchable(text: $searchQuery)
            .toolbar {
                ToolbarItem {
                    Button { showCreateSheet = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem {
                    Button { Task { try await gistService.fetchGists() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        } detail: {
            if let gist = selectedGist {
                GistDetailView(gistId: gist.id)
            } else {
                ContentUnavailableView("Select a Gist", systemImage: "doc.text")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateGistView()
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
