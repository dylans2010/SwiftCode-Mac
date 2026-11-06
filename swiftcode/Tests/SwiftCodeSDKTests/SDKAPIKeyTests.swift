import XCTest
@testable import SwiftCodeSDK

/// HMAC round-trips and key lifecycle. All keys here are TEST-ONLY
/// (fixed test device key, in-memory store). No live network, no real
/// credentials.
final class SDKAPIKeyTests: XCTestCase {
    private func makeStore() -> SDKAPIKeyStore {
        SDKAPIKeyStore(store: MemorySecretStore())
    }

    func testHMACRoundTrip() async throws {
        let store = makeStore()
        let (key, secret) = try await store.createKey(label: "Test key", scopes: [.appsCreate], isLive: false)
        XCTAssertTrue(secret.hasPrefix("sc_dev_test_"))
        let verified = try await store.verify(secret: secret)
        XCTAssertEqual(verified.id, key.id)
        XCTAssertEqual(verified.label, "Test key")
        XCTAssertNotNil(verified.lastUsedAt)
    }

    func testLivePrefix() async throws {
        let store = makeStore()
        let (_, secret) = try await store.createKey(label: "Live", scopes: [.appsCreate], isLive: true)
        XCTAssertTrue(secret.hasPrefix("sc_dev_live_"))
    }

    func testVerifyRejectsTamperedSecret() async throws {
        let store = makeStore()
        let (_, secret) = try await store.createKey(label: "Test", scopes: [.appsCreate], isLive: false)
        let tampered = secret + "x"
        await XCTAssertThrowsErrorAsync(try await store.verify(secret: tampered)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyInvalid)
        }
    }

    func testVerifyRejectsUnknownKey() async throws {
        let store = makeStore()
        // A well-formed secret for a key that was never stored.
        let phantom = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "Phantom", scopes: [.appsCreate])
        let secret = SDKAPIKeyCodec.generateSecret(for: phantom, deviceKey: TestKeys.deviceKey)
        // The store's device key differs from the test key, so the
        // signature fails — still `.apiKeyInvalid`, never a leak.
        await XCTAssertThrowsErrorAsync(try await store.verify(secret: secret)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyInvalid)
        }
    }

    func testRevokeIsIdempotentAndClosesVerification() async throws {
        let store = makeStore()
        let (key, secret) = try await store.createKey(label: "Test", scopes: [.appsCreate], isLive: false)
        _ = try await store.verify(secret: secret)
        await store.revoke(id: key.id)
        await store.revoke(id: key.id)
        await XCTAssertThrowsErrorAsync(try await store.verify(secret: secret)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyRevoked)
        }
    }

    func testExpiredKeyFailsVerification() async throws {
        let store = MemorySecretStore()
        let keyStore = SDKAPIKeyStore(store: store)
        // Persist an already-expired key record directly, with a secret
        // generated from the store's own device key.
        let deviceKey = try await keyStore.getOrCreateDeviceKey()
        let expired = SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix, label: "Expired",
            scopes: [.appsCreate], expiresAt: Date(timeIntervalSinceNow: -60)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try store.write(encoder.encode(expired), account: SDKAPIKeyStore.metadataAccountPrefix + expired.id.uuidString)
        let secret = SDKAPIKeyCodec.generateSecret(for: expired, deviceKey: deviceKey)
        await XCTAssertThrowsErrorAsync(try await keyStore.verify(secret: secret)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyInvalid)
        }
    }

    func testRateLimitLocksOutAfterTenFailures() async throws {
        let store = makeStore()
        for _ in 0..<10 {
            await XCTAssertThrowsErrorAsync(try await store.verify(secret: "garbage")) { error in
                XCTAssertEqual((error as? SDKError)?.code, .apiKeyInvalid)
            }
        }
        await XCTAssertThrowsErrorAsync(try await store.verify(secret: "garbage")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyRateLimited)
        }
    }

    func testCreateKeyValidation() async throws {
        let store = makeStore()
        await XCTAssertThrowsErrorAsync(try await store.createKey(label: "", scopes: [.appsCreate], isLive: false)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
        await XCTAssertThrowsErrorAsync(try await store.createKey(label: "x", scopes: [], isLive: false)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
        await XCTAssertThrowsErrorAsync(
            try await store.createKey(label: "x", scopes: [.appsCreate], isLive: false, expiresAt: Date(timeIntervalSinceNow: -1))
        ) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
    }

    func testEntitlementGrantAndRequire() async throws {
        let store = makeStore()
        let (key, _) = try await store.createKey(label: "Test", scopes: [.appsCreate], isLive: false)
        await XCTAssertThrowsErrorAsync(try await store.requireEntitlement(.developerAIAssist, on: key)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyScopeInsufficient)
        }
        try await store.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        let listed = await store.list()
        XCTAssertTrue(listed.first?.entitlements.contains(.developerAIAssist) == true)
    }

    func testExtractPresentedKeyIDIsUntrusted() {
        let key = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate])
        let secret = SDKAPIKeyCodec.generateSecret(for: key, deviceKey: TestKeys.deviceKey)
        XCTAssertEqual(SDKAPIKeyCodec.extractPresentedKeyID(from: secret), key.id.uuidString)
        XCTAssertNil(SDKAPIKeyCodec.extractPresentedKeyID(from: "not-a-key"))
    }
}

// MARK: - Async XCTAssertThrowsError helper

extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error but got success. \(message())", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
