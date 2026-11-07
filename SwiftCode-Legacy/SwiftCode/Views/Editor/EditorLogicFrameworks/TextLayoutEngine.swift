import AppKit

@MainActor
final class TextLayoutEngine {
    static let shared = TextLayoutEngine()
    private init() {}

    static func editorFont(size: CGFloat = 14) -> NSFont {
        NSFont(name: "Menlo", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func lineHeight(fontSize: CGFloat = 14) -> CGFloat {
        editorFont(size: fontSize).ascender - editorFont(size: fontSize).descender + editorFont(size: fontSize).leading
    }

    static func paragraphStyle(fontSize: CGFloat = 14) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let h = lineHeight(fontSize: fontSize)
        style.minimumLineHeight = h
        style.maximumLineHeight = h
        style.lineSpacing = 0
        return style
    }

    static let lineNumberColumnWidth: CGFloat = 50

    static func textContainerInset(topPadding: CGFloat = 8) -> NSSize {
        NSSize(width: 10, height: topPadding)
    }

    static func yPosition(forLine line: Int, fontSize: CGFloat = 14, topInset: CGFloat = 8) -> CGFloat {
        topInset + CGFloat(line - 1) * lineHeight(fontSize: fontSize)
    }

    static func lineCount(in text: String) -> Int {
        max(1, text.components(separatedBy: "\n").count)
    }

    static func expandTabs(_ text: String, tabWidth: Int = 4) -> String {
        text.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth))
    }

    static func leadingWhitespace(of line: String) -> String {
        var result = ""
        for ch in line {
            guard ch == " " || ch == "\t" else { break }
            result.append(ch)
        }
        return result
    }

    static func codeColumnWidth(
        totalWidth: CGFloat,
        minimapWidth: CGFloat = 0
    ) -> CGFloat {
        max(totalWidth - lineNumberColumnWidth - minimapWidth, 200)
    }
}
