// Ported from Legacy `SwiftCode/UI/Styles/Styling/AdaptiveBreakpoints.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> `.background(.thinMaterial, in:
// RoundedRectangle(...))`: no liquidGlass modifier exists in the destination
// (Legacy LiquidGlass.swift is PARTIAL, another scope); this is the destination's
// own card treatment (WorkersMainView.swift precedent).
// Wiring: the app root must inject AdaptiveLayoutEngine.shared as an
// environmentObject (MacDesktopOptimizedModifier reads it) and wrap pages in
// AdaptivePage/AdaptiveDashboardPage/AdaptiveEditorPage/AdaptiveSettingsPage;
// AdaptiveGrid/AdaptiveSplitLayout/AdaptiveSheet are used directly by callers.

import SwiftUI

public enum AdaptiveBreakpoint: String, CaseIterable, Comparable, Sendable {
    case compactDesktop
    case regularDesktop
    case largeDesktop
    case professionalDesktop
    case ultraWideDesktop

    public static func < (lhs: AdaptiveBreakpoint, rhs: AdaptiveBreakpoint) -> Bool {
        let allCases = AdaptiveBreakpoint.allCases
        return allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    public var minWidth: CGFloat {
        switch self {
        case .compactDesktop: return 0
        case .regularDesktop: return 1024
        case .largeDesktop: return 1440
        case .professionalDesktop: return 1920
        case .ultraWideDesktop: return 2560
        }
    }

    public var defaultColumns: Int {
        switch self {
        case .compactDesktop: return 1
        case .regularDesktop: return 2
        case .largeDesktop: return 3
        case .professionalDesktop: return 4
        case .ultraWideDesktop: return 6
        }
    }

    public var standardPadding: CGFloat {
        switch self {
        case .compactDesktop: return 16
        case .regularDesktop: return 20
        case .largeDesktop: return 24
        case .professionalDesktop: return 32
        case .ultraWideDesktop: return 40
        }
    }

    public var standardSpacing: CGFloat {
        switch self {
        case .compactDesktop: return 12
        case .regularDesktop: return 16
        case .largeDesktop: return 20
        case .professionalDesktop: return 24
        case .ultraWideDesktop: return 32
        }
    }

    public static func breakpoint(for width: CGFloat) -> AdaptiveBreakpoint {
        if width >= 2560 { return .ultraWideDesktop }
        if width >= 1920 { return .professionalDesktop }
        if width >= 1440 { return .largeDesktop }
        if width >= 1024 { return .regularDesktop }
        return .compactDesktop
    }
}
