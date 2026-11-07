import AppKit
import Foundation
import Testing
@testable import YcodeIDECore
import YcodeProject
@testable import YcodeUI

@MainActor
@Suite(.serialized) struct UISpacingTests {
    static func box(_ v: NSView) -> NSRect {
        let r = v.convert(v.bounds, to: nil)
        let h = v.window?.contentView?.superview?.bounds.height ?? v.window?.frame.height ?? 0
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    func withWindow(_ body: (WorkspaceWindowController, NSWindow) throws -> Void) throws {
        _ = NSApplication.shared
        let prefs = IsolatedPreferences("ui-spacing")
        defer { prefs.restore() }
        let dir = try UISpacingProbeTests.demoPackage()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let wc = WorkspaceWindowController(session: WorkspaceSession(model: try WorkspaceModel(url: dir)), loadDestinations: false,
                                           startLanguageService: false, openFirstFile: false)
        let win = try #require(wc.window)
        defer { win.close() }
        wc.applyDefaultLayout()
        wc.open(path: dir.appendingPathComponent("Sources/Demo/Model.swift").path, line: nil)
        win.contentView?.layoutSubtreeIfNeeded()
        try body(wc, win)
    }

    @Test func projectOutlineStartsSevenPointsBelowTheSelector() throws {
        try withWindow { wc, win in
            let nav = wc.navigator
            let o = nav.outlineView
            #expect(o.numberOfRows >= 3)
            let selector = Self.box(nav.selectorView)
            let rowTop = (win.contentView?.superview?.bounds.height ?? 0) - o.convert(o.rect(ofRow: 0), to: nil).maxY
            #expect(abs(rowTop - (selector.maxY + 7)) <= 0.5, "first row \(rowTop - selector.maxY) points below the selector")
            #expect(o.rect(ofRow: 0).height == 22 && o.rect(ofRow: 1).height == 22)
            nav.select(4)
            nav.select(0)
            win.contentView?.layoutSubtreeIfNeeded()
            let again = (win.contentView?.superview?.bounds.height ?? 0) - o.convert(o.rect(ofRow: 0), to: nil).maxY
            #expect(abs(again - (selector.maxY + 7)) <= 0.5)
        }
    }

    @Test func headerNavigatorsKeepTheirFirstRowBelowTheHeader() throws {
        try withWindow { wc, win in
            let nav = wc.navigator
            let file = "/tmp/DemoTests.swift"
            let found = TestDiscovery.tests(in: "import Testing\n@Test func one() {}\n@Test func two() {}\n", file: file)
            nav.setTests(found, results: [:])
            nav.select(5)
            win.contentView?.layoutSubtreeIfNeeded()
            let o = nav.outlineView
            #expect(o.numberOfRows >= 2)
            let clip = Self.box(nav.scrollClipView)
            let rowTop = (win.contentView?.superview?.bounds.height ?? 0) - o.convert(o.rect(ofRow: 0), to: nil).maxY
            #expect(abs(rowTop - (clip.minY + NavigatorAreaController.clipToFirstRow)) <= 0.5,
                    "first row \(rowTop - clip.minY) points below the clip's top")
            #expect(clip.minY > Self.box(nav.selectorView).maxY)
        }
    }

    @Test func jumpBarIsTheReferenceBandAndASeparator() throws {
        try withWindow { wc, _ in
            let bar = Self.box(wc.editor.jumpBar)
            #expect(bar.minY == 52 && bar.height == 34)
            #expect(Self.box(wc.editor.scrollView).minY <= bar.minY)
            #expect(Self.box(wc.editor.scrollView).minY + wc.editor.scrollView.contentInsets.top == bar.maxY)
        }
    }

