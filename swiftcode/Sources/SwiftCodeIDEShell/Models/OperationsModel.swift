import Foundation
import Observation
import SwiftCodeIDECore

public enum OperationsPanel: String, CaseIterable, Identifiable, Codable {
    case dashboard = "Dashboard"
    case projectRegistry = "Project Registry"
    case archives = "Archive Manager"
    case buildHistory = "Build History"
    case diagnostics = "Diagnostics"
    case dependencies = "Dependencies"
    case storage = "Storage"
    case security = "Security"
    case aiReports = "AI Reports"
    case health = "Workspace Health"
    case logs = "Logging Center"
    case timeline = "Timeline"
    case search = "Search"
    case queue = "Operation Queue"
    case notifications = "Notifications"
    case preferences = "Preferences"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .projectRegistry: return "folder"
        case .archives: return "archivebox"
        case .buildHistory: return "clock"
        case .diagnostics: return "ant"
        case .dependencies: return "puzzlepiece"
        case .storage: return "externaldrive"
        case .security: return "shield"
        case .aiReports: return "sparkles"
        case .health: return "heart.text.square"
        case .logs: return "doc.text.magnifyingglass"
        case .timeline: return "calendar.day.timeline.left"
        case .search: return "magnifyingglass"
        case .queue: return "list.bullet.rectangle"
        case .notifications: return "bell"
        case .preferences: return "gearshape"
        }
    }
}

public struct OperationsArchive: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let version: String
    public let buildNumber: String
    public let date: Date
    public let configuration: String
    public let commit: String
    public let binarySize: Int64
    public let symbolsAvailable: Bool
    public var releaseNotes: String
    public init(id: UUID = UUID(), projectName: String, version: String, buildNumber: String, date: Date = Date(), configuration: String = "Release", commit: String = "N/A", binarySize: Int64 = 0, symbolsAvailable: Bool = true, releaseNotes: String = "") {
        self.id = id; self.projectName = projectName; self.version = version; self.buildNumber = buildNumber
        self.date = date; self.configuration = configuration; self.commit = commit
        self.binarySize = binarySize; self.symbolsAvailable = symbolsAvailable; self.releaseNotes = releaseNotes
    }
}

public struct OperationsBuildRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let date: Date
    public let duration: TimeInterval
    public let warnings: Int
    public let errors: Int
    public let sdk: String
    public let destination: String
    public let configuration: String
    public let compiler: String
    public let logPath: String?
    public var status: String
    public init(id: UUID = UUID(), projectName: String, date: Date = Date(), duration: TimeInterval = 0, warnings: Int = 0, errors: Int = 0, sdk: String = "macosx", destination: String = "My Mac", configuration: String = "Debug", compiler: String = "swiftc", logPath: String? = nil, status: String = "Succeeded") {
        self.id = id; self.projectName = projectName; self.date = date; self.duration = duration
        self.warnings = warnings; self.errors = errors; self.sdk = sdk; self.destination = destination
        self.configuration = configuration; self.compiler = compiler; self.logPath = logPath; self.status = status
    }
}

public struct OperationsNotification: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let type: String
    public let date: Date
    public var isRead: Bool
    public init(id: UUID = UUID(), title: String, subtitle: String, type: String, date: Date = Date(), isRead: Bool = false) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.type = type; self.date = date; self.isRead = isRead
    }
}

public struct OperationsLogEntry: Identifiable, Codable, Sendable, Hashable {
    public enum Level: String, Codable, Sendable { case info, warning, error }
    public let id: UUID
    public let date: Date
    public let level: Level
    public let panel: String
    public let message: String
    public init(id: UUID = UUID(), date: Date = Date(), level: Level = .info, panel: String, message: String) {
        self.id = id; self.date = date; self.level = level; self.panel = panel; self.message = message
    }
}

public struct OperationsRegistryEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let rootURL: URL
    public var lastOpened: Date
    public var gitStatus: String
    public var packageStatus: String
    public var buildStatus: String
    public init(entry: ProjectRegistryEntry, gitStatus: String = "Unknown", packageStatus: String = "Unknown", buildStatus: String = "Unknown") {
        self.id = entry.id; self.name = entry.name; self.rootURL = entry.rootURL
        self.lastOpened = entry.lastOpenedAt; self.gitStatus = gitStatus
        self.packageStatus = packageStatus; self.buildStatus = buildStatus
    }
}

