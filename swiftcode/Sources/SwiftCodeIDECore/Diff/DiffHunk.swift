// Ported from Legacy `SwiftCode/Backend/Assist/AssistDiffEngine.swift` (commit d51a8f0d, Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-ma/assist-core/MANIFEST.md.
// Scope: `DiffHunk` ONLY. `UnifiedDiffResult`, `DiffConflictError`, and
// `AssistDiffEngine` are deliberately NOT ported — the ledger marks
// `AssistDiffEngine.swift` SUPERSEDED by `SwiftCodeIDECore/MyersDiff.swift`,
// and the staged `DiffEngine.swift` already adapts its return type to
// `MyersDiff.Result`. Resolves the `LiveFileEditEvent.hunks: [DiffHunk]`
// reference in staged `MyersDiffAlgorithm.swift`.
// NOTE: destination `GitDiffHunk` (`SwiftCodeSDK/Kits/SourceControlKit/GitDiffHunk.swift`)
// is NOT an equivalent — different shape (stored `header: String`, no
// old/new start/count) and it lives in SwiftCodeSDK, which SwiftCodeIDECore
// does not depend on.

import Foundation

public struct DiffHunk: Codable, Sendable, Identifiable {
    public let id: UUID
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [String]

    public init(id: UUID = UUID(), oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [String]) {
        self.id = id
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }

    public var header: String {
        return "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
    }
}
