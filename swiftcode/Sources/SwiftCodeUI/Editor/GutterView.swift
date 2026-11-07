import AppKit
import SwiftCodeBuild
import SwiftCodeIDECore

@MainActor
public final class GutterView: NSRulerView, NSViewToolTipOwner {
    public struct Marks {
        public var breakpoints: [Int: Bool] = [:]
        public var breakpointsActive = true
        public var customized: Set<Int> = []
        public var issues: [Int: Diagnostic.Severity] = [:]
        public var currentLine: Int?
        public var tests: [Int: TestStatusMark] = [:]
        public var fixable: Set<Int> = []
        public var issuesStale = false
        public var changes: [Int: LineDiff.Row.Kind] = [:]
        public var coverage: [Int: Int] = [:]
    }

    public enum TestStatusMark: Equatable { case notRun, passed, failed }

    public var marks = Marks() { didSet { needsDisplay = true } }
    public var showsLineNumbers = true { didSet { needsDisplay = true } }
    public var caretLine: Int? { didSet { if oldValue != caretLine { needsDisplay = true } } }
    public var lineIndex = LineIndex("") { didSet { needsDisplay = true } }
    public var onClick: ((Int) -> Void)?
    public var onMove: ((Int, Int) -> Void)?
    public var onRemove: ((Int) -> Void)?
    public var onEdit: ((Int) -> Void)?
    public var onRunTest: ((Int) -> Void)?
    public var onRibbonClick: ((Int) -> Void)?
    public var onFixIt: ((Int) -> Void)?
    public var foldStarts: [Int: Bool] = [:] { didSet { needsDisplay = true } }

    static let ribbonWidth: CGFloat = 12
    public static let changeColumnWidth: CGFloat = 11
    static let baseThickness = CGFloat(EditorMetrics.codeColumn)

    public var showsChangeColumn = false {
        didSet {
            guard oldValue != showsChangeColumn else { return }
            ruleThickness = Self.baseThickness + authorsInset
            updateChangeToolTips()
            needsDisplay = true
        }
    }
    public var showsAuthors = GitBlameSettings.showInlineBlame {
        didSet {
            guard oldValue != showsAuthors else { return }
            ruleThickness = Self.baseThickness + authorsInset
            updateChangeToolTips()
            needsDisplay = true
        }
    }
    public static let authorsColumnWidth: CGFloat = 170
    public var authorBlocks: [GitBlame.Block] = [] { didSet { if oldValue != authorBlocks { needsDisplay = true } } }
    private var avatarImageCache: [String: NSImage] = [:]
    public var onAuthorsClick: ((Int) -> Void)?
    var authorsInset: CGFloat { showsAuthors ? Self.authorsColumnWidth : 0 }
    public var changeRegions: [SourceChangeRegion] = [] {
        didSet {
            guard oldValue != changeRegions else { return }
            updateChangeToolTips()
            needsDisplay = true
        }
    }
    public var onChangeClick: ((Int) -> Void)?
    var leftInset: CGFloat { authorsInset + (showsChangeColumn ? Self.changeColumnWidth : 0) }
    public var showsRibbon = true { didSet { needsDisplay = true } }
    public var showsCoverage = false { didSet { needsDisplay = true } }
    static let coverageWidth: CGFloat = 4
    private var textView: NSTextView? { clientView as? NSTextView }

