import Foundation
import SwiftUI

public actor SyntaxHighlightingEngine {
    public static let shared = SyntaxHighlightingEngine()

    public func tokenize(text: String, language: SourceLanguage) async -> [TokenizedLine] {
        let lines = text.components(separatedBy: .newlines)
        var tokenizedLines: [TokenizedLine] = []

        for (index, line) in lines.enumerated() {
            let tokens: [TokenizedLine.Token] = {
                switch language {
                case .swift:
                    return SwiftTokenizer.shared.tokenize(line)
                default:
                    return [TokenizedLine.Token(text: line, kind: .plain)]
                }
            }()
            tokenizedLines.append(TokenizedLine(lineNumber: index + 1, tokens: tokens))
        }

        return tokenizedLines
    }
}
