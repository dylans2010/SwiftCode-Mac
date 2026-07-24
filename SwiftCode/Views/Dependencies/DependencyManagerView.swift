import SwiftUI
import AppKit

struct ParsedDependency: Identifiable, Codable {
    var id: UUID = UUID()
    var url: String
    var requirementType: DependencyRequirementType
    var value: String
    var isLocal: Bool = false
}

enum DependencyRequirementType: String, CaseIterable, Identifiable, Codable {
    case from = "from"
    case branch = "branch"
    case revision = "revision"
    case exact = "exact"

    var id: String { rawValue }
}

struct GitHubSearchPackage: Identifiable, Codable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let htmlUrl: String
    let cloneUrl: String
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let license: GitHubLicense?

    struct GitHubLicense: Codable {
        let name: String?
        let spdxId: String?
    }
}

struct DependencyManagerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var dependencies: [ParsedDependency] = []
    @State private var errorMessage: String?
    @State private var showError = false

    // Form inputs
    @State private var selectedPackageURL = ""
    @State private var selectedRequirementType: DependencyRequirementType = .from
    @State private var selectedRequirementValue = "1.0.0"
    @State private var isLocalPackage = false

    // UI selections & states
    @State private var editingDependency: ParsedDependency?
    @State private var searchQuery = ""
    @State private var githubSearchResults: [GitHubSearchPackage] = []
    @State private var isSearching = false

    // Details/Preview panel
    @State private var selectedGitHubPackage: GitHubSearchPackage?
    @State private var readmePreviewText = ""
    @State private var isLoadingReadme = false

    // Presets/Favorites & Recents stored in UserDefaults
    @State private var favoritePackages: [String] = [
        "https://github.com/Alamofire/Alamofire.git",
        "https://github.com/apple/swift-algorithms.git",
        "https://github.com/apple/swift-collections.git",
        "https://github.com/pointfreeco/swift-composable-architecture.git",
        "https://github.com/SDWebImage/SDWebImageSwiftUI.git"
    ]
    @State private var recentlyUsedPackages: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Dependency Manager", systemImage: "puzzlepiece.extension.fill")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            Text("Search, import, and manage local or remote Swift packages. Add dependencies to your Package.swift cleanly and automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Group 1: Active Dependencies
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Active Dependencies", systemImage: "checklist")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.blue)
                                Spacer()
                                Button {
                                    selectLocalFolderPackage()
                                } label: {
                                    Label("Add Local...", systemImage: "folder.badge.plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if dependencies.isEmpty {
                                Text("No packages imported yet in Package.swift.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(dependencies) { dep in
                                        HStack {
                                            Image(systemName: dep.isLocal ? "folder.fill" : "puzzlepiece.extension.fill")
                                                .foregroundStyle(dep.isLocal ? .orange : .blue)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url)
                                                    .font(.subheadline.bold())
                                                Text("\(dep.requirementType.rawValue): \(dep.value)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            HStack(spacing: 8) {
                                                Button {
                                                    beginEdit(dep)
                                                } label: {
                                                    Image(systemName: "pencil")
                                                        .foregroundStyle(.blue)
                                                }
                                                .buttonStyle(.plain)

                                                Button {
                                                    removeDependency(dep)
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .foregroundStyle(.red)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Group 2: Favorite Presets
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Favorite Presets", systemImage: "star.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(favoritePackages, id: \.self) { fav in
                                        Button {
                                            self.selectedPackageURL = fav
                                            self.isLocalPackage = false
                                            self.selectedRequirementType = .from
                                            self.selectedRequirementValue = "1.0.0"
                                            self.selectedGitHubPackage = nil
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                                Text(fav.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? fav)
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.secondary.opacity(0.1), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Group 3: GitHub Search Engine
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("GitHub Search Engine", systemImage: "magnifyingglass")
                                .font(.subheadline.bold())
                                .foregroundStyle(.purple)

                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search package name (e.g. Alamofire)...", text: $searchQuery)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        searchGitHubPackages()
                                    }

                                Button("Search") {
                                    searchGitHubPackages()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            if isSearching {
                                HStack {
                                    Spacer()
                                    ProgressView().scaleEffect(0.6)
                                    Text("Searching GitHub...").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 8)
                            } else if !githubSearchResults.isEmpty {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(githubSearchResults) { pkg in
                                            Button {
                                                selectGitHubPackage(pkg)
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(pkg.name)
                                                            .font(.subheadline.bold())
                                                            .foregroundStyle(.primary)
                                                        Text(pkg.fullName)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    HStack(spacing: 6) {
                                                        Image(systemName: "star.fill")
                                                            .foregroundStyle(.yellow)
                                                        Text("\(pkg.stargazersCount)")
                                                            .font(.caption2)
                                                    }
                                                }
                                                .padding(8)
                                                .background(selectedPackageURL == pkg.cloneUrl ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(height: 160)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Selected GitHub Package Metadata Card
                    if let pkg = selectedGitHubPackage {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(pkg.name, systemImage: "sparkles")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Button {
                                        toggleFavoritePackage(pkg.cloneUrl)
                                    } label: {
                                        Image(systemName: favoritePackages.contains(pkg.cloneUrl) ? "star.fill" : "star")
                                            .foregroundStyle(.yellow)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(pkg.description ?? "No description available.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 16) {
                                    Label("\(pkg.stargazersCount) stars", systemImage: "star.fill")
                                    Label("\(pkg.forksCount) forks", systemImage: "arrow.branch")
                                    Label(pkg.license?.name ?? "No License", systemImage: "doc.text")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Group 4: Package Specifications Form
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Package Specifications")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Repository URL or Local Path")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("Path/URL", text: $selectedPackageURL)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Requirement Specification")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                Picker("", selection: $selectedRequirementType) {
                                    ForEach(DependencyRequirementType.allCases) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .disabled(isLocalPackage)

                                TextField(requirementPlaceholderText, text: $selectedRequirementValue)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .disabled(isLocalPackage)
                            }

                            if detectDuplicate(selectedPackageURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text("Duplicate detected! This package appears to already exist.")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }
                                .padding(6)
                                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Group 5: Package.swift Preview Syntax
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Package.swift Output Preview", systemImage: "doc.text.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)

                            Text(previewSyntaxString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.green)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Group 6: README Preview Panel
                    if selectedGitHubPackage != nil {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("README.md Preview")
                                    .font(.subheadline.bold())

                                if isLoadingReadme {
                                    HStack {
                                        ProgressView().controlSize(.small)
                                        Text("Loading documentation...").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    ScrollView {
                                        Text(readmePreviewText)
                                            .font(.caption.monospaced())
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .frame(height: 180)
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Bottom Action Trigger Button
                    Button {
                        saveDependency()
                    } label: {
                        Label(editingDependency != nil ? "Save Dependency" : "Import Swift Package", systemImage: "square.and.arrow.down.fill")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedPackageURL.isEmpty)
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Package Dependency Suite")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .onAppear {
                loadDependencies()
                loadPresetsState()
            }
        }
    }

    private var requirementPlaceholderText: String {
        switch selectedRequirementType {
        case .from: return "Version number (e.g. 5.8.0)"
        case .branch: return "Branch name (e.g. main)"
        case .revision: return "Revision SHA (e.g. 0ea8b21)"
        case .exact: return "Exact version (e.g. 1.5.3)"
        }
    }

    private var previewSyntaxString: String {
        if isLocalPackage {
            return ".package(path: \"\(selectedPackageURL)\")"
        } else {
            return ".package(url: \"\(selectedPackageURL)\", \(selectedRequirementType.rawValue): \"\(selectedRequirementValue)\")"
        }
    }

    // MARK: - Actions & SPM Logic

    private func loadDependencies() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else { return }

        // Parse path dependencies as well as URL ones
        let pathPattern = #"\.package\(path:\s*"([^"]+)"\)"#
        let urlPattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#

        var parsedList: [ParsedDependency] = []
        let nsContent = content as NSString

        if let pathRegex = try? NSRegularExpression(pattern: pathPattern) {
            let matches = pathRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let path = nsContent.substring(with: match.range(at: 1))
                parsedList.append(ParsedDependency(url: path, requirementType: .exact, value: "local", isLocal: true))
            }
        }

        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let url = nsContent.substring(with: match.range(at: 1))
                let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
                let val = nsContent.substring(with: match.range(at: 3))

                let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
                parsedList.append(ParsedDependency(url: url, requirementType: reqType, value: val, isLocal: false))
            }
        }

        self.dependencies = parsedList
    }

    private func selectLocalFolderPackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Folder Containing Package.swift"

        if panel.runModal() == .OK, let url = panel.url {
            let fileCheck = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: fileCheck.path) {
                // Succeeded validation! Set inputs
                self.selectedPackageURL = url.path
                self.isLocalPackage = true
                self.selectedRequirementType = .exact
                self.selectedRequirementValue = "local"
                self.selectedGitHubPackage = nil
            } else {
                self.errorMessage = "The selected directory does not contain a valid Package.swift file."
                self.showError = true
            }
        }
    }

    private func searchGitHubPackages() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        isSearching = true
        githubSearchResults.removeAll()

        Task {
            do {
                let urlStr = "https://api.github.com/search/repositories?q=\(trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedQuery)+topic:swift-package"
                guard let url = URL(string: urlStr) else { return }
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                // Add GitHub token if active
                if let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                let (data, _) = try await URLSession.shared.data(for: request)

                struct GHSearchResult: Codable {
                    let items: [GitHubSearchPackage]?
                }

                let response = try JSONDecoder().decode(GHSearchResult.self, from: data)
                self.githubSearchResults = response.items ?? []
            } catch {
                self.errorMessage = "Failed to search GitHub packages: \(error.localizedDescription)"
                self.showError = true
            }
            isSearching = false
        }
    }

    private func selectGitHubPackage(_ pkg: GitHubSearchPackage) {
        self.selectedGitHubPackage = pkg
        self.selectedPackageURL = pkg.cloneUrl
        self.isLocalPackage = false
        self.selectedRequirementType = .from
        self.selectedRequirementValue = "1.0.0"

        // Load readme preview asynchronously
        self.readmePreviewText = ""
        self.isLoadingReadme = true

        Task {
            do {
                let owner = pkg.fullName.split(separator: "/").first.map(String.init) ?? ""
                let name = pkg.name
                let readmeURLStr = "https://raw.githubusercontent.com/\(owner)/\(name)/main/README.md"
                guard let readmeURL = URL(string: readmeURLStr) else { return }
                let (data, _) = try await URLSession.shared.data(from: readmeURL)
                if let text = String(data: data, encoding: .utf8) {
                    self.readmePreviewText = text
                } else {
                    self.readmePreviewText = "No readable README.md found on the main branch."
                }
            } catch {
                self.readmePreviewText = "No README.md documentation available for this package."
            }
            self.isLoadingReadme = false
        }
    }

    private func toggleFavoritePackage(_ url: String) {
        if favoritePackages.contains(url) {
            favoritePackages.removeAll { $0 == url }
        } else {
            favoritePackages.append(url)
        }
        UserDefaults.standard.set(favoritePackages, forKey: "com.swiftcode.packages.favorites")
    }

    private func detectDuplicate(_ url: String) -> Bool {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: ".git", with: "")
        return dependencies.contains { $0.url.lowercased().replacingOccurrences(of: ".git", with: "") == normalized }
    }

    private func beginEdit(_ dep: ParsedDependency) {
        self.editingDependency = dep
        self.selectedPackageURL = dep.url
        self.selectedRequirementType = dep.requirementType
        self.selectedRequirementValue = dep.value
        self.isLocalPackage = dep.isLocal
        self.selectedGitHubPackage = nil
    }

    private func removeDependency(_ dep: ParsedDependency) {
        dependencies.removeAll { $0.id == dep.id }
        updatePackageSwift()
    }

    private func saveDependency() {
        let urlStr = selectedPackageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let valStr = selectedRequirementValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing = editingDependency, let idx = dependencies.firstIndex(where: { $0.id == editing.id }) {
            dependencies[idx].url = urlStr
            dependencies[idx].requirementType = selectedRequirementType
            dependencies[idx].value = valStr
            dependencies[idx].isLocal = isLocalPackage
        } else {
            let dep = ParsedDependency(url: urlStr, requirementType: selectedRequirementType, value: valStr, isLocal: isLocalPackage)
            dependencies.append(dep)
        }

        // Record recents
        if !isLocalPackage && !recentlyUsedPackages.contains(urlStr) {
            recentlyUsedPackages.insert(urlStr, at: 0)
            if recentlyUsedPackages.count > 5 {
                recentlyUsedPackages.removeLast()
            }
            UserDefaults.standard.set(recentlyUsedPackages, forKey: "com.swiftcode.packages.recents")
        }

        updatePackageSwift()

        // Reset form
        self.selectedGitHubPackage = nil
        self.selectedPackageURL = ""
        self.editingDependency = nil
    }

    private func updatePackageSwift() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")

        let depsString = dependencies.map { dep in
            if dep.isLocal {
                return "        .package(path: \"\(dep.url)\")"
            } else {
                return "        .package(url: \"\(dep.url)\", \(dep.requirementType.rawValue): \"\(dep.value)\")"
            }
        }.joined(separator: ",\n")

        let packageContent = """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(project.name)",
    platforms: [.iOS(.v17)],
    dependencies: [
\(depsString)
    ],
    targets: [
        .executableTarget(
            name: "\(project.name)",
            path: "Sources"
        )
    ]
)
"""
        do {
            try packageContent.write(to: packageURL, atomically: true, encoding: .utf8)
            sessionStore.refreshFileTree(for: project)
            loadDependencies()
        } catch {
            errorMessage = "Failed to write Package.swift: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - State Persistence

    private func loadPresetsState() {
        if let favs = UserDefaults.standard.stringArray(forKey: "com.swiftcode.packages.favorites") {
            self.favoritePackages = favs
        }
        if let recents = UserDefaults.standard.stringArray(forKey: "com.swiftcode.packages.recents") {
            self.recentlyUsedPackages = recents
        }
    }
}
