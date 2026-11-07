import AppKit
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

@MainActor
@Suite(.serialized) struct LiquidGlassTests {

    @Test func toolbarItemsAreGlassShapes() throws {
        guard #available(macOS 26, *) else { return }
        let r32 = WindowChromeR32Tests()
        let dir = try r32.package("glass-toolbar")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        #expect((0..<2).map { wc.leftPanesControl.width(forSegment: $0) } == [31.5, 31.5])
        #expect((0..<3).map { wc.editorModesControl.width(forSegment: $0) } == [35, 35, 35])
        let items = Dictionary((wc.window?.toolbar?.items ?? []).map { ($0.itemIdentifier.rawValue, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(items["scheme"]?.isBordered == true && items["issues"]?.isBordered == true)
        #expect(items["activity"]?.isBordered == false)
        let run = try #require(items["run"]?.view as? NSSegmentedControl)
        #expect((0..<2).map { run.width(forSegment: $0) } == [30, 30])
        let ids = wc.toolbarDefaultItemIdentifiers(NSToolbar()).map(\.rawValue)
        let conv = try #require(ids.firstIndex(of: "newConversation")), scheme = try #require(ids.firstIndex(of: "scheme"))
        #expect(ids[conv + 1] == NSToolbarItem.Identifier.space.rawValue && conv + 2 == scheme)
        #expect(ids.firstIndex(of: "run")! + 1 == ids.firstIndex(of: NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue)!)
        #expect(items["issues"]?.isHidden == true && !wc.overflowedToolbarItems.contains("issues"))
    }

    @Test func navigatorBarsFloatOverTheOutline() throws {
        guard #available(macOS 26, *) else { return }
        let nav = NavigatorInspectorR45Tests().laidOutNavigator()
        nav.view.setFrameSize(NSSize(width: 290, height: 600))
        nav.view.layoutSubtreeIfNeeded()
        let sel = nav.selectorView.frame
        #expect(sel.size == NSSize(width: 278, height: 30) && sel.minX == 6, "\(sel)")
        #expect(!nav.selectorPill.isHidden && nav.selectorPill.frame.size == NavigatorAreaController.selectorPillSize)
        let plus = nav.plusGlass.frame, field = nav.filterGlass.frame
        #expect(plus.size == NavigatorAreaController.plusSize && abs(plus.minX - 6) <= 0.5, "\(plus)")
        #expect(field.height == 30 && abs(field.minY - 7) <= 0.5 && abs(field.minX - plus.maxX - NavigatorAreaController.plusToFilter) <= 0.5 && field.width == 242 && abs(nav.view.bounds.maxX - field.maxX - 6) <= 0.5, "\(field)")
        let scroll = nav.scrollView
        let inRoot = scroll.convert(scroll.bounds, to: nav.view)
        #expect(abs(inRoot.maxY - sel.maxY) <= 0.5 && abs(inRoot.minY - field.minY) <= 0.5, "\(inRoot)")
        #expect(abs(scroll.scrollerInsets.top - sel.height - 3) <= 0.5 && abs(scroll.scrollerInsets.bottom - field.height - 11) <= 0.5,
                "\(scroll.scrollerInsets)")
        let row0 = nav.outlineView.convert(nav.outlineView.rect(ofRow: 0), to: nav.view)
        #expect(nav.outlineView.numberOfRows == 0 || abs(sel.minY - row0.maxY - NavigatorAreaController.firstRowGap) <= 0.5, "\(row0) \(sel)")
        #expect(scroll.contentInsets.top > 0 && scroll.contentInsets.bottom >= nav.filterGlass.frame.height)
        #expect(!nav.scrollClipView.clipsToBounds)
        nav.select(3)
        nav.view.layoutSubtreeIfNeeded()
        #expect(nav.scrollClipView.clipsToBounds && abs(scroll.frame.maxY - nav.scrollClipView.bounds.maxY) <= 0.5)
        #expect(abs(scroll.contentInsets.top - (NavigatorAreaController.clipToFirstRow - nav.outlineTopPadding)) <= 0.25)
        nav.select(0)
        nav.view.layoutSubtreeIfNeeded()
        #expect(!nav.scrollClipView.clipsToBounds)
    }

    @Test func inspectorBarDividerAndDebugBar() throws {
        guard #available(macOS 26, *) else { return }
        let r32 = WindowChromeR32Tests()
        let dir = try r32.package("glass-areas")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wc = try r32.window(dir)
        wc.window?.contentView?.layoutSubtreeIfNeeded()
        let bar = wc.inspector.tabBarView.frame
        let width = wc.inspector.view.bounds.width
        #expect(bar.height == 30 && abs(bar.minX - 6) <= 0.5 && abs(width - bar.maxX - 6) <= 0.5, "\(bar)")
        #expect(wc.inspector.inspectorItemFlushHeight(in: wc))
        #expect(wc.debugArea.debugBar.frame.height == 36)
        #expect(wc.editorArea.view.additionalSafeAreaInsets.bottom == 36)
    }

    @Test func welcomeGeometry() throws {
        guard #available(macOS 26, *) else { return }
        let td = TestDefaults("glass-welcome")
        defer { td.remove() }
        let w = WelcomeWindowController(recents: RecentProjects(defaults: td.defaults))
        let content = try #require(w.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let h = content.bounds.height
        let box = w.recentsBox.frame
        #expect(box.minX == 60 && box.width == 360 && h - box.maxY == 295 && box.height == 277, "\(box)")
        #expect(w.recentsBox.layer?.cornerRadius == 12 && w.recentsBox.layer?.borderWidth == 0 || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        #expect(w.table.rowHeight == 47 && w.table.intercellSpacing.height == 0)
        #expect(w.tableView(w.table, rowViewForRow: 0) is RecentRowView)
        #expect([w.openButton, w.cloneButton].allSatisfy { $0.bezelStyle == .push && $0.borderShape == .capsule })
    }
}

extension InspectorAreaController {
    func inspectorItemFlushHeight(in wc: WorkspaceWindowController) -> Bool {
        guard let window = wc.window, let content = window.contentView else { return false }
        let r = view.convert(view.bounds, to: content)
        return abs(r.maxY - content.bounds.maxY) <= 0.5 && abs(r.maxX - content.bounds.maxX) <= 0.5 && wc.inspectorItem.allowsFullHeightLayout
    }
}

@MainActor
@Suite(.serialized) struct NavigatorBottomBarGlyphTests {
    static func inkRange(_ view: NSView) -> ClosedRange<CGFloat>? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
        var lo = Int.max, hi = Int.min
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                lo = min(lo, x); hi = max(hi, x)
                break
            }
        }
        guard lo <= hi else { return nil }
        return CGFloat(lo) / scale...CGFloat(hi + 1) / scale
    }

    @Test func plusIsCentredWithNoArrow() throws {
        guard #available(macOS 26, *) else { return }
        let nav = NavigatorInspectorR45Tests().laidOutNavigator()
        nav.view.setFrameSize(NSSize(width: 290, height: 600))
        nav.view.layoutSubtreeIfNeeded()
        let button = nav.addBreakpointButton
        #expect((button.cell as? NSPopUpButtonCell)?.arrowPosition == .noArrow)
        let ink = try #require(Self.inkRange(button))
        let circle = nav.plusGlass.convert(nav.plusGlass.bounds, to: button)
        let left = ink.lowerBound - circle.minX, right = circle.maxX - ink.upperBound
        #expect(ink.upperBound - ink.lowerBound <= 12.5, "\(ink)")
        #expect(abs(left - right) <= 1, "left \(left), right \(right)")
    }

    @Test func optionsGlyphAndTextStartWhereTheReferenceDoes() throws {
        guard #available(macOS 26, *) else { return }
        let nav = NavigatorInspectorR45Tests().laidOutNavigator()
        nav.view.setFrameSize(NSSize(width: 290, height: 600))
        nav.view.layoutSubtreeIfNeeded()
        let options = nav.filterOptions
        let ink = try #require(Self.inkRange(options))
        let capsule = nav.filterGlass.convert(nav.filterGlass.bounds, to: options)
        let start = ink.lowerBound - capsule.minX, end = ink.upperBound - capsule.minX
        #expect(abs(start - 7.5) <= 1, "glyph starts \(start)")
        #expect(abs(end - 27.5) <= 1.5, "glyph ends \(end)")
        let field = try #require(nav.filter as? NavigatorFilterField)
        #expect(field.leadingInset == NavigatorAreaController.filterTextInset)
    }
}
