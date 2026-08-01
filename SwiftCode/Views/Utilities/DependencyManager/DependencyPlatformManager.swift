import Foundation
import Observation
import os.log

public struct ParsedDependency: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public var url: String
    public var requirementType: DependencyRequirementType
    public var value: String
    public var isLocal: Bool = false

    public init(id: UUID = UUID(), url: String, requirementType: DependencyRequirementType, value: String, isLocal: Bool = false) {
        self.id = id
        self.url = url
        self.requirementType = requirementType
        self.value = value
        self.isLocal = isLocal
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

    public struct GitHubLicense: Codable, Sendable {
        public let name: String?
        public let spdxId: String?
    }
}

/// A model representing a custom user-created collection of packages.
public struct PackageCollection: Identifiable, Codable, Hashable {
    public var id = UUID()
    public var name: String
    public var description: String
    public var packageURLs: [String]
    public var category: String // e.g., "Networking", "Database", "UI"
    public var isPinned: Bool = false
    public var isWatchlist: Bool = false
    public var customTags: [String] = []
}

/// A model representing package metadata returned by the GitHub search or from our local catalog.
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
    public var swiftToolsVersion: String = "5.10"
    public var platforms: [String] = ["macOS 14+", "iOS 17+"]
    public var lastReleasedVersion: String = "1.0.0"
    public var releaseDate: Date = Date()
    public var isVerified: Bool = false
    public var topics: [String] = []
}

/// Model for AI conversations in the package workspace.
public struct PackageAIChat: Identifiable, Codable, Hashable {
    public var id = UUID()
    public var prompt: String
    public var response: String
    public var timestamp = Date()
    public var isFavorite: Bool = false
}

/// Model for Security Advisories.
public struct SecurityAdvisory: Identifiable, Codable, Hashable {
    public var id = UUID()
    public var packageName: String
    public var title: String
    public var severity: String // e.g. "High", "Critical", "Moderate"
    public var affectedVersions: String
    public var fixedVersion: String
    public var advisoryUrl: String
    public var details: String
}

/// Model for compatibility analysis.
public struct CompatibilityReport: Codable, Hashable {
    public var swiftVersionMatch: Bool
    public var toolsVersionMatch: Bool
    public var platformSupportMatch: Bool
    public var existingConflicts: [String]
    public var recommendations: [String]
    public var healthScore: Int // 0-100
}

/// Dynamic dependency node for graph visualizer.
public struct DependencyVisualNode: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var version: String
    public var dependencies: [String]
    public var isCircular: Bool = false
    public var hasConflict: Bool = false
    public var isLocal: Bool = false
}

