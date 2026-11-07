import AppKit
import Testing
@testable import YcodeUI

@MainActor
@Suite struct ProjectEditorEmptyTableTests {
    @Test func placeholderSitsBelowHeaderCentered() throws {
        let t = StaticTable(columns: ["Name", "Status"], rows: [], emptyText: "Add development assets here")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView!.addSubview(t.container)
        t.container.frame = window.contentView!.bounds
        window.contentView!.layoutSubtreeIfNeeded()
        let label = try #require(t.emptyLabel)
        let scroll = try #require(t.table.enclosingScrollView)
        let header = try #require(t.table.headerView)
        let root = window.contentView!
        let l = label.convert(label.bounds, to: root)
        let h = header.convert(header.bounds, to: root)
        let s = scroll.convert(scroll.bounds, to: root)
        #expect(h.height > 0)
        #expect(!l.intersects(h), "placeholder \(l) overlaps header \(h) in \(s)")
        let body = NSRect(x: s.minX, y: s.minY, width: s.width, height: h.minY - s.minY)
        #expect(body.contains(l))
        #expect(abs(l.midX - body.midX) < 1)
        #expect(abs(l.midY - body.midY) < 3)
    }
}
