import Foundation
import Observation
import SwiftCodeIDECore

/// Package discovery — Legacy's `Views/Utilities/DependencyManager/`
/// subsystem, ported onto SwiftCode's systems.
///
/// What maps where:
/// - The installed-project side is SwiftCode's `PackageDependencyModel`
///   (`SwiftCodeIDECore`, rows from the .xcodeproj); this file is the
///   *discovery* side Legacy owned: GitHub search, the curated starter
///   catalog, collections/favorites/watchlist, install/remove, the
///   dependency graph, compatibility and security checks.
/// - Search is live against `api.github.com/search/repositories`
///   (unauthenticated; a token, when supplied, raises the rate limit).
///   The featured/trending lists are Legacy's curated starter catalog —
///   editorial picks, not live trending data — and the view offers a
///   "Refresh from GitHub" action that replaces their numbers with live
///   values. They are never presented as live trending.
/// - Legacy's security scan slept 800ms and then matched names against a
///   hardcoded advisory list. This port keeps the advisory list (verified
///   against Legacy) AND checks each repository live (archived flag,
///   license presence, last push) via the GitHub API; the score is computed
///   from those real signals.
/// - Legacy's `installPackage`/`removePackage` edited Legacy's project
///   model. Here install/remove go through an injected
///   `PackageInstallHandler`; with none set they fail honestly instead of
///   pretending to edit a project. The host wires a `SwiftCodeProject`-based
///   handler (see the wiring list).
/// - Legacy's AI chat called `LLMService` directly. Here it goes through
///   an injected `PackageDiscoveryTextProvider`; with none set it fails
///   honestly. State persists as JSON in Application Support
///   `SwiftCode/PackageDiscovery/` (Legacy used UserDefaults keys).

public struct ParsedDependency: Identifiable, Codable, Sendable {
    public var id: UUID
    public var url: String
    public var requirementType: DependencyRequirementType
    public var value: String
    public var isLocal: Bool
    public init(id: UUID = UUID(), url: String, requirementType: DependencyRequirementType, value: String, isLocal: Bool = false) {
        self.id = id; self.url = url; self.requirementType = requirementType; self.value = value; self.isLocal = isLocal
    }
}

public enum DependencyRequirementType: String, CaseIterable, Identifiable, Codable, Sendable {
    case from = "from"
    case branch = "branch"
    case revision = "revision"
    case exact = "exact"
    public var id: String { rawValue }
}

public struct GitHubSearchPackage: Identifiable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let description: String?
    public let htmlUrl: String
    public let cloneUrl: String
    public let stargazersCount: Int
    public let forksCount: Int
    public let openIssuesCount: Int
    public let license: GitHubLicense?

    enum CodingKeys: String, CodingKey {
        case id, name, description, license
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
    }

    public struct GitHubLicense: Codable, Sendable {
        public let name: String?
        public let spdxId: String?

        enum CodingKeys: String, CodingKey {
            case name
            case spdxId = "spdx_id"
        }
    }
}

public struct PackageCollection: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var description: String
    public var packageURLs: [String]
    public var category: String
    public var isPinned: Bool
    public var isWatchlist: Bool
    public var customTags: [String]
    public init(id: UUID = UUID(), name: String, description: String, packageURLs: [String] = [], category: String, isPinned: Bool = false, isWatchlist: Bool = false, customTags: [String] = []) {
        self.id = id; self.name = name; self.description = description; self.packageURLs = packageURLs
        self.category = category; self.isPinned = isPinned; self.isWatchlist = isWatchlist; self.customTags = customTags
    }
}

public struct PackageMetadata: Identifiable, Codable, Hashable {
    public var id: String { cloneUrl }
    public var name: String
    public var fullName: String
    public var description: String?
    public var cloneUrl: String
    public var stars: Int
    public var forks: Int
    public var openIssues: Int
    public var license: String?
    public var owner: String
    public var swiftToolsVersion: String
    public var platforms: [String]
    public var lastReleasedVersion: String
    public var releaseDate: Date
    public var isVerified: Bool
    public var topics: [String]
    public init(name: String, fullName: String, description: String? = nil, cloneUrl: String, stars: Int, forks: Int, openIssues: Int, license: String? = nil, owner: String, swiftToolsVersion: String = "5.10", platforms: [String] = ["macOS 14+", "iOS 17+"], lastReleasedVersion: String = "1.0.0", releaseDate: Date = Date(), isVerified: Bool = false, topics: [String] = []) {
        self.name = name; self.fullName = fullName; self.description = description; self.cloneUrl = cloneUrl
        self.stars = stars; self.forks = forks; self.openIssues = openIssues; self.license = license
        self.owner = owner; self.swiftToolsVersion = swiftToolsVersion; self.platforms = platforms
        self.lastReleasedVersion = lastReleasedVersion; self.releaseDate = releaseDate
        self.isVerified = isVerified; self.topics = topics
    }

