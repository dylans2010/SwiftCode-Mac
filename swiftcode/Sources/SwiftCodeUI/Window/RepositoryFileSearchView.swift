import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/RepositoryExplorerView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// The repository explorer's source browser: file search across the
/// project tree plus an in-explorer file content view.
///
/// Legacy listed files from `ProjectSessionStore` and loaded content on
/// tap. This port enumerates the project directory directly (skipping
/// `.git` and other generated directories), filters by file name, and
/// loads the selected file's text. The "Blame Viewer" button routes to
/// `onShowBlame`, which the host wires to the editor's Authors (blame)
/// column for that file.
///
/// Hook: host as the explorer's Source Browser section with the project
/// root; `onShowBlame` should open the file in the editor with the blame
/// column shown.
@MainActor
public struct RepositoryFileSearchView: View {
    public var projectRoot: URL
    /// Open the blame view for this file.
    public var onShowBlame: (URL) -> Void

    @State private var fileSearchText = ""
    @State private var selectedFile: URL?
    @State private var fileContent = ""
    @State private var fileList: [URL] = []
    @State private var isLoading = false

    private static let skippedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods", ".cxx"
    ]

    public init(projectRoot: URL, onShowBlame: @escaping (URL) -> Void = { _ in }) {
        self.projectRoot = projectRoot
        self.onShowBlame = onShowBlame
    }

    private var filteredFiles: [URL] {
        fileList.filter {
            fileSearchText.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(fileSearchText)
        }
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter files...", text: $fileSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .padding(8)

                Divider()

                if isLoading {
                    ProgressView().controlSize(.small).padding()
                    Spacer()
                } else if filteredFiles.isEmpty {
                    Text("No files match")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List(filteredFiles, id: \.self, selection: $selectedFile) { url in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { loadFile(url) }
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

            VStack(spacing: 0) {
                if let url = selectedFile {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Spacer()
                        Button("Blame Viewer") { onShowBlame(url) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    ScrollView {
                        Text(fileContent)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                } else {
                    ContentUnavailableView(
                        "No File Selected",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Select any source file in the hierarchy to view contents directly.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await loadFileList() }
    }

    private func loadFileList() async {
        isLoading = true
        defer { isLoading = false }
        let root = projectRoot
        fileList = await Task.detached {
            var found: [URL] = []
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            while let url = enumerator?.nextObject() as? URL {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    if Self.skippedDirectories.contains(url.lastPathComponent) {
                        enumerator?.skipDescendants()
                    }
                    continue
                }
                found.append(url)
            }
            return found.sorted { $0.path < $1.path }
        }.value
    }

    private func loadFile(_ url: URL) {
        selectedFile = url
        fileContent = (try? String(contentsOf: url, encoding: .utf8))
            ?? "Could not read this file as text."
    }
}
