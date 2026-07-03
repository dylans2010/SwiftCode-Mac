import Foundation

public enum StringDiffTool {
    public static func simpleDiff(old: String, new: String) -> String {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        let hunks = MyersDiffAlgorithm.shared.diff(old: oldLines, new: newLines)
        return hunks.map { hunk in
            "\(hunk.header)\n\(hunk.lines.joined(separator: "\n"))"
        }.joined(separator: "\n")
    }
}
