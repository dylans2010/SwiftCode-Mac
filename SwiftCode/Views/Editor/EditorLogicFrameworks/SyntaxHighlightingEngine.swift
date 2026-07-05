import SwiftUI

// MARK: - Syntax Highlighting Engine
// Wraps SyntaxHighlighter and adds multi-theme support.
// Supports Swift, shell scripts, JSON, plist, and Markdown.

final class SyntaxHighlightingEngine {
    static let shared = SyntaxHighlightingEngine()
    private init() {}

    // MARK: - Highlight

    /// Highlight `code` using the file extension to select the language rules.
    @MainActor
    func highlight(_ code: String, fileExtension: String = "swift", theme: CodeColoringTheme = .dark) -> AttributedString {
        let tokens = tokenize(code, fileExtension: fileExtension)
        return buildAttributedString(from: tokens, theme: theme)
    }

    // MARK: - Tokenizer

    private enum TokenKind {
        case keyword, string, comment, number, type, function, variable, punctuation, plain
    }

    private struct Token {
        let text: String
        let kind: TokenKind
    }

    private func tokenize(_ code: String, fileExtension: String) -> [Token] {
        let lang = fileExtension.lowercased()
        switch lang {
        case "sh", "bash", "zsh": return tokenizeShell(code)
        case "json": return tokenizeJSON(code)
        case "plist": return tokenizePlist(code)
        case "md", "markdown": return tokenizeMarkdown(code)
        default: return tokenizeSwift(code)
        }
    }

    // MARK: - Swift Tokenizer

