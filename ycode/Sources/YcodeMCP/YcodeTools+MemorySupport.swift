import Foundation
import YcodeIDECore

/// Shared stores and file formats for the ported Legacy memory tool
/// family (Wave 4, Memory slice).
///
/// Behaviour source: Legacy `AssistMemoryGraph` (in-memory key-value
/// graph), `UserMemoryManager` (`UserMemory.md` Markdown format),
/// `AssistConversationHistory` (per-conversation `<id>.context.md`)
/// and `AssistContextPersistenceStore` (`.assist_context_store.json`)
/// (Dylan's own code, ported under MIT), as specified in the Wave 4
/// memory spec draft (`/tmp/wave4-memory-spec.md`; the coordinator
/// merges it into `specs/ide/`).
///
/// The three Legacy stores map onto Ycode host stores as follows
/// (see the spec draft §1 for the full rationale; no SQLite /
/// CoreData / IDE database layer is introduced — the destination
/// audit §5 records that none exists by design):
///
/// * **Session memory graph** (`mem_store`, `mem_retrieve`,
///   `mem_clear`, `mem_context_snapshot`): Legacy's
///   `AssistMemoryGraph` is in-memory only — a process-lifetime
///   `[String: String]` behind an `NSLock`, never written to disk.
///   The port keeps that exactly: `YcodeMemoryGraphStore`, one graph
///   per workspace root path, process-lifetime, never persisted.
///   "Long-term" in Legacy's tool descriptions means this graph,
///   not disk; the port does not upgrade it to durable storage.
/// * **Durable user memory** (`save_to_memory`, `view_memory`,
///   `manage_memory`): Legacy writes the app-global
///   `~/Library/Application Support/SwiftCode/UserMemory.md`. That
///   file is shared by every workspace, so the port does NOT reuse
///   it — memory must be workspace-confined. The port keeps
///   Legacy's exact Markdown format (header, `## <Category>`
///   sections, `- **<key>**: <value> <!-- updated: <ISO8601> -->`
///   lines, categories and keys sorted) in a per-workspace file,
///   `<workspace>/.assist_temp/memory/UserMemory.md` (the Wave 1
///   artifact-store pattern: a `.assist_temp` subdirectory, like
///   `.assist_temp/artifacts` and `.assist_temp/backups`).
/// * **Persistent context** (`context_persistence_store`): Legacy
///   writes `<workspace>/.assist_context_store.json` (a `[String:
///   String]` JSON object, pretty-printed, sorted keys). The port
///   keeps that exact path and format — it is already a hidden
///   workspace file, hence workspace-confined by construction.
/// * **Conversation context** (`conversation_context_manager`):
///   Legacy writes one `<uuid>.context.md` per conversation under
///   `~/Library/Application Support/SwiftCode/Conversations/`,
///   keyed by `AssistConversationHistory`'s active conversation ID.
///   The MCP host has no conversation identity
///   (`WorkspaceSession` carries no conversation; the IDE's selected
///   conversation is not visible to the host), so per-conversation
///   files are impossible here. The port keeps one file per
///   workspace, `<workspace>/.assist_temp/memory/
///   conversation_context.md`, with Legacy's exact append format
///   (`# Conversation Context` header, then one `### Additional
///   Model Context (Updated <ISO8601>):` section per update).
///   It is the active conversation's context for this workspace's
///   MCP session.
///
/// Other deliberate deviations from Legacy, recorded here:
///
/// * Legacy's `UserMemoryManager` seeds a new `UserMemory.md` with
///   SwiftCode-specific defaults (ArchitectureStyle,
///   TargetPlatform, AppIdentity). Ycode does not seed: a new file
///   is the header only. Seeding another app's identity into a
///   Ycode workspace would be wrong.
/// * Legacy gates `save_to_memory` / `manage_memory` writes on
///   `AppSettings.enableUserMemory`. Ycode has no such setting;
///   writes are gated by the MCP approval path instead (the tools
///   register `writes: true` and write through `commit()`).
/// * Legacy's `save_to_memory` success message names its
///   app-global path. The port names the real workspace file
///   (`.assist_temp/memory/UserMemory.md`); reporting the Legacy
///   path would be false.
/// * `mem_context_snapshot` reads Legacy's snapshot list
///   (`AssistSnapshotFunctions.listSnapshots`). Ycode has no
///   snapshot store, so `latest_snapshot` is always `"none"` and
///   the stored payload records only the session, the workspace
///   and that fact. The stored marker is a real memory-graph entry
///   (retrievable with `mem_retrieve`); nothing is faked.
/// * Empty-string arguments are treated as missing (Ycode's
///   `MCPToolCall.string` / `require` convention), where Legacy's
///   raw `[String: Any]` guards would have accepted an empty key
///   for `mem_store` / `mem_retrieve` and an empty action for
///   `manage_memory` / `conversation_context_manager`. The failure
///   messages are Legacy's.
///
/// Secrets: all four stores are plaintext files (or process memory)
/// inside the workspace. Callers must not store credentials or
/// other secrets with these tools; nothing here scans or redacts
/// values, and Legacy did not either.

