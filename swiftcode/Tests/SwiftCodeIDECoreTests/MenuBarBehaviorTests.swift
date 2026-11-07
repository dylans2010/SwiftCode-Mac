import Foundation
import Testing
@testable import SwiftCodeIDECore

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct MenuBarBehaviorTests {
    @Test func titlesInContext() {
        #expect(MenuTitles.title(generic: "Close Document", in: nil) == "Close Document")
        var c = MenuContext()
        c.containerKind = .package
        c.workspaceName = "Obs"
        c.fileName = "Model.swift"
        c.caretLine = 12
        #expect(MenuTitles.title(generic: "Close Tab, Editor Pane, Window Tab, or Window", in: c) == "Close Window")
        c.editorTabCount = 2
        #expect(MenuTitles.title(generic: "Close Tab, Editor Pane, Window Tab, or Window", in: c) == "Close Tab")
        #expect(MenuTitles.title(generic: "Close Document", in: c) == "Close \u{201C}Model.swift\u{201D}")
        #expect(MenuTitles.title(generic: "Close Workspace", in: c) == "Close Package")
        #expect(MenuTitles.title(generic: "Workspace Settings…", in: c) == "Package Settings…")
        #expect(MenuTitles.title(generic: "Add Files…", in: c) == "Add Files to \u{201C}Obs\u{201D}…")
        #expect(MenuTitles.title(generic: "Find in Workspace", in: c) == "Find in Package")
        #expect(MenuTitles.title(generic: "Find and Replace in Workspace…", in: c) == "Find and Replace in Package…")
        #expect(MenuTitles.title(generic: "Find in Selected Groups…", in: c) == "Find in Selected Groups…")
        #expect(MenuTitles.title(generic: "Jump to Line…", in: c) == "Jump to Line in \u{201C}Model.swift\u{201D}…")
        #expect(MenuTitles.title(generic: "Compile File", in: c) == "Compile \u{201C}Model.swift\u{201D}")
        #expect(MenuTitles.title(generic: "Bookmark Line", in: c) == "Bookmark \u{201C}Model.swift\u{201D} Line 12")
        #expect(MenuTitles.title(generic: "Bookmark File With Dialog", in: c) == "Bookmark \u{201C}Model.swift\u{201D}…")
        #expect(MenuTitles.title(generic: "Stage Selected Files", in: c) == "Stage Changes in \u{201C}Model.swift\u{201D}")
        #expect(MenuTitles.title(generic: "Discard Changes in Selected Files…", in: c) == "Discard Changes in \u{201C}Model.swift\u{201D}…")
        #expect(MenuTitles.title(generic: "Mark as Resolved", in: c) == "Mark Selected Files as Resolved")
        c.hasNavigatorFileSelection = true
        #expect(MenuTitles.title(generic: "Stage Selected Files", in: c) == "Stage Changes in Selected Files")
        c.selectedFileIsUntracked = true
        #expect(MenuTitles.title(generic: "Discard Changes in Selected Files…", in: c) == "Move Selected Files to Trash…")
        c.containerKind = .project
        #expect(MenuTitles.title(generic: "Find Next in Workspace", in: c) == "Find Next in Project")
        #expect(MenuTitles.title(generic: "Close Workspace", in: c) == "Close Project")
        c.windowTabCount = 2
        #expect(MenuTitles.title(generic: "Close Window", in: c) == "Close Window Tab")
        c.isPaused = true
        c.breakpointsActive = false
        #expect(MenuTitles.title(generic: "Pause", in: c) == "Continue")
        #expect(MenuTitles.title(generic: "Deactivate Breakpoints", in: c) == "Activate Breakpoints")
    }

    @Test func separatorsCollapseAroundHiddenItems() {
        let shown = MenuConditions.visibleSeparators(isSeparator: [false, true, false, true, false, true, false],
                                                     isVisible: [true, false, false, false, true, false, false])
        #expect(shown == [false, true, false, false, false, false, false])
        #expect(MenuConditions.visibleSeparators(isSeparator: [true, false, true], isVisible: [false, true, false]) == [false, false, false])
    }

    @Test func disabledCommandsHoldTheirShortcuts() {
        let t = TestDefaults("menu-keys")
        defer { t.remove() }
        let p = Preferences(defaults: t.defaults, themesDirectory: swiftcodeDir.appendingPathComponent(".build-ide/menu-keys/Themes"))
        let build = KeyBindings.entries(p).first { $0.title == "Build" }!
        let c = KeyBindings.set(build.id, key: "b", modifiers: [.command, .control], p)
        #expect(c.map(\.title) == ["Compile File"])
        let c2 = KeyBindings.conflicts(key: "[", modifiers: [.command, .shift], excluding: build.id, p)
        #expect(c2.map(\.title) == ["Show Previous Tab"])
        #expect(p.keyBindingOverrides.isEmpty)
    }
}
