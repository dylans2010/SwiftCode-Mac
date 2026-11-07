#if DEBUG
import Foundation

public struct SDKConfig: Sendable, Codable, Equatable {
    public let sdkVersion: String
    public let apiVersion: String
    public let minimumHostVersion: String
    public let protocolVersion: Int
    public let releaseNotes: [String: String]
    public let updateTimestamp: Date
    public let deprecatedAPIs: [String]

    public init(
        sdkVersion: String,
        apiVersion: String,
        minimumHostVersion: String,
        protocolVersion: Int,
        releaseNotes: [String: String],
        updateTimestamp: Date,
        deprecatedAPIs: [String]
    ) {
        self.sdkVersion = sdkVersion
        self.apiVersion = apiVersion
        self.minimumHostVersion = minimumHostVersion
        self.protocolVersion = protocolVersion
        self.releaseNotes = releaseNotes
        self.updateTimestamp = updateTimestamp
        self.deprecatedAPIs = deprecatedAPIs
    }
}

public enum SDKConfigError: Error, Sendable {
    case missingResource
    case unreadable(Error)
    case decoding(Error)
}

public enum SDKConfigStore {
    public static func load() throws -> SDKConfig {
        guard let url = Bundle.module.url(forResource: "SwiftCodeSDK", withExtension: "json")
                ?? Bundle.main.url(forResource: "SwiftCodeSDK", withExtension: "json") else {
            throw SDKConfigError.missingResource
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SDKConfigError.unreadable(error)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SDKConfig.self, from: data)
        } catch {
            throw SDKConfigError.decoding(error)
        }
    }

    public static func isDeprecated(api: String, in config: SDKConfig) -> Bool {
        config.deprecatedAPIs.contains(api)
    }
}
#endif
