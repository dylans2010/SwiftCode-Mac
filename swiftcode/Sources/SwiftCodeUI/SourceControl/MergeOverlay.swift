import AppKit
import SwiftCodeIDECore

@MainActor
public final class MergeOverlayView: NSView {
    public let veil = CALayer()
    public private(set) var alert: MergeAlertView?
    public private(set) var sheet: MergeSheetController?
    public var toolbarBottom: CGFloat = 52
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var onClose: (() -> Void)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        veil.backgroundColor = NSColor.black.cgColor
        veil.opacity = 0
        layer?.addSublayer(veil)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    var palette: MergeSheetPalette { MergeSheetPalette.forDark(effectiveAppearance.isDarkMerge) }

    public var veilOpacity: Float { Float(palette.veilOpacity) }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        veil.frame = bounds
        CATransaction.commit()
        if let a = alert {
            let f = MergeSheetMetrics.alertFrame(window: (bounds.width, bounds.height), chooser: a.chooser != nil)
            a.frame = NSRect(x: f.x, y: f.y, width: f.width, height: f.height)
        }
        if let s = sheet {
            let f = MergeSheetMetrics.sheetFrame(window: (bounds.width, bounds.height), toolbarBottom: toolbarBottom)
            s.view.frame = NSRect(x: f.x, y: f.y, width: f.width, height: f.height)
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        return super.hitTest(point) ?? (frame.contains(point) ? self : nil)
    }

    public override func mouseDown(with event: NSEvent) {}

    static func install(in window: NSWindow) -> MergeOverlayView? {
        guard let frameView = window.contentView?.superview else { return nil }
        if let existing = frameView.subviews.compactMap({ $0 as? MergeOverlayView }).first { return existing }
        let o = MergeOverlayView(frame: frameView.bounds)
        frameView.addSubview(o, positioned: .above, relativeTo: nil)
        o.toolbarBottom = max(0, window.frame.height - window.contentLayoutRect.maxY)
        return o
    }

    func setVeil(on: Bool, duration: Double) {
        let to: Float = on ? veilOpacity : 0
        let from = veil.presentation()?.opacity ?? veil.opacity
        veil.opacity = to
        guard duration > 0 else { veil.removeAnimation(forKey: "veil"); return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        veil.add(a, forKey: "veil")
    }

    @discardableResult
    func showAlert(_ alert: MergeAlertView) -> MergeAlertView {
        self.alert?.removeFromSuperview()
        self.alert = alert
        addSubview(alert)
        needsLayout = true
        layoutSubtreeIfNeeded()
        setVeil(on: true, duration: MergeSheetMotion.veilIn)
        alert.mergeButton.isDefaultLook = false
        DispatchQueue.main.asyncAfter(deadline: .now() + MergeSheetMotion.veilIn) { [weak alert] in alert?.mergeButton.isDefaultLook = true }
        window?.makeFirstResponder(alert)
        return alert
    }

    func dismissAlert() {
        guard let a = alert else { return }
        alert = nil
        a.wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = MergeSheetMotion.alertOut
        a.layer?.opacity = 0
        a.layer?.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + MergeSheetMotion.alertOut) { a.removeFromSuperview() }
    }

    func showSheet(_ sheet: MergeSheetController) {
        self.sheet = sheet
        let v = sheet.view
        v.wantsLayer = true
        addSubview(v)
        needsLayout = true
        layoutSubtreeIfNeeded()
        if veil.opacity == 0 { setVeil(on: true, duration: MergeSheetMotion.veilIn) }
        animateSheet(in: true)
        window?.makeFirstResponder(sheet.canvas)
    }

    func animateSheet(in appearing: Bool) {
        guard let layer = sheet?.view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = appearing ? 0 : 1
        fade.toValue = appearing ? 1 : 0
        fade.duration = appearing ? MergeSheetMotion.sheetFade : MergeSheetMotion.sheetOutFade
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        fade.fillMode = .both
        layer.opacity = appearing ? 1 : 0
        layer.add(fade, forKey: "sheetFade")
        guard !reduceMotion else { layer.removeAnimation(forKey: "sheetSlide"); return }
        let c = MergeSheetMotion.slideCurve
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        let up = (layer.superlayer?.isGeometryFlipped ?? false) || isFlipped ? -MergeSheetMotion.slideDistance : MergeSheetMotion.slideDistance
        slide.fromValue = appearing ? up : 0
        slide.toValue = appearing ? 0 : up
        slide.duration = appearing ? MergeSheetMotion.sheetSlide : MergeSheetMotion.sheetOutSlide
        slide.timingFunction = CAMediaTimingFunction(controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2))
        slide.fillMode = .both
        layer.add(slide, forKey: "sheetSlide")
    }

    func close(animated: Bool = true) {
        let duration = animated ? max(MergeSheetMotion.sheetOutSlide, MergeSheetMotion.veilIn) : 0
        if animated, sheet != nil { animateSheet(in: false) }
        if let a = alert { a.removeFromSuperview(); alert = nil }
        setVeil(on: false, duration: animated ? MergeSheetMotion.veilIn : 0)
        let s = sheet
        sheet = nil
        let finish = { [weak self] in
            s?.view.removeFromSuperview()
            s?.removeFromParent()
            self?.removeFromSuperview()
            self?.onClose?()
        }
        if duration > 0 && window?.isVisible == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { finish() }
        } else {
            finish()
        }
    }
}

extension NSAppearance {
    var isDarkMerge: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    convenience init(mergeHex hex: UInt32, alpha: CGFloat = 1) {
        let c = MergeSheetPalette.components(hex)
        self.init(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha)
    }
}

@MainActor
public final class MergeButton: NSControl {
    public var title: String { didSet { needsDisplay = true } }
    public var isDefaultLook = false { didSet { needsDisplay = true } }
    public var keyEquivalent = ""
    var fontSize: CGFloat = 13

    public init(title: String) {
        self.title = title
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public override var isEnabled: Bool { didSet { needsDisplay = true } }

    var palette: MergeSheetPalette { MergeSheetPalette.forDark(effectiveAppearance.isDarkMerge) }

    public var colors: (fill: NSColor, label: NSColor) {
        let p = palette
        if !isEnabled { return (NSColor(mergeHex: p.disabledButton), NSColor(mergeHex: p.disabledButtonLabel)) }
        if isDefaultLook { return (NSColor(mergeHex: p.accent), .white) }
        return (NSColor(mergeHex: p.button), NSColor(mergeHex: p.buttonLabel))
    }

    public override func draw(_ dirtyRect: NSRect) {
        let c = colors
        c.fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: isDefaultLook ? .medium : .regular),
                                                    .foregroundColor: c.label]
        let s = NSAttributedString(string: title, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()))
    }

    func fittingWidth(minimum: CGFloat) -> CGFloat {
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)]).width
        return max(minimum, (w + 28).rounded())
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        performClick(nil)
    }

    public override func performClick(_ sender: Any?) {
        guard isEnabled, let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }
}
