import Foundation
import Testing
@testable import SwiftCodePaywall

struct PaywallBypassTests {

    @Test("The bypass flag uses Legacy's UserDefaults key")
    func bypassKey() {
        #expect(PaywallBypass.defaultsKey == "bypass_paywall")
    }

    @Test("The bypass flag defaults to off")
    func bypassDefaultsOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "swiftcode-paywall-\(UUID().uuidString)"))
        var bypass = PaywallBypass(defaults: defaults)
        #expect(!bypass.isEnabled)
    }

    @Test("The bypass flag round-trips and persists across instances")
    func bypassRoundTrips() throws {
        let suite = "swiftcode-paywall-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        var bypass = PaywallBypass(defaults: defaults)
        bypass.isEnabled = true
        #expect(bypass.isEnabled)
        #expect(PaywallBypass(defaults: defaults).isEnabled)
        bypass.isEnabled = false
        #expect(!PaywallBypass(defaults: defaults).isEnabled)
    }
}
