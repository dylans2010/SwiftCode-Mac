import AppKit
import SwiftCodeIDECore

extension JumpBar {
    static let pathRaise: CGFloat = -2.75
    static let truncationFade: CGFloat = 4

    var isActivePane: Bool {
        get { paneState.active }
        set {
            guard paneState.active != newValue else { return }
            paneState.active = newValue
            setPath(lastComponents)
        }
    }

    var showsPaneCloseButton: Bool {
        get { paneState.closable }
        set {
            guard paneState.closable != newValue else { return }
            paneState.closable = newValue
            setPath(lastComponents)
        }
    }

    var pathTextColor: NSColor { isActivePane ? .labelColor : .secondaryLabelColor }

    func chevronLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "›")
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    func pathLabel(_ title: String, middle: Bool) -> NSTextField {
        let l = FadingTruncationLabel(labelWithString: title)
        l.font = .systemFont(ofSize: 11)
        l.textColor = pathTextColor
        l.lineBreakMode = .byClipping
        l.cell?.truncatesLastVisibleLine = false
        l.setContentCompressionResistancePriority(middle ? .defaultLow - 1 : .defaultHigh, for: .horizontal)
        return l
    }

    func pathIconTint(symbol: String, title: String) -> NSColor? {
        guard isActivePane else { return .secondaryLabelColor }
        return OutlineItem.color(Self.iconTint(symbol: symbol, title: title)) ?? .controlAccentColor
    }

    static func iconTint(symbol: String, title: String) -> WorkspaceChrome.IconTint {
        switch symbol {
        case "folder.badge.gearshape", "shippingbox", "square.stack.3d.up": .blue
        case "folder.fill", "folder": .lightBlue
        case WorkspaceChrome.fileSymbol("a.swift"): .orange
        case WorkspaceChrome.fileSymbol("a.png"), WorkspaceChrome.fileSymbol("a.xcassets"): .blue
        default: .accent
        }
    }

    func addPaneCloseButton() {
        let b = iconButton("xmark", "Close this Editor Pane")
        b.target = self
        b.action = #selector(closeClicked)
        b.contentTintColor = .secondaryLabelColor
        b.widthAnchor.constraint(equalToConstant: 20).isActive = true
        paneState.closeButton = b
        stack.addArrangedSubview(b)
        stack.setCustomSpacing(10, after: b)
    }

    func addPaneDivider() {
        let d = NSBox()
        d.boxType = .separator
        d.translatesAutoresizingMaskIntoConstraints = false
        d.widthAnchor.constraint(equalToConstant: 1).isActive = true
        d.heightAnchor.constraint(equalToConstant: 14).isActive = true
        if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(8, after: last) }
        stack.addArrangedSubview(d)
        stack.setCustomSpacing(10, after: d)
    }

    var paneCloseButton: NSButton? { showsPaneCloseButton ? paneState.closeButton : nil }
}

final class JumpBarPaneState {
    var active = true
    var closable = false
    weak var closeButton: NSButton?
}

final class FadingTruncationLabel: NSTextField {
    var isTruncated: Bool { intrinsicContentSize.width > bounds.width + 0.5 }

    override func layout() {
        super.layout()
        updateFade()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateFade()
    }

    private func updateFade() {
        wantsLayer = true
        guard isTruncated, bounds.width > JumpBar.truncationFade else { layer?.mask = nil; return }
        let mask = (layer?.mask as? CAGradientLayer) ?? CAGradientLayer()
        mask.frame = bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double((bounds.width - JumpBar.truncationFade) / bounds.width)), 1]
        layer?.mask = mask
    }
}
