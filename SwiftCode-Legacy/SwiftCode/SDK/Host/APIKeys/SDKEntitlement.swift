import Foundation

public struct SDKEntitlement: Sendable, Hashable, RawRepresentable, Codable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    public static let developerAIAssist = SDKEntitlement(unchecked: "com.SwiftCode.developer-AI-Assist")

    public static let developerAIAllowsCloud = SDKEntitlement(unchecked: "com.SwiftCode.developer-AI-Allows-Cloud")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let entitlement = SDKEntitlement(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Developer API key entitlement must be a non-empty string."
            )
        }
        self = entitlement
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
