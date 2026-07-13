import SwiftUI

struct GlobalSearchView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var query = ""
    @State private var results: [SearchManager.SearchResult] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search all personal documentation...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { _, _ in
                        performSearch()
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if results.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "Start typing to search" : "No results found", systemImage: "magnifyingglass")
                } description: {
                    Text(query.isEmpty ? "Search spanning all document types, smart collections, and attachment metadata." : "Check spelling or try using different keywords.")
                }
            } else {
                List(results) { result in
                    Button {
                        coordinator.selectedModuleKind = result.document.moduleKind
                        coordinator.selectedDocumentID = result.document.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: result.document.moduleKind.icon)
                                    .foregroundStyle(result.document.moduleKind.accentColor)
                                Text(result.document.title)
                                    .font(.body.bold())
                                Spacer()
                                Text(result.document.moduleKind.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func performSearch() {
        results = (try? coordinator.search.search(query: query)) ?? []
    }
}
