import Foundation
import Testing
@testable import SwiftCodeAssistant

@Suite struct GeminiKeyRotationTests {
    static func fakeKey(_ tag: String) -> String {
        "AI" + "za" + tag + String(repeating: "7", count: 28)
    }

    static func manager(store: MemorySecretStore = MemorySecretStore()) -> (GeminiKeyRotationManager, MemorySecretStore) {
        (GeminiKeyRotationManager(store: store), store)
    }

    @Test func maskAndHash() {
        let key = Self.fakeKey("alpha")
        #expect(GeminiKeyRotationManager.maskKey(key) == "AIza••••••••••••7777")
        #expect(GeminiKeyRotationManager.hashKey(key) == GeminiKeyRotationManager.hashKey(key))
        #expect(GeminiKeyRotationManager.hashKey(key) != key)
        #expect(GeminiKeyRotationManager.hashKey(key).count == 64)
        #expect(GeminiKeyRotationManager.hashKey(Self.fakeKey("beta")) != GeminiKeyRotationManager.hashKey(key))
        #expect(GeminiKeyRotationManager.maskKey("short") == "••••••••")
        #expect(GeminiKeyRotationManager.isValidGeminiKey(key) == true)
        #expect(GeminiKeyRotationManager.isValidGeminiKey("too short") == false)
        #expect(GeminiKeyRotationManager.isValidGeminiKey("has space " + String(repeating: "x", count: 20)) == false)
    }

    @Test func importCountsNewDuplicateAndInvalid() async {
        let (rotation, _) = Self.manager()
        let result = await rotation.importKeys([
            Self.fakeKey("alpha"),
            Self.fakeKey("beta"),
            Self.fakeKey("alpha"),
            "bad",
            Self.fakeKey("beta"),
        ].joined(separator: ",\n"))
        #expect(result.totalDetected == 5)
        #expect(result.newKeysAdded == 2)
        #expect(result.duplicatesRemoved == 2)
        #expect(result.invalidKeysRejected == 1)
        #expect(await rotation.keys.count == 2)
        #expect(await rotation.activeKeyId == rotation.keys.first?.id)
        #expect(await rotation.keys.allSatisfy { !$0.maskedValue.contains("7") || $0.maskedValue.hasSuffix("7777") })
        #expect(await rotation.keys.allSatisfy { $0.keyHash.count == 64 })
    }

    @Test func importIgnoresQuotesAndSemicolons() async {
        let (rotation, _) = Self.manager()
        let result = await rotation.importKeys("\"\(Self.fakeKey("alpha"))\"; '\(Self.fakeKey("beta"))'")
        #expect(result.newKeysAdded == 2)
        #expect(result.totalDetected == 2)
    }

    @Test func activeKeyIsReturnedAndMarkedActive() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let first = await rotation.getActiveOrNextKey()
        #expect(first?.key == Self.fakeKey("alpha"))
        #expect(first?.metadata.state == .active)
        #expect(first?.metadata.lastUsed != nil)
        let again = await rotation.getActiveOrNextKey()
        #expect(again?.key == Self.fakeKey("alpha"))
    }

    @Test func selectionPrefersFewestFailuresThenCircularOrder() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys([Self.fakeKey("alpha"), Self.fakeKey("beta"), Self.fakeKey("gamma")].joined(separator: ","))
        let ids = await rotation.keys.map { $0.id }
        await rotation.markFailed(id: ids[1])
        await rotation.markFailed(id: ids[1])
        await rotation.markFailed(id: ids[2])
        let next = await rotation.selectNextAvailableKey(excludingId: ids[0])
        #expect(next?.key == Self.fakeKey("gamma"))
        #expect(await rotation.keys.first { $0.id == ids[0] }?.state == .ready)
        #expect(await rotation.activeKeyId == ids[2])
    }

    @Test func rateLimitCooldownBlocksThenHealthyClears() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let ids = await rotation.keys.map { $0.id }
        await rotation.markRateLimited(id: ids[0], retryAfterSeconds: 3_600)
        #expect(await rotation.keys.first { $0.id == ids[0] }?.isAvailableForUse == false)
        #expect(await rotation.keys.first { $0.id == ids[0] }?.state == .rateLimited)
        #expect(await rotation.selectNextAvailableKey()?.key == Self.fakeKey("beta"))
        await rotation.markHealthy(id: ids[0])
        #expect(await rotation.keys.first { $0.id == ids[0] }?.state == .ready)
        #expect(await rotation.keys.first { $0.id == ids[0] }?.rateLimitedUntil == nil)
        #expect(await rotation.keys.first { $0.id == ids[0] }?.successCount == 1)
    }

    @Test func markFailedPermanentMarksInvalid() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let ids = await rotation.keys.map { $0.id }
        await rotation.markFailed(id: ids[0], isPermanentAuthError: true)
        #expect(await rotation.keys.first { $0.id == ids[0] }?.state == .invalid)
        #expect(await rotation.keys.first { $0.id == ids[0] }?.isAvailableForUse == false)
        #expect(await rotation.selectNextAvailableKey()?.key == Self.fakeKey("beta"))
        await rotation.resetHealth()
        #expect(await rotation.keys.first { $0.id == ids[0] }?.state == .invalid)
    }

    @Test func rotateNowPicksADifferentKey() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let before = await rotation.activeKeyId
        let rotated = await rotation.rotateNow()
        #expect(rotated != nil)
        #expect(rotated?.id != before)
        #expect(await rotation.activeKeyId == rotated?.id)
        let (single, _) = Self.manager()
        _ = await single.importKeys(Self.fakeKey("solo"))
        #expect(await single.rotateNow() == nil)
    }

    @Test func metadataPersistsAcrossInstancesSharingAStore() async {
        let store = MemorySecretStore()
        let first = GeminiKeyRotationManager(store: store)
        _ = await first.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let second = GeminiKeyRotationManager(store: store)
        #expect(await second.keys.count == 2)
        #expect(await second.activeKeyId == first.activeKeyId)
        #expect(await second.getActiveOrNextKey()?.key == Self.fakeKey("alpha"))
    }

    @Test func removeKeyFallsBackToNextAvailable() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let ids = await rotation.keys.map { $0.id }
        await rotation.removeKey(id: ids[0])
        #expect(await rotation.keys.count == 1)
        #expect(await rotation.activeKeyId == ids[1])
        await rotation.removeAllKeys()
        #expect(await rotation.keys.isEmpty)
        #expect(await rotation.activeKeyId == nil)
        #expect(await rotation.getActiveOrNextKey() == nil)
    }

    @Test func reorderKeysTakesOrderedIDs() async {
        let (rotation, _) = Self.manager()
        _ = await rotation.importKeys([Self.fakeKey("alpha"), Self.fakeKey("beta"), Self.fakeKey("gamma")].joined(separator: ","))
        let ids = await rotation.keys.map { $0.id }
        await rotation.reorderKeys([ids[2], ids[0], ids[1]])
        #expect(await rotation.keys.map { $0.id } == [ids[2], ids[0], ids[1]])
        #expect(await rotation.keys.map { $0.orderIndex } == [0, 1, 2])
    }
}
