import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "SystemIndex")

public struct SystemAssetDocument: Codable, Sendable, Identifiable {
    public var id: String { relativePath }
    public let relativePath: String
    public let title: String
    public let contentHash: String
    public let dependencies: [String]
    public let sections: [SystemAssetSection]
    public let indexedAt: Date
}

public struct SystemAssetSection: Codable, Sendable, Identifiable {
    public let id: String
    public let documentPath: String
    public let documentTitle: String
    public let heading: String
    public let level: Int
    public let text: String
    public let tokenEstimate: Int
    public let titleTerms: [String]
    public let headingTerms: [String]
    public let bodyTerms: [String]
    public let fileTerms: [String]
}

public enum SystemIndexRetrievalReason: String, Codable, Sendable {
    case baseline
    case titleMatch
    case filenameMatch
    case keywordMatch
    case dependency
}

public struct SystemIndexRetrieval: Sendable {
    public let sectionID: String
    public let documentPath: String
    public let documentTitle: String
    public let sectionHeading: String
    public let text: String
    public let score: Double
    public let reason: SystemIndexRetrievalReason
    public let contentHash: String
    public var tokenEstimate: Int { (text.count + 3) / 4 }
}

public struct InstructionQueryContext: Sendable {
    public enum TaskCategory: String, Sendable, CaseIterable {
        case general
        case coding
        case fileOperations
        case buildAndTest
        case authentication
        case toolUse
        case planning
        case streaming
        case errorRecovery
        case projectContext
    }

    public enum ExecutionStage: String, Sendable {
        case preparation
        case generation
        case toolCall
        case toolResult
        case errorRecovery
        case finalization
    }

    public var userText: String
    public var taskCategory: TaskCategory
    public var stage: ExecutionStage
    public var modelID: String
    public var maxTokens: Int
    public var excludingChunkIDs: Set<String>

    public init(
        userText: String,
        taskCategory: TaskCategory = .general,
        stage: ExecutionStage = .preparation,
        modelID: String = "",
        maxTokens: Int = 4000,
        excludingChunkIDs: Set<String> = []
    ) {
        self.userText = userText
        self.taskCategory = taskCategory
        self.stage = stage
        self.modelID = modelID
        self.maxTokens = maxTokens
        self.excludingChunkIDs = excludingChunkIDs
    }
}

public struct SystemIndexBudgetResult: Sendable {
    public let retrievals: [SystemIndexRetrieval]
    public let totalTokenEstimate: Int
    public let omittedSectionCount: Int
    public let safeguardsIncluded: Bool
    public let budgetExceeded: Bool
    public let notes: [String]

    public func formattedForPrompt() -> String {
        guard !retrievals.isEmpty else { return "" }
        var out = "# RETRIEVED ASSIST INSTRUCTIONS\n"
        out += "The following instruction sections were selected for this task from the local System Assets library. Follow them; they take precedence over conflicting informal guidance, but mandatory safeguards are never overridden.\n"
        for r in retrievals {
            out += "\n## [\(r.documentTitle) — \(r.sectionHeading)]\n\(r.text)\n"
        }
        return out
    }
}

public enum SystemIndexReadiness: Sendable, Equatable {
    case notStarted
    case indexing
    case ready(documents: Int, chunks: Int)
    case failed(String)
}

public struct SystemIndexDiagnostics: Codable, Sendable {
    public let authoritativeDirectory: String
    public let generation: Int
    public let documentCount: Int
    public let chunkCount: Int
    public let lastScanTime: Date?
    public let lastRefreshError: String?
    public let discoveredFiles: [String]
    public let isWatcherActive: Bool
    public let notes: [String]
}

public struct SystemIndexRequestLedger: Sendable {
    public private(set) var retrievedChunkIDs: Set<String> = []
    public private(set) var retrievalRounds: Int = 0

    public init() {}

    public mutating func record(_ result: SystemIndexBudgetResult) {
        for r in result.retrievals { retrievedChunkIDs.insert(r.sectionID) }
        retrievalRounds += 1
    }

    public mutating func reset() {
        retrievedChunkIDs.removeAll()
        retrievalRounds = 0
    }
}

public struct SystemIndexRankingWeights: Sendable {
    public var titleWeight: Double = 3.0
    public var headingWeight: Double = 2.0
    public var filenameWeight: Double = 2.5
    public var bodyWeight: Double = 1.0
    public var baselineBoost: Double = 1.5
    public var dependencyBoost: Double = 1.2

