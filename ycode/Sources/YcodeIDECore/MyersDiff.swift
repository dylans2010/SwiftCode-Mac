import Foundation

/// A real Myers diff (O(ND)) over lines, plus unified-diff rendering.
///
/// Behaviour source: Legacy's `AssistDiffEngine` /
/// `MyersDiffAlgorithm` (Dylan's own code, ported under MIT), which
/// renders unified diffs with 3 context lines and `@@ -a,b +c,d @@`
/// hunk headers. This is an original implementation of the published
/// Myers O(ND) algorithm (E. W. Myers, "An O(ND) Algorithm and its
/// Variations", Algorithmica 1986): the forward greedy search with a
/// stored V-trace, then backtracking to a minimal edit script. No
/// Legacy code is copied.
///
/// The previous Ycode diffs were positional (Wave 1
/// `file_compare_diff`, Wave 5 `EnginesPatch.unifiedDiff`): lines at
/// the same index were compared, so one inserted line made the whole
/// tail read as changed. This engine replaces them.
///
/// Limits, stated plainly: the trace stores one V-array per edit
/// distance, so memory is O(D^2) in the edit distance D. Inputs are
/// trimmed of their common prefix/suffix first (which keeps D tiny
/// for the usual near-identical files), and when D would exceed
/// `maxEditDistance` the result falls back to the old positional
/// diff with `usedFallback == true` instead of allocating
/// unboundedly. The fallback output is still a correct
/// (non-minimal) diff; callers that need minimality can check the
/// flag.
public enum MyersDiff {
    /// One step of an edit script.
    public enum Operation: Equatable, Sendable {
        /// A line present in both sides.
        case equal(String)
        /// A line present only in the old side.
        case delete(String)
        /// A line present only in the new side.
        case insert(String)
    }

    /// The result of diffing two line lists.
    public struct Result: Sendable {
        /// The minimal edit script (or the positional fallback's
        /// script when `usedFallback` is true).
        public var operations: [Operation]
        /// Inserted lines.
        public var added: Int
        /// Deleted lines.
        public var removed: Int
        /// True when the Myers search was abandoned for the
        /// positional fallback (edit distance above the cap).
        public var usedFallback: Bool

        public init(operations: [Operation], added: Int, removed: Int, usedFallback: Bool) {
            self.operations = operations
            self.added = added
            self.removed = removed
            self.usedFallback = usedFallback
        }
    }

    /// Largest edit distance the Myers search will pursue before
    /// falling back to the positional diff.
    public static let maxEditDistance = 4096

