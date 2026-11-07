import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DeviceZoomMode: Equatable, Sendable {
    case fit
    case actual
    case scale(Double)

    public var storedValue: String {
        switch self {
        case .fit: "fit"
        case .actual: "actual"
        case .scale(let s): String(s)
        }
    }

    public init?(storedValue v: String) {
        switch v {
        case "fit": self = .fit
        case "actual": self = .actual
        default:
            guard let s = Double(v), s > 0 else { return nil }
            self = .scale(s)
        }
    }
}

public enum DeviceZoom {
    public static let steps: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1, 1.25, 1.5, 2, 3, 4]
    public static let fitMargin: Double = 24

    public static func fit(_ content: CGSize, in area: CGSize, margin: Double = fitMargin) -> Double {
        guard content.width > 0, content.height > 0 else { return 1 }
        let w = max(1, Double(area.width) - 2 * margin), h = max(1, Double(area.height) - 2 * margin)
        return min(4, max(0.05, min(w / Double(content.width), h / Double(content.height))))
    }

    public static func zoomIn(from s: Double) -> Double { steps.first { $0 > s * 1.001 } ?? steps.last! }
    public static func zoomOut(from s: Double) -> Double { steps.last { $0 < s * 0.999 } ?? steps.first! }

    public static func physical(panel: DevicePanelSpec, displayPointsPerInch: Double) -> Double {
        guard panel.pixelsPerInch > 0, displayPointsPerInch > 0 else { return 1 }
        return panel.scale / panel.pixelsPerInch * displayPointsPerInch
    }

    public static func displayPointsPerInch(pointWidth: Double, millimetresWide: Double) -> Double? {
        guard pointWidth > 0, millimetresWide > 1 else { return nil }
        return pointWidth / (millimetresWide / 25.4)
    }
}

public enum CompactWindowLayout {
    public static let toolbarHeight: Double = 52
    public static let topGap: Double = 4
    public static let sideMargin: Double = 17
    public static let controlsHeight: Double = DeviceControlsLayout.height
    public static let controlsGap: Double = 10
    public static let bottomMargin: Double = 8
    public static let minimumWidth: Double = 340

    public static func chromeHeight(toolbar: Double = toolbarHeight) -> Double { toolbar + topGap + controlsGap + controlsHeight + bottomMargin }

    public static func scale(device: CGSize, windowWidth width: Double) -> Double {
        guard device.width > 0 else { return 1 }
        return max(0.05, (width - 2 * sideMargin) / Double(device.width))
    }

    public static func contentSize(device: CGSize, scale: Double, toolbar: Double = toolbarHeight) -> CGSize {
        CGSize(width: (Double(device.width) * scale + 2 * sideMargin).rounded(),
               height: (Double(device.height) * scale + chromeHeight(toolbar: toolbar)).rounded())
    }

    public static func constrainedContentSize(device: CGSize, proposed: CGSize, toolbar: Double = toolbarHeight) -> CGSize {
        let w = max(minimumWidth, Double(proposed.width))
        return contentSize(device: device, scale: scale(device: device, windowWidth: w), toolbar: toolbar)
    }

    public static func deviceRect(device: CGSize, contentWidth width: Double, toolbar: Double = toolbarHeight) -> CGRect {
        let s = scale(device: device, windowWidth: width)
        let w = Double(device.width) * s, h = Double(device.height) * s
        return CGRect(x: (width - w) / 2, y: toolbar + topGap, width: w, height: h)
    }

    public static func rotatedContentSize(oldDevice: CGSize, newDevice: CGSize, contentWidth: Double,
                                          toolbar: Double = toolbarHeight) -> CGSize {
        contentSize(device: newDevice, scale: scale(device: oldDevice, windowWidth: contentWidth), toolbar: toolbar)
    }

    public static func defaultScale(device: CGSize, targetHeight: Double = 510) -> Double {
        guard device.height > 0 else { return 0.5 }
        let byHeight = min(1, targetHeight / Double(max(device.height, device.width * 0.75)))
        return max(byHeight, scale(device: device, windowWidth: minimumWidth))
    }
}
