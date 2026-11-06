// Adapted from SwiftCode-Legacy SwiftCode/Core/Simulator/SimulatorDiscoveryError.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct SimulatorDiscoveryError: Error, Sendable, Identifiable {
    public var id: UUID { uuid }
    private let uuid = UUID()

    public let stage: DiscoveryStage
    public let underlyingMessage: String

    public var localizedDescription: String {
        "Failed at stage '\(stage.rawValue)': \(underlyingMessage)"
    }

    public init(stage: DiscoveryStage, underlyingMessage: String) {
        self.stage = stage
        self.underlyingMessage = underlyingMessage
    }
}
