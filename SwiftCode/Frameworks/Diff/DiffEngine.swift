import Foundation

public actor DiffEngine {
    public static let shared = DiffEngine()

    public func computeDiff(old: [String], new: [String]) async -> [GitDiffHunk] {
        return MyersDiffAlgorithm.shared.diff(old: old, new: new)
    }
}
