import SwiftUI

@MainActor
struct GitHubCodeSearchView: View {
    let project: Project?
    @State private var query = ""
    @State private var results: [String] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            // Header search input row
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search codebase content...", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performSearch()
                        }
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    performSearch()
                } label: {
                    Text("Search")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isSearching || query.isEmpty)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isSearching {
                GitHubLoadingView(message: "Searching codebase...")
            } else if results.isEmpty {
                GitHubEmptyStateView(
                    title: "Code Search",
                    description: "Search local codebase files for pattern matching or variable declarations.",
                    systemImage: "doc.text.magnifyingglass",
                    accentColor: .orange
                )
            } else {
                List(results, id: \.self) { result in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.orange)
                        Text(result)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func performSearch() {
        guard let project = project else { return }
        isSearching = true
        results.removeAll()

        Task {
            do {
                let fileManager = FileManager.default
                let dirURL = await project.directoryURL

                guard let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: nil) else {
                    isSearching = false
                    return
                }

                var matched: [String] = []
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" || fileURL.pathExtension == "txt" || fileURL.pathExtension == "md" {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        if content.contains(query) {
                            let relPath = fileURL.path.replacingOccurrences(of: dirURL.path + "/", with: "")
                            matched.append(relPath)
                        }
                    }
                }
                self.results = matched
            } catch {
                // Silent catch
            }
            isSearching = false
        }
    }
}