    /// Splits text into lines the way Legacy's diff does
    /// (`components(separatedBy: .newlines)`), except that empty text
    /// is zero lines, not one empty line: diffing an empty file
    /// against `"x\n"` is one insertion, not a deletion of a phantom
    /// empty line plus an insertion.
    public static func lines(of text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: .newlines)
    }

    /// A minimal edit script between two line lists.
    public static func diff(old: [String], new: [String]) -> Result {
        // Trim the common prefix and suffix: the Myers search then
        // runs only on the changed middle, which keeps D small for
        // near-identical files of any size.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let oldMid = Array(old[prefix..<(old.count - suffix)])
        let newMid = Array(new[prefix..<(new.count - suffix)])
        let mid = diffMiddle(old: oldMid, new: newMid)
        var operations: [Operation] = []
        operations.reserveCapacity(old.count + new.count)
        for line in old[..<prefix] { operations.append(.equal(line)) }
        operations += mid.operations
        for line in old[(old.count - suffix)...] { operations.append(.equal(line)) }
        return Result(operations: operations, added: mid.added, removed: mid.removed, usedFallback: mid.usedFallback)
    }

    /// The Myers search over the trimmed middle (no common
    /// prefix/suffix). Pure inserts/deletes short-circuit.
    private static func diffMiddle(old: [String], new: [String]) -> Result {
        if old.isEmpty {
            return Result(operations: new.map(Operation.insert), added: new.count, removed: 0, usedFallback: false)
        }
        if new.isEmpty {
            return Result(operations: old.map(Operation.delete), added: 0, removed: old.count, usedFallback: false)
        }
        let n = old.count, m = new.count
        let max = n + m
        // V[k] is the furthest x reached on diagonal k (x - y = k),
        // stored offset by max so k = -max...max indexes 0...2*max.
        var trace: [[Int]] = []
        trace.reserveCapacity(min(max, maxEditDistance) + 1)
        var v = [Int](repeating: 0, count: 2 * max + 1)
        var foundD: Int?
        outer: for d in 0...max {
            if d > maxEditDistance { break }
            trace.append(v)
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max]) {
                    x = v[k + 1 + max] // down: insertion
                } else {
                    x = v[k - 1 + max] + 1 // right: deletion
                }
                var y = x - k
                while x < n, y < m, old[x] == new[y] { x += 1; y += 1 }
                v[k + max] = x
                if x >= n, y >= m { foundD = d; break outer }
                k += 2
            }
        }
        guard let d = foundD else { return positional(old: old, new: new) }
        // Backtrack through the stored trace to recover the script.
        var operations: [Operation] = []
        var x = n, y = m
        for back in stride(from: d, through: 1, by: -1) {
            let vPrev = trace[back]
            let k = x - y
            let prevK: Int
            if k == -back || (k != back && vPrev[k - 1 + max] < vPrev[k + 1 + max]) {
                prevK = k + 1 // came down: the step was an insertion
            } else {
                prevK = k - 1 // came right: the step was a deletion
            }
            let prevX = vPrev[prevK + max]
            let prevY = prevX - prevK
            while x > prevX, y > prevY {
                operations.append(.equal(old[x - 1]))
                x -= 1; y -= 1
            }
            if x == prevX {
                operations.append(.insert(new[y - 1]))
                y -= 1
            } else {
                operations.append(.delete(old[x - 1]))
                x -= 1
            }
        }
        while x > 0, y > 0 {
            operations.append(.equal(old[x - 1]))
            x -= 1; y -= 1
        }
        operations.reverse()
        var insertCount = 0, deleteCount = 0
        for op in operations {
            if case .insert = op { insertCount += 1 }
            if case .delete = op { deleteCount += 1 }
        }
        return Result(operations: operations, added: insertCount, removed: deleteCount, usedFallback: false)
    }

    /// The old positional diff (same-index comparison), kept only as
    /// the fallback when the Myers search exceeds its edit-distance
    /// cap. A changed line is one deletion plus one insertion.
    static func positional(old: [String], new: [String]) -> Result {
        var operations: [Operation] = []
        var added = 0, removed = 0
        for i in 0..<max(old.count, new.count) {
            let o = i < old.count ? old[i] : nil
            let n = i < new.count ? new[i] : nil
            if let o, let n {
                if o == n { operations.append(.equal(o)) } else {
                    operations.append(.delete(o)); operations.append(.insert(n))
                    removed += 1; added += 1
                }
            } else if let o {
                operations.append(.delete(o)); removed += 1
            } else if let n {
                operations.append(.insert(n)); added += 1
            }
        }
        return Result(operations: operations, added: added, removed: removed, usedFallback: true)
    }

    /// The edit distance (insertions + deletions) between two line
    /// lists: the minimal number of line edits, or nil when the
    /// search exceeds the cap (the fallback's distance is not
    /// minimal, so no number is reported).
    public static func editDistance(old: [String], new: [String]) -> Int? {
        let r = diff(old: old, new: new)
        return r.usedFallback ? nil : r.added + r.removed
    }

    /// Renders `diff(old:new:)` as a unified diff: `--- a/<file>` /
    /// `+++ b/<file>` headers, `@@ -a,b +c,d @@` hunk headers (Legacy's
    /// always-with-counts form), `contextLines` lines of context
    /// (Legacy: 3) around each change, ` ` / `-` / `+` line prefixes.
    /// An identical pair renders only the two headers.
    public static func unifiedDiff(old: String, new: String, file: String, contextLines: Int = 3) -> String {
        let r = diff(old: lines(of: old), new: lines(of: new))
        return unifiedDiff(result: r, file: file, contextLines: contextLines)
    }

    /// Unified rendering of an already-computed diff result.
    public static func unifiedDiff(result: Result, file: String, contextLines: Int = 3) -> String {
        unifiedDiff(result: result, oldFile: file, newFile: file, contextLines: contextLines)
    }

    /// Unified rendering with different old/new file labels (a
    /// two-file comparison: `--- a/<oldFile>`, `+++ b/<newFile>`).
    public static func unifiedDiff(result: Result, oldFile: String, newFile: String, contextLines: Int = 3) -> String {
        var out = ["--- a/\(oldFile)", "+++ b/\(newFile)"]
        let ops = result.operations
        // Hunk boundaries: a change, plus contextLines of equal lines
        // on each side; an equal run longer than 2 * contextLines
        // splits the hunk, shorter runs stay inside it (so nearby
        // changes merge into one hunk).
        var hunks: [(start: Int, end: Int)] = []
        var i = 0
        while i < ops.count {
            if isEqual(ops[i]) { i += 1; continue }
            // Walk forward from this change: equal runs of at most
            // 2 * contextLines stay inside the hunk; longer runs end it.
            var k = i
            var lastChange = i
            while k < ops.count {
                if isEqual(ops[k]) {
                    var runEnd = k
                    while runEnd < ops.count, isEqual(ops[runEnd]) { runEnd += 1 }
                    if runEnd - k > 2 * contextLines { break }
                    k = runEnd
                } else {
                    lastChange = k
                    k += 1
                }
            }
            let hunkStart = max(0, i - contextLines)
            let hunkEnd = min(ops.count, lastChange + 1 + contextLines)
            if let last = hunks.last, hunkStart <= last.end {
                hunks[hunks.count - 1] = (last.start, max(last.end, hunkEnd))
            } else {
                hunks.append((hunkStart, hunkEnd))
            }
            i = hunkEnd
        }
        for hunk in hunks {
            var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0
            for idx in 0..<hunk.start {
                switch ops[idx] {
                case .equal: oldStart += 1; newStart += 1
                case .delete: oldStart += 1
                case .insert: newStart += 1
                }
            }
            var body: [String] = []
            for idx in hunk.start..<hunk.end {
                switch ops[idx] {
                case .equal(let line): body.append(" \(line)"); oldCount += 1; newCount += 1
                case .delete(let line): body.append("-\(line)"); oldCount += 1
                case .insert(let line): body.append("+\(line)"); newCount += 1
                }
            }
            // A zero-count side starts at the line before the hunk
            // (GNU convention: `-0,0` for an insertion at the start);
            // otherwise starts are 1-based.
            let oldHeader = oldCount == 0 ? oldStart : oldStart + 1
            let newHeader = newCount == 0 ? newStart : newStart + 1
            out.append("@@ -\(oldHeader),\(oldCount) +\(newHeader),\(newCount) @@")
            out += body
        }
        return out.joined(separator: "\n")
    }

    private static func isEqual(_ op: Operation) -> Bool {
        if case .equal = op { return true }
        return false
    }
}
