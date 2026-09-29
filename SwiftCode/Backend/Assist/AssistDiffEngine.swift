import Foundation

// MARK: - Assist v3 Unified Diff Engine

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

public struct UnifiedDiffResult: Codable, Sendable {
    public let filePath: String
    public let hunks: [DiffHunk]
    public let addedLines: Int
    public let removedLines: Int
    public let unifiedText: String

    public var hasChanges: Bool {
        return addedLines > 0 || removedLines > 0
    }

    public init(filePath: String, hunks: [DiffHunk], addedLines: Int, removedLines: Int, unifiedText: String) {
        self.filePath = filePath
        self.hunks = hunks
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.unifiedText = unifiedText
    }
}

public enum DiffConflictError: Error, LocalizedError, Sendable {
    case targetNotFound(target: String, file: String)
    case multipleMatches(target: String, count: Int, file: String)
    case staleFileState(file: String)

    public var errorDescription: String? {
        switch self {
        case .targetNotFound(let target, let file):
            let preview = target.count > 60 ? String(target.prefix(60)) + "..." : target
            return "Target text '\(preview)' was not found in \(file). Verify current file contents before editing."
        case .multipleMatches(let target, let count, let file):
            let preview = target.count > 60 ? String(target.prefix(60)) + "..." : target
            return "Target text '\(preview)' matched \(count) locations in \(file). Provide more surrounding context to disambiguate."
        case .staleFileState(let file):
            return "File \(file) state changed unexpectedly on disk during operation."
        }
    }
}

public final class AssistDiffEngine: Sendable {
    public static let shared = AssistDiffEngine()

    public init() {}

    public func createUnifiedDiff(filePath: String, oldContent: String, newContent: String) -> UnifiedDiffResult {
        return MyersDiffAlgorithm.shared.computeUnifiedDiff(filePath: filePath, oldContent: oldContent, newContent: newContent, contextLines: 3)
    }

    public func generateUnifiedDiff(filePath: String, original: String, modified: String) -> String {
        return createUnifiedDiff(filePath: filePath, oldContent: original, newContent: modified).unifiedText
    }

    public func applyTargetedReplacement(
        filePath: String,
        originalContent: String,
        targetContent: String,
        replacementContent: String
    ) throws -> (modifiedContent: String, diffResult: UnifiedDiffResult) {
        let occurrences = originalContent.components(separatedBy: targetContent).count - 1

        if occurrences == 0 {
            throw DiffConflictError.targetNotFound(target: targetContent, file: filePath)
        }
        if occurrences > 1 {
            throw DiffConflictError.multipleMatches(target: targetContent, count: occurrences, file: filePath)
        }

        let modified = originalContent.replacingOccurrences(of: targetContent, with: replacementContent)
        let diff = createUnifiedDiff(filePath: filePath, oldContent: originalContent, newContent: modified)

        return (modified, diff)
    }

    public func applyTargetedReplacement(
        source: String,
        target: String,
        replacement: String,
        allowMultiple: Bool = false,
        filePath: String = "file"
    ) throws -> String {
        let occurrences = source.components(separatedBy: target).count - 1

        if occurrences == 0 {
            throw DiffConflictError.targetNotFound(target: target, file: filePath)
        }
        if occurrences > 1 && !allowMultiple {
            throw DiffConflictError.multipleMatches(target: target, count: occurrences, file: filePath)
        }

        return source.replacingOccurrences(of: target, with: replacement)
    }

    public func computeMultiFileDiff(files: [(filePath: String, oldContent: String, newContent: String)]) -> [UnifiedDiffResult] {
        return files.map { file in
            createUnifiedDiff(filePath: file.filePath, oldContent: file.oldContent, newContent: file.newContent)
        }
    }

    public func generateMultiFileUnifiedText(results: [UnifiedDiffResult]) -> String {
        return results.map { $0.unifiedText }.joined(separator: "\n")
    }

    public func createFileActivityItem(
        filePath: String,
        operation: String,
        oldContent: String,
        newContent: String
    ) -> FileActivityItem {
        let diff = createUnifiedDiff(filePath: filePath, oldContent: oldContent, newContent: newContent)
        let hunkStrings = diff.hunks.map { hunk in
            ([hunk.header] + hunk.lines).joined(separator: "\n")
        }
        return FileActivityItem(
            filePath: filePath,
            operation: operation,
            addedLines: diff.addedLines,
            deletedLines: diff.removedLines,
            diffSummary: diff.unifiedText,
            diffHunks: hunkStrings,
            isReconciled: true
        )
    }
}
