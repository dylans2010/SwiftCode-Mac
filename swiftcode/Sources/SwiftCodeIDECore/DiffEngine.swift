// Ported from Legacy `SwiftCode/Frameworks/Diff/DiffEngine.swift` (commit d51a8f0d, Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See _fragments/reverse-diff-MANIFEST.md.
// ADAPTATION: Legacy delegated to `MyersDiffAlgorithm.shared.diff(old:new:)`
// returning `[GitDiffHunk]`. Neither type exists in SwiftCodeIDECore:
// `MyersDiffAlgorithm` was already ported as `MyersDiff`
// (swiftcode/Sources/SwiftCodeIDECore/MyersDiff.swift), and `GitDiffHunk`
// lives only in SwiftCodeSDK, which SwiftCodeIDECore does not depend on.
// This port therefore delegates to `MyersDiff.diff(old:new:)` and returns
// its `MyersDiff.Result` (minimal edit script plus added/removed counts) —
// the destination's equivalent of the Legacy `[GitDiffHunk]` result.
// The actor shape, `shared` singleton, and async `computeDiff` signature
// are preserved from Legacy.

import Foundation

public actor DiffEngine {
    public static let shared = DiffEngine()

    public func computeDiff(old: [String], new: [String]) async -> MyersDiff.Result {
        MyersDiff.diff(old: old, new: new)
    }
}
