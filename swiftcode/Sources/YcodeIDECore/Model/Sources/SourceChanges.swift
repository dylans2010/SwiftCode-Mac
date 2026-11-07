import Foundation

public struct SourceChangeRegion: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case added, modified, deleted }
    public var kind: Kind
    public var firstLine: Int
    public var lineCount: Int
    public var staged: Bool

    public init(kind: Kind, firstLine: Int, lineCount: Int, staged: Bool) {
        self.kind = kind
        self.firstLine = firstLine
        self.lineCount = lineCount
        self.staged = staged
    }

    public var lastLine: Int { firstLine + max(lineCount, 1) - 1 }

    public func contains(line: Int) -> Bool { line >= firstLine && line <= lastLine }

    public var accessibilityDescription: String {
        lastLine > firstLine ? "Local modification on lines \(firstLine) through \(lastLine)" : "Local modification on line \(firstLine)"
    }

    public var toolTip: String { staged ? "Staged change" : "Unstaged change" }
}

public enum SourceChanges {
    public static func regions(text: String, index: String?, head: String?) -> [SourceChangeRegion] {
        guard index != nil || head != nil else { return [] }
        let new = LineDiff.lines(text)
        func changes(_ base: String) -> [ReviewChange] {
            CodeReviewModel.changes(LineDiff.sideBySide(LineDiff.diff(LineDiff.lines(base), new)))
        }
        func region(_ c: ReviewChange, staged: Bool) -> SourceChangeRegion {
            let kind: SourceChangeRegion.Kind = c.newCount == 0 ? .deleted : (c.kind == .added ? .added : .modified)
            return SourceChangeRegion(kind: kind, firstLine: max(1, c.newStart), lineCount: c.newCount, staged: staged)
        }
        let unstaged = changes(index ?? head ?? "").map { region($0, staged: false) }
        let uncommitted = index == nil || index == head ? [] : changes(head ?? "").map { region($0, staged: true) }
        let staged = uncommitted.filter { s in !unstaged.contains { overlaps($0, s) } }
        return (unstaged + staged).sorted { ($0.firstLine, $0.lineCount) < ($1.firstLine, $1.lineCount) }
    }

    static func overlaps(_ a: SourceChangeRegion, _ b: SourceChangeRegion) -> Bool {
        a.firstLine <= b.lastLine && b.firstLine <= a.lastLine
    }

    public static func step(from line: Int, in regions: [SourceChangeRegion], forward: Bool) -> SourceChangeRegion? {
        guard !regions.isEmpty else { return nil }
        if forward { return regions.first { $0.firstLine > line } ?? regions.first }
        return regions.last { $0.firstLine < line } ?? regions.last
    }
}
