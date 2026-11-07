import Foundation

public struct ConflictEditorState: Equatable, Sendable {
    public enum Pair: Int, CaseIterable, Sendable { case leftRight, baseLeft, baseRight }
    public static let pairTitles = ["Left \u{2194} Right", "Base \u{2194} Left", "Base \u{2194} Right"]
    public static let choiceTitles = ["Left", "Right", "Left + Right", "Right + Left", "Base", "Edit"]
    public static let segmentChoices: [MergeDocument.Choice] = [.ours, .theirs, .oursThenTheirs, .theirsThenOurs, .base]
    public static let editSegment = 5

    public enum Source: Equatable, Sendable {
        case repository
        case files(hasAncestor: Bool)
    }

    public let source: Source
    public var files: [String] = []
    public var currentFile: String?
    public private(set) var document: MergeDocument?
    public private(set) var currentHunk: Int?
    public private(set) var pair: Pair = .leftRight
    public private(set) var isEditing = false
    public var integration: GitRepository.IntegrationState = .none
    public var lastError: String?
    public internal(set) var otherDocuments: [String: MergeDocument] = [:]
    public var leftFooter: MergeSheetFooter?
    public var rightFooter: MergeSheetFooter?

    public init(source: Source = .repository) {
        self.source = source
    }

    public var isComparingFiles: Bool { source != .repository }
    public var hasBase: Bool { if case .files(let a) = source { a } else { true } }

    public mutating func load(_ doc: MergeDocument?) {
        document = doc
        isEditing = false
        currentHunk = doc.flatMap { $0.step(from: nil, forward: true, unresolvedOnly: true) ?? $0.step(from: nil, forward: true) }
        syncEditing()
    }

    public mutating func selectHunk(_ h: Int?) {
        guard let doc = document, let h, doc.hunks.indices.contains(h) else { return }
        currentHunk = h
        syncEditing()
    }

    public mutating func nextHunk() { selectHunk(document?.step(from: currentHunk, forward: true)) }
    public mutating func previousHunk() { selectHunk(document?.step(from: currentHunk, forward: false)) }

    public mutating func choose(_ choice: MergeDocument.Choice) {
        guard var doc = document, let h = currentHunk else { return }
        doc.choose(choice, hunk: h)
        document = doc
        if case .custom = choice { isEditing = true; return }
        isEditing = false
        if choice != .unresolved, let next = doc.step(from: h, forward: true, unresolvedOnly: true), next != h {
            selectHunk(next)
        }
    }

    public mutating func chooseSegment(_ i: Int) {
        if i == Self.editSegment { beginEditing(); return }
        if Self.segmentChoices.indices.contains(i) { choose(Self.segmentChoices[i]) }
    }

    public mutating func beginEditing() {
        guard let doc = document, let h = currentHunk else { return }
        let c = doc.chunks[doc.hunks[h]]
        let start: [String] = switch doc.choices[h] {
        case .unresolved: c.ours + c.theirs
        case .custom(let l): l
        default: doc.lines(forHunk: h)
        }
        choose(.custom(start))
    }

    public mutating func setEditedText(_ text: String) {
        guard isEditing, var doc = document, let h = currentHunk else { return }
        doc.choose(.custom(LineDiff.lines(text)), hunk: h)
        document = doc
    }

    public var editedText: String {
        guard let doc = document, let h = currentHunk, case .custom(let l) = doc.choices[h] else { return "" }
        return l.isEmpty ? "" : l.joined(separator: "\n") + "\n"
    }

    private mutating func syncEditing() {
        guard let doc = document, let h = currentHunk else { isEditing = false; return }
        if case .custom = doc.choices[h] { isEditing = true } else { isEditing = false }
    }

    public mutating func setPair(_ p: Pair) { pair = hasBase ? p : .leftRight }

    public enum Follow: Equatable, Sendable {
        case keep
        case show(String?)
    }

    public mutating func update(integration: GitRepository.IntegrationState, conflicted: [String]) -> Follow {
        self.integration = integration
        guard conflicted != files else { return .keep }
        files = conflicted
        otherDocuments = otherDocuments.filter { conflicted.contains($0.key) }
        if let f = currentFile, !conflicted.contains(f) { return .show(conflicted.first) }
        return .keep
    }

    public static func target(wanted: String?, in files: [String]) -> String? {
        wanted.flatMap { w in files.contains(w) ? w : nil } ?? files.first
    }

