import SwiftIDEUtils
import SwiftParser
import SwiftSyntax

final class SwiftClassifier {
    private var result: IncrementalParseResult?

    func parse(_ source: [UInt8]) {
        result = source.withUnsafeBufferPointer { Parser.parseIncrementally(source: $0, parseTransition: nil) }
    }

    func reparse(_ source: [UInt8], edits: [SourceEdit]) {
        guard let previous = result else { return parse(source) }
        let transition = IncrementalParseTransition(previousIncrementalParseResult: previous, edits: ConcurrentEdits(fromSequential: edits))
        result = source.withUnsafeBufferPointer { Parser.parseIncrementally(source: $0, parseTransition: transition) }
    }

    func classify(_ bytes: Range<Int>, source: [UInt8], into out: inout [(SyntaxTokenKind, Int, Int)]) {
        guard let tree = result?.tree else { return }
        let range = AbsolutePosition(utf8Offset: bytes.lowerBound)..<AbsolutePosition(utf8Offset: bytes.upperBound)
        for c in tree.classifications(in: range) {
            let a = c.range.lowerBound.utf8Offset, b = c.range.upperBound.utf8Offset
            guard b > a, let kind = Self.kind(c.kind, firstByte: source[a]) else { continue }
            if kind == .typeName, c.kind == .identifier,
               tree.token(at: AbsolutePosition(utf8Offset: a))?.parent?.is(ImportPathComponentSyntax.self) == true { continue }
            out.append((kind, a, b))
        }
    }

    static func kind(_ c: SyntaxClassification, firstByte: UInt8) -> SyntaxTokenKind? {
        switch c {
        case .keyword: .keyword
        case .attribute: .attribute
        case .blockComment, .lineComment: .comment
        case .docBlockComment, .docLineComment: .docComment
        case .stringLiteral: .string
        case .regexLiteral: .regex
        case .integerLiteral, .floatLiteral: .number
        case .ifConfigDirective: .preprocessor
        case .type: .typeName
        case .editorPlaceholder: .placeholder
        case .identifier: firstByte >= 65 && firstByte <= 90 ? .typeName : nil
        case .dollarIdentifier, .operator, .argumentLabel, .none: nil
        @unknown default: nil
        }
    }
}