private func operationsDirectory() -> URL {
    if IDEProcess.isTestProcess {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-operations-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("SwiftCode/Operations", isDirectory: true)
}

private func loadJSON<T: Decodable>(_ name: String) -> [T] {
    let url = operationsDirectory().appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([T].self, from: data)) ?? []
}

private func saveJSON<T: Encodable>(_ value: [T], _ name: String) {
    let dir = operationsDirectory()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(value) else { return }
    try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
}

@Observable
@MainActor
public final class OperationsBuildHistory {
    public static let shared = OperationsBuildHistory()
    public private(set) var buildRecords: [OperationsBuildRecord] = []

    public init() { buildRecords = loadJSON("build_history.json") }

    public func recordBuild(projectName: String, duration: TimeInterval, warnings: Int, errors: Int, sdk: String, destination: String, configuration: String, status: String) {
        let record = OperationsBuildRecord(projectName: projectName, duration: duration, warnings: warnings, errors: errors, sdk: sdk, destination: destination, configuration: configuration, status: status)
        buildRecords.insert(record, at: 0)
        saveJSON(buildRecords, "build_history.json")
    }

    public func clearHistory() {
        buildRecords.removeAll()
        saveJSON(buildRecords, "build_history.json")
    }

    public var successRate: Double {
        guard !buildRecords.isEmpty else { return 0 }
        let ok = buildRecords.filter { $0.status == "Succeeded" }.count
        return Double(ok) / Double(buildRecords.count)
    }
}

@Observable
@MainActor
public final class OperationsArchiveStore {
    public static let shared = OperationsArchiveStore()
    public private(set) var archives: [OperationsArchive] = []

    public init() { archives = loadJSON("archives.json") }

    public func addArchive(_ archive: OperationsArchive) {
        archives.insert(archive, at: 0)
        saveJSON(archives, "archives.json")
    }

    public func removeArchive(id: UUID) {
        archives.removeAll { $0.id == id }
        saveJSON(archives, "archives.json")
    }
}

@Observable
@MainActor
public final class OperationsNotificationStore {
    public static let shared = OperationsNotificationStore()
    public private(set) var notifications: [OperationsNotification] = []

    public init() { notifications = loadJSON("notifications.json") }

    public func post(title: String, subtitle: String, type: String) {
        notifications.insert(OperationsNotification(title: title, subtitle: subtitle, type: type), at: 0)
        saveJSON(notifications, "notifications.json")
    }

    public func markRead(id: UUID) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[idx].isRead = true
        saveJSON(notifications, "notifications.json")
    }

    public var unreadCount: Int { notifications.filter { !$0.isRead }.count }
}

@Observable
@MainActor
public final class OperationsLog {
    public static let shared = OperationsLog()
    public private(set) var entries: [OperationsLogEntry] = []

    public init() { entries = loadJSON("operations_log.json") }

    public func append(_ message: String, level: OperationsLogEntry.Level = .info, panel: String = "Operations") {
        entries.insert(OperationsLogEntry(level: level, panel: panel, message: message), at: 0)
        entries = Array(entries.prefix(500))
        saveJSON(entries, "operations_log.json")
    }
}

@Observable
@MainActor
public final class OperationsQueue {
    public struct Operation: Identifiable, Sendable {
        public enum Status: String, Sendable { case queued, running, succeeded, failed }
        public let id: UUID
        public let name: String
        public var status: Status
        public var error: String?
    }

    public static let shared = OperationsQueue()
    public private(set) var operations: [Operation] = []
    public var activeTaskCount: Int { operations.filter { $0.status == .running || $0.status == .queued }.count }

    public func enqueue(_ name: String, work: @escaping @Sendable () async throws -> Void) {
        let id = UUID()
        operations.insert(Operation(id: id, name: name, status: .queued, error: nil), at: 0)
        Task {
            await MainActor.run { if let idx = operations.firstIndex(where: { $0.id == id }) { operations[idx].status = .running } }
            do {
                try await work()
                await MainActor.run { if let idx = operations.firstIndex(where: { $0.id == id }) { operations[idx].status = .succeeded } }
            } catch {
                await MainActor.run { if let idx = operations.firstIndex(where: { $0.id == id }) { operations[idx].status = .failed; operations[idx].error = error.localizedDescription } }
            }
        }
    }
}