    public init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.baseThickness
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    func visibleLines() -> [(line: Int, rect: NSRect)] {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager else { return [] }
        var out: [(Int, NSRect)] = []
        let visible = tv.visibleRect
        let origin = tv.textContainerOrigin
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > visible.maxY { return false }
            if frame.maxY >= visible.minY {
                let offset = tcm.offset(from: tcm.documentRange.location, to: fragment.rangeInElement.location)
                let first = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
                let r = NSRect(x: 0, y: frame.minY + origin.y, width: 0, height: first)
                let inGutter = self.convert(r, from: tv)
                out.append((self.lineIndex.line(at: offset), inGutter))
            }
            return true
        }
        return out
    }

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let numberWidth = ruleThickness - Self.ribbonWidth

        let font = Theme.gutterFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.lineNumberColor]
        let inset = leftInset
        let rows = visibleLines()
        if let l = caretLine, let r = rows.first(where: { $0.line == l })?.rect {
            Theme.currentLineBandColor.setFill()
            let x = authorsInset + CGFloat(EditorMetrics.currentLineBandStart)
            let band = NSRect(x: x, y: r.minY, width: bounds.width - x, height: Theme.lineHeight)
            let radius = CGFloat(EditorMetrics.currentLineBandRadius)
            let p = NSBezierPath(roundedRect: band.insetBy(dx: 0, dy: 0), xRadius: radius, yRadius: radius)
            p.append(NSBezierPath(rect: NSRect(x: band.midX, y: band.minY, width: band.width / 2, height: band.height)))
            p.windingRule = .nonZero
            p.fill()
        }
        if showsAuthors { drawAuthors(rows) }
        if showsChangeColumn { drawChangeBars(rows) }
        for (line, r) in rows {
            let row = NSRect(x: 2 + inset, y: r.minY, width: numberWidth - 3 - inset, height: max(r.height, 14))
            if let enabled = marks.breakpoints[line] {
                drawBreakpoint(in: row, enabled: enabled && marks.breakpointsActive, customized: marks.customized.contains(line))
            }
            if line == marks.currentLine {
                Theme.currentLineColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(rect: NSRect(x: inset, y: row.minY, width: 3, height: row.height)).fill()
            }
            if let t = marks.tests[line] {
                drawTestDiamond(t, at: NSPoint(x: testDiamondCenterX(numberWidth: numberWidth), y: row.midY))
            } else if showsLineNumbers {
                let isBP = marks.breakpoints[line] != nil
                var a = attrs
                if isBP { a[.foregroundColor] = NSColor.white } else if line == caretLine { a[.foregroundColor] = Theme.textColor }
                let s = NSAttributedString(string: "\(line)", attributes: a)
                s.draw(at: NSPoint(x: lineNumberEnd - s.size().width, y: r.minY + baselineOffset - font.ascender))
            }
            if showsRibbon, let folded = foldStarts[line] {
                drawFoldMark(folded: folded, at: NSPoint(x: numberWidth + Self.ribbonWidth / 2, y: row.midY))
            }
            if let k = marks.changes[line] {
                (k == .added ? NSColor.systemGreen : (k == .removed ? NSColor.systemRed : NSColor.systemBlue)).setFill()
                NSRect(x: bounds.width - 3, y: k == .removed ? row.minY - 1 : row.minY, width: 3, height: k == .removed ? 3 : row.height).fill()
            }
            if showsCoverage, let count = marks.coverage[line] { drawCoverage(count, in: row) }
        }
    }

    private func drawCoverage(_ count: Int, in row: NSRect) {
        (count == 0 ? NSColor.systemRed.withAlphaComponent(0.6) : NSColor.secondaryLabelColor.withAlphaComponent(0.25)).setFill()
        NSRect(x: bounds.width - 4 - Self.coverageWidth, y: row.minY, width: Self.coverageWidth, height: row.height).fill()
    }

    public func coverageText(line: Int) -> String? {
        guard showsCoverage, let c = marks.coverage[line] else { return nil }
        return "\(c)"
    }

    private func drawBreakpoint(in row: NSRect, enabled: Bool, customized: Bool = false) {
        let r = row.insetBy(dx: 0, dy: 1)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - 6, y: r.minY))
        p.line(to: NSPoint(x: r.maxX, y: r.midY))
        p.line(to: NSPoint(x: r.maxX - 6, y: r.maxY))
        p.line(to: NSPoint(x: r.minX, y: r.maxY))
        p.close()
        let base = customized ? (Theme.breakpointColor.blended(withFraction: 0.35, of: .black) ?? Theme.breakpointColor) : Theme.breakpointColor
        base.withAlphaComponent(enabled ? 1 : 0.35).setFill()
        p.fill()
    }

    private func drawFoldMark(folded: Bool, at c: NSPoint) {
        let p = NSBezierPath()
        if folded {
            p.move(to: NSPoint(x: c.x - 2.5, y: c.y - 4)); p.line(to: NSPoint(x: c.x + 3, y: c.y)); p.line(to: NSPoint(x: c.x - 2.5, y: c.y + 4))
        } else {
            p.move(to: NSPoint(x: c.x - 4, y: c.y - 2.5)); p.line(to: NSPoint(x: c.x + 4, y: c.y - 2.5)); p.line(to: NSPoint(x: c.x, y: c.y + 3))
        }
        p.close()
        (folded ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
        p.fill()
    }

    func testDiamondCenterX(numberWidth: CGFloat) -> CGFloat { lineNumberEnd - 7 }

    public var lineNumberEnd: CGFloat { authorsInset + CGFloat(EditorMetrics.lineNumberEnd) }

    public var baselineOffset: CGFloat { (Theme.lineHeight + Theme.font.descender).rounded() }

    public func isOnTestDiamond(x: CGFloat) -> Bool {
        let c = testDiamondCenterX(numberWidth: ruleThickness - Self.ribbonWidth)
        return x >= leftInset && abs(x - c) <= 12
    }

    public func numberColumnContent(line: Int) -> String {
        if let t = marks.tests[line] { return "diamond:\(t)" }
        return showsLineNumbers ? "\(line)" : ""
    }

    private func drawTestDiamond(_ t: TestStatusMark, at c: NSPoint) {
        let r: CGFloat = 4.5
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y - r))
        p.line(to: NSPoint(x: c.x + r, y: c.y))
        p.line(to: NSPoint(x: c.x, y: c.y + r))
        p.line(to: NSPoint(x: c.x - r, y: c.y))
        p.close()
        switch t {
        case .notRun:
            NSColor.secondaryLabelColor.setStroke()
            p.stroke()
        case .passed:
            NSColor.systemGreen.setFill()
            p.fill()
        case .failed:
            NSColor.systemRed.setFill()
            p.fill()
        }
    }

    func line(atGutterY y: CGFloat) -> Int? {
        let lines = visibleLines()
        if let hit = lines.first(where: { y >= $0.rect.minY && y < $0.rect.minY + max($0.rect.height, 14) }) { return hit.line }
        return nil
    }

    public override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        guard let line = line(atGutterY: start.y) else { return }
        if showsAuthors, start.x < authorsInset {
            onAuthorsClick?(line)
            return
        }
        if showsChangeColumn, start.x < leftInset {
            if changeRegion(atLine: line) != nil { onChangeClick?(line) }
            return
        }
        let x = start.x - leftInset
        if showsRibbon, x >= ruleThickness - leftInset - Self.ribbonWidth {
            onRibbonClick?(line)
            return
        }
        if marks.tests[line] != nil, isOnTestDiamond(x: start.x) {
            onRunTest?(line)
            return
        }
        let hadBreakpoint = marks.breakpoints[line] != nil
        if hadBreakpoint && (event.clickCount >= 2 || event.modifierFlags.contains(.command)) {
            onEdit?(line)
            return
        }
        var dragged = false
        var outside = false
        var target = line
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = convert(e.locationInWindow, from: nil)
            if e.type == .leftMouseUp { break }
            dragged = dragged || hypot(p.x - start.x, p.y - start.y) > 3
            outside = !bounds.insetBy(dx: -20, dy: -20).contains(p) || p.x > bounds.maxX + 10
            if let l = self.line(atGutterY: p.y) { target = l }
        }
        if hadBreakpoint && dragged && outside { onRemove?(line) }
        else if hadBreakpoint && dragged && target != line { onMove?(line, target) }
        else if !dragged { onClick?(line) }
    }
}

