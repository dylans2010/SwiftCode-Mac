import SwiftUI

/// Settings page (Legacy
/// `SwiftCode/UI/Styles/Styling/AdaptiveSettingsPage.swift`, Dylan's own
/// code, ported under MIT). Direct port: content centred at a maximum
/// width of 800 (professional settings density).

public struct AdaptiveSettingsPage<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        AdaptivePage {
            content
                .frame(maxWidth: 800) // Professional settings density
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
