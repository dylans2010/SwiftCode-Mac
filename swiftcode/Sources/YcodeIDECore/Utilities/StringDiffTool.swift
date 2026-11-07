import Foundation

public enum StringDiffTool {
    public static func simpleDiff(old: String, new: String, file: String = "file") -> String {
        MyersDiff.unifiedDiff(old: old, new: new, file: file, contextLines: 3)
    }
}
