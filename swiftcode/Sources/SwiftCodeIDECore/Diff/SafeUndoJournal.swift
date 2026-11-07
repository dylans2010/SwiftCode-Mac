import Foundation

public final class SafeUndoJournal: @unchecked Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var relativePath: String
        public var original: String?
        public var unrecorded: Bool
        public var tool: String
        public var date: Date

        public init(relativePath: String, original: String?, unrecorded: Bool, tool: String, date: Date) {
            self.relativePath = relativePath
            self.original = original
            self.unrecorded = unrecorded
            self.tool = tool
            self.date = date
        }
    }

    public static let maxOriginalBytes = 1_000_000
    public static let maxEntries = 100

    public static let shared = SafeUndoJournal()

    private let lock = NSLock()
    private let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                appropriateFor: nil, create: true) {
            self.baseDirectory = appSupport.appendingPathComponent("SwiftCodeUndo", isDirectory: true)
        } else {
            self.baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftCodeUndo", isDirectory: true)
        }
    }

    static func workspaceKey(for root: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in root.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private func journalURL(for root: URL) -> URL {
        baseDirectory.appendingPathComponent(Self.workspaceKey(for: root), isDirectory: true)
            .appendingPathComponent("journal.json")
    }

    private func load(workspaceRoot root: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: journalURL(for: root)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry], workspaceRoot root: URL) {
        let url = journalURL(for: root)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: url, options: .atomic)
        } catch {
        }
    }

    public func record(workspaceRoot root: URL, relativePath: String, original: String?, unrecorded: Bool = false, tool: String) {
        lock.withLock {
            var entries = load(workspaceRoot: root)
            let tooLarge = (original?.utf8.count ?? 0) > Self.maxOriginalBytes
            entries.append(Entry(relativePath: relativePath, original: tooLarge ? nil : original,
                                 unrecorded: unrecorded || tooLarge,
                                 tool: tool, date: Date()))
            if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
            save(entries, workspaceRoot: root)
        }
    }

    public func popLast(workspaceRoot root: URL) -> Entry? {
        lock.withLock {
            var entries = load(workspaceRoot: root)
            guard let last = entries.popLast() else { return nil }
            save(entries, workspaceRoot: root)
            return last
        }
    }

    public func entries(workspaceRoot root: URL) -> [Entry] {
        lock.withLock { load(workspaceRoot: root) }
    }

    public func clear(workspaceRoot root: URL) {
        lock.withLock {
            try? FileManager.default.removeItem(at: journalURL(for: root))
        }
    }
}