    public init() {}
    public init(titleWeight: Double, headingWeight: Double, filenameWeight: Double,
                bodyWeight: Double, baselineBoost: Double, dependencyBoost: Double) {
        self.titleWeight = titleWeight
        self.headingWeight = headingWeight
        self.filenameWeight = filenameWeight
        self.bodyWeight = bodyWeight
        self.baselineBoost = baselineBoost
        self.dependencyBoost = dependencyBoost
    }
}

final class SystemAssetsDirectoryMonitor: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let queue = DispatchQueue(label: "com.swiftcode.assist.systemassets.watcher", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        stop()
        let path = url.path
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.warning("SystemAssetsDirectoryMonitor: Unable to open file descriptor for path: \(path, privacy: .public)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleDebouncedNotification()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        src.resume()
        self.source = src
    }

    private func scheduleDebouncedNotification() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        stop()
    }
}

struct PersistedIndex: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let documents: [SystemAssetDocument]
}

struct PersistedManifest: Codable {
    let schemaVersion: Int
    let files: [String: String]
}

private struct RawSection { var level: Int; var heading: String; var lines: [String] }

public actor SystemIndexService {
    public static let shared = SystemIndexService()

    public static let schemaVersion = 2

    public static let baselineDocumentNames: Set<String> = ["Identity.md", "Safeguards.md"]

    public static let resourcesSubdirectory = "System Assets"

    public static let expectedDocumentNames: Set<String> = [
        "AgentSystemAsset.md", "Identity.md", "AvailableTools.md", "CallTool.md",
        "Safeguards.md", "Contexts.md", "SwiftUsage.md", "AgenticLoop.md",
        "ModelProviders.md", "Streaming.md", "ErrorHandling.md", "Authentication.md",
        "ExecutionPlans.md", "Skills.md", "ProjectContext.md", "ResponseFormatting.md",
        "ContextBudgeting.md", "FileOperations.md", "BuildAndTesting.md", "SystemIndex.md",
        "ToolRoutingPolicy.md", "UsingSystem.md", "TakeScreenshot.md", "TakeScreenrecord.md", "UseApp.md",
        "DocumentationWithGitHub.md", "LocalizingApps.md"
    ]

    public var rankingWeights = SystemIndexRankingWeights()

    public private(set) var generation: Int = 1

    private var documents: [String: SystemAssetDocument] = [:]
    private var currentManifest: [String: String] = [:]
    private var readiness: SystemIndexReadiness = .notStarted
    private var readyTask: Task<Void, Never>?
    private var lastNotes: [String] = []
    private var lastScanTime: Date?
    private var lastRefreshError: String?

    private var customAssetsDirectory: URL?
    private var directoryMonitor: SystemAssetsDirectoryMonitor?

    private init() {}

    public func setCustomAssetsDirectory(_ url: URL?) async {
        directoryMonitor?.stop()
        directoryMonitor = nil
        self.customAssetsDirectory = url
        self.readyTask = nil
        self.readiness = .notStarted
        self.documents.removeAll()
        self.currentManifest.removeAll()
        await ensureReady()
    }

    public nonisolated func authoritativeAssetsDirectory() -> URL {
        let fm = FileManager.default

        if let envPath = ProcessInfo.processInfo.environment["SWIFTCODE_SYSTEM_ASSETS_PATH"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true)
        }
        if let userPref = UserDefaults.standard.string(forKey: "com.swiftcode.assist.systemAssetsPath"), !userPref.isEmpty {
            return URL(fileURLWithPath: userPref, isDirectory: true)
        }

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("com.swiftcode.assist/SystemAssets", isDirectory: true)
        }

        return bundledAssetsURL() ?? URL(fileURLWithPath: "/tmp/SwiftCodeSystemAssets", isDirectory: true)
    }

    private func effectiveAssetsDirectory() -> URL {
        customAssetsDirectory ?? authoritativeAssetsDirectory()
    }

    public nonisolated func initializeRuntimeAssetsIfNeeded() {
        let fm = FileManager.default
        let runtimeDir = authoritativeAssetsDirectory()

        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: runtimeDir.path, isDirectory: &isDir) {
            try? fm.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        }

        if let seedSource = bundledAssetsURL(), seedSource.path != runtimeDir.path {
            if let enumerator = fm.enumerator(at: seedSource, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let srcURL as URL in enumerator {
                    guard srcURL.pathExtension.lowercased() == "md" else { continue }
                    let relative = srcURL.path.replacingOccurrences(of: seedSource.path + "/", with: "")
                    let destURL = runtimeDir.appendingPathComponent(relative)
                    if !fm.fileExists(atPath: destURL.path) {
                        try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? fm.copyItem(at: srcURL, to: destURL)
                    }
                }
            }
        }
    }

    public func ensureReady() async {
        if readiness == .notStarted {
            let task = Task { await self.buildOrLoadIndex() }
            readyTask = task
            await task.value
            startWatcherIfNeeded()
            return
        }

        if let task = readyTask {
            await task.value
            return
        }

        await checkFreshnessAndRefreshIfNeeded()
    }

    public func status() -> SystemIndexReadiness { readiness }
    public func documentCount() -> Int { documents.count }
    public func chunkCount() -> Int { documents.values.reduce(0) { $0 + $1.sections.count } }
    public func lastDiagnostics() -> [String] { lastNotes }

    public func diagnostics() -> SystemIndexDiagnostics {
        SystemIndexDiagnostics(
            authoritativeDirectory: effectiveAssetsDirectory().path,
            generation: generation,
            documentCount: documents.count,
            chunkCount: chunkCount(),
            lastScanTime: lastScanTime,
            lastRefreshError: lastRefreshError,
            discoveredFiles: documents.keys.sorted(),
            isWatcherActive: directoryMonitor != nil,
            notes: lastNotes
        )
    }

    public func invalidate() {
        readyTask = nil
        readiness = .notStarted
        documents.removeAll()
        currentManifest.removeAll()
    }

    public func refresh() async {
        await checkFreshnessAndRefreshIfNeeded()
    }

    public func rebuildIndex() async {
        await checkFreshnessAndRefreshIfNeeded()
    }

    private func startWatcherIfNeeded() {
        guard directoryMonitor == nil else { return }
        let dir = effectiveAssetsDirectory()
        let monitor = SystemAssetsDirectoryMonitor(url: dir) { [weak self] in
            guard let self else { return }
            Task {
                await self.checkFreshnessAndRefreshIfNeeded()
            }
        }
        monitor.start()
        self.directoryMonitor = monitor
    }

    public func checkFreshnessAndRefreshIfNeeded() async {
        let scanned = scanAssetsDirectory()
        var diskManifest: [String: String] = [:]
        for (relativePath, url) in scanned {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                diskManifest[relativePath] = Self.contentHash(of: text)
            }
        }

        if diskManifest != currentManifest || documents.count != scanned.count {
            logger.info("SystemIndex: Disk modifications detected. Updating active index snapshot...")
            await buildOrLoadIndex(scannedFiles: scanned, diskManifest: diskManifest)
        }
    }

    public nonisolated func bundledAssetsURL() -> URL? {
        let fm = FileManager.default

        if let resourceURL = Bundle.module.resourceURL {
            let url = resourceURL.appendingPathComponent(Self.resourcesSubdirectory, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent(Self.resourcesSubdirectory, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }

        let currentDir = fm.currentDirectoryPath
        var candidatePaths: [String] = [
            currentDir + "/SwiftCode/Backend/Assist/Functions/System Assets",
            currentDir + "/Backend/Assist/Functions/System Assets",
            currentDir + "/System Assets"
        ]

        var anchorURLs: [URL] = []
        if let execURL = Bundle.main.executableURL { anchorURLs.append(execURL) }
        anchorURLs.append(Bundle.main.bundleURL)

        for anchor in anchorURLs {
            var dir = anchor.deletingLastPathComponent()
            for _ in 0..<8 {
                candidatePaths.append(dir.appendingPathComponent("SwiftCode/Backend/Assist/Functions/System Assets").path)
                candidatePaths.append(dir.appendingPathComponent("Backend/Assist/Functions/System Assets").path)
                candidatePaths.append(dir.appendingPathComponent("System Assets").path)
                let parent = dir.deletingLastPathComponent()
                if parent == dir { break }
                dir = parent
            }
        }

        for path in candidatePaths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        return nil
    }

    public nonisolated func assetText(forRelativePath relativePath: String) -> String? {
        let runtimeDir = authoritativeAssetsDirectory()
        let runtimeURL = runtimeDir.appendingPathComponent(relativePath)
        if let content = try? String(contentsOf: runtimeURL, encoding: .utf8) {
            return content
        }
        if let base = bundledAssetsURL() {
            let bundleURL = base.appendingPathComponent(relativePath)
            if let content = try? String(contentsOf: bundleURL, encoding: .utf8) {
                return content
            }
        }
        return nil
    }

    public nonisolated func bundledText(forRelativePath relativePath: String) -> String? {
        assetText(forRelativePath: relativePath)
    }

    private func scanAssetsDirectory() -> [(relativePath: String, url: URL)] {
        let base = effectiveAssetsDirectory()
        initializeRuntimeAssetsIfNeeded()

        var found: [(String, URL)] = []
        let fm = FileManager.default

        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: base.path, isDirectory: &isDir) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }

        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            if let bundleBase = bundledAssetsURL(), bundleBase.path != base.path {
                if let bundleEnum = fm.enumerator(at: bundleBase, includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let url as URL in bundleEnum {
                        guard url.pathExtension.lowercased() == "md" else { continue }
                        let relative = url.path.replacingOccurrences(of: bundleBase.path + "/", with: "")
                        found.append((relative, url))
                    }
                }
            }
            return found.sorted { $0.0 < $1.0 }
        }

        let baseStandardPath = base.standardizedFileURL.path
        for case let url as URL in enumerator {
            let lastComponent = url.lastPathComponent
            if lastComponent.hasPrefix(".") || lastComponent.hasPrefix("~") ||
               lastComponent.hasSuffix(".tmp") || lastComponent.hasSuffix(".swp") {
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }

            let standardPath = url.standardizedFileURL.path
            guard standardPath.hasPrefix(baseStandardPath) else {
                logger.warning("SystemIndex: Skipped file outside authoritative root: \(url.path, privacy: .public)")
                continue
            }

            if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = resources.fileSize, size > 2_000_000 {
                logger.warning("SystemIndex: Skipped oversized file (>2MB): \(url.path, privacy: .public)")
                continue
            }

            let relative = standardPath.replacingOccurrences(of: baseStandardPath + "/", with: "")
            found.append((relative, url))
        }

        if found.isEmpty, let bundleBase = bundledAssetsURL(), bundleBase.path != base.path {
            if let bundleEnum = fm.enumerator(at: bundleBase, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let url as URL in bundleEnum {
                    guard url.pathExtension.lowercased() == "md" else { continue }
                    let relative = url.path.replacingOccurrences(of: bundleBase.path + "/", with: "")
                    found.append((relative, url))
                }
            }
        }

        return found.sorted { $0.0 < $1.0 }
    }

    private nonisolated func cacheDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("com.swiftcode.assist/SystemIndex", isDirectory: true)
    }

    private func loadPersisted() -> (index: PersistedIndex, manifest: PersistedManifest)? {
        guard customAssetsDirectory == nil, let dir = cacheDirectory() else { return nil }
        let indexURL = dir.appendingPathComponent("index.json")
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard
            let indexData = try? Data(contentsOf: indexURL),
            let manifestData = try? Data(contentsOf: manifestURL),
            let index = try? JSONDecoder().decode(PersistedIndex.self, from: indexData),
            let manifest = try? JSONDecoder().decode(PersistedManifest.self, from: manifestData),
            index.schemaVersion == Self.schemaVersion,
            manifest.schemaVersion == Self.schemaVersion
        else { return nil }
        return (index, manifest)
    }

    private func persist(documents: [SystemAssetDocument], manifest: [String: String]) {
        guard customAssetsDirectory == nil, let dir = cacheDirectory() else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let index = PersistedIndex(schemaVersion: Self.schemaVersion, createdAt: Date(), documents: documents)
            let persistedManifest = PersistedManifest(schemaVersion: Self.schemaVersion, files: manifest)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let indexTmp = dir.appendingPathComponent("index.json.tmp")
            let manifestTmp = dir.appendingPathComponent("manifest.json.tmp")
            try encoder.encode(index).write(to: indexTmp, options: .atomic)
            try encoder.encode(persistedManifest).write(to: manifestTmp, options: .atomic)
            let fm = FileManager.default
            _ = try fm.replaceItemAt(dir.appendingPathComponent("index.json"), withItemAt: indexTmp)
            _ = try fm.replaceItemAt(dir.appendingPathComponent("manifest.json"), withItemAt: manifestTmp)
        } catch {
            logger.error("SystemIndex: failed to persist index: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func buildOrLoadIndex(scannedFiles: [(relativePath: String, url: URL)]? = nil, diskManifest: [String: String]? = nil) async {
        readiness = .indexing
        var notes: [String] = []

        let scanned = scannedFiles ?? scanAssetsDirectory()
        if scanned.isEmpty {
            let msg = "SystemIndex: no Markdown assets found in '\(effectiveAssetsDirectory().path)'."
            logger.error("\(msg, privacy: .public)")
            readiness = .failed(msg)
            lastNotes = [msg]
            lastRefreshError = msg
            return
        }

        var newManifest: [String: String] = [:]
        var contentsByPath: [String: String] = [:]
        for (relativePath, url) in scanned {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                notes.append("Unreadable asset skipped: \(relativePath)")
                continue
            }
            contentsByPath[relativePath] = text
            newManifest[relativePath] = diskManifest?[relativePath] ?? Self.contentHash(of: text)
        }

        if customAssetsDirectory == nil, let persisted = loadPersisted(), persisted.manifest.files == newManifest {
            var docs: [String: SystemAssetDocument] = [:]
            for doc in persisted.index.documents { docs[doc.relativePath] = doc }
            for path in docs.keys where newManifest[path] == nil { docs.removeValue(forKey: path) }
            documents = docs
            currentManifest = newManifest
            lastScanTime = Date()
            lastRefreshError = nil
            readiness = .ready(documents: docs.count, chunks: chunkCount())
            notes.append("Loaded persisted index (\(docs.count) documents, \(chunkCount()) chunks); assets unchanged.")
            lastNotes = notes
            logger.info("SystemIndex ready from cache: \(docs.count) documents.")
            return
        }

        var docs: [String: SystemAssetDocument] = [:]
        var reused = 0, reparsed = 0
        var existingDocs = self.documents
        if existingDocs.isEmpty, let persisted = loadPersisted() {
            for doc in persisted.index.documents { existingDocs[doc.relativePath] = doc }
        }

        for (relativePath, text) in contentsByPath {
            let hash = newManifest[relativePath] ?? ""
            if let old = existingDocs[relativePath], old.contentHash == hash {
                docs[relativePath] = old
                reused += 1
            } else {
                docs[relativePath] = Self.parseDocument(relativePath: relativePath, text: text)
                reparsed += 1
            }
        }

        self.documents = docs
        self.currentManifest = newManifest
        self.generation += 1
        self.lastScanTime = Date()
        self.lastRefreshError = nil

        persist(documents: Array(docs.values), manifest: newManifest)

        let missing = Self.expectedDocumentNames.subtracting(Set(contentsByPath.keys.map { ($0 as NSString).lastPathComponent }))
        if !missing.isEmpty {
            notes.append("Expected assets missing from runtime directory: \(missing.sorted().joined(separator: ", "))")
        }
        notes.append("Index updated (gen \(generation)): \(docs.count) documents, \(chunkCount()) chunks (\(reused) reused, \(reparsed) reparsed).")
        readiness = .ready(documents: docs.count, chunks: chunkCount())
        lastNotes = notes
        logger.info("SystemIndex ready: \(docs.count) documents, \(self.chunkCount()) chunks (generation: \(self.generation)).")
    }

    public func retrieve(for query: InstructionQueryContext) async -> SystemIndexBudgetResult {
        await ensureReady()
        var notes: [String] = []

        guard !documents.isEmpty else {
            let msg: String
            switch readiness {
            case .failed(let reason): msg = "SystemIndex unavailable (\(reason))."
            case .indexing: msg = "SystemIndex still indexing; no instructions retrieved."
            default: msg = "SystemIndex has no indexed documents."
            }
            logger.error("\(msg, privacy: .public)")
            notes.append(msg)
            let fallback = fallbackBaselineSections()
            return SystemIndexBudgetResult(
                retrievals: fallback, totalTokenEstimate: fallback.reduce(0) { $0 + $1.tokenEstimate },
                omittedSectionCount: 0, safeguardsIncluded: !fallback.isEmpty,
                budgetExceeded: false, notes: notes
            )
        }

        let queryTerms = Self.queryTerms(for: query)
        let baselinePaths = Set(documents.keys.filter { Self.baselineDocumentNames.contains(($0 as NSString).lastPathComponent) })

        struct Scored { let section: SystemAssetSection; let score: Double; let reason: SystemIndexRetrievalReason }
        var scored: [Scored] = []
        for doc in documents.values {
            let isBaseline = baselinePaths.contains(doc.relativePath)
            for section in doc.sections {
                if query.excludingChunkIDs.contains(section.id) { continue }
                let (score, reason) = Self.score(
                    section: section, queryTerms: queryTerms,
                    isBaseline: isBaseline, weights: rankingWeights
                )
                if score > 0 || isBaseline {
                    scored.append(Scored(section: section, score: isBaseline ? score + rankingWeights.baselineBoost : score,
                                        reason: isBaseline && score == 0 ? .baseline : reason))
                }
            }
        }
        scored.sort { $0.score > $1.score }

        var selected: [Scored] = []
        var visitedDocs: Set<String> = []
        var seenSections = Set<String>()
        func take(_ s: Scored, reason: SystemIndexRetrievalReason, boost: Double) {
            guard !seenSections.contains(s.section.id) else { return }
            seenSections.insert(s.section.id)
            visitedDocs.insert(s.section.documentPath)
            selected.append(Scored(section: s.section, score: s.score + boost, reason: reason))
        }
        for s in scored {
            take(s, reason: s.reason, boost: 0)
            if let doc = documents[s.section.documentPath] {
                for depName in doc.dependencies {
                    let depPath = Self.resolveDependency(depName, in: documents)
                    guard let depPath, !visitedDocs.contains(depPath),
                          let depDoc = documents[depPath] else { continue }
                    visitedDocs.insert(depPath)
                    if let best = depDoc.sections
                        .filter({ !query.excludingChunkIDs.contains($0.id) && !seenSections.contains($0.id) })
                        .max(by: { Self.score(section: $0, queryTerms: queryTerms, isBaseline: false, weights: rankingWeights).0
                                   < Self.score(section: $1, queryTerms: queryTerms, isBaseline: false, weights: rankingWeights).0 }) {
                        let (depScore, _) = Self.score(section: best, queryTerms: queryTerms, isBaseline: false, weights: rankingWeights)
                        take(Scored(section: best, score: depScore, reason: .dependency),
                             reason: .dependency, boost: rankingWeights.dependencyBoost)
                    }
                }
            }
            if selected.count >= 40 { break }
        }

        selected.sort {
            let aBase = baselinePaths.contains($0.section.documentPath)
            let bBase = baselinePaths.contains($1.section.documentPath)
            if aBase != bBase { return aBase }
            return $0.score > $1.score
        }

        var budgeted: [SystemIndexRetrieval] = []
        var usedTokens = 0
        var omitted = 0
        var safeguardsIncluded = false
        var exceeded = false
        for s in selected {
            let tokens = (s.section.text.count + 3) / 4
            let isSafeguard = isSafeguardDocument(s.section)
            if usedTokens + tokens > query.maxTokens {
                if isSafeguard {
                    exceeded = true
                } else {
                    omitted += 1
                    continue
                }
            }
            usedTokens += tokens
            if isSafeguard { safeguardsIncluded = true }
            budgeted.append(SystemIndexRetrieval(
                sectionID: s.section.id, documentPath: s.section.documentPath,
                documentTitle: s.section.documentTitle, sectionHeading: s.section.heading,
                text: s.section.text, score: s.score, reason: s.reason,
                contentHash: documents[s.section.documentPath]?.contentHash ?? ""
            ))
        }
        if exceeded {
            notes.append("Context budget (\(query.maxTokens) tokens) exceeded by mandatory safeguard sections; safeguards were preserved and lower-priority content omitted.")
        }
        if omitted > 0 {
            notes.append("\(omitted) lower-relevance section(s) omitted by context budget.")
        }

        return SystemIndexBudgetResult(
            retrievals: budgeted, totalTokenEstimate: usedTokens,
            omittedSectionCount: omitted, safeguardsIncluded: safeguardsIncluded,
            budgetExceeded: exceeded, notes: notes + lastNotes
        )
    }

    public nonisolated func baselinePrompt() -> String {
        var parts: [String] = []
        for name in ["AgentSystemAsset.md", "Identity.md", "Safeguards.md", "TaskCompletion.md", "ToolRoutingPolicy.md"] {
            if let text = assetText(forRelativePath: name), !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    private func fallbackBaselineSections() -> [SystemIndexRetrieval] {
        var out: [SystemIndexRetrieval] = []
        for name in ["Identity.md", "Safeguards.md", "AgentSystemAsset.md", "TaskCompletion.md", "ToolRoutingPolicy.md"] {
            guard let text = Self.shared.assetText(forRelativePath: name), !text.isEmpty else { continue }
            out.append(SystemIndexRetrieval(
                sectionID: "bundle-fallback#\(name)", documentPath: name,
                documentTitle: name, sectionHeading: "Full document (index unavailable)",
                text: text, score: 0, reason: .baseline, contentHash: ""
            ))
        }
        return out
    }

    private func isSafeguardDocument(_ section: SystemAssetSection) -> Bool {
        let name = (section.documentPath as NSString).lastPathComponent
        return name == "Safeguards.md"
    }

    private static func resolveDependency(_ name: String, in documents: [String: SystemAssetDocument]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if documents[trimmed] != nil { return trimmed }
        let fileName = (trimmed as NSString).lastPathComponent
        return documents.keys.first { ($0 as NSString).lastPathComponent == fileName }
    }

    private static let headingPattern = #"^(#{1,6})[ \t]+(.+?)[ \t]*$"#
    private static let dependsPattern = #"<!--\s*system-index-depends\s*:\s*([^>]+?)\s*-->"#

    static func contentHash(of text: String) -> String {
        SHA256.hash(Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    public static func parseDocument(relativePath: String, text: String) -> SystemAssetDocument {
        let fileName = (relativePath as NSString).lastPathComponent
        var title = (fileName as NSString).deletingPathExtension
        var dependencies: [String] = []

        if let range = text.range(of: dependsPattern, options: .regularExpression) {
            let comment = String(text[range])
            let inner = comment
                .replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .replacingOccurrences(of: "system-index-depends", with: "")
                .replacingOccurrences(of: ":", with: "")
            dependencies = inner.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }

        var rawSections: [RawSection] = []
        var current = RawSection(level: 0, heading: "", lines: [])
        var sawContent = false
        let headingRegex = try? NSRegularExpression(pattern: headingPattern)
        for line in text.components(separatedBy: "\n") {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if let m = headingRegex?.firstMatch(in: line, range: fullRange), m.numberOfRanges == 3 {
                if sawContent || !current.lines.isEmpty {
                    rawSections.append(current)
                }
                let hashes = nsLine.substring(with: m.range(at: 1))
                let headingText = nsLine.substring(with: m.range(at: 2))
                if title == (fileName as NSString).deletingPathExtension, hashes.count == 1, !headingText.isEmpty {
                    title = headingText
                }
                current = RawSection(level: hashes.count, heading: headingText, lines: [])
                sawContent = false
            } else {
                current.lines.append(line)
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sawContent = true }
            }
        }
        if sawContent || !current.lines.isEmpty { rawSections.append(current) }
        if rawSections.isEmpty {
            rawSections.append(RawSection(level: 0, heading: title, lines: text.components(separatedBy: "\n")))
        }

        let maxChunkChars = 3000
        var sections: [SystemAssetSection] = []
        for raw in rawSections {
            let headingLine = raw.level > 0 ? String(repeating: "#", count: raw.level) + " " + raw.heading + "\n\n" : ""
            let body = raw.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let fullText = (headingLine + body).trimmingCharacters(in: .whitespacesAndNewlines)
            if fullText.isEmpty { continue }
            let chunks = chunkText(fullText, maxChars: maxChunkChars)
            for (idx, chunk) in chunks.enumerated() {
                let slug = slugify(raw.heading.isEmpty ? title : raw.heading)
                let id = "\(relativePath)#\(slug)-\(idx)"
                let titleTerms = normalizeTerms(title)
                let headingTerms = normalizeTerms(raw.heading)
                let bodyTerms = normalizeTerms(String(chunk.prefix(2000)))
                let fileTerms = normalizeTerms((fileName as NSString).deletingPathExtension)
                sections.append(SystemAssetSection(
                    id: id, documentPath: relativePath, documentTitle: title,
                    heading: raw.heading.isEmpty ? title : raw.heading,
                    level: raw.level, text: chunk,
                    tokenEstimate: (chunk.count + 3) / 4,
                    titleTerms: Array(titleTerms.prefix(40)),
                    headingTerms: Array(headingTerms.prefix(60)),
                    bodyTerms: Array(bodyTerms.prefix(400)),
                    fileTerms: Array(fileTerms.prefix(20))
                ))
            }
        }

        return SystemAssetDocument(
            relativePath: relativePath, title: title,
            contentHash: contentHash(of: text), dependencies: dependencies,
            sections: sections, indexedAt: Date()
        )
    }

    public static func chunkText(_ text: String, maxChars: Int) -> [String] {
        guard text.count > maxChars else { return [text] }
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current: [String] = []
        var currentLen = 0
        for para in paragraphs {
            if currentLen + para.count + 2 > maxChars, !current.isEmpty {
                chunks.append(current.joined(separator: "\n\n"))
                let overlap = current.suffix(1)
                current = Array(overlap)
                currentLen = overlap.joined().count
            }
            current.append(para)
            currentLen += para.count + 2
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n\n")) }
        return chunks.isEmpty ? [text] : chunks
    }

    public static func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        let allowed = CharacterSet.alphanumerics
        var out = ""
        var lastDash = false
        for scalar in lower.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "have", "will",
        "your", "you", "are", "was", "were", "been", "being", "has", "had",
        "not", "but", "they", "their", "them", "then", "than", "when", "where",
        "which", "while", "about", "into", "through", "during", "each", "other",
        "such", "only", "also", "just", "like", "over", "more", "most", "some",
        "any", "all", "can", "should", "must", "may", "its", "our", "out"
    ]

    public static func normalizeTerms(_ text: String) -> [String] {
        let lower = text.lowercased()
        let parts = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            guard p.count > 2, !stopwords.contains(p), !seen.contains(p) else { continue }
            seen.insert(p)
            out.append(p)
        }
        return out
    }

    public static func categoryKeywords(for category: InstructionQueryContext.TaskCategory) -> [String] {
        switch category {
        case .general: return []
        case .coding:
            return ["swift", "swiftui", "code", "function", "class", "struct", "xcode", "refactor", "debug", "bug", "compile", "method", "view"]
        case .fileOperations:
            return ["file", "write", "create", "delete", "move", "rename", "edit", "patch", "directory", "folder", "path"]
        case .buildAndTest:
            return ["build", "test", "xcodebuild", "scheme", "target", "archive", "compile", "run"]
        case .authentication:
            return ["auth", "oauth", "signin", "login", "token", "credential", "apikey", "secret", "session"]
        case .toolUse:
            return ["tool", "execute", "terminal", "command", "shell", "call", "screenshot", "screenrecord", "capture", "window", "display", "navigate", "interact", "click", "app"]
        case .planning:
            return ["plan", "steps", "task", "execute", "workflow"]
        case .streaming:
            return ["stream", "progress", "partial", "delta", "chunk"]
        case .errorRecovery:
            return ["error", "fail", "retry", "fix", "crash", "recover", "timeout"]
        case .projectContext:
            return ["project", "repository", "swiftcode", "workspace", "convention"]
        }
    }

    public static func classifyCategory(for text: String) -> InstructionQueryContext.TaskCategory {
        let terms = Set(normalizeTerms(text))
        var best: InstructionQueryContext.TaskCategory = .general
        var bestScore = 0
        for category in InstructionQueryContext.TaskCategory.allCases where category != .general {
            let keywords = categoryKeywords(for: category)
            let score = keywords.filter { terms.contains($0) }.count
            if score > bestScore { bestScore = score; best = category }
        }
        return best
    }

    public static func queryTerms(for query: InstructionQueryContext) -> [String] {
        var terms = normalizeTerms(query.userText)
        terms.append(contentsOf: categoryKeywords(for: query.taskCategory))
        switch query.stage {
        case .toolCall, .toolResult:
            terms.append(contentsOf: ["tool", "execute", "safeguard", "argument", "result", "capability", "permission"])
        case .errorRecovery:
            terms.append(contentsOf: ["error", "retry", "recover", "fallback"])
        case .preparation:
            terms.append(contentsOf: ["instruction", "context", "session", "capability"])
        default:
            break
        }
        return Array(Set(terms))
    }

    public static func score(
        section: SystemAssetSection,
        queryTerms: [String],
        isBaseline: Bool,
        weights: SystemIndexRankingWeights
    ) -> (Double, SystemIndexRetrievalReason) {
        let titleSet = Set(section.titleTerms)
        let headingSet = Set(section.headingTerms)
        let bodySet = Set(section.bodyTerms)
        let fileSet = Set(section.fileTerms)
        var titleHits = 0, headingHits = 0, bodyHits = 0, fileHits = 0
        for term in queryTerms {
            if titleSet.contains(term) { titleHits += 1 }
            if headingSet.contains(term) { headingHits += 1 }
            if bodySet.contains(term) { bodyHits += 1 }
            if fileSet.contains(term) { fileHits += 1 }
        }
        let bodyNorm = 1.0 + Double(section.bodyTerms.count) / 200.0
        let score = weights.titleWeight * Double(titleHits)
            + weights.headingWeight * Double(headingHits)
            + weights.filenameWeight * Double(fileHits)
            + weights.bodyWeight * (Double(bodyHits) / bodyNorm)
        let reason: SystemIndexRetrievalReason
        if titleHits > 0 { reason = .titleMatch }
        else if fileHits > 0 { reason = .filenameMatch }
        else { reason = .keywordMatch }
        return (score, reason)
    }
}
