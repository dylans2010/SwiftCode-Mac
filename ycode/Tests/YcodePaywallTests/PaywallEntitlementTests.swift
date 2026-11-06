import Foundation
import Testing
@testable import YcodePaywall

/// Entitlement logic against fixtures. This is Legacy's rule exactly:
/// Pro when the verified entitlement set is non-empty or the bypass
/// flag is on, with a debug override winning over both while set.
/// No StoreKit is involved: the state is pure.
struct PaywallEntitlementTests {

    @Test("No entitlements, no bypass, no override is not Pro")
    func emptyIsNotPro() {
        let state = PaywallEntitlementState()
        #expect(!state.isPro)
        #expect(!state.proAccess)
        #expect(state.source == .none)
    }

    @Test("Any catalog entitlement grants Pro")
    func catalogEntitlementIsPro() {
        for id in PaywallProductCatalog.identifiers {
            let state = PaywallEntitlementState(purchasedProductIDs: [id])
            #expect(state.isPro, "Expected \(id) to grant Pro")
            #expect(state.source == .entitlements)
        }
    }

    @Test("Any verified entitlement grants Pro, even an unknown ID — Legacy's rule")
    func unknownEntitlementIsPro() {
        // Legacy tested only that the purchased set was non-empty, so
        // a future App Store Connect product would grant Pro too.
        // This test pins that faithful behaviour; narrowing the gate
        // to catalog IDs would be a product decision, not a port.
        let state = PaywallEntitlementState(purchasedProductIDs: ["swiftcode.pro.future"])
        #expect(state.isPro)
        #expect(state.source == .entitlements)
    }

    @Test("The bypass flag grants Pro with no entitlements")
    func bypassGrantsPro() {
        let state = PaywallEntitlementState(bypassPaywall: true)
        #expect(state.isPro)
        #expect(state.source == .bypassFlag)
    }

    @Test("A debug override granting Pro wins over an empty entitlement set")
    func debugOverrideGrantsPro() {
        let state = PaywallEntitlementState(debugOverride: true)
        #expect(state.isPro)
        #expect(state.source == .debugOverride)
    }

    @Test("A debug override revoking Pro wins over real entitlements")
    func debugOverrideRevokesPro() {
        let state = PaywallEntitlementState(
            purchasedProductIDs: ["swiftcode.pro.lifetime"],
            debugOverride: false
        )
        #expect(!state.isPro)
        #expect(state.source == .debugOverride)
    }

    @Test("Entitlements outrank the bypass flag as the reported source")
    func entitlementsOutrankBypass() {
        let state = PaywallEntitlementState(
            purchasedProductIDs: ["swiftcode.pro.monthly"],
            bypassPaywall: true
        )
        #expect(state.isPro)
        #expect(state.source == .entitlements)
    }

    @Test("resolve matches the struct for every combination")
    func resolveMatchesStruct() {
        let cases: [(Set<String>, Bool, Bool?)] = [
            ([], false, nil),
            (["swiftcode.pro.monthly"], false, nil),
            ([], true, nil),
            ([], false, true),
            (["swiftcode.pro.yearly"], true, false),
            (["swiftcode.pro.lifetime"], false, true),
        ]
        for (purchased, bypass, override) in cases {
            let state = PaywallEntitlementState(
                purchasedProductIDs: purchased,
                bypassPaywall: bypass,
                debugOverride: override
            )
            #expect(
                PaywallEntitlementState.resolve(
                    purchasedProductIDs: purchased,
                    bypassPaywall: bypass,
                    debugOverride: override
                ) == state.isPro
            )
        }
    }
}
