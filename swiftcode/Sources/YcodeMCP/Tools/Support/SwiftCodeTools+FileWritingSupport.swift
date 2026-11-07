import Foundation
import YcodeIDECore

enum FileWritingSupport {
    static func unifiedDiff(old: String?, new: String, file: String) -> String {
        MyersDiff.unifiedDiff(old: old ?? "", new: new, file: file)
    }

    static func diffCounts(old: String?, new: String) -> (added: Int, removed: Int) {
        let result = MyersDiff.diff(old: MyersDiff.lines(of: old ?? ""), new: MyersDiff.lines(of: new))
        return (result.added, result.removed)
    }
}
