import Foundation
import SwiftUI

public actor SyntaxHighlightingEngine {
    public static let shared = SyntaxHighlightingEngine()

    public func tokenize(text: String, language: SourceLanguage) async -> [TokenizedLine] {
        let lines = text.components(separatedBy: .newlines)
        var tokenizedLines: [TokenizedLine] = []

        let provider = LanguageManager.shared.provider(forId: language.rawValue)

        for (index, line) in lines.enumerated() {
            let tokens: [TokenizedLine.Token] = {
                if let provider = provider {
                    return provider.tokenize(line: line)
                }
                return [TokenizedLine.Token(text: line, kind: .plain)]
            }()
            tokenizedLines.append(TokenizedLine(lineNumber: index + 1, tokens: tokens))
        }

        return tokenizedLines
    }
}
