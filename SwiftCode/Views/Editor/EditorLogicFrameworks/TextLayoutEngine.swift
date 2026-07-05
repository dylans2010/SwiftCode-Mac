import UIKit

// MARK: - Text Layout Engine
// Centralises all text layout constants and helpers used by the code editor.
// Provides consistent line height, indentation, tab rendering,
// cursor placement, and wrapping logic so the editor behaves like a real IDE.

final class TextLayoutEngine {
    static let shared = TextLayoutEngine()
    private init() {}

    // MARK: - Font

    /// Returns the standard monospaced editor font for a given size.
    static func editorFont(size: CGFloat = 14) -> UIFont {
        UIFont(name: "Menlo", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Line Height

    /// Returns the consistent line height for the editor font at the given size.
    /// All layout calculations (line numbers, scrolling, cursor) must use this value.
    static func lineHeight(fontSize: CGFloat = 14) -> CGFloat {
        editorFont(size: fontSize).lineHeight.rounded(.up)
    }

    // MARK: - Paragraph Style

    /// Returns a paragraph style that enforces a consistent line height.
    /// Applying this style prevents vertical misalignment between the line
    /// number column and the code column.
    static func paragraphStyle(fontSize: CGFloat = 14) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let h = lineHeight(fontSize: fontSize)
        style.minimumLineHeight = h
        style.maximumLineHeight = h
        style.lineSpacing = 0
        return style
    }

    // MARK: - Line Number Column

    /// Fixed width of the line number gutter (points).
    static let lineNumberColumnWidth: CGFloat = 50

    // MARK: - Text Container Insets

    /// Insets applied to the editable UITextView.  The left inset ensures the
    /// first character never touches the line-number/gutter boundary.
    static func textContainerInset(topPadding: CGFloat = 8) -> UIEdgeInsets {
        UIEdgeInsets(top: topPadding, left: 10, bottom: 12, right: 12)
    }

    // MARK: - Y Position for a Line

    /// Returns the Y origin (in the text view's coordinate space) for a given
    /// 1-based line number.  The value accounts for the top inset used by the
    /// text view so the line number gutter can draw numbers at the same Y.
    static func yPosition(forLine line: Int, fontSize: CGFloat = 14, topInset: CGFloat = 8) -> CGFloat {
        topInset + CGFloat(line - 1) * lineHeight(fontSize: fontSize)
    }

    // MARK: - Line Count

    /// Returns the number of lines in a text string.
    static func lineCount(in text: String) -> Int {
        max(1, text.components(separatedBy: "\n").count)
    }

    // MARK: - Tab Rendering

    /// Expands tab characters into a consistent number of spaces so indentation
    /// renders identically regardless of platform tab-stop settings.
    static func expandTabs(_ text: String, tabWidth: Int = 4) -> String {
        text.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth))
    }

    // MARK: - Auto-Indent

    /// Returns the leading whitespace of a given line (used for auto-indent on
    /// newline insertion).
    static func leadingWhitespace(of line: String) -> String {
        var result = ""
        for ch in line {
            guard ch == " " || ch == "\t" else { break }
            result.append(ch)
        }
        return result
    }

    // MARK: - Wrapping Width

    /// Calculates the usable content width for the editable code region,
    /// subtracting the line number gutter and any additional margin guard
    /// (e.g. for an overlay such as a minimap or search button).
    static func codeColumnWidth(
        totalWidth: CGFloat,
        minimapWidth: CGFloat = 0
    ) -> CGFloat {
        max(totalWidth - lineNumberColumnWidth - minimapWidth, 200)
    }
}
