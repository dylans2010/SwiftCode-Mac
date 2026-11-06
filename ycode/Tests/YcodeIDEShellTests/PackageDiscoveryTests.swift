import Foundation
import Testing
@testable import YcodeIDEShell

/// Package discovery: the pure graph/compatibility logic, the GitHub URL
/// parsing, and the persisted collections/favorites state.
/// The store tests share one state file, so the suite runs serially.
@Suite(.serialized)
@MainActor
struct PackageDiscoveryTests {
    @Test func graphFlagsConflictingRequirements() {
        let deps = [
            ParsedDependency(url: "https://github.com/apple/swift-collections.git", requirementType: .from, value: "1.0.0"),
            ParsedDependency(url: "https://github.com/apple/swift-collections.git", requirementType: .exact, value: "1.1.0"),
            ParsedDependency(url: "https://github.com/Alamofire/Alamofire.git", requirementType: .from, value: "5.9.0"),
        ]
        let nodes = PackageDependencyGraph.build(dependencies: deps)
        #expect(nodes.count == 2)
        #expect(nodes.first { $0.name == "swift-collections" }?.hasConflict == true)
        #expect(nodes.first { $0.name == "Alamofire" }?.hasConflict == false)
    }

    @Test func compatibilityScoresHonestly() {
        let package = PackageMetadata(
            name: "Demo", fullName: "example/Demo", cloneUrl: "https://github.com/example/Demo.git",
            stars: 10, forks: 1, openIssues: 0, license: "MIT", owner: "example",
            swiftToolsVersion: "5.9", platforms: ["macOS 13+"], lastReleasedVersion: "1.0.0")
        let ok = PackageCompatibility.analyze(package: package, projectSwiftToolsVersion: "5.10", projectPlatforms: ["macOS"])
        #expect(ok.toolsVersionMatch)
        #expect(ok.platformSupportMatch)
        #expect(ok.healthScore == 100)
        let tooNew = PackageCompatibility.analyze(package: package, projectSwiftToolsVersion: "5.7", projectPlatforms: ["macOS"])
        #expect(!tooNew.toolsVersionMatch)
        #expect(tooNew.healthScore < 100)
        let noLicense = PackageMetadata(
            name: "NoLic", fullName: "example/NoLic", cloneUrl: "https://github.com/example/NoLic.git",
            stars: 0, forks: 0, openIssues: 0, license: nil, owner: "example",
            swiftToolsVersion: "5.9", platforms: [], lastReleasedVersion: "1.0.0")
        let unknown = PackageCompatibility.analyze(package: noLicense, projectSwiftToolsVersion: "5.10", projectPlatforms: ["macOS"])
        #expect(!unknown.platformSupportMatch)
        #expect(unknown.recommendations.contains { $0.contains("declares no platforms") })
    }

    @Test func repositoryPathParsing() {
        #expect(PackageDiscoveryStore.repositoryPath(from: "https://github.com/apple/swift-collections.git") == "apple/swift-collections")
        #expect(PackageDiscoveryStore.repositoryPath(from: "not-a-url") == nil)
    }

    @Test func metadataFromSearchResult() {
        let result = GitHubSearchPackage(
            id: 7, name: "swift-collections", fullName: "apple/swift-collections",
            description: "Collections", htmlUrl: "https://github.com/apple/swift-collections",
            cloneUrl: "https://github.com/apple/swift-collections.git",
            stargazersCount: 4800, forksCount: 410, openIssuesCount: 32,
            license: GitHubSearchPackage.GitHubLicense(name: "Apache License 2.0", spdxId: "Apache-2.0"))
        let meta = PackageMetadata.fromSearchResult(result)
        #expect(meta.stars == 4800)
        #expect(meta.license == "Apache-2.0")
        #expect(meta.owner == "apple")
    }

    @Test func starterCatalogLoads() {
        let store = PackageDiscoveryStore()
        #expect(store.featuredPackages.contains { $0.name == "swift-collections" })
        #expect(store.trendingPackages.contains { $0.name == "Alamofire" })
        #expect(store.knownAdvisories.contains { $0.packageName == "Alamofire" })
    }

    @Test func favoritesAndCollectionsPersist() {
        let store = PackageDiscoveryStore()
        store.toggleFavorite(url: "https://github.com/example/Demo.git")
        #expect(store.favoritePackages.contains("https://github.com/example/Demo.git"))
        store.createCollection(name: "Test Kit", description: "For tests", category: "Utility")
        #expect(store.collections.contains { $0.name == "Test Kit" })
        store.toggleFavorite(url: "https://github.com/example/Demo.git")
        #expect(!store.favoritePackages.contains("https://github.com/example/Demo.git"))
    }

    @Test func installWithoutHandlerFailsHonestly() async {
        let store = PackageDiscoveryStore()
        let package = PackageMetadata(name: "Demo", fullName: "example/Demo", cloneUrl: "https://github.com/example/Demo.git", stars: 0, forks: 0, openIssues: 0, owner: "example")
        let ok = await store.installPackage(package, requirementType: .from, requirementValue: "1.0.0")
        #expect(!ok)
        #expect(store.operationLogs.contains { $0.contains("No project is open") })
    }
}
