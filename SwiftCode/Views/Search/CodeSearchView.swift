import SwiftUI

@MainActor
struct CodeSearchView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var indexService = CodeIndexService.shared

    @State private var searchQuery = ""
    @State private var replaceQuery = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var isReplacing = false
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var selectedFileExtension: String? = nil
    @State private var searchBackendHint = ""
    @State private var notificationMessage: String?
    @State private var showNotification = false
    @FocusState private var searchFocused: Bool

    private let fileExtensions = [
        "All", "swift", "json", "plist", "yml", "yaml", "md", "txt", "xml",
        "html", "css", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Elegant Native Floating Header for Search Inputs
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    TextField("Search your workspace codebase...", text: $searchQuery)
                        .font(.system(.title3, design: .rounded))
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .onSubmit { performSearch() }
                        .onChange(of: searchQuery) { _, newValue in
                            if newValue.isEmpty {
                                results = []
                            } else {
                                performSearch()
                            }
                        }
                        .textFieldStyle(.plain)

                    if isSearching {
                        ProgressView().controlSize(.small)
                    }

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                // Inline Replace Interface
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.arrow.left.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    TextField("Replace with...", text: $replaceQuery)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)

                    Spacer()

                    if !replaceQuery.isEmpty && !results.isEmpty {
                        Button {
                            performReplaceAll()
                        } label: {
                            Label("Replace All", systemImage: "arrow.right.arrow.left")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(isReplacing)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider()

            // Filter Pills Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Toggle(isOn: $caseSensitive) {
                        Label("Match Case", systemImage: "case")
                    }
                    .toggleStyle(CustomToggleStyle())
                    .onChange(of: caseSensitive) { _, _ in
                        if !searchQuery.isEmpty { performSearch() }
                    }

                    Toggle(isOn: $useRegex) {
                        Label("Regex", systemImage: "text.and.command")
                    }
                    .toggleStyle(CustomToggleStyle())
                    .onChange(of: useRegex) { _, _ in
                        if !searchQuery.isEmpty { performSearch() }
                    }

                    Divider().frame(height: 20)

                    ForEach(fileExtensions, id: \.self) { ext in
                        let isSelected = (ext == "All" && selectedFileExtension == nil) ||
                                         (ext != "All" && selectedFileExtension == ext)

                        Button {
                            selectedFileExtension = (ext == "All") ? nil : ext
                            if !searchQuery.isEmpty { performSearch() }
                        } label: {
                            Text(ext == "All" ? "All Files" : ".\(ext)")
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(isSelected ? .borderedProminent : .bordered)
                        .tint(isSelected ? .orange : .secondary)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Header Statistics
            if !results.isEmpty {
                HStack {
                    Text("\(results.count) Match\(results.count == 1 ? "" : "es") Found")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if !searchBackendHint.isEmpty {
                        Text("•  via \(searchBackendHint)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()
            }

            // Interactive Matches List
            Group {
                if results.isEmpty && !searchQuery.isEmpty && !isSearching {
                    ContentUnavailableView {
                        Label("No Matches Found", systemImage: "magnifyingglass")
                    } description: {
                        Text("No occurrences of '\(searchQuery)' found in the active project directory.")
                    }
                } else if results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.7))
                        Text("Global Code Search")
                            .font(.headline)
                        Text("Search and replace code, keys, and values instantly across your entire project.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { result in
                        Button {
                            openResult(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: fileIcon(result.fileName))
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(result.fileName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                    Text(":\(result.lineNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(result.filePath)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                highlightedSnippet(result.snippet, query: searchQuery)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .frame(minWidth: 550, minHeight: 480)
        .alert("Search & Replace", isPresented: $showNotification, presenting: notificationMessage) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
        .onAppear { searchFocused = true }
    }

    private func highlightedSnippet(_ snippet: String, query: String) -> Text {
        if query.isEmpty {
            return Text(snippet)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        } else {
            let lowerSnippet = snippet.lowercased()
            let lowerQuery = query.lowercased()

            if let range = lowerSnippet.range(of: lowerQuery) {
                let startIdx = snippet.distance(from: snippet.startIndex, to: range.lowerBound)
                let endIdx = snippet.distance(from: snippet.startIndex, to: range.upperBound)

                let prefix = String(snippet.prefix(startIdx))
                let match = String(snippet.prefix(endIdx).dropFirst(startIdx))
                let suffix = String(snippet.dropFirst(endIdx))

                var prefixAttr = AttributedString(prefix)
                prefixAttr.font = .system(.caption, design: .monospaced)
                prefixAttr.foregroundColor = .secondary

                var matchAttr = AttributedString(match)
                matchAttr.font = .system(.caption, design: .monospaced).bold()
                matchAttr.foregroundColor = .orange
                matchAttr.backgroundColor = Color.orange.opacity(0.15)

                var suffixAttr = AttributedString(suffix)
                suffixAttr.font = .system(.caption, design: .monospaced)
                suffixAttr.foregroundColor = .secondary

                var combined = prefixAttr
                combined.append(matchAttr)
                combined.append(suffixAttr)

                return Text(combined)
            } else {
                return Text(snippet)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty,
              let project = sessionStore.activeProject else { return }
        isSearching = true
        let dirURL = project.directoryURL
        let query = searchQuery
        let caseFlag = caseSensitive
        let regexFlag = useRegex
        let extFilter = selectedFileExtension
        Task {
            let searchResults = await searchUsingBestAvailableBackend(
                query: query,
                at: dirURL,
                caseSensitive: caseFlag,
                useRegex: regexFlag,
                fileExtension: extFilter
            )
            self.results = searchResults
            self.isSearching = false
        }
    }

    private func searchUsingBestAvailableBackend(
        query: String,
        at directoryURL: URL,
        caseSensitive: Bool,
        useRegex: Bool,
        fileExtension: String?
    ) async -> [SearchResult] {
        do {
            let ripgrepOutput = try await BinaryManager.shared.runRipgrepSearch(
                query: query,
                in: directoryURL.path,
                caseSensitive: caseSensitive,
                useRegex: useRegex,
                fileExtension: fileExtension
            )
            self.searchBackendHint = "ripgrep"
            return parseRipgrep(output: ripgrepOutput.stdout, projectRoot: directoryURL)
        } catch {
            self.searchBackendHint = "index fallback"
            return await indexService.searchProject(
                query: query,
                at: directoryURL,
                caseSensitive: caseSensitive,
                useRegex: useRegex,
                fileExtension: fileExtension
            )
        }
    }

    private func parseRipgrep(output: String, projectRoot: URL) -> [SearchResult] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count == 4, let lineNumber = Int(parts[1]) else { return nil }

                let fullPath = String(parts[0])
                let relativePath = fullPath.replacingOccurrences(of: projectRoot.path + "/", with: "")

                return SearchResult(
                    fileName: URL(fileURLWithPath: fullPath).lastPathComponent,
                    filePath: relativePath,
                    lineNumber: lineNumber,
                    snippet: String(parts[3]),
                    matchRange: nil
                )
            }
    }

    private func performReplaceAll() {
        guard !searchQuery.isEmpty, let project = sessionStore.activeProject else { return }
        isReplacing = true

        let targetQuery = searchQuery
        let replacement = replaceQuery
        let caseFlag = caseSensitive
        let regexFlag = useRegex
        let dirURL = project.directoryURL

        Task {
            var replacedCount = 0
            var filesModified: Set<String> = []

            for result in results {
                let fileURL = dirURL.appendingPathComponent(result.filePath)
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                let updatedContent: String
                if regexFlag {
                    let options: NSRegularExpression.Options = caseFlag ? [] : [.caseInsensitive]
                    if let regex = try? NSRegularExpression(pattern: targetQuery, options: options) {
                        let range = NSRange(content.startIndex..<content.endIndex, in: content)
                        updatedContent = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: replacement)
                    } else {
                        updatedContent = content
                    }
                } else {
                    if caseFlag {
                        updatedContent = content.replacingOccurrences(of: targetQuery, with: replacement)
                    } else {
                        updatedContent = content.replacingOccurrences(of: targetQuery, with: replacement, options: .caseInsensitive)
                    }
                }

                if updatedContent != content {
                    do {
                        try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
                        filesModified.insert(result.filePath)
                        replacedCount += 1
                    } catch {
                        print("Failed to write to file: \(fileURL.path)")
                    }
                }
            }

            self.isReplacing = false
            self.replaceQuery = ""
            self.results = []
            self.notificationMessage = "Successfully completed replace: modified \(filesModified.count) files across \(replacedCount) occurrences."
            self.showNotification = true
            self.sessionStore.refreshFileTree(for: project)
        }
    }

    private func openResult(_ result: SearchResult) {
        let node = FileNode(name: result.fileName, path: result.filePath, isDirectory: false)
        sessionStore.openFile(node)
        dismiss()
    }

    private func fileIcon(_ fileName: String) -> String {
        switch fileName.components(separatedBy: ".").last?.lowercased() ?? "" {
        case "swift": return "swift"
        case "json": return "curlybraces"
        case "md": return "doc.text"
        case "yml", "yaml": return "list.dash"
        case "html", "css", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }
}

// Inline toggle system to support elegant buttons
struct ToggleSource: Identifiable {
    let id = UUID()
    let title: String
    let isSystem: Bool
}

struct CustomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Color.orange : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }
}
