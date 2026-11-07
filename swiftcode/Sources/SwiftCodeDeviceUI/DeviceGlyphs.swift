#if os(macOS)
import AppKit
import SwiftCodeDeviceModel

public enum DeviceGlyph: String, Sendable, CaseIterable {
    case phone
    case tablet
    case headset
    case openFlat
    case watch

    public static func of(_ family: DeviceFamily) -> DeviceGlyph {
        switch family {
        case .phone: .phone
        case .pad: .tablet
        case .vision: .headset
        case .watch: .watch
        }
    }

    @MainActor
    public func image(height: CGFloat = 16, lit: Bool = false) -> NSImage {
        let (aspect, radius): (CGFloat, CGFloat) = switch self {
        case .phone: (0.52, 0.16)
        case .tablet: (0.74, 0.10)
        case .headset: (1.7, 0.42)
        case .openFlat: (1.42, 0.10)
        case .watch: (0.72, 0.30)
        }
        let w = (height * aspect).rounded(), h = height
        let img = NSImage(size: NSSize(width: w, height: h), flipped: true) { rect in
            let line: CGFloat = 1.3
            if self == .watch { Self.drawWatch(in: rect, line: line, lit: lit); return true }
            let body = rect.insetBy(dx: line / 2, dy: line / 2)
            let r = min(body.width, body.height) * radius
            let outline = NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
            outline.lineWidth = line
            NSColor.black.setStroke()
            outline.stroke()
            let inset: CGFloat = self == .headset ? 2.6 : 2.4
            let screen = body.insetBy(dx: inset, dy: inset)
            if lit, screen.width > 0, screen.height > 0 {
                NSColor.black.withAlphaComponent(0.55).setFill()
                NSBezierPath(roundedRect: screen, xRadius: max(0, r - inset / 2), yRadius: max(0, r - inset / 2)).fill()
            }
            if self == .openFlat {
                let hinge = NSBezierPath()
                hinge.move(to: NSPoint(x: body.midX, y: body.minY + 1))
                hinge.line(to: NSPoint(x: body.midX, y: body.maxY - 1))
                hinge.lineWidth = 0.9
                hinge.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = rawValue
        return img
    }

    private static func drawWatch(in rect: NSRect, line: CGFloat, lit: Bool) {
        NSColor.black.setStroke()
        let knob: CGFloat = max(1.5, rect.width * 0.12)
        let faceW = rect.width - knob - line, faceH = rect.height * 0.58
        let face = NSRect(x: rect.minX + line / 2, y: rect.midY - faceH / 2, width: faceW, height: faceH)
        let r = faceW * 0.30
        let strapW = faceW * 0.62
        let left = face.midX - strapW / 2, right = face.midX + strapW / 2
        for (from, edge) in [(face.minY, rect.minY + line / 2), (face.maxY, rect.maxY - line / 2)] {
            let strap = NSBezierPath()
            strap.move(to: NSPoint(x: left, y: from))
            strap.line(to: NSPoint(x: left, y: edge))
            strap.line(to: NSPoint(x: right, y: edge))
            strap.line(to: NSPoint(x: right, y: from))
            strap.lineWidth = line
            strap.stroke()
        }
        let outline = NSBezierPath(roundedRect: face, xRadius: r, yRadius: r)
        outline.lineWidth = line
        outline.stroke()
        let k = NSBezierPath(roundedRect: NSRect(x: face.maxX - 0.2, y: face.minY + faceH * 0.28, width: knob, height: faceH * 0.22),
                             xRadius: 0.6, yRadius: 0.6)
        NSColor.black.setFill()
        k.fill()
        let screen = face.insetBy(dx: 2.2, dy: 2.2)
        if lit, screen.width > 0, screen.height > 0 {
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: screen, xRadius: max(0, r - 1.1), yRadius: max(0, r - 1.1)).fill()
        }
    }
}
#endif
