//
//  SkillDiscoveryService.swift
//  SwiftCode
//
//  Discovers external skills across Codex, Claude, VS Code, Antigravity, and other ecosystems,
//  and safely imports them into SwiftCode's authoritative persistent Skills directory.
//

import Foundation
import os
import CryptoKit

private let logger = Logger(subsystem: "com.swiftcode.Skills", category: "SkillDiscovery")

public struct DiscoveredSkillCandidate: Sendable {
    public let name: String
    public let sourceKind: SkillSourceKind
    public let sourceDescription: String
    public let rootDirectoryURL: URL
    public let skillFileURL: URL
}

@MainActor
public final class SkillDiscoveryService: ObservableObject {
    public static let shared = SkillDiscoveryService()

    @Published public private(set) var isDiscovering: Bool = false
    @Published public private(set) var lastDiscoveryDate: Date? = nil
    @Published public private(set) var importedSkillsCount: Int = 0
    @Published public private(set) var discoveryLogs: [String] = []

    private let fileManager = FileManager.default

    private init() {
        Task {
            // Run background discovery shortly after launch without blocking startup
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self.discoverAndImportAll()
        }
    }

    private func log(_ msg: String) {
        logger.info("\(msg, privacy: .public)")
        discoveryLogs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(msg)")
        if discoveryLogs.count > 100 {
            discoveryLogs.removeFirst(discoveryLogs.count - 100)
        }
    }

    // MARK: - Orchestrated Discovery & Import Pipeline

    public func discoverAndImportAll() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer {
            isDiscovering = false
            lastDiscoveryDate = Date()
        }

        log("Starting global skill discovery across local environments...")

        let activeProjectURL = ProjectSessionStore.shared.activeProject?.directoryURL

        let candidates = await Task.detached(priority: .utility) { () -> [DiscoveredSkillCandidate] in
            var list: [DiscoveredSkillCandidate] = []
            let service = SkillDiscoveryScanner(projectURL: activeProjectURL)
            list.append(contentsOf: service.discoverKnownProviders())
            list.append(contentsOf: service.discoverUserSkills())
            list.append(contentsOf: service.discoverConfiguredLocations())
            list.append(contentsOf: service.discoverAdditionalCompatibleLocations())
            return list
        }.value

        log("Discovered \(candidates.count) external skill candidate(s). Proceeding to safe import...")

        let imported = await importDiscoveredSkills(candidates)
        self.importedSkillsCount = imported
        log("Import completed. \(imported) skills verified in authoritative SwiftCode library.")