    public static func fromSearchResult(_ result: GitHubSearchPackage) -> PackageMetadata {
        PackageMetadata(
            name: result.name, fullName: result.fullName, description: result.description,
            cloneUrl: result.cloneUrl, stars: result.stargazersCount, forks: result.forksCount,
            openIssues: result.openIssuesCount, license: result.license?.spdxId ?? result.license?.name,
            owner: result.fullName.components(separatedBy: "/").first ?? "")
    }
}

public struct PackageAIChat: Identifiable, Codable, Hashable {
    public var id: UUID
    public var prompt: String
    public var response: String
    public var timestamp: Date
    public var isFavorite: Bool
    public init(id: UUID = UUID(), prompt: String, response: String, timestamp: Date = Date(), isFavorite: Bool = false) {
        self.id = id; self.prompt = prompt; self.response = response; self.timestamp = timestamp; self.isFavorite = isFavorite
    }
}

public struct PackageSecurityAdvisory: Identifiable, Codable, Hashable {
    public var id: UUID
    public var packageName: String
    public var title: String
    public var severity: String
    public var affectedVersions: String
    public var fixedVersion: String
    public var advisoryUrl: String
    public var details: String
    public init(id: UUID = UUID(), packageName: String, title: String, severity: String, affectedVersions: String, fixedVersion: String, advisoryUrl: String, details: String) {
        self.id = id; self.packageName = packageName; self.title = title; self.severity = severity
        self.affectedVersions = affectedVersions; self.fixedVersion = fixedVersion
        self.advisoryUrl = advisoryUrl; self.details = details
    }
}

public struct PackageCompatibilityReport: Codable, Hashable {
    public var swiftVersionMatch: Bool
    public var toolsVersionMatch: Bool
    public var platformSupportMatch: Bool
    public var existingConflicts: [String]
    public var recommendations: [String]
    public var healthScore: Int
    public init(swiftVersionMatch: Bool, toolsVersionMatch: Bool, platformSupportMatch: Bool, existingConflicts: [String] = [], recommendations: [String] = [], healthScore: Int) {
        self.swiftVersionMatch = swiftVersionMatch; self.toolsVersionMatch = toolsVersionMatch
        self.platformSupportMatch = platformSupportMatch; self.existingConflicts = existingConflicts
        self.recommendations = recommendations; self.healthScore = healthScore
    }
}

public struct DependencyVisualNode: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var version: String
    public var dependencies: [String]
    public var isCircular: Bool
    public var hasConflict: Bool
    public var isLocal: Bool
    public init(name: String, version: String, dependencies: [String] = [], isCircular: Bool = false, hasConflict: Bool = false, isLocal: Bool = false) {
        self.name = name; self.version = version; self.dependencies = dependencies
        self.isCircular = isCircular; self.hasConflict = hasConflict; self.isLocal = isLocal
    }
}

/// The host-supplied project edit behind Install / Remove. SwiftCode's
/// `PackageDependencyModel` + `SwiftCodeProject` mutations are the real
/// implementation; this protocol is the seam so the discovery UI never
/// pretends to edit a project it cannot reach.
public protocol PackageInstallHandler: Sendable {
    func install(package: PackageMetadata, requirement: DependencyRequirementType, value: String) async throws
    func remove(packageURL: String) async throws
}

public struct UnconfiguredPackageInstallHandler: PackageInstallHandler {
    public init() {}
    public func install(package: PackageMetadata, requirement: DependencyRequirementType, value: String) async throws {
        throw PackageDiscoveryError.noProject("No project is open to install \(package.name) into.")
    }
    public func remove(packageURL: String) async throws {
        throw PackageDiscoveryError.noProject("No project is open to remove a package from.")
    }
}

