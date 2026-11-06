import Foundation
import Observation
import SwiftUI

/// Preview environment state (Legacy
/// `SwiftCode/Core/Preview/PreviewState.swift`, Dylan's own code,
/// ported under MIT). The destination's `PreviewCanvasSettings` had
/// only 6 toggles (Display, Color Scheme, Contrast, Control Borders,
/// Orientation, Dynamic Type); this restores the full set Legacy
/// carried: localization, high contrast, bold text, reduce motion,
/// layout direction, custom width/height, safe-area insets, and
/// display scale. Applied to a view by `applyPreviewEnvironment`
/// (`PreviewEnvironment.swift`).

@Observable
@MainActor
public final class PreviewState {
    public var isDarkMode: Bool = false
    public var dynamicTypeSize: DynamicTypeSize = .medium
    public var localization: String = "en"
    public var isPortrait: Bool = true
    public var scale: Double = 1.0
    public var currentDevice: String = "iPhone 16 Pro"
    public var customWidth: Double? = nil
    public var customHeight: Double? = nil
    public var safeAreaInsets: EdgeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    public var isHighContrast: Bool = false
    public var layoutDirection: LayoutDirection = .leftToRight
    public var displayScale: CGFloat = 2.0
    public var isBoldTextEnabled: Bool = false
    public var isReduceMotionEnabled: Bool = false

    public init() {}
}
