import AppKit
import Foundation
import Testing
import YcodeBuild
@testable import YcodeUI

@MainActor
@Suite(.serialized) struct EditorChromeR40Tests {
    let r32 = WindowChromeR32Tests()

    @Test func jumpBarHidesTheExtensionPerTheSetting() throws {
        try SettingsR33Tests().withPrefs("r40-ext") { p, _ in
            let dir = try r32.package("r40-e1")
            defer { try? FileManager.default.removeItem(at: dir) }
            let wc = try r32.window(dir)
            let helper = dir.appendingPathComponent("Sources/Chrome/Helper.swift").path
            wc.open(path: helper, line: nil)
            #expect(wc.editor.jumpBarTitles.contains("Helper") && !wc.editor.jumpBarTitles.contains("Helper.swift"))
            #expect(wc.editor.jumpBarTitles.contains("Chrome"))
            p.fileExtensions = .show
            #expect(wc.editor.jumpBarTitles.contains("Helper.swift"))
            p.fileExtensions = .hide
            #expect(wc.editor.jumpBarTitles.contains("Helper"))
            let plist = dir.appendingPathComponent("Sources/Chrome/Data.plist")
            try "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict/>\n</plist>\n".write(to: plist, atomically: true, encoding: .utf8)
            let again = try r32.window(dir)
            again.open(path: plist.path, line: nil)
            #expect(again.editor.auxiliary != nil && again.editor.jumpBarTitles.contains("Data") && !again.editor.jumpBarTitles.contains("Data.plist"))
        }
        #expect(WorkspaceWindowController.jumpBarFileTitle("Model.swift", hideExtension: true) == "Model")
        #expect(WorkspaceWindowController.jumpBarFileTitle("Model.swift", hideExtension: false) == "Model.swift")
        #expect(WorkspaceWindowController.jumpBarFileTitle(".gitignore", hideExtension: true) == ".gitignore")
    }

    @Test func issueClusterIsThreeGlyphOnlyControls() throws {
        let dir = try r32.package("r40-e2")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        let model = dir.appendingPathComponent("Sources/Chrome/Model.swift").path
        wc.open(path: model, line: nil)
        wc.session.packageIssues = [Diagnostic(severity: .warning, message: "value is never read", location: .init(file: model, line: 2))]
        #expect(Array(wc.editor.jumpBarTitles.suffix(3)) == ["Show Previous Issue", "Issues", "Show Next Issue"])
        #expect(wc.editor.jumpBarIssueArrowSymbols == ["chevron.left", "chevron.right"])
        let glyph = try #require(wc.editor.jumpBarIssueGlyph)
        #expect(glyph.symbol == "exclamationmark.triangle.fill" && glyph.title.isEmpty)
        wc.session.packageIssues.append(Diagnostic(severity: .error, message: "missing return", location: .init(file: model, line: 3)))
        #expect(wc.editor.jumpBarIssueGlyph?.symbol == "xmark.octagon.fill")
        #expect(wc.editor.jumpBarIssueTitles == ["Value is never read", "Missing return"])
    }

    @Test func lineAndColumnAreRealAndAFileOpensAtOneOne() throws {
        let dir = try r32.package("r40-e3")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        let model = dir.appendingPathComponent("Sources/Chrome/Model.swift").path
        let helper = dir.appendingPathComponent("Sources/Chrome/Helper.swift").path
        let label = wc.debugArea.positionLabel
        wc.open(path: model, line: nil)
        #expect(label.stringValue == "Line: 1  Col: 1")
        #expect(wc.editor.textView.selectedRange() == NSRange(location: 0, length: 0))
        let line2 = try #require(wc.editor.textView.lineIndex.range(ofLine: 2))
        wc.editor.textView.setSelectedRange(NSRange(location: line2.location + 4, length: 0))
        #expect(label.stringValue == "Line: 2  Col: 5")
        wc.editor.textView.setSelectedRange(NSRange(location: (wc.editor.text as NSString).length, length: 0))
        wc.open(path: helper, line: nil)
        #expect(label.stringValue == "Line: 1  Col: 1")
        wc.open(path: model, line: 3)
        #expect(label.stringValue == "Line: 3  Col: 1")
        wc.editor.textView.insertText("\tx", replacementRange: NSRange(location: 0, length: 0))
        wc.editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(label.stringValue == "Line: 1  Col: 3")
    }

