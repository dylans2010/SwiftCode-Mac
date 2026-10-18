//
//  UserMemoryManager.swift
//  SwiftCode
//
//  Manages persistent user context and durable memory stored in `UserMemory.md`
//  located in ~/Library/Application Support/SwiftCode/UserMemory.md.
//

import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "UserMemoryManager")

public struct UserMemoryEntry: Identifiable, Codable, Sendable, Hashable {
    public var id: String { key }
    public let key: String
    public var value: String
    public var category: String
    public var updatedAt: Date

    public init(key: String, value: String, category: String = "General", updatedAt: Date = Date()) {
        self.key = key
        self.value = value
        self.category = category
        self.updatedAt = updatedAt
    }
}

@MainActor
public final class UserMemoryManager: ObservableObject {
    public static let shared = UserMemoryManager()

    @Published public private(set) var entries: [UserMemoryEntry] = []
    @Published public private(set) var lastSavedMemory: UserMemoryEntry? = nil

    private let fileManager = FileManager.default

    public var memoryDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var memoryFileURL: URL {
        return memoryDirectoryURL.appendingPathComponent("UserMemory.md")
    }

    private init() {
        loadMemory()
    }

    public func reload() {
        loadMemory()
    }

    // MARK: - Core Storage Operations

    public func loadMemory() {
        let url = memoryFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            createDefaultMemoryFileIfNeeded()
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            self.entries = parseMarkdown(content)
        } catch {
            logger.error("Failed to read UserMemory.md: \(error.localizedDescription)")
        }
    }

    public func readMemoryMarkdown() -> String {
        createDefaultMemoryFileIfNeeded()
        return (try? String(contentsOf: memoryFileURL, encoding: .utf8)) ?? ""
    }

    @discardableResult
    public func saveMemory(key: String, value: String, category: String = "General") -> Bool {
        guard AppSettings.shared.enableUserMemory else {
            logger.info("UserMemory is disabled in settings; rejecting write for key '\(key)'.")
            return false
        }

        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : category

        guard !cleanKey.isEmpty && !cleanValue.isEmpty else { return false }

        var currentEntries = entries
        if let idx = currentEntries.firstIndex(where: { $0.key.caseInsensitiveCompare(cleanKey) == .orderedSame }) {
            currentEntries[idx].value = cleanValue
            currentEntries[idx].category = cleanCategory
            currentEntries[idx].updatedAt = Date()
            lastSavedMemory = currentEntries[idx]
        } else {
            let newEntry = UserMemoryEntry(key: cleanKey, value: cleanValue, category: cleanCategory, updatedAt: Date())
            currentEntries.append(newEntry)
            lastSavedMemory = newEntry
        }

        self.entries = currentEntries
        let saved = persistToDisk()
        if saved {
            NotificationCenter.default.post(name: NSNotification.Name("UserMemoryDidUpdate"), object: nil, userInfo: ["key": cleanKey])
        }
        return saved
    }

    @discardableResult
    public func deleteMemory(key: String) -> Bool {
        var currentEntries = entries
        guard let idx = currentEntries.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else {
            return false
        }
        currentEntries.remove(at: idx)
        self.entries = currentEntries
        let saved = persistToDisk()
        if saved {
            NotificationCenter.default.post(name: NSNotification.Name("UserMemoryDidUpdate"), object: nil)
        }
        return saved
    }

    @discardableResult
    public func clearAll() -> Bool {
        self.entries = []
        let header = "# User Memory & Durable Context\n\n_Auto-maintained by SwiftCode Assist & User Settings._\n\n"
        do {
            try header.write(to: memoryFileURL, atomically: true, encoding: .utf8)
            NotificationCenter.default.post(name: NSNotification.Name("UserMemoryDidUpdate"), object: nil)
            return true
        } catch {
            logger.error("Failed to clear UserMemory.md: \(error.localizedDescription)")
            return false
        }
    }

    public func search(query: String) -> [UserMemoryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.key.lowercased().contains(q) ||
            $0.value.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }

    // MARK: - Markdown Serialization

    private func persistToDisk() -> Bool {
        var md = "# User Memory & Durable Context\n\n"
        md += "_Auto-maintained by SwiftCode Assist & User Settings._\n\n"

        // Group by category
        let categories = Dictionary(grouping: entries, by: { $0.category })
        let sortedCategories = categories.keys.sorted()

        let df = ISO8601DateFormatter()
        for cat in sortedCategories {
            md += "## \(cat)\n\n"
            if let items = categories[cat] {
                for item in items.sorted(by: { $0.key < $1.key }) {
                    let dateStr = df.string(from: item.updatedAt)
                    md += "- **\(item.key)**: \(item.value) <!-- updated: \(dateStr) -->\n"
                }
            }
            md += "\n"
        }

        do {
            try md.write(to: memoryFileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            logger.error("Failed to write to UserMemory.md: \(error.localizedDescription)")
            return false
        }
    }

    private func parseMarkdown(_ markdown: String) -> [UserMemoryEntry] {
        var result: [UserMemoryEntry] = []
        var currentCategory = "General"

        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let cat = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !cat.isEmpty {
                    currentCategory = cat
                }
                continue
            }

            guard trimmed.hasPrefix("- **") else { continue }
            // Format: - **Key**: Value <!-- updated: date -->
            guard let keyEnd = trimmed.range(of: "**:") else { continue }
            let keyStart = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let key = String(trimmed[keyStart..<keyEnd.lowerBound]).trimmingCharacters(in: .whitespaces)

            var rawVal = String(trimmed[keyEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
            var date = Date()
            if let commentStart = rawVal.range(of: "<!-- updated:") {
                let valOnly = String(rawVal[..<commentStart.lowerBound]).trimmingCharacters(in: .whitespaces)
                let commentRest = String(rawVal[commentStart.upperBound...])
                if let commentEnd = commentRest.range(of: "-->") {
                    let dStr = String(commentRest[..<commentEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if let parsedDate = ISO8601DateFormatter().date(from: dStr) {
                        date = parsedDate
                    }
                }
                rawVal = valOnly
            }

            if !key.isEmpty && !rawVal.isEmpty {
                result.append(UserMemoryEntry(key: key, value: rawVal, category: currentCategory, updatedAt: date))
            }
        }
        return result
    }

    private func createDefaultMemoryFileIfNeeded() {
        guard !fileManager.fileExists(atPath: memoryFileURL.path) else { return }
        let initialContent = """
        # User Memory & Durable Context

        _Auto-maintained by SwiftCode Assist & User Settings._

        ## Preferences

        - **ArchitectureStyle**: Standard SwiftUI with MVVM, Observation, and Swift 6 Strict Concurrency.
        - **TargetPlatform**: macOS & iOS Universal with Native Mac Styling.

        ## Project Context

        - **AppIdentity**: SwiftCode Native IDE for macOS.
        """
        try? initialContent.write(to: memoryFileURL, atomically: true, encoding: .utf8)
        self.entries = parseMarkdown(initialContent)
    }
}