    @Test func inspectorRowsKeepTheRightInset() throws {
        try withWindow { wc, _ in
            let insp = wc.inspector
            insp.view.layoutSubtreeIfNeeded()
            let area = Self.box(insp.view)
            let limit = area.maxX - InspectorAreaController.contentInset
            let name = try #require(insp.nameField)
            #expect(abs(Self.box(name).maxX - (area.maxX - 7)) <= 1, "the name field ends \(area.maxX - Self.box(name).maxX) from the edge")
            for key in ["Type", "Location", "Text Encoding", "Line Endings", "Indent Using"] {
                let c = try #require(insp.fileControls[key])
                #expect(Self.box(c).maxX <= limit + 1, "\(key) ends \(area.maxX - Self.box(c).maxX) from the edge")
                #expect(Self.box(c).minX >= area.minX + InspectorAreaController.contentInset)
            }
            let ends = ["Type", "Text Encoding", "Line Endings", "Indent Using"].compactMap { insp.fileControls[$0] }.map { Self.box($0).maxX }
            #expect(Set(ends.map { $0.rounded() }).count == 1)
        }
    }

    @Test func debugAreaBottomBarsShareOneHeight() throws {
        try withWindow { wc, win in
            wc.toggleDebugArea(nil)
            win.contentView?.layoutSubtreeIfNeeded()
            let d = wc.debugArea
            let vars = try #require(d.variablesBarStack), console = try #require(d.consoleBarStack)
            let height = (win.contentView?.superview?.bounds.height ?? 0)
            for bar in [vars, console] {
                let b = Self.box(bar)
                #expect(b.height == DebugAreaController.bottomBarHeight)
                #expect(abs(b.maxY - height) <= 0.5)
                for v in bar.arrangedSubviews where !v.isHidden {
                    let bottom = (v.superview ?? bar).convert(v.alignmentRect(forFrame: v.frame), to: nil).minY
                    #expect(bottom >= 3.5, "\(type(of: v)) is \(bottom) from the window's bottom edge")
                }
            }
        }
    }

    @Test func settingsLabelsAreNotCutOff() throws {
        let t = TestDefaults("ui-spacing-settings")
        defer { t.remove() }
        let wc = SettingsWindowController(prefs: Preferences(defaults: t.defaults), components: [])
        let pane = try #require(wc.pane(GeneralSettingsPane.self))
        pane.view.layoutSubtreeIfNeeded()
        let rows = pane.cards.flatMap(\.rowViews).compactMap { $0 as? SettingsRowView }
        let restore = try #require(rows.first { $0.label.stringValue.hasPrefix("Restore open projects") })
        #expect(restore.help.map { $0.frame.height > 20 } == true)
        for r in rows where !r.label.stringValue.isEmpty {
            #expect(r.label.intrinsicContentSize.width <= r.label.frame.width + 0.5, "\(r.label.stringValue) is cut off")
        }
        wc.window?.close()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 26,
                   "macOS 26 floats the hub's sidebar; the circle ends 5 points before its edge (metrics.md §14.1)"))
    func hubSidebarGroupEndsAtTheSidebarEdge() throws {
        _ = NSApplication.shared
        let prefs = IsolatedPreferences("ui-spacing-hub")
        defer { prefs.restore() }
        let row = DeviceRow(name: "Phone (SwiftCode)", identifier: "spacing-1", platform: "iOS", osVersion: "27.1", state: "Shutdown",
                            model: "SwiftCode Simulator", isAvailable: true, isSwiftCodeRemote: true, isFoldable: false)
        let hub = DevicesController(devices: [], simulators: [row])
        let w = hub.makeWindow()
        w.setFrameAutosaveName("")
        hub.splitView.autosaveName = nil
        defer { w.close() }
        w.contentView?.layoutSubtreeIfNeeded()
        hub.placeFirstDividers()
        let frame = try #require(w.contentView?.superview)
        frame.layoutSubtreeIfNeeded()
        func buttons(_ v: NSView) -> [NSButton] { ((v as? NSButton).map { [$0] } ?? []) + v.subviews.flatMap(buttons) }
        let toggle = try #require(buttons(frame).first { $0.action == #selector(NSSplitViewController.toggleSidebar(_:)) })
        let sidebarEdge: CGFloat = 240
        #expect(abs(Self.box(toggle).maxX - (sidebarEdge - 7)) <= 1.5, "the circle ends \(sidebarEdge - Self.box(toggle).maxX) before the sidebar")
    }
}