extension GutterView {
    public func changeRegion(atLine line: Int) -> SourceChangeRegion? {
        changeRegions.first { $0.contains(line: line) }
    }

    func changeBarRects(_ rows: [(line: Int, rect: NSRect)]) -> [(SourceChangeRegion, NSRect)] {
        var out: [(SourceChangeRegion, NSRect)] = []
        let x: CGFloat = authorsInset + 3, w: CGFloat = 5
        for region in changeRegions {
            let covered = rows.filter { region.contains(line: $0.line) }
            if region.kind == .deleted {
                if let r = rows.first(where: { $0.line == region.firstLine }) {
                    out.append((region, NSRect(x: x - 1, y: r.rect.minY - 2, width: w + 2, height: 4)))
                } else if let last = rows.last, region.firstLine == last.line + 1 {
                    out.append((region, NSRect(x: x - 1, y: last.rect.minY + max(last.rect.height, 14) - 2, width: w + 2, height: 4)))
                }
                continue
            }
            guard let top = covered.first, let bottom = covered.last else { continue }
            let maxY = bottom.rect.minY + max(bottom.rect.height, 14)
            out.append((region, NSRect(x: x, y: top.rect.minY, width: w, height: maxY - top.rect.minY)))
        }
        return out
    }

    func drawChangeBars(_ rows: [(line: Int, rect: NSRect)]) {
        for (region, rect) in changeBarRects(rows) {
            (region.staged ? NSColor.secondaryLabelColor : NSColor.controlAccentColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    public func changeToolTip(atGutterY y: CGFloat) -> String? {
        guard showsChangeColumn else { return nil }
        if let hit = changeBarRects(visibleLines()).first(where: { y >= $0.1.minY - 1 && y <= $0.1.maxY + 1 }) { return hit.0.toolTip }
        return line(atGutterY: y).flatMap(changeRegion(atLine:))?.toolTip
    }

    func updateChangeToolTips() {
        removeAllToolTips()
        if showsAuthors { addToolTip(NSRect(x: 0, y: -100_000, width: Self.authorsColumnWidth, height: 200_000), owner: self, userData: nil) }
        guard showsChangeColumn else { return }
        addToolTip(NSRect(x: authorsInset, y: -100_000, width: Self.changeColumnWidth, height: 200_000), owner: self, userData: nil)
    }

    public func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        if showsAuthors, point.x < authorsInset { return line(atGutterY: point.y).flatMap(authorsToolTip(line:)) ?? "" }
        return changeToolTip(atGutterY: point.y) ?? ""
    }

    public var changeBarDescriptions: [String] { changeRegions.map(\.accessibilityDescription) }

    public override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        guard showsChangeColumn else { return children }
        let rows = visibleLines()
        for (region, rect) in changeBarRects(rows) {
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.image)
            e.setAccessibilityLabel(region.accessibilityDescription)
            e.setAccessibilityHelp(region.toolTip)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(rect)
            children.append(e)
        }
        return children
    }
}

