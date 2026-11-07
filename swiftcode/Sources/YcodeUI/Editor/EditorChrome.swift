import AppKit
import YcodeIDECore
import YcodeSyntax

@MainActor
enum EditorVeil {
    static var fill: NSColor { Theme.backgroundColor.withAlphaComponent(1 - CGFloat(EditorMetrics.barVeil)) }
    static var separator: NSColor { NSColor.separatorColor }

    static func drawSeparator(_ r: NSRect) {
        Theme.backgroundColor.setFill()
        r.fill(using: .copy)
        separator.setFill()
        r.fill(using: .sourceOver)
    }
}

@MainActor
enum EditorBlurVeil {
    static var applies: Bool { EditorTheme.color(Theme.current.background) == nil }
}

public class EditorBlurBackdrop: NSView {
    var sources: () -> [NSView] = { [] }
    var regions: () -> [(rect: NSRect, share: CGFloat)] = { [] }
    public var showsStructure: Bool { EditorBlurVeil.applies }
    public override var isFlipped: Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public func themeChanged() {
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard EditorBlurVeil.applies else {
            EditorVeil.fill.setFill()
            dirtyRect.intersection(bounds).fill(using: .copy)
            return
        }
        Theme.backgroundColor.setFill()
        dirtyRect.intersection(bounds).fill(using: .copy)
        let views = sources()
        for (rect, share) in regions() where share > 0 && rect.intersects(dirtyRect) {
            guard let image = StructureBlur.image(of: rect, in: self, sources: views, background: Theme.backgroundColor) else { continue }
            StructureBlur.draw(image, for: rect, in: self, share: share)
        }
    }
}

public final class EditorBottomBarBackdrop: EditorBlurBackdrop {
    public static var separatorColor: NSColor {
        NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .separatorColor
                : NSColor.black.withAlphaComponent(CGFloat(EditorMetrics.bottomBarSeparatorInk))
        }
    }
    private let line = SeparatorLine()

    override init(frame: NSRect) {
        super.init(frame: frame)
        line.autoresizingMask = [.width, .maxYMargin]
        line.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        addSubview(line)
        regions = { [weak self] in
            guard let self else { return [] }
            return [(NSRect(x: 0, y: 1, width: self.bounds.width, height: max(0, self.bounds.height - 1)), CGFloat(BarBlur.bottomBarShare))]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func themeChanged() {
        super.themeChanged()
        line.needsDisplay = true
    }

    final class SeparatorLine: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            Theme.backgroundColor.setFill()
            bounds.fill(using: .copy)
            EditorBottomBarBackdrop.separatorColor.setFill()
            bounds.fill(using: .sourceOver)
        }
    }
}

