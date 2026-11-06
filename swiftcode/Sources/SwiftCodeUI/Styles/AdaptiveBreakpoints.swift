import SwiftUI

/// Adaptive breakpoints (Legacy
/// `SwiftCode/UI/Styles/Styling/AdaptiveBreakpoints.swift`, Dylan's own
/// code, ported under MIT). Direct port: compact 0 / regular 1024 /
/// large 1440 / professional 1920 / ultra-wide 2560, with per-breakpoint
/// columns (1/2/3/4/6), padding (16/20/24/32/40), and spacing
/// (12/16/20/24/32).

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