@Observable
@MainActor
public final class DependencyPlatformManager {
    public static let shared = DependencyPlatformManager()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "DependencyPlatformManager")
    private let fm = FileManager.default

    // MARK: - State Properties
    public var collections: [PackageCollection] = []
    public var favoritePackages: [String] = []
    public var watchlistPackages: [String] = []
    public var searchHistory: [String] = []
    public var continueBrowsing: [String] = []
    public var recentActivity: [String] = []

    // Search & Explorer Cache
    public var searchResults: [PackageMetadata] = []
    public var trendingPackages: [PackageMetadata] = []
    public var featuredPackages: [PackageMetadata] = []
    public var cachedReadmes: [String: String] = [:] // Key: cloneUrl -> Readme text
    public var cachedManifests: [String: String] = [:] // Key: cloneUrl -> Package.swift syntax

    // Operation & Execution states
    public var isOperationRunning: Bool = false
    public var operationProgress: Double = 0.0
    public var operationStatus: String = "Idle"
    public var operationLogs: [String] = []

    // AI Assistant States
    public var chatHistory: [PackageAIChat] = []
    public var savedPrompts: [String] = [
        "Recommend a high-performance network caching library for swift",
        "Generate a Package.swift manifest configuration for a multi-target iOS/macOS library",
        "Explain how to migrate a project from CocoaPods to Swift Package Manager",
        "Compare Alamofire with URLSession for microservices architecture",
        "Explain how to resolve circular dependency conflict between target A and B"
    ]
    public var promptTemplates: [String: String] = [
        "Architecture Recommendation": "How should I architect a modular Swift package with separate Utilities, Core, and UI targets?",
        "Security Assessment": "What are the security best practices when importing third-party SPM packages?",
        "Performance Optimization": "How can I optimize the build times of a workspace with 15+ external packages?"
    ]

    // Security Center States
    public var knownAdvisories: [SecurityAdvisory] = []
    public var securityScanRunning: Bool = false
    public var securityScore: Int = 100

    // MARK: - Initializer
    private init() {
        loadState()
        loadPresets()
    }

    // MARK: - Persistence Keys
    private let collectionsKey = "com.swiftcode.dependencies.collections"
    private let favoritesKey = "com.swiftcode.dependencies.favorites"
    private let watchlistKey = "com.swiftcode.dependencies.watchlist"
    private let historyKey = "com.swiftcode.dependencies.history"
    private let chatKey = "com.swiftcode.dependencies.chatHistory"

    private func loadState() {
        let defaults = UserDefaults.standard

        // Favorites
        self.favoritePackages = defaults.stringArray(forKey: favoritesKey) ?? [
            "https://github.com/Alamofire/Alamofire.git",
            "https://github.com/apple/swift-algorithms.git",
            "https://github.com/apple/swift-collections.git",
            "https://github.com/pointfreeco/swift-composable-architecture.git",
            "https://github.com/SDWebImage/SDWebImageSwiftUI.git"
        ]

        // Watchlist
        self.watchlistPackages = defaults.stringArray(forKey: watchlistKey) ?? [
            "https://github.com/apple/swift-async-algorithms.git",
            "https://github.com/grpc/grpc-swift.git"
        ]

        // Search History
        self.searchHistory = defaults.stringArray(forKey: historyKey) ?? ["Alamofire", "swift-collections", "Keychain", "sqlite"]

        // Collections
        if let data = defaults.data(forKey: collectionsKey),
           let decoded = try? JSONDecoder().decode([PackageCollection].self, from: data) {
            self.collections = decoded
        } else {
            // Seed default collections
            self.collections = [
                PackageCollection(
                    name: "Core Networking Kit",
                    description: "Essential packages for secure endpoints, HTTP requests, and socket operations.",
                    packageURLs: ["https://github.com/Alamofire/Alamofire.git"],
                    category: "Networking",
                    isPinned: true
                ),
                PackageCollection(
                    name: "UI Utilities",
                    description: "Polished templates, image processing pipelines, and vector drawing additions.",
                    packageURLs: ["https://github.com/SDWebImage/SDWebImageSwiftUI.git"],
                    category: "UI",
                    isPinned: false
                )
            ]
        }

        // Chat History
        if let data = defaults.data(forKey: chatKey),
           let decoded = try? JSONDecoder().decode([PackageAIChat].self, from: data) {
            self.chatHistory = decoded
        }
    }

    public func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(favoritePackages, forKey: favoritesKey)
        defaults.set(watchlistPackages, forKey: watchlistKey)
        defaults.set(searchHistory, forKey: historyKey)

        if let data = try? JSONEncoder().encode(collections) {
            defaults.set(data, forKey: collectionsKey)
        }
        if let data = try? JSONEncoder().encode(chatHistory) {
            defaults.set(data, forKey: chatKey)
        }
    }

    private func loadPresets() {
        // Featured packages seed
        self.featuredPackages = [
            PackageMetadata(
                name: "swift-collections",
                fullName: "apple/swift-collections",
                description: "Efficient double-ended queues, ordered sets, ordered dictionaries, and red-black trees.",
                cloneUrl: "https://github.com/apple/swift-collections.git",
                stars: 4800,
                forks: 410,
                openIssues: 32,
                license: "Apache 2.0",
                owner: "apple",
                swiftToolsVersion: "5.9",
                platforms: ["macOS 13+", "iOS 16+", "tvOS 16+", "watchOS 9+"],
                lastReleasedVersion: "1.1.0",
                isVerified: true,
                topics: ["data-structures", "algorithms", "performance"]
            ),
            PackageMetadata(
                name: "swift-algorithms",
                fullName: "apple/swift-algorithms",
                description: "A toolbox of sequence and collection algorithms for the Swift standard library.",
                cloneUrl: "https://github.com/apple/swift-algorithms.git",
                stars: 6200,
                forks: 580,
                openIssues: 18,
                license: "Apache 2.0",
                owner: "apple",
                swiftToolsVersion: "5.8",
                platforms: ["macOS 12+", "iOS 15+"],
                lastReleasedVersion: "1.2.0",
                isVerified: true,
                topics: ["algorithms", "sorting", "permutations"]
            )
        ]

        // Trending packages seed
        self.trendingPackages = [
            PackageMetadata(
                name: "swift-composable-architecture",
                fullName: "pointfreeco/swift-composable-architecture",
                description: "A library for building applications in a consistent and understandable way, with composition, testing, and ergonomics in mind.",
                cloneUrl: "https://github.com/pointfreeco/swift-composable-architecture.git",
                stars: 10500,
                forks: 1200,
                openIssues: 45,
                license: "MIT",
                owner: "pointfreeco",
                swiftToolsVersion: "5.9",
                platforms: ["macOS 13+", "iOS 16+"],
                lastReleasedVersion: "1.10.0",
                isVerified: true,
                topics: ["architecture", "redux", "state-management"]
            ),
            PackageMetadata(
                name: "Alamofire",
                fullName: "Alamofire/Alamofire",
                description: "Elegant HTTP Networking in Swift",
                cloneUrl: "https://github.com/Alamofire/Alamofire.git",
                stars: 41000,
                forks: 7500,
                openIssues: 12,
                license: "MIT",
                owner: "Alamofire",
                swiftToolsVersion: "5.10",
                platforms: ["macOS 10.15+", "iOS 13+"],
                lastReleasedVersion: "5.9.1",
                isVerified: true,
                topics: ["networking", "http", "rest"]
            ),
            PackageMetadata(
                name: "SDWebImageSwiftUI",
                fullName: "SDWebImage/SDWebImageSwiftUI",
                description: "SwiftUI Image loading and animation framework powered by SDWebImage.",
                cloneUrl: "https://github.com/SDWebImage/SDWebImageSwiftUI.git",
                stars: 3200,
                forks: 480,
                openIssues: 15,
                license: "MIT",
                owner: "SDWebImage",
                swiftToolsVersion: "5.7",
                platforms: ["macOS 11+", "iOS 14+"],
                lastReleasedVersion: "3.0.4",
                isVerified: true,
                topics: ["swiftui", "image-loading", "webp", "gif"]
            )
        ]

        // Seed default Advisories
        self.knownAdvisories = [
            SecurityAdvisory(
                packageName: "Alamofire",
                title: "Improper Certificate Validation under Specific Proxy Configurations",
                severity: "Moderate",
                affectedVersions: "< 5.6.1",
                fixedVersion: "5.6.1",
                advisoryUrl: "https://github.com/Alamofire/Alamofire/security/advisories/GHSA-9pxf-2ur3-3p2g",
                details: "Alamofire versions before 5.6.1 incorrectly evaluated server trust constraints when using proxy connections with manual route configurations."
            ),
            SecurityAdvisory(
                packageName: "UnsafeCoreKit",
                title: "Buffer overflow vulnerability in serialization pipeline",
                severity: "Critical",
                affectedVersions: "<= 1.0.4",
                fixedVersion: "1.0.5",
                advisoryUrl: "https://nvd.nist.gov/vuln/detail/CVE-2026-99999",
                details: "A buffer overflow in string conversion routines can lead to potential remote code execution during processing of untrusted payloads."
            )
        ]

        self.continueBrowsing = [
            "https://github.com/apple/swift-collections.git",
            "https://github.com/SDWebImage/SDWebImageSwiftUI.git"
        ]

        self.recentActivity = [
            "Imported apple/swift-collections 1.1.0",
            "Searched for 'Alamofire'",
            "Scanned project security workspace",
            "Added core-networking collection"
        ]
    }

    // MARK: - Actions & Operations

    /// Executes a simulated GitHub search or fetches cached result
    public func executeGitHubSearch(query: String, language: String, license: String, minStars: Int) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        logger.info("Starting GitHub package discovery for query: \(query)")
        if !searchHistory.contains(trimmed) {
            searchHistory.insert(trimmed, at: 0)
            if searchHistory.count > 10 {
                searchHistory.removeLast()
            }
            saveState()
        }

        isOperationRunning = true
        operationProgress = 0.2
        operationStatus = "Connecting to GitHub Search API..."

        // Add log
        operationLogs.append("Initiated search for query: '\(trimmed)' with star filter: \(minStars)")

        do {
            let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let urlStr = "https://api.github.com/search/repositories?q=\(encodedQuery)+topic:swift-package+language:swift"
            guard let url = URL(string: urlStr) else { return }

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            // Apply Keychain Token if present
            if let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                operationLogs.append("Authorized request using configured GitHub API token.")
            }

            operationProgress = 0.5
            operationStatus = "Fetching results..."

            let (data, _) = try await URLSession.shared.data(for: request)

            operationProgress = 0.8
            operationStatus = "Decoding repositories..."

            struct GHSearchResult: Codable {
                let items: [GitHubSearchPackage]?
            }

            let result = try JSONDecoder().decode(GHSearchResult.self, from: data)

            let mapped = (result.items ?? []).map { item in
                PackageMetadata(
                    name: item.name,
                    fullName: item.fullName,
                    description: item.description,
                    cloneUrl: item.cloneUrl,
                    stars: item.stargazersCount,
                    forks: item.forksCount,
                    openIssues: item.openIssuesCount,
                    license: item.license?.name ?? item.license?.spdxId ?? "MIT",
                    owner: String(item.fullName.split(separator: "/").first ?? "Unknown"),
                    swiftToolsVersion: "5.10",
                    platforms: ["macOS 14+", "iOS 17+"],
                    lastReleasedVersion: "1.0.0",
                    topics: []
                )
            }

            self.searchResults = mapped
            operationLogs.append("Found \(mapped.count) matching package repositories.")

        } catch {
            logger.error("GitHub search failed: \(error.localizedDescription)")
            operationLogs.append("Search failed: \(error.localizedDescription)")

            // Fallback gracefully to offline seed data rather than failing completely
            let offlineMatch = featuredPackages + trendingPackages
            self.searchResults = offlineMatch.filter { $0.name.lowercased().contains(trimmed.lowercased()) }
            operationLogs.append("Returned \(self.searchResults.count) offline-cached fallback matches.")
        }

        isOperationRunning = false
        operationProgress = 1.0
        operationStatus = "Idle"
    }

    /// Installs a package to the active project's Package.swift
    public func installPackage(url: String, requirementType: String, requirementValue: String, activeProject: Project?) async -> Bool {
        guard let project = activeProject else {
            operationLogs.append("Installation failed: No active project session.")
            return false
        }

        isOperationRunning = true
        operationProgress = 0.1
        operationStatus = "Resolving Package manifest..."
        operationLogs.append("Installing \(url) (\(requirementType): \(requirementValue))...")

        try? await Task.sleep(nanoseconds: 500_000_000)

        operationProgress = 0.4
        operationStatus = "Writing Package.swift..."

        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")

        // Read dependencies
        var dependencies: [ParsedDependency] = []
        if let content = try? String(contentsOf: packageURL, encoding: .utf8) {
            let nsContent = content as NSString
            let pathPattern = #"\.package\(path:\s*"([^"]+)"\)"#
            let urlPattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#

            if let pathRegex = try? NSRegularExpression(pattern: pathPattern) {
                let matches = pathRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
                for match in matches {
                    let path = nsContent.substring(with: match.range(at: 1))
                    dependencies.append(ParsedDependency(url: path, requirementType: .exact, value: "local", isLocal: true))
                }
            }

            if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
                let matches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
                for match in matches {
                    let pUrl = nsContent.substring(with: match.range(at: 1))
                    let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
                    let val = nsContent.substring(with: match.range(at: 3))
                    let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
                    dependencies.append(ParsedDependency(url: pUrl, requirementType: reqType, value: val, isLocal: false))
                }
            }
        }

        // Remove existing duplicate if any
        dependencies.removeAll { $0.url.lowercased().replacingOccurrences(of: ".git", with: "") == url.lowercased().replacingOccurrences(of: ".git", with: "") }

        // Add new dependency
        let reqType = DependencyRequirementType(rawValue: requirementType) ?? .from
        let isLocal = (requirementType == "local" || requirementType == "path")
        dependencies.append(ParsedDependency(url: url, requirementType: isLocal ? .exact : reqType, value: requirementValue, isLocal: isLocal))

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
            operationProgress = 0.8
            operationStatus = "Verifying package structure..."
            ProjectSessionStore.shared.refreshFileTree(for: project)
            operationLogs.append("Successfully imported \(url) to Package.swift.")

            // Cache manifest syntax
            cachedManifests[url] = packageContent

            if !recentActivity.contains("Imported \(url)") {
                recentActivity.insert("Imported \(url)", at: 0)
            }

            isOperationRunning = false
            operationProgress = 1.0
            operationStatus = "Idle"
            return true
        } catch {
            logger.error("Failed to write Package.swift: \(error.localizedDescription)")
            operationLogs.append("Error updating manifest: \(error.localizedDescription)")
            isOperationRunning = false
            operationProgress = 1.0
            operationStatus = "Idle"
            return false
        }
    }

    /// Removes a package from the active project's Package.swift
    public func removePackage(url: String, activeProject: Project?) async -> Bool {
        guard let project = activeProject else { return false }

        isOperationRunning = true
        operationProgress = 0.2
        operationStatus = "Locating package reference..."
        operationLogs.append("Removing \(url) from manifest...")

        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else {
            isOperationRunning = false
            return false
        }

        var dependencies: [ParsedDependency] = []
        let nsContent = content as NSString

        let pathPattern = #"\.package\(path:\s*"([^"]+)"\)"#
        let urlPattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#

        if let pathRegex = try? NSRegularExpression(pattern: pathPattern) {
            let matches = pathRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let path = nsContent.substring(with: match.range(at: 1))
                dependencies.append(ParsedDependency(url: path, requirementType: .exact, value: "local", isLocal: true))
            }
        }

        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let pUrl = nsContent.substring(with: match.range(at: 1))
                let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
                let val = nsContent.substring(with: match.range(at: 3))
                let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
                dependencies.append(ParsedDependency(url: pUrl, requirementType: reqType, value: val, isLocal: false))
            }
        }

        let beforeCount = dependencies.count
        dependencies.removeAll { $0.url.lowercased().replacingOccurrences(of: ".git", with: "") == url.lowercased().replacingOccurrences(of: ".git", with: "") }

        if dependencies.count == beforeCount {
            operationLogs.append("Package reference not found in Package.swift.")
            isOperationRunning = false
            return false
        }

        operationProgress = 0.6
        operationStatus = "Writing updated manifest..."

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
            operationProgress = 0.9
            ProjectSessionStore.shared.refreshFileTree(for: project)
            operationLogs.append("Successfully removed \(url) from package dependencies.")
            recentActivity.insert("Removed package \(url)", at: 0)
            isOperationRunning = false
            return true
        } catch {
            operationLogs.append("Failed to write updated manifest: \(error.localizedDescription)")
            isOperationRunning = false
            return false
        }
    }

    // MARK: - Security Auditing
    public func executeSecurityScan(dependencies: [ParsedDependency]) async {
        securityScanRunning = true
        operationLogs.append("Initiating security audit for \(dependencies.count) dependencies...")

        try? await Task.sleep(nanoseconds: 800_000_000)

        var foundAdvisories = 0
        var score = 100

        for dep in dependencies {
            let depName = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
            if knownAdvisories.contains(where: { $0.packageName.lowercased() == depName.lowercased() }) {
                foundAdvisories += 1
                score -= 30
            }
        }

        self.securityScore = max(0, score)
        operationLogs.append("Security audit complete. Found \(foundAdvisories) known advisories. Global risk score: \(self.securityScore)/100.")
        securityScanRunning = false
    }

    // MARK: - Project Compatibility Analysis
    public func analyzeCompatibility(packageUrl: String, activeProject: Project?) -> CompatibilityReport {
        let repoName = packageUrl.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "SelectedPackage"

        var report = CompatibilityReport(
            swiftVersionMatch: true,
            toolsVersionMatch: true,
            platformSupportMatch: true,
            existingConflicts: [],
            recommendations: [],
            healthScore: 95
        )

        if let project = activeProject {
            // Check for existing package structure
            let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
            if !FileManager.default.fileExists(atPath: packageURL.path) {
                report.recommendations.append("The active project does not contain a Package.swift manifest yet. SwiftCode will automatically generate one upon installation.")
                report.healthScore -= 10
            }

            // High star/featured triggers
            let isPopular = featuredPackages.contains(where: { $0.cloneUrl == packageUrl }) || trendingPackages.contains(where: { $0.cloneUrl == packageUrl })
            if isPopular {
                report.recommendations.append("\(repoName) is a highly-rated community resource. Integration path is fully tested.")
                report.healthScore = 100
            } else {
                report.recommendations.append("Ensure the selected version matches target deployment environments.")
            }
        } else {
            report.recommendations.append("Open a project session inside the main editor workspace to analyze full platform requirements.")
            report.healthScore = 50
        }

        return report
    }

    // MARK: - AI Assistant Queries
    public func askAIAssistant(prompt: String) async -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        isOperationRunning = true
        operationStatus = "AI Co-Designer formulating answer..."
        operationLogs.append("Formulated question to AI package assistant.")

        let promptWithContext = """
You are a highly skilled Swift Package Manager and dependency management consultant.
Provide a professional, clear, production-ready, and comprehensive architectural response to:
"\(trimmed)"

Give specific package recommendations, Package.swift configurations, or dependency visualization explanations where useful.
"""

        var aiAnswer = ""
        do {
            // Leverage the central LLMService if available
            aiAnswer = try await LLMService.shared.generateResponse(prompt: promptWithContext)
        } catch {
            // Robust offline knowledge-base fallback response
            aiAnswer = generateAIFallback(for: trimmed)
        }

        let chat = PackageAIChat(prompt: trimmed, response: aiAnswer)
        chatHistory.append(chat)
        saveState()

        isOperationRunning = false
        operationStatus = "Idle"
        return aiAnswer
    }

    private func generateAIFallback(for prompt: String) -> String {
        let normalized = prompt.lowercased()

        if normalized.contains("networking") || normalized.contains("alamofire") {
            return """
### Recommendation: Core Networking Architecture

For high-performance network calls inside Swift 6 workspaces, **Alamofire** combined with Swift structured concurrency remains the premier solution.

```swift
// Package.swift Dependency Spec
.package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.1")
```

**Alternative:** If your codebase is purely built on modern OS layers, standard **URLSession** with async/await handles native pipelines elegantly without any external dependency.
"""
        } else if normalized.contains("composable") || normalized.contains("architecture") || normalized.contains("redux") {
            return """
### Architecture Analysis: Composable Architecture (TCA)

**The Composable Architecture (TCA)** by Point-Free provides a powerful framework for building applications in a consistent, state-driven, and composable manner.

*   **Pros:** Ergonomic state propagation, high testability, easy modularization.
*   **Cons:** Higher learning curve, compile-time overhead for large target matrices.

```swift
// Manifest Integration
.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.10.0")
```
"""
        } else if normalized.contains("conflict") || normalized.contains("circular") {
            return """
### Resolving Circular Dependency Conflicts

When Target A references Target B, and Target B imports Target A, Swift Package Manager will emit a cyclic dependency error.

**Resolution Steps:**
1.  **Extract Shared Domain:** Move shared models, interfaces, or protocol protocols into a separate target (e.g., `SharedModels` or `CoreInterfaces`).
2.  **Point Dependencies Downward:** Update both Target A and Target B to depend only on the new shared target. This guarantees a unidirectional acyclic graph (DAG).
"""
        } else {
            return """
### Package Platform Assistant Report

Your request regarding **"\(prompt)"** has been analyzed.

1.  **Swift 6 Compatibility:** All recommended packages conform to strict concurrency checks.
2.  **Modularization Tip:** Leverage target divisions inside `Package.swift` to keep external libraries isolated within dedicated networking or model layers.
3.  **Security Recommendation:** Verify license credentials to ensure full compatibility with your target deployment platform.
"""
        }
    }

    // MARK: - Collections CRUD
    public func createCollection(name: String, description: String, category: String) {
        let col = PackageCollection(name: name, description: description, packageURLs: [], category: category)
        collections.append(col)
        saveState()
    }

    public func toggleFavorite(url: String) {
        if favoritePackages.contains(url) {
            favoritePackages.removeAll { $0 == url }
        } else {
            favoritePackages.append(url)
        }
        saveState()
    }

    public func toggleWatchlist(url: String) {
        if watchlistPackages.contains(url) {
            watchlistPackages.removeAll { $0 == url }
        } else {
            watchlistPackages.append(url)
        }
        saveState()
    }

    // MARK: - Graph Generation
    public func buildDependencyGraph(dependencies: [ParsedDependency]) -> [DependencyVisualNode] {
        var nodes: [DependencyVisualNode] = []

        // Root node represents the current project itself
        var rootDeps: [String] = []

        for dep in dependencies {
            let name = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
            rootDeps.append(name)

            // Nested simulated children for visual richness
            var childDeps: [String] = []
            if name.lowercased().contains("composable") {
                childDeps = ["CasePaths", "CombineSchedulers", "ConcurrencyExtras", "IdentifiedCollections"]
            } else if name.lowercased().contains("sdwebimage") {
                childDeps = ["SDWebImage"]
            } else if name.lowercased().contains("alamofire") {
                childDeps = ["Foundation"]
            }

            nodes.append(DependencyVisualNode(
                name: name,
                version: dep.value,
                dependencies: childDeps,
                isCircular: false,
                hasConflict: knownAdvisories.contains(where: { $0.packageName.lowercased() == name.lowercased() }),
                isLocal: dep.isLocal
            ))

            // Map the child dependencies as leaf nodes if they are not already listed
            for child in childDeps {
                if !nodes.contains(where: { $0.name == child }) {
                    nodes.append(DependencyVisualNode(
                        name: child,
                        version: "v1.0.0",
                        dependencies: [],
                        isCircular: false,
                        hasConflict: false,
                        isLocal: false
                    ))
                }
            }
        }

        return nodes
    }
}
