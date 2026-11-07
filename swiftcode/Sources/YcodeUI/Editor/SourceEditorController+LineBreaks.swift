import AppKit
import YcodeIDECore

extension SourceEditorController: NSTextLayoutManagerDelegate {
    public nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation,
                                              hyphenating: Bool) -> Bool {
        guard let storage = (textLayoutManager.textContentManager as? NSTextContentStorage)?.textStorage,
              let width = textLayoutManager.textContainer?.size.width else { return true }
        let advance = wrapSnapshot.advance
        guard advance > 0, width.isFinite, width < 100_000 else { return true }
        let offset = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
        return EditorLineBreaks.allowsBreak(before: offset, in: storage.string as NSString, columns: Int(width / advance))
    }
}

public enum EditorLineBreaks {
    public static func allowsBreak(before offset: Int, in text: NSString, columns: Int) -> Bool {
        guard offset > 0, offset < text.length, columns > 0 else { return true }
        func isSpace(_ u: unichar) -> Bool { u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D }
        guard !isSpace(text.character(at: offset)), isSpace(text.character(at: offset - 1)) else { return true }
        var end = offset
        while end < text.length, !isSpace(text.character(at: end)), end - offset <= columns { end += 1 }
        return end - offset <= columns
    }
}
