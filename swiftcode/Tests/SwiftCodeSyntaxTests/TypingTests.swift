import Foundation
import Testing
@testable import SwiftCodeSyntax

private let spaces4 = TypingOptions()

private func ret(_ s: String, _ lang: SyntaxLanguage = .swift, _ o: TypingOptions = spaces4) -> String? {
    let (text, sel) = marked(s)
    return render(text, TypingRules.newline(in: SyntaxDocument(text: text, language: lang), selection: sel, options: o))
}

private func type(_ c: String, _ s: String, _ lang: SyntaxLanguage = .swift, closers: Set<Int> = [], _ o: TypingOptions = spaces4) -> String? {
    let (text, sel) = marked(s)
    return render(text, TypingRules.insert(c, in: SyntaxDocument(text: text, language: lang), selection: sel, options: o, pendingClosers: closers)?.edit)
}

private func electric(_ c: String, _ s: String, _ lang: SyntaxLanguage = .swift) -> String? {
    let (text, sel) = marked(s)
    return render(text, TypingRules.reindentAfterTyping(c, in: SyntaxDocument(text: text, language: lang), caret: sel.location, options: spaces4))
}

@Suite struct TypingTests {

    @Test func returnIndentsAfterAnOpener() {
        #expect(ret("func f() {|") == "func f() {\n    |")
        #expect(ret("    if a {|\n    }") == "    if a {\n        |\n    }")
        #expect(ret("let a = [|") == "let a = [\n    |")
        #expect(ret("struct A {\n    let x = 1|\n}") == "struct A {\n    let x = 1\n    |\n}")
        #expect(ret("let a = 1|") == "let a = 1\n|")
    }

    @Test func returnBetweenBracketsSplitsThem() {
        #expect(ret("func f() {|}") == "func f() {\n    |\n}")
        #expect(ret("    call(|)") == "    call(\n        |\n    )")
        #expect(ret("if a {\n    b|}") == "if a {\n    b\n|}")
        #expect(ret("<a>|</a>", .xml) == "<a>\n    |\n</a>")
    }

    @Test func returnInSwitchAndComments() {
        #expect(ret("switch x {\ncase 1:|") == "switch x {\ncase 1:\n    |")
        #expect(ret("    /// Doc|") == "    /// Doc\n    /// |")
        #expect(ret("    /* a|") == "    /* a\n    |")
        #expect(ret("    let s = \"a|b\"") == "    let s = \"a\n    |b\"")
    }

    @Test func returnOnABlankLineEmptiesIt() {
        #expect(ret("{\n    |") == "{\n\n    |")
        #expect(ret("a {|    }") == "a {\n    |\n}")
    }

    @Test func returnWithoutAutoIndentKeepsTheIndentation() {
        var o = spaces4
        o.autoIndent = false
        #expect(ret("    if a {|", .swift, o) == "    if a {\n    |")
    }

    @Test func returnOtherLanguages() {
        #expect(ret("int f(void) {|}", .c) == "int f(void) {\n    |\n}")
        #expect(ret("{\n  \"a\": [|", .json) == "{\n  \"a\": [\n      |")
        #expect(ret("<dict>|", .xml) == "<dict>\n    |")
        #expect(ret("<dict>\n    <key>a</key>|", .xml) == "<dict>\n    <key>a</key>\n    |")
        #expect(ret("if [ x ]; then|", .shell) == "if [ x ]; then\n    |")
        #expect(ret("key:|", .yaml) == "key:\n    |")
        #expect(ret("  a: 1|", .yaml) == "  a: 1\n  |")
        #expect(ret("  text|", .plain) == "  text\n  |")
        #expect(ret("let s = \"\"\"|") == "let s = \"\"\"\n|\n\"\"\"")
        #expect(ret("Text(\"a\")\n    .padding()|") == "Text(\"a\")\n    .padding()\n    |")
    }

    @Test func markdownListsContinue() {
        #expect(ret("- one|", .markdown) == "- one\n- |")
        #expect(ret("  3. three|", .markdown) == "  3. three\n  4. |")
        #expect(ret("- [x] done|", .markdown) == "- [x] done\n- [ ] |")
        #expect(ret("> q|", .markdown) == "> q\n> |")
        #expect(ret("- one\n- |", .markdown) == "- one\n|")
        #expect(ret("plain|", .markdown) == "plain\n|")
    }