    @Test func testDiamondsReplaceNumbersAndIssuesHaveNoGutterGlyph() throws {
        let dir = try r32.package("r40-e6")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        let model = dir.appendingPathComponent("Sources/Chrome/Model.swift").path
        wc.open(path: model, line: nil)
        let g = wc.editor.gutter
        wc.editor.setTests([2: .passed])
        #expect(g.numberColumnContent(line: 1) == "1")
        #expect(g.numberColumnContent(line: 2) == "diamond:passed")
        let c = g.testDiamondCenterX(numberWidth: g.ruleThickness - GutterView.ribbonWidth)
        #expect(c > 20 && g.isOnTestDiamond(x: c) && !g.isOnTestDiamond(x: 2))
        wc.editor.setTests([:])

        wc.window?.contentView?.layoutSubtreeIfNeeded()
        func render() throws -> Data {
            let rep = try #require(g.bitmapImageRepForCachingDisplay(in: g.bounds))
            g.cacheDisplay(in: g.bounds, to: rep)
            return try #require(rep.tiffRepresentation)
        }
        let before = try render()
        let fixIt = Diagnostic.FixIt(file: model, start: .init(file: model, line: 2, column: 5), end: .init(file: model, line: 2, column: 11),
                                     replacement: "internal")
        wc.session.packageIssues = [Diagnostic(severity: .error, message: "use internal", location: .init(file: model, line: 2, column: 5), fixIts: [fixIt])]
        #expect(g.marks.issues[2] == .error && g.marks.fixable == [2])
        #expect(try render() == before)

        let r = try #require(wc.editor.textView.lineRect(2))
        #expect(wc.editor.annotationLine(at: NSPoint(x: r.maxX - 10, y: r.midY)) == 2)
        #expect(wc.editor.annotationLine(at: NSPoint(x: r.minX + 8, y: r.midY)) == nil)
        let menu = try #require(wc.editor.fixItMenu(line: 2))
        #expect(menu.items.map(\.title) == ["Use internal", "Fix"])
        #expect(wc.editor.fixItMenu(line: 1) == nil)
        let fix = menu.items[1]
        NSApp.sendAction(try #require(fix.action), to: fix.target, from: fix)
        #expect(wc.editor.text.contains("internal var value"))
    }

    func previewPackage(_ tag: String) throws -> URL {
        let dir = try r32.package(tag)
        try "import SwiftUI\n\nstruct Card: View {\n    var body: some View { Text(\"Hi\") }\n}\n\n#Preview {\n    Card()\n}\n"
            .write(to: dir.appendingPathComponent("Sources/Chrome/Card.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func canvasShowsForFilesWithPreviews() throws {
        let dir = try previewPackage("r40-e7")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        let card = dir.appendingPathComponent("Sources/Chrome/Card.swift").path
        let model = dir.appendingPathComponent("Sources/Chrome/Model.swift").path
        wc.open(path: model, line: nil)
        #expect(wc.canvas == nil && wc.isCanvasModeOn && wc.activeEditorMode == .canvas)
        wc.open(path: card, line: nil)
        let c = try #require(wc.canvas)
        #expect(wc.canvasShownAutomatically && wc.activeEditorMode == .canvas)
        #expect(c.isPaused && c.names == ["Preview"])
        #expect(wc.editorArea.canvasPlacement != nil)
        #expect(c.devicePopUpTitle == "Automatic \u{2013} My Mac")
        c.view.layoutSubtreeIfNeeded()
        let pill = c.pausedCapsule.convert(c.pausedCapsule.bounds, to: c.body)
        #expect(c.body.bounds.maxY - pill.maxY <= 20 && abs(pill.midX - c.body.bounds.midX) < 1)
        let device = c.devicePopUp.convert(c.devicePopUp.bounds, to: c.view)
        #expect(device.minX < 20 && device.minY < 28)
        wc.open(path: model, line: nil)
        #expect(wc.canvas == nil && wc.isCanvasModeOn)
        wc.open(path: card, line: nil)
        #expect(wc.canvas != nil)
        wc.toggleCanvas(nil)
        #expect(wc.canvas == nil && !wc.isCanvasModeOn && wc.activeEditorMode == nil)
        wc.open(path: model, line: nil)
        wc.open(path: card, line: nil)
        #expect(wc.canvas == nil)
        wc.toggleCanvas(nil)
        #expect(wc.canvas != nil)
        wc.open(path: model, line: nil)
        #expect(wc.canvas == nil && wc.isCanvasModeOn)
        wc.toggleCanvas(nil)
        wc.toggleCanvas(nil)
        #expect(wc.isCanvasModeOn && wc.canvas == nil && wc.editorArea.canvas == nil)
    }

    @Test func canvasModeIsOnInEveryNewEditor() throws {
        let dir = try previewPackage("r43-e10")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        let model = dir.appendingPathComponent("Sources/Chrome/Model.swift").path
        let card = dir.appendingPathComponent("Sources/Chrome/Card.swift").path
        wc.open(path: model, line: nil)
        let item = NSMenuItem(title: "Canvas", action: #selector(WorkspaceWindowController.toggleCanvas(_:)), keyEquivalent: "")
        _ = wc.validateMenuItem(item)
        #expect(item.state == .on && wc.editorModesControl.isSelected(forSegment: 0))
        #expect(wc.canvas == nil && wc.editorArea.canvas == nil && wc.editorArea.canvasPlacement == nil)
        wc.showEditorOnly(nil)
        _ = wc.validateMenuItem(item)
        #expect(item.state == .off && !wc.editorModesControl.isSelected(forSegment: 0))
        wc.toggleCanvas(nil)
        wc.toggleAssistant(nil)
        #expect(!wc.isCanvasModeOn && wc.activeEditorMode == .assistant)
        wc.toggleAssistant(nil)
        wc.open(path: card, line: nil)
        #expect(wc.canvas == nil && wc.activeEditorMode == nil)
        let other = try r32.window(dir)
        other.open(path: card, line: nil)
        #expect(other.isCanvasModeOn && other.canvas != nil)
    }

    @Test func savingAPreviewBringsUpTheCanvas() throws {
        let dir = try previewPackage("r43-e10-save")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        wc.open(path: dir.appendingPathComponent("Sources/Chrome/Model.swift").path, line: nil)
        #expect(wc.canvas == nil && wc.isCanvasModeOn)
        let tv = wc.editor.textView
        tv.insertText("\n#Preview { Text(\"x\") }\n", replacementRange: NSRange(location: (tv.string as NSString).length, length: 0))
        try wc.editor.save()
        wc.scheduleCanvasRefresh(try #require(wc.editor.fileURL))
        #expect(wc.canvas != nil)
    }

    @Test func canvasDoesNotPushAsideAnotherEditorMode() throws {
        let dir = try previewPackage("r40-e7-assistant")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        wc.open(path: dir.appendingPathComponent("Sources/Chrome/Model.swift").path, line: nil)
        wc.toggleAssistant(nil)
        wc.open(path: dir.appendingPathComponent("Sources/Chrome/Card.swift").path, line: nil)
        #expect(wc.canvas == nil && wc.activeEditorMode == .assistant)
    }

    @Test func canvasAutoShowRule() {
        #expect(CanvasAutoShow.hasPreviews(fileName: "A.swift", text: "#Preview { Text(\"a\") }"))
        #expect(CanvasAutoShow.hasPreviews(fileName: "A.swift", text: "struct P: PreviewProvider { static var previews: some View { Text(\"a\") } }"))
        #expect(!CanvasAutoShow.hasPreviews(fileName: "A.swift", text: "// #Preview in a comment\nlet a = 1"))
        #expect(!CanvasAutoShow.hasPreviews(fileName: "A.m", text: "#Preview"))
        let d = CanvasAutoShow.decide
        #expect(d(true, false, true) == .show)
        #expect(d(true, false, false) == .keep)
        #expect(d(false, true, true) == .hide)
        #expect(d(false, false, true) == .keep)
        #expect(d(true, true, false) == .hide)
        #expect(d(true, true, true) == .keep)
    }
}
