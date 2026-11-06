import Foundation

/// Line-based string diff, rendered as a unified diff.
///
/// Ported from Legacy's `StringDiffTool`. Legacy rendered the hunks of its
/// own `MyersDiffAlgorithm`; Ycode already has the same engine as
/// `MyersDiff` (`ycode/Sources/YcodeIDECore/MyersDiff.swift`, landed by
/// gap-closure), so this renders through `MyersDiff.unifiedDiff` instead:
/// `--- a/<file>` / `+++ b/<file>` headers, `@@ -a,b +c,d @@` hunk headers,
/// 3 lines of context, ` ` / `-` / `+` prefixes — the same output shape
/// Legacy's hunks had.
public enum StringDiffTool {
    /// Unified diff of `old` vs `new`, labelled with `file` in both headers.
    public static func simpleDiff(old: String, new: String, file: String = "file") -> String {
        MyersDiff.unifiedDiff(old: old, new: new, file: file, contextLines: 3)
    }
}
