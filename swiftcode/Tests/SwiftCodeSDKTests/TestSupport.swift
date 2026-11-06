import Foundation
@testable import SwiftCodeSDK

/// In-memory secret store for tests. No Keychain, no disk, no real
/// secrets — every value here is test-only.
/// Namespaced `SDKMemorySecretStore` (not `MemorySecretStore`): the SDK
/// host's `SDKSecretStoring` seam needs enumeration
/// (`accountNames(withPrefix:)`), which SwiftCodeAssistant's production
/// `MemorySecretStore`/`SecretStore` deliberately does not provide — so
/// this is a separate test helper for a different protocol, not a
/// duplicate of the production type.
final class SDKMemorySecretStore: SDKSecretStoring, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func read(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func write(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = data
    }

    func delete(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }

    func accountNames(withPrefix prefix: String) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}

/// TEST-ONLY device key. Never a real key; used only to exercise the
/// HMAC codec and key store in tests.
enum TestKeys {
    static let deviceKey = Data(repeating: 0x42, count: 32)
}
