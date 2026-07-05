import SwiftUI
import ZIPFoundation

struct SearchDocumentationView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var viewModel = RepositoryAnalysisViewModel()
    @State private var repositoryURL = ""
    @State private var prompt = ""

    @AppStorage("search_docs_history") private var searchHistoryData: Data = Data()

    private var searchHistory: [String] {
        (try? JSONDecoder().decode([String].self, from: searchHistoryData)) ?? []
    }

    var body: some View {
        AdvancedToolScreen(title: "Repository Search") {
            VStack(spacing: 20) {
                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Source Repository", systemImage: "server.rack")
                        .font(.headline)

                    TextField("GitHub Repository URL", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack(spacing: 10) {
                        Button {
                            viewModel.runScan(source: .github(repositoryURL))
                        } label: {
                            Text("Analyze URL")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            viewModel.runScan(source: .folder(projectManager.activeProject?.directoryURL))
                        } label: {
                            Text("Current Project")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if viewModel.isScanning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: viewModel.progress)
                                .tint(.orange)
                            Text(viewModel.statusMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }

                    if let reportError = viewModel.reportError {
                        Text(reportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                // Analysis Sections
                if !viewModel.report.projectSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Analysis Report", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)

                        DisclosureGroup("Project Summary") {
                            Text(viewModel.report.projectSummary)
                                .font(.caption)
                                .padding(.top, 4)
                        }

                        DisclosureGroup("Architecture") {
                            Text(viewModel.report.architectureOverview)
                                .font(.caption)
                                .padding(.top, 4)
                        }

                        DisclosureGroup("Key Files") {
                            Text(viewModel.report.importantFiles)
                                .font(.caption)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }

                // AI Chat Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ask AI about Repo", systemImage: "sparkles")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if viewModel.chatHistory.isEmpty {
                                Text("Ask a question about the indexed code to see AI answers.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(viewModel.chatHistory) { message in
                                    chatBubble(for: message)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    HStack {
                        TextField("How do I use...", text: $prompt)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            addToHistory(prompt)
                            viewModel.askQuestion(prompt)
                            prompt = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.isEmpty || viewModel.isScanning)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                // History Section
                if !searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                            Spacer()
                            Button("Clear") { clearHistory() }
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(searchHistory, id: \.self) { item in
                                    Button {
                                        prompt = item
                                    } label: {
                                        Text(item)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func chatBubble(for message: SearchDocChatMessage) -> some View {
        HStack {
            if message.role == "You" { Spacer() }

            VStack(alignment: message.role == "You" ? .trailing : .leading, spacing: 4) {
                Text(message.role)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.caption)
                    .padding(10)
                    .background(message.role == "You" ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if message.role != "You" { Spacer() }
        }
    }

    private func addToHistory(_ query: String) {
        var current = searchHistory
        if let index = current.firstIndex(of: query) { current.remove(at: index) }
        current.insert(query, at: 0)
        let limited = Array(current.prefix(10))
        if let data = try? JSONEncoder().encode(limited) {
            searchHistoryData = data
        }
    }

    private func clearHistory() {
        searchHistoryData = Data()
    }
}

@MainActor
private final class RepositoryAnalysisViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var statusMessage = "Idle"
    @Published var reportError: String?
    @Published var report = RepositoryKnowledgeReport.empty
    @Published var chatHistory: [SearchDocChatMessage] = []

    private var scanTask: Task<Void, Never>?

    func runScan(source: RepositorySource) {
        scanTask?.cancel()
        isScanning = true
        progress = 0
        statusMessage = "Preparing Analysis..."
        reportError = nil

        scanTask = Task {
            do {
                let result = try await RepositoryKnowledgeReport.from(source: source) { [weak self] update in
                    await MainActor.run {
                        self?.progress = update.progress
                        self?.statusMessage = update.message
                    }
                }
                await MainActor.run {
                    self.report = result
                    self.chatHistory = []
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.report = .empty
                    self.reportError = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }

    func askQuestion(_ rawPrompt: String) {
        let query = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        chatHistory.append(.init(role: "You", text: query))
        chatHistory.append(.init(role: "AI", text: report.answer(for: query)))
    }
}

private enum RepositorySource {
    case github(String)
    case zip(URL?)
    case folder(URL?)
}

private struct SearchDocChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

private struct RepositoryProgressUpdate {
    let progress: Double
    let message: String
}

private enum RepositoryScanError: LocalizedError {
    case invalidLocalFolder
    case missingZipPath
    case invalidGitHubURL
    case unsupportedGitHubURL
    case githubListingFailed
    case corruptedArchive
    case emptyRepository

    var errorDescription: String? {
        switch self {
        case .invalidLocalFolder: return "No local folder available."
        case .missingZipPath: return "ZIP file path is missing."
        case .invalidGitHubURL: return "Invalid GitHub URL."
        case .unsupportedGitHubURL: return "Only github.com repository URLs are supported."
        case .githubListingFailed: return "Failed to list repository contents from GitHub."
        case .corruptedArchive: return "The ZIP archive appears invalid or corrupted."
        case .emptyRepository: return "No supported documentation/source files were found."
        }
    }
}

private struct RepositoryKnowledgeReport {
    var projectSummary: String
    var architectureOverview: String
    var importantFiles: String
    var dependencies: String
    var integrationGuide: String
    var searchableSnippets: [String]

    static let empty = Self(projectSummary: "", architectureOverview: "", importantFiles: "", dependencies: "", integrationGuide: "", searchableSnippets: [])

    static func from(source: RepositorySource, progress: @escaping (RepositoryProgressUpdate) async -> Void) async throws -> Self {
        switch source {
        case .folder(let url):
            guard let root = url else { throw RepositoryScanError.invalidLocalFolder }
            await progress(.init(progress: 0.05, message: "Scanning local repository..."))
            return try await analyzeLocalRepository(rootURL: root, progress: progress)
        case .zip(let url):
            guard let zipURL = url else { throw RepositoryScanError.missingZipPath }
            await progress(.init(progress: 0.1, message: "Extracting archive..."))
            let rootURL = try extractZip(at: zipURL)
            return try await analyzeLocalRepository(rootURL: rootURL, progress: progress)
        case .github(let value):
            return try await analyzeGitHubRepository(input: value, progress: progress)
        }
    }

    private static func analyzeGitHubRepository(input: String, progress: @escaping (RepositoryProgressUpdate) async -> Void) async throws -> Self {
        await progress(.init(progress: 0.05, message: "Validating GitHub URL..."))
        guard let parsed = GitHubRepoReference(urlString: input) else { throw RepositoryScanError.invalidGitHubURL }
        guard parsed.host == "github.com" else { throw RepositoryScanError.unsupportedGitHubURL }

        await progress(.init(progress: 0.15, message: "Listing repository tree from GitHub API..."))
        let (manifestFiles, dependencyFiles, readmeFile) = try await fetchGitHubFileManifests(for: parsed)

        await progress(.init(progress: 0.35, message: "Fetching targeted files..."))
        let lightweight = try await buildLightweightReportFromGitHub(parsed: parsed, manifests: manifestFiles, dependencyPaths: dependencyFiles, readmePath: readmeFile, progress: progress)
        return lightweight
    }

    private static func extractZip(at url: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("repo-unzip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        do {
            try FileManager.default.unzipItem(at: url, to: dest)
        } catch {
            throw RepositoryScanError.corruptedArchive
        }

        if let first = try? FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil).first {
            return first
        }
        return dest
    }

    private static func analyzeLocalRepository(rootURL: URL, progress: @escaping (RepositoryProgressUpdate) async -> Void) async throws -> Self {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fm = FileManager.default
                    let allowed = Set(["swift", "md", "txt", "json", "yaml", "yml", "plist"])
                    let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

                    var files: [URL] = []
                    var scanned = 0
                    while let item = enumerator?.nextObject() as? URL {
                        scanned += 1
                        if scanned % 250 == 0 {
                            Task { await progress(.init(progress: min(0.2 + Double(scanned) / 50000.0, 0.7), message: "Indexed \(scanned) paths...")) }
                        }
                        if allowed.contains(item.pathExtension.lowercased()) { files.append(item) }
                    }

                    guard !files.isEmpty else { throw RepositoryScanError.emptyRepository }
                    Task { await progress(.init(progress: 0.78, message: "Analyzing code structure...")) }
                    continuation.resume(returning: try buildReport(rootURL: rootURL, files: files))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func buildReport(rootURL: URL, files: [URL]) throws -> Self {
        let snippetLines = files.prefix(80).compactMap { url -> String? in
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let data = try? handle.read(upToCount: 1600),
                  let content = String(data: data, encoding: .utf8)
            else { return nil }
            let first = content.split(separator: "\n").prefix(2).joined(separator: " ")
            return "\(url.lastPathComponent): \(first)"
        }

        let readme = files.first(where: { $0.lastPathComponent.lowercased().contains("readme") })
        let readmeText = readme.flatMap { try? String(contentsOf: $0) } ?? ""

        let dependenciesText = files.filter { ["package.swift", "podfile", "cartfile"].contains($0.lastPathComponent.lowercased()) }
            .compactMap { try? String(contentsOf: $0) }
            .joined(separator: "\n")

        let swiftFiles = files.filter { $0.pathExtension.lowercased() == "swift" }
        let importSet = Set(swiftFiles.compactMap { try? String(contentsOf: $0) }
            .flatMap { text in
                text.split(separator: "\n").compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("import ") else { return nil }
                    return String(trimmed.dropFirst("import ".count))
                }
            })

        let important = files.sorted { $0.path.count < $1.path.count }
            .prefix(10)
            .map { "- " + $0.path.replacingOccurrences(of: rootURL.path + "/", with: "") }
            .joined(separator: "\n")

        return .init(
            projectSummary: "Repository root: \(rootURL.lastPathComponent)\nFiles scanned: \(files.count)\n\(readmeText.prefix(600))",
            architectureOverview: "Swift files: \(swiftFiles.count). Imported modules: \(importSet.sorted().joined(separator: ", ")).",
            importantFiles: important,
            dependencies: dependenciesText.isEmpty ? "No dependency manifests found." : String(dependenciesText.prefix(1000)),
            integrationGuide: "1. Start from README and manifest files.\n2. Inspect the key files listed above.\n3. Follow imported modules to locate boundaries and extension points.\n4. Validate integration with project tests/build.",
            searchableSnippets: snippetLines
        )
    }

    private static func fetchGitHubFileManifests(for ref: GitHubRepoReference) async throws -> ([String], [String], String?) {
        let treeURL = URL(string: "https://api.github.com/repos/\(ref.owner)/\(ref.repo)/git/trees/\(ref.branch)?recursive=1")!
        let (data, response) = try await URLSession.shared.data(from: treeURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RepositoryScanError.githubListingFailed }

        let decoded = try JSONDecoder().decode(SearchGitHubTreeResponse.self, from: data)
        let allowed = Set(["swift", "md", "txt", "json", "yaml", "yml", "plist"])
        let manifests = decoded.tree
            .filter { $0.type == "blob" }
            .map(\.path)
            .filter { path in
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                return allowed.contains(ext)
            }
            .prefix(250)
            .map { String($0) }

        let dependency = decoded.tree
            .filter { ["package.swift", "podfile", "cartfile"].contains($0.path.lowercased()) }
            .map(\.path)
        let readme = decoded.tree.first(where: { $0.path.lowercased().contains("readme") })?.path

        return (Array(manifests), dependency, readme)
    }

    private static func buildLightweightReportFromGitHub(parsed: GitHubRepoReference, manifests: [String], dependencyPaths: [String], readmePath: String?, progress: @escaping (RepositoryProgressUpdate) async -> Void) async throws -> Self {
        let swiftFiles = manifests.filter { $0.lowercased().hasSuffix(".swift") }
        var snippetLines: [String] = []
        var imports = Set<String>()
        var readmeText = ""
        var dependencyText = ""

        let sampleFiles = manifests.prefix(60)
        for (index, path) in sampleFiles.enumerated() {
            if index % 8 == 0 {
                await progress(.init(progress: 0.35 + (Double(index) / Double(max(sampleFiles.count, 1))) * 0.45, message: "Downloading indexed files (\(index + 1)/\(sampleFiles.count))..."))
            }

            if let content = try await fetchGitHubFileContent(parsed: parsed, path: path) {
                let head = content.split(separator: "\n").prefix(2).joined(separator: " ")
                snippetLines.append("\(URL(fileURLWithPath: path).lastPathComponent): \(head)")

                if path.lowercased().hasSuffix(".swift") {
                    content.split(separator: "\n").forEach { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("import ") {
                            imports.insert(String(trimmed.dropFirst(7)))
                        }
                    }
                }
            }
        }

        if let readmePath, let readme = try await fetchGitHubFileContent(parsed: parsed, path: readmePath) {
            readmeText = String(readme.prefix(600))
        }

        if !dependencyPaths.isEmpty {
            for path in dependencyPaths.prefix(4) {
                if let body = try await fetchGitHubFileContent(parsed: parsed, path: path) {
                    dependencyText += "\n\n# \(path)\n\(body.prefix(500))"
                }
            }
        }

        await progress(.init(progress: 0.9, message: "Compiling report..."))
        let important = manifests.prefix(10).map { "- \($0)" }.joined(separator: "\n")

        return .init(
            projectSummary: "Repository: \(parsed.owner)/\(parsed.repo)\nIndexed files: \(manifests.count)\n\(readmeText)",
            architectureOverview: "Swift files discovered: \(swiftFiles.count). Imported modules found in sampled files: \(imports.sorted().joined(separator: ", ")).",
            importantFiles: important,
            dependencies: dependencyText.isEmpty ? "No dependency manifests found." : dependencyText,
            integrationGuide: "1. Review README and dependency manifests.\n2. Start integration from important files list.\n3. Follow imports to identify boundaries.\n4. Validate with project build/test steps.",
            searchableSnippets: snippetLines
        )
    }

    private static func fetchGitHubFileContent(parsed: GitHubRepoReference, path: String) async throws -> String? {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let contentsURL = URL(string: "https://raw.githubusercontent.com/\(parsed.owner)/\(parsed.repo)/\(parsed.branch)/\(encodedPath)")!
        let (data, response) = try await URLSession.shared.data(from: contentsURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func answer(for query: String) -> String {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        let matches = searchableSnippets.filter { snippet in
            let lower = snippet.lowercased()
            return terms.contains(where: { lower.contains($0) })
        }.prefix(5)

        if matches.isEmpty {
            return "No direct text match found. Try asking with specific filenames, symbols, or module names."
        }

        return "Top relevant snippets:\n" + matches.joined(separator: "\n")
    }
}

private struct GitHubRepoReference {
    let host: String
    let owner: String
    let repo: String
    let branch: String

    init?(urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        self.host = host
        owner = parts[0]
        repo = parts[1].replacingOccurrences(of: ".git", with: "")

        if let branchIndex = parts.firstIndex(of: "tree"), parts.indices.contains(branchIndex + 1) {
            branch = parts[branchIndex + 1]
        } else {
            branch = "main"
        }
    }
}

private struct SearchGitHubTreeResponse: Decodable {
    let tree: [SearchGitHubTreeNode]
}

private struct SearchGitHubTreeNode: Decodable {
    let path: String
    let type: String
}