extension GutterView {
    public func authorBlock(atLine line: Int) -> GitBlame.Block? { authorBlockIndex(atLine: line).map { authorBlocks[$0] } }

    func authorBlockIndex(atLine line: Int) -> Int? {
        var lo = 0, hi = authorBlocks.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2, b = authorBlocks[mid]
            if line < b.firstLine { hi = mid - 1 } else if line >= b.firstLine + b.lineCount { lo = mid + 1 } else { return mid }
        }
        return nil
    }

    public func authorsText(line: Int) -> String? {
        guard showsAuthors, let b = authorBlock(atLine: line), b.firstLine == line else { return nil }
        return GitBlame.annotation(b.commit)
    }

    public func authorsToolTip(line: Int) -> String? {
        guard showsAuthors, let b = authorBlock(atLine: line) else { return nil }
        return GitBlame.details(b.commit)
    }

    func drawAuthors(_ rows: [(line: Int, rect: NSRect)]) {
        let w = Self.authorsColumnWidth
        NSColor.quaternaryLabelColor.withAlphaComponent(0.05).setFill()
        NSRect(x: 0, y: bounds.minY, width: w, height: bounds.height).fill()
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let showAvatar = GitBlameSettings.showAuthorAvatar
        var shownBlock: Int?
        for (line, r) in rows {
            guard let bi = authorBlockIndex(atLine: line) else { continue }
            let b = authorBlocks[bi]
            let row = NSRect(x: 0, y: r.minY, width: w, height: max(r.height, 14))
            if bi % 2 == 1 {
                NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
                row.fill()
            }
            guard shownBlock != b.firstLine else { continue }
            shownBlock = b.firstLine
            if line == b.firstLine {
                NSColor.separatorColor.setFill()
                NSRect(x: 0, y: row.minY, width: w, height: 0.5).fill()
            }
            let color: NSColor = b.commit.isUncommitted ? .tertiaryLabelColor : .secondaryLabelColor
            let hasAvatar = showAvatar && !b.commit.author.isEmpty
            let textX: CGFloat = hasAvatar ? 24 : 6
            if hasAvatar {
                let avatar = cachedAvatarImage(for: b.commit.author)
                avatar.draw(in: NSRect(x: 4, y: row.midY - 8, width: 16, height: 16))
            }
            let text = NSAttributedString(string: GitBlame.annotation(b.commit),
                                          attributes: [.font: Theme.gutterFont, .foregroundColor: color, .paragraphStyle: para])
            let h = text.size().height
            text.draw(with: NSRect(x: textX, y: row.minY + (row.height - h) / 2, width: w - textX - 6, height: h),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        NSColor.separatorColor.setFill()
        NSRect(x: w - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    private func cachedAvatarImage(for author: String) -> NSImage {
        if let cached = avatarImageCache[author] { return cached }
        let image = Self.avatarImage(for: author)
        avatarImageCache[author] = image
        return image
    }

    static func avatarImage(for author: String) -> NSImage {
        let initials = author.split(separator: " ").prefix(2).compactMap(\.first)
            .map { String($0).uppercased() }.joined()
        let label = initials.isEmpty ? "?" : initials
        var hash = 0
        for scalar in author.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
        let hue = CGFloat(abs(hash) % 360) / 360.0
        let fill = NSColor(calibratedHue: hue, saturation: 0.45, brightness: 0.72, alpha: 1)
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        fill.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        let textSize = text.size()
        text.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                              y: (size.height - textSize.height) / 2))
        image.unlockFocus()
        return image
    }
}
