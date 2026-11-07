import Foundation

public final class StoreKitEncoder: Sendable {
    public static let shared = StoreKitEncoder()

    private init() {}

    public func encode(_ config: StoreKitConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    public func encodeToString(_ config: StoreKitConfig) throws -> String {
        let data = try encode(config)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "StoreKitEncoderError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert encoded data to UTF-8 string"])
        }
        return string
    }

    public func encode(to url: URL, config: StoreKitConfig) throws {
        let data = try encode(config)
        try data.write(to: url, options: .atomic)
    }
}
