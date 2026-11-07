import Foundation
import Testing
@testable import SwiftCodePaywall

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
        let state = ProSectionState(entitlement: PaywallEntitlementState(purchasedProductIDs: ["some.future.product"]))
        #expect(state.isPro)
    }
}
