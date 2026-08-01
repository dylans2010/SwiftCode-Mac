import SwiftUI

enum GistsScreen: Hashable {
    case list
    case create
    case detail(id: String)
}

struct GistsView: View {
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var starredGistIDs: Set<String> = []
    @State private var currentScreen: GistsScreen = .list

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
        Group {
            switch currentScreen {
            case .list:
                listView
            case .create:
                CreateGistView {
                    currentScreen = .list
                }
            case .detail(let id):
                GistDetailView(gistId: id) {
                    currentScreen = .list
                }
            }
        }
    }

    @ViewBuilder
    private var listView: some View {
        VStack(spacing: 0) {
            // Header actions row (inspired by IssuesView / ReleasesView)
            HStack(spacing: 12) {
                Label("GitHub Gists", systemImage: "doc.on.doc.fill")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search gists...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
                .frame(width: 220)

                Button {
                    Task { try? await gistService.fetchGists() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(gistService.isLoading)

                Button {
                    currentScreen = .create
                } label: {
                    Label("New Gist", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if gistService.isLoading && gistService.gists.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading Gists...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGists.isEmpty {
                VStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Gists Found",
                        systemImage: "doc.on.doc",
                        description: Text("Create your first gist to get started.")
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Your Gist Directory") {
                        ForEach(filteredGists) { gist in
                            Button {
                                currentScreen = .detail(id: gist.id)
                            } label: {
                                HStack {
                                    GistRowView(gist: gist, isStarred: starredGistIDs.contains(gist.id))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
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
                            Divider()
                        }
                    }
                }
                .listStyle(.plain)
            }
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
