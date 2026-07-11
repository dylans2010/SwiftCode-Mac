import Foundation

/// Coordinates layout rendering dimensions, viewport matching, and dynamic safe area offsets.
public final class PreviewRenderer: Sendable {
    public static let shared = PreviewRenderer()
    private init() {}

    /// Calculates the correct aspect-fit view dimensions for a device inside a container size.
    public func calculateScaledFrame(
        deviceWidth: Double,
        deviceHeight: Double,
        containerWidth: Double,
        containerHeight: Double,
        zoomScale: Double
    ) -> (width: Double, height: Double, scale: Double) {
        let baseScale = min(containerWidth / deviceWidth, containerHeight / deviceHeight)
        let finalScale = min(baseScale, 1.0) * zoomScale

        return (
            width: deviceWidth * finalScale,
            height: deviceHeight * finalScale,
            scale: finalScale
        )
    }

    /// Resolves the physical device width and height based on the device name and orientation.
    public func resolveDeviceDimensions(name: String, orientation: PreviewConfiguration.DeviceOrientation) -> (width: Double, height: Double) {
        let baseDimensions: (width: Double, height: Double) = {
            switch name.lowercased() {
            case let n where n.contains("se"):
                return (375.0, 667.0)
            case let n where n.contains("pro max"):
                return (440.0, 956.0)
            case let n where n.contains("ipad"):
                return (820.0, 1180.0)
            case let n where n.contains("watch"):
                return (242.0, 280.0)
            case let n where n.contains("vision"):
                return (1280.0, 720.0)
            default:
                // Standard iPhone 16 / Pro dimensions
                return (393.0, 852.0)
            }
        }()

        switch orientation {
        case .portrait, .portraitUpsideDown:
            return baseDimensions
        case .landscapeLeft, .landscapeRight:
            return (width: baseDimensions.height, height: baseDimensions.width)
        }
    }
}
