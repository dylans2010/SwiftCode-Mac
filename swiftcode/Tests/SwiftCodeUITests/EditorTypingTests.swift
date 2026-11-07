import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct EditorTypingTests {
    func editor(_ name: String, _ text: String) throws -> (SourceEditorController, NSWindow) {
        _ = NSApplication.shared
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/typing")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        let e = SourceEditorController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = e
        try e.open(file)
        window.makeFirstResponder(e.textView)
        return (e, window)
    }

    func type(_ s: String, into tv: NSTextView) {
        for ch in s {
            let (chars, code, flags): (String, UInt16, NSEvent.ModifierFlags) = switch ch {
            case "\n": ("\r", 36, [])
            case "\t": ("\t", 48, [])
            case "⇤": ("\u{19}", 48, [.shift])
            case "⌫": ("\u{7F}", 51, [])
            default: (String(ch), 0, [])
            }
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0,
                                     context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            tv.keyDown(with: e)
        }
    }

    func caretText(_ e: SourceEditorController) -> String {
        (e.text as NSString).replacingCharacters(in: NSRange(location: e.textView.selectedRange().location, length: 0), with: "|")
    }

    @Test func typingASwiftFile() throws {
        let prefs = IsolatedPreferences("typing")
        defer { prefs.restore() }
        let (e, _) = try editor("Typing.swift", "")
        let tv = e.textView
        type("struct A {", into: tv)
        #expect(caretText(e) == "struct A {|}")
        type("\n", into: tv)
        #expect(caretText(e) == "struct A {\n    |\n}")
        type("func f(x: Int) -> String {\nlet a = (x + 1)", into: tv)
        #expect(caretText(e) == "struct A {\n    func f(x: Int) -> String {\n        let a = (x + 1)|\n    }\n}")
        type("\nreturn \"a\" + String(a)", into: tv)
        #expect(caretText(e) == "struct A {\n    func f(x: Int) -> String {\n        let a = (x + 1)\n        return \"a\" + String(a)|\n    }\n}")
        type("\nswitch a {\ncase 1:\nbreak\ndefault:\nbreak", into: tv)
        #expect(e.text.contains("""
                switch a {
                case 1:
                    break
                default:
                    break
                }
        """))
        let end = (e.text as NSString).range(of: "        }\n    }").location
        tv.setSelectedRange(NSRange(location: end + 9, length: 0))
        type("\n", into: tv)
        type("(", into: tv)
        #expect(e.pendingAutomaticClosers.count == 1)
        type("⌫", into: tv)
        #expect(caretText(e).contains("        }\n        |\n    }"))
        tv.setSelectedRange(NSRange(location: tv.selectedRange().location - 8, length: 0))
        type("\t", into: tv)
        #expect(caretText(e).contains("        }\n        |\n    }"))
        type("⇤", into: tv)
        #expect(caretText(e).contains("        }\n    |\n    }"))
        #expect(tv.undoManager?.canUndo == true)
        let k = (e.text as NSString).range(of: "struct").location
        #expect(e.textView.textStorage?.attribute(.foregroundColor, at: k, effectiveRange: nil) as? NSColor == Theme.color(forToken: SyntaxTokenKind.keyword))
        tv.undoManager?.removeAllActions()
    }

    @Test func typingFollowsTheSettings() throws {
        let prefs = IsolatedPreferences("typing-settings")
        defer { prefs.restore() }
        let p = Preferences.shared
        p.autoInsertClosers = false
        p.encloseSelection = false
        p.autoIndent = false
        p.indentWithTabs = true
        let (e, _) = try editor("Settings.swift", "    if a {")
        let tv = e.textView
        tv.setSelectedRange(NSRange(location: (e.text as NSString).length, length: 0))
        type("(\n", into: tv)
        #expect(caretText(e) == "    if a {(\n    |")
        p.autoIndent = true
        p.autoInsertClosers = true
        p.encloseSelection = true
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        type("\t", into: tv)
        #expect(e.text.hasPrefix("\t    if a {"))
        tv.setSelectedRange((e.text as NSString).range(of: "if a"))
        type("(", into: tv)
        #expect(e.text.contains("(if a)") && (e.text as NSString).substring(with: tv.selectedRange()) == "if a")
        tv.string = "f(<#x#>)"
        e.textDidChange(Notification(name: NSText.didChangeNotification))
        tv.setSelectedRange(NSRange(location: 2, length: 5))
        type("\"", into: tv)
        #expect(e.text == "f(\")")
        tv.undoManager?.removeAllActions()
    }

    @Test func scopeGuidesAndInvisibles() throws {
        let prefs = IsolatedPreferences("typing-guides")
        defer { prefs.restore() }
        let (e, window) = try editor("Guides.swift", "struct A {\n    func f() {\n        a()\n        b()\n    }\n}\n")
        #expect(e.scopeGuideBlocks.isEmpty)
        Preferences.shared.scopeGuides = .lines
        Preferences.shared.showInvisibles = true
        #expect(e.scopeGuideBlocks == [SyntaxBlock(startLine: 0, endLine: 5, depth: 0), SyntaxBlock(startLine: 1, endLine: 4, depth: 1)])
        window.contentView?.layoutSubtreeIfNeeded()
        e.textView.display()
        #expect(EditorMenu.sourceItems.contains { if case .command(let c) = $0 { c.title == "Scope Guides" && c.isAvailable } else { false } })
        #expect(EditorMenu.sourceItems.contains { if case .command(let c) = $0 { c.title == "Invisibles" && c.isAvailable } else { false } })
    }

    @Test func commentsAndReindentByLanguage() throws {
        let prefs = IsolatedPreferences("typing-comments")
        defer { prefs.restore() }
        let (x, _) = try editor("Info.plist", "<dict>\n<key>a</key>\n</dict>\n")
        x.textView.setSelectedRange(NSRange(location: 8, length: 0))
        x.commentSelection(nil)
        #expect(x.text == "<dict>\n<!-- <key>a</key> -->\n</dict>\n")
        x.commentSelection(nil)
        #expect(x.text == "<dict>\n<key>a</key>\n</dict>\n")
        x.textView.setSelectedRange(NSRange(location: 0, length: (x.text as NSString).length))
        #expect(x.reindentLines())
        #expect(x.text == "<dict>\n    <key>a</key>\n</dict>\n")
        let (y, _) = try editor("ci.yml", "a: 1\n")
        y.commentSelection(nil)
        #expect(y.text == "# a: 1\n")
        let (m, _) = try editor("README.md", "- one")
        m.textView.setSelectedRange(NSRange(location: 5, length: 0))
        type("\ntwo\n\n", into: m.textView)
        #expect(m.text == "- one\n- two\n")
        #expect(m.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == Theme.color(forToken: SyntaxTokenKind.listMarker))
    }
}
