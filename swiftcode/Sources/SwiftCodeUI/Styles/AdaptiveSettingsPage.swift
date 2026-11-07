import SwiftUI

public struct AdaptiveSettingsPage<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        AdaptivePage {
            content
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
