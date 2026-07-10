import Foundation
import SwiftUI
import os.log

#if canImport(Splash)
import Splash
#endif

#if canImport(AppKit)
import AppKit
public typealias RenderColor = NSColor
#else
import UIKit
public typealias RenderColor = UIColor
#endif

/// A token representing a syntactic construct in the source code.
public struct HighlightToken: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let range: NSRange
    public let kind: SyntaxTokenKind
    public let text: String
}

/// Dynamic theme configuration for the CodeRenderEngine.
public struct RenderTheme: Sendable, Hashable {
    public let background: RenderColor
    public let defaultText: RenderColor
    public let keyword: RenderColor
    public let function: RenderColor
    public let variable: RenderColor
    public let type: RenderColor
    public let comment: RenderColor
    public let string: RenderColor
    public let number: RenderColor
    public let attribute: RenderColor
    public let preprocessor: RenderColor
    public let operatorColor: RenderColor
    public let macro: RenderColor
    public let error: RenderColor
    public let placeholder: RenderColor
    public let todo: RenderColor

    public init(
        background: RenderColor,
        defaultText: RenderColor,
        keyword: RenderColor,
        function: RenderColor,
        variable: RenderColor,
        type: RenderColor,
        comment: RenderColor,
        string: RenderColor,
        number: RenderColor,
        attribute: RenderColor,
        preprocessor: RenderColor,
        operatorColor: RenderColor,
        macro: RenderColor,
        error: RenderColor,
        placeholder: RenderColor,
        todo: RenderColor
    ) {
        self.background = background
        self.defaultText = defaultText
        self.keyword = keyword
        self.function = function
        self.variable = variable
        self.type = type
        self.comment = comment
        self.string = string
        self.number = number
        self.attribute = attribute
        self.preprocessor = preprocessor
        self.operatorColor = operatorColor
        self.macro = macro
        self.error = error
        self.placeholder = placeholder
        self.todo = todo
    }

    public static let standardDark = RenderTheme(
        background: RenderColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        defaultText: RenderColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
        keyword: RenderColor(red: 0.99, green: 0.37, blue: 0.53, alpha: 1),
        function: RenderColor(red: 0.67, green: 0.85, blue: 0.33, alpha: 1),
        variable: RenderColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1),
        type: RenderColor(red: 0.35, green: 0.82, blue: 0.98, alpha: 1),
        comment: RenderColor(red: 0.42, green: 0.68, blue: 0.42, alpha: 1),
        string: RenderColor(red: 0.99, green: 0.41, blue: 0.36, alpha: 1),
        number: RenderColor(red: 0.82, green: 0.68, blue: 1.0, alpha: 1),
        attribute: RenderColor(red: 0.99, green: 0.58, blue: 0.23, alpha: 1),
        preprocessor: RenderColor(red: 0.99, green: 0.58, blue: 0.23, alpha: 1),
        operatorColor: RenderColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
        macro: RenderColor(red: 1.0, green: 0.45, blue: 0.85, alpha: 1),
        error: RenderColor.red,
        placeholder: RenderColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1),
        todo: RenderColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
    )
}

/// A syntax-highlighted attributed string that can be passed between actors.
///
/// `NSAttributedString` is immutable after initialization and the render engine only stores immutable
/// copies in this wrapper, making cross-actor transfer safe for the UI to enumerate later.
public struct HighlightedAttributedContent: @unchecked Sendable {
    public let attributedString: NSAttributedString

    public init(_ attributedString: NSAttributedString) {
        self.attributedString = NSAttributedString(attributedString: attributedString)
    }
}

