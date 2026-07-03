import Foundation

public struct SwiftTokenizer: Sendable {
    public static let shared = SwiftTokenizer()

    private let keywords = Set(["struct", "class", "enum", "func", "var", "let", "if", "else", "switch", "case", "import", "public", "private", "extension", "protocol", "return", "try", "await", "async", "actor", "main"])

    public func tokenize(_ line: String) -> [TokenizedLine.Token] {
        // Simple regex-based tokenizer
        var tokens: [TokenizedLine.Token] = []

        let words = line.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let scanner = Scanner(string: line)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            if let word = scanner.scanCharacters(from: .alphanumerics) {
                if keywords.contains(word) {
                    tokens.append(TokenizedLine.Token(text: word, kind: .keyword))
                } else if Double(word) != nil {
                    tokens.append(TokenizedLine.Token(text: word, kind: .number))
                } else if word.first?.isUppercase == true {
                    tokens.append(TokenizedLine.Token(text: word, kind: .type))
                } else {
                    tokens.append(TokenizedLine.Token(text: word, kind: .plain))
                }
            } else if let whitespace = scanner.scanCharacters(from: .whitespaces) {
                tokens.append(TokenizedLine.Token(text: whitespace, kind: .plain))
            } else if let quote = scanner.scanString("\"") {
                var stringVal = quote
                if let content = scanner.scanUpToString("\"") {
                    stringVal += content
                    if let endQuote = scanner.scanString("\"") {
                        stringVal += endQuote
                    }
                }
                tokens.append(TokenizedLine.Token(text: stringVal, kind: .string))
            } else if let comment = scanner.scanString("//") {
                let rest = scanner.scanUpToString("\n") ?? ""
                tokens.append(TokenizedLine.Token(text: comment + rest, kind: .comment))
                break
            } else if let symbol = scanner.scanCharacter() {
                tokens.append(TokenizedLine.Token(text: String(symbol), kind: .plain))
            }
        }

        return tokens
    }
}
