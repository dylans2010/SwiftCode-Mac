import SwiftUI

/// Styling registry (Legacy
/// `SwiftCode/UI/Styles/Styling/StylingRegistry.swift`, Dylan's own code,
/// ported under MIT). Direct port; `registerDefaults()` is an empty
/// no-op in Legacy (layout providers / spacing systems are registered
/// by the adaptive types themselves), kept as-is.

public final class StylingRegistry: Sendable {
    public static let shared = StylingRegistry()

    private init() {}

    public func registerDefaults() {
        // Initialization of layout providers, spacing systems, etc.
    }
}
