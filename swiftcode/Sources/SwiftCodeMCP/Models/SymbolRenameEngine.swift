import Foundation
import SwiftParser
import SwiftSyntax

/// A token-aware project rename, built on the same swift-syntax parse
/// as `SwiftASTInspection`.
///
/// The Wave 3 port was whole-word *textual* replacement
/// (`\boldName\b` over the raw file): it also renamed occurrences
/// inside string literals and comments, and renamed the name where
/// it appeared as a module in an `import` line. This engine walks
/// the parse tree's tokens instead and renames only real identifier
/// tokens — so `"oldName"` in a string, `// oldName` in a comment,
/// and `import oldName` are left alone, and the count of skipped
/// occurrences is reported.
///
/// Limits, stated plainly: this is syntactic, not semantic. There
/// is no type checker and no cross-file symbol index, so shadowing
/// is not resolved: a same-named local in an unrelated scope is
/// renamed too, and a member accessed through a different spelling
/// (e.g. a stringly-typed key) is not renamed. What it guarantees
/// is token accuracy within each file: every replacement is an
/// identifier token, and no string, comment, or import path is
/// touched. Callers that need a semantic rename must use an
/// index-backed rename; this tool's description says so.
enum SymbolRenameEngine {
    /// The result of renaming one file's source.
    struct Result: Sendable {
        /// The source with identifier tokens renamed.
        var updated: String
        /// Identifier tokens replaced.
        var replacements: Int
        /// Whole-word occurrences left alone (inside strings or
        /// comments, in import paths, or keywords).
        var skipped: Int
        /// Whether a declaration of `oldName` exists in the file.
        var declarationFound: Bool
        /// Its kind (`class`, `func`, `var`, …) when found.
        var declarationKind: String?
    }

    /// Renames identifier tokens `oldName` → `newName` in `source`.
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

    /// Whole-word occurrences of `name` in raw text (the count the
    /// old textual rename would have replaced).
    static func wholeWordCount(of name: String, in source: String) -> Int {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
        return regex.numberOfMatches(in: source, options: [], range: NSRange(source.startIndex..., in: source))
    }
}
