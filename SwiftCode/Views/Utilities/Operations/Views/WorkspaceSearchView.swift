import SwiftUI

struct WorkspaceSearchView: View {
    @State private var ws = WorkspaceSearch.shared
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Global Operations Search")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Search across registered projects, archived binaries, log files, builds, and diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            // Large search input row
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("Type keywords to search projects, builds, archives, logs, or reports...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { oldValue, newValue in
                        ws.search(query: newValue)
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        ws.searchResults.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            .padding(16)

            Divider()

            if query.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Enter a search term above to scan the workspace.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ws.searchResults.isEmpty {
                ContentUnavailableView {
                    Label("No Results for '\(query)'", systemImage: "magnifyingglass")
                } description: {
                    Text("Try typing another keyword, like a project name, a build status, or package identifier.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(ws.searchResults) { item in
                    HStack(spacing: 14) {
                        Image(systemName: iconForCategory(item.category))
                            .font(.title3)
                            .foregroundStyle(colorForCategory(item.category))
                            .frame(width: 32, height: 32)
                            .background(colorForCategory(item.category).opacity(0.12))
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.detail)
                                .font(.headline)
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(item.category)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colorForCategory(item.category).opacity(0.15))
                            .foregroundStyle(colorForCategory(item.category))
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            if !query.isEmpty {
                ws.search(query: query)
            }
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Project": return "folder.fill"
        case "Archive": return "archivebox.fill"
        case "Build": return "clock.fill"
        default: return "doc.text"
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Project": return .orange
        case "Archive": return .blue
        case "Build": return .green
        default: return .secondary
        }
    }
}