public enum OperationsHealth {
    public struct Factor: Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let detail: String
        public let healthy: Bool
    }

    public static func freeDiskSpace(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return free
    }

    public static func directorySize(at url: URL, maxFiles: Int = 2000) -> Int64 {
        var total: Int64 = 0
        var seen = 0
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == ".git" { enumerator.skipDescendants(); continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
            seen += 1
            if seen >= maxFiles { break }
        }
        return total
    }

     @MainActor public static func factors(workspaceURL: URL?, buildHistory: OperationsBuildHistory, registryCount: Int) -> [Factor] {
        var factors: [Factor] = []
        if let url = workspaceURL, let free = freeDiskSpace(at: url) {
            factors.append(Factor(name: "Disk space", detail: "\(free / 1_073_741_824) GB free", healthy: free > 5_368_709_120))
        }
        if !buildHistory.buildRecords.isEmpty {
            let rate = Int(buildHistory.successRate * 100)
            factors.append(Factor(name: "Build success rate", detail: "\(rate)% over \(buildHistory.buildRecords.count) recorded builds", healthy: rate >= 80))
        } else {
            factors.append(Factor(name: "Build success rate", detail: "No builds recorded yet", healthy: true))
        }
        factors.append(Factor(name: "Project registry", detail: "\(registryCount) project(s) registered", healthy: registryCount > 0))
        return factors
    }
}

public struct OperationsSecretFinding: Sendable, Identifiable {
    public var id: String { "\(file):\(line)" }
    public let file: String
    public let line: Int
    public let pattern: String
}

public enum OperationsSecurity {
    public static func scan(root: URL, maxFiles: Int = 500) -> [OperationsSecretFinding] {
        let patterns = ["AKIA[0-9A-Z]{16}", "api[_-]?key\\s*=\\s*[\"'][^\"']{8,}", "secret\\s*=\\s*[\"'][^\"']{8,}"]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        var findings: [OperationsSecretFinding] = []
        var seen = 0
        let skipped: Set<String> = [".git", ".build", "DerivedData", "xcuserdata", "node_modules"]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        for case let fileURL as URL in enumerator {
            if skipped.contains(fileURL.lastPathComponent) { enumerator.skipDescendants(); continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory != true else { continue }
            guard ["swift", "m", "h", "plist", "json", "env", "txt", "md"].contains(fileURL.pathExtension) else { continue }
            seen += 1
            if seen > maxFiles { break }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (lineNumber, line) in text.components(separatedBy: .newlines).enumerated() {
                for regex in regexes {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        findings.append(OperationsSecretFinding(file: fileURL.lastPathComponent, line: lineNumber + 1, pattern: regex.pattern))
                        break
                    }
                }
            }
        }
        return findings
    }
}

@Observable
@MainActor
public final class OperationsCoordinator {
    public static let shared = OperationsCoordinator()

    public var selectedPanel: OperationsPanel = .dashboard
    public var selectedProjectID: UUID?
    public var searchQuery: String = ""
    public var showInspector: Bool = false
    public var isSidebarCollapsed: Bool = false
    public private(set) var registryEntries: [OperationsRegistryEntry] = []

    public let builds = OperationsBuildHistory.shared
    public let archives = OperationsArchiveStore.shared
    public let notifications = OperationsNotificationStore.shared
    public let log = OperationsLog.shared
    public let queue = OperationsQueue.shared

    private init() {}

    public func selectPanel(_ panel: OperationsPanel) {
        selectedPanel = panel
    }

    public func refreshRegistry() async {
        let stored = (try? await ProjectRegistryStore.shared.load()) ?? []
        var entries = stored.map { OperationsRegistryEntry(entry: $0) }
        for idx in entries.indices {
            let root = entries[idx].rootURL
            let hasGit = FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
            let hasPackage = FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
            entries[idx].gitStatus = hasGit ? "Repository present" : "No Repository"
            entries[idx].packageStatus = hasPackage ? "Up to date" : "No package config"
        }
        registryEntries = entries
    }
}
