import SwiftUI

struct SearchSidebarView: View {
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @Environment(WorkspaceViewModel.self) var workspaceVM

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search in project", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = ""; searchResults = [] }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding()

            if isSearching {
                ProgressView()
                    .padding()
            }

            List(searchResults) { result in
                Button(action: {
                    Task {
                        await workspaceVM.editor.openFile(url: URL(fileURLWithPath: result.filePath))
                    }
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(result.fileName)
                                .font(.headline)
                            Spacer()
                            Text("Line \(result.lineNumber)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(result.filePath)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)

                        Text(result.lineContent)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                            .padding(4)
                            .background(Color.accentColor.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                ContentUnavailableView("No results found", systemImage: "magnifyingglass", description: Text("Try a different search term"))
            }

            Spacer()
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        Task {
            let tool = GrepTool()
            let projectRoot = workspaceVM.projectURL.path
            do {
                let rawOutput = try await tool.run(pattern: searchText, directory: projectRoot)
                let lines = rawOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
                searchResults = lines.compactMap { line -> SearchResult? in
                    let parts = line.components(separatedBy: ":")
                    guard parts.count >= 3 else { return nil }
                    let filePath = parts[0]
                    let lineNumber = Int(parts[1]) ?? 0
                    let content = parts.dropFirst(2).joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    return SearchResult(filePath: filePath, lineNumber: lineNumber, snippet: content)
                }
            } catch {
                print("Search failed: \(error)")
                searchResults = []
            }
            isSearching = false
        }
    }
}