/// One process-lifetime key-value graph per workspace, mirroring
/// Legacy's `AssistMemoryGraph` (`NSLock` + `[String: String]`,
/// never persisted).
final class YcodeMemoryGraphStore: @unchecked Sendable {
    static let shared = YcodeMemoryGraphStore()

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

    /// Clears one workspace's graph; returns how many entries were held.
    @discardableResult
    func clear(workspace: String) -> Int {
        lock.withLock {
            let count = graphs[workspace]?.count ?? 0
            graphs[workspace] = [:]
            return count
        }
    }

    /// The session ID for a workspace, minted once per process (Legacy's
    /// `AssistContext.sessionId`, one per Assist session).
    func sessionID(workspace: String) -> UUID {
        lock.withLock {
            if let id = sessionIDs[workspace] { return id }
            let id = UUID()
            sessionIDs[workspace] = id
            return id
        }
    }
}

/// One durable memory entry, mirroring Legacy's `UserMemoryEntry`.
struct YcodeUserMemoryEntry: Codable, Sendable, Equatable {
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

/// Legacy's `UserMemory.md` Markdown format: the header, one
/// `## <Category>` section per category (sorted), one
/// `- **<key>**: <value> <!-- updated: <ISO8601> -->` line per entry
/// (keys sorted within a category). Parsing accepts Legacy's file
/// too (the subtitle line differs — see the file header — but the
/// parser ignores every line that is neither a `## ` heading nor a
/// `- **` entry).
enum YcodeUserMemoryFormat {
    static let header = "# User Memory & Durable Context\n\n_Auto-maintained by Ycode Assist._\n\n"

    static func render(_ entries: [YcodeUserMemoryEntry]) -> String {
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

    static func parse(_ markdown: String) -> [YcodeUserMemoryEntry] {
        var result: [YcodeUserMemoryEntry] = []
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
                result.append(YcodeUserMemoryEntry(key: key, value: rawVal, category: currentCategory, updatedAt: date))
            }
        }
        return result
    }
}

/// The context store's JSON: Legacy writes it with
/// `JSONSerialization` (`.prettyPrinted, .sortedKeys`). The manual
/// renderer below produces the same shape for a `[String: String]`
/// dictionary and is the fallback if serialization ever fails.
enum YcodeContextStoreFormat {
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

extension YcodeMCPHost {
    /// The workspace key the session memory graph is filed under: the
    /// workspace root path. One graph per workspace, so one
    /// workspace's memory never leaks into another's.
    func memoryWorkspaceKey(in s: WorkspaceSession) -> String {
        Self.folder(of: s.model).path
    }

    /// Where the durable per-workspace memory files live:
    /// `<workspace>/.assist_temp/memory` (the Wave 1 artifact-store
    /// pattern, alongside `.assist_temp/artifacts` and
    /// `.assist_temp/backups`).
    func memoryDirectory(in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model).appendingPathComponent(".assist_temp/memory", isDirectory: true)
    }

    /// `<workspace>/.assist_temp/memory/UserMemory.md`.
    func userMemoryURL(in s: WorkspaceSession) -> URL {
        memoryDirectory(in: s).appendingPathComponent("UserMemory.md")
    }

    /// `<workspace>/.assist_temp/memory/conversation_context.md`.
    func conversationContextURL(in s: WorkspaceSession) -> URL {
        memoryDirectory(in: s).appendingPathComponent("conversation_context.md")
    }

    /// `<workspace>/.assist_context_store.json` — Legacy's exact path.
    func contextStoreURL(in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model).appendingPathComponent(".assist_context_store.json")
    }

    /// The durable entries, parsed from the workspace file (empty
    /// when the file does not exist yet). Reads through `text(of:)`,
    /// so the editor's unsaved text wins when the file is open.
    func loadUserMemoryEntries(in s: WorkspaceSession) -> [YcodeUserMemoryEntry] {
        YcodeUserMemoryFormat.parse(text(of: userMemoryURL(in: s)) ?? "")
    }

    /// The context store, parsed from the workspace file. A missing
    /// or unparsable file reads as empty, like Legacy (which
    /// `try?`-s the read and falls back to `[:]`).
    func loadContextStore(in s: WorkspaceSession) -> [String: String] {
        guard let text = text(of: contextStoreURL(in: s)) else { return [:] }
        return YcodeContextStoreFormat.parse(text)
    }
}
