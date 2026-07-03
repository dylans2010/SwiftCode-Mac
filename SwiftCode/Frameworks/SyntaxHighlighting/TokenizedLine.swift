import Foundation

public struct TokenizedLine: Sendable, Identifiable {
    public var id: Int { lineNumber }
    public let lineNumber: Int
    public let tokens: [Token]

    public struct Token: Sendable {
        public let text: String
        public let kind: SyntaxTokenKind
    }
}
