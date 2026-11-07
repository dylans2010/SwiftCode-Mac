import Foundation

public actor DiffEngine {
    public static let shared = DiffEngine()

    public func computeDiff(old: [String], new: [String]) async -> MyersDiff.Result {
        MyersDiff.diff(old: old, new: new)
    }
}
