import AppKit
import YcodeIDECore

extension NavigatorAreaController {
    func configureTestHeader() {
        testPlanPopUp.controlSize = .small
        testPlanPopUp.font = .systemFont(ofSize: 11)
        testPlanPopUp.isBordered = true
        let width = testPlanPopUp.widthAnchor.constraint(equalToConstant: NavigatorBars.testPlanPopUpWidth)
        width.priority = .defaultHigh
        width.isActive = true
        testPlanPopUp.addItem(withTitle: testPlanName)
        testPlanPopUp.setAccessibilityLabel("Test Plan")
        testModeControl.controlSize = .small
        testModeControl.selectedSegment = 0
        testModeControl.setAccessibilityLabel("Mode")
        for (i, t) in NavigatorBars.testModes.enumerated() {
            testModeControl.setToolTip(t, forSegment: i)
            testModeControl.setLabel("", forSegment: i)
        }
        testModeControl.target = self
        testModeControl.action = #selector(testModeChosen)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        testPlanPopUp.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        for v in [testPlanPopUp, spacer, testModeControl] as [NSView] { testHeader.addArrangedSubview(v) }
        testHeader.orientation = .horizontal
        testHeader.spacing = 4
        testHeader.isHidden = true
    }

    @objc func testModeChosen() { groupTestsByTags = testModeControl.selectedSegment == 1 }

    func addTrailingGlyph(_ symbol: String, tint: NSColor?, to cell: NSView, label: NSView) {
        let v = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        v.contentTintColor = tint ?? .secondaryLabelColor
        v.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(v)
        NSLayoutConstraint.activate([
            v.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            v.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: v.leadingAnchor, constant: -4),
        ])
    }

    public func bookmarkMenuItems(_ b: Bookmark) -> [NSMenuItem] {
        let done = b.done == true
        let item = NSMenuItem(title: done ? "Mark as Not Done" : "Mark as Done", action: #selector(bookmarkDoneChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = BookmarkBox(b)
        return [item]
    }

    @objc func bookmarkDoneChosen(_ item: NSMenuItem) {
        guard let b = (item.representedObject as? BookmarkBox)?.bookmark else { return }
        onSetBookmarkDone?(b, b.done != true)
    }
}

final class NavigatorFilterField: NSSearchField {
    static let optionsWidth: CGFloat = 23.5
    static let optionsLeading: CGFloat = 2.3
    static let toggleWidth: CGFloat = 18
    static let toggleHeight: CGFloat = 16
    var leadingInset: CGFloat = 30 { didSet { needsLayout = true; needsDisplay = true } }
    var trailingInset: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }

    override class var cellClass: AnyClass? {
        get { NavigatorFilterFieldCell.self }
        set {}
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    static let cancelWidth: CGFloat = 16

    func textRect(_ bounds: NSRect) -> NSRect {
        var r = bounds
        r.origin.x += leadingInset
        r.size.width = max(0, bounds.width - leadingInset - trailingInset - Self.cancelWidth - 2)
        return r
    }

    func cancelRect(_ bounds: NSRect) -> NSRect {
        NSRect(x: bounds.maxX - trailingInset - Self.cancelWidth - 2, y: bounds.midY - Self.cancelWidth / 2,
               width: Self.cancelWidth, height: Self.cancelWidth)
    }

    override func rectForSearchText(whenCentered isCentered: Bool) -> NSRect {
        let r = super.rectForSearchText(whenCentered: isCentered)
        let t = textRect(bounds)
        return NSRect(x: t.minX, y: r.minY, width: t.width, height: r.height)
    }
    override func rectForSearchButton(whenCentered isCentered: Bool) -> NSRect { .zero }
    override func rectForCancelButton(whenCentered isCentered: Bool) -> NSRect {
        let r = super.rectForCancelButton(whenCentered: isCentered)
        let c = cancelRect(bounds)
        return NSRect(x: c.minX, y: r.minY, width: r.width, height: r.height)
    }

    static let optionsGlyph: NSImage = {
        let funnel = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 6.5, weight: .semibold))
        let circle: CGFloat = 15.5, chevronX: CGFloat = 15.1, chevronSize = NSSize(width: 8, height: 5)
        let size = NSSize(width: optionsWidth, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            if let f = funnel {
                f.draw(in: NSRect(x: 0, y: (size.height - circle) / 2, width: circle, height: circle))
            }
            if let c = chevron {
                c.draw(in: NSRect(x: chevronX, y: (size.height - chevronSize.height) / 2, width: chevronSize.width, height: chevronSize.height))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Filter options"
        return image
    }()
}

final class NavigatorOptionsButton: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func draw(_ dirtyRect: NSRect) {
        let glyph = NavigatorFilterField.optionsGlyph
        let tint = isEnabled ? (contentTintColor ?? .secondaryLabelColor) : .tertiaryLabelColor
        let tinted = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: 0, y: (bounds.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
    }
}

final class NavigatorFilterToggle: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

final class NavigatorFilterFieldCell: NSSearchFieldCell {
    private var field: NavigatorFilterField? { controlView as? NavigatorFilterField }
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let r = super.searchTextRect(forBounds: rect)
        guard let f = field else { return r }
        let t = f.textRect(rect)
        return NSRect(x: t.minX, y: r.minY, width: t.width, height: r.height)
    }
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { .zero }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        let r = super.cancelButtonRect(forBounds: rect)
        guard let f = field else { return r }
        return NSRect(x: f.cancelRect(rect).minX, y: r.minY, width: r.width, height: r.height)
    }
}

final class BookmarkBox: NSObject {
    let bookmark: Bookmark
    init(_ b: Bookmark) { bookmark = b }
}
