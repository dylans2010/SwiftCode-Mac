import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistMemoryStore")

// MARK: - Memory Entry Model

public struct UserMemoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var category: String
    public var content: String
    public var timestamp: Date

    public init(id: UUID = UUID(), category: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.category = category
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Assist Memory Store

@Observable
@MainActor
public final class AssistMemoryStore {
    public static let shared = AssistMemoryStore()

    public static let userDefaultsKey = "assist_memory_enabled"

    public static let defaultTemplate = """
    # User Memory

    Personal preferences, project context, workflow patterns, and persistent facts recorded by Assist.

    ## User Preferences & Profile
    - Preferred Language: Swift
    - Coding Style: Clean, modern Swift with structured concurrency

    ## Project Context
    - Active Workspace: SwiftCode

    ## Learned Patterns & Directives
    - Follow strict architectural boundaries and avoid speculative edits.
    """

    private let fileLock = NSLock()

    public var isMemoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.userDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.userDefaultsKey)
        }
    }

    public private(set) var rawContent: String = ""
    public private(set) var entries: [UserMemoryEntry] = []

    public var memoryFileURL: URL {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let swiftCodeDir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)

        if !fileManager.fileExists(atPath: swiftCodeDir.path) {
            try? fileManager.createDirectory(at: swiftCodeDir, withIntermediateDirectories: true)
        }
        return swiftCodeDir.appendingPathComponent("UserMemory.md")
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            Self.userDefaultsKey: true
        ])
        reload()
    }

    // MARK: - Disk Synchronization

    public func reload() {
        let fileManager = FileManager.default
        let url = memoryFileURL

        if !fileManager.fileExists(atPath: url.path) {
            do {
                try Self.defaultTemplate.write(to: url, atomically: true, encoding: .utf8)
                self.rawContent = Self.defaultTemplate
            } catch {
                logger.error("Failed to initialize UserMemory.md: \(error.localizedDescription)")
                self.rawContent = Self.defaultTemplate
            }
        } else {
            do {
                self.rawContent = try String(contentsOf: url, encoding: .utf8)
            } catch {
                logger.error("Failed to read UserMemory.md: \(error.localizedDescription)")
                self.rawContent = Self.defaultTemplate
            }
        }

        self.entries = parseEntries(from: rawContent)
    }

    @discardableResult
    public func saveRawContent(_ content: String) -> Bool {
        fileLock.lock()
        defer { fileLock.unlock() }

        do {
            try content.write(to: memoryFileURL, atomically: true, encoding: .utf8)
            self.rawContent = content
            self.entries = parseEntries(from: content)
            logger.info("Successfully wrote \(content.count) characters to UserMemory.md")
            return true
        } catch {
            logger.error("Failed to write UserMemory.md: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Memory Retrieval

    public func retrieve(query: String? = nil) -> String {
        guard isMemoryEnabled else {
            return "User has Memory module OFF."
        }

        reload()

        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return rawContent
        }

        let lowerQuery = query.lowercased()
        let matchingEntries = entries.filter {
            $0.content.lowercased().contains(lowerQuery) ||
            $0.category.lowercased().contains(lowerQuery)
        }

        if matchingEntries.isEmpty {
            return "No memory entries matched query '\(query)'. Current UserMemory.md:\n\n\(rawContent)"
        }

        var result = "# Filtered Memory for: \"\(query)\"\n\n"
        for entry in matchingEntries {
            result += "### \(entry.category)\n- \(entry.content)\n\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Memory Capture

    @discardableResult
    public func capture(memory: String, category: String? = nil) -> Bool {
        guard isMemoryEnabled else {
            logger.warning("Attempted capture while Memory module is OFF.")
            return false
        }

        reload()

        let cat = (category?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Learned Patterns & Directives"
        let cleanMemory = memory.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = rawContent.components(separatedBy: "\n")
        let targetHeader = "## \(cat)"

        if let headerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(targetHeader) == .orderedSame }) {
            // Insert under existing header
            var insertIndex = headerIndex + 1
            while insertIndex < lines.count && !lines[insertIndex].starts(with: "## ") {
                insertIndex += 1
            }
            // Insert before the next header or at end
            lines.insert("- \(cleanMemory)", at: insertIndex)
        } else {
            // Append new section
            if !lines.isEmpty && !lines.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append("## \(cat)")
            lines.append("- \(cleanMemory)")
        }

        let updated = lines.joined(separator: "\n")
        return saveRawContent(updated)
    }

    // MARK: - Memory Management

    @discardableResult
    public func saveToMemory(_ details: String) -> Bool {
        guard isMemoryEnabled else { return false }
        return capture(memory: details, category: "Learned Patterns & Directives")
    }

    @discardableResult
    public func modifySaved(_ modification: String) -> Bool {
        guard isMemoryEnabled else { return false }
        reload()

        let trimmed = modification.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = rawContent.components(separatedBy: "\n")

        // Format 1: "Old content -> New content"
        if trimmed.contains("->") {
            let parts = trimmed.components(separatedBy: "->")
            if parts.count >= 2 {
                let target = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let replacement = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

                for (idx, line) in lines.enumerated() {
                    let cleanedLine = line.replacingOccurrences(of: "^[-*]\\s+", with: "", options: .regularExpression)
                    if cleanedLine.lowercased().contains(target) {
                        lines[idx] = "- \(replacement)"
                        let updated = lines.joined(separator: "\n")
                        return saveRawContent(updated)
                    }
                }
            }
        }

        // Format 2: Matching substring or entry content replacement
        for (idx, line) in lines.enumerated() {
            let cleanedLine = line.replacingOccurrences(of: "^[-*]\\s+", with: "", options: .regularExpression)
            if cleanedLine.localizedCaseInsensitiveContains(trimmed) {
                lines[idx] = "- \(trimmed)"
                let updated = lines.joined(separator: "\n")
                return saveRawContent(updated)
            }
        }

        // If not found, append it as a learned pattern
        return capture(memory: trimmed, category: "Learned Patterns & Directives")
    }

    @discardableResult
    public func deleteContext(_ contextToDelete: String) -> Bool {
        guard isMemoryEnabled else { return false }
        reload()

        let target = contextToDelete.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var lines = rawContent.components(separatedBy: "\n")
        var removed = false

        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.starts(with: "- ") || trimmed.starts(with: "* ") else { return false }
            let bulletContent = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces).lowercased()
            if bulletContent.contains(target) || target.contains(bulletContent) {
                removed = true
                return true
            }
            return false
        }

        if removed {
            return saveRawContent(lines.joined(separator: "\n"))
        }
        return false
    }

    // MARK: - Granular Entry CRUD for UI

    public func addEntry(category: String, content: String) -> Bool {
        return capture(memory: content, category: category)
    }

    public func updateEntry(id: UUID, newContent: String) -> Bool {
        guard let entry = entries.first(where: { $0.id == id }) else { return false }
        return modifySaved("\(entry.content) -> \(newContent)")
    }

    public func deleteEntry(id: UUID) -> Bool {
        guard let entry = entries.first(where: { $0.id == id }) else { return false }
        return deleteContext(entry.content)
    }

    public func resetToTemplate() -> Bool {
        return saveRawContent(Self.defaultTemplate)
    }

    // MARK: - Markdown Parsing Helper

    private func parseEntries(from markdown: String) -> [UserMemoryEntry] {
        var parsed: [UserMemoryEntry] = []
        let lines = markdown.components(separatedBy: "\n")
        var currentCategory = "General"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "## ") {
                currentCategory = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "- ") || trimmed.starts(with: "* ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    parsed.append(UserMemoryEntry(
                        category: currentCategory,
                        content: content
                    ))
                }
            }
        }
        return parsed
    }
}
