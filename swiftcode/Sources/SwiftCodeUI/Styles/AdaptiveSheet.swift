import SwiftUI

/// Adaptive sheet (Legacy
/// `SwiftCode/UI/Styles/Styling/AdaptiveSheet.swift`, Dylan's own code,
/// ported under MIT). Direct port: minimum 640×460 with the sheet
/// liquid-glass style, desktop-optimised.

public struct AdaptiveSheet<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(minWidth: 640, minHeight: 460)
            .liquidGlass(style: .sheet, cornerRadius: 16)
            .macDesktopOptimized()
    }
}
