import Foundation

public enum WeatherError: LocalizedError, Sendable {
    case permissionDenied
    case unknown

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Weather data access was denied."
        case .unknown: return "An unknown weather service error occurred."
        }
    }

    public var failureReason: String? {
        switch self {
        case .permissionDenied:
            return "The weather service did not accept the request: the key may be revoked, the token malformed, or the operation not allowed."
        case .unknown:
            return nil
        }
    }

    public var helpAnchor: String? { nil }

    public var recoverySuggestion: String? { nil }
}

enum WeatherUnits {
    static var millimetersPerHour: UnitSpeed {
        UnitSpeed(symbol: "mm/h", converter: UnitConverterLinear(coefficient: 0.001 / 3600))
    }
}
