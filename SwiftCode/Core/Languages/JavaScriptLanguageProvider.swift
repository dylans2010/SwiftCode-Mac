import Foundation

public struct JavaScriptLanguageProvider: LanguageProvider {
    public let id = "javascript"
    public let displayName = "JavaScript"
    public let fileExtensions = ["js"]
    public let iconName = "scroll"
    public let iconColorName = "yellow"
    public let capabilities: Set<LanguageCapability> = [.livePreview, .format]

    public let commentSyntax = CommentSyntax(linePrefix: "//", blockStart: "/*", blockEnd: "*/")

    public init() {}

    public func tokenize(line: String) -> [TokenizedLine.Token] {
        var tokens: [TokenizedLine.Token] = []
        let words = line.components(separatedBy: .whitespaces)
        let keywords: Set<String> = ["function", "var", "let", "const", "if", "else", "return", "class", "import", "export"]

        for word in words {
            if keywords.contains(word) {
                tokens.append(TokenizedLine.Token(text: word, kind: .keyword))
            } else if word.hasPrefix("\"") || word.hasPrefix("'") {
                tokens.append(TokenizedLine.Token(text: word, kind: .string))
            } else {
                tokens.append(TokenizedLine.Token(text: word, kind: .plain))
            }
            tokens.append(TokenizedLine.Token(text: " ", kind: .plain))
        }
        return tokens
    }
}
