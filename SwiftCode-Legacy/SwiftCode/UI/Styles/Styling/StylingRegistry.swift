import SwiftUI

public final class StylingRegistry: Sendable {
    public static let shared = StylingRegistry()

    private init() {}

    public func registerDefaults() {
        // Initialization of layout providers, spacing systems, etc.
    }
}
