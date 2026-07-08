import SwiftUI

public struct StylingBootstrap {
    public static func initialize() {
        StylingRegistry.shared.registerDefaults()
    }

    public static func configureEnvironment<V: View>(_ view: V) -> some View {
        view
            .environmentObject(AdaptiveLayoutEngine.shared)
    }
}
