import Foundation
@_exported import YcodeSyntax

public struct SourceTokenizer: Sendable {
    public typealias Language = SyntaxLanguage

    public typealias Kind = SyntaxTokenKind.Role

    public struct Token: Equatable, Sendable {
        public var kind: Kind
        public var range: NSRange
    }

    public let language: Language
    public init(language: Language) { self.language = language }

    public func tokens(in text: String) -> [Token] {
        SyntaxLexers.tokens(in: text, language: language).compactMap { t in
            let role = t.kind.role
            return role == .identifier ? nil : Token(kind: role, range: t.range)
        }
    }
}

extension EditorTheme {
    public func color(for kind: SyntaxTokenKind) -> ThemeColor? { ThemeColor(hex: tokens[kind.role.rawValue]) }
}
