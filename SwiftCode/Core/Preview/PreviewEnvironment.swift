import SwiftUI

@MainActor
public struct PreviewEnvironmentModifier: ViewModifier {
    let state: PreviewState

    public func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, state.isDarkMode ? .dark : .light)
            .environment(\.dynamicTypeSize, state.dynamicTypeSize)
            .environment(\.locale, Locale(identifier: state.localization))
            .environment(\.layoutDirection, state.layoutDirection)
            .environment(\.displayScale, state.displayScale)
            .environment(\.accessibilityDifferentiateWithoutColor, state.isHighContrast)
            .environment(\.accessibilityBoldText, state.isBoldTextEnabled)
            .environment(\.accessibilityReduceMotion, state.isReduceMotionEnabled)
    }
}

public extension View {
    @MainActor
    func applyPreviewEnvironment(_ state: PreviewState) -> some View {
        self.modifier(PreviewEnvironmentModifier(state: state))
    }
}
