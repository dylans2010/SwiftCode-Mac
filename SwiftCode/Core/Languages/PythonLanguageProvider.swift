import Foundation

public struct PythonLanguageProvider: LanguageProvider {
    public let id = "python"
    public let displayName = "Python"
    public let fileExtensions = ["py"]
    public let iconName = "terminal"
    public let iconColorName = "cyan"
    public let capabilities: Set<LanguageCapability> = [.run, .format]

    public let commentSyntax = CommentSyntax(linePrefix: "#")

    public init() {}

    public func tokenize(line: String) -> [TokenizedLine.Token] {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return [TokenizedLine.Token(text: line, kind: .comment)]
        }

        var tokens: [TokenizedLine.Token] = []
        let words = line.components(separatedBy: .whitespaces)
        let keywords: Set<String> = ["def", "class", "if", "elif", "else", "return", "import", "from", "as", "with"]

        for word in words {
            if keywords.contains(word) {
                tokens.append(TokenizedLine.Token(text: word, kind: .keyword))
            } else {
                tokens.append(TokenizedLine.Token(text: word, kind: .plain))
            }
            tokens.append(TokenizedLine.Token(text: " ", kind: .plain))
        }
        return tokens
    }
}
