import SwiftUI

/// Applies a `PreviewState` to a preview as environment (Legacy
/// `SwiftCode/Core/Preview/PreviewEnvironment.swift`, Dylan's own
/// code, ported under MIT).
///
/// Legacy applied only color scheme, dynamic type, locale, layout
/// direction, and display scale. This extends the modifier to the
/// rest of `PreviewState`, which the destination's canvas never
/// applied: high contrast (`.colorSchemeContrast`), bold text
/// (`.legibilityWeight`), reduce motion
/// (`.accessibilityReduceMotion`), custom dimensions (frame), and
/// safe-area insets (`.safeAreaInset`). The state defaults match
/// Legacy's (`localization "en"`, portrait, scale 1, iPhone 16 Pro
/// safe areas).
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
            .environment(\.colorSchemeContrast, state.isHighContrast ? .increased : .standard)
            .environment(\.legibilityWeight, state.isBoldTextEnabled ? .bold : .regular)
            .environment(\.accessibilityReduceMotion, state.isReduceMotionEnabled)
            .frame(width: state.customWidth, height: state.customHeight)
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: state.safeAreaInsets.top) }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: state.safeAreaInsets.bottom) }
    }
}

public extension View {
    @MainActor
    func applyPreviewEnvironment(_ state: PreviewState) -> some View {
        self.modifier(PreviewEnvironmentModifier(state: state))
    }
}