    public var title: String {
        currentFile.map { "Conflicts in \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "No Conflicts"
    }

    public var fileNames: [String] { files.map { URL(fileURLWithPath: $0).lastPathComponent } }

    public var statusText: String {
        if let lastError { return lastError }
        guard let doc = document else { return source == .repository && files.isEmpty ? "All conflicts resolved" : "" }
        let n = doc.unresolvedCount
        if n == 0 { return doc.hunks.isEmpty ? "No differences" : "Resolved" }
        return "\(n) conflict\(n == 1 ? "" : "s") unresolved"
    }

    public var canMarkResolved: Bool {
        guard source == .repository, currentFile != nil, let doc = document else { return false }
        return doc.isResolved
    }

    public var hunkLabel: String {
        let total = document?.hunks.count ?? 0
        let noun = isComparingFiles && !hasBase ? "Difference" : "Change"
        if let doc = document, let h = currentHunk, total > 0 {
            return "\(noun) \(h + 1) of \(total)" + (doc.chunks[doc.hunks[h]].kind == .conflict ? " (conflict)" : "")
        }
        return total == 0 ? "No \(noun.lowercased())s" : "\(total) \(noun.lowercased())\(total == 1 ? "" : "s")"
    }

    public var hasHunks: Bool { !(document?.hunks.isEmpty ?? true) }

    public var currentIsConflict: Bool {
        guard let doc = document, let h = currentHunk else { return false }
        return doc.chunks[doc.hunks[h]].kind == .conflict
    }

    public var selectedSegment: Int? {
        guard let doc = document, let h = currentHunk else { return nil }
        switch doc.choices[h] {
        case .ours: return 0
        case .theirs: return 1
        case .oursThenTheirs: return 2
        case .theirsThenOurs: return 3
        case .base: return 4
        case .custom: return Self.editSegment
        case .unresolved: return nil
        }
    }

    public func isSegmentEnabled(_ i: Int) -> Bool { currentHunk != nil && (i != 4 || hasBase) }

    public var showsIntegrationButtons: Bool { source == .repository && integration.isInProgress }
    public var canContinue: Bool { showsIntegrationButtons && files.isEmpty }
    public var continueTitle: String { integration.verb.isEmpty ? "Continue" : "Continue \(integration.verb)" }
    public var abortTitle: String { integration.verb.isEmpty ? "Abort" : "Abort \(integration.verb)" }

    public var comparison: (old: String, new: String, oldTitle: String, newTitle: String) {
        guard let doc = document else { return ("", "", "", "") }
        return switch pair {
        case .leftRight: (doc.oursText, doc.theirsText, "Left: " + doc.oursLabel, "Right: " + doc.theirsLabel)
        case .baseLeft: (doc.baseText, doc.oursText, "Base: " + doc.baseLabel, "Left: " + doc.oursLabel)
        case .baseRight: (doc.baseText, doc.theirsText, "Base: " + doc.baseLabel, "Right: " + doc.theirsLabel)
        }
    }

    public var comparisonRows: [LineDiff.Row] {
        let c = comparison
        return LineDiff.sideBySide(LineDiff.diff(LineDiff.lines(c.old), LineDiff.lines(c.new)))
    }

    public func comparisonRow(in rows: [LineDiff.Row]) -> Int? {
        guard let doc = document, let h = currentHunk else { return nil }
        let starts = doc.sideStarts(forHunk: h)
        let leftStart = pair == .leftRight ? starts.ours : starts.base
        return rows.firstIndex { ($0.left?.number ?? 0) > leftStart } ?? 0
    }

    public struct ResultLine: Equatable, Sendable {
        public enum Tint: Equatable, Sendable { case none, unresolved, resolved }
        public var text: String
        public var hunk: Int?
        public var tint: Tint
        public var isSelected: Bool
    }

    public var resultLines: [ResultLine] {
        guard let doc = document else { return [] }
        let (lines, ranges) = doc.layout()
        var hunkOf: [Int: Int] = [:]
        for (h, r) in ranges.enumerated() { for l in r { hunkOf[l] = h } }
        return lines.enumerated().map { i, text in
            guard let h = hunkOf[i] else { return ResultLine(text: text, hunk: nil, tint: .none, isSelected: false) }
            return ResultLine(text: text, hunk: h, tint: doc.choices[h] == .unresolved ? .unresolved : .resolved, isSelected: h == currentHunk)
        }
    }

    public var resultStartLine: Int? {
        guard let doc = document, let h = currentHunk else { return nil }
        let ranges = doc.layout().hunkRanges
        return ranges.indices.contains(h) ? ranges[h].lowerBound : nil
    }
}