    @Test func closersCaseDefaultAndElseReindent() {
        #expect(electric("}", "if a {\n    b\n    }|") == "if a {\n    b\n}|")
        #expect(electric(":", "switch x {\n    case 1:|") == "switch x {\ncase 1:|")
        #expect(electric(":", "switch x {\ncase 1:\n    a()\n    default:|") == "switch x {\ncase 1:\n    a()\ndefault:|")
        #expect(electric("e", "func f() {\n    #if A\n    a()\n        #else|") == "func f() {\n    #if A\n    a()\n    #else|")
        #expect(electric("f", "int f() {\n    #endif|", .c) == "int f() {\n#endif|")
        #expect(electric("/", "<a>\n    </|", .xml) == "<a>\n</|")
        #expect(electric("i", "if x; then\n    a\n    fi|", .shell) == "if x; then\n    a\nfi|")
        #expect(electric("}", "if a {\n    b }|") == nil)
        #expect(electric("e", "    #els|e") == nil)
        #expect(electric("s", "    cases|") == nil)
    }

    @Test func reindentLines() throws {
        let t = """
        struct A {
        func f(x: Int) {
        switch x {
        case 1:
        print("{")
        default:
        break
        }
        let y = [
        1,
        ]
        }
        /* keep
             this */
        }

        """
        let d = SyntaxDocument(text: t, language: .swift)
        let e = try #require(d.reindent(lines: 0...(d.lineCount - 1), options: IndentOptions(), selection: NSRange(location: 0, length: 0)))
        #expect(e.applied(to: t) == """
        struct A {
            func f(x: Int) {
                switch x {
                case 1:
                    print("{")
                default:
                    break
                }
                let y = [
                    1,
                ]
            }
            /* keep
             this */
        }

        """)
        let c = "int f() {\n#if A\nreturn 1;\n  #endif\n}\n"
        let dc = SyntaxDocument(text: c, language: .c)
        #expect(dc.reindent(lines: 0...4, options: IndentOptions(unit: "\t"), selection: NSRange())?.applied(to: c) == "int f() {\n#if A\n\treturn 1;\n#endif\n}\n")
        let x = "<plist>\n<dict>\n<key>a</key>\n<true/>\n</dict>\n</plist>\n"
        let dx = SyntaxDocument(text: x, language: .xml)
        #expect(dx.reindent(lines: 0...6, options: IndentOptions(indentWidth: 2), selection: NSRange())?.applied(to: x)
                == "<plist>\n  <dict>\n    <key>a</key>\n    <true/>\n  </dict>\n</plist>\n")
        let sh = "if a; then\nb\nelse\nc\nfi\n"
        #expect(SyntaxDocument(text: sh, language: .shell).reindent(lines: 0...5, options: IndentOptions(), selection: NSRange())?.applied(to: sh)
                == "if a; then\n    b\nelse\n    c\nfi\n")
        #expect(SyntaxDocument(text: "a:\nb: 1\n", language: .yaml).reindent(lines: 0...1, options: IndentOptions(), selection: NSRange()) == nil)
    }

    @Test func openersInsertTheirCloser() {
        #expect(type("(", "f|") == "f(|)")
        #expect(type("{", "if a |") == "if a {|}")
        #expect(type("[", "x = |, y") == "x = [|], y")
        #expect(type("\"", "let s = |") == "let s = \"|\"")
        #expect(type("'", "char c = |;", .c) == "char c = '|';")
        #expect(type("`", "use |", .markdown) == "use `|`")
    }

    @Test func noPairingWhereItWouldBeWrong() {
        #expect(type("(", "f|oo") == nil)
        #expect(type("\"", "a|b") == nil)
        #expect(type("(", "// note |") == nil)
        #expect(type("\"", "let s = \"a |\"") == nil)
        #expect(type("'", "don|", .c) == nil)
        #expect(type("'", "let c = |") == nil)
        var o = spaces4
        o.autoClose = false
        #expect(type("(", "f|", .swift, o) == nil)
    }

    @Test func closersAreSteppedOver() {
        #expect(type(")", "f(|)", closers: [2]) == "f()|")
        #expect(type("\"", "\"a|\"", closers: [2]) == "\"a\"|")
        #expect(type(")", "f(|)", closers: []) == nil)
        let r = TypingRules.insert("]", in: SyntaxDocument(text: "[]", language: .swift), selection: NSRange(location: 1, length: 0), options: spaces4, pendingClosers: [1])
        #expect(r?.steppedOver == 1)
        #expect(TypingRules.insert("(", in: SyntaxDocument(text: "f", language: .swift), selection: NSRange(location: 1, length: 0), options: spaces4, pendingClosers: [])?.insertedClosers == [2])
    }

    @Test func selectionsAreEnclosed() {
        #expect(type("(", "let a = |b + c|") == "let a = (|b + c|)")
        #expect(type("\"", "x = |name|") == "x = \"|name|\"")
        #expect(type("[", "|a\nb|") == "[|a\nb|]")
        var o = spaces4
        o.encloseSelection = false
        #expect(type("(", "|x|", .swift, o) == nil)
    }

    @Test func deleteBackwardRemovesAPair() {
        let d = SyntaxDocument(text: "f()", language: .swift)
        #expect(render("f()", TypingRules.deleteBackward(in: d, selection: NSRange(location: 2, length: 0), pendingClosers: [2])) == "f|")
        #expect(TypingRules.deleteBackward(in: d, selection: NSRange(location: 2, length: 0), pendingClosers: []) == nil)
    }

    @Test func pendingClosersFollowEdits() {
        #expect(TypingRules.adjust([5, 10], editing: NSRange(location: 2, length: 0), replacementLength: 3) == [8, 13])
        #expect(TypingRules.adjust([5, 10], editing: NSRange(location: 4, length: 2), replacementLength: 0) == [8])
        #expect(TypingRules.adjust([5], editing: NSRange(location: 5, length: 0), replacementLength: 1) == [6])
        #expect(TypingRules.adjust([5], editing: NSRange(location: 6, length: 1), replacementLength: 1) == [5])
    }

    @Test func tabFollowsTheSetting() {
        func tab(_ s: String, _ k: TabKeyBehavior, backward: Bool = false, _ o: IndentOptions = IndentOptions()) -> String? {
            let (text, sel) = marked(s)
            let opts = TypingOptions(indent: o, tabKey: k)
            return render(text, TypingRules.tab(in: SyntaxDocument(text: text, language: .swift), selection: sel, backward: backward, options: opts))
        }
        #expect(tab("if a {\n|b\n}", .indentsInLeadingWhitespace) == "if a {\n    |b\n}")
        #expect(tab("if a {\n    |b\n}", .indentsInLeadingWhitespace) == "if a {\n        |b\n}")
        #expect(tab("if a {\n  |  b\n}", .indentsInLeadingWhitespace) == "if a {\n    |b\n}")
        #expect(tab("if a {\n|\n}", .indentsInLeadingWhitespace) == "if a {\n    |\n}")
        #expect(tab("let x|", .indentsInLeadingWhitespace) == "let x   |")
        #expect(tab("|func", .indentsInLeadingWhitespace, IndentOptions(usesTabs: true)) == "\t|func")
        #expect(tab("if a {\nb|c\n}", .indentsAlways) == "if a {\n    b|c\n}")
        #expect(tab("if a {\n    b|c\n}", .indentsAlways) == nil)
        #expect(tab("ab|", .insertsIndentation) == "ab    |")
        #expect(tab("|a\nb|", .indentsInLeadingWhitespace) == "|    a\n    b|")
        #expect(tab("    a|", .indentsInLeadingWhitespace, backward: true) == "a|")
        #expect(tab("|    a\n    b\n|", .indentsAlways, backward: true) == "|a\nb|\n")
    }

    @Test func commentToggling() {
        func toggle(_ s: String, _ lang: SyntaxLanguage) -> String? {
            let (text, sel) = marked(s)
            return render(text, TypingRules.toggleComment(in: SyntaxDocument(text: text, language: lang), selection: sel))
        }
        #expect(toggle("    let a|", .swift) == "//     let a|")
        #expect(toggle("//     let a|", .swift) == "    let a|")
        #expect(toggle("|a\n\nb|", .c) == "|// a\n\n// b|")
        #expect(toggle("|// a\n// b|", .c) == "|a\nb|")
        #expect(toggle("key: 1|", .yaml) == "# key: 1|")
        #expect(toggle("echo|", .shell) == "# echo|")
        #expect(toggle("  <a/>|", .xml) == "  <!-- <a/> -->|")
        #expect(toggle("  <!-- <a/> -->|", .xml) == "  <a/>|")
        #expect(toggle("|one\ntwo|", .markdown) == "|<!-- one\ntwo -->|")
        #expect(toggle("text|", .plain) == nil)
    }

    @Test func structureIgnoresCommentsAndStrings() {
        let t = "f(\"(\", /* ) */ x) { [1] }\n#define Y {\n"
        let d = SyntaxDocument(text: t, language: .c)
        let events = d.blockEvents(onLine: 0).map { ($0.isOpen ? "+" : "-") + String(Character(UnicodeScalar(d.units[$0.offset])!)) }
        #expect(events == ["+(", "-)", "+{", "+[", "-]", "-}"])
        #expect(d.blockEvents(onLine: 1).isEmpty)
        #expect(d.matchingBracket(at: 1) == 16)
        #expect(d.matchingBracket(at: 16) == 1)
        let s = SyntaxDocument(text: "a {\n  b {\n  }\n}\n", language: .swift)
        #expect(s.blocks() == [SyntaxBlock(startLine: 0, endLine: 3, depth: 0), SyntaxBlock(startLine: 1, endLine: 2, depth: 1)])
        #expect(s.enclosingOpener(before: 8)?.line == 0 && s.enclosingOpener(before: 9)?.line == 1)
    }
}
