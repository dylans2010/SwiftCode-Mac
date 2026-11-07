import Foundation
import SwiftCodeIDECore

final class SwiftCodeMemoryGraphStore: @unchecked Sendable {
    static let shared = SwiftCodeMemoryGraphStore()

    private let lock = NSLock()
    private var graphs: [String: [String: String]] = [:]
    private var sessionIDs: [String: UUID] = [:]

    private init() {}

    func store(workspace: String, key: String, value: String) {
        lock.withLock { graphs[workspace, default: [:]][key] = value }
    }

    func retrieve(workspace: String, key: String) -> String? {
        lock.withLock { graphs[workspace]?[key] }
    }

    @discardableResult
    func clear(workspace: String) -> Int {
        lock.withLock {
            let count = graphs[workspace]?.count ?? 0
            graphs[workspace] = [:]
            return count
        }
    }

    func sessionID(workspace: String) -> UUID {
        lock.withLock {
            if let id = sessionIDs[workspace] { return id }
            let id = UUID()
            sessionIDs[workspace] = id
            return id
        }
    }
}

struct SwiftCodeUserMemoryEntry: Codable, Sendable, Equatable {
    var key: String
    var value: String
    var category: String
    var updatedAt: Date

    init(key: String, value: String, category: String = "General", updatedAt: Date = Date()) {
        self.key = key
        self.value = value
        self.category = category
        self.updatedAt = updatedAt
    }
}

enum SwiftCodeUserMemoryFormat {
    static let header = "# User Memory & Durable Context\n\n_Auto-maintained by SwiftCode Assist._\n\n"

    static func render(_ entries: [SwiftCodeUserMemoryEntry]) -> String {
        var md = header
        let df = ISO8601DateFormatter()
        let categories = Dictionary(grouping: entries, by: { $0.category })
        for cat in categories.keys.sorted() {
            md += "## \(cat)\n\n"
            for item in (categories[cat] ?? []).sorted(by: { $0.key < $1.key }) {
                md += "- **\(item.key)**: \(item.value) <!-- updated: \(df.string(from: item.updatedAt)) -->\n"
            }
            md += "\n"
        }
        return md
    }

    static func parse(_ markdown: String) -> [SwiftCodeUserMemoryEntry] {
        var result: [SwiftCodeUserMemoryEntry] = []
        var currentCategory = "General"
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let cat = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !cat.isEmpty { currentCategory = cat }
                continue
            }
            guard trimmed.hasPrefix("- **") else { continue }
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
                    if let parsedDate = ISO8601DateFormatter().date(from: dStr) { date = parsedDate }
                }
                rawVal = valOnly
            }
            if !key.isEmpty && !rawVal.isEmpty {
                result.append(SwiftCodeUserMemoryEntry(key: key, value: rawVal, category: currentCategory, updatedAt: date))
            }
        }
        return result
    }
}

enum SwiftCodeContextStoreFormat {
    static func render(_ db: [String: String]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: db, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        guard !db.isEmpty else { return "{}" }
        let lines = db.keys.sorted().map { "  \(jsonString($0)): \(jsonString(db[$0] ?? ""))" }
        return "{\n" + lines.joined(separator: ",\n") + "\n}"
    }

    static func parse(_ text: String) -> [String: String] {
        guard let data = text.data(using: .utf8),
              let db = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return db
    }

    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

extension SwiftCodeMCPHost {
    func memoryWorkspaceKey(in s: WorkspaceSession) -> String {
        Self.folder(of: s.model).path
    }

    func memoryDirectory(in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model).appendingPathComponent(".assist_temp/memory", isDirectory: true)
    }

    func userMemoryURL(in s: WorkspaceSession) -> URL {
        memoryDirectory(in: s).appendingPathComponent("UserMemory.md")
    }

    func conversationContextURL(in s: WorkspaceSession) -> URL {
        memoryDirectory(in: s).appendingPathComponent("conversation_context.md")
    }

    func contextStoreURL(in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model).appendingPathComponent(".assist_context_store.json")
    }

    func loadUserMemoryEntries(in s: WorkspaceSession) -> [SwiftCodeUserMemoryEntry] {
        SwiftCodeUserMemoryFormat.parse(text(of: userMemoryURL(in: s)) ?? "")
    }

    func loadContextStore(in s: WorkspaceSession) -> [String: String] {
        guard let text = text(of: contextStoreURL(in: s)) else { return [:] }
        return SwiftCodeContextStoreFormat.parse(text)
    }
}
