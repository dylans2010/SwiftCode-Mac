import SwiftUI

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
