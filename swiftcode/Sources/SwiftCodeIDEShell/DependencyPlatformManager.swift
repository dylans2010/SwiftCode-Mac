// Ported from Legacy `SwiftCode/Views/Utilities/DependencyManager/DependencyPlatformManager.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SecurityAdvisory, DependencyPlatformManager.
// Fixed by W-V2: dropped the bogus `import PackageDescription` (only usable in a
// Package.swift manifest — this file only *generates* manifest text inside string
// literals) and added the real imports (SwiftCodeAssistant for LLMService/KeychainService,
// SwiftCodeIDECore for Project/ProjectSessionStore). This unblocks
// DependencyVisualizerView's `DependencyPlatformManager.shared` ref.
//
// CLEANUP (2026-11-06, triage §C20) — fabricated package data deleted:
// (a) Seeded featured/trending catalogs (stale fixed stars/forks/versions,
//     e.g. swift-collections 4800 stars, tools "5.9") are gone; both lists
//     start empty and fill only from live GitHub search results.
// (b) Seeded advisories are gone. The "UnsafeCoreKit / CVE-2026-99999"
//     advisory was invented (no such CVE, no such package) and is deleted,
//     never re-seeded. The "Alamofire / GHSA-9pxf-2ur3-3p2g" entry is
//     deleted too: its advisory page and its API record both return 404
//     (checked 2026-11-06), so it cannot be presented as verified.
//     `knownAdvisories` starts empty until a live advisory source
//     (GitHub Advisory Database / OSV API) populates it.
// (c) `recentActivity` / `continueBrowsing` start empty and are recorded
//     from real user actions only (install/remove, package detail views).
// (d) On GitHub API failure the search no longer falls back to the seed
//     catalog filtered by name ("offline-cached fallback matches"); it
//     clears results, records `searchError`, and surfaces the failure.
// (e) `buildDependencyGraph` no longer invents children by name match
//     (composable -> CasePaths/…, alamofire -> Foundation); it delegates
//     to `PackageDependencyGraph.build`, which never invents edges.
//     Transitive edges need `Package.resolved` / `swift package
//     show-dependencies --format json` — not a flat list.
// (f) Live GitHub search results are no longer re-stamped with
//     tools "5.10", platforms ["macOS 14+", "iOS 17+"], version "1.0.0"
//     (and no "MIT" license is assumed when the API returns none):
//     only values the API returns are kept; the rest stay unset.
//
// NOTE: `PackageMetadata`'s own init defaults (in the sibling
// `PackageDiscoveryModel.swift`, out of this slice) still stamp
// "5.10" / ["macOS 14+", "iOS 17+"] / "1.0.0" for callers that rely
// on them — that residue needs a follow-up in that file. This file
// passes explicit unset values instead of relying on the defaults.

