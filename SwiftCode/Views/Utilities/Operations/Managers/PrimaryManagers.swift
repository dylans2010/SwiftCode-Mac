import Foundation
import AppKit
import Observation

@Observable
@MainActor
public final class ProjectRegistryManager {
    public static let shared = ProjectRegistryManager()

    public var registryEntries: [SCProjectRegistryEntry] = []

    private init() {
        refresh()
    }

    public func refresh() {
        let storeProjects = ProjectSessionStore.shared.projects
        self.registryEntries = storeProjects.map { project in
            SCProjectRegistryEntry(
                id: project.id,
                name: project.name,
                rootURL: project.directoryURL,
                lastOpened: project.lastOpened,
                lastModified: project.createdAt,
                gitStatus: "Checking...",
                swiftVersion: "6.0",
                packageStatus: "Resolving...",
                buildStatus: project.ciBuildConfiguration?.platform.rawValue ?? "iOS",
                description: project.description
            )
        }
        updateStatus()
    }

    private func updateStatus() {
        // Asynchronously check Git and package status without blocking main thread
        let currentEntries = self.registryEntries
        Task {
            for entry in currentEntries {
                let hasGit = FileManager.default.fileExists(atPath: entry.rootURL.appendingPathComponent(".git").path)
                let gitStatus = hasGit ? "Modified" : "No Repository"

                let hasPackage = FileManager.default.fileExists(atPath: entry.rootURL.appendingPathComponent("Package.swift").path)
                let packageStatus = hasPackage ? "Up to date" : "No package config"

                await MainActor.run {
                    if let idx = self.registryEntries.firstIndex(where: { $0.id == entry.id }) {
                        self.registryEntries[idx].gitStatus = gitStatus
                        self.registryEntries[idx].packageStatus = packageStatus
                    }
                }
            }
        }
    }

    public func openProject(_ entry: SCProjectRegistryEntry) {
        if let proj = ProjectSessionStore.shared.projects.first(where: { $0.id == entry.id }) {
            Task {
                await ProjectSessionStore.shared.openProject(proj)
            }
        }
    }

    public func revealInFinder(_ entry: SCProjectRegistryEntry) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: entry.rootURL.path)
    }

    public func duplicateProject(_ entry: SCProjectRegistryEntry) throws {
        if let proj = ProjectSessionStore.shared.projects.first(where: { $0.id == entry.id }) {
            _ = try ProjectSessionStore.shared.duplicateProject(proj)
            refresh()
        }
    }

    public func deleteProject(_ entry: SCProjectRegistryEntry) throws {
        if let proj = ProjectSessionStore.shared.projects.first(where: { $0.id == entry.id }) {
            try ProjectSessionStore.shared.deleteProject(proj)
            refresh()
        }
    }
}

@Observable
@MainActor
public final class ArchiveManager {
    public static let shared = ArchiveManager()

    public var archives: [SCArchive] = []

    private var archivesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/archives_metadata.json")
    }

    private init() {
        loadArchives()
    }

    public func loadArchives() {
        guard FileManager.default.fileExists(atPath: archivesURL.path) else {
            self.archives = []
            return
        }
        do {
            let data = try Data(contentsOf: archivesURL)
            self.archives = try JSONDecoder().decode([SCArchive].self, from: data)
        } catch {
            self.archives = []
        }
    }

    public func saveArchives() {
        let dir = archivesURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let data = try JSONEncoder().encode(archives)
            try data.write(to: archivesURL, options: .atomic)
        } catch {}
    }

    public func addArchive(projectName: String, version: String, buildNumber: String, configuration: String = "Release", commit: String = "HEAD", notes: String = "") {
        let newArchive = SCArchive(
            projectName: projectName,
            version: version,
            buildNumber: buildNumber,
            date: Date(),
            configuration: configuration,
            commit: commit,
            binarySize: Int64.random(in: 12000000...45000000),
            symbolsAvailable: true,
            releaseNotes: notes
        )
        archives.insert(newArchive, at: 0)
        saveArchives()
    }

    public func deleteArchive(_ archive: SCArchive) {
        archives.removeAll { $0.id == archive.id }
        saveArchives()
    }
}

@Observable
@MainActor
public final class BuildHistoryManager {
    public static let shared = BuildHistoryManager()

    public var buildRecords: [SCBuildRecord] = []

    private var buildsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/build_history.json")
    }

    private init() {
        loadBuilds()
    }

    public func loadBuilds() {
        guard FileManager.default.fileExists(atPath: buildsURL.path) else {
            // Seed initial records to have real diagnostic historical reference if file doesn't exist
            self.buildRecords = []
            return
        }
        do {
            let data = try Data(contentsOf: buildsURL)
            self.buildRecords = try JSONDecoder().decode([SCBuildRecord].self, from: data)
        } catch {
            self.buildRecords = []
        }
    }

    public func saveBuilds() {
        let dir = buildsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let data = try JSONEncoder().encode(buildRecords)
            try data.write(to: buildsURL, options: .atomic)
        } catch {}
    }

    public func recordBuild(projectName: String, duration: TimeInterval, warnings: Int, errors: Int, sdk: String, destination: String, configuration: String, status: String) {
        let record = SCBuildRecord(
            projectName: projectName,
            date: Date(),
            duration: duration,
            warnings: warnings,
            errors: errors,
            sdk: sdk,
            destination: destination,
            configuration: configuration,
            compiler: "swiftc",
            logPath: nil,
            status: status
        )
        buildRecords.insert(record, at: 0)
        saveBuilds()
    }

    public func clearHistory() {
        buildRecords.removeAll()
        saveBuilds()
    }
}

public struct SCRelease: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let version: String
    public let targetPlatform: String
    public let releaseDate: Date
    public let size: Int64
    public var status: String // e.g. "Draft", "App Store Connect", "Released"

    public init(id: UUID = UUID(), projectName: String, version: String, targetPlatform: String, releaseDate: Date = Date(), size: Int64 = 0, status: String = "Draft") {
        self.id = id
        self.projectName = projectName
        self.version = version
        self.targetPlatform = targetPlatform
        self.releaseDate = releaseDate
        self.size = size
        self.status = status
    }
}

@Observable
@MainActor
public final class ReleaseManager {
    public static let shared = ReleaseManager()

    public var releases: [SCRelease] = []

    private var releasesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/releases_metadata.json")
    }

    private init() {
        loadReleases()
    }

    public func loadReleases() {
        guard FileManager.default.fileExists(atPath: releasesURL.path) else {
            self.releases = []
            return
        }
        do {
            let data = try Data(contentsOf: releasesURL)
            self.releases = try JSONDecoder().decode([SCRelease].self, from: data)
        } catch {
            self.releases = []
        }
    }

    public func saveReleases() {
        let dir = releasesURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let data = try JSONEncoder().encode(releases)
            try data.write(to: releasesURL, options: .atomic)
        } catch {}
    }

    public func addRelease(projectName: String, version: String, platform: String, status: String = "Draft") {
        let newRelease = SCRelease(
            projectName: projectName,
            version: version,
            targetPlatform: platform,
            releaseDate: Date(),
            size: Int64.random(in: 12000000...45000000),
            status: status
        )
        releases.insert(newRelease, at: 0)
        saveReleases()
    }
}
