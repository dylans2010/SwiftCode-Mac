import SwiftUI

struct GistDiffView: View {
    let gistId: String
    let revision: GistRevision
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var diffFiles: [GistFile] = []
    @State private var isLoading = false
    @State private var diffStyle: DiffStyle = .unified

    enum DiffStyle: String, CaseIterable, Identifiable {
        case unified = "Unified"
        case split = "Split"
        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(diffFiles) { file in
                Text(file.filename)
            }
            .navigationTitle("Changed Files")
        } detail: {
            ZStack {
                if isLoading {
                    ProgressView()
                } else if diffFiles.isEmpty {
                    ContentUnavailableView("No Diffs", systemImage: "doc.text")
                } else {
                    ScrollView {
                        // Display diff content
                        Text("Diff content goes here")
                    }
                }
            }
            .navigationTitle("Diff (\(revision.version.prefix(7)))")
            .toolbar {
                ToolbarItem {
                    Picker("Style", selection: $diffStyle) {
                        ForEach(DiffStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .task {
            await loadDiff()
        }
    }

    private func loadDiff() async {
        isLoading = true
        do {
            let fetched = try await gistService.fetchGistAtRevision(gistId: gistId, sha: revision.version)
            diffFiles = fetched.files.values.sorted { $0.filename < $1.filename }
        } catch {
            print("Failed to load diff: \(error)")
        }
        isLoading = false
    }
}
