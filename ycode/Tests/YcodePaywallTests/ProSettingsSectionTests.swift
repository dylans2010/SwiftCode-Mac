import Foundation
import Testing
@testable import YcodePaywall

// MARK: - Settings Pro section (Wave 15)
//
// Pure-state tests only: the entitlement rule is Wave 13's
// `PaywallEntitlementState` (already covered by
// `PaywallEntitlementTests`); this suite covers the section's
// own mapping onto it. No StoreKit, no network, no purchases.

@Suite struct ProSettingsSectionTests {
    @Test func notProShowsUpgrade() {
        let state = ProSectionState(entitlement: PaywallEntitlementState())
        #expect(state.isPro == false)
        #expect(state.source == .none)
        #expect(state.showsUpgradeButton)
        #expect(state.upgradeTitle == "Upgrade to Pro")
        #expect(state.statusText == nil)
    }

    @Test func proViaEntitlementShowsMember() {
        let state = ProSectionState(entitlement: PaywallEntitlementState(purchasedProductIDs: ["swiftcode.pro.yearly"]))
        #expect(state.isPro)
        #expect(state.source == .entitlements)
        #expect(!state.showsUpgradeButton)
        #expect(state.memberTitle == "SwiftCode Pro Member!")
        #expect(state.statusText == "Active")
    }

    @Test func proViaBypassFlagShowsMember() {
        let state = ProSectionState(entitlement: PaywallEntitlementState(bypassPaywall: true))
        #expect(state.isPro)
        #expect(state.source == .bypassFlag)
        #expect(!state.showsUpgradeButton)
        #expect(state.statusText == "Active")
    }

    @Test func debugOverrideShowsMember() {
        let state = ProSectionState(entitlement: PaywallEntitlementState(debugOverride: true))
        #expect(state.isPro)
        #expect(state.source == .debugOverride)
        #expect(!state.showsUpgradeButton)
    }

    @Test func debugOverrideOffShowsUpgrade() {
        let state = ProSectionState(entitlement: PaywallEntitlementState(debugOverride: false))
        #expect(!state.isPro)
        #expect(state.showsUpgradeButton)
    }

    @Test func anyVerifiedEntitlementGrantsPro() {
        // Legacy's faithful quirk, preserved: ANY verified current
        // entitlement grants Pro, not just the three catalog IDs.
        let state = ProSectionState(entitlement: PaywallEntitlementState(purchasedProductIDs: ["some.future.product"]))
        #expect(state.isPro)
    }
}
