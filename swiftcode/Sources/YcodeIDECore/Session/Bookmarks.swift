import Foundation

public struct Bookmark: Codable, Equatable, Sendable {
    public var file: String
    public var line: Int?
    public var label: String
    public var done: Bool?
    public init(file: String, line: Int?, label: String, done: Bool? = nil) {
        self.file = file
        self.line = line
        self.label = label
        self.done = done
    }
}

@MainActor
public final class BookmarkStore {
    public private(set) var all: [Bookmark] = []
    let fileURL: URL?
    package var onChange: (() -> Void)?

    package init(containerURL: URL, isPackage: Bool) {
        let user = NSUserName()
        let base = isPackage ? containerURL.appendingPathComponent(".swiftpm/xcode") : containerURL
        fileURL = base.appendingPathComponent("xcuserdata/\(user).xcuserdatad/swiftcode-bookmarks.json")
        if let f = fileURL, let d = try? Data(contentsOf: f), let list = try? JSONDecoder().decode([Bookmark].self, from: d) { all = list }
    }

    func save() {
        guard let f = fileURL else { return }
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(all).write(to: f, options: .atomic)
        onChange?()
    }

    public func add(_ b: Bookmark) {
        all.removeAll { $0.file == b.file && $0.line == b.line }
        all.append(b)
        all.sort { ($0.file, $0.line ?? 0) < ($1.file, $1.line ?? 0) }
        save()
    }

    public func setDone(_ b: Bookmark, _ done: Bool) {
        guard let i = all.firstIndex(where: { $0.file == b.file && $0.line == b.line }) else { return }
        all[i].done = done ? true : nil
        save()
    }

    public func remove(_ b: Bookmark) {
        all.removeAll { $0 == b }
        save()
    }

    public func next(from file: String, line: Int, backward: Bool, workspace: Bool) -> Bookmark? {
        let lines = all.filter { $0.line != nil }
        let ordered = workspace ? lines : lines.filter { $0.file == file }
        guard !ordered.isEmpty else { return nil }
        func key(_ b: Bookmark) -> (String, Int) { (b.file, b.line!) }
        let here = (file, line)
        if backward { return ordered.last { key($0) < here } ?? ordered.last }
        return ordered.first { key($0) > here } ?? ordered.first
    }
}
