import AppKit
import Foundation
import Testing
@testable import YcodeIDECore
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct MenuR43Tests {

    @Test func fileMenuHasOneOpenRecent() throws {
        try MenuBarGoldenTests().withFactoryBar { bar in
            #expect(SwiftCodeDocumentController().maximumRecentDocumentCount == 0)
            let file = try #require(bar.item(withTitle: "File")?.submenu)
            let foreign = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            foreign.submenu = NSMenu(title: "Open Recent")
            foreign.submenu?.addItem(NSMenuItem(title: "Clear Menu", action: NSSelectorFromString("clearRecentDocuments:"), keyEquivalent: ""))
            let open = try #require(file.items.firstIndex { $0.title == "Open…" })
            file.insertItem(foreign, at: open + 1)
            #expect(file.items.filter { $0.title == "Open Recent" }.count == 2)
            MenuBarDelegate.shared.update(file, controller: nil)
            let recents = file.items.filter { $0.title == "Open Recent" }
            #expect(recents.count == 1 && recents.first?.submenu is CommandMenu)
            #expect(recents.first?.submenu?.delegate === RecentProjectsMenuDelegate.shared)
        }
    }

    @Test func helpMenuHasNoSystemFeedbackItem() throws {
        try MenuBarGoldenTests().withFactoryBar { bar in
            let help = try #require(bar.item(withTitle: "Help")?.submenu)
            help.insertItem(NSMenuItem(title: "Send SwiftCode Feedback to Apple", action: NSSelectorFromString("_openFeedbackAssistant:"), keyEquivalent: ""), at: 0)
            help.insertItem(.separator(), at: 1)
            MenuBarDelegate.shared.update(help, controller: nil)
            #expect(help.items.first?.title == "Developer Documentation")
            #expect(!help.items.contains { $0.title.contains("Feedback to Apple") })
            #expect(help.items.contains { $0.title == "Report a Bug…" })
            help.insertItem(NSMenuItem(title: "Send SwiftCode Feedback to Apple", action: NSSelectorFromString("_openFeedbackAssistant:"), keyEquivalent: ""), at: 0)
            help.insertItem(.separator(), at: 1)
            MenuBarDelegate.shared.menuWillOpen(help)
            #expect(help.items.first?.title == "Developer Documentation")
        }
    }

    let r32 = WindowChromeR32Tests()

    func outline(_ wc: WorkspaceWindowController) throws -> NSOutlineView {
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        return try #require(all(wc.navigator.view).compactMap { $0 as? NSOutlineView }.first)
    }

    @discardableResult
    func select(_ path: String, in wc: WorkspaceWindowController) throws -> String {
        wc.navigator.select(0)
        let o = try outline(wc)
        o.expandItem(nil, expandChildren: true)
        func real(_ p: String) -> String { URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        func rowPath(_ r: Int) -> String? { (o.item(atRow: r) as? OutlineItem).flatMap { $0.nodePath ?? $0.path } }
        let row = try #require((0..<o.numberOfRows).first { rowPath($0).map(real) == real(path) })
        o.selectRowIndexes([row], byExtendingSelection: false)
        return try #require(rowPath(row))
    }

    func validated(_ wc: WorkspaceWindowController, _ action: String) throws -> (enabled: Bool, title: String) {
        let spec = try #require(CommandTable.command(action: action))
        let i = CommandMenuItem(title: spec.title, action: NSSelectorFromString(action), keyEquivalent: "")
        i.spec = spec
        let ok = wc.validateMenuItem(i)
        return (ok, i.title)
    }

    func newMenu(_ wc: WorkspaceWindowController) throws -> NSMenu {
        let bar = MainMenu.make()
        let new = try #require(bar.item(withTitle: "File")?.submenu?.item(withTitle: "New")?.submenu)
        MenuBarDelegate.shared.update(new, controller: wc)
        return new
    }

    func visible(_ m: NSMenu) -> [String] { m.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title) }

    @Test func fileFromClipboardFollowsThePasteboard() throws {
        let dir = try r32.package("r43-clipboard")
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard(name: NSPasteboard.Name("org.swiftcode.tests.r43.\(UUID().uuidString)"))
        let old = WorkspaceWindowController.menuPasteboard
        WorkspaceWindowController.menuPasteboard = board
        defer { WorkspaceWindowController.menuPasteboard = old; board.releaseGlobally() }
        let wc = try r32.window(dir)
        wc.open(path: dir.appendingPathComponent("Sources/Chrome/Model.swift").path, line: nil)
        board.clearContents()
        var v = try validated(wc, "newFileFromClipboard:")
        #expect(!v.enabled && v.title == "File from Clipboard")
        board.setString("let pasted = 42\n", forType: .string)
        v = try validated(wc, "newFileFromClipboard:")
        #expect(v.enabled && v.title == "New File from Clipboard")
        let url = try #require(wc.newFileFromClipboard(nil))
        #expect(url.lastPathComponent == "File" && url.deletingLastPathComponent().lastPathComponent == "Chrome")
        #expect(try String(contentsOf: url, encoding: .utf8) == "let pasted = 42\n")
        #expect(wc.editor.fileURL?.standardizedFileURL == url.standardizedFileURL && wc.editor.text == "let pasted = 42\n")
        #expect(MenuTitles.title(generic: "File from Clipboard", in: nil) == "File from Clipboard")
    }

    @Test func newMenuAndFindFollowTheNavigatorSelection() throws {
        let dir = try r32.package("r43-selection")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        let groups = ["Group", "Group without Folder", "Group from Selection", "Group from Selection without Folder"]
        #expect(wc.projectNavigatorSelection == nil)
        #expect(Set(groups + ["Folder", "Folder from Selection"]).isSubset(of: visible(try newMenu(wc))))
        #expect(try validated(wc, "newFolder:").enabled == false)
        var find = try validated(wc, "findInSelectedGroups:")
        #expect(!find.enabled && find.title == "Find in Selected Groups…")
        let model = try select(dir.appendingPathComponent("Sources/Chrome/Model.swift").path, in: wc)
        #expect(wc.projectNavigatorSelection?.kind == .file && wc.projectSelectionIsInFolder)
        let shown = visible(try newMenu(wc))
        #expect(groups.allSatisfy { !shown.contains($0) } && shown.suffix(2) == ["Folder", "Folder from Selection"])
        #expect(try validated(wc, "newFolder:").enabled)
        find = try validated(wc, "findInSelectedGroups:")
        #expect(find.enabled && find.title == "Find in Selected File…")
        wc.findInSelectedGroups(nil)
        #expect(wc.navigator.selectedIndex == 3 && wc.navigator.findScopeValue == .group(model))
        wc.navigator.find("public")
        #expect(wc.navigator.shownRows.count == 1 && wc.navigator.shownRows.first?.title.hasPrefix("Model.swift") == true)
        let folder = try select(dir.appendingPathComponent("Sources/Chrome").path, in: wc)
        find = try validated(wc, "findInSelectedGroups:")
        #expect(find.enabled && find.title == "Find in Selected Groups…")
        wc.findInSelectedGroups(nil)
        wc.navigator.find("public")
        #expect(wc.navigator.findScopeValue == .group(folder) && wc.navigator.shownRows.count == 2)
    }

    @Test func groupItemsStayForAFileInAGroup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-r43-groups-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Hello.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: swiftcodeDir.appendingPathComponent("Tests/SwiftCodeProjectTests/Fixtures/Hello.xcodeproj/project.pbxproj"),
                                         to: proj.appendingPathComponent("project.pbxproj"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Hello"), withIntermediateDirectories: true)
        let main = dir.appendingPathComponent("Hello/main.swift")
        try "print(1)\n".write(to: main, atomically: true, encoding: .utf8)
        let wc = try r32.window(proj)
        let path = try #require(wc.session.model.root.allFiles.compactMap(\.path).first { $0.hasSuffix("/main.swift") })
        try select(path, in: wc)
        #expect(wc.projectNavigatorSelection?.kind == .file && !wc.projectSelectionIsInFolder)
        let shown = visible(try newMenu(wc))
        #expect(["Group", "Group without Folder", "Group from Selection", "Group from Selection without Folder", "Folder"].allSatisfy(shown.contains))
    }

    @Test func copyAndPasteAreSubmenus() throws {
        try MenuBarGoldenTests().withFactoryBar { bar in
            let edit = try #require(bar.item(withTitle: "Edit")?.submenu)
            let top = edit.items.prefix(9).map { $0.isSeparatorItem ? "—" : $0.title }
            #expect(top == ["Undo", "Redo", "—", "Cut", "Copy", "Paste", "Duplicate", "Delete", "—"])
            let copy = try #require(edit.item(withTitle: "Copy"))
            let paste = try #require(edit.item(withTitle: "Paste"))
            #expect(copy.keyEquivalent.isEmpty && paste.keyEquivalent.isEmpty)
            #expect(copy.submenu?.items.map(\.title) == ["Copy", "Copy File and Line", "Copy Symbol Name", "Copy Qualified Symbol Name"])
            #expect(copy.submenu?.items.allSatisfy { !$0.isAlternate } == true)
            #expect(copy.submenu?.items.map { MainMenu.canonicalShortcut($0) } == ["⌘C", "⌃⌥⌘C", "⌃⇧⌘C", "⌃⌥⇧⌘C"])
            #expect(paste.submenu?.items.map(\.title) == ["Paste", "Move Item Here", "Paste and Preserve Formatting"])
            #expect(paste.submenu?.item(withTitle: "Move Item Here")?.isHidden == true)
            var ctx = MenuContext()
            #expect(!MenuConditions.isShown(.itemToMove, in: ctx))
            ctx.hasItemToMove = true
            #expect(MenuConditions.isShown(.itemToMove, in: ctx))
        }
    }

    @Test func copyVariantsAndPasteAreEnabledOnTheirOwn() throws {
        let dir = try r32.package("r43-copy")
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard(name: NSPasteboard.Name("org.swiftcode.tests.r43.\(UUID().uuidString)"))
        let old = WorkspaceWindowController.menuPasteboard
        WorkspaceWindowController.menuPasteboard = board
        defer { WorkspaceWindowController.menuPasteboard = old; board.releaseGlobally() }
        let wc = try r32.window(dir)
        wc.open(path: dir.appendingPathComponent("Sources/Chrome/Model.swift").path, line: nil)
        let tv = wc.editor.textView
        tv.setSelectedRange(NSRange(location: 14, length: 0))
        #expect(!tv.validateMenuItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")))
        #expect(try validated(wc, "copyFileAndLine:").enabled)
        #expect(try validated(wc, "copySymbolName:").enabled && (try validated(wc, "copyQualifiedSymbolName:").enabled))
        board.clearContents()
        #expect(try validated(wc, "pasteAndPreserveFormatting:").enabled == false)
        board.setString("    let x = 1\n", forType: .string)
        #expect(try validated(wc, "pasteAndPreserveFormatting:").enabled)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        wc.pasteAndPreserveFormatting(nil)
        #expect(wc.editor.text.hasPrefix("    let x = 1\npublic struct Model"))
    }
}
