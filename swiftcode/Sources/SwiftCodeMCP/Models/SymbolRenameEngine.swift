import Foundation
import SwiftParser
import SwiftSyntax

enum SymbolRenameEngine {
    struct Result: Sendable {
        var updated: String
        var replacements: Int
        var skipped: Int
        var declarationFound: Bool
        var declarationKind: String?
    }

    static func rename(source: String, oldName: String, newName: String) -> Result {
        let tree = Parser.parse(source: source)
        var replacements = 0
        var updated = ""
        updated.reserveCapacity(source.utf8.count)
        for token in tree.tokens(viewMode: .sourceAccurate) {
            updated += token.leadingTrivia.description
            if case .identifier = token.tokenKind, token.text == oldName,
               token.parent?.is(ImportPathComponentSyntax.self) != true {
                updated += newName
                replacements += 1
            } else {
                updated += token.text
            }
            updated += token.trailingTrivia.description
        }
        let wholeWord = wholeWordCount(of: oldName, in: source)
        let declarationKind = SwiftASTInspection.inspect(source: source).kind(of: oldName)
        return Result(updated: updated, replacements: replacements,
                      skipped: max(0, wholeWord - replacements),
                      declarationFound: declarationKind != nil, declarationKind: declarationKind)
    }

    static func wholeWordCount(of name: String, in source: String) -> Int {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
        return regex.numberOfMatches(in: source, options: [], range: NSRange(source.startIndex..., in: source))
    }
}