        await SkillIndex.shared.rebuildIndex()
    }

    // MARK: - Safe Import into SwiftCode Application Support

    public func importDiscoveredSkills(_ candidates: [DiscoveredSkillCandidate]) async -> Int {
        let destinationBaseDir = SkillIndex.shared.authoritativeSkillsDirectory
        let fm = fileManager

        var totalImported = 0

        for candidate in candidates {
            do {
                let success = try importSingleSkill(candidate: candidate, destinationBaseDir: destinationBaseDir, fileManager: fm)
                if success {
                    totalImported += 1
                }
            } catch {
                log("Failed to import skill '\(candidate.name)' from \(candidate.sourceDescription): \(error.localizedDescription)")
            }
        }

        return totalImported
    }

    private func importSingleSkill(
        candidate: DiscoveredSkillCandidate,
        destinationBaseDir: URL,
        fileManager: FileManager
    ) throws -> Bool {
        // Sanitize skill name to prevent directory traversal or malformed folder names
        let sanitizedName = candidate.name
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedName.isEmpty else { return false }

        // Security: Guarantee the destination path is canonically contained within destinationBaseDir
        let targetDirectoryURL = destinationBaseDir.appendingPathComponent(sanitizedName, isDirectory: true).standardized
        let canonicalBase = destinationBaseDir.standardized.path

        guard targetDirectoryURL.path.hasPrefix(canonicalBase) else {
            logger.error("Security violation: Target skill directory escapes Application Support: \(targetDirectoryURL.path)")
            return false
        }

        // Check if destination skill directory already exists
        if fileManager.fileExists(atPath: targetDirectoryURL.path) {
            // Deduplication Check: Read existing and candidate SKILL.md
            let existingSkillFile = targetDirectoryURL.appendingPathComponent("SKILL.md")
            if fileManager.fileExists(atPath: existingSkillFile.path),
               let existingData = try? Data(contentsOf: existingSkillFile),
               let candidateData = try? Data(contentsOf: candidate.skillFileURL) {

                let existingHash = SHA256.hash(data: existingData)
                let candidateHash = SHA256.hash(data: candidateData)

                if existingHash == candidateHash {
                    // Identical content; skip redundant write
                    return true
                } else {
                    // Content differs: Conflict handling. Suffix with source provider
                    let conflictName = "\(sanitizedName)-\(candidate.sourceKind.rawValue.lowercased())"
                    let conflictDirectoryURL = destinationBaseDir.appendingPathComponent(conflictName, isDirectory: true).standardized
                    if !fileManager.fileExists(atPath: conflictDirectoryURL.path) {
                        try copyDirectorySafely(from: candidate.rootDirectoryURL, to: conflictDirectoryURL, sourceCandidate: candidate)
                        return true
                    }
                    return true
                }
            }
        }

        // Fresh import
        try copyDirectorySafely(from: candidate.rootDirectoryURL, to: targetDirectoryURL, sourceCandidate: candidate)
        return true
    }

    /// Recursively copies directory or single file while protecting against symlink escapes
    private func copyDirectorySafely(from sourceURL: URL, to destURL: URL, sourceCandidate: DiscoveredSkillCandidate) throws {
        let fm = fileManager
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue {
            let enumerator = fm.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceVals = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                // Never copy unresolved external symlinks
                if resourceVals?.isSymbolicLink == true {
                    continue
                }

                let subPath = fileURL.path.replacingOccurrences(of: sourceURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !subPath.isEmpty, !subPath.contains("..") else { continue }

                let targetItemURL = destURL.appendingPathComponent(subPath)

                if resourceVals?.isDirectory == true {
                    try fm.createDirectory(at: targetItemURL, withIntermediateDirectories: true)
                } else if resourceVals?.isRegularFile == true {
                    try fm.createDirectory(at: targetItemURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: targetItemURL.path) {
                        try fm.removeItem(at: targetItemURL)
                    }
                    try fm.copyItem(at: fileURL, to: targetItemURL)
                }
            }
        } else {
            // Source is a standalone file (e.g. foo.SKILL.md)
            let destFile = destURL.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: destFile.path) {
                try fm.removeItem(at: destFile)
            }
            try fm.copyItem(at: sourceCandidate.skillFileURL, to: destFile)
        }

        // Write metadata sidecar tracking original origin
        let metadataSidecar = destURL.appendingPathComponent("metadata.json")
        let metadata: [String: Any] = [
            "name": sourceCandidate.name,
            "source": sourceCandidate.sourceKind.rawValue,
            "sourceDescription": sourceCandidate.sourceDescription,
            "originalPath": sourceCandidate.rootDirectoryURL.path,
            "importedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) {
            try? data.write(to: metadataSidecar)
        }
    }
}

// MARK: - Filesystem Scanner for Multi-Ecosystem Discovery

private struct SkillDiscoveryScanner: Sendable {
    private var fileManager: FileManager { FileManager.default }
    private let projectURL: URL?

    init(projectURL: URL? = nil) {
        self.projectURL = projectURL
    }

    private var homeURL: URL {
        fileManager.homeDirectoryForCurrentUser
    }

    public func discoverKnownProviders() -> [DiscoveredSkillCandidate] {
        var results: [DiscoveredSkillCandidate] = []

        // 1. Claude Skills
        let claudeLocations = [
            homeURL.appendingPathComponent(".claude/skills"),
            homeURL.appendingPathComponent("Library/Application Support/Claude/skills")
        ]
        for url in claudeLocations {
            results.append(contentsOf: scanDirectory(url, sourceKind: .claude, sourceName: "Claude Skills"))
        }

        // 2. Codex Skills
        let codexLocations = [
            homeURL.appendingPathComponent(".codex/skills"),
            homeURL.appendingPathComponent(".codex/extensions")
        ]
        for url in codexLocations {
            results.append(contentsOf: scanDirectory(url, sourceKind: .codex, sourceName: "Codex Skills"))
        }

        // 3. VS Code & Cursor Skills
        let vscodeLocations = [
            homeURL.appendingPathComponent(".vscode/skills"),
            homeURL.appendingPathComponent("Library/Application Support/Code/User/skills"),
            homeURL.appendingPathComponent("Library/Application Support/Cursor/User/skills"),
            homeURL.appendingPathComponent(".cursor/skills")
        ]
        for url in vscodeLocations {
            results.append(contentsOf: scanDirectory(url, sourceKind: .vscode, sourceName: "VS Code / Cursor Skills"))
        }

        // 4. Antigravity / Gemini Skills
        let antigravityLocations = [
            homeURL.appendingPathComponent(".gemini/config/skills"),
            homeURL.appendingPathComponent(".gemini/antigravity-ide/builtin/skills"),
            homeURL.appendingPathComponent(".gemini/skills")
        ]
        for url in antigravityLocations {
            results.append(contentsOf: scanDirectory(url, sourceKind: .antigravity, sourceName: "Antigravity SDK Skills"))
        }

        // 5. OpenCode / Agent Ecosystems
        let agentLocations = [
            homeURL.appendingPathComponent(".agents/skills"),
            homeURL.appendingPathComponent(".config/skills")
        ]
        for url in agentLocations {
            results.append(contentsOf: scanDirectory(url, sourceKind: .other, sourceName: "Agent Ecosystem Skills"))
        }

        return results
    }

