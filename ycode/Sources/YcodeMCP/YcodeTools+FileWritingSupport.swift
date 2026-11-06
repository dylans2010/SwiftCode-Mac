import Foundation
import YcodeIDECore

/// Shared helpers for the ported Legacy file-writing tool family
/// (Wave 2), added by the correctness gap closure.
///
/// The family renders Legacy's unified (Myers) diffs for the writes
/// that report one: `file_create`, `code_replace`, and (via the
/// coordinator-owned patch) `file_write`. The engine is
/// `MyersDiff` (YcodeIDECore); these helpers are only the family's
/// calling convention — `old == nil` is a new file, rendered as an
/// all-insertion diff — so the three call sites cannot drift apart.
enum FileWritingSupport {
    /// Legacy's unified diff for one write: `old` is the file's
    /// previous text (nil: the file did not exist), `new` is the
    /// text being written, `file` is the workspace-relative path
    /// used in the `--- a/…` / `+++ b/…` headers.
    static func unifiedDiff(old: String?, new: String, file: String) -> String {
        MyersDiff.unifiedDiff(old: old ?? "", new: new, file: file)
    }

    /// (added, removed) line counts for one write, from the same
    /// minimal edit script the diff renders.
    static func diffCounts(old: String?, new: String) -> (added: Int, removed: Int) {
        let result = MyersDiff.diff(old: MyersDiff.lines(of: old ?? ""), new: MyersDiff.lines(of: new))
        return (result.added, result.removed)
    }
}
