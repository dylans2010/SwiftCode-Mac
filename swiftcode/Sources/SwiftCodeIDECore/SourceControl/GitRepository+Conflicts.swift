import Foundation

extension GitRepository {
    public struct ConflictSides: Equatable, Sendable {
        public var base: String?
        public var ours: String?
        public var theirs: String?
        public var oursLabel: String
        public var theirsLabel: String
    }

    public func conflictLabels(_ state: IntegrationState? = nil) -> (ours: String, theirs: String) {
        let current = currentBranch() ?? headHash().map { String($0.prefix(7)) } ?? "HEAD"
        switch state ?? integrationState() {
        case .merging(let branch): return (current, branch)
        case .rebasing(let branch, let onto, _, _): return (onto.isEmpty ? "Upstream" : onto, branch.isEmpty ? "Rebased commit" : branch)
        case .cherryPicking(let c): return (current, String(c.prefix(7)))
        case .reverting(let c): return (current, "Revert of " + String(c.prefix(7)))
        case .none: return (current, "Stashed changes")
        }
    }

    public func conflictSides(of path: String) -> ConflictSides? {
        guard let rel = relative(path) else { return nil }
        let text = (try? git(["ls-files", "-u", "-z", "--", rel])) ?? ""
        var stages = Set<Int>()
        for entry in text.split(separator: "\0") {
            let meta = entry.split(separator: "\t", maxSplits: 1).first ?? ""
            if let s = meta.split(separator: " ").last.flatMap({ Int($0) }) { stages.insert(s) }
        }
        guard !stages.isEmpty else { return nil }
        func stage(_ n: Int) -> String? { stages.contains(n) ? (try? git(["show", ":\(n):" + rel])) : nil }
        let labels = conflictLabels()
        return ConflictSides(base: stage(1), ours: stage(2), theirs: stage(3), oursLabel: labels.ours, theirsLabel: labels.theirs)
    }

    public func mergeDocument(forConflictedFile path: String) -> MergeDocument? {
        if let s = conflictSides(of: path) {
            return MergeDocument(base: s.base ?? "", ours: s.ours ?? "", theirs: s.theirs ?? "",
                                 oursLabel: s.oursLabel + (s.ours == nil ? " (deleted)" : ""),
                                 theirsLabel: s.theirsLabel + (s.theirs == nil ? " (deleted)" : ""))
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let parsed = ConflictMarkers.parse(text),
              parsed.chunks.contains(where: { $0.kind == .conflict }) else { return nil }
        return MergeDocument(chunks: parsed.chunks, oursLabel: parsed.oursLabel ?? "Ours", theirsLabel: parsed.theirsLabel ?? "Theirs")
    }

    public func resolveConflict(_ path: String, text: String) throws {
        guard relative(path) != nil else { throw GitError(description: "\(path) is outside the repository") }
        if ConflictMarkers.hasConflicts(text) { throw GitError(description: "The file still has conflict markers.") }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        try markResolved([path])
    }

    public func resolveConflictByDeleting(_ path: String) throws {
        guard let rel = relative(path) else { throw GitError(description: "\(path) is outside the repository") }
        if FileManager.default.fileExists(atPath: path) { try Trash.move(URL(fileURLWithPath: path)) }
        _ = try git(["rm", "-q", "--cached", "--", rel])
    }
}
