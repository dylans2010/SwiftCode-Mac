import Foundation
import Testing
@testable import YcodeSyntax

@Suite struct ImportPathTests {
    static let source = """
    import Foundation
    @testable import YcodeSyntax
    import struct Foundation.Date
    import os.log
    let d = Foundation.Date()
    """

    @Test(arguments: [true, false]) func moduleNamesArePlain(parser: Bool) {
        let t = snapshot(Self.source, .swift, parser: parser)
        #expect(!t.contains("typeName Foundation") || t.filter { $0 == "typeName Foundation" }.count == 1, "\(t)")
        #expect(!t.contains("typeName SwiftCodeSyntax"), "\(t)")
        #expect(t.contains("keyword import"))
        #expect(t.contains("typeName Date"), "\(t)")
        let lines = (0..<SyntaxDocument(text: Self.source, language: .swift, usesParser: parser).lineCount)
        let d = SyntaxDocument(text: Self.source, language: .swift, usesParser: parser)
        let ns = Self.source as NSString
        for line in lines.prefix(4) {
            let kinds = d.tokens(onLine: line).map { "\($0.kind) \(ns.substring(with: $0.range))" }
            #expect(!kinds.contains { $0.hasPrefix("typeName") }, "line \(line): \(kinds)")
        }
        let last = d.tokens(onLine: 4).map { "\($0.kind) \(ns.substring(with: $0.range))" }
        #expect(last.contains("typeName Foundation") && last.contains("typeName Date"), "\(last)")
    }

    @Test func lexerImportPathRule() {
        let t = snapshot("return Foo\ncase let Bar\nimport  A . B\n", .swift, parser: false)
        #expect(t.contains("typeName Foo") && t.contains("typeName Bar"), "\(t)")
        #expect(!t.contains("typeName A") && !t.contains("typeName B"), "\(t)")
    }
}
