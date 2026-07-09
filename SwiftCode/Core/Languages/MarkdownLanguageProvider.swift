import Foundation

public struct MarkdownLanguageProvider: LanguageProvider {
    public let id = "markdown"
    public let displayName = "Markdown"
    public let fileExtensions = ["md", "markdown"]
    public let iconName = "doc.plaintext"
    public let iconColorName = "blue"
    public let capabilities: Set<LanguageCapability> = [.livePreview]

    public let commentSyntax = CommentSyntax(blockStart: "<!--", blockEnd: "-->")

    public init() {}

    public func tokenize(line: String) -> [TokenizedLine.Token] {
        if line.hasPrefix("#") {
            return [TokenizedLine.Token(text: line, kind: .keyword)]
        }

        var tokens: [TokenizedLine.Token] = []
        let parts = line.components(separatedBy: " ")
        for part in parts {
            if (part.hasPrefix("**") && part.hasSuffix("**")) || (part.hasPrefix("__") && part.hasSuffix("__")) {
                tokens.append(TokenizedLine.Token(text: part, kind: .keyword))
            } else if (part.hasPrefix("*") && part.hasSuffix("*")) || (part.hasPrefix("_") && part.hasSuffix("_")) {
                tokens.append(TokenizedLine.Token(text: part, kind: .string))
            } else if part.hasPrefix("[") && part.contains("](") {
                tokens.append(TokenizedLine.Token(text: part, kind: .keyword))
            } else {
                tokens.append(TokenizedLine.Token(text: part, kind: .plain))
            }
            tokens.append(TokenizedLine.Token(text: " ", kind: .plain))
        }
        return tokens
    }
}
