import Foundation

public struct AssistCodeFunctions {
    public static func replaceBlock(in content: String, search: String, replace: String) -> String {
        return content.replacingOccurrences(of: search, with: replace)
    }

    public static func insertAfter(in content: String, pattern: String, insert: String) -> String {
        if let range = content.range(of: pattern) {
            var newContent = content
            newContent.insert(contentsOf: "\n" + insert, at: range.upperBound)
            return newContent
        }
        return content
    }

    public static func insertBefore(in content: String, pattern: String, insert: String) -> String {
        if let range = content.range(of: pattern) {
            var newContent = content
            newContent.insert(contentsOf: insert + "\n", at: range.lowerBound)
            return newContent
        }
        return content
    }
}
