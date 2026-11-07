import AppKit
import SwiftCodeIDECore

final class NavigatorRowView: NSTableRowView {
    static let bandHeight: CGFloat = 22
    static let bandInset: CGFloat = 10
    static let bandRadius: CGFloat = 8

    static var unfocusedBand: NSColor {
        NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.045)
        }
    }

    static func bandRect(in bounds: NSRect) -> NSRect {
        let h = min(bandHeight, bounds.height)
        return NSRect(x: bounds.minX + bandInset, y: bounds.midY - h / 2, width: max(0, bounds.width - 2 * bandInset), height: h)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        (isEmphasized ? NSColor.controlAccentColor : Self.unfocusedBand).setFill()
        NSBezierPath(roundedRect: Self.bandRect(in: bounds), xRadius: Self.bandRadius, yRadius: Self.bandRadius).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && isEmphasized ? .emphasized : .normal
    }
}

final class NavigatorCellView: NSTableCellView {
    var labelColor: NSColor = NavigatorCellView.rowLabelColor
    var iconTint: NSColor?
    var recolorsLabel = true
    static var rowLabelColor: NSColor {
        NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .labelColor
                : NSColor(srgbRed: 0x3B / 255.0, green: 0x3B / 255.0, blue: 0x3C / 255.0, alpha: 1)
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyStyle() }
    }

    func applyStyle() {
        let on = backgroundStyle == .emphasized
        if recolorsLabel, let label = textField {
            let color = on ? NSColor.alternateSelectedControlTextColor : labelColor
            if label.textColor != color { label.textColor = color }
        }
        imageView?.contentTintColor = on ? .alternateSelectedControlTextColor : iconTint
    }
}

final class NavigatorRowLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { StyledTitleCell.self }
        set {}
    }

    var styledTitle: NSAttributedString? {
        get { (cell as? StyledTitleCell)?.styledTitle }
        set { (cell as? StyledTitleCell)?.styledTitle = newValue }
    }

    final class StyledTitleCell: NSTextFieldCell {
        var styledTitle: NSAttributedString?
        override var objectValue: Any? {
            get { super.objectValue }
            set { super.objectValue = styledTitle ?? newValue }
        }
    }
}
