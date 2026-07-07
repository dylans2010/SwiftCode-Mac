import Foundation

public final class ProjectPlistManager {
    public static let shared = ProjectPlistManager()
    private init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = PropertyListDecoder()
        return try decoder.decode(type, from: data)
    }

    public func validate(data: Data) -> Bool {
        do {
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return true
        } catch {
            return false
        }
    }
}
