import Foundation
@testable import YcodeSDK

/// In-memory secret store for tests. No Keychain, no disk, no real
/// secrets — every value here is test-only.
final class MemorySecretStore: SDKSecretStoring, @unchecked Sendable {
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
