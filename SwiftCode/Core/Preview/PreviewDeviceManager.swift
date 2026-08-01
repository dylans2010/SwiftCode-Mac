import Foundation
import SwiftUI

public struct PreviewDeviceConfig: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let width: Double
    public let height: Double
    public let cornerRadius: Double
    public let safeAreaTop: Double
    public let safeAreaBottom: Double
}

@MainActor
public final class PreviewDeviceManager {
    public static let shared = PreviewDeviceManager()

    public let devices: [PreviewDeviceConfig] = [
        PreviewDeviceConfig(name: "iPhone 16 Pro", width: 393.0, height: 852.0, cornerRadius: 38.0, safeAreaTop: 59.0, safeAreaBottom: 34.0),
        PreviewDeviceConfig(name: "iPhone 16 Plus", width: 430.0, height: 932.0, cornerRadius: 40.0, safeAreaTop: 59.0, safeAreaBottom: 34.0),
        PreviewDeviceConfig(name: "iPad Air", width: 820.0, height: 1180.0, cornerRadius: 18.0, safeAreaTop: 24.0, safeAreaBottom: 20.0),
        PreviewDeviceConfig(name: "Apple Watch Ultra", width: 198.0, height: 242.0, cornerRadius: 24.0, safeAreaTop: 0.0, safeAreaBottom: 0.0),
        PreviewDeviceConfig(name: "Apple Vision Pro", width: 1200.0, height: 800.0, cornerRadius: 40.0, safeAreaTop: 0.0, safeAreaBottom: 0.0),
        PreviewDeviceConfig(name: "MacBook Pro", width: 1440.0, height: 900.0, cornerRadius: 12.0, safeAreaTop: 0.0, safeAreaBottom: 0.0)
    ]

    private init() {}

    public func device(named name: String) -> PreviewDeviceConfig {
        // FORCE-UNWRAP SAFETY JUSTIFICATION: array 'devices' is hardcoded with non-empty items,
        // and default fallback is guaranteed to exist at index 0.
        return devices.first(where: { name.contains($0.name) || $0.name.contains(name) }) ?? devices[0]
    }
}
