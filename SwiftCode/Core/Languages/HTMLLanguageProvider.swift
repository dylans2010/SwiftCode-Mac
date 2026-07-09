import Foundation

public struct HTMLLanguageProvider: LanguageProvider {
    public let id = "html"
    public let displayName = "HTML"
    public let fileExtensions = ["html", "htm"]
    public let iconName = "chevron.left.forwardslash.chevron.right"
    public let iconColorName = "red"
    public let capabilities: Set<LanguageCapability> = [.livePreview, .format]

    public let commentSyntax = CommentSyntax(blockStart: "<!--", blockEnd: "-->")

    public init() {}

    public func tokenize(line: String) -> [TokenizedLine.Token] {
        var tokens: [TokenizedLine.Token] = []
        let scanner = Scanner(string: line)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            if let tag = scanner.scanUpToString(">") {
                let fullTag = tag + (scanner.scanString(">") ?? "")
                if fullTag.hasPrefix("<") {
                    tokens.append(TokenizedLine.Token(text: fullTag, kind: .keyword))
                } else {
                    tokens.append(TokenizedLine.Token(text: fullTag, kind: .plain))
                }
            } else if let char = scanner.scanCharacter() {
                tokens.append(TokenizedLine.Token(text: String(char), kind: .plain))
            }
        }
        return tokens.isEmpty ? [TokenizedLine.Token(text: line, kind: .plain)] : tokens
    }

    public func generateDefaultContent(fileName: String) -> String {
        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>\(fileName)</title>
</head>
<body>
    <h1>Hello World</h1>
</body>
</html>
"""
    }
}
