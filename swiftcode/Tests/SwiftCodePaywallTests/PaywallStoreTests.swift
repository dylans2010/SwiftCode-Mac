import Foundation
import Testing
@testable import SwiftCodePaywall

/// The store's debug and bypass behaviour, which needs no live
/// StoreKit. Every test uses `autoStart: false` so no transaction
/// listener and no background product/entitlement load can race the
/// assertions. No live StoreKit transaction or sandbox purchase is
/// ever attempted here.
@MainActor
struct PaywallStoreTests {

    @Test("A fresh store is not Pro")
    func freshStoreIsNotPro() {
        let store = PaywallStore(autoStart: false)
        #expect(!store.isPro)
        #expect(store.offers.isEmpty)
        #expect(store.entitlement.source == .none)
    }

    @Test("The debug override grants and revokes Pro")
    func debugOverrideGrantsAndRevokes() {
        let store = PaywallStore(autoStart: false)
        store.setDebugProAccess(true)
        #expect(store.isPro)
        #expect(store.entitlement.source == .debugOverride)
        store.setDebugProAccess(false)
        #expect(!store.isPro)
        #expect(store.entitlement.source == .debugOverride)
    }

    @Test("Clearing the debug override returns the flag to entitlements")
    func clearDebugOverride() {
        let store = PaywallStore(autoStart: false)
        store.setDebugProAccess(true)
        store.clearDebugOverride()
        #expect(!store.isPro)
        #expect(store.entitlement.source == .none)
    }

    @Test("The store picks up the bypass flag at init")
    func bypassFlagAtInit() throws {
        let defaults = try #require(UserDefaults(suiteName: "swiftcode-paywall-\(UUID().uuidString)"))
        let bypass = PaywallBypass(defaults: defaults)
        bypass.isEnabled = true
        let store = PaywallStore(bypass: bypass, autoStart: false)
        #expect(store.isPro)
        #expect(store.entitlement.source == .bypassFlag)
    }

    @Test("refreshBypassFlag picks up a flag change without a store round-trip")
    func refreshBypassFlag() throws {
        let defaults = try #require(UserDefaults(suiteName: "swiftcode-paywall-\(UUID().uuidString)"))
        let bypass = PaywallBypass(defaults: defaults)
        let store = PaywallStore(bypass: bypass, autoStart: false)
        #expect(!store.isPro)
        bypass.isEnabled = true
        store.refreshBypassFlag()
        #expect(store.isPro)
        #expect(store.entitlement.source == .bypassFlag)
        bypass.isEnabled = false
        store.refreshBypassFlag()
        #expect(!store.isPro)
    }

    #if !canImport(StoreKit)
    @Test("Without StoreKit, loading products fails honestly and offers stay empty")
    func loadProductsWithoutStoreKit() async {
        let store = PaywallStore(autoStart: false)
        await store.loadProducts()
        #expect(store.lastError == .storeKitUnavailable)
        #expect(store.offers.isEmpty)
    }

    @Test("Without StoreKit, a purchase throws instead of faking a transaction")
    func purchaseWithoutStoreKit() async {
        let store = PaywallStore(autoStart: false)
        let offer = PaywallProductOffer(
            productID: "swiftcode.pro.monthly",
            displayName: "Monthly",
            description: "",
            displayPrice: "$4.99",
            price: 4.99
        )
        await #expect(throws: PaywallError.storeKitUnavailable) {
            try await store.purchase(offer)
        }
    }

    @Test("Without StoreKit, restore throws instead of pretending to sync")
    func restoreWithoutStoreKit() async {
        let store = PaywallStore(autoStart: false)
        await #expect(throws: PaywallError.storeKitUnavailable) {
            try await store.restorePurchases()
        }
    }

    @Test("Without StoreKit, a refresh records the missing framework and keeps the debug override")
    func refreshWithoutStoreKitKeepsDebugOverride() async {
        let store = PaywallStore(autoStart: false)
        store.setDebugProAccess(true)
        await store.refreshEntitlements()
        #expect(store.lastError == .storeKitUnavailable)
        #expect(store.isPro)
        #expect(store.entitlement.source == .debugOverride)
    }
    #endif
}