/// The centralized, high-performance rendering engine subsystem.
public actor CodeRenderEngine {
    public static let shared = CodeRenderEngine()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "CodeRenderEngine")

    // Caches to avoid O(N) re-parsing / re-rendering
    private var tokenCache: [String: [HighlightToken]] = [:]
    private var highlightedCache: [String: HighlightedAttributedContent] = [:]

    private init() {}

    /// Detect language from filename or file path.
    public func detectLanguage(from url: URL) -> SourceLanguage {
        SourceLanguage.from(url: url)
    }

    /// Main background parsing API. Generates and caches tokens for a file.
    public func parseAndHighlight(
        _ text: String,
        language: SourceLanguage,
        theme: RenderTheme = .standardDark
    ) -> HighlightedAttributedContent {
        let cacheKey = "\(text.hashValue)-\(language.rawValue)-\(theme.hashValue)"

        if let cached = highlightedCache[cacheKey] {
            return cached
        }

        let attributed = HighlightedAttributedContent(highlightContent(text, language: language, theme: theme))
        highlightedCache[cacheKey] = attributed

        // Trim cache to prevent memory bloat
        if highlightedCache.count > 100, let oldestCacheKey = highlightedCache.keys.first {
            highlightedCache.removeValue(forKey: oldestCacheKey)
        }

        return attributed
    }

    /// Low-level highlighting logic. Combines Splash syntax engine
    /// and fallback high-precision regex matching patterns.
    private func highlightContent(
        _ text: String,
        language: SourceLanguage,
        theme: RenderTheme
    ) -> NSAttributedString {
        #if canImport(Splash)
        if language == .swift {
            let font = Splash.Font(size: 13)
            let splashTheme = Splash.Theme.midnight(withFont: font)
            let highlighter = Splash.SyntaxHighlighter(format: AttributedStringOutputFormat(theme: splashTheme))
            let result = highlighter.highlight(text)

            // Adjust paragraph line spacing on the returned attributed string
            let mutable = NSMutableAttributedString(attributedString: result)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutable.length))
            return mutable
        }
        #endif

        // High-precision custom regex-based highlighter fallback (used for other languages like JSON/Markdown)
        let font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)

        attributed.addAttributes([
            .font: font,
            .foregroundColor: theme.defaultText,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)

        // Skip tokenizing for plain text
        guard language != .plainText else {
            return attributed
        }

        // Compile Regex patterns for high fidelity syntax coloring
        let patterns = compilePatterns(for: language, theme: theme)

        for entry in patterns {
            let matches = entry.regex.matches(in: text, range: fullRange)
            for match in matches {
                let captureGroup = entry.captureGroup
                let range = match.numberOfRanges > captureGroup ? match.range(at: captureGroup) : match.range
                guard range.location != NSNotFound else { continue }

                // SAFETY: Direct bounds check to ensure no out-of-bounds crash on modification
                // Invariant: range must lie strictly within string length bounds
                if range.location + range.length <= text.utf16.count {
                    attributed.addAttribute(.foregroundColor, value: entry.color, range: range)
                }
            }
        }

        return attributed
    }

    private struct CompiledPattern {
        let regex: NSRegularExpression
        let captureGroup: Int
        let color: RenderColor
    }

    private func compilePatterns(for language: SourceLanguage, theme: RenderTheme) -> [CompiledPattern] {
        var patterns: [CompiledPattern] = []

        func add(_ pattern: String, color: RenderColor, captureGroup: Int = 0, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                patterns.append(CompiledPattern(regex: regex, captureGroup: captureGroup, color: color))
            }
        }

        switch language {
        case .swift:
            // 1. Comments (Block & Line) & TODO/FIXME annotations
            add(#"(\/\/[^\n]*)"#, color: theme.comment)
            add(#"(\/\*[\s\S]*?\*\/)"#, color: theme.comment)
            add(#"\b(TODO|FIXME)\b"#, color: theme.todo)

            // 2. Strings (Double-quoted & Multi-line raw strings)
            add(#"("""[\s\S]*?""")"#, color: theme.string)
            add(#"("(?:[^"\\]|\\.)*")"#, color: theme.string)

            // 3. Preprocessor, Compiler directives, Imports & Macros
            add(#"\b(import)\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: theme.keyword, captureGroup: 1)
            add(#"\bimport\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: theme.type, captureGroup: 1)
            add(#"(#if|#else|#elseif|#endif|#available|#unavailable|#selector|#keyPath|#file|#line|#function|#Preview)\b"#, color: theme.preprocessor)
            add(#"(@[a-zA-Z_][a-zA-Z0-9_]*)"#, color: theme.attribute)

            // 4. Access Modifiers & Keywords
            let keywords = [
                "struct", "class", "enum", "protocol", "extension", "actor", "macro",
                "func", "var", "let", "init", "deinit", "subscript", "typealias",
                "public", "private", "internal", "fileprivate", "open",
                "if", "else", "switch", "case", "default", "break", "continue", "fallthrough",
                "return", "try", "catch", "throw", "throws", "rethrows", "defer", "guard", "where", "do",
                "async", "await", "get", "set", "willSet", "didSet", "static", "final", "override", "required",
                "convenience", "mutating", "nonmutating", "lazy", "weak", "unowned", "in", "is", "as",
                "some", "any", "self", "super", "true", "false", "nil", "isolated", "nonisolated"
            ]
            add("\\b(\(keywords.joined(separator: "|")))\\b", color: theme.keyword)

            // 5. Types (Upper Camel Case) & Generics
            add(#"\b([A-Z][a-zA-Z0-9_]*)\b"#, color: theme.type)

            // 6. Functions (calls and definitions)
            add(#"\bfunc\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, color: theme.function, captureGroup: 1)
            add(#"\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\(?"#, color: theme.function, captureGroup: 1)

            // 7. Numbers (Hex, Binary, Octal, Decimal)
            add(#"\b(0x[0-9a-fA-F]+)\b"#, color: theme.number)
            add(#"\b(0b[01]+)\b"#, color: theme.number)
            add(#"\b(0o[0-7]+)\b"#, color: theme.number)
            add(#"\b(\d+\.?\d*(?:e[+-]?\d+)?)\b"#, color: theme.number)

            // 8. Operators
            add(#"(\?\?|\.\.\.|\.\.<|\+|-|\*|\/|==|!=|<=|>=|<|>)"#, color: theme.operatorColor)

        case .json:
            add(#"("(?:[^"\\]|\\.)*")\s*:"#, color: theme.type, captureGroup: 1)
            add(#":\s*("(?:[^"\\]|\\.)*")"#, color: theme.string, captureGroup: 1)
            add(#"\b(true|false|null)\b"#, color: theme.keyword)
            add(#"(-?\d+\.?\d*(?:[eE][+-]?\d+)?)"#, color: theme.number)

        case .markdown:
            add(#"(^#{1,6}\s+[^\n]+)"#, color: theme.keyword, options: [.anchorsMatchLines])
            add(#"(\*\*[^\*]+\*\*|__[^_]+__)"#, color: theme.type)
            add(#"(\*[^\*\n]+\*|_[^_\n]+_)"#, color: theme.function)
            add(#"(`[^`\n]+`)"#, color: theme.string)
            add(#"(```[\s\S]*?```)"#, color: theme.string)
            add(#"(\[[^\]]+\]\([^\)]+\))"#, color: theme.attribute)
            add(#"(^>\s+[^\n]*)"#, color: theme.comment, options: [.anchorsMatchLines])

        default:
            break
        }

        return patterns
    }
}
