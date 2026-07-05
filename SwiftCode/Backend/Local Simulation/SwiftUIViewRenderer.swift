import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

final class SwiftUIViewRenderer {
    enum Orientation {
        case portrait
        case landscape
    }

    private(set) var device: PreviewDevice = .iPhone15
    private(set) var orientation: Orientation = .portrait

    func configure(device: PreviewDevice, orientation: Orientation) {
        self.device = device
        self.orientation = orientation
    }

    func scaledFrame(in available: CGSize) -> CGSize {
        let base = orientation == .portrait
        ? CGSize(width: device.width, height: device.height)
        : CGSize(width: device.height, height: device.width)

        let horizontalScale = available.width / max(base.width, 1)
        let verticalScale = available.height / max(base.height, 1)
        let scale = min(horizontalScale, verticalScale, 1)

        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    #if canImport(UIKit)
    func hostingController(for loadedView: AnyView) -> UIHostingController<AnyView> {
        UIHostingController(rootView: loadedView)
    }
    #endif
}