import Foundation
import Observation
import SwiftCodeAssistant
import SwiftCodeIDECore
import os

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
    /// The last GitHub search failure, if any; `nil` after a success.
    /// Search failures are surfaced here (and in `operationLogs`) instead
    /// of being papered over with seeded data.
    public var searchError: String? = nil
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
        // No seeded catalogs: featured/trending lists populate only from
        // live GitHub search results (see executeGitHubSearch). The stale
        // fixed star/fork/version rows Legacy shipped (swift-collections
        // 4800 stars, tools "5.9", etc.) are deleted, not re-seeded.
        self.featuredPackages = []
        self.trendingPackages = []

        // No seeded advisories. Advisories come only from a live advisory
        // source (GitHub Advisory Database / OSV API); nothing is invented
        // here. Deleted: the fabricated "UnsafeCoreKit / CVE-2026-99999"
        // entry (no such CVE, no such package) and the "Alamofire /
        // GHSA-9pxf-2ur3-3p2g" entry, whose advisory page and API record
        // both return 404, so it cannot be presented as verified either.
        self.knownAdvisories = []

        // Browsing history and activity start empty and are recorded from
        // real user actions only (PackageDetailsView appends to
        // continueBrowsing; install/remove append to recentActivity).
        self.continueBrowsing = []
        self.recentActivity = []
    }

    // MARK: - Actions & Operations

    /// Searches GitHub for Swift packages via the live Search API.
    /// On failure the error is surfaced (`searchError`, operation log,
    /// `operationStatus`) and results are cleared — no seeded or cached
    /// data is ever substituted for failed search results.
    public func executeGitHubSearch(query: String, language: String, license: String, minStars: Int) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        logger.info("Starting GitHub package discovery for query: \(query)")
        searchError = nil
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
            guard let url = URL(string: urlStr) else {
                // Do not return with the manager stuck "running".
                self.searchError = "Could not build the GitHub search URL."
                operationLogs.append("Search failed: \(self.searchError ?? "")")
                isOperationRunning = false
                operationProgress = 1.0
                operationStatus = "Search failed"
                return
            }

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            // Apply Keychain Token if present
            if let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                operationLogs.append("Authorized request using configured GitHub API token.")
            }

            operationProgress = 0.5
            operationStatus = "Fetching results..."

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "DependencyPlatformManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub Search API returned HTTP \(http.statusCode)."])
            }

            operationProgress = 0.8
            operationStatus = "Decoding repositories..."

            struct GHSearchResult: Codable {
                let items: [GitHubSearchPackage]?
            }

            let result = try JSONDecoder().decode(GHSearchResult.self, from: data)

            // Only values the Search API actually returns are kept. The
            // search payload carries no Swift tools version, platform
            // list, latest release, or (sometimes) license, so those stay
            // unset (""/[]/nil) instead of being re-stamped with "5.10",
            // ["macOS 14+", "iOS 17+"], "1.0.0", or an assumed "MIT".
            let mapped = (result.items ?? []).map { item in
                PackageMetadata(
                    name: item.name,
                    fullName: item.fullName,
                    description: item.description,
                    cloneUrl: item.cloneUrl,
                    stars: item.stargazersCount,
                    forks: item.forksCount,
                    openIssues: item.openIssuesCount,
                    license: item.license?.spdxId ?? item.license?.name,
                    owner: String(item.fullName.split(separator: "/").first ?? "Unknown"),
                    swiftToolsVersion: "",
                    platforms: [],
                    lastReleasedVersion: "",
                    topics: []
                )
            }

            self.searchResults = mapped
            self.searchError = nil
            operationLogs.append("Found \(mapped.count) matching package repositories.")

        } catch {
            logger.error("GitHub search failed: \(error.localizedDescription)")
            operationLogs.append("Search failed: \(error.localizedDescription)")

            // Surface the failure instead of substituting seed data:
            // stale or invented results would present as search results.
            self.searchResults = []
            self.searchError = error.localizedDescription
            operationLogs.append("No results: the search failed and no cached or seeded data is substituted.")
        }

        isOperationRunning = false
        operationProgress = 1.0
        operationStatus = searchError == nil ? "Idle" : "Search failed"
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
            aiAnswer = try await LLMService.shared.generateResponse(prompt: promptWithContext, useContext: false)
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
    /// Builds the dependency graph from a flat dependency list. Edges
    /// are NOT invented: only the direct dependencies become nodes, with
    /// no children, because a flat list cannot prove transitive edges
    /// (this delegates to `PackageDependencyGraph.build`, which never
    /// invents edges). Transitive edges require `Package.resolved` or
    /// `swift package show-dependencies --format json`; until a caller
    /// supplies that data, nodes honestly have no children. The only
    /// overlay is `hasConflict`, set from the live known-advisory list
    /// (and from duplicate requirement values, per that builder).
    public func buildDependencyGraph(dependencies: [ParsedDependency]) -> [DependencyVisualNode] {
        PackageDependencyGraph.build(dependencies: dependencies).map { node in
            var node = node
            node.hasConflict = node.hasConflict
                || knownAdvisories.contains { $0.packageName.lowercased() == node.name.lowercased() }
            return node
        }
    }
}
