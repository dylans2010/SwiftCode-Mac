import SwiftUI

public struct AdaptiveSheet<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(minWidth: 880, maxWidth: 960, minHeight: 520, maxHeight: 600)
            .macDesktopOptimized()
    }
}
