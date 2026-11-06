import Foundation
import Testing
@testable import YcodePaywall

/// The developer bypass flag round-trips through an isolated
/// UserDefaults suite (the `YcodeCompletionTests` pattern), under
/// Legacy's exact key.
struct PaywallBypassTests {

    @Test("The bypass flag uses Legacy's UserDefaults key")
    func bypassKey() {
        #expect(PaywallBypass.defaultsKey == "bypass_paywall")
    }

    @Test("The bypass flag defaults to off")
    func bypassDefaultsOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "ycode-paywall-\(UUID().uuidString)"))
        let bypass = PaywallBypass(defaults: defaults)
        #expect(!bypass.isEnabled)
    }

    @Test("The bypass flag round-trips and persists across instances")
    func bypassRoundTrips() throws {
        let suite = "ycode-paywall-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let bypass = PaywallBypass(defaults: defaults)
        bypass.isEnabled = true
        #expect(bypass.isEnabled)
        #expect(PaywallBypass(defaults: defaults).isEnabled)
        bypass.isEnabled = false
        #expect(!PaywallBypass(defaults: defaults).isEnabled)
    }
}