    private func tokenizeSwift(_ code: String) -> [Token] {
        let keywordPattern = #"\b(import|class|struct|enum|protocol|extension|func|var|let|if|else|guard|return|switch|case|default|for|while|break|continue|throw|throws|try|catch|do|in|is|as|nil|true|false|self|super|init|deinit|get|set|willSet|didSet|override|final|open|public|internal|private|fileprivate|static|mutating|nonmutating|lazy|weak|unowned|some|any|typealias|associatedtype|where|subscript|operator|infix|prefix|postfix|async|await|actor|rethrows|defer|inout)\b"#

        let patterns: [(NSRegularExpression, TokenKind)] = [
            (try! NSRegularExpression(pattern: #"//[^\n]*"#), .comment),
            (try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#), .comment),
            (try! NSRegularExpression(pattern: #""""[\s\S]*?""""#), .string),
            (try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#), .string),
            (try! NSRegularExpression(pattern: keywordPattern), .keyword),
            (try! NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z0-9_]*\b"#), .type),
            (try! NSRegularExpression(pattern: #"\b\d+\.?\d*\b"#), .number),
            (try! NSRegularExpression(pattern: #"\b[a-z_][a-zA-Z0-9_]*\s*(?=\()"#), .function),
        ]
        return buildTokens(from: code, patterns: patterns)
    }

    // MARK: - Shell Tokenizer

    private func tokenizeShell(_ code: String) -> [Token] {
        let kwPattern = #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|exit|local|export|source|true|false|echo|read)\b"#
        let cmdPattern = #"\b(mkdir|cp|rm|cd|ls|cat|grep|sed|awk|chmod|chown|curl|wget|git|brew|swift|xcodebuild)\b"#

        let patterns: [(NSRegularExpression, TokenKind)] = [
            (try! NSRegularExpression(pattern: #"#[^\n]*"#), .comment),
            (try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#), .string),
            (try! NSRegularExpression(pattern: #"'(?:[^'\\]|\\.)*'"#), .string),
            (try! NSRegularExpression(pattern: kwPattern), .keyword),
            (try! NSRegularExpression(pattern: cmdPattern), .function),
            (try! NSRegularExpression(pattern: #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#), .variable),
            (try! NSRegularExpression(pattern: #"\b\d+\b"#), .number),
        ]
        return buildTokens(from: code, patterns: patterns)
    }

    // MARK: - JSON Tokenizer

    private func tokenizeJSON(_ code: String) -> [Token] {
        let patterns: [(NSRegularExpression, TokenKind)] = [
            (try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#), .string),
            (try! NSRegularExpression(pattern: #"\b(true|false|null)\b"#), .keyword),
            (try! NSRegularExpression(pattern: #"-?\d+\.?\d*(?:[eE][+-]?\d+)?"#), .number),
        ]
        return buildTokens(from: code, patterns: patterns)
    }

    // MARK: - Plist Tokenizer

    private func tokenizePlist(_ code: String) -> [Token] {
        let patterns: [(NSRegularExpression, TokenKind)] = [
            (try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#), .comment),
            (try! NSRegularExpression(pattern: #"<[^>]+>"#), .keyword),
            (try! NSRegularExpression(pattern: #">([^<]+)<"#), .string),
        ]
        return buildTokens(from: code, patterns: patterns)
    }

    // MARK: - Markdown Tokenizer

    private func tokenizeMarkdown(_ code: String) -> [Token] {
        let patterns: [(NSRegularExpression, TokenKind)] = [
            (try! NSRegularExpression(pattern: #"^#{1,6}\s+[^\n]+"#, options: .anchorsMatchLines), .keyword),
            (try! NSRegularExpression(pattern: #"\*\*[^\*]+\*\*|__[^_]+__"#), .type),
            (try! NSRegularExpression(pattern: #"\*[^\*\n]+\*|_[^_\n]+_"#), .function),
            (try! NSRegularExpression(pattern: #"`[^`\n]+`"#), .string),
            (try! NSRegularExpression(pattern: #"```[\s\S]*?```"#), .string),
            (try! NSRegularExpression(pattern: #"\[[^\]]+\]\([^\)]+\)"#), .variable),
            (try! NSRegularExpression(pattern: #"^>\s+[^\n]*"#, options: .anchorsMatchLines), .comment),
        ]
        return buildTokens(from: code, patterns: patterns)
    }

    // MARK: - Token Building (shared)

    private func buildTokens(from code: String, patterns: [(NSRegularExpression, TokenKind)]) -> [Token] {
        var tokens: [Token] = []
        let nsCode = code as NSString
        let fullRange = NSRange(location: 0, length: nsCode.length)

        var processedRanges: [NSRange] = []
        var allMatches: [(NSRange, TokenKind)] = []

        for (regex, kind) in patterns {
            let matches = regex.matches(in: code, range: fullRange)
            for match in matches {
                let range = match.range
                let overlaps = processedRanges.contains { NSIntersectionRange($0, range).length > 0 }
                if !overlaps {
                    allMatches.append((range, kind))
                    processedRanges.append(range)
                }
            }
        }

        let sorted = allMatches.sorted { $0.0.location < $1.0.location }
        var cursor = 0
        for (range, kind) in sorted {
            if range.location > cursor {
                let plainRange = NSRange(location: cursor, length: range.location - cursor)
                tokens.append(Token(text: nsCode.substring(with: plainRange), kind: .plain))
            }
            tokens.append(Token(text: nsCode.substring(with: range), kind: kind))
            cursor = range.location + range.length
        }
        if cursor < nsCode.length {
            tokens.append(Token(text: nsCode.substring(from: cursor), kind: .plain))
        }
        return tokens
    }

    // MARK: - Attributed String Builder

    @MainActor
    private func buildAttributedString(from tokens: [Token], theme: CodeColoringTheme) -> AttributedString {
        var result = AttributedString()
        let fontSize = CGFloat(AppSettings.shared.editorFontSize)
        for token in tokens {
            var part = AttributedString(token.text)
            part.foregroundColor = color(for: token.kind, theme: theme)
            if case .keyword = token.kind {
                part.font = .system(size: fontSize, design: .monospaced).bold()
            } else {
                part.font = .system(size: fontSize, design: .monospaced)
            }
            result.append(part)
        }
        return result
    }

    private func color(for kind: TokenKind, theme: CodeColoringTheme) -> Color {
        switch kind {
        case .keyword:     return theme.keywordColor
        case .string:      return theme.stringColor
        case .comment:     return theme.commentColor
        case .number:      return theme.numberColor
        case .type:        return theme.typeColor
        case .function:    return theme.functionColor
        case .variable:    return theme.keywordColor.opacity(0.8)
        case .punctuation: return theme.plainColor
        case .plain:       return theme.plainColor
        }
    }
}