final class EditorBandBackdrop: EditorBlurBackdrop {
    var jumpBarTop: CGFloat = 0 { didSet { if oldValue != jumpBarTop { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        regions = { [weak self] in
            guard let self else { return [] }
            let top = min(self.jumpBarTop, self.bounds.height), sep = CGFloat(EditorMetrics.jumpBarSeparator)
            return [(NSRect(x: 0, y: 0, width: self.bounds.width, height: top), CGFloat(BarBlur.toolbarBandShare)),
                    (NSRect(x: 0, y: top, width: self.bounds.width, height: max(0, self.bounds.height - top - sep)), CGFloat(BarBlur.jumpBarShare))]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

final class ScopeHeaderView: NSView {
    weak var scrollTarget: NSScrollView?
    override func scrollWheel(with event: NSEvent) {
        if let t = scrollTarget { t.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
    struct Row {
        var line: Int
        var text: NSAttributedString
    }
    private(set) var rows: [Row] = []
    var lineHeight: CGFloat = 18
    var codeColumn = CGFloat(EditorMetrics.codeColumn)
    var numberEnd = CGFloat(EditorMetrics.lineNumberEnd)
    var showsLineNumbers = true
    var baseline: CGFloat = 14

    override var isFlipped: Bool { true }

    func show(_ rows: [Row]) {
        self.rows = rows
        isHidden = rows.isEmpty
        needsDisplay = true
    }

    var bandHeight: CGFloat { CGFloat(EditorMetrics.stickyHeaderHeight(rows: rows.count, lineHeight: Double(lineHeight))) }
    var totalHeight: CGFloat { rows.isEmpty ? 0 : bandHeight + CGFloat(EditorMetrics.stickyHeaderSeparator) }

    override func draw(_ dirtyRect: NSRect) {
        EditorVeil.fill.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bandHeight).fill(using: .copy)
        EditorVeil.drawSeparator(NSRect(x: 0, y: bandHeight, width: bounds.width, height: CGFloat(EditorMetrics.stickyHeaderSeparator)))
        let numberAttrs: [NSAttributedString.Key: Any] = [.font: Theme.gutterFont, .foregroundColor: Theme.lineNumberColor]
        for (i, r) in rows.enumerated() {
            let top = CGFloat(EditorMetrics.stickyHeaderTopPad) + CGFloat(i) * lineHeight
            let base = top + baseline
            if showsLineNumbers {
                let n = NSAttributedString(string: "\(r.line)", attributes: numberAttrs)
                n.draw(at: NSPoint(x: numberEnd - n.size().width, y: base - Theme.gutterFont.ascender))
            }
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: codeColumn, y: top, width: max(0, bounds.width - codeColumn), height: lineHeight).clip()
            r.text.draw(at: NSPoint(x: codeColumn, y: base - Theme.font.ascender))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

@MainActor
final class MinimapView: NSView {
    weak var scrollTarget: NSScrollView?
    override func scrollWheel(with event: NSEvent) {
        if let t = scrollTarget { t.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
    struct Run: Equatable {
        var column: Int
        var length: Int
        var color: NSColor
    }
    var rows: [[Run]] = [] { didSet { cache = nil; needsDisplay = true } }
    var contentTop: CGFloat = 0 { didSet { if oldValue != contentTop { needsDisplay = true } } }
    var visibleTop: CGFloat = 0 { didSet { if oldValue != visibleTop { needsDisplay = true } } }
    var visibleHeight: CGFloat = 0 { didSet { if oldValue != visibleHeight { needsDisplay = true } } }
    var scrollFraction: CGFloat = 0 { didSet { if oldValue != scrollFraction { needsDisplay = true } } }
    var advance: CGFloat = 8
    var textTopInset = CGFloat(EditorMetrics.firstLineInset)
    var onScrollTo: ((CGFloat) -> Void)?
    private var cache: NSImage?

    override var isFlipped: Bool { true }

    static func width(forEditorWidth w: CGFloat) -> CGFloat {
        CGFloat(EditorMetrics.minimapWidth(editorWidth: Double(w)) + EditorMetrics.minimapSeparator)
    }

    var pitch: CGFloat { CGFloat(EditorMetrics.minimapLinePitch) }
    var scale: CGFloat { CGFloat(EditorMetrics.minimapScale) }
    var contentHeight: CGFloat { CGFloat(rows.count) * pitch + textTopInset * scale }
    var offset: CGFloat {
        CGFloat(EditorMetrics.minimapOffset(contentHeight: Double(contentHeight), viewHeight: Double(max(0, bounds.height - contentTop)),
                                            fraction: Double(scrollFraction)))
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize.width != frame.width { cache = nil }
        super.setFrameSize(newSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.backgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        let sep = CGFloat(EditorMetrics.minimapSeparator)
        let top = contentTop - offset
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSRect(x: sep, y: top + visibleTop * scale, width: bounds.width - sep, height: visibleHeight * scale).fill()
        if let image = renderedRows() {
            image.draw(in: NSRect(x: 0, y: top + textTopInset * scale, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: sep, height: bounds.height).fill()
    }

    private func renderedRows() -> NSImage? {
        if let cache { return cache }
        guard !rows.isEmpty, bounds.width > 0 else { return nil }
        let inset = CGFloat(EditorMetrics.minimapSeparator + EditorMetrics.minimapTextInset)
        let charWidth = advance * scale
        let height = min(CGFloat(rows.count) * pitch, 16_000)
        let width = bounds.width
        let image = NSImage(size: NSSize(width: width, height: max(1, height)), flipped: true) { [rows, pitch] _ in
            let bar = CGFloat(EditorMetrics.minimapBarHeight)
            let ink = CGFloat(EditorMetrics.minimapInk)
            for (i, runs) in rows.enumerated() {
                let y = CGFloat(i) * pitch
                if y > height { break }
                for r in runs {
                    let x = inset + CGFloat(r.column) * charWidth
                    guard x < width else { continue }
                    r.color.withAlphaComponent(r.color.alphaComponent * ink).setFill()
                    NSRect(x: x, y: y, width: min(CGFloat(r.length) * charWidth, width - x), height: bar).fill()
                }
            }
            return true
        }
        cache = image
        return image
    }

    override func mouseDown(with event: NSEvent) { scrollTo(event) }
    override func mouseDragged(with event: NSEvent) { scrollTo(event) }

    private func scrollTo(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let docY = (p.y - contentTop + offset) / scale - textTopInset
        onScrollTo?(max(0, docY))
    }
}

extension MinimapView {
    static func rows(of storage: NSAttributedString, columns: Int, tabWidth: Int, wraps: Bool, tokens: IndexSet = IndexSet()) -> [[Run]] {
        let ns = storage.string as NSString
        var out: [[Run]] = []
        var lineStart = 0
        let length = ns.length
        let cols = max(8, columns)
        while lineStart <= length {
            var end = lineStart
            while end < length, ns.character(at: end) != 10 { end += 1 }
            let line = ns.substring(with: NSRange(location: lineStart, length: end - lineStart))
            let indent = EditorMetrics.wrappedIndent(of: Substring(line), tabWidth: tabWidth)
            var row: [Run] = []
            var col = 0
            var i = lineStart
            var leading = true
            func flush() { out.append(row); row = [] }
            while i < end {
                var range = NSRange()
                let color = (storage.attribute(.foregroundColor, at: i, effectiveRange: &range) as? NSColor) ?? Theme.textColor
                let runEnd = min(end, NSMaxRange(range))
                var open = false
                var runCol = 0
                var inkEnd = 0
                func closeRun() {
                    if open, inkEnd > runCol { row.append(Run(column: runCol, length: inkEnd - runCol, color: color)) }
                    open = false
                }
                while i < runEnd {
                    let c = ns.character(at: i)
                    if wraps, col >= cols {
                        closeRun()
                        flush()
                        col = min(indent, cols / 2)
                    }
                    if c == 32 || c == 9 {
                        if leading || !tokens.contains(i) { closeRun() }
                        col += c == 9 ? tabWidth - col % max(1, tabWidth) : 1
                    } else {
                        leading = false
                        if !open { open = true; runCol = col }
                        col += 1
                        inkEnd = col
                    }
                    i += 1
                }
                closeRun()
            }
            flush()
            lineStart = end + 1
        }
        return out
    }

    static func tokenInteriors(_ tokens: [SyntaxToken]) -> IndexSet {
        var set = IndexSet()
        for t in tokens where t.length > 1 && t.kind != .identifier { set.insert(integersIn: t.location..<t.end) }
        return set
    }
}
