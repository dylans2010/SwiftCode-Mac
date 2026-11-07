import Foundation

public struct ReplacePlan: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public var path: String
        public var matches: [WorkspaceSearch.Match]
        public var included: [Bool]
        public var isIncluded: Bool { included.contains(true) }
        public var includedCount: Int { included.filter { $0 }.count }
    }

    public var query: FindQuery
    public var replacement: String
    public var files: [File]

    public init(query: FindQuery, replacement: String, results: [WorkspaceSearch.FileResult]) {
        self.query = query
        self.replacement = replacement
        files = results.map { File(path: $0.path, matches: $0.matches, included: Array(repeating: true, count: $0.matches.count)) }
    }

    public mutating func setIncluded(_ on: Bool, file: Int, match: Int? = nil) {
        guard files.indices.contains(file) else { return }
        if let m = match {
            guard files[file].included.indices.contains(m) else { return }
            files[file].included[m] = on
        } else {
            files[file].included = Array(repeating: on, count: files[file].matches.count)
        }
    }

    public var includedCount: Int { files.reduce(0) { $0 + $1.includedCount } }
    public var includedFileCount: Int { files.filter(\.isIncluded).count }

    public func replacementText(for m: WorkspaceSearch.Match, in text: String) -> String {
        guard query.kind == .regularExpression, let regex = query.matcher()?.expression else { return replacement }
        let ns = text as NSString
        guard NSMaxRange(m.range) <= ns.length,
              let r = regex.firstMatch(in: text, options: [.anchored, .withTransparentBounds],
                                       range: NSRange(location: m.range.location, length: ns.length - m.range.location)),
              r.range == m.range else { return replacement }
        return regex.replacementString(for: r, in: text, offset: 0, template: replacement)
    }

    public func preview(file: Int, match: Int, text: String) -> (before: String, after: String) {
        let m = files[file].matches[match]
        let ns = text as NSString
        let index = LineIndex(text)
        guard NSMaxRange(m.range) <= ns.length, let first = index.range(ofLine: m.line) else { return (m.text, m.text) }
        let lastLine = index.line(at: max(m.range.location, NSMaxRange(m.range) - 1))
        let last = index.range(ofLine: lastLine) ?? first
        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let before = ns.substring(with: span)
        let local = NSRange(location: m.range.location - span.location, length: m.range.length)
        let after = (before as NSString).replacingCharacters(in: local, with: replacementText(for: m, in: text))
        return (before.trimmingCharacters(in: .whitespacesAndNewlines), after.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func newText(file: Int, text: String) -> (text: String, replaced: Int, stale: Int) {
        let f = files[file]
        let ns = text as NSString
        var picked: [(NSRange, String)] = []
        var stale = 0
        var end = 0
        for (i, m) in f.matches.enumerated() where f.included[i] {
            guard NSMaxRange(m.range) <= ns.length, m.matchedText.isEmpty || ns.substring(with: m.range) == m.matchedText else { stale += 1; continue }
            guard m.range.location >= end else { continue }
            picked.append((m.range, replacementText(for: m, in: text)))
            end = NSMaxRange(m.range)
        }
        let out = NSMutableString(string: text)
        for (r, s) in picked.reversed() { out.replaceCharacters(in: r, with: s) }
        return (out as String, picked.count, stale)
    }

    public func apply(_ io: ReplaceIO) -> ReplaceTransaction {
        var t = ReplaceTransaction(title: "Replace \(includedCount) Occurrence\(includedCount == 1 ? "" : "s")")
        for (i, f) in files.enumerated() where f.isIncluded {
            guard let old = io.read(f.path) else { t.failed.append(f.path); continue }
            let (new, n, stale) = newText(file: i, text: old)
            if stale > 0 { t.stale.append(f.path) }
            guard n > 0, new != old else { continue }
            if io.write(f.path, new) {
                t.changes.append(ReplaceChange(path: f.path, oldText: old, newText: new, count: n))
            } else {
                t.failed.append(f.path)
            }
        }
        return t
    }
}

public struct ReplaceIO {
    public var read: (String) -> String?
    public var write: (String, String) -> Bool
    public init(read: @escaping (String) -> String?, write: @escaping (String, String) -> Bool) {
        self.read = read
        self.write = write
    }

    public static var disk: ReplaceIO {
        ReplaceIO(read: { try? String(contentsOfFile: $0, encoding: .utf8) },
                  write: { path, text in (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil })
    }
}

public struct ReplaceChange: Equatable, Sendable {
    public var path: String
    public var oldText: String
    public var newText: String
    public var count: Int
}

public struct ReplaceTransaction: Equatable, Sendable {
    public var title: String
    public var changes: [ReplaceChange] = []
    public var stale: [String] = []
    public var failed: [String] = []
    public var replacedCount: Int { changes.reduce(0) { $0 + $1.count } }
    public init(title: String) { self.title = title }
}

public final class ReplaceHistory {
    public struct Outcome: Equatable, Sendable {
        public var restored: [String] = []
        public var conflicts: [String] = []
    }

    public private(set) var undoStack: [ReplaceTransaction] = []
    public private(set) var redoStack: [ReplaceTransaction] = []
    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func record(_ t: ReplaceTransaction) {
        guard !t.changes.isEmpty else { return }
        undoStack.append(t)
        redoStack.removeAll()
    }

    @discardableResult
    public func undo(_ io: ReplaceIO) -> Outcome {
        guard let t = undoStack.popLast() else { return Outcome() }
        redoStack.append(t)
        return Self.restore(t, io, toOriginal: true)
    }

    @discardableResult
    public func redo(_ io: ReplaceIO) -> Outcome {
        guard let t = redoStack.popLast() else { return Outcome() }
        undoStack.append(t)
        return Self.restore(t, io, toOriginal: false)
    }

    public static func restore(_ t: ReplaceTransaction, _ io: ReplaceIO, toOriginal: Bool) -> Outcome {
        let from: KeyPath<ReplaceChange, String> = toOriginal ? \.newText : \.oldText
        let to: KeyPath<ReplaceChange, String> = toOriginal ? \.oldText : \.newText
        var o = Outcome()
        for c in t.changes {
            if io.read(c.path) == c[keyPath: from], io.write(c.path, c[keyPath: to]) { o.restored.append(c.path) } else { o.conflicts.append(c.path) }
        }
        return o
    }
}
