import SwiftUI

struct SearchSidebarView: View {
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false

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
                    Text(result.lineContent)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
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
            // In a production app, the project root should be dynamically determined
            let projectRoot = FileManager.default.currentDirectoryPath
            do {
                let rawOutput = try await tool.run(pattern: searchText, directory: projectRoot)
                let lines = rawOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
                searchResults = lines.compactMap { line -> SearchResult? in
                    let parts = line.components(separatedBy: ":")
                    guard parts.count >= 3 else { return nil }
                    let filePath = parts[0]
                    let lineNumber = Int(parts[1]) ?? 0
                    let content = parts.dropFirst(2).joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    return SearchResult(filePath: filePath, lineNumber: lineNumber, lineContent: content)
                }
            } catch {
                print("Search failed: \(error)")
            }
            isSearching = false
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let lineNumber: Int
    let lineContent: String

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}
