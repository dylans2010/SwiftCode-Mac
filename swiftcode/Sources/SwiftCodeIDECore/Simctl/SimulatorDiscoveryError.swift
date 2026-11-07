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