    public func discoverUserSkills() -> [DiscoveredSkillCandidate] {
        let userSkillsURL = homeURL.appendingPathComponent(".skills")
        return scanDirectory(userSkillsURL, sourceKind: .user, sourceName: "User Home Skills (~/.skills)")
    }

    public func discoverConfiguredLocations() -> [DiscoveredSkillCandidate] {
        // Any custom paths configured in UserDefaults
        var results: [DiscoveredSkillCandidate] = []
        if let customPaths = UserDefaults.standard.stringArray(forKey: "com.swiftcode.custom_skills_paths") {
            for path in customPaths {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                results.append(contentsOf: scanDirectory(url, sourceKind: .other, sourceName: "Configured Location"))
            }
        }
        return results
    }

    public func discoverAdditionalCompatibleLocations() -> [DiscoveredSkillCandidate] {
        // Active workspace project skills
        var results: [DiscoveredSkillCandidate] = []
        if let projectURL = self.projectURL {
            let candidates = [
                projectURL.appendingPathComponent(".agents/skills"),
                projectURL.appendingPathComponent(".skills"),
                projectURL.appendingPathComponent("skills")
            ]
            for c in candidates {
                results.append(contentsOf: scanDirectory(c, sourceKind: .project, sourceName: "Workspace Project Skills"))
            }
        }
        return results
    }

    private func scanDirectory(_ directoryURL: URL, sourceKind: SkillSourceKind, sourceName: String) -> [DiscoveredSkillCandidate] {
        var candidates: [DiscoveredSkillCandidate] = []
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        guard let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        for item in contents {
            var itemIsDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &itemIsDir), itemIsDir.boolValue {
                // Check if this subfolder contains a SKILL.md or SKILLS.md
                let skillFile1 = item.appendingPathComponent("SKILL.md")
                let skillFile2 = item.appendingPathComponent("SKILLS.md")
                let skillFile3 = item.appendingPathComponent("skill.md")

                if fileManager.fileExists(atPath: skillFile1.path) {
                    candidates.append(DiscoveredSkillCandidate(name: item.lastPathComponent, sourceKind: sourceKind, sourceDescription: sourceName, rootDirectoryURL: item, skillFileURL: skillFile1))
                } else if fileManager.fileExists(atPath: skillFile2.path) {
                    candidates.append(DiscoveredSkillCandidate(name: item.lastPathComponent, sourceKind: sourceKind, sourceDescription: sourceName, rootDirectoryURL: item, skillFileURL: skillFile2))
                } else if fileManager.fileExists(atPath: skillFile3.path) {
                    candidates.append(DiscoveredSkillCandidate(name: item.lastPathComponent, sourceKind: sourceKind, sourceDescription: sourceName, rootDirectoryURL: item, skillFileURL: skillFile3))
                }
            } else if item.lastPathComponent.hasSuffix(".SKILL.md") || item.lastPathComponent.hasSuffix(".SKILLS.md") {
                let name = item.lastPathComponent.replacingOccurrences(of: ".SKILL.md", with: "").replacingOccurrences(of: ".SKILLS.md", with: "")
                candidates.append(DiscoveredSkillCandidate(name: name, sourceKind: sourceKind, sourceDescription: sourceName, rootDirectoryURL: item, skillFileURL: item))
            }
        }

        return candidates
    }
}
