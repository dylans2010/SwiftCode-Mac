import Foundation

public struct FeatureFlags: Sendable {
    public static let shared = FeatureFlags()

    public let isProductionReady: Bool = true
    public let allowsSimulatedFailures: Bool = false

    public init() {}
}