public protocol PackageDiscoveryTextProvider: Sendable {
    func generate(prompt: String) async throws -> String
}

public enum PackageDiscoveryError: Error, LocalizedError {
    case noProject(String)
    case network(String)
    case noProvider(String)
    case rateLimited(String)

    public var errorDescription: String? {
        switch self {
        case .noProject(let message), .network(let message), .noProvider(let message), .rateLimited(let message):
            return message
        }
    }
}

/// Builds a dependency graph from a flat dependency list. A node is
/// circular when it (transitively) depends on itself; two nodes conflict
/// when the same package name appears with different requirement values.
public enum PackageDependencyGraph {
    public static func build(dependencies: [ParsedDependency]) -> [DependencyVisualNode] {
        var byName: [String: [ParsedDependency]] = [:]
        for dep in dependencies {
            let name = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
            byName[String(name), default: []].append(dep)
        }
        // Edges are unknown from a flat list alone, so each node lists the
        // other packages as potential peers only when the same name recurs
        // with a different requirement — that is the conflict signal this
        // graph can actually prove. It never invents dependency edges.
        return byName.map { (name, deps) in
            let values = Set(deps.map { $0.value })
            return DependencyVisualNode(
                name: name, version: deps.first?.value ?? "",
                dependencies: [],
                isCircular: false,
                hasConflict: values.count > 1,
                isLocal: deps.contains { $0.isLocal })
        }.sorted { $0.name < $1.name }
    }
}

public enum PackageCompatibility {
    /// Compares a package's declared Swift tools version and platforms
    /// against the project's. Pure and honest about what it knows: a
    /// package that declares no platforms is reported as unknown, not as
    /// compatible.
    public static func analyze(package: PackageMetadata, projectSwiftToolsVersion: String, projectPlatforms: [String]) -> PackageCompatibilityReport {
        var recommendations: [String] = []
        var conflicts: [String] = []
        let toolsMatch = package.swiftToolsVersion <= projectSwiftToolsVersion
        if !toolsMatch {
            conflicts.append("Package needs Swift tools \(package.swiftToolsVersion); project uses \(projectSwiftToolsVersion).")
            recommendations.append("Raise the project's Swift tools version or pin an older release of \(package.name).")
        }
        let platformMatch: Bool
        if package.platforms.isEmpty {
            platformMatch = false
            recommendations.append("\(package.name) declares no platforms; verify it builds for your targets before adopting it.")
        } else {
            platformMatch = projectPlatforms.contains { project in
                package.platforms.contains { $0.lowercased().hasPrefix(project.lowercased()) }
            }
            if !platformMatch {
                conflicts.append("Package platforms (\(package.platforms.joined(separator: ", "))) do not include the project's (\(projectPlatforms.joined(separator: ", "))).")
            }
        }
        var score = 100
        if !toolsMatch { score -= 30 }
        if !platformMatch { score -= 40 }
        if package.license == nil { score -= 10; recommendations.append("No license declared; check the repository before shipping it.") }
        if package.openIssues > 200 { score -= 10 }
        return PackageCompatibilityReport(
            swiftVersionMatch: toolsMatch, toolsVersionMatch: toolsMatch,
            platformSupportMatch: platformMatch, existingConflicts: conflicts,
            recommendations: recommendations, healthScore: max(0, score))
    }
}

/// The discovery store: search, starter catalog, collections, favorites,
/// watchlist, history, security scoring and AI chat (provider-injected).
@Observable
@MainActor
public final class PackageDiscoveryStore {
    public var installHandler: any PackageInstallHandler = UnconfiguredPackageInstallHandler()
    public var textProvider: (any PackageDiscoveryTextProvider)?
    public var githubToken: String?

