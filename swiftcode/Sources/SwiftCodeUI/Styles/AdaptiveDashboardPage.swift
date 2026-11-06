import SwiftUI

/// Dashboard page (Legacy
/// `SwiftCode/UI/Styles/Styling/AdaptiveDashboardPage.swift`, Dylan's own
/// code, ported under MIT). Direct port: an `AdaptivePage` around a
/// scrolling content view.

public struct AdaptiveDashboardPage<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        AdaptivePage {
            ScrollView {
                content
            }
        }
    }
}
