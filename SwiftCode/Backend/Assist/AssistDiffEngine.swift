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

    /// Computes a unified diff between two string versions of a file.
    public func createUnifiedDiff(filePath: String, oldContent: String, newContent: String) -> UnifiedDiffResult {
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")

        let diff = computeLineDifferences(oldLines: oldLines, newLines: newLines)

        var hunks: [DiffHunk] = []
        var totalAdded = 0
        var totalRemoved = 0

        var currentHunkLines: [String] = []
        var oldStart = 1
        var newStart = 1
        var oldCount = 0
        var newCount = 0

        for item in diff {
            switch item {
            case .unchanged(let line):
                if !currentHunkLines.isEmpty {
                    // Include up to 3 lines of trailing context
                    currentHunkLines.append(" " + line)
                    oldCount += 1
                    newCount += 1
                    if currentHunkLines.filter({ $0.hasPrefix(" ") }).count >= 3 {
                        hunks.append(DiffHunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: currentHunkLines))
                        currentHunkLines = []
                        oldCount = 0
                        newCount = 0
                    }
                }
            case .addition(let line):
                if currentHunkLines.isEmpty {
                    oldStart = max(1, oldCount)
                    newStart = max(1, newCount)
                }
                currentHunkLines.append("+" + line)
                newCount += 1
                totalAdded += 1
            case .deletion(let line):
                if currentHunkLines.isEmpty {
                    oldStart = max(1, oldCount)
                    newStart = max(1, newCount)
                }
                currentHunkLines.append("-" + line)
                oldCount += 1
                totalRemoved += 1
            }
        }

        if !currentHunkLines.isEmpty {
            hunks.append(DiffHunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: currentHunkLines))
        }

        var text = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        if hunks.isEmpty {
            text += "(No changes detected)"
        } else {
            for hunk in hunks {
                text += hunk.header + "\n"
                for line in hunk.lines {
                    text += line + "\n"
                }
            }
        }

        return UnifiedDiffResult(
            filePath: filePath,
            hunks: hunks,
            addedLines: totalAdded,
            removedLines: totalRemoved,
            unifiedText: text
        )
    }

    /// Convenience helper returning the unified diff string directly.
    public func generateUnifiedDiff(filePath: String, original: String, modified: String) -> String {
        return createUnifiedDiff(filePath: filePath, oldContent: original, newContent: modified).unifiedText
    }

    /// Validates a targeted replacement and executes it safely, raising an error if target is missing or ambiguous.
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

    /// Validates a targeted replacement with optional multiple-replacement allowance.
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

    private enum DiffItem {
        case unchanged(String)
        case addition(String)
        case deletion(String)
    }

    private func computeLineDifferences(oldLines: [String], newLines: [String]) -> [DiffItem] {
        var items: [DiffItem] = []

        var i = 0
        var j = 0

        while i < oldLines.count && j < newLines.count {
            if oldLines[i] == newLines[j] {
                items.append(.unchanged(oldLines[i]))
                i += 1
                j += 1
            } else {
                // Lookahead to find match
                let matchInNew = (j..<min(j + 5, newLines.count)).firstIndex(where: { newLines[$0] == oldLines[i] })
                let matchInOld = (i..<min(i + 5, oldLines.count)).firstIndex(where: { oldLines[$0] == newLines[j] })

                if let foundNew = matchInNew {
                    while j < foundNew {
                        items.append(.addition(newLines[j]))
                        j += 1
                    }
                } else if let foundOld = matchInOld {
                    while i < foundOld {
                        items.append(.deletion(oldLines[i]))
                        i += 1
                    }
                } else {
                    items.append(.deletion(oldLines[i]))
                    items.append(.addition(newLines[j]))
                    i += 1
                    j += 1
                }
            }
        }

        while i < oldLines.count {
            items.append(.deletion(oldLines[i]))
            i += 1
        }

        while j < newLines.count {
            items.append(.addition(newLines[j]))
            j += 1
        }

        return items
    }
}
