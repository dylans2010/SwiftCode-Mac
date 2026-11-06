import Foundation

/// The `safe_undo` store: the previous content of every file a
/// `commit()` write changed, so the last modification can really be
/// reverted.
///
/// Decision (see `specs/ide/gap-closure-correctness.md` §3): this is
/// deliberately NOT the Wave 7 `project_snapshot` store
/// (`SwiftCodeSnapshots/<uuid>/files`, a full-tree copy per snapshot).
/// Legacy's `safe_undo` (`AssistUndoTool`) restores snapshot[1] from
/// that same full-tree store — which only works after two explicit
/// snapshots exist, and snapshots are only ever created explicitly
/// (Legacy's agent loop never snapshots per action; the only
/// `createSnapshot` callers are the snapshot tool and UI). A
/// per-write full-tree copy would be the faithful way to make undo
/// work after every write, but it is far too heavy. This journal
/// records only what changed — one entry per committed file, holding
/// its previous text — which is exactly what "reverts the last
/// modification" needs, at O(changed file) cost. The two stores
/// answer different questions (point-in-time workspace restore vs.
/// last-modification revert) and stay separate, the same precedent
/// Wave 8 set for `checkpoint_creator` vs. `project_snapshot`.
///
/// Storage: Application Support `SwiftCodeUndo/<workspace-key>/journal.json`
/// (never inside the workspace, so undo state is not itself
/// workspace content). The workspace key is an FNV-1a hash of the
/// workspace root path, so two workspaces never share a journal.
/// Entries are capped (`maxEntries`); an entry whose previous content
/// was too large or not UTF-8 is recorded with `unrecorded == true`
/// and undo refuses it honestly instead of deleting the file.
public final class SafeUndoJournal: @unchecked Sendable {
    /// One recorded modification.
    public struct Entry: Codable, Sendable, Equatable {
        /// Workspace-relative path of the changed file.
        public var relativePath: String
        /// The file's text before the change; nil when the file did
        /// not exist (undo deletes it).
        public var original: String?
        /// True when the previous content could not be recorded
        /// (too large or not UTF-8): undo must refuse this entry.
        public var unrecorded: Bool
        /// The tool that made the change.
        public var tool: String
        /// When the change was committed.
        public var date: Date

        public init(relativePath: String, original: String?, unrecorded: Bool, tool: String, date: Date) {
            self.relativePath = relativePath
            self.original = original
            self.unrecorded = unrecorded
            self.tool = tool
            self.date = date
        }
    }

    /// Largest previous content recorded (bytes of UTF-8). Larger
    /// files are recorded as `unrecorded` rather than copied.
    public static let maxOriginalBytes = 1_000_000
    /// Entries kept per workspace; older ones drop off the front.
    public static let maxEntries = 100

    public static let shared = SafeUndoJournal()

    private let lock = NSLock()
    private let baseDirectory: URL

    /// - Parameter baseDirectory: the `SwiftCodeUndo` directory. Nil
    ///   resolves Application Support `SwiftCodeUndo` (tests pass a
    ///   temporary directory).
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

    /// A stable per-workspace directory name: FNV-1a-64 of the
    /// workspace root path, hex. (A hash, not the path itself, so
    /// the journal path stays short and contains no separators.)
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
            // The journal is best-effort: a failed save must never
            // break the write it records.
        }
    }

    /// Records one committed change. `original` is the file's text
    /// before the change (nil: the file did not exist); pass
    /// `unrecorded: true` when it could not be read. A previous
    /// content over `maxOriginalBytes` is stored as `unrecorded`
    /// instead of copied, so the journal cannot grow without bound.
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

    /// Removes and returns the most recent entry, if any.
    public func popLast(workspaceRoot root: URL) -> Entry? {
        lock.withLock {
            var entries = load(workspaceRoot: root)
            guard let last = entries.popLast() else { return nil }
            save(entries, workspaceRoot: root)
            return last
        }
    }

    /// All entries, oldest first (does not consume them).
    public func entries(workspaceRoot root: URL) -> [Entry] {
        lock.withLock { load(workspaceRoot: root) }
    }

    /// Drops the workspace's whole journal.
    public func clear(workspaceRoot root: URL) {
        lock.withLock {
            try? FileManager.default.removeItem(at: journalURL(for: root))
        }
    }
}
