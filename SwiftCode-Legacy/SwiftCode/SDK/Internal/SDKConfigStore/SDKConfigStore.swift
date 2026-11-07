#if DEBUG

import Foundation

public struct SDKConfig: Codable, Sendable {
    public let sdkVersion: String
    public let apiVersion: String
    public let minimumHostVersion: String
    public let protocolVersion: Int
    public let releaseNotes: [String]
    public let updateTimestamp: String
    public let deprecatedAPIs: [String]
}

public enum SDKConfigError: Error, LocalizedError {
    case missingResource
    case unreadable(Error)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .missingResource:
            return "SwiftCodeSDK.json is missing from the app bundle. " +
                "The coordinator must add SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json " +
                "to the SwiftCode target's Copy Bundle Resources build phase."
        case .unreadable(let error):
            return "SwiftCodeSDK.json could not be read: \(error.localizedDescription)"
        case .decoding(let error):
            return "SwiftCodeSDK.json could not be decoded as SDKConfig: \(error.localizedDescription)"
        }
    }
}

public enum SDKConfigStore {
    public static func load() throws -> SDKConfig {
        guard let url = Bundle.main.url(forResource: "SwiftCodeSDK", withExtension: "json") else {
            throw SDKConfigError.missingResource
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SDKConfigError.unreadable(error)
        }
        do {
            return try JSONDecoder().decode(SDKConfig.self, from: data)
        } catch {
            throw SDKConfigError.decoding(error)
        }
    }

    public static func isDeprecated(api: String, in config: SDKConfig) -> Bool {
        config.deprecatedAPIs.contains(api)
    }
}

#endif
