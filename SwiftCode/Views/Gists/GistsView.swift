import SwiftUI

struct GistsView: View {
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var showCreateSheet = false
    @State private var selectedGistId: GistIDWrapper?
    @State private var showDeleteConfirmation = false
    @State private var gistToDelete: GistResponse?
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
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea()

                if gistService.isLoading && gistService.gists.isEmpty {
                    ProgressView("Loading Gists...")
                } else if filteredGists.isEmpty {
                    emptyState
                } else {
                    gistList
                }
            }
            .navigationTitle("GitHub Gists")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search Gists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { try await gistService.fetchGists() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                _ = try? await gistService.fetchGists()
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateGistView()
                    .environmentObject(gistService)
            }
            .sheet(item: $selectedGistId) { wrapper in
                GistDetailView(gistId: wrapper.id)
                    .environmentObject(gistService)
            }
            .alert("Delete Gist", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let gist = gistToDelete {
                        Task { try await gistService.deleteGist(id: gist.id) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this Gist? This action cannot be undone.")
            }
            .overlay {
                if let error = gistService.errorMessage {
                    errorBanner(message: error)
                }
            }
        }
        .task {
            if gistService.gists.isEmpty {
                _ = try? await gistService.fetchGists()
            }
            refreshStarredStatus()
        }
    }

    private func refreshStarredStatus() {
        Task {
            let gistIDs = gistService.gists.map { $0.id }
            await withTaskGroup(of: (String, Bool).self) { group in
                for id in gistIDs {
                    group.addTask {
                        let isStarred = (try? await gistService.checkIsStarred(id: id)) ?? false
                        return (id, isStarred)
                    }
                }

                for await (id, isStarred) in group {
                    if isStarred {
                        starredGistIDs.insert(id)
                    }
                }
            }
        }
    }

    private var gistList: some View {
        List {
            ForEach(filteredGists) { gist in
                GistRowView(gist: gist, isStarred: starredGistIDs.contains(gist.id))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedGistId = GistIDWrapper(id: gist.id)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            gistToDelete = gist
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            toggleStar(gist)
                        } label: {
                            Label(
                                starredGistIDs.contains(gist.id) ? "Unstar" : "Star",
                                systemImage: starredGistIDs.contains(gist.id) ? "star.slash.fill" : "star.fill"
                            )
                        }
                        .tint(.yellow)
                    }
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(searchQuery.isEmpty ? "No Gists found" : "No Gists matching \"\(searchQuery)\"")
                .font(.headline)
                .foregroundStyle(.secondary)

            if searchQuery.isEmpty {
                Button("Create your first Gist") {
                    showCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
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

    struct GistIDWrapper: Identifiable {
        let id: String
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline)
                .padding()
                .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
