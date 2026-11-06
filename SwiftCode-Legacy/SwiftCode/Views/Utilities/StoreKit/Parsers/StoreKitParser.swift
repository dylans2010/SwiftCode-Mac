import Foundation

public final class StoreKitParser: Sendable {
    public static let shared = StoreKitParser()

    private init() {}

    public func parse(data: Data) throws -> StoreKitConfig {
        let decoder = JSONDecoder()
        return try decoder.decode(StoreKitConfig.self, from: data)
    }

    public func parse(url: URL) throws -> StoreKitConfig {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    public func parse(jsonString: String) throws -> StoreKitConfig {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "StoreKitParserError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 String"])
        }
        return try parse(data: data)
    }
}