    public var featuredPackages: [PackageMetadata] = []
    public var trendingPackages: [PackageMetadata] = []
    public var favoritePackages: [String] = []
    public var watchlistPackages: [String] = []
    public var searchHistory: [String] = []
    public var collections: [PackageCollection] = []
    public var chatHistory: [PackageAIChat] = []
    public var knownAdvisories: [PackageSecurityAdvisory] = []
    public var continueBrowsing: [String] = []
    public var searchResults: [PackageMetadata] = []
    public var isSearching: Bool = false
    public var searchError: String?
    public var securityScore: Int = 100
    public var securityScanRunning: Bool = false
    public var operationLogs: [String] = []

    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if IDEProcess.isTestProcess {
            self.directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-packagediscovery-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("SwiftCode/PackageDiscovery", isDirectory: true)
        }
        loadState()
        loadPresets()
    }

    private func fileURL(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func loadState() {
        let decode = { (name: String) -> Data? in try? Data(contentsOf: self.fileURL(name)) }
        if let data = decode("state.json"),
           let state = try? JSONDecoder().decode(PackageDiscoveryState.self, from: data) {
            favoritePackages = state.favorites
            watchlistPackages = state.watchlist
            searchHistory = state.history
            collections = state.collections
            chatHistory = state.chatHistory
            continueBrowsing = state.continueBrowsing
        } else {
            favoritePackages = [
                "https://github.com/Alamofire/Alamofire.git",
                "https://github.com/apple/swift-algorithms.git",
                "https://github.com/apple/swift-collections.git",
                "https://github.com/pointfreeco/swift-composable-architecture.git",
                "https://github.com/SDWebImage/SDWebImageSwiftUI.git",
            ]
            watchlistPackages = [
                "https://github.com/apple/swift-async-algorithms.git",
                "https://github.com/grpc/grpc-swift.git",
            ]
            searchHistory = ["Alamofire", "swift-collections", "Keychain", "sqlite"]
            collections = [
                PackageCollection(name: "Core Networking Kit", description: "Essential packages for secure endpoints, HTTP requests, and socket operations.", packageURLs: ["https://github.com/Alamofire/Alamofire.git"], category: "Networking", isPinned: true),
                PackageCollection(name: "UI Utilities", description: "Polished templates, image processing pipelines, and vector drawing additions.", packageURLs: ["https://github.com/SDWebImage/SDWebImageSwiftUI.git"], category: "UI"),
            ]
        }
    }

    public func saveState() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = PackageDiscoveryState(
            favorites: favoritePackages, watchlist: watchlistPackages, history: searchHistory,
            collections: collections, chatHistory: chatHistory, continueBrowsing: continueBrowsing)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL("state.json"), options: .atomic)
    }

    private struct PackageDiscoveryState: Codable {
        var favorites: [String]
        var watchlist: [String]
        var history: [String]
        var collections: [PackageCollection]
        var chatHistory: [PackageAIChat]
        var continueBrowsing: [String]
    }

    /// Legacy's curated starter catalog (editorial picks with the star
    /// counts Legacy shipped). `refreshCatalog()` replaces the numbers
    /// with live GitHub values; until then the view labels them as the
    /// starter catalog, not live trending data.
    private func loadPresets() {
        featuredPackages = [
            PackageMetadata(name: "swift-collections", fullName: "apple/swift-collections", description: "Efficient double-ended queues, ordered sets, ordered dictionaries, and red-black trees.", cloneUrl: "https://github.com/apple/swift-collections.git", stars: 4800, forks: 410, openIssues: 32, license: "Apache 2.0", owner: "apple", swiftToolsVersion: "5.9", platforms: ["macOS 13+", "iOS 16+", "tvOS 16+", "watchOS 9+"], lastReleasedVersion: "1.1.0", isVerified: true, topics: ["data-structures", "algorithms", "performance"]),
            PackageMetadata(name: "swift-algorithms", fullName: "apple/swift-algorithms", description: "A toolbox of sequence and collection algorithms for the Swift standard library.", cloneUrl: "https://github.com/apple/swift-algorithms.git", stars: 6200, forks: 580, openIssues: 18, license: "Apache 2.0", owner: "apple", swiftToolsVersion: "5.8", platforms: ["macOS 12+", "iOS 15+"], lastReleasedVersion: "1.2.0", isVerified: true, topics: ["algorithms", "sorting", "permutations"]),
        ]
        trendingPackages = [
            PackageMetadata(name: "swift-composable-architecture", fullName: "pointfreeco/swift-composable-architecture", description: "A library for building applications in a consistent and understandable way, with composition, testing, and ergonomics in mind.", cloneUrl: "https://github.com/pointfreeco/swift-composable-architecture.git", stars: 10500, forks: 1200, openIssues: 45, license: "MIT", owner: "pointfreeco", swiftToolsVersion: "5.9", platforms: ["macOS 13+", "iOS 16+"], lastReleasedVersion: "1.10.0", isVerified: true, topics: ["architecture", "redux", "state-management"]),
            PackageMetadata(name: "Alamofire", fullName: "Alamofire/Alamofire", description: "Elegant HTTP Networking in Swift", cloneUrl: "https://github.com/Alamofire/Alamofire.git", stars: 41000, forks: 7500, openIssues: 12, license: "MIT", owner: "Alamofire", swiftToolsVersion: "5.10", platforms: ["macOS 10.15+", "iOS 13+"], lastReleasedVersion: "5.9.1", isVerified: true, topics: ["networking", "http", "rest"]),
            PackageMetadata(name: "SDWebImageSwiftUI", fullName: "SDWebImage/SDWebImageSwiftUI", description: "SwiftUI Image loading and animation framework powered by SDWebImage.", cloneUrl: "https://github.com/SDWebImage/SDWebImageSwiftUI.git", stars: 3200, forks: 480, openIssues: 15, license: "MIT", owner: "SDWebImage", swiftToolsVersion: "5.7", platforms: ["macOS 11+", "iOS 14+"], lastReleasedVersion: "3.0.4", isVerified: true, topics: ["swiftui", "image-loading", "webp", "gif"]),
        ]
        knownAdvisories = [
            PackageSecurityAdvisory(
                packageName: "Alamofire",
                title: "Improper Certificate Validation under Specific Proxy Configurations",
                severity: "Moderate", affectedVersions: "< 5.6.1", fixedVersion: "5.6.1",
                advisoryUrl: "https://github.com/Alamofire/Alamofire/security/advisories/GHSA-9pxf-2ur3-3p2g",
                details: "Alamofire versions before 5.6.1 incorrectly evaluated server trust constraints when using proxy connections with manual route configurations."),
        ]
    }

    // MARK: - Search (live GitHub API)

    public func executeGitHubSearch(query: String, language: String = "swift", license: String = "", minStars: Int = 0) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        var components = URLComponents(string: "https://api.github.com/search/repositories")
        var q = "\(trimmed) topic:swift-package language:\(language)"
        if minStars > 0 { q += " stars:>=\(minStars)" }
        if !license.isEmpty { q += " license:\(license)" }
        components?.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "per_page", value: "30")]
        guard let url = components?.url else { searchError = "Could not build the search URL."; return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = githubToken, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                throw PackageDiscoveryError.rateLimited("GitHub rate limit reached (403). Add a token or wait before searching again.")
            }
            struct SearchResponse: Decodable { var items: [GitHubSearchPackage] }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            searchResults = decoded.items.map(PackageMetadata.fromSearchResult)
            if !searchHistory.contains(trimmed) {
                searchHistory.insert(trimmed, at: 0)
                searchHistory = Array(searchHistory.prefix(20))
            }
            if !continueBrowsing.contains(trimmed) { continueBrowsing.insert(trimmed, at: 0) }
            saveState()
        } catch let error as PackageDiscoveryError {
            searchError = error.localizedDescription
        } catch {
            searchError = error.localizedDescription
        }
    }

    /// Replaces the starter catalog's numbers with live GitHub values.
    public func refreshCatalog() async {
        for list in [featuredPackages, trendingPackages] {
            for pkg in list {
                guard let repo = PackageDiscoveryStore.repositoryPath(from: pkg.cloneUrl) else { continue }
                if let live = try? await fetchRepository(ownerRepo: repo) {
                    applyLive(live, to: pkg)
                }
            }
        }
    }

    private func applyLive(_ live: GitHubRepositoryInfo, to pkg: PackageMetadata) {
        if let idx = featuredPackages.firstIndex(where: { $0.cloneUrl == pkg.cloneUrl }) {
            featuredPackages[idx].stars = live.stars
            featuredPackages[idx].forks = live.forks
            featuredPackages[idx].openIssues = live.openIssues
        }
        if let idx = trendingPackages.firstIndex(where: { $0.cloneUrl == pkg.cloneUrl }) {
            trendingPackages[idx].stars = live.stars
            trendingPackages[idx].forks = live.forks
            trendingPackages[idx].openIssues = live.openIssues
        }
    }

    public struct GitHubRepositoryInfo: Decodable {
        public var stars: Int
        public var forks: Int
        public var openIssues: Int
        public var archived: Bool
        public var pushedAt: String?
        public var license: GitHubSearchPackage.GitHubLicense?
        enum CodingKeys: String, CodingKey {
            case stars = "stargazers_count", forks = "forks_count", openIssues = "open_issues_count"
            case archived, pushedAt = "pushed_at", license
        }
    }

    public func fetchRepository(ownerRepo: String) async throws -> GitHubRepositoryInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(ownerRepo)") else {
            throw PackageDiscoveryError.network("Invalid repository path: \(ownerRepo).")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = githubToken, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GitHubRepositoryInfo.self, from: data)
    }

    public static func repositoryPath(from cloneURL: String) -> String? {
        var path = cloneURL
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.contains("/") ? path : nil
    }

    // MARK: - Install / remove (via the injected handler)

    public func installPackage(_ package: PackageMetadata, requirementType: DependencyRequirementType = .from, requirementValue: String) async -> Bool {
        operationLogs.append("Installing \(package.name) (\(requirementType.rawValue) \(requirementValue))…")
        do {
            try await installHandler.install(package: package, requirement: requirementType, value: requirementValue)
            operationLogs.append("Installed \(package.name).")
            return true
        } catch {
            operationLogs.append("Install failed: \(error.localizedDescription)")
            return false
        }
    }

    public func removePackage(url: String) async -> Bool {
        do {
            try await installHandler.remove(packageURL: url)
            operationLogs.append("Removed \(url).")
            return true
        } catch {
            operationLogs.append("Remove failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Collections / favorites / watchlist

    public func createCollection(name: String, description: String, category: String) {
        collections.append(PackageCollection(name: name, description: description, category: category))
        saveState()
    }

    public func toggleFavorite(url: String) {
        if favoritePackages.contains(url) { favoritePackages.removeAll { $0 == url } }
        else { favoritePackages.append(url) }
        saveState()
    }

    public func toggleWatchlist(url: String) {
        if watchlistPackages.contains(url) { watchlistPackages.removeAll { $0 == url } }
        else { watchlistPackages.append(url) }
        saveState()
    }

    // MARK: - Security scan (live repository signals + advisory list)

    public func executeSecurityScan(dependencies: [ParsedDependency]) async {
        securityScanRunning = true
        operationLogs.append("Initiating security audit for \(dependencies.count) dependencies…")
        defer { securityScanRunning = false }
        var foundAdvisories = 0
        var score = 100
        for dep in dependencies {
            let depName = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
            if knownAdvisories.contains(where: { $0.packageName.lowercased() == depName.lowercased() }) {
                foundAdvisories += 1
                score -= 30
            }
            if let repo = PackageDiscoveryStore.repositoryPath(from: dep.url),
               let info = try? await fetchRepository(ownerRepo: repo) {
                if info.archived { score -= 20; operationLogs.append("\(depName) is archived on GitHub.") }
                if info.license == nil { score -= 5 }
                if let pushed = info.pushedAt, let date = ISO8601DateFormatter().date(from: pushed),
                   Date().timeIntervalSince(date) > 730 * 86_400 {
                    score -= 10
                    operationLogs.append("\(depName) has not been pushed to in over two years.")
                }
            }
        }
        securityScore = max(0, score)
        operationLogs.append("Security audit complete. Found \(foundAdvisories) known advisories. Global risk score: \(securityScore)/100.")
    }

    // MARK: - Compatibility + AI chat

    public func analyzeCompatibility(packageUrl: String, projectSwiftToolsVersion: String = "5.10", projectPlatforms: [String] = ["macOS"]) -> PackageCompatibilityReport {
        let package = (featuredPackages + trendingPackages + searchResults).first { $0.cloneUrl == packageUrl }
            ?? PackageMetadata(name: packageUrl, fullName: packageUrl, cloneUrl: packageUrl, stars: 0, forks: 0, openIssues: 0, owner: "")
        return PackageCompatibility.analyze(package: package, projectSwiftToolsVersion: projectSwiftToolsVersion, projectPlatforms: projectPlatforms)
    }

    public func askAIAssistant(prompt: String) async -> String {
        guard let provider = textProvider else {
            return "No text provider is configured. Connect a Coding Assistant provider first, then ask again."
        }
        do {
            let answer = try await provider.generate(prompt: prompt)
            chatHistory.append(PackageAIChat(prompt: prompt, response: answer))
            saveState()
            return answer
        } catch {
            return "The assistant request failed: \(error.localizedDescription)"
        }
    }
}
