import Foundation
import CryptoKit

public final class ProjectHashManager: Sendable {
    public static let shared = ProjectHashManager()
    private init() {}

    public func hash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    public func hash512(data: Data) -> String {
        let hash = SHA512.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    public func hashFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return hash(data: data)
    }

    public func compare(data: Data, with hash: String) -> Bool {
        return self.hash(data: data) == hash
    }
}
