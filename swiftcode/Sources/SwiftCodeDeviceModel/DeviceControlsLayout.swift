import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DeviceControlsLayout {
    public static let height: Double = 36.5
    public static let pitch: Double = 34
    public static let edge: Double = 20
    public static let gap: Double = 7.5
    public static let bottomMargin: Double = 8
    public static let dividerExtra: Double = 3.5
    public static let buttonWidth: Double = 34

    public struct Device: Equatable, Sendable {
        public var showsHome: Bool
        public var rotates: Bool
        public var foldable: Bool
        public var spatial: Bool
        public init(showsHome: Bool = true, rotates: Bool = true, foldable: Bool = false, spatial: Bool = false) {
            self.showsHome = showsHome
            self.rotates = rotates
            self.foldable = foldable
            self.spatial = spatial
        }

        public init(spec: DeviceFrameSpec, foldable: Bool? = nil, spatial: Bool? = nil) {
            let vision = spatial ?? (spec.family == .vision)
            self.init(showsHome: spec.family != .watch, rotates: spec.rotates && !vision,
                      foldable: foldable ?? spec.isFoldable, spatial: vision)
        }
    }

    public static func groups(_ d: Device) -> [[DeviceCommand]] {
        var out: [[DeviceCommand]] = [(d.showsHome ? [.home] : []) + [.screenshot, .recordScreen]]
        var second: [DeviceCommand] = []
        if d.spatial { second = [.resetCamera] } else if d.rotates { second = [.rotateLeft] }
        if d.foldable { second += [.poseClosed, .posePartiallyOpen, .poseOpen] }
        if !second.isEmpty { out.append(second) }
        return out
    }

    public static func hasDivider(after c: DeviceCommand, in group: [DeviceCommand]) -> Bool {
        (c == .rotateLeft || c == .resetCamera) && group.contains(.poseClosed)
    }

    public static func width(of group: [DeviceCommand]) -> Double {
        guard !group.isEmpty else { return 0 }
        let dividers = group.filter { hasDivider(after: $0, in: group) }.count
        return 2 * edge + pitch * Double(group.count - 1) + dividerExtra * Double(dividers)
    }

    public static func glyphCentres(of group: [DeviceCommand]) -> [Double] {
        var x = edge
        var out: [Double] = []
        for c in group {
            out.append(x)
            x += pitch + (hasDivider(after: c, in: group) ? dividerExtra : 0)
        }
        return out
    }

    public static func dividerCentre(of group: [DeviceCommand]) -> Double? {
        guard let i = group.firstIndex(where: { hasDivider(after: $0, in: group) }) else { return nil }
        let c = glyphCentres(of: group)
        return (c[i] + c[i + 1]) / 2
    }

    public static func totalWidth(_ groups: [[DeviceCommand]]) -> Double {
        groups.map(width(of:)).reduce(0, +) + gap * Double(max(0, groups.count - 1))
    }

    public static func capsuleRects(_ groups: [[DeviceCommand]], canvasWidth width: Double, canvasHeight height: Double) -> [CGRect] {
        var x = (width - totalWidth(groups)) / 2
        let y = height - bottomMargin - self.height
        return groups.map { g in
            defer { x += self.width(of: g) + gap }
            return CGRect(x: x, y: y, width: self.width(of: g), height: self.height)
        }
    }

    public static func controlRects(_ groups: [[DeviceCommand]], canvasWidth width: Double, canvasHeight height: Double) -> [(DeviceCommand, CGRect)] {
        var out: [(DeviceCommand, CGRect)] = []
        for (g, r) in zip(groups, capsuleRects(groups, canvasWidth: width, canvasHeight: height)) {
            for (c, cx) in zip(g, glyphCentres(of: g)) {
                out.append((c, CGRect(x: Double(r.minX) + cx - buttonWidth / 2, y: Double(r.minY), width: buttonWidth, height: self.height)))
            }
        }
        return out
    }

    public static func deviceArea(canvasWidth width: Double, canvasHeight height: Double, top: Double) -> CGRect {
        let bottom = height - bottomMargin - self.height
        return CGRect(x: 0, y: top, width: width, height: max(1, bottom - top))
    }

    public static func deviceRect(device: CGSize, scale: Double, in area: CGRect) -> CGRect {
        let w = Double(device.width) * scale, h = Double(device.height) * scale
        return CGRect(x: Double(area.midX) - w / 2, y: Double(area.midY) - h / 2, width: w, height: h)
    }
}
